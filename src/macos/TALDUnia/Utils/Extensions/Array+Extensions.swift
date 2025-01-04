import Foundation
import Accelerate // macOS 13.0+
import simd // macOS 13.0+

// MARK: - Float Array Extensions
extension Array where Element == Float {
    /// Root Mean Square value of the array
    public var rms: Float {
        guard !isEmpty else { return 0 }
        var squareSum: Float = 0
        vDSP_vsq(self, 1, &squareSum, 1, vDSP_Length(count))
        return sqrt(squareSum / Float(count))
    }
    
    /// Peak absolute value in the array
    public var peak: Float {
        guard !isEmpty else { return 0 }
        var maxVal: Float = 0
        vDSP_maxmgv(self, 1, &maxVal, vDSP_Length(count))
        return maxVal
    }
    
    /// Normalizes the array to a peak value of 1.0
    /// - Returns: Normalized array
    public func normalize() -> [Float] {
        guard let max = self.max(), max != 0 else { return self }
        var result = [Float](repeating: 0, count: count)
        var scalar = Float(1.0) / max
        vDSP_vsmul(self, 1, &scalar, &result, 1, vDSP_Length(count))
        return result
    }
    
    /// Applies gain to the array using vectorized multiplication
    /// - Parameter gain: Gain factor to apply
    /// - Returns: Processed array with applied gain
    public func applyGain(_ gain: Float) -> [Float] {
        var result = [Float](repeating: 0, count: count)
        var scalar = gain
        vDSP_vsmul(self, 1, &scalar, &result, 1, vDSP_Length(count))
        return result
    }
    
    /// Performs linear interpolation on the array
    /// - Parameter factor: Interpolation factor
    /// - Returns: Interpolated array
    public func interpolate(factor: Float) -> [Float] {
        return simdInterpolate(factor: factor)
    }
    
    /// Performs convolution with the given kernel
    /// - Parameter kernel: Convolution kernel
    /// - Returns: Convolved signal array
    public func convolve(with kernel: [Float]) -> [Float] {
        return vectorizedConvolve(kernel)
    }
    
    /// Performs optimized convolution using Accelerate framework
    /// - Parameter kernel: Convolution kernel
    /// - Returns: Convolved signal array
    public func vectorizedConvolve(_ kernel: [Float]) -> [Float] {
        guard !isEmpty && !kernel.isEmpty else { return [] }
        let resultCount = count + kernel.count - 1
        var result = [Float](repeating: 0, count: resultCount)
        vDSP_conv(self, 1, kernel, 1, &result, 1, vDSP_Length(resultCount), vDSP_Length(kernel.count))
        return result
    }
    
    /// Performs SIMD-accelerated linear interpolation
    /// - Parameter factor: Interpolation factor
    /// - Returns: Interpolated array
    public func simdInterpolate(factor: Float) -> [Float] {
        guard factor > 0 else { return self }
        let outputSize = Int(Float(count) * factor)
        var result = [Float](repeating: 0, count: outputSize)
        
        // Process in SIMD vector chunks where possible
        let vectorSize = 4
        let vectorCount = count / vectorSize
        let stride = simd_float4(0, 1, 2, 3)
        
        for i in 0..<vectorCount {
            let baseIndex = i * vectorSize
            let input = simd_float4(self[baseIndex..<baseIndex + vectorSize])
            let outputIndex = Int(Float(baseIndex) * factor)
            
            for j in 0..<Int(factor * Float(vectorSize)) {
                let position = Float(j) / factor
                let vectorPosition = stride + simd_float4(repeating: position)
                let weights = simd_float4(repeating: 1) - abs(vectorPosition - position)
                let contribution = input * weights
                if outputIndex + j < result.count {
                    result[outputIndex + j] += contribution.sum()
                }
            }
        }
        
        // Handle remaining elements
        for i in (vectorCount * vectorSize)..<count {
            let outputIndex = Int(Float(i) * factor)
            for j in 0..<Int(factor) {
                if outputIndex + j < result.count {
                    result[outputIndex + j] += self[i]
                }
            }
        }
        
        return result
    }
}

// MARK: - Double Array Extensions
extension Array where Element == Double {
    /// Root Mean Square value of the array
    public var rms: Double {
        guard !isEmpty else { return 0 }
        var squareSum: Double = 0
        vDSP_vsqD(self, 1, &squareSum, 1, vDSP_Length(count))
        return sqrt(squareSum / Double(count))
    }
    
    /// Peak absolute value in the array
    public var peak: Double {
        guard !isEmpty else { return 0 }
        var maxVal: Double = 0
        vDSP_maxmgvD(self, 1, &maxVal, vDSP_Length(count))
        return maxVal
    }
    
    /// Normalizes the array to a peak value of 1.0
    /// - Returns: Normalized array
    public func normalize() -> [Double] {
        guard let max = self.max(), max != 0 else { return self }
        var result = [Double](repeating: 0, count: count)
        var scalar = Double(1.0) / max
        vDSP_vsmulD(self, 1, &scalar, &result, 1, vDSP_Length(count))
        return result
    }
    
    /// Applies gain to the array using vectorized multiplication
    /// - Parameter gain: Gain factor to apply
    /// - Returns: Processed array with applied gain
    public func applyGain(_ gain: Double) -> [Double] {
        var result = [Double](repeating: 0, count: count)
        var scalar = gain
        vDSP_vsmulD(self, 1, &scalar, &result, 1, vDSP_Length(count))
        return result
    }
}

// MARK: - Generic BinaryFloatingPoint Array Extensions
extension Array where Element: BinaryFloatingPoint {
    /// Sum of all elements in the array
    public var sum: Element {
        return reduce(0, +)
    }
    
    /// Arithmetic mean of the array
    public var mean: Element {
        guard !isEmpty else { return 0 }
        return sum / Element(count)
    }
    
    /// Statistical variance of the array
    public var variance: Element {
        guard count > 1 else { return 0 }
        let m = mean
        return map { ($0 - m) * ($0 - m) }.sum / Element(count - 1)
    }
    
    /// Standard deviation of the array
    public var standardDeviation: Element {
        return Element(Double(variance).squareRoot())
    }
}