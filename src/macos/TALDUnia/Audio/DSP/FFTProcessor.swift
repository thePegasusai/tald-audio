//
// FFTProcessor.swift
// TALD UNIA
//
// High-performance FFT processor with hardware-specific optimizations for ESS ES9038PRO DAC
// Version: 1.0.0
//

import Foundation // macOS 13.0+
import Accelerate // macOS 13.0+
import simd // macOS 13.0+

// MARK: - Global Constants

private let kDefaultFFTSize: Int = 2048
private let kMinFFTSize: Int = 256
private let kMaxFFTSize: Int = 16384
private let kOverlapFactor: Float = 0.5
private let kHardwareAlignment: Int = 32
private let kMaxLatencyMs: Float = 10.0
private let kQualityThreshold: Float = 0.0005

// MARK: - FFT Configuration

private struct FFTConfig {
    let fftSize: Int
    let hopSize: Int
    let windowType: WindowType
    let isOptimized: Bool
    
    enum WindowType {
        case hann
        case blackman
        case hamming
    }
}

// MARK: - Performance Monitoring

private struct FFTPerformanceMetrics {
    var averageLatency: Double = 0.0
    var peakLatency: Double = 0.0
    var processingLoad: Double = 0.0
    var thdPlusNoise: Double = 0.0
    var lastUpdateTime: Date = Date()
    
    mutating func update(latency: TimeInterval, load: Double) {
        averageLatency = (averageLatency + latency) / 2.0
        peakLatency = max(peakLatency, latency)
        processingLoad = load
        lastUpdateTime = Date()
    }
}

// MARK: - FFT Processor Implementation

@objc
public class FFTProcessor {
    // MARK: - Properties
    
    private var fftSetup: vDSP_DFT_Setup?
    private let fftSize: Int
    private let hopSize: Int
    private let inputBuffer: UnsafeMutablePointer<Float>
    private let fftBuffer: UnsafeMutablePointer<DSPSplitComplex>
    private let windowBuffer: UnsafeMutablePointer<Float>
    private var isProcessing: Bool = false
    private let processingQueue: DispatchQueue
    private let bufferLock = NSLock()
    private var metrics = FFTPerformanceMetrics()
    private let config: FFTConfig
    
    // MARK: - Initialization
    
    public init(fftSize: Int = kDefaultFFTSize, overlapFactor: Float = kOverlapFactor) throws {
        // Validate FFT size
        guard case .success = validateFFTSize(fftSize) else {
            throw TALDError.configurationError(
                code: "INVALID_FFT_SIZE",
                message: "Invalid FFT size configuration",
                metadata: ErrorMetadata(
                    timestamp: Date(),
                    component: "FFTProcessor",
                    additionalInfo: ["fftSize": "\(fftSize)"]
                )
            )
        }
        
        self.fftSize = fftSize
        self.hopSize = Int(Float(fftSize) * (1.0 - overlapFactor))
        
        // Create FFT setup
        guard let setup = vDSP_DFT_zop_CreateSetup(
            nil,
            vDSP_Length(fftSize),
            vDSP_DFT_FORWARD
        ) else {
            throw TALDError.audioProcessingError(
                code: "FFT_SETUP_FAILED",
                message: "Failed to create FFT setup",
                metadata: ErrorMetadata(
                    timestamp: Date(),
                    component: "FFTProcessor",
                    additionalInfo: ["fftSize": "\(fftSize)"]
                )
            )
        }
        self.fftSetup = setup
        
        // Allocate aligned buffers
        guard let inputMem = UnsafeMutablePointer<Float>.allocate(capacity: fftSize)
            .alignedPointer(to: Float.self, alignment: kHardwareAlignment),
              let fftMem = UnsafeMutablePointer<DSPSplitComplex>.allocate(capacity: 1)
            .alignedPointer(to: DSPSplitComplex.self, alignment: kHardwareAlignment),
              let windowMem = UnsafeMutablePointer<Float>.allocate(capacity: fftSize)
            .alignedPointer(to: Float.self, alignment: kHardwareAlignment) else {
            throw TALDError.audioProcessingError(
                code: "BUFFER_ALLOCATION_FAILED",
                message: "Failed to allocate aligned buffers",
                metadata: ErrorMetadata(
                    timestamp: Date(),
                    component: "FFTProcessor",
                    additionalInfo: ["fftSize": "\(fftSize)"]
                )
            )
        }
        
        self.inputBuffer = inputMem
        self.fftBuffer = fftMem
        self.windowBuffer = windowMem
        
        // Initialize window function
        vDSP_hann_window(windowBuffer, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))
        
        // Configure processing queue
        self.processingQueue = DispatchQueue(
            label: "com.tald.unia.fft.processor",
            qos: .userInteractive
        )
        
        // Initialize configuration
        self.config = FFTConfig(
            fftSize: fftSize,
            hopSize: hopSize,
            windowType: .hann,
            isOptimized: true
        )
    }
    
    deinit {
        if let setup = fftSetup {
            vDSP_DFT_DestroySetup(setup)
        }
        inputBuffer.deallocate()
        fftBuffer.deallocate()
        windowBuffer.deallocate()
    }
    
    // MARK: - FFT Processing
    
    public func processSpectrum(_ input: UnsafePointer<Float>,
                              _ output: UnsafeMutablePointer<Float>,
                              frameCount: Int) -> Result<SpectralData, TALDError> {
        let startTime = Date()
        
        return bufferLock.synchronized {
            // Validate frame count
            guard frameCount > 0 && frameCount <= fftSize else {
                return .failure(TALDError.audioProcessingError(
                    code: "INVALID_FRAME_COUNT",
                    message: "Invalid frame count for FFT processing",
                    metadata: ErrorMetadata(
                        timestamp: Date(),
                        component: "FFTProcessor",
                        additionalInfo: ["frameCount": "\(frameCount)"]
                    )
                ))
            }
            
            // Copy input with window function
            vDSP_vmul(input, 1, windowBuffer, 1, inputBuffer, 1, vDSP_Length(frameCount))
            
            // Perform FFT
            var splitComplex = DSPSplitComplex(
                realp: fftBuffer.pointee.realp,
                imagp: fftBuffer.pointee.imagp
            )
            
            vDSP_DFT_Execute(fftSetup!, inputBuffer, &splitComplex)
            
            // Calculate magnitude spectrum
            vDSP_zvmags(&splitComplex, 1, output, 1, vDSP_Length(frameCount / 2))
            
            // Convert to dB scale
            var scaleFactor = Float(20.0)
            vDSP_vdbcon(output, 1, &scaleFactor, output, 1, vDSP_Length(frameCount / 2), 1)
            
            // Update performance metrics
            let processingTime = Date().timeIntervalSince(startTime)
            metrics.update(
                latency: processingTime,
                load: Double(frameCount) / Double(fftSize)
            )
            
            // Validate processing quality
            if metrics.thdPlusNoise > Double(kQualityThreshold) {
                return .failure(TALDError.audioProcessingError(
                    code: "QUALITY_THRESHOLD_EXCEEDED",
                    message: "THD+N exceeded quality threshold",
                    metadata: ErrorMetadata(
                        timestamp: Date(),
                        component: "FFTProcessor",
                        additionalInfo: [
                            "thd": "\(metrics.thdPlusNoise)",
                            "threshold": "\(kQualityThreshold)"
                        ]
                    )
                ))
            }
            
            // Return spectral data
            return .success(SpectralData(
                magnitude: Array(UnsafeBufferPointer(start: output, count: frameCount / 2)),
                fftSize: fftSize,
                hopSize: hopSize
            ))
        }
    }
    
    // MARK: - Spectral Effects
    
    public func applySpectralEffect(_ spectrum: inout DSPSplitComplex,
                                  effect: SpectralEffect) {
        bufferLock.synchronized {
            switch effect {
            case .normalize:
                var maxValue: Float = 0.0
                vDSP_maxv(spectrum.realp, 1, &maxValue, vDSP_Length(fftSize / 2))
                if maxValue > 0.0 {
                    var scale = 1.0 / maxValue
                    vDSP_vsmul(spectrum.realp, 1, &scale, spectrum.realp, 1, vDSP_Length(fftSize / 2))
                    vDSP_vsmul(spectrum.imagp, 1, &scale, spectrum.imagp, 1, vDSP_Length(fftSize / 2))
                }
            case .smooth(let factor):
                var smoothFactor = factor
                vDSP_vsmooth(spectrum.realp, 1, &smoothFactor, spectrum.realp, 1, vDSP_Length(fftSize / 2))
                vDSP_vsmooth(spectrum.imagp, 1, &smoothFactor, spectrum.imagp, 1, vDSP_Length(fftSize / 2))
            }
        }
    }
    
    // MARK: - Performance Monitoring
    
    public func monitorPerformance() -> FFTPerformanceMetrics {
        bufferLock.synchronized {
            return metrics
        }
    }
}

// MARK: - Validation Functions

public func validateFFTSize(_ fftSize: Int) -> Result<Void, TALDError> {
    // Check if power of 2
    if (fftSize & (fftSize - 1)) != 0 {
        return .failure(TALDError.configurationError(
            code: "INVALID_FFT_SIZE",
            message: "FFT size must be power of 2",
            metadata: ErrorMetadata(
                timestamp: Date(),
                component: "FFTProcessor",
                additionalInfo: ["fftSize": "\(fftSize)"]
            )
        ))
    }
    
    // Check size bounds
    if fftSize < kMinFFTSize || fftSize > kMaxFFTSize {
        return .failure(TALDError.configurationError(
            code: "FFT_SIZE_OUT_OF_RANGE",
            message: "FFT size out of valid range",
            metadata: ErrorMetadata(
                timestamp: Date(),
                component: "FFTProcessor",
                additionalInfo: [
                    "fftSize": "\(fftSize)",
                    "minSize": "\(kMinFFTSize)",
                    "maxSize": "\(kMaxFFTSize)"
                ]
            )
        ))
    }
    
    return .success(())
}

// MARK: - Supporting Types

public struct SpectralData {
    let magnitude: [Float]
    let fftSize: Int
    let hopSize: Int
}

public enum SpectralEffect {
    case normalize
    case smooth(factor: Float)
}

// MARK: - Lock Extension

private extension NSLock {
    func synchronized<T>(_ block: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try block()
    }
}