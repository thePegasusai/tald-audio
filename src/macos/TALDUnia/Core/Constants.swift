//
// Constants.swift
// TALD UNIA
//
// Core constants and configuration values for the TALD UNIA audio system
// Version: 1.0.0
//

import Foundation // macOS 13.0+

// MARK: - Global Application Constants
let APP_VERSION: String = "1.0.0"
let BUILD_NUMBER: Int = 1
let DEBUG_MODE: Bool = false
let MINIMUM_OS_VERSION: String = "13.0"

// MARK: - Audio Processing Constants
struct AudioConstants {
    /// Sample rate in Hz for audio processing (192kHz for premium audio quality)
    static let SAMPLE_RATE: Int = 192000
    
    /// Bit depth for audio processing (32-bit float for maximum precision)
    static let BIT_DEPTH: Int = 32
    
    /// Audio buffer size in samples (256 for optimal latency/performance balance)
    static let BUFFER_SIZE: Int = 256
    
    /// Maximum number of supported audio channels
    static let MAX_CHANNELS: Int = 8
    
    /// Target audio processing latency in seconds (<10ms as per requirements)
    static let TARGET_LATENCY: Double = 0.008
    
    /// Total Harmonic Distortion + Noise threshold (Burmester-level quality)
    static let THD_N_THRESHOLD: Double = 0.0005
    
    /// Target amplifier efficiency (90% as per requirements)
    static let AMPLIFIER_EFFICIENCY: Double = 0.90
}

// MARK: - AI Processing Constants
struct AIConstants {
    /// AI model version for audio enhancement
    static let MODEL_VERSION: String = "2.0.0"
    
    /// Batch size for AI inference processing
    static let INFERENCE_BATCH_SIZE: Int = 1024
    
    /// Threshold for AI enhancement activation
    static let ENHANCEMENT_THRESHOLD: Float = 0.2
    
    /// Maximum allowed processing time for AI enhancement (2ms)
    static let MAX_PROCESSING_TIME: TimeInterval = 0.002
}

// MARK: - Spatial Audio Constants
struct SpatialConstants {
    /// Version of the HRTF (Head-Related Transfer Function) model
    static let HRTF_VERSION: String = "1.0.0"
    
    /// Version of the room acoustics model
    static let ROOM_MODEL_VERSION: String = "1.0.0"
    
    /// Head tracking update rate in seconds (1ms for precise tracking)
    static let HEAD_TRACKING_UPDATE_RATE: Double = 0.001
    
    /// Spatial audio processing resolution in degrees
    static let SPATIAL_RESOLUTION: Double = 0.1
}

// MARK: - Network Configuration Constants
struct NetworkConstants {
    /// API version for backend communication
    static let API_VERSION: String = "v1"
    
    /// WebSocket protocol for real-time audio streaming
    static let WEBSOCKET_PROTOCOL: String = "wss"
    
    /// Network timeout interval in seconds
    static let TIMEOUT_INTERVAL: TimeInterval = 30.0
    
    /// Maximum number of retry attempts for network operations
    static let MAX_RETRY_ATTEMPTS: Int = 3
}