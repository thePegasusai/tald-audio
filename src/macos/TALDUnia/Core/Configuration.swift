//
// Configuration.swift
// TALD UNIA
//
// Core configuration management for TALD UNIA audio system
// Version: 2.0.0
//

import Foundation // macOS 13.0+

// MARK: - Configuration Constants
private let CONFIG_FILE_NAME: String = "tald_config.json"
private let DEFAULT_CONFIG_PATH: String = "~/Library/Application Support/TALDUnia/"
private let CONFIG_VERSION: String = "2.0.0"

// MARK: - Configuration Types
/// Audio configuration structure
public struct AudioConfig: Codable {
    var sampleRate: Int = AudioConstants.SAMPLE_RATE
    var bitDepth: Int = AudioConstants.BIT_DEPTH
    var bufferSize: Int = AudioConstants.BUFFER_SIZE
    var thdnThreshold: Double = AudioConstants.THD_N_THRESHOLD
    var targetLatency: Double = AudioConstants.TARGET_LATENCY
    var amplifierEfficiency: Double = AudioConstants.AMPLIFIER_EFFICIENCY
}

/// AI processing configuration
public struct AIConfig: Codable {
    var modelVersion: String = AIConstants.MODEL_VERSION
    var batchSize: Int = AIConstants.INFERENCE_BATCH_SIZE
    var enhancementThreshold: Float = AIConstants.ENHANCEMENT_THRESHOLD
    var maxProcessingTime: TimeInterval = AIConstants.MAX_PROCESSING_TIME
}

/// Spatial audio configuration
public struct SpatialConfig: Codable {
    var hrtfVersion: String = SpatialConstants.HRTF_VERSION
    var roomModelVersion: String = SpatialConstants.ROOM_MODEL_VERSION
    var headTrackingUpdateRate: Double = SpatialConstants.HEAD_TRACKING_UPDATE_RATE
    var spatialResolution: Double = SpatialConstants.SPATIAL_RESOLUTION
}

/// Network configuration
public struct NetworkConfig: Codable {
    var apiVersion: String = NetworkConstants.API_VERSION
    var websocketProtocol: String = NetworkConstants.WEBSOCKET_PROTOCOL
    var timeoutInterval: TimeInterval = NetworkConstants.TIMEOUT_INTERVAL
    var maxRetryAttempts: Int = NetworkConstants.MAX_RETRY_ATTEMPTS
}

/// Logging configuration
public struct LogConfig: Codable {
    var enabled: Bool = true
    var level: String = "info"
    var maxFileSize: Int = 10_485_760 // 10MB
    var maxFileCount: Int = 5
}

/// Power management configuration
public struct PowerConfig: Codable {
    var powerSavingEnabled: Bool = true
    var idleTimeout: TimeInterval = 300 // 5 minutes
    var processingPriority: Int = 4 // 0-9 scale
}

// MARK: - Configuration Manager
@MainActor
public final class Configuration {
    // MARK: - Singleton Instance
    public static let shared = Configuration()
    
    // MARK: - Properties
    private let configurationQueue = DispatchQueue(label: "com.tald.unia.configuration", qos: .userInitiated)
    private let configurationLock = NSLock()
    
    public private(set) var audioConfig: AudioConfig
    public private(set) var aiConfig: AIConfig
    public private(set) var spatialConfig: SpatialConfig
    public private(set) var networkConfig: NetworkConfig
    public private(set) var logConfig: LogConfig
    public private(set) var powerConfig: PowerConfig
    public private(set) var version: String
    
    private var observers: [NSObjectProtocol] = []
    private var backupManager: ConfigurationBackupManager?
    
    // MARK: - Initialization
    private init() {
        // Initialize with default values
        self.audioConfig = AudioConfig()
        self.aiConfig = AIConfig()
        self.spatialConfig = SpatialConfig()
        self.networkConfig = NetworkConfig()
        self.logConfig = LogConfig()
        self.powerConfig = PowerConfig()
        self.version = CONFIG_VERSION
        
        // Setup configuration
        setupConfiguration()
    }
    
    deinit {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
    }
    
    // MARK: - Configuration Setup
    private func setupConfiguration() {
        configurationQueue.async { [weak self] in
            guard let self = self else { return }
            
            // Initialize backup manager
            self.backupManager = ConfigurationBackupManager()
            
            // Load configuration
            switch self.loadConfiguration() {
            case .success(let config):
                self.updateConfiguration(config)
            case .failure(let error):
                self.handleConfigurationError(error)
            }
            
            // Setup observers
            self.setupObservers()
        }
    }
    
    // MARK: - Configuration Loading
    private func loadConfiguration() -> Result<Configuration, TALDError> {
        configurationLock.lock()
        defer { configurationLock.unlock() }
        
        let fileManager = FileManager.default
        let configPath = (DEFAULT_CONFIG_PATH as NSString).expandingTildeInPath
        let configURL = URL(fileURLWithPath: configPath).appendingPathComponent(CONFIG_FILE_NAME)
        
        // Check if configuration exists
        guard fileManager.fileExists(atPath: configURL.path) else {
            return createDefaultConfiguration()
        }
        
        do {
            let data = try Data(contentsOf: configURL)
            let decoder = JSONDecoder()
            let config = try decoder.decode(Configuration.self, from: data)
            
            // Validate version and migrate if needed
            if config.version != CONFIG_VERSION {
                return migrateConfiguration(config)
            }
            
            return .success(config)
        } catch {
            let metadata = ErrorMetadata(
                timestamp: Date(),
                component: "Configuration",
                additionalInfo: ["path": configURL.path]
            )
            return .failure(.configurationError(
                code: "LOAD_FAILED",
                message: "Failed to load configuration: \(error.localizedDescription)",
                metadata: metadata
            ))
        }
    }
    
    // MARK: - Configuration Saving
    private func saveConfiguration() -> Result<Void, TALDError> {
        configurationLock.lock()
        defer { configurationLock.unlock() }
        
        do {
            // Create backup before saving
            try backupManager?.createBackup()
            
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(self)
            
            let configPath = (DEFAULT_CONFIG_PATH as NSString).expandingTildeInPath
            let fileManager = FileManager.default
            
            // Create directory if needed
            try fileManager.createDirectory(
                atPath: configPath,
                withIntermediateDirectories: true,
                attributes: nil
            )
            
            let configURL = URL(fileURLWithPath: configPath).appendingPathComponent(CONFIG_FILE_NAME)
            try data.write(to: configURL, options: .atomic)
            
            return .success(())
        } catch {
            let metadata = ErrorMetadata(
                timestamp: Date(),
                component: "Configuration",
                additionalInfo: ["operation": "save"]
            )
            return .failure(.configurationError(
                code: "SAVE_FAILED",
                message: "Failed to save configuration: \(error.localizedDescription)",
                metadata: metadata
            ))
        }
    }
    
    // MARK: - Configuration Updates
    public func updateAudioConfig(_ config: AudioConfig) -> Result<Void, TALDError> {
        configurationLock.lock()
        defer { configurationLock.unlock() }
        
        // Validate new configuration
        guard validateAudioConfig(config) else {
            let metadata = ErrorMetadata(
                timestamp: Date(),
                component: "AudioConfig",
                additionalInfo: ["sampleRate": "\(config.sampleRate)"]
            )
            return .failure(.configurationError(
                code: "INVALID_AUDIO_CONFIG",
                message: "Invalid audio configuration parameters",
                metadata: metadata
            ))
        }
        
        // Update configuration
        self.audioConfig = config
        
        // Save changes
        return saveConfiguration()
    }
    
    // MARK: - Validation
    private func validateAudioConfig(_ config: AudioConfig) -> Bool {
        return config.sampleRate >= 44100 &&
               config.sampleRate <= 192000 &&
               config.bitDepth >= 16 &&
               config.bitDepth <= 32 &&
               config.bufferSize >= 64 &&
               config.bufferSize <= 2048 &&
               config.thdnThreshold <= 0.0005 &&
               config.targetLatency <= 0.010 &&
               config.amplifierEfficiency >= 0.90
    }
    
    // MARK: - Observers
    private func setupObservers() {
        // System configuration changes
        let powerObserver = NotificationCenter.default.addObserver(
            forName: NSNotification.Name.NSProcessInfoPowerStateDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handlePowerStateChange()
        }
        observers.append(powerObserver)
        
        // Audio configuration changes
        let audioObserver = NotificationCenter.default.addObserver(
            forName: NSNotification.Name("AudioConfigurationDidChange"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleAudioConfigurationChange()
        }
        observers.append(audioObserver)
    }
    
    // MARK: - Event Handlers
    private func handlePowerStateChange() {
        configurationQueue.async { [weak self] in
            guard let self = self else { return }
            
            let processingPriority = ProcessInfo.processInfo.isLowPowerModeEnabled ?
                2 : self.powerConfig.processingPriority
            
            self.powerConfig.processingPriority = processingPriority
            _ = self.saveConfiguration()
        }
    }
    
    private func handleAudioConfigurationChange() {
        configurationQueue.async { [weak self] in
            guard let self = self else { return }
            
            // Validate current audio configuration
            if !self.validateAudioConfig(self.audioConfig) {
                self.audioConfig = AudioConfig() // Reset to defaults
                _ = self.saveConfiguration()
            }
        }
    }
}

// MARK: - Codable Conformance
extension Configuration: Codable {
    private enum CodingKeys: String, CodingKey {
        case audioConfig, aiConfig, spatialConfig
        case networkConfig, logConfig, powerConfig
        case version
    }
}