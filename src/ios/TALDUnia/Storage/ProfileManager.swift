// Foundation Latest
import Foundation

/// Thread-safe error types for profile management
public enum ProfileManagerError: Error {
    case invalidProfile(String)
    case profileNotFound(String)
    case persistenceError(String)
    case threadingError(String)
    case cacheError(String)
    case validationError(String)
    case migrationError(String)
}

/// Thread-safe singleton class managing user profiles with comprehensive error handling and cache integration
@objc public final class ProfileManager: NSObject {
    
    // MARK: - Singleton Instance
    
    /// Shared profile manager instance
    @objc public static let shared = ProfileManager()
    
    // MARK: - Private Properties
    
    private let lock = NSLock()
    private var profiles: [Profile]
    private var activeProfile: Profile?
    private let fileManager: FileManager
    private let profilesDirectory: URL
    private let currentSchemaVersion: Int = 1
    
    // MARK: - Initialization
    
    private override init() {
        // Initialize with capacity hint for better performance
        self.profiles = Array(minimumCapacity: 10)
        self.fileManager = FileManager.default
        
        // Set up profiles directory
        let applicationSupport = try! fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        self.profilesDirectory = applicationSupport.appendingPathComponent("Profiles", isDirectory: true)
        
        super.init()
        
        // Create profiles directory if needed
        try? fileManager.createDirectory(
            at: profilesDirectory,
            withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.complete]
        )
        
        // Load saved profiles
        loadProfiles()
        
        // Set up observers
        setupNotificationObservers()
    }
    
    // MARK: - Profile Management
    
    /// Creates a new profile with thread safety and validation
    public func createProfile(userId: String, name: String, preferences: [String: Any]) -> Result<Profile, ProfileManagerError> {
        lock.lock()
        defer { lock.unlock() }
        
        do {
            // Create and validate new profile
            let profile = try Profile(
                userId: userId,
                name: name,
                preferences: preferences
            )
            
            // Check for duplicate profiles
            guard !profiles.contains(where: { $0.userId == userId }) else {
                throw ProfileManagerError.invalidProfile("Profile already exists for user: \(userId)")
            }
            
            // Add to profiles array
            profiles.append(profile)
            
            // Cache profile
            try CacheManager.shared.cacheProfile(profile, policy: .hybrid(memoryTTL: 3600, diskTTL: 86400)).get()
            
            // Persist profile
            try persistProfile(profile)
            
            // Post notification
            NotificationCenter.default.post(
                name: .profileDidCreate,
                object: self,
                userInfo: ["profile": profile]
            )
            
            return .success(profile)
            
        } catch let error as ProfileManagerError {
            return .failure(error)
        } catch {
            return .failure(.persistenceError(error.localizedDescription))
        }
    }
    
    /// Retrieves a profile by ID with cache integration
    public func getProfile(withId id: UUID) -> Result<Profile?, ProfileManagerError> {
        lock.lock()
        defer { lock.unlock() }
        
        // Check cache first
        if let cachedProfile = try? CacheManager.shared.getCachedProfile(withId: id).get() {
            return .success(cachedProfile)
        }
        
        // Check memory array
        if let profile = profiles.first(where: { $0.id == id }) {
            // Update cache
            _ = CacheManager.shared.cacheProfile(profile, policy: .hybrid(memoryTTL: 3600, diskTTL: 86400))
            return .success(profile)
        }
        
        return .success(nil)
    }
    
    /// Updates an existing profile with validation
    public func updateProfile(_ profile: Profile) -> Result<Void, ProfileManagerError> {
        lock.lock()
        defer { lock.unlock() }
        
        do {
            // Find profile index
            guard let index = profiles.firstIndex(where: { $0.id == profile.id }) else {
                throw ProfileManagerError.profileNotFound("Profile not found: \(profile.id)")
            }
            
            // Update profile
            profiles[index] = profile
            
            // Update cache
            try CacheManager.shared.cacheProfile(profile, policy: .hybrid(memoryTTL: 3600, diskTTL: 86400)).get()
            
            // Persist changes
            try persistProfile(profile)
            
            // Post notification
            NotificationCenter.default.post(
                name: .profileDidUpdate,
                object: self,
                userInfo: ["profile": profile]
            )
            
            return .success(())
            
        } catch let error as ProfileManagerError {
            return .failure(error)
        } catch {
            return .failure(.persistenceError(error.localizedDescription))
        }
    }
    
    /// Deletes a profile and its associated data
    public func deleteProfile(withId id: UUID) -> Result<Bool, ProfileManagerError> {
        lock.lock()
        defer { lock.unlock() }
        
        do {
            // Find profile
            guard let index = profiles.firstIndex(where: { $0.id == id }) else {
                return .success(false)
            }
            
            let profile = profiles[index]
            
            // Remove from memory
            profiles.remove(at: index)
            
            // Remove from cache
            CacheManager.shared.clearCache()
            
            // Remove from disk
            let profileURL = profilesDirectory.appendingPathComponent("\(id.uuidString).profile")
            try fileManager.removeItem(at: profileURL)
            
            // Post notification
            NotificationCenter.default.post(
                name: .profileDidDelete,
                object: self,
                userInfo: ["profileId": id]
            )
            
            return .success(true)
            
        } catch {
            return .failure(.persistenceError(error.localizedDescription))
        }
    }
    
    /// Sets the active profile with validation
    public func setActiveProfile(_ profile: Profile) -> Result<Void, ProfileManagerError> {
        lock.lock()
        defer { lock.unlock() }
        
        do {
            // Validate profile exists
            guard profiles.contains(where: { $0.id == profile.id }) else {
                throw ProfileManagerError.profileNotFound("Profile not found: \(profile.id)")
            }
            
            // Update active profile
            activeProfile = profile
            
            // Post notification
            NotificationCenter.default.post(
                name: .activeProfileDidChange,
                object: self,
                userInfo: ["profile": profile]
            )
            
            return .success(())
            
        } catch let error as ProfileManagerError {
            return .failure(error)
        } catch {
            return .failure(.threadingError(error.localizedDescription))
        }
    }
    
    // MARK: - Private Methods
    
    private func loadProfiles() {
        do {
            let profileURLs = try fileManager.contentsOfDirectory(
                at: profilesDirectory,
                includingPropertiesForKeys: nil,
                options: .skipsHiddenFiles
            )
            
            for url in profileURLs {
                guard url.pathExtension == "profile" else { continue }
                
                let data = try Data(contentsOf: url)
                let profile = try JSONDecoder().decode(Profile.self, from: data)
                
                // Validate schema version
                guard profile.schemaVersion <= currentSchemaVersion else {
                    throw ProfileManagerError.migrationError("Unsupported schema version: \(profile.schemaVersion)")
                }
                
                profiles.append(profile)
            }
            
        } catch {
            NotificationCenter.default.post(
                name: .profileLoadingDidFail,
                object: self,
                userInfo: ["error": error]
            )
        }
    }
    
    private func persistProfile(_ profile: Profile) throws {
        let profileURL = profilesDirectory.appendingPathComponent("\(profile.id.uuidString).profile")
        let data = try JSONEncoder().encode(profile)
        try data.write(to: profileURL, options: .completeFileProtection)
    }
    
    private func setupNotificationObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleMemoryWarning),
            name: UIApplication.didReceiveMemoryWarningNotification,
            object: nil
        )
    }
    
    @objc private func handleMemoryWarning() {
        lock.lock()
        defer { lock.unlock() }
        
        // Clear cache except for active profile
        CacheManager.shared.clearCache()
        
        // Cache active profile if exists
        if let activeProfile = activeProfile {
            _ = CacheManager.shared.cacheProfile(activeProfile, policy: .memory)
        }
    }
}

// MARK: - Notification Names

public extension Notification.Name {
    static let profileDidCreate = Notification.Name("TALDUNIAProfileDidCreate")
    static let profileDidUpdate = Notification.Name("TALDUNIAProfileDidUpdate")
    static let profileDidDelete = Notification.Name("TALDUNIAProfileDidDelete")
    static let activeProfileDidChange = Notification.Name("TALDUNIAActiveProfileDidChange")
    static let profileLoadingDidFail = Notification.Name("TALDUNIAProfileLoadingDidFail")
}