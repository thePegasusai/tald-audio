// Foundation v17.0+
import Foundation
import AVFoundation

/// Constants for audio format configuration
private enum FormatConstants {
    static let kMinSampleRate: Double = 44100
    static let kMaxSampleRate: Double = 192000
    static let kDefaultBitDepth: Int = 32
    static let kMaxChannels: Int = 8
    static let kOptimalBufferSize: Int = 256
    static let kHardwareLatency: Double = 2.0
}

/// Manages audio format configuration and validation for high-quality audio processing with hardware optimization
@objc public class AudioFormat: NSObject {
    
    // MARK: - Properties
    
    /// Current audio format configuration
    public private(set) var currentFormat: AVAudioFormat?
    
    /// Current sample rate in Hz
    public private(set) var sampleRate: Int
    
    /// Current bit depth
    public private(set) var bitDepth: Int
    
    /// Number of audio channels
    public private(set) var channelCount: Int
    
    /// Indicates if audio data is interleaved
    public private(set) var isInterleaved: Bool
    
    /// Current processing latency in milliseconds
    public private(set) var currentLatency: Double
    
    /// Indicates if format is optimized for hardware
    public private(set) var isHardwareOptimized: Bool
    
    /// Current channel layout configuration
    private var channelLayout: AVAudioChannelLayout?
    
    // MARK: - Initialization
    
    /// Initializes AudioFormat with specified parameters and hardware optimization
    /// - Parameters:
    ///   - sampleRate: The desired sample rate in Hz
    ///   - bitDepth: The desired bit depth
    ///   - channels: The number of audio channels
    ///   - interleaved: Whether the audio data should be interleaved
    public init(sampleRate: Int = AudioConstants.sampleRate,
                bitDepth: Int = AudioConstants.bitDepth,
                channels: Int = AudioConstants.channelCount,
                interleaved: Bool = true) throws {
        
        self.sampleRate = sampleRate
        self.bitDepth = bitDepth
        self.channelCount = channels
        self.isInterleaved = interleaved
        self.currentLatency = FormatConstants.kHardwareLatency
        self.isHardwareOptimized = false
        
        super.init()
        
        // Validate hardware capabilities
        try validateHardwareCapabilities(sampleRate: sampleRate,
                                       bitDepth: bitDepth,
                                       channels: channels)
            .get()
        
        // Create initial format
        try createAudioFormat()
            .get()
    }
    
    // MARK: - Format Validation
    
    /// Validates if the sample rate is supported by the system and hardware
    /// - Parameter sampleRate: The sample rate to validate
    /// - Returns: Result indicating validation success or detailed error
    @inlinable
    public func validateSampleRate(_ sampleRate: Double) -> Result<Bool, Error> {
        // Check range
        guard sampleRate >= FormatConstants.kMinSampleRate &&
              sampleRate <= FormatConstants.kMaxSampleRate else {
            return .failure(AppError.audioError(
                reason: "Sample rate \(sampleRate) Hz is outside supported range",
                severity: .error,
                context: ErrorContext(additionalInfo: [
                    "minRate": FormatConstants.kMinSampleRate,
                    "maxRate": FormatConstants.kMaxSampleRate
                ])
            ))
        }
        
        // Verify hardware compatibility
        guard sampleRate <= AudioConstants.sampleRate else {
            return .failure(AppError.hardwareError(
                reason: "Sample rate exceeds DAC capabilities",
                severity: .error,
                context: ErrorContext(additionalInfo: [
                    "requestedRate": sampleRate,
                    "maxHardwareRate": AudioConstants.sampleRate,
                    "dacModel": AudioConstants.dacModel
                ])
            ))
        }
        
        return .success(true)
    }
    
    /// Validates format compatibility with ESS ES9038PRO DAC
    /// - Parameters:
    ///   - sampleRate: The sample rate to validate
    ///   - bitDepth: The bit depth to validate
    ///   - channels: The number of channels to validate
    /// - Returns: Result indicating hardware compatibility or detailed error
    @inlinable
    public func validateHardwareCapabilities(sampleRate: Int,
                                           bitDepth: Int,
                                           channels: Int) -> Result<Bool, Error> {
        // Validate sample rate
        let sampleRateResult = validateSampleRate(Double(sampleRate))
        if case .failure(let error) = sampleRateResult {
            return .failure(error)
        }
        
        // Validate bit depth
        guard bitDepth <= FormatConstants.kDefaultBitDepth else {
            return .failure(AppError.hardwareError(
                reason: "Bit depth exceeds DAC capabilities",
                severity: .error,
                context: ErrorContext(additionalInfo: [
                    "requestedBitDepth": bitDepth,
                    "maxBitDepth": FormatConstants.kDefaultBitDepth
                ])
            ))
        }
        
        // Validate channel count
        guard channels <= FormatConstants.kMaxChannels else {
            return .failure(AppError.hardwareError(
                reason: "Channel count exceeds hardware capabilities",
                severity: .error,
                context: ErrorContext(additionalInfo: [
                    "requestedChannels": channels,
                    "maxChannels": FormatConstants.kMaxChannels
                ])
            ))
        }
        
        return .success(true)
    }
    
    // MARK: - Format Management
    
    /// Creates a new hardware-optimized AVAudioFormat instance
    /// - Returns: Result containing the created format or detailed error
    public func createAudioFormat() -> Result<AVAudioFormat, Error> {
        let audioFormat: AVAudioFormat
        
        // Create format based on configuration
        if isInterleaved {
            guard let format = AVAudioFormat(
                standardFormatWithSampleRate: Double(sampleRate),
                channels: UInt32(channelCount)
            ) else {
                return .failure(AppError.audioError(
                    reason: "Failed to create interleaved format",
                    severity: .error,
                    context: ErrorContext(additionalInfo: [
                        "sampleRate": sampleRate,
                        "channels": channelCount
                    ])
                ))
            }
            audioFormat = format
        } else {
            guard let format = AVAudioFormat(
                nonInterleavedFloatFormatWithSampleRate: Double(sampleRate),
                channels: UInt32(channelCount)
            ) else {
                return .failure(AppError.audioError(
                    reason: "Failed to create non-interleaved format",
                    severity: .error,
                    context: ErrorContext(additionalInfo: [
                        "sampleRate": sampleRate,
                        "channels": channelCount
                    ])
                ))
            }
            audioFormat = format
        }
        
        // Update properties
        currentFormat = audioFormat
        isHardwareOptimized = true
        
        return .success(audioFormat)
    }
    
    /// Updates the audio format with new parameters while maintaining hardware optimization
    /// - Parameters:
    ///   - sampleRate: Optional new sample rate
    ///   - bitDepth: Optional new bit depth
    ///   - channels: Optional new channel count
    ///   - interleaved: Optional new interleaved state
    /// - Returns: Result indicating update success or detailed error
    public func updateFormat(sampleRate: Int? = nil,
                           bitDepth: Int? = nil,
                           channels: Int? = nil,
                           interleaved: Bool? = nil) -> Result<Bool, Error> {
        
        let newSampleRate = sampleRate ?? self.sampleRate
        let newBitDepth = bitDepth ?? self.bitDepth
        let newChannels = channels ?? self.channelCount
        let newInterleaved = interleaved ?? self.isInterleaved
        
        // Validate new configuration
        try? validateHardwareCapabilities(
            sampleRate: newSampleRate,
            bitDepth: newBitDepth,
            channels: newChannels
        ).get()
        
        // Update properties
        self.sampleRate = newSampleRate
        self.bitDepth = newBitDepth
        self.channelCount = newChannels
        self.isInterleaved = newInterleaved
        
        // Create new format
        let formatResult = createAudioFormat()
        switch formatResult {
        case .success(let format):
            currentFormat = format
            return .success(true)
        case .failure(let error):
            return .failure(error)
        }
    }
}