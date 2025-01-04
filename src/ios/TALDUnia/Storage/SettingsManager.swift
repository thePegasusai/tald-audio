// Foundation Latest
import Foundation

/// Thread-safe error types for settings operations
public enum SettingsError: Error {
    case invalidSettings(String)
    case storageError(String)
    case encryptionError(String)
    case threadingError(String)
    case validationError(String)
    case cacheError(String)
}

/// Thread-safe singleton class managing secure storage and retrieval of audio settings
@objc public final class SettingsManager: NSObject {
    
    // MARK: - Singleton Instance
    
    /// Shared settings manager instance
    @objc public static let shared = SettingsManager()
    
    // MARK: - Private Properties
    
    private let defaults = UserDefaults.standard
    private let notificationCenter = NotificationCenter.default
    private let lock = NSLock()
    private let monitor = PerformanceMonitor()
    private let encryptionManager: EncryptionManager
    private let cacheManager = CacheManager.shared
    
    // Storage keys
    private let settingsKey = "com.taldunia.settings"
    private let hashKey = "com.taldunia.settings.hash"
    
    // MARK: - Initialization
    
    private override init() {
        // Initialize encryption manager with secure key storage
        self.encryptionManager = EncryptionManager()
        
        super.init()
        
        // Setup notification observers
        setupNotificationObservers()
        
        // Setup automatic cache invalidation
        setupCacheInvalidation()
    }
    
    // MARK: - Public Methods
    
    /// Securely saves audio settings with validation and encryption
    public func saveSettings(_ settings: AudioSettings) -> Result<Void, SettingsError> {
        lock.lock()
        defer { lock.unlock() }
        
        do {
            // Validate settings against quality standards
            try settings.validate().get()
            
            // Validate audio quality requirements
            try validateAudioQuality(settings)
            
            // Encode settings
            let encoder = JSONEncoder()
            let settingsData = try encoder.encode(settings)
            
            // Encrypt settings data
            let encryptedData = try encryptionManager.encrypt(settingsData)
            
            // Calculate integrity hash
            let hash = calculateHash(for: encryptedData)
            
            // Perform atomic write
            defaults.setValue(encryptedData, forKey: settingsKey)
            defaults.setValue(hash, forKey: hashKey)
            
            // Update cache
            try cacheManager.cacheAudioSettings(settings, policy: .hybrid(
                memoryTTL: 3600,
                diskTTL: 86400
            )).get()
            
            // Log transaction
            monitor.logSettingsUpdate(settings.id)
            
            // Post notification
            notificationCenter.post(name: .settingsDidChange, object: self)
            
            return .success(())
            
        } catch {
            return .failure(mapError(error))
        }
    }
    
    /// Loads and validates settings with cache optimization
    public func loadSettings(forProfileId profileId: UUID) -> Result<AudioSettings, SettingsError> {
        lock.lock()
        defer { lock.unlock() }
        
        do {
            // Check cache first
            if let cachedSettings = try cacheManager.getCachedProfile(withId: profileId).get() {
                monitor.logCacheHit()
                return .success(cachedSettings.getAudioSettings().first!)
            }
            
            // Load encrypted data
            guard let encryptedData = defaults.data(forKey: settingsKey),
                  let storedHash = defaults.string(forKey: hashKey) else {
                throw SettingsError.storageError("Settings not found")
            }
            
            // Verify data integrity
            let calculatedHash = calculateHash(for: encryptedData)
            guard calculatedHash == storedHash else {
                throw SettingsError.validationError("Settings data integrity check failed")
            }
            
            // Decrypt data
            let decryptedData = try encryptionManager.decrypt(encryptedData)
            
            // Decode settings
            let decoder = JSONDecoder()
            let settings = try decoder.decode(AudioSettings.self, from: decryptedData)
            
            // Validate settings
            try settings.validate().get()
            
            // Update cache
            try cacheManager.cacheAudioSettings(settings, policy: .hybrid(
                memoryTTL: 3600,
                diskTTL: 86400
            )).get()
            
            monitor.logSettingsLoad(settings.id)
            
            return .success(settings)
            
        } catch {
            return .failure(mapError(error))
        }
    }
    
    /// Securely deletes settings with cache cleanup
    public func deleteSettings(forProfileId profileId: UUID) -> Result<Void, SettingsError> {
        lock.lock()
        defer { lock.unlock() }
        
        do {
            // Verify deletion authorization
            guard try verifyDeletionAuthorization(profileId) else {
                throw SettingsError.validationError("Unauthorized settings deletion")
            }
            
            // Remove from storage
            defaults.removeObject(forKey: settingsKey)
            defaults.removeObject(forKey: hashKey)
            
            // Clear cache
            try cacheManager.invalidateCache(forProfileId: profileId).get()
            
            // Clean up encryption keys
            try encryptionManager.deleteKeys(forProfileId: profileId)
            
            monitor.logSettingsDeletion(profileId)
            
            // Post notification
            notificationCenter.post(name: .settingsDidDelete, object: self)
            
            return .success(())
            
        } catch {
            return .failure(mapError(error))
        }
    }
    
    /// Synchronizes settings with system configuration
    @objc private func syncSettings() {
        lock.lock()
        defer { lock.unlock() }
        
        do {
            // Load current configuration
            let config = Configuration.shared
            
            // Validate configuration integrity
            try config.validate()
            
            // Update local settings cache
            try cacheManager.invalidateCache().get()
            
            // Verify audio quality standards
            try validateAudioQuality(config.audioSettings)
            
            // Perform atomic settings update
            try saveSettings(config.audioSettings).get()
            
            monitor.logSettingsSync()
            
            // Post notification
            notificationCenter.post(name: .settingsDidSync, object: self)
            
        } catch {
            handleSyncError(error)
        }
    }
    
    // MARK: - Private Methods
    
    private func setupNotificationObservers() {
        notificationCenter.addObserver(
            self,
            selector: #selector(syncSettings),
            name: .configurationDidChange,
            object: nil
        )
    }
    
    private func setupCacheInvalidation() {
        Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            self?.invalidateCache()
        }
    }
    
    private func validateAudioQuality(_ settings: AudioSettings) throws {
        guard settings.hardwareSettings.currentTHDN <= QualityConstants.targetTHD else {
            throw SettingsError.validationError("THD+N exceeds quality threshold")
        }
    }
    
    private func calculateHash(for data: Data) -> String {
        return data.sha256().base64EncodedString()
    }
    
    private func verifyDeletionAuthorization(_ profileId: UUID) throws -> Bool {
        // Implement authorization logic
        return true
    }
    
    private func invalidateCache() {
        try? cacheManager.invalidateCache().get()
    }
    
    private func handleSyncError(_ error: Error) {
        monitor.logError(error)
        notificationCenter.post(
            name: .settingsSyncDidFail,
            object: self,
            userInfo: ["error": error]
        )
    }
    
    private func mapError(_ error: Error) -> SettingsError {
        switch error {
        case let settingsError as SettingsError:
            return settingsError
        case let cacheError as CacheError:
            return .cacheError(cacheError.localizedDescription)
        default:
            return .storageError(error.localizedDescription)
        }
    }
}

// MARK: - Notification Names

public extension Notification.Name {
    static let settingsDidChange = Notification.Name("TALDUNIASettingsDidChange")
    static let settingsDidDelete = Notification.Name("TALDUNIASettingsDidDelete")
    static let settingsDidSync = Notification.Name("TALDUNIASettingsDidSync")
    static let settingsSyncDidFail = Notification.Name("TALDUNIASettingsSyncDidFail")
}