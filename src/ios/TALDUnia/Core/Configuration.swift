// Foundation v6.0+, CryptoKit v2.0+
import Foundation
import CryptoKit

/// Runtime environment for the TALD UNIA system
@objc public enum Environment: Int {
    case development
    case staging
    case production
}

/// Current configuration version
public let ConfigurationVersion = "2.0"

/// Thread-safe configuration manager with encryption and validation capabilities
@objc @dynamicMemberLookup public final class Configuration {
    
    // MARK: - Shared Instance
    
    /// Shared configuration instance
    public static let shared = Configuration()
    
    // MARK: - Properties
    
    /// Current runtime environment
    public private(set) var environment: Environment
    
    /// Current configuration version
    public private(set) var configVersion: String
    
    /// Audio processing settings
    private var audioSettings: AudioSettings
    
    /// AI enhancement settings
    private var aiSettings: AISettings
    
    /// Spatial audio settings
    private var spatialSettings: SpatialSettings
    
    /// Network configuration
    private var networkSettings: NetworkSettings
    
    /// Thread synchronization lock
    private let configLock = NSLock()
    
    /// Encryption key for secure storage
    private let encryptionKey: SymmetricKey
    
    // MARK: - Initialization
    
    private init() {
        self.environment = .development
        self.configVersion = ConfigurationVersion
        
        // Initialize encryption key
        let keyData = Data(count: SymmetricKeySize.bits256.rawValue / 8)
        self.encryptionKey = SymmetricKey(data: keyData)
        
        // Initialize default settings
        self.audioSettings = AudioSettings(
            sampleRate: AudioConstants.sampleRate,
            bufferSize: AudioConstants.bufferSize,
            bitDepth: AudioConstants.bitDepth,
            channelCount: AudioConstants.channelCount,
            maxLatency: AudioConstants.maxLatency
        )
        
        self.aiSettings = AISettings(
            modelVersion: AIConstants.modelVersion,
            enhancementLevel: AIConstants.defaultEnhancementLevel,
            inferenceTimeout: AIConstants.inferenceTimeout,
            confidenceThreshold: AIConstants.minimumConfidenceThreshold
        )
        
        self.spatialSettings = SpatialSettings(
            roomSize: SpatialConstants.defaultRoomSize,
            reverbTime: SpatialConstants.defaultReverbTime,
            hrtfResolution: SpatialConstants.hrtfResolution
        )
        
        self.networkSettings = NetworkSettings(
            baseURL: NetworkConstants.baseURL,
            timeoutInterval: NetworkConstants.timeoutInterval,
            maxRetryCount: NetworkConstants.maxRetryCount
        )
        
        // Load saved configuration if available
        loadConfiguration()
        
        // Setup observers
        setupNotificationObservers()
    }
    
    // MARK: - Configuration Loading
    
    /// Loads and validates configuration from storage
    @discardableResult
    public func loadConfiguration(forceMigration: Bool = false) -> Configuration {
        configLock.lock()
        defer { configLock.unlock() }
        
        do {
            // Check for stored configuration
            if let storedData = UserDefaults.standard.data(forKey: "TALDUNIAConfig") {
                let decryptedData = try decrypt(data: storedData)
                let decoder = JSONDecoder()
                let config = try decoder.decode(ConfigurationData.self, from: decryptedData)
                
                // Perform migration if needed
                if forceMigration || config.version != ConfigurationVersion {
                    try migrateConfiguration(from: config.version)
                }
                
                // Update settings
                updateSettings(from: config)
            }
            
            // Validate configuration
            try validate()
            
        } catch {
            // Handle configuration errors
            handleConfigurationError(error)
        }
        
        return self
    }
    
    // MARK: - Configuration Saving
    
    /// Securely saves current configuration
    public func saveConfiguration(createBackup: Bool = true) -> Result<Bool, Error> {
        configLock.lock()
        defer { configLock.unlock() }
        
        do {
            // Validate before saving
            try validate()
            
            // Create configuration data
            let config = ConfigurationData(
                version: configVersion,
                environment: environment,
                audioSettings: audioSettings,
                aiSettings: aiSettings,
                spatialSettings: spatialSettings,
                networkSettings: networkSettings
            )
            
            // Encode and encrypt
            let encoder = JSONEncoder()
            let configData = try encoder.encode(config)
            let encryptedData = try encrypt(data: configData)
            
            // Create backup if requested
            if createBackup {
                UserDefaults.standard.set(
                    UserDefaults.standard.data(forKey: "TALDUNIAConfig"),
                    forKey: "TALDUNIAConfig_backup"
                )
            }
            
            // Save configuration
            UserDefaults.standard.set(encryptedData, forKey: "TALDUNIAConfig")
            
            // Post notification
            NotificationCenter.default.post(
                name: .configurationDidChange,
                object: self
            )
            
            return .success(true)
            
        } catch {
            return .failure(AppError.configurationError(
                reason: "Failed to save configuration: \(error.localizedDescription)",
                context: ErrorContext()
            ))
        }
    }
    
    // MARK: - Configuration Reset
    
    /// Resets configuration to default values
    public func reset() -> Result<Void, Error> {
        configLock.lock()
        defer { configLock.unlock() }
        
        do {
            // Reset to default values
            audioSettings = AudioSettings(
                sampleRate: AudioConstants.sampleRate,
                bufferSize: AudioConstants.bufferSize,
                bitDepth: AudioConstants.bitDepth,
                channelCount: AudioConstants.channelCount,
                maxLatency: AudioConstants.maxLatency
            )
            
            aiSettings = AISettings(
                modelVersion: AIConstants.modelVersion,
                enhancementLevel: AIConstants.defaultEnhancementLevel,
                inferenceTimeout: AIConstants.inferenceTimeout,
                confidenceThreshold: AIConstants.minimumConfidenceThreshold
            )
            
            spatialSettings = SpatialSettings(
                roomSize: SpatialConstants.defaultRoomSize,
                reverbTime: SpatialConstants.defaultReverbTime,
                hrtfResolution: SpatialConstants.hrtfResolution
            )
            
            networkSettings = NetworkSettings(
                baseURL: NetworkConstants.baseURL,
                timeoutInterval: NetworkConstants.timeoutInterval,
                maxRetryCount: NetworkConstants.maxRetryCount
            )
            
            // Validate and save new configuration
            try validate()
            _ = saveConfiguration(createBackup: true)
            
            // Post notification
            NotificationCenter.default.post(
                name: .configurationDidReset,
                object: self
            )
            
            return .success(())
            
        } catch {
            return .failure(AppError.configurationError(
                reason: "Failed to reset configuration: \(error.localizedDescription)",
                context: ErrorContext()
            ))
        }
    }
    
    // MARK: - Validation
    
    /// Validates all configuration values
    public func validate() throws {
        // Validate audio settings
        guard audioSettings.sampleRate >= 44100,
              audioSettings.bufferSize > 0,
              audioSettings.bitDepth > 0,
              audioSettings.channelCount > 0,
              audioSettings.maxLatency > 0 else {
            throw AppError.invalidConfiguration(
                key: "audioSettings",
                context: ErrorContext()
            )
        }
        
        // Validate AI settings
        guard aiSettings.enhancementLevel >= 0 && aiSettings.enhancementLevel <= 1,
              aiSettings.confidenceThreshold >= 0 && aiSettings.confidenceThreshold <= 1,
              aiSettings.inferenceTimeout > 0 else {
            throw AppError.invalidConfiguration(
                key: "aiSettings",
                context: ErrorContext()
            )
        }
        
        // Validate spatial settings
        guard spatialSettings.roomSize > 0 && spatialSettings.roomSize <= SpatialConstants.maxRoomSize,
              spatialSettings.reverbTime > 0,
              spatialSettings.hrtfResolution > 0 else {
            throw AppError.invalidConfiguration(
                key: "spatialSettings",
                context: ErrorContext()
            )
        }
        
        // Validate network settings
        guard !networkSettings.baseURL.isEmpty,
              networkSettings.timeoutInterval > 0,
              networkSettings.maxRetryCount > 0 else {
            throw AppError.invalidConfiguration(
                key: "networkSettings",
                context: ErrorContext()
            )
        }
    }
    
    // MARK: - Private Methods
    
    private func encrypt(data: Data) throws -> Data {
        let sealedBox = try AES.GCM.seal(data, using: encryptionKey)
        return sealedBox.combined ?? Data()
    }
    
    private func decrypt(data: Data) throws -> Data {
        let sealedBox = try AES.GCM.SealedBox(combined: data)
        return try AES.GCM.open(sealedBox, using: encryptionKey)
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
        // Clear any cached configuration data
    }
    
    private func handleConfigurationError(_ error: Error) {
        NotificationCenter.default.post(
            name: .configurationDidFail,
            object: self,
            userInfo: ["error": error]
        )
    }
}

// MARK: - Notification Names

public extension Notification.Name {
    static let configurationDidChange = Notification.Name("TALDUNIAConfigurationDidChange")
    static let configurationDidReset = Notification.Name("TALDUNIAConfigurationDidReset")
    static let configurationDidFail = Notification.Name("TALDUNIAConfigurationDidFail")
}