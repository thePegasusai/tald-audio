//
// AudioMath.swift
// TALD UNIA
//
// High-precision mathematical utilities for audio processing with SIMD optimization
// Version: 1.0.0
//

import Foundation // macOS 13.0+
import Accelerate // macOS 13.0+

// MARK: - Constants

/// Minimum decibel value for audio calculations
private let kMinDecibels: Float = -160.0

/// Maximum decibel value for audio calculations
private let kMaxDecibels: Float = 0.0

/// Small value to prevent divide by zero and denormal numbers
private let kEpsilon: Float = 1.0e-10

/// Nyquist frequency multiplier
private let kNyquistMultiplier: Float = 0.5

/// Maximum supported sample rate
private let kMaxSampleRate: Float = 384000.0

/// Small value to prevent denormal numbers in DSP calculations
private let kDenormalPrevention: Float = 1.0e-15

/// Phase calculation epsilon for high precision
private let kPhaseEpsilon: Float = 1.0e-12

// MARK: - Error Types

/// Errors specific to audio mathematical operations
public enum AudioMathError: Error {
    case frequencyOutOfRange
    case sampleRateInvalid
    case numericalOverflow
    case precisionLoss
}

// MARK: - Processing Mode

/// Audio processing optimization mode
public enum AudioProcessingMode {
    case highQuality    // Maximum precision, higher CPU usage
    case balanced      // Balance between quality and performance
    case efficient     // Optimized for power efficiency
}

// MARK: - SIMD-Optimized Conversions

/// Converts linear amplitude to decibels with denormal handling
/// - Parameter linearValue: Linear amplitude value
/// - Returns: Decibel value
@inline(__always)
@available(macOS 13.0, *)
public func linearToDecibels(_ linearValue: Float) -> Float {
    let value = linearValue + kDenormalPrevention
    if value < kEpsilon {
        return kMinDecibels
    }
    
    var result: Float = 0.0
    var input = value
    
    // Use vForce for SIMD optimization
    vvlog10f(&result, &input, [1])
    result *= 20.0
    
    return min(max(result, kMinDecibels), kMaxDecibels)
}

/// SIMD-optimized batch conversion from linear to decibel values
/// - Parameters:
///   - input: Pointer to input linear values
///   - output: Pointer to output decibel values
///   - count: Number of values to process
@inline(never)
@available(macOS 13.0, *)
public func vectorizedLinearToDecibels(
    _ input: UnsafePointer<Float>,
    _ output: UnsafeMutablePointer<Float>,
    _ count: Int
) {
    // Add denormal prevention
    var preventionBuffer = [Float](repeating: kDenormalPrevention, count: count)
    vDSP_vadd(input, 1, preventionBuffer, 1, output, 1, vDSP_Length(count))
    
    // Calculate log10
    vvlog10f(output, output, [Int32(count)])
    
    // Multiply by 20 for dB conversion
    var scalar: Float = 20.0
    vDSP_vsmul(output, 1, &scalar, output, 1, vDSP_Length(count))
    
    // Clamp values
    vDSP_vclip(output, 1, &kMinDecibels, &kMaxDecibels, output, 1, vDSP_Length(count))
}

/// Calculates precise phase shift with error bounds checking
/// - Parameters:
///   - frequency: Signal frequency in Hz
///   - timeDelay: Time delay in seconds
///   - sampleRate: Current sample rate
/// - Returns: Phase shift in radians with error handling
public func calculatePhaseShift(
    frequency: Float,
    timeDelay: Float,
    sampleRate: Float
) -> Result<Float, AudioMathError> {
    // Validate frequency against Nyquist limit
    let nyquistFrequency = sampleRate * kNyquistMultiplier
    guard frequency <= nyquistFrequency else {
        return .failure(.frequencyOutOfRange)
    }
    
    // Check for numerical overflow conditions
    guard frequency * timeDelay <= Float.greatestFiniteMagnitude / (2.0 * .pi) else {
        return .failure(.numericalOverflow)
    }
    
    // Calculate phase shift with high precision
    let phaseShift = 2.0 * .pi * frequency * timeDelay
    
    // Normalize phase to [-π, π] range
    let normalizedPhase = atan2(sin(phaseShift), cos(phaseShift))
    
    // Check precision loss
    if abs(sin(normalizedPhase) - sin(phaseShift)) > kPhaseEpsilon {
        return .failure(.precisionLoss)
    }
    
    return .success(normalizedPhase)
}

// MARK: - Audio Math Utilities

/// Static utility class for hardware-optimized audio calculations
@available(macOS 13.0, *)
public final class AudioMathUtils {
    
    // MARK: - Properties
    
    /// Indicates if SIMD optimization is enabled
    public private(set) static var isSimdEnabled: Bool = true
    
    /// Current processing mode
    public private(set) static var processingMode: AudioProcessingMode = .highQuality
    
    // MARK: - Initialization
    
    private init() {
        // Prevent instantiation of utility class
    }
    
    // MARK: - Configuration
    
    /// Configures calculations for specific hardware requirements
    /// - Parameter config: Hardware configuration
    /// - Returns: Success status
    public static func optimizeForHardware(_ config: AudioHardwareConfig) -> Bool {
        // Enable SIMD for ESS ES9038PRO DAC
        isSimdEnabled = true
        
        // Set processing mode based on hardware capabilities
        switch config.performanceProfile {
        case .premium:
            processingMode = .highQuality
        case .balanced:
            processingMode = .balanced
        case .efficient:
            processingMode = .efficient
        }
        
        return true
    }
    
    // MARK: - Utility Functions
    
    /// Converts frequency to angular velocity
    /// - Parameter frequency: Frequency in Hz
    /// - Returns: Angular velocity in radians/second
    @inline(__always)
    public static func frequencyToAngularVelocity(_ frequency: Float) -> Float {
        return 2.0 * .pi * frequency
    }
    
    /// Calculates wavelength from frequency and sample rate
    /// - Parameters:
    ///   - frequency: Frequency in Hz
    ///   - sampleRate: Sample rate in Hz
    /// - Returns: Wavelength in samples
    @inline(__always)
    public static func calculateWavelength(frequency: Float, sampleRate: Float) -> Float {
        return sampleRate / frequency
    }
}