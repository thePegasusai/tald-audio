//
// AudioFormat.swift
// TALD UNIA
//
// Manages audio format configurations with hardware optimization for premium audio quality
// Version: 1.0.0
//

import Foundation // macOS 13.0+
import AVFoundation // macOS 13.0+
import CoreAudio // macOS 13.0+

// MARK: - Global Constants

/// Default sample rate from core audio constants
private let kDefaultSampleRate: Int = AudioConstants.SAMPLE_RATE

/// Default bit depth from core audio constants
private let kDefaultBitDepth: Int = AudioConstants.BIT_DEPTH

/// Extended sample rate support for premium audio quality
private let kSupportedSampleRates: [Int] = [44100, 48000, 88200, 96000, 176400, 192000, 352800, 384000]

/// Supported bit depths for various quality levels
private let kSupportedBitDepths: [Int] = [16, 24, 32]

/// Optimal hardware buffer size for ESS ES9038PRO DAC
private let kHardwareBufferSize: Int = 256

// MARK: - Audio Format Creation

/// Creates an optimized AVAudioFormat instance with hardware considerations
/// - Parameters:
///   - sampleRate: The desired sample rate in Hz
///   - bitDepth: The desired bit depth
///   - channelCount: Number of audio channels
///   - isHardwareOptimized: Whether to optimize for ESS ES9038PRO DAC
/// - Returns: Result containing the configured format or error
public func createAudioFormat(
    sampleRate: Int = kDefaultSampleRate,
    bitDepth: Int = kDefaultBitDepth,
    channelCount: Int = 2,
    isHardwareOptimized: Bool = true
) -> Result<AVAudioFormat, TALDError> {
    
    // Validate sample rate
    guard kSupportedSampleRates.contains(sampleRate) else {
        return .failure(TALDError.configurationError(
            code: "INVALID_SAMPLE_RATE",
            message: "Unsupported sample rate: \(sampleRate)",
            metadata: ErrorMetadata(
                timestamp: Date(),
                component: "AudioFormat",
                additionalInfo: ["sampleRate": "\(sampleRate)"]
            )
        ))
    }
    
    // Validate bit depth
    guard kSupportedBitDepths.contains(bitDepth) else {
        return .failure(TALDError.configurationError(
            code: "INVALID_BIT_DEPTH",
            message: "Unsupported bit depth: \(bitDepth)",
            metadata: ErrorMetadata(
                timestamp: Date(),
                component: "AudioFormat",
                additionalInfo: ["bitDepth": "\(bitDepth)"]
            )
        ))
    }
    
    // Configure format description
    var audioFormatDescription = AudioStreamBasicDescription()
    audioFormatDescription.mSampleRate = Float64(sampleRate)
    audioFormatDescription.mFormatID = kAudioFormatLinearPCM
    audioFormatDescription.mFormatFlags = kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked
    audioFormatDescription.mBitsPerChannel = UInt32(bitDepth)
    audioFormatDescription.mChannelsPerFrame = UInt32(channelCount)
    audioFormatDescription.mFramesPerPacket = 1
    audioFormatDescription.mBytesPerFrame = audioFormatDescription.mChannelsPerFrame * UInt32(bitDepth / 8)
    audioFormatDescription.mBytesPerPacket = audioFormatDescription.mBytesPerFrame
    
    // Apply hardware optimization if requested
    if isHardwareOptimized {
        audioFormatDescription.mFormatFlags |= kAudioFormatFlagIsNonInterleaved
        if bitDepth == 32 {
            audioFormatDescription.mFormatFlags |= kAudioFormatFlagIsAlignedHigh
        }
    }
    
    // Create AVAudioFormat
    guard let format = AVAudioFormat(streamDescription: &audioFormatDescription) else {
        return .failure(TALDError.audioProcessingError(
            code: "FORMAT_CREATION_FAILED",
            message: "Failed to create audio format",
            metadata: ErrorMetadata(
                timestamp: Date(),
                component: "AudioFormat",
                additionalInfo: [
                    "sampleRate": "\(sampleRate)",
                    "bitDepth": "\(bitDepth)",
                    "channelCount": "\(channelCount)"
                ]
            )
        ))
    }
    
    return .success(format)
}

// MARK: - Audio Format Manager

/// Manages audio format configurations with hardware optimization support
public class AudioFormatManager {
    
    // MARK: - Properties
    
    /// Current audio format configuration
    public private(set) var currentFormat: AVAudioFormat
    
    /// Current sample rate in Hz
    public private(set) var currentSampleRate: Int
    
    /// Current bit depth
    public private(set) var currentBitDepth: Int
    
    /// Current channel count
    public private(set) var currentChannelCount: Int
    
    /// Hardware optimization status
    public private(set) var isHardwareOptimized: Bool
    
    /// Notifier for format changes
    private let formatChangeNotifier = NotificationCenter.default
    
    // MARK: - Initialization
    
    /// Initializes the AudioFormatManager with optional initial format
    /// - Parameters:
    ///   - initialFormat: Optional initial audio format
    ///   - enableHardwareOptimization: Whether to enable hardware optimization
    public init(initialFormat: AVAudioFormat? = nil, enableHardwareOptimization: Bool = true) {
        self.isHardwareOptimized = enableHardwareOptimization
        
        // Create initial format if none provided
        if let format = initialFormat {
            self.currentFormat = format
            self.currentSampleRate = Int(format.sampleRate)
            self.currentBitDepth = Int(format.streamDescription.pointee.mBitsPerChannel)
            self.currentChannelCount = Int(format.channelCount)
        } else {
            // Use default format
            let formatResult = createAudioFormat(
                sampleRate: kDefaultSampleRate,
                bitDepth: kDefaultBitDepth,
                channelCount: 2,
                isHardwareOptimized: enableHardwareOptimization
            )
            
            switch formatResult {
            case .success(let format):
                self.currentFormat = format
                self.currentSampleRate = kDefaultSampleRate
                self.currentBitDepth = kDefaultBitDepth
                self.currentChannelCount = 2
            case .failure(let error):
                fatalError("Failed to create default audio format: \(error.localizedDescription)")
            }
        }
    }
    
    // MARK: - Format Management
    
    /// Updates the current audio format configuration
    /// - Parameters:
    ///   - newFormat: The new format to apply
    ///   - forceHardwareSync: Whether to force hardware synchronization
    /// - Returns: Result indicating success or failure with error context
    public func updateFormat(newFormat: AVAudioFormat, forceHardwareSync: Bool = false) -> Result<Bool, TALDError> {
        // Validate new format
        let newSampleRate = Int(newFormat.sampleRate)
        let newBitDepth = Int(newFormat.streamDescription.pointee.mBitsPerChannel)
        let newChannelCount = Int(newFormat.channelCount)
        
        guard kSupportedSampleRates.contains(newSampleRate) else {
            return .failure(TALDError.configurationError(
                code: "INVALID_SAMPLE_RATE",
                message: "Unsupported sample rate in new format: \(newSampleRate)",
                metadata: ErrorMetadata(
                    timestamp: Date(),
                    component: "AudioFormatManager",
                    additionalInfo: ["sampleRate": "\(newSampleRate)"]
                )
            ))
        }
        
        guard kSupportedBitDepths.contains(newBitDepth) else {
            return .failure(TALDError.configurationError(
                code: "INVALID_BIT_DEPTH",
                message: "Unsupported bit depth in new format: \(newBitDepth)",
                metadata: ErrorMetadata(
                    timestamp: Date(),
                    component: "AudioFormatManager",
                    additionalInfo: ["bitDepth": "\(newBitDepth)"]
                )
            ))
        }
        
        // Update format properties
        currentFormat = newFormat
        currentSampleRate = newSampleRate
        currentBitDepth = newBitDepth
        currentChannelCount = newChannelCount
        
        // Notify observers of format change
        formatChangeNotifier.post(
            name: Notification.Name("AudioFormatDidChange"),
            object: self,
            userInfo: [
                "sampleRate": newSampleRate,
                "bitDepth": newBitDepth,
                "channelCount": newChannelCount,
                "isHardwareOptimized": isHardwareOptimized
            ]
        )
        
        return .success(true)
    }
    
    /// Validates a given audio format against system capabilities
    /// - Parameter format: The format to validate
    /// - Returns: Boolean indicating format validity
    public func validateFormat(_ format: AVAudioFormat) -> Bool {
        let sampleRate = Int(format.sampleRate)
        let bitDepth = Int(format.streamDescription.pointee.mBitsPerChannel)
        
        return kSupportedSampleRates.contains(sampleRate) &&
               kSupportedBitDepths.contains(bitDepth) &&
               format.channelCount <= AudioConstants.MAX_CHANNELS
    }
}