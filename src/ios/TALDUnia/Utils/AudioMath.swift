//
// AudioMath.swift
// TALD UNIA
//
// High-performance audio mathematics utilities optimized for iOS using SIMD and Accelerate framework
// Version: 1.0.0
//

import Foundation // Latest - Basic Swift functionality and math operations
import Accelerate // Latest - High-performance mathematical operations using vDSP and vForce functions

// MARK: - Constants

/// Minimum decibel value for audio calculations (-160 dB)
private let kMinDecibels: Float = -160.0

/// Maximum decibel value for audio calculations (0 dB)
private let kMaxDecibels: Float = 0.0

/// Reference level for decibel calculations
private let kReferenceLevel: Float = 1.0

/// Small value to prevent log of zero
private let kEpsilon: Float = 1.0e-10

/// Default FFT size for spectral analysis
private let kFFTSize: Int = 2048

/// Maximum number of harmonics to analyze for THD calculation
private let kMaxHarmonics: Int = 10

// MARK: - Amplitude Conversion Functions

/// Converts linear amplitude to decibels using SIMD optimization
/// - Parameter amplitude: Linear amplitude value to convert
/// - Returns: Corresponding decibel value, clamped between kMinDecibels and kMaxDecibels
@inline(__always)
public func linearToDecibels(_ amplitude: Float) -> Float {
    // Guard against invalid input
    guard amplitude >= kEpsilon else {
        return kMinDecibels
    }
    
    // Create single-element array for vForce operation
    var input = [amplitude]
    var output = [Float](repeating: 0, count: 1)
    
    // Perform vectorized log10 calculation
    vvlog10f(&output, input, [1])
    
    // Calculate decibels and apply reference level scaling
    let decibels = 20.0 * output[0]
    
    // Clamp result to valid range
    return min(max(decibels, kMinDecibels), kMaxDecibels)
}

/// Converts decibels to linear amplitude using parallel processing
/// - Parameter decibels: Decibel value to convert
/// - Returns: Corresponding linear amplitude value
@inline(__always)
public func decibelsToLinear(_ decibels: Float) -> Float {
    // Clamp input to valid range
    let clampedDecibels = min(max(decibels, kMinDecibels), kMaxDecibels)
    
    // Prepare for vectorized calculation
    var input = [clampedDecibels / 20.0]
    var output = [Float](repeating: 0, count: 1)
    
    // Perform vectorized power calculation
    vvpowf(&output, [10.0], input, [1])
    
    // Apply reference level scaling
    return output[0] * kReferenceLevel
}

// MARK: - Audio Analysis Functions

/// Calculates Root Mean Square value of audio buffer using vDSP
/// - Parameters:
///   - buffer: Pointer to audio sample buffer
///   - length: Number of samples in buffer
/// - Returns: RMS value of the audio buffer
public func calculateRMS(_ buffer: UnsafePointer<Float>, length: Int) -> Float {
    // Validate input parameters
    guard length > 0 else {
        return 0.0
    }
    
    // Allocate temporary buffer for squared values
    var squaredValues = [Float](repeating: 0, count: length)
    
    // Calculate squared values using vDSP
    vDSP_vsq(buffer, 1, &squaredValues, 1, vDSP_Length(length))
    
    // Calculate mean of squared values
    var mean: Float = 0.0
    vDSP_meanv(squaredValues, 1, &mean, vDSP_Length(length))
    
    // Calculate square root using vForce
    var result: Float = 0.0
    vvsqrtf(&result, [mean], [1])
    
    return result
}

/// Finds peak level in audio buffer using vDSP optimization
/// - Parameters:
///   - buffer: Pointer to audio sample buffer
///   - length: Number of samples in buffer
/// - Returns: Peak level in decibels
public func calculatePeakLevel(_ buffer: UnsafePointer<Float>, length: Int) -> Float {
    // Validate input parameters
    guard length > 0 else {
        return kMinDecibels
    }
    
    // Find maximum absolute value using vDSP
    var maxValue: Float = 0.0
    vDSP_maxmgv(buffer, 1, &maxValue, vDSP_Length(length))
    
    // Convert to decibels
    return linearToDecibels(maxValue)
}

/// Calculates Total Harmonic Distortion using FFT analysis
/// - Parameters:
///   - buffer: Pointer to audio sample buffer
///   - length: Number of samples in buffer
///   - fundamentalFrequency: Expected fundamental frequency in Hz
/// - Returns: THD value as percentage
public func calculateTHD(_ buffer: UnsafePointer<Float>, length: Int, fundamentalFrequency: Float) -> Float {
    // Validate input parameters
    guard length >= kFFTSize && fundamentalFrequency > 0 else {
        return 0.0
    }
    
    // Create FFT setup
    guard let fftSetup = vDSP_DFT_zop_CreateSetup(nil, vDSP_Length(kFFTSize), .FORWARD) else {
        return 0.0
    }
    defer {
        vDSP_DFT_DestroySetup(fftSetup)
    }
    
    // Prepare FFT buffers
    var realPart = [Float](repeating: 0, count: kFFTSize)
    var imagPart = [Float](repeating: 0, count: kFFTSize)
    
    // Apply Hanning window
    var window = [Float](repeating: 0, count: kFFTSize)
    vDSP_hann_window(&window, vDSP_Length(kFFTSize), Int32(vDSP_HANN_NORM))
    vDSP_vmul(buffer, 1, window, 1, &realPart, 1, vDSP_Length(kFFTSize))
    
    // Perform FFT
    var splitComplex = DSPSplitComplex(realp: &realPart, imagp: &imagPart)
    vDSP_DFT_Execute(fftSetup, &splitComplex.realp, &splitComplex.imagp, &splitComplex.realp, &splitComplex.imagp)
    
    // Calculate magnitude spectrum
    var magnitudes = [Float](repeating: 0, count: kFFTSize/2)
    vDSP_zvmags(&splitComplex, 1, &magnitudes, 1, vDSP_Length(kFFTSize/2))
    
    // Find fundamental frequency bin
    let binWidth = Float(44100) / Float(kFFTSize) // Assuming 44.1kHz sample rate
    let fundamentalBin = Int(fundamentalFrequency / binWidth)
    
    // Calculate harmonic magnitudes
    var fundamentalPower: Float = magnitudes[fundamentalBin]
    var harmonicsPower: Float = 0.0
    
    for harmonic in 2...kMaxHarmonics {
        let harmonicBin = harmonic * fundamentalBin
        guard harmonicBin < kFFTSize/2 else { break }
        harmonicsPower += magnitudes[harmonicBin]
    }
    
    // Calculate THD
    guard fundamentalPower > kEpsilon else {
        return 0.0
    }
    
    return 100.0 * sqrt(harmonicsPower / fundamentalPower)
}