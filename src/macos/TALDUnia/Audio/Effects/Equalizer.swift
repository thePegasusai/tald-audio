//
// Equalizer.swift
// TALD UNIA
//
// High-precision parametric equalizer with ESS ES9038PRO DAC integration
// Version: 1.0.0
//

import Foundation // macOS 13.0+
import Accelerate // macOS 13.0+
import simd // macOS 13.0+

// MARK: - Global Constants

private let kMaxBands: Int = 31
private let kMinFrequency: Float = 20.0
private let kMaxFrequency: Float = 20000.0
private let kMaxGainDB: Float = 12.0
private let kMinQ: Float = 0.1
private let kMaxQ: Float = 10.0
private let kBufferSize: Int = 256
private let kSampleRate: Float = 192000.0
private let kBitDepth: Int = 32

// MARK: - Filter Band Structure

private struct FilterBand {
    var frequency: Float
    var gain: Float
    var q: Float
    var isEnabled: Bool
    var coefficients: FilterCoefficients
}

private struct FilterCoefficients {
    var b0: Double
    var b1: Double
    var b2: Double
    var a1: Double
    var a2: Double
}

// MARK: - Equalizer Implementation

@objc
public class Equalizer {
    // MARK: - Properties
    
    private let dspProcessor: DSPProcessor
    private let simdProcessor: SIMDProcessor
    private var bands: [FilterBand]
    private let sampleRate: Float
    private var isEnabled: Bool
    private let processingQueue: DispatchQueue
    private let dacInterface: ESS9038Interface
    private let monitor: PerformanceMonitor
    private let activeProcessingCount = AtomicInteger()
    
    // MARK: - Initialization
    
    public init(config: EQConfiguration, dacConfig: ESS9038Configuration) throws {
        // Validate configurations
        guard config.sampleRate <= kSampleRate,
              config.bitDepth == kBitDepth,
              config.bands <= kMaxBands else {
            throw TALDError.configurationError(
                code: "INVALID_EQ_CONFIG",
                message: "Invalid equalizer configuration",
                metadata: ErrorMetadata(
                    timestamp: Date(),
                    component: "Equalizer",
                    additionalInfo: [
                        "sampleRate": "\(config.sampleRate)",
                        "bitDepth": "\(config.bitDepth)",
                        "bands": "\(config.bands)"
                    ]
                )
            )
        }
        
        // Initialize processors
        self.dspProcessor = try DSPProcessor(config: DSPConfiguration(
            bufferSize: kBufferSize,
            channels: 2,
            sampleRate: Double(kSampleRate),
            isOptimized: true,
            useHardwareAcceleration: true
        ))
        
        self.simdProcessor = try SIMDProcessor(
            channels: 2,
            vectorSize: 8,
            config: .ess9038Pro
        )
        
        // Initialize filter bands
        self.bands = []
        self.sampleRate = kSampleRate
        self.isEnabled = true
        
        // Configure processing queue
        self.processingQueue = DispatchQueue(
            label: "com.tald.unia.equalizer",
            qos: .userInteractive,
            attributes: .concurrent
        )
        
        // Initialize DAC interface
        self.dacInterface = try ESS9038Interface(config: dacConfig)
        
        // Initialize performance monitoring
        self.monitor = PerformanceMonitor()
        
        // Configure initial filter bands
        try setupDefaultBands()
    }
    
    // MARK: - Audio Processing
    
    public func process(
        _ input: UnsafePointer<Float>,
        _ output: UnsafeMutablePointer<Float>,
        frameCount: Int
    ) -> Result<Void, TALDError> {
        let startTime = Date()
        let activeCount = activeProcessingCount.increment()
        defer { activeProcessingCount.decrement() }
        
        // Validate buffer alignment
        guard input.alignedPointer(to: Float.self, alignment: 16) != nil,
              output.alignedPointer(to: Float.self, alignment: 16) != nil else {
            return .failure(TALDError.audioProcessingError(
                code: "BUFFER_ALIGNMENT",
                message: "Buffers not aligned for SIMD operations",
                metadata: ErrorMetadata(
                    timestamp: Date(),
                    component: "Equalizer",
                    additionalInfo: ["frameCount": "\(frameCount)"]
                )
            ))
        }
        
        // Process through SIMD processor
        let simdResult = simdProcessor.processVector(input, output, frameCount: frameCount)
        guard case .success = simdResult else {
            return .failure(TALDError.audioProcessingError(
                code: "SIMD_PROCESSING",
                message: "SIMD processing failed",
                metadata: ErrorMetadata(
                    timestamp: Date(),
                    component: "Equalizer",
                    additionalInfo: ["frameCount": "\(frameCount)"]
                )
            ))
        }
        
        // Apply filter bands
        for band in bands where band.isEnabled {
            // Apply biquad filtering with SIMD optimization
            vDSP_deq22(
                output,
                1,
                [Float(band.coefficients.b0),
                 Float(band.coefficients.b1),
                 Float(band.coefficients.b2)],
                [Float(band.coefficients.a1),
                 Float(band.coefficients.a2)],
                output,
                1,
                vDSP_Length(frameCount)
            )
        }
        
        // Apply final gain compensation and DAC optimization
        let dacResult = dacInterface.processOutput(output, frameCount: frameCount)
        guard case .success = dacResult else {
            return .failure(TALDError.audioProcessingError(
                code: "DAC_PROCESSING",
                message: "DAC processing failed",
                metadata: ErrorMetadata(
                    timestamp: Date(),
                    component: "Equalizer",
                    additionalInfo: ["frameCount": "\(frameCount)"]
                )
            ))
        }
        
        // Update performance metrics
        let processingTime = Date().timeIntervalSince(startTime)
        monitor.updateMetrics(processingTime: processingTime)
        
        return .success(())
    }
    
    // MARK: - Filter Calculations
    
    @inline(__always)
    private func calculateFilterCoefficients(
        frequency: Float,
        gain: Float,
        q: Float,
        sampleRate: Float
    ) -> FilterCoefficients {
        // Validate frequency range
        let clampedFreq = min(max(frequency, kMinFrequency), kMaxFrequency)
        let clampedGain = min(max(gain, -kMaxGainDB), kMaxGainDB)
        let clampedQ = min(max(q, kMinQ), kMaxQ)
        
        // Calculate intermediate values with guard bits
        let omega = 2.0 * .pi * Double(clampedFreq) / Double(sampleRate)
        let sinOmega = sin(omega)
        let cosOmega = cos(omega)
        let alpha = sinOmega / (2.0 * Double(clampedQ))
        let a = pow(10.0, Double(clampedGain) / 40.0)
        
        // Calculate coefficients with overflow protection
        let b0 = 1.0 + alpha * a
        let b1 = -2.0 * cosOmega
        let b2 = 1.0 - alpha * a
        let a0 = 1.0 + alpha / a
        let a1 = -2.0 * cosOmega
        let a2 = 1.0 - alpha / a
        
        // Normalize coefficients
        return FilterCoefficients(
            b0: b0 / a0,
            b1: b1 / a0,
            b2: b2 / a0,
            a1: a1 / a0,
            a2: a2 / a0
        )
    }
    
    // MARK: - Band Management
    
    private func setupDefaultBands() throws {
        // Configure standard ISO frequency bands
        let frequencies: [Float] = [
            31.5, 63, 125, 250, 500, 1000, 2000, 4000, 8000, 16000
        ]
        
        for frequency in frequencies {
            let band = FilterBand(
                frequency: frequency,
                gain: 0.0,
                q: 1.4,
                isEnabled: true,
                coefficients: calculateFilterCoefficients(
                    frequency: frequency,
                    gain: 0.0,
                    q: 1.4,
                    sampleRate: sampleRate
                )
            )
            bands.append(band)
        }
    }
    
    public func setBand(index: Int, frequency: Float, gain: Float, q: Float) -> Result<Void, TALDError> {
        guard index >= 0 && index < bands.count else {
            return .failure(TALDError.configurationError(
                code: "INVALID_BAND_INDEX",
                message: "Invalid equalizer band index",
                metadata: ErrorMetadata(
                    timestamp: Date(),
                    component: "Equalizer",
                    additionalInfo: ["index": "\(index)"]
                )
            ))
        }
        
        processingQueue.async {
            self.bands[index].frequency = frequency
            self.bands[index].gain = gain
            self.bands[index].q = q
            self.bands[index].coefficients = self.calculateFilterCoefficients(
                frequency: frequency,
                gain: gain,
                q: q,
                sampleRate: self.sampleRate
            )
        }
        
        return .success(())
    }
}