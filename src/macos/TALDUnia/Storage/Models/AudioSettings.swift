//
// AudioSettings.swift
// TALD UNIA
//
// Model representing audio settings and configuration parameters with power optimization
// Foundation version: macOS 13.0+
//

import Foundation

// MARK: - Global Constants
private let SETTINGS_VERSION: String = "1.1.0"
private let POWER_OPTIMIZATION_ENABLED: Bool = true

// MARK: - AudioSettings Model
@objc public class AudioSettings: NSObject, Codable, Equatable {
    // MARK: - Properties
    public let id: UUID
    public var sampleRate: Int
    public var bitDepth: Int
    public var bufferSize: Int
    public var channels: Int
    public var masterVolume: Float
    public var enhancementEnabled: Bool
    public var spatialEnabled: Bool
    public var eqSettings: [String: Float]
    public var dspParameters: [String: Any]
    public var powerOptimizationSettings: [String: Float]
    public var updatedAt: Date
    public var lastValidated: Date
    
    private enum CodingKeys: String, CodingKey {
        case id, sampleRate, bitDepth, bufferSize, channels
        case masterVolume, enhancementEnabled, spatialEnabled
        case eqSettings, powerOptimizationSettings, updatedAt, lastValidated
        // dspParameters handled separately due to Any type
    }
    
    // MARK: - Initialization
    public init(
        sampleRate: Int? = nil,
        bitDepth: Int? = nil,
        bufferSize: Int? = nil,
        channels: Int? = nil,
        powerSettings: [String: Float]? = nil
    ) {
        self.id = UUID()
        self.sampleRate = sampleRate ?? AudioConstants.SAMPLE_RATE
        self.bitDepth = bitDepth ?? AudioConstants.BIT_DEPTH
        self.bufferSize = bufferSize ?? AudioConstants.BUFFER_SIZE
        self.channels = channels ?? AudioConstants.MAX_CHANNELS
        self.masterVolume = 1.0
        self.enhancementEnabled = true
        self.spatialEnabled = true
        self.eqSettings = [:]
        self.dspParameters = [
            "enhancementLevel": 0.8,
            "noiseReduction": true,
            "dynamicRange": 120.0
        ]
        self.powerOptimizationSettings = powerSettings ?? [
            "efficiencyTarget": AudioConstants.AMPLIFIER_EFFICIENCY,
            "powerMode": 1.0, // 1.0 = balanced, 0.0 = power saver, 2.0 = performance
            "processingThreshold": 0.7
        ]
        self.updatedAt = Date()
        self.lastValidated = Date()
        
        super.init()
    }
    
    // MARK: - Codable Implementation
    public required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        id = try container.decode(UUID.self, forKey: .id)
        sampleRate = try container.decode(Int.self, forKey: .sampleRate)
        bitDepth = try container.decode(Int.self, forKey: .bitDepth)
        bufferSize = try container.decode(Int.self, forKey: .bufferSize)
        channels = try container.decode(Int.self, forKey: .channels)
        masterVolume = try container.decode(Float.self, forKey: .masterVolume)
        enhancementEnabled = try container.decode(Bool.self, forKey: .enhancementEnabled)
        spatialEnabled = try container.decode(Bool.self, forKey: .spatialEnabled)
        eqSettings = try container.decode([String: Float].self, forKey: .eqSettings)
        powerOptimizationSettings = try container.decode([String: Float].self, forKey: .powerOptimizationSettings)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        lastValidated = try container.decode(Date.self, forKey: .lastValidated)
        
        // Handle dspParameters separately due to Any type
        dspParameters = UserDefaults.standard.dictionary(forKey: "dspParameters") ?? [:]
        
        super.init()
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(id, forKey: .id)
        try container.encode(sampleRate, forKey: .sampleRate)
        try container.encode(bitDepth, forKey: .bitDepth)
        try container.encode(bufferSize, forKey: .bufferSize)
        try container.encode(channels, forKey: .channels)
        try container.encode(masterVolume, forKey: .masterVolume)
        try container.encode(enhancementEnabled, forKey: .enhancementEnabled)
        try container.encode(spatialEnabled, forKey: .spatialEnabled)
        try container.encode(eqSettings, forKey: .eqSettings)
        try container.encode(powerOptimizationSettings, forKey: .powerOptimizationSettings)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encode(lastValidated, forKey: .lastValidated)
        
        // Save dspParameters separately
        UserDefaults.standard.set(dspParameters, forKey: "dspParameters")
    }
    
    // MARK: - Equatable Implementation
    public static func == (lhs: AudioSettings, rhs: AudioSettings) -> Bool {
        return lhs.id == rhs.id &&
            lhs.sampleRate == rhs.sampleRate &&
            lhs.bitDepth == rhs.bitDepth &&
            lhs.bufferSize == rhs.bufferSize &&
            lhs.channels == rhs.channels &&
            lhs.masterVolume == rhs.masterVolume &&
            lhs.enhancementEnabled == rhs.enhancementEnabled &&
            lhs.spatialEnabled == rhs.spatialEnabled &&
            lhs.eqSettings == rhs.eqSettings &&
            lhs.powerOptimizationSettings == rhs.powerOptimizationSettings &&
            lhs.updatedAt == rhs.updatedAt &&
            lhs.lastValidated == rhs.lastValidated
    }
    
    // MARK: - Settings Validation
    public func validateSettings() throws -> Bool {
        // Validate sample rate
        guard sampleRate == AudioConstants.SAMPLE_RATE else {
            throw TALDError.configurationError(
                code: "INVALID_SAMPLE_RATE",
                message: "Sample rate must be \(AudioConstants.SAMPLE_RATE)Hz",
                metadata: ErrorMetadata(
                    timestamp: Date(),
                    component: "AudioSettings",
                    additionalInfo: ["current": "\(sampleRate)"]
                )
            )
        }
        
        // Validate bit depth
        guard bitDepth == AudioConstants.BIT_DEPTH else {
            throw TALDError.configurationError(
                code: "INVALID_BIT_DEPTH",
                message: "Bit depth must be \(AudioConstants.BIT_DEPTH)-bit",
                metadata: ErrorMetadata(
                    timestamp: Date(),
                    component: "AudioSettings",
                    additionalInfo: ["current": "\(bitDepth)"]
                )
            )
        }
        
        // Validate buffer size
        guard bufferSize == AudioConstants.BUFFER_SIZE else {
            throw TALDError.configurationError(
                code: "INVALID_BUFFER_SIZE",
                message: "Buffer size must be \(AudioConstants.BUFFER_SIZE) samples",
                metadata: ErrorMetadata(
                    timestamp: Date(),
                    component: "AudioSettings",
                    additionalInfo: ["current": "\(bufferSize)"]
                )
            )
        }
        
        // Validate power optimization
        if POWER_OPTIMIZATION_ENABLED {
            guard let efficiencyTarget = powerOptimizationSettings["efficiencyTarget"],
                  efficiencyTarget >= Float(AudioConstants.AMPLIFIER_EFFICIENCY) else {
                throw TALDError.configurationError(
                    code: "INVALID_POWER_EFFICIENCY",
                    message: "Power efficiency must meet target of \(AudioConstants.AMPLIFIER_EFFICIENCY)",
                    metadata: ErrorMetadata(
                        timestamp: Date(),
                        component: "AudioSettings",
                        additionalInfo: ["current": "\(powerOptimizationSettings["efficiencyTarget"] ?? 0.0)"]
                    )
                )
            }
        }
        
        lastValidated = Date()
        return true
    }
    
    // MARK: - Settings Update
    public func update(
        sampleRate: Int? = nil,
        bitDepth: Int? = nil,
        bufferSize: Int? = nil,
        channels: Int? = nil,
        eqSettings: [String: Float]? = nil,
        dspParameters: [String: Any]? = nil,
        powerSettings: [String: Float]? = nil
    ) throws {
        if let sampleRate = sampleRate { self.sampleRate = sampleRate }
        if let bitDepth = bitDepth { self.bitDepth = bitDepth }
        if let bufferSize = bufferSize { self.bufferSize = bufferSize }
        if let channels = channels { self.channels = channels }
        if let eqSettings = eqSettings { self.eqSettings = eqSettings }
        if let dspParameters = dspParameters { self.dspParameters = dspParameters }
        if let powerSettings = powerSettings { self.powerOptimizationSettings = powerSettings }
        
        // Validate new settings
        try validateSettings()
        
        updatedAt = Date()
    }
}