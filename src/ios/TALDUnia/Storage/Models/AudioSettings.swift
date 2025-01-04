// Foundation Latest
import Foundation

/// Error types specific to audio settings
enum AudioSettingsError: Error {
    case invalidHardwareConfiguration(String)
    case invalidSpatialConfiguration(String)
    case invalidAIConfiguration(String)
    case invalidEQConfiguration(String)
    case threadSafetyViolation(String)
    case encodingError(String)
    case decodingError(String)
    case migrationError(String)
}

/// Structure representing an equalizer band
struct EQBand: Codable {
    let frequency: Float
    let gain: Float
    let q: Float
}

/// Structure for spatial audio configuration
struct SpatialConfig: Codable {
    var roomSize: Double
    var reverbTime: Double
    var hrtfEnabled: Bool
    var headTrackingEnabled: Bool
}

/// Structure for AI enhancement configuration
struct AIConfig: Codable {
    var enhancementLevel: Float
    var modelVersion: String
    var confidenceThreshold: Float
    var processingPriority: Int
}

/// Thread-safe model class representing comprehensive audio settings
@objc @objcMembers public class AudioSettings: NSObject, Codable {
    // MARK: - Properties
    
    public private(set) var id: UUID
    public private(set) var profileId: UUID
    public private(set) var hardwareSettings: HardwareSettings
    public private(set) var equalizerBands: [EQBand]
    public private(set) var spatialSettings: SpatialConfig
    public private(set) var enhancementSettings: AIConfig
    public private(set) var isActive: Bool
    public private(set) var createdAt: Date
    public private(set) var updatedAt: Date
    
    private let settingsLock = NSLock()
    private let schemaVersion: Int = 1
    
    // MARK: - Initialization
    
    public init(id: UUID,
                profileId: UUID,
                hardwareSettings: HardwareSettings,
                spatialSettings: SpatialConfig? = nil,
                enhancementSettings: AIConfig? = nil) throws {
        self.id = id
        self.profileId = profileId
        self.hardwareSettings = hardwareSettings
        self.createdAt = Date()
        self.updatedAt = Date()
        self.isActive = true
        self.equalizerBands = []
        
        // Initialize spatial settings with defaults if not provided
        self.spatialSettings = spatialSettings ?? SpatialConfig(
            roomSize: SpatialConstants.defaultRoomSize,
            reverbTime: SpatialConstants.defaultReverbTime,
            hrtfEnabled: true,
            headTrackingEnabled: true
        )
        
        // Initialize AI settings with defaults if not provided
        self.enhancementSettings = enhancementSettings ?? AIConfig(
            enhancementLevel: AIConstants.defaultEnhancementLevel,
            modelVersion: AIConstants.modelVersion,
            confidenceThreshold: AIConstants.minimumConfidenceThreshold,
            processingPriority: AIConstants.processingPriority
        )
        
        super.init()
        
        // Validate initial configuration
        try validateConfiguration().get()
    }
    
    // MARK: - Codable Implementation
    
    private enum CodingKeys: String, CodingKey {
        case id, profileId, hardwareSettings, equalizerBands
        case spatialSettings, enhancementSettings, isActive
        case createdAt, updatedAt, schemaVersion
    }
    
    public func encode(to encoder: Encoder) throws {
        settingsLock.lock()
        defer { settingsLock.unlock() }
        
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(id, forKey: .id)
        try container.encode(profileId, forKey: .profileId)
        try container.encode(hardwareSettings, forKey: .hardwareSettings)
        try container.encode(equalizerBands, forKey: .equalizerBands)
        try container.encode(spatialSettings, forKey: .spatialSettings)
        try container.encode(enhancementSettings, forKey: .enhancementSettings)
        try container.encode(isActive, forKey: .isActive)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
    }
    
    public required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        // Version checking for future migrations
        let version = try container.decode(Int.self, forKey: .schemaVersion)
        guard version <= schemaVersion else {
            throw AudioSettingsError.migrationError("Unsupported schema version: \(version)")
        }
        
        // Decode properties
        id = try container.decode(UUID.self, forKey: .id)
        profileId = try container.decode(UUID.self, forKey: .profileId)
        hardwareSettings = try container.decode(HardwareSettings.self, forKey: .hardwareSettings)
        equalizerBands = try container.decode([EQBand].self, forKey: .equalizerBands)
        spatialSettings = try container.decode(SpatialConfig.self, forKey: .spatialSettings)
        enhancementSettings = try container.decode(AIConfig.self, forKey: .enhancementSettings)
        isActive = try container.decode(Bool.self, forKey: .isActive)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        
        super.init()
    }
    
    // MARK: - Public Methods
    
    /// Updates hardware settings with thread safety and validation
    public func updateHardwareSettings(_ newSettings: HardwareSettings) -> Result<Void, Error> {
        settingsLock.lock()
        defer { settingsLock.unlock() }
        
        do {
            // Validate new hardware settings
            try validateConfiguration().get()
            
            // Update settings and timestamp
            self.hardwareSettings = newSettings
            self.updatedAt = Date()
            
            return .success(())
        } catch {
            return .failure(error)
        }
    }
    
    /// Validates the complete configuration
    public func validateConfiguration() -> Result<Void, Error> {
        settingsLock.lock()
        defer { settingsLock.unlock() }
        
        do {
            // Validate hardware settings
            try hardwareSettings.validate().get()
            
            // Validate spatial settings
            guard spatialSettings.roomSize <= SpatialConstants.maxRoomSize else {
                throw AudioSettingsError.invalidSpatialConfiguration("Room size exceeds maximum")
            }
            
            // Validate AI enhancement settings
            guard enhancementSettings.confidenceThreshold >= AIConstants.minimumConfidenceThreshold else {
                throw AudioSettingsError.invalidAIConfiguration("Confidence threshold too low")
            }
            
            // Validate equalizer bands
            for band in equalizerBands {
                guard QualityConstants.frequencyResponse.contains(Double(band.frequency)) else {
                    throw AudioSettingsError.invalidEQConfiguration("Invalid frequency: \(band.frequency)")
                }
            }
            
            return .success(())
        } catch {
            return .failure(error)
        }
    }
}