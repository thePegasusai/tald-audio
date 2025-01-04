// Foundation v6.0+
import Foundation

/// Core audio processing and hardware configuration constants aligned with ESS ES9038PRO DAC specifications
public struct AudioConstants {
    /// Sample rate in Hz (192kHz for premium audio quality)
    public static let sampleRate: Int = 192_000
    
    /// Bit depth for audio processing (32-bit float for maximum precision)
    public static let bitDepth: Int = 32
    
    /// Buffer size in samples (256 as per ESS ES9038PRO DAC specifications)
    public static let bufferSize: Int = 256
    
    /// Number of audio channels (2 for stereo processing)
    public static let channelCount: Int = 2
    
    /// Maximum allowed audio processing latency (10ms as per requirements)
    public static let maxLatency: TimeInterval = 0.010
    
    /// DAC model identifier
    public static let dacModel: String = "ESS ES9038PRO"
    
    /// Audio controller model identifier
    public static let controllerModel: String = "XMOS XU316"
}

/// AI processing configuration for audio enhancement
public struct AIConstants {
    /// Current AI model version
    public static let modelVersion: String = "2.0.0"
    
    /// Maximum time allowed for AI inference
    public static let inferenceTimeout: TimeInterval = 0.005
    
    /// Default AI enhancement level (0.0 - 1.0)
    public static let defaultEnhancementLevel: Float = 0.8
    
    /// Minimum confidence threshold for AI processing
    public static let minimumConfidenceThreshold: Float = 0.85
    
    /// Processing priority for AI operations (0-99)
    public static let processingPriority: Int = 45
}

/// Network configuration for audio streaming and cloud processing
public struct NetworkConstants {
    /// Base URL for cloud services
    public static let baseURL: String = "https://api.taldunia.com/v1"
    
    /// Network timeout interval
    public static let timeoutInterval: TimeInterval = 30.0
    
    /// Maximum number of retry attempts
    public static let maxRetryCount: Int = 3
    
    /// Connection pool size for network operations
    public static let connectionPoolSize: Int = 8
}

/// Spatial audio processing configuration
public struct SpatialConstants {
    /// Default room size in cubic meters
    public static let defaultRoomSize: Double = 50.0
    
    /// Default reverberation time (RT60) in seconds
    public static let defaultReverbTime: Double = 0.3
    
    /// Maximum supported room size in cubic meters
    public static let maxRoomSize: Double = 200.0
    
    /// HRTF angle resolution in degrees
    public static let hrtfResolution: Double = 1.0
    
    /// Maximum number of spatial audio channels
    public static let maxSpatialChannels: Int = 16
}

/// Audio quality standards and targets
public struct QualityConstants {
    /// Target Total Harmonic Distortion + Noise (0.0005% as per requirements)
    public static let targetTHD: Double = 0.000005
    
    /// Target Signal-to-Noise Ratio in dB (>120dB as per requirements)
    public static let targetSNR: Double = 120.0
    
    /// Minimum required quality improvement through AI processing (20% as per requirements)
    public static let minQualityImprovement: Double = 0.20
    
    /// Maximum allowed jitter in audio processing
    public static let maxJitter: TimeInterval = 0.000001
    
    /// Supported frequency response range in Hz (20Hz - 20kHz)
    public static let frequencyResponse: Range<Double> = 20.0..<20_000.0
}