//
// Array+Extensions.swift
// TALD UNIA
//
// High-performance array extensions for audio signal processing
// Version: 1.0.0
//

import Foundation // Latest - Basic Swift functionality
import Accelerate // Latest - High-performance SIMD operations

// MARK: - Array Extension for Audio Processing
extension Array where Element == Float {
    
    /// Memory pool for temporary buffers to reduce allocations
    private static let bufferPool = NSCache<NSNumber, [Float]>()
    
    /// Calculates the Root Mean Square (RMS) value of the array using SIMD optimization
    /// - Returns: RMS value with precision meeting THD+N requirements
    @inlinable
    public func rms() -> Float {
        guard !isEmpty else { return 0.0 }
        
        // Reuse or allocate temporary buffer
        let count = vDSP_Length(self.count)
        let cacheKey = NSNumber(value: count)
        var squared = Array.bufferPool.object(forKey: cacheKey) ?? [Float](repeating: 0, count: self.count)
        defer { Array.bufferPool.setObject(squared, forKey: cacheKey) }
        
        // Calculate squared values using SIMD
        vDSP_vsq(self, 1, &squared, 1, count)
        
        // Calculate mean
        var mean: Float = 0.0
        vDSP_meanv(squared, 1, &mean, count)
        
        // Calculate square root
        var result: Float = 0.0
        vvsqrtf(&result, [mean], [1])
        
        return result
    }
    
    /// Finds the peak absolute value in the array using vectorized operations
    /// - Returns: Maximum absolute value with high precision
    @inlinable
    public func peak() -> Float {
        guard !isEmpty else { return 0.0 }
        
        var maxValue: Float = 0.0
        vDSP_maxmgv(self, 1, &maxValue, vDSP_Length(count))
        
        return maxValue
    }
    
    /// Normalizes array values to a specified peak level with precision scaling
    /// - Parameter targetLevel: Target peak level (0.0 to 1.0)
    /// - Returns: Normalized array maintaining signal quality
    @inlinable
    public func normalize(to targetLevel: Float = 1.0) -> [Float] {
        guard !isEmpty else { return [] }
        
        // Clamp target level to valid range
        let clampedTarget = min(max(targetLevel, 0.0), 1.0)
        
        // Find current peak
        let currentPeak = self.peak()
        
        // Guard against division by zero
        guard currentPeak > 0.0 else { return self }
        
        // Calculate scaling factor
        let scaleFactor = clampedTarget / currentPeak
        
        // Allocate or reuse output buffer
        let cacheKey = NSNumber(value: count)
        var output = Array.bufferPool.object(forKey: cacheKey) ?? [Float](repeating: 0, count: count)
        defer { Array.bufferPool.setObject(output, forKey: cacheKey) }
        
        // Apply scaling using SIMD
        vDSP_vsmul(self, 1, [scaleFactor], &output, 1, vDSP_Length(count))
        
        return Array(output[0..<count])
    }
    
    /// Applies gain in decibels to array values with optimized conversion
    /// - Parameter gainDB: Gain value in decibels
    /// - Returns: Array with applied gain maintaining signal quality
    @inlinable
    public func applyGain(_ gainDB: Float) -> [Float] {
        guard !isEmpty else { return [] }
        
        // Convert dB to linear gain using AudioMath utility
        let linearGain = AudioMath.decibelsToLinear(gainDB)
        
        // Allocate or reuse output buffer
        let cacheKey = NSNumber(value: count)
        var output = Array.bufferPool.object(forKey: cacheKey) ?? [Float](repeating: 0, count: count)
        defer { Array.bufferPool.setObject(output, forKey: cacheKey) }
        
        // Apply gain using SIMD
        vDSP_vsmul(self, 1, [linearGain], &output, 1, vDSP_Length(count))
        
        // Handle denormal numbers
        if linearGain < 1.0e-10 {
            vDSP_vclr(&output, 1, vDSP_Length(count))
        }
        
        return Array(output[0..<count])
    }
}