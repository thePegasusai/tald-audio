//
// Profile.swift
// TALD UNIA
//
// Model representing a user profile with enhanced audio preferences and power optimization
// Foundation version: macOS 13.0+
//

import Foundation // macOS 13.0+

// MARK: - Global Constants
private let PROFILE_VERSION: String = "1.1.0"
private let VALIDATION_INTERVAL: TimeInterval = 3600 // 1 hour

// MARK: - Profile Model
@objc public class Profile: NSObject, Codable, Equatable {
    // MARK: - Properties
    public let id: UUID
    public var name: String
    public var description: String
    public var audioSettings: AudioSettings
    public var isDefault: Bool
    public var aiEnhancementEnabled: Bool
    public var spatialAudioEnabled: Bool
    public var powerOptimizationEnabled: Bool
    public var enhancementQuality: Float
    public let createdAt: Date
    public var updatedAt: Date
    public var lastValidated: Date
    
    private let lock = NSLock()
    
    private enum CodingKeys: String, CodingKey {
        case id, name, description, audioSettings, isDefault
        case aiEnhancementEnabled, spatialAudioEnabled
        case powerOptimizationEnabled, enhancementQuality
        case createdAt, updatedAt, lastValidated
    }
    
    // MARK: - Initialization
    public init(
        name: String,
        description: String? = nil,
        audioSettings: AudioSettings? = nil,
        powerOptimizationEnabled: Bool? = true
    ) {
        self.id = UUID()
        self.name = name
        self.description = description ?? "User profile for TALD UNIA audio system"
        self.audioSettings = audioSettings ?? AudioSettings()
        self.isDefault = false
        self.aiEnhancementEnabled = true
        self.spatialAudioEnabled = true
        self.powerOptimizationEnabled = powerOptimizationEnabled ?? true
        self.enhancementQuality = 0.8 // Default to 80% quality
        self.createdAt = Date()
        self.updatedAt = Date()
        self.lastValidated = Date()
        
        super.init()
        
        // Perform initial validation
        try? validateProfile()
    }
    
    // MARK: - Codable Implementation
    public required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        description = try container.decode(String.self, forKey: .description)
        audioSettings = try container.decode(AudioSettings.self, forKey: .audioSettings)
        isDefault = try container.decode(Bool.self, forKey: .isDefault)
        aiEnhancementEnabled = try container.decode(Bool.self, forKey: .aiEnhancementEnabled)
        spatialAudioEnabled = try container.decode(Bool.self, forKey: .spatialAudioEnabled)
        powerOptimizationEnabled = try container.decode(Bool.self, forKey: .powerOptimizationEnabled)
        enhancementQuality = try container.decode(Float.self, forKey: .enhancementQuality)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        lastValidated = try container.decode(Date.self, forKey: .lastValidated)
        
        super.init()
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(description, forKey: .description)
        try container.encode(audioSettings, forKey: .audioSettings)
        try container.encode(isDefault, forKey: .isDefault)
        try container.encode(aiEnhancementEnabled, forKey: .aiEnhancementEnabled)
        try container.encode(spatialAudioEnabled, forKey: .spatialAudioEnabled)
        try container.encode(powerOptimizationEnabled, forKey: .powerOptimizationEnabled)
        try container.encode(enhancementQuality, forKey: .enhancementQuality)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encode(lastValidated, forKey: .lastValidated)
    }
    
    // MARK: - Equatable Implementation
    public static func == (lhs: Profile, rhs: Profile) -> Bool {
        return lhs.id == rhs.id &&
            lhs.name == rhs.name &&
            lhs.description == rhs.description &&
            lhs.audioSettings == rhs.audioSettings &&
            lhs.isDefault == rhs.isDefault &&
            lhs.aiEnhancementEnabled == rhs.aiEnhancementEnabled &&
            lhs.spatialAudioEnabled == rhs.spatialAudioEnabled &&
            lhs.powerOptimizationEnabled == rhs.powerOptimizationEnabled &&
            lhs.enhancementQuality == rhs.enhancementQuality &&
            lhs.createdAt == rhs.createdAt &&
            lhs.updatedAt == rhs.updatedAt &&
            lhs.lastValidated == rhs.lastValidated
    }
    
    // MARK: - Profile Validation
    public func validateProfile() throws -> Bool {
        lock.lock()
        defer { lock.unlock() }
        
        // Validate name
        guard !name.isEmpty else {
            throw TALDError.validationError(
                code: "INVALID_PROFILE_NAME",
                message: "Profile name cannot be empty",
                metadata: ErrorMetadata(
                    timestamp: Date(),
                    component: "Profile",
                    additionalInfo: ["profile_id": id.uuidString]
                )
            )
        }
        
        // Validate audio settings
        try audioSettings.validateSettings()
        
        // Validate power optimization settings
        if powerOptimizationEnabled {
            guard let efficiency = audioSettings.powerOptimizationSettings["efficiencyTarget"],
                  efficiency >= Float(AudioConstants.AMPLIFIER_EFFICIENCY) else {
                throw TALDError.configurationError(
                    code: "INVALID_POWER_SETTINGS",
                    message: "Power efficiency must meet minimum target",
                    metadata: ErrorMetadata(
                        timestamp: Date(),
                        component: "Profile",
                        additionalInfo: [
                            "profile_id": id.uuidString,
                            "current_efficiency": String(describing: audioSettings.powerOptimizationSettings["efficiencyTarget"])
                        ]
                    )
                )
            }
        }
        
        // Validate enhancement quality
        guard (0.0...1.0).contains(enhancementQuality) else {
            throw TALDError.configurationError(
                code: "INVALID_ENHANCEMENT_QUALITY",
                message: "Enhancement quality must be between 0.0 and 1.0",
                metadata: ErrorMetadata(
                    timestamp: Date(),
                    component: "Profile",
                    additionalInfo: [
                        "profile_id": id.uuidString,
                        "current_quality": String(enhancementQuality)
                    ]
                )
            )
        }
        
        lastValidated = Date()
        return true
    }
    
    // MARK: - Profile Update
    public func update(
        name: String? = nil,
        description: String? = nil,
        audioSettings: AudioSettings? = nil,
        aiEnhancementEnabled: Bool? = nil,
        spatialAudioEnabled: Bool? = nil,
        powerOptimizationEnabled: Bool? = nil,
        enhancementQuality: Float? = nil
    ) throws {
        lock.lock()
        defer { lock.unlock() }
        
        // Update provided fields
        if let name = name { self.name = name }
        if let description = description { self.description = description }
        if let audioSettings = audioSettings { self.audioSettings = audioSettings }
        if let aiEnhancementEnabled = aiEnhancementEnabled { self.aiEnhancementEnabled = aiEnhancementEnabled }
        if let spatialAudioEnabled = spatialAudioEnabled { self.spatialAudioEnabled = spatialAudioEnabled }
        if let powerOptimizationEnabled = powerOptimizationEnabled { self.powerOptimizationEnabled = powerOptimizationEnabled }
        if let enhancementQuality = enhancementQuality { self.enhancementQuality = enhancementQuality }
        
        // Validate new configuration
        try validateProfile()
        
        // Update timestamps
        updatedAt = Date()
    }
}