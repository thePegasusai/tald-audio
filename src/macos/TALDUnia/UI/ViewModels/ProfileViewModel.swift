//
// ProfileViewModel.swift
// TALD UNIA
//
// ViewModel for managing user audio profiles with power optimization and version control
// SwiftUI version: macOS 13.0+
//

import SwiftUI // macOS 13.0+
import Combine // macOS 13.0+

// MARK: - Constants
private let PROFILE_UPDATE_DEBOUNCE: TimeInterval = 0.5
private let PROFILE_VERSION: Int = 1
private let PROFILE_CACHE_DURATION: TimeInterval = 300
private let MAX_PROFILES: Int = 10

// MARK: - Profile Statistics
public struct ProfileStatistics {
    var totalProfiles: Int = 0
    var activeProfiles: Int = 0
    var lastModified: Date = Date()
    var averageQuality: Float = 0.0
    var powerOptimizedCount: Int = 0
}

// MARK: - ProfileViewModel Implementation
@MainActor
public class ProfileViewModel: ObservableObject {
    
    // MARK: - Published Properties
    @Published private(set) var profiles: [Profile] = []
    @Published var activeProfile: Profile?
    @Published var isLoading: Bool = false
    @Published var error: TALDError?
    @Published var profileStats: ProfileStatistics = ProfileStatistics()
    
    // MARK: - Private Properties
    private let profileManager: ProfileManager
    private var cancellables = Set<AnyCancellable>()
    private let serialQueue = DispatchQueue(label: "com.tald.unia.profilevm", qos: .userInitiated)
    private let profileCache = NSCache<NSString, Profile>()
    private var updateDebouncer: AnyCancellable?
    private var powerMonitor = ProcessInfo.processInfo
    
    // MARK: - Initialization
    public init() {
        self.profileManager = ProfileManager.shared()
        
        // Configure cache
        profileCache.countLimit = MAX_PROFILES
        
        // Setup observers
        setupObservers()
        
        // Load initial profiles
        Task {
            await loadProfiles()
        }
    }
    
    // MARK: - Public Interface
    
    /// Loads all available profiles with caching support
    public func loadProfiles() async {
        isLoading = true
        error = nil
        
        do {
            let loadedProfiles = try await serialQueue.sync { () -> [Profile] in
                let profiles = try profileManager.getAllProfiles()
                
                // Validate and cache profiles
                return try profiles.compactMap { profile in
                    try profile.validateProfile()
                    profileCache.setObject(profile, forKey: profile.id.uuidString as NSString)
                    return profile
                }
            }
            
            profiles = loadedProfiles
            updateProfileStatistics()
            
            // Set default active profile if none selected
            if activeProfile == nil {
                activeProfile = profiles.first(where: { $0.isDefault })
            }
            
        } catch {
            self.error = error as? TALDError ?? TALDError.configurationError(
                code: "PROFILE_LOAD_ERROR",
                message: "Failed to load profiles",
                metadata: ErrorMetadata(
                    timestamp: Date(),
                    component: "ProfileViewModel",
                    additionalInfo: ["error": error.localizedDescription]
                )
            )
        }
        
        isLoading = false
    }
    
    /// Creates a new audio profile with validation
    public func createProfile(
        name: String,
        description: String? = nil,
        settings: AudioSettings? = nil
    ) async throws {
        guard profiles.count < MAX_PROFILES else {
            throw TALDError.configurationError(
                code: "MAX_PROFILES_EXCEEDED",
                message: "Maximum number of profiles reached",
                metadata: ErrorMetadata(
                    timestamp: Date(),
                    component: "ProfileViewModel",
                    additionalInfo: ["current_count": String(profiles.count)]
                )
            )
        }
        
        let newProfile = try await serialQueue.sync { () -> Profile in
            let profile = try profileManager.createProfile(
                name: name,
                description: description,
                settings: settings
            )
            
            // Cache the new profile
            profileCache.setObject(profile, forKey: profile.id.uuidString as NSString)
            return profile
        }
        
        profiles.append(newProfile)
        updateProfileStatistics()
    }
    
    /// Updates an existing profile with power-aware validation
    public func updateProfile(
        _ profile: Profile,
        name: String? = nil,
        description: String? = nil,
        settings: AudioSettings? = nil
    ) async throws {
        guard let index = profiles.firstIndex(where: { $0.id == profile.id }) else {
            throw TALDError.configurationError(
                code: "PROFILE_NOT_FOUND",
                message: "Profile not found for update",
                metadata: ErrorMetadata(
                    timestamp: Date(),
                    component: "ProfileViewModel",
                    additionalInfo: ["profile_id": profile.id.uuidString]
                )
            )
        }
        
        // Debounce updates to prevent excessive processing
        updateDebouncer?.cancel()
        updateDebouncer = Just(())
            .delay(for: .seconds(PROFILE_UPDATE_DEBOUNCE), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                Task { [weak self] in
                    try await self?.performProfileUpdate(
                        profile,
                        name: name,
                        description: description,
                        settings: settings
                    )
                }
            }
    }
    
    /// Deletes a profile with validation
    public func deleteProfile(_ profile: Profile) async throws {
        guard !profile.isDefault else {
            throw TALDError.configurationError(
                code: "CANNOT_DELETE_DEFAULT",
                message: "Cannot delete default profile",
                metadata: ErrorMetadata(
                    timestamp: Date(),
                    component: "ProfileViewModel",
                    additionalInfo: ["profile_id": profile.id.uuidString]
                )
            )
        }
        
        try await serialQueue.sync {
            try profileManager.deleteProfile(profile.id)
            profileCache.removeObject(forKey: profile.id.uuidString as NSString)
        }
        
        profiles.removeAll(where: { $0.id == profile.id })
        if activeProfile?.id == profile.id {
            activeProfile = profiles.first(where: { $0.isDefault })
        }
        
        updateProfileStatistics()
    }
    
    /// Sets the active profile with power optimization
    public func setActiveProfile(_ profile: Profile) async throws {
        guard profiles.contains(where: { $0.id == profile.id }) else {
            throw TALDError.configurationError(
                code: "INVALID_PROFILE",
                message: "Selected profile is not available",
                metadata: ErrorMetadata(
                    timestamp: Date(),
                    component: "ProfileViewModel",
                    additionalInfo: ["profile_id": profile.id.uuidString]
                )
            )
        }
        
        // Validate profile before activation
        try await serialQueue.sync {
            try profile.validateProfile()
        }
        
        // Adjust power settings if needed
        if powerMonitor.isLowPowerModeEnabled && profile.powerOptimizationEnabled {
            try await optimizeProfileForPower(profile)
        }
        
        activeProfile = profile
    }
    
    /// Exports a profile to data
    public func exportProfile(_ profile: Profile) async throws -> Data {
        return try await serialQueue.sync {
            try profileManager.exportProfile(profile.id)
        }
    }
    
    /// Imports a profile from data
    public func importProfile(from data: Data) async throws {
        let importedProfile = try await serialQueue.sync { () -> Profile in
            try profileManager.importProfile(from: data)
        }
        
        profiles.append(importedProfile)
        updateProfileStatistics()
    }
    
    // MARK: - Private Helper Methods
    
    private func setupObservers() {
        // Observe power state changes
        NotificationCenter.default.publisher(for: NSProcessInfo.powerStateDidChangeNotification)
            .sink { [weak self] _ in
                Task { [weak self] in
                    await self?.handlePowerStateChange()
                }
            }
            .store(in: &cancellables)
    }
    
    private func performProfileUpdate(
        _ profile: Profile,
        name: String?,
        description: String?,
        settings: AudioSettings?
    ) async throws {
        try await serialQueue.sync {
            try profileManager.updateProfile(
                profile.id,
                name: name,
                description: description,
                settings: settings
            )
            
            if let updatedProfile = try? profileManager.getProfile(profile.id) {
                profileCache.setObject(updatedProfile, forKey: profile.id.uuidString as NSString)
                if let index = profiles.firstIndex(where: { $0.id == profile.id }) {
                    profiles[index] = updatedProfile
                }
                if activeProfile?.id == profile.id {
                    activeProfile = updatedProfile
                }
            }
        }
        
        updateProfileStatistics()
    }
    
    private func optimizeProfileForPower(_ profile: Profile) async throws {
        var settings = profile.audioSettings
        settings.powerOptimizationSettings["efficiencyTarget"] = Float(AudioConstants.AMPLIFIER_EFFICIENCY)
        settings.powerOptimizationSettings["powerMode"] = 0.0 // Power saver mode
        
        try await updateProfile(
            profile,
            settings: settings
        )
    }
    
    private func updateProfileStatistics() {
        profileStats.totalProfiles = profiles.count
        profileStats.activeProfiles = profiles.filter({ !$0.isDefault }).count
        profileStats.lastModified = Date()
        profileStats.powerOptimizedCount = profiles.filter({ $0.powerOptimizationEnabled }).count
        profileStats.averageQuality = profiles.reduce(0) { $0 + $1.enhancementQuality } / Float(profiles.count)
    }
    
    private func handlePowerStateChange() async {
        if powerMonitor.isLowPowerModeEnabled {
            // Optimize active profile for power efficiency
            if let activeProfile = activeProfile {
                try? await optimizeProfileForPower(activeProfile)
            }
            
            // Reduce cache size
            profileCache.countLimit = MAX_PROFILES / 2
        } else {
            profileCache.countLimit = MAX_PROFILES
        }
    }
}