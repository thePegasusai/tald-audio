// Foundation Latest
import Foundation
// Combine Latest
import Combine

/// Thread-safe ViewModel class managing profile data and operations with enhanced error handling
@MainActor
public final class ProfileViewModel: ObservableObject {
    // MARK: - Published Properties
    
    @Published private(set) var profiles: [Profile] = []
    @Published private(set) var currentProfile: Profile?
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var error: ProfileError?
    @Published private(set) var backupProgress: Double = 0.0
    
    // MARK: - Private Properties
    
    private let profileManager: ProfileManager
    private var cancellables = Set<AnyCancellable>()
    private let profileCache = NSCache<NSString, Profile>()
    private let queue: DispatchQueue
    private let lock = NSLock()
    
    // MARK: - Initialization
    
    public init(profileManager: ProfileManager = .shared) {
        self.profileManager = profileManager
        self.queue = DispatchQueue(label: "com.taldunia.profilevm", qos: .userInitiated)
        
        setupObservers()
        loadProfiles()
    }
    
    // MARK: - Public Methods
    
    /// Loads all profiles with caching support
    public func loadProfiles() {
        Task {
            isLoading = true
            defer { isLoading = false }
            
            do {
                let result = profileManager.getProfiles()
                switch result {
                case .success(let loadedProfiles):
                    await MainActor.run {
                        self.profiles = loadedProfiles
                        cacheProfiles(loadedProfiles)
                    }
                case .failure(let error):
                    await handleError(error)
                }
            } catch {
                await handleError(error)
            }
        }
    }
    
    /// Creates a new profile with validation
    public func createProfile(name: String, preferences: [String: Any]) async -> Result<Profile, ProfileError> {
        isLoading = true
        defer { isLoading = false }
        
        do {
            let result = profileManager.createProfile(
                userId: Configuration.shared.userId,
                name: name,
                preferences: preferences
            )
            
            switch result {
            case .success(let profile):
                await MainActor.run {
                    profiles.append(profile)
                    cacheProfile(profile)
                }
                return .success(profile)
            case .failure(let error):
                await handleError(error)
                return .failure(error)
            }
        } catch {
            await handleError(error)
            return .failure(.invalidProfile(error.localizedDescription))
        }
    }
    
    /// Updates an existing profile
    public func updateProfile(_ profile: Profile) async -> Result<Void, ProfileError> {
        isLoading = true
        defer { isLoading = false }
        
        let result = profileManager.updateProfile(profile)
        switch result {
        case .success:
            await MainActor.run {
                if let index = profiles.firstIndex(where: { $0.id == profile.id }) {
                    profiles[index] = profile
                    cacheProfile(profile)
                }
            }
            return .success(())
        case .failure(let error):
            await handleError(error)
            return .failure(error)
        }
    }
    
    /// Deletes a profile
    public func deleteProfile(_ profile: Profile) async -> Result<Bool, ProfileError> {
        isLoading = true
        defer { isLoading = false }
        
        let result = profileManager.deleteProfile(withId: profile.id)
        switch result {
        case .success(let deleted):
            if deleted {
                await MainActor.run {
                    profiles.removeAll { $0.id == profile.id }
                    clearProfileCache(profile)
                }
            }
            return .success(deleted)
        case .failure(let error):
            await handleError(error)
            return .failure(error)
        }
    }
    
    /// Sets the active profile
    public func setActiveProfile(_ profile: Profile) async -> Result<Void, ProfileError> {
        isLoading = true
        defer { isLoading = false }
        
        let result = profileManager.setActiveProfile(profile)
        switch result {
        case .success:
            await MainActor.run {
                self.currentProfile = profile
            }
            return .success(())
        case .failure(let error):
            await handleError(error)
            return .failure(error)
        }
    }
    
    /// Backs up a profile
    public func backupProfile(_ profile: Profile) async -> Result<URL, ProfileError> {
        isLoading = true
        backupProgress = 0.0
        defer { 
            isLoading = false
            backupProgress = 0.0
        }
        
        do {
            let backupURL = try await performBackup(profile)
            return .success(backupURL)
        } catch let error as ProfileError {
            await handleError(error)
            return .failure(error)
        } catch {
            await handleError(error)
            return .failure(.persistenceError(error.localizedDescription))
        }
    }
    
    // MARK: - Private Methods
    
    private func setupObservers() {
        NotificationCenter.default.publisher(for: .profileDidUpdate)
            .sink { [weak self] notification in
                guard let profile = notification.userInfo?["profile"] as? Profile else { return }
                self?.handleProfileUpdate(profile)
            }
            .store(in: &cancellables)
        
        NotificationCenter.default.publisher(for: .profileDidDelete)
            .sink { [weak self] notification in
                guard let profileId = notification.userInfo?["profileId"] as? UUID else { return }
                self?.handleProfileDeletion(profileId)
            }
            .store(in: &cancellables)
    }
    
    private func cacheProfiles(_ profiles: [Profile]) {
        lock.lock()
        defer { lock.unlock() }
        
        profiles.forEach { profile in
            profileCache.setObject(profile, forKey: profile.id.uuidString as NSString)
        }
    }
    
    private func cacheProfile(_ profile: Profile) {
        lock.lock()
        defer { lock.unlock() }
        
        profileCache.setObject(profile, forKey: profile.id.uuidString as NSString)
    }
    
    private func clearProfileCache(_ profile: Profile) {
        lock.lock()
        defer { lock.unlock() }
        
        profileCache.removeObject(forKey: profile.id.uuidString as NSString)
    }
    
    private func handleProfileUpdate(_ profile: Profile) {
        Task { @MainActor in
            if let index = profiles.firstIndex(where: { $0.id == profile.id }) {
                profiles[index] = profile
                cacheProfile(profile)
            }
        }
    }
    
    private func handleProfileDeletion(_ profileId: UUID) {
        Task { @MainActor in
            profiles.removeAll { $0.id == profileId }
            profileCache.removeObject(forKey: profileId.uuidString as NSString)
        }
    }
    
    private func handleError(_ error: Error) async {
        await MainActor.run {
            self.error = error as? ProfileError ?? .persistenceError(error.localizedDescription)
        }
    }
    
    private func performBackup(_ profile: Profile) async throws -> URL {
        var progress: Double = 0.0
        let progressIncrement = 0.1
        
        return try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    // Simulate backup progress
                    while progress < 1.0 {
                        Thread.sleep(forTimeInterval: 0.1)
                        progress += progressIncrement
                        Task { @MainActor in
                            self.backupProgress = progress
                        }
                    }
                    
                    // Create backup URL in documents directory
                    let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                    let backupURL = documentsURL.appendingPathComponent("profile_\(profile.id).backup")
                    
                    // Encode profile data
                    let encoder = JSONEncoder()
                    let data = try encoder.encode(profile)
                    try data.write(to: backupURL)
                    
                    continuation.resume(returning: backupURL)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}