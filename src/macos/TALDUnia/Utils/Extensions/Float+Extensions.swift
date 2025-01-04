//
// Float+Extensions.swift
// TALD UNIA
//
// High-precision Float extensions optimized for ESS ES9038PRO DAC integration
// Version: 1.0.0
//

import Foundation // macOS 13.0+
import simd // macOS 13.0+

// MARK: - Constants

/// Minimum normalized value for audio processing
private let kMinNormalizedValue: Float = -1.0

/// Maximum normalized value for audio processing
private let kMaxNormalizedValue: Float = 1.0

/// Default epsilon for high-precision comparisons
private let kDefaultEpsilon: Float = 1.0e-10

/// Threshold for denormal number detection
private let kDenormalThreshold: Float = 1.0e-15

/// Maximum decibel value for audio processing
private let kMaxDecibels: Float = 120.0

// MARK: - Float Extensions

extension Float {
    
    /// Clamps float value between minimum and maximum bounds with denormal number handling
    /// - Parameters:
    ///   - min: Minimum allowed value
    ///   - max: Maximum allowed value
    /// - Returns: Clamped value with denormal protection
    @inlinable
    @inline(__always)
    public func clamp(min: Float, max: Float) -> Float {
        let value = AudioMath.handleDenormalNumbers(self)
        if value < min { return min }
        if value > max { return max }
        return value
    }
    
    /// Normalizes float value to range [-1, 1] with high-precision handling
    /// - Returns: Normalized value with denormal protection
    @inlinable
    @inline(__always)
    public func normalize() -> Float {
        let value = AudioMath.handleDenormalNumbers(self)
        return value.clamp(min: kMinNormalizedValue, max: kMaxNormalizedValue)
    }
    
    /// Converts float value to decibels with high-precision handling
    /// - Returns: Value in decibels with range protection
    @inlinable
    public func toDecibels() -> Float {
        let value = AudioMath.handleDenormalNumbers(self)
        let decibels = AudioMath.linearToDecibels(value)
        return decibels.clamp(min: -kMaxDecibels, max: kMaxDecibels)
    }
    
    /// Converts decibel value to linear scale with precision handling
    /// - Returns: Linear value with denormal protection
    @inlinable
    public func fromDecibels() -> Float {
        let value = self.clamp(min: -kMaxDecibels, max: kMaxDecibels)
        let linear = AudioMath.decibelsToLinear(value)
        return AudioMath.handleDenormalNumbers(linear)
    }
    
    /// Checks if value is within epsilon range of target with high precision
    /// - Parameters:
    ///   - target: Target value for comparison
    ///   - epsilon: Precision threshold (defaults to kDefaultEpsilon)
    /// - Returns: True if within epsilon range
    @inlinable
    @inline(__always)
    public func isWithinEpsilon(of target: Float, epsilon: Float = kDefaultEpsilon) -> Bool {
        let value = AudioMath.handleDenormalNumbers(self)
        let targetValue = AudioMath.handleDenormalNumbers(target)
        let difference = abs(value - targetValue)
        return difference <= epsilon
    }
    
    /// Checks if value is potentially a denormal number
    /// - Returns: True if value is below denormal threshold
    @inlinable
    @inline(__always)
    internal func isDenormal() -> Bool {
        return abs(self) < kDenormalThreshold
    }
}