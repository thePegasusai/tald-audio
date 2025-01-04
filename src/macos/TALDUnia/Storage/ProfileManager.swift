//
// ProfileManager.swift
// TALD UNIA
//
// Thread-safe profile manager with multi-level caching and enhanced validation
// Foundation version: macOS 13.0+
//

import Foundation // macOS 13.0+

// MARK: - Constants
private let DEFAULT_PROFILE_NAME = "Default Profile"
private let MAX_PROFILES = 10
private let PROFILE_CACHE_TTL: TimeInterval = 3600 // 1 hour
private let PROFILE_VERSION = 1
private let CLEANUP_INTERVAL: TimeInterval = 86400 // 24 hours
private let MAX_EXPORT_SIZE = 10 * 1024 * 1024 // 10MB

// MARK: - Profile Statistics
private struct ProfileStatistics {
    var totalProfiles: Int = 0
    var activeProfiles: Int = 0
    var lastModified: Date = Date()
    var averageSettingsSize: Int = 0
    var profileVersions: [Int: Int] = [:]
}

// MARK: - Profile Manager Implementation
@objc public class ProfileManager: NSObject {
    
    // MARK: - Properties
    private static let shared = ProfileManager()
    private var profiles: [UUID: Profile] = [:]
    private let queue = DispatchQueue(label: "com.tald.unia.profile", qos: .userInitiated)
    private let fileManager = FileManager.default
    private let profilesDirectory: URL
    private var cleanupTimer: Timer?
    private var profileStats = ProfileStatistics()
    
    // MARK: - Initialization
    private override init() {
        // Setup profiles directory
        let appSupport = try! fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        profilesDirectory = appSupport.appendingPathComponent("TALDUnia/Profiles", isDirectory: true)
        
        super.init()
        
        // Create profiles directory if needed
        try? fileManager.createDirectory(at: profilesDirectory, withIntermediateDirectories: true)
        
        // Setup cleanup timer
        cleanupTimer = Timer.scheduledTimer(
            withTimeInterval: CLEANUP_INTERVAL,
            repeats: true
        ) { [weak self] _ in
            self?.performCleanup()
        }
        
        // Load existing profiles
        loadProfiles()
        
        // Create default profile if needed
        if profiles.isEmpty {
            try? createDefaultProfile()
        }
    }
    
    // MARK: - Public Interface
    public static func shared() -> ProfileManager {
        return ProfileManager.shared
    }
    
    public func createProfile(
        name: String,
        description: String? = nil,
        settings: AudioSettings? = nil
    ) throws -> Profile {
        return try queue.sync {
            // Check profile limit
            guard profiles.count < MAX_PROFILES else {
                throw TALDError.configurationError(
                    code: "PROFILE_LIMIT_EXCEEDED",
                    message: "Maximum number of profiles (\(MAX_PROFILES)) reached",
                    metadata: ErrorMetadata(
                        timestamp: Date(),
                        component: "ProfileManager",
                        additionalInfo: ["current_count": "\(profiles.count)"]
                    )
                )
            }
            
            // Create and validate new profile
            let profile = Profile(
                name: name,
                description: description,
                audioSettings: settings
            )
            try profile.validateProfile()
            
            // Cache profile
            CacheManager.shared().cacheProfile(
                profile,
                ttl: PROFILE_CACHE_TTL
            )
            
            // Save to disk
            try saveProfile(profile)
            
            // Update statistics
            updateProfileStats(adding: profile)
            
            profiles[profile.id] = profile
            return profile
        }
    }
    
    public func getProfile(_ id: UUID) throws -> Profile {
        return try queue.sync {
            // Check cache first
            if let cached = CacheManager.shared().getProfile(id) {
                return cached
            }
            
            // Get from memory
            guard let profile = profiles[id] else {
                throw TALDError.configurationError(
                    code: "PROFILE_NOT_FOUND",
                    message: "Profile with ID \(id) not found",
                    metadata: ErrorMetadata(
                        timestamp: Date(),
                        component: "ProfileManager",
                        additionalInfo: ["profile_id": id.uuidString]
                    )
                )
            }
            
            // Update cache
            CacheManager.shared().cacheProfile(
                profile,
                ttl: PROFILE_CACHE_TTL
            )
            
            return profile
        }
    }
    
    public func updateProfile(
        _ id: UUID,
        name: String? = nil,
        description: String? = nil,
        settings: AudioSettings? = nil
    ) throws {
        try queue.sync {
            guard var profile = profiles[id] else {
                throw TALDError.configurationError(
                    code: "PROFILE_NOT_FOUND",
                    message: "Profile with ID \(id) not found",
                    metadata: ErrorMetadata(
                        timestamp: Date(),
                        component: "ProfileManager",
                        additionalInfo: ["profile_id": id.uuidString]
                    )
                )
            }
            
            // Update profile
            try profile.update(
                name: name,
                description: description,
                audioSettings: settings
            )
            
            // Validate updated profile
            try profile.validateProfile()
            
            // Update cache and storage
            CacheManager.shared().cacheProfile(
                profile,
                ttl: PROFILE_CACHE_TTL
            )
            try saveProfile(profile)
            
            profiles[id] = profile
            profileStats.lastModified = Date()
        }
    }
    
    public func deleteProfile(_ id: UUID) throws {
        try queue.sync {
            guard let profile = profiles[id], !profile.isDefault else {
                throw TALDError.configurationError(
                    code: "INVALID_PROFILE_DELETE",
                    message: "Cannot delete default or non-existent profile",
                    metadata: ErrorMetadata(
                        timestamp: Date(),
                        component: "ProfileManager",
                        additionalInfo: ["profile_id": id.uuidString]
                    )
                )
            }
            
            // Remove from cache
            CacheManager.shared().invalidateProfile(id)
            
            // Remove from disk
            let profileURL = profilesDirectory.appendingPathComponent("\(id.uuidString).profile")
            try? fileManager.removeItem(at: profileURL)
            
            // Update statistics
            updateProfileStats(removing: profile)
            
            profiles.removeValue(forKey: id)
        }
    }
    
    public func exportProfile(_ id: UUID) throws -> Data {
        return try queue.sync {
            guard let profile = profiles[id] else {
                throw TALDError.configurationError(
                    code: "PROFILE_NOT_FOUND",
                    message: "Profile with ID \(id) not found",
                    metadata: ErrorMetadata(
                        timestamp: Date(),
                        component: "ProfileManager",
                        additionalInfo: ["profile_id": id.uuidString]
                    )
                )
            }
            
            let encoder = JSONEncoder()
            let data = try encoder.encode(profile)
            
            guard data.count <= MAX_EXPORT_SIZE else {
                throw TALDError.configurationError(
                    code: "PROFILE_SIZE_EXCEEDED",
                    message: "Profile export size exceeds maximum allowed",
                    metadata: ErrorMetadata(
                        timestamp: Date(),
                        component: "ProfileManager",
                        additionalInfo: [
                            "profile_id": id.uuidString,
                            "size": "\(data.count)",
                            "max_size": "\(MAX_EXPORT_SIZE)"
                        ]
                    )
                )
            }
            
            return data
        }
    }
    
    // MARK: - Private Helper Methods
    private func createDefaultProfile() throws {
        let defaultSettings = AudioSettings()
        let defaultProfile = try createProfile(
            name: DEFAULT_PROFILE_NAME,
            description: "Default TALD UNIA audio profile",
            settings: defaultSettings
        )
        defaultProfile.isDefault = true
        try saveProfile(defaultProfile)
    }
    
    private func loadProfiles() {
        guard let profileFiles = try? fileManager.contentsOfDirectory(
            at: profilesDirectory,
            includingPropertiesForKeys: nil,
            options: .skipsHiddenFiles
        ) else { return }
        
        for profileURL in profileFiles {
            guard profileURL.pathExtension == "profile",
                  let data = try? Data(contentsOf: profileURL),
                  let profile = try? JSONDecoder().decode(Profile.self, from: data) else {
                continue
            }
            
            // Validate and migrate if needed
            if profile.version < PROFILE_VERSION {
                try? profile.migrate(to: PROFILE_VERSION)
            }
            
            profiles[profile.id] = profile
            updateProfileStats(adding: profile)
        }
    }
    
    private func saveProfile(_ profile: Profile) throws {
        let profileURL = profilesDirectory.appendingPathComponent("\(profile.id.uuidString).profile")
        let data = try JSONEncoder().encode(profile)
        try data.write(to: profileURL, options: .atomic)
    }
    
    private func performCleanup() {
        queue.async { [weak self] in
            guard let self = self else { return }
            
            // Cleanup expired cache entries
            CacheManager.shared().cleanupExpired()
            
            // Update profile statistics
            self.profileStats.totalProfiles = self.profiles.count
            self.profileStats.activeProfiles = self.profiles.values.filter { !$0.isDefault }.count
            
            // Verify profile integrity
            for profile in self.profiles.values {
                try? profile.validateProfile()
            }
        }
    }
    
    private func updateProfileStats(adding profile: Profile) {
        profileStats.totalProfiles += 1
        if !profile.isDefault {
            profileStats.activeProfiles += 1
        }
        profileStats.profileVersions[profile.version, default: 0] += 1
        profileStats.lastModified = Date()
    }
    
    private func updateProfileStats(removing profile: Profile) {
        profileStats.totalProfiles -= 1
        if !profile.isDefault {
            profileStats.activeProfiles -= 1
        }
        profileStats.profileVersions[profile.version, default: 0] -= 1
        profileStats.lastModified = Date()
    }
}