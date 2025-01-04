//
// Float+Extensions.swift
// TALD UNIA
//
// High-precision floating-point extensions for audio processing
// Version: 1.0.0
//

import Foundation // Latest - Core Swift functionality and mathematical operations
import AudioMath // Internal - Audio mathematical constants and utilities

// MARK: - Float Extensions for Audio Processing
extension Float {
    
    /// Converts linear amplitude value to decibels with high precision
    /// - Returns: Value in decibels, clamped between kMinDecibels and kMaxDecibels
    @inlinable
    public func toDecibels() -> Float {
        // Guard against denormal numbers
        guard self >= kEpsilon else {
            return kMinDecibels
        }
        
        // Use AudioMath's optimized conversion
        return AudioMath.linearToDecibels(self)
    }
    
    /// Converts decibel value to linear amplitude
    /// - Returns: Linear amplitude value with guaranteed numerical stability
    @inlinable
    public func fromDecibels() -> Float {
        // Use AudioMath's optimized conversion
        return AudioMath.decibelsToLinear(self)
    }
    
    /// Clamps float value between bounds using SIMD-optimized operations
    /// - Parameters:
    ///   - minimum: Lower bound for clamping
    ///   - maximum: Upper bound for clamping
    /// - Returns: Clamped value with guaranteed bounds
    @inlinable
    public func clamp(minimum: Float, maximum: Float) -> Float {
        // Validate input parameters
        guard minimum <= maximum else {
            return self
        }
        
        // Use Swift's built-in clamping for SIMD optimization
        return Swift.min(Swift.max(self, minimum), maximum)
    }
    
    /// Normalizes float value to [0,1] range with high precision
    /// - Parameters:
    ///   - minimum: Lower bound of input range
    ///   - maximum: Upper bound of input range
    /// - Returns: Normalized value with guaranteed [0,1] bounds
    @inlinable
    public func normalize(minimum: Float, maximum: Float) -> Float {
        // Validate input range
        guard minimum < maximum else {
            return 0
        }
        
        // Handle potential division by zero
        let range = maximum - minimum
        guard range > kEpsilon else {
            return 0
        }
        
        // Apply normalization formula with clamping
        let normalized = (self - minimum) / range
        return normalized.clamp(minimum: 0, maximum: 1)
    }
    
    /// Denormalizes float value from [0,1] to target range with precision guarantees
    /// - Parameters:
    ///   - minimum: Lower bound of target range
    ///   - maximum: Upper bound of target range
    /// - Returns: Denormalized value with guaranteed range bounds
    @inlinable
    public func denormalize(minimum: Float, maximum: Float) -> Float {
        // Validate input is in [0,1] range
        let normalizedValue = self.clamp(minimum: 0, maximum: 1)
        
        // Validate target range
        guard minimum < maximum else {
            return minimum
        }
        
        // Apply denormalization formula
        let range = maximum - minimum
        return (normalizedValue * range) + minimum
    }
}