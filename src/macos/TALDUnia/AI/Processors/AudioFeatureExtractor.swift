//
// AudioFeatureExtractor.swift
// TALD UNIA
//
// High-performance audio feature extraction for AI model input with ESS ES9038PRO DAC optimization
// Version: 1.0.0
//

import Foundation // macOS 13.0+
import Accelerate // macOS 13.0+
import simd // macOS 13.0+

// MARK: - Global Constants

private let kFeatureFrameSize: Int = 1024
private let kFeatureOverlap: Float = 0.5
private let kMinFeatureValue: Float = -80.0
private let kMaxFeatureValue: Float = 0.0
private let kMaxChannels: Int = 8
private let kHardwareBufferAlignment: Int = 16
private let kMaxLatencyMs: Double = 10.0
private let kQualityThreshold: Double = 0.0005

// MARK: - Performance Monitoring

private struct PerformanceMetrics {
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

// MARK: - Hardware Configuration

private struct HardwareConfig {
    let bufferSize: Int
    let bitDepth: Int
    let useI2S: Bool
    let optimizeForDAC: Bool
    
    static let ess9038Pro = HardwareConfig(
        bufferSize: 256,
        bitDepth: 32,
        useI2S: true,
        optimizeForDAC: true
    )
}

// MARK: - Feature Extraction Implementation

@objc
public class AudioFeatureExtractor {
    // MARK: - Properties
    
    private let fftProcessor: FFTProcessor
    private let frameSize: Int
    private let overlap: Float
    private let featureBuffer: UnsafeMutablePointer<Float>
    private var isProcessing: Bool = false
    private let activeChannels: AtomicInteger
    private var metrics: PerformanceMetrics
    private let dacConfig: HardwareConfig
    private let processingQueue: DispatchQueue
    private let lock = NSLock()
    
    // MARK: - Initialization
    
    public init(frameSize: Int = kFeatureFrameSize,
                overlap: Float = kFeatureOverlap,
                dacConfig: HardwareConfig = .ess9038Pro) throws {
        
        self.frameSize = frameSize
        self.overlap = overlap
        self.dacConfig = dacConfig
        self.metrics = PerformanceMetrics()
        self.activeChannels = AtomicInteger()
        
        // Initialize FFT processor
        self.fftProcessor = try FFTProcessor(fftSize: frameSize, overlapFactor: overlap)
        
        // Allocate aligned feature buffer
        guard let buffer = UnsafeMutablePointer<Float>.allocate(capacity: frameSize)
            .alignedPointer(to: Float.self, alignment: kHardwareBufferAlignment) else {
            throw TALDError.audioProcessingError(
                code: "BUFFER_ALLOCATION_FAILED",
                message: "Failed to allocate aligned feature buffer",
                metadata: ErrorMetadata(
                    timestamp: Date(),
                    component: "AudioFeatureExtractor",
                    additionalInfo: ["frameSize": "\(frameSize)"]
                )
            )
        }
        self.featureBuffer = buffer
        
        // Configure processing queue
        self.processingQueue = DispatchQueue(
            label: "com.tald.unia.feature.extractor",
            qos: .userInteractive,
            attributes: .concurrent
        )
    }
    
    deinit {
        featureBuffer.deallocate()
    }
    
    // MARK: - Feature Extraction
    
    public func extractFeatures(_ inputBuffer: AudioBuffer,
                              channel: Int) -> Result<[Float], TALDError> {
        let startTime = Date()
        let activeCount = activeChannels.increment()
        defer { activeChannels.decrement() }
        
        return lock.synchronized {
            // Validate input
            guard channel >= 0 && channel < kMaxChannels else {
                return .failure(TALDError.audioProcessingError(
                    code: "INVALID_CHANNEL",
                    message: "Invalid channel index",
                    metadata: ErrorMetadata(
                        timestamp: Date(),
                        component: "AudioFeatureExtractor",
                        additionalInfo: ["channel": "\(channel)"]
                    )
                ))
            }
            
            // Extract temporal features
            var features = [Float](repeating: 0.0, count: frameSize)
            
            guard case .success = inputBuffer.read(featureBuffer, frameCount: frameSize) else {
                return .failure(TALDError.audioProcessingError(
                    code: "BUFFER_READ_ERROR",
                    message: "Failed to read from input buffer",
                    metadata: ErrorMetadata(
                        timestamp: Date(),
                        component: "AudioFeatureExtractor",
                        additionalInfo: ["frameSize": "\(frameSize)"]
                    )
                ))
            }
            
            // Calculate RMS energy
            var rms: Float = 0.0
            vDSP_rmsqv(featureBuffer, 1, &rms, vDSP_Length(frameSize))
            features[0] = rms
            
            // Calculate zero crossing rate
            var zcr: Float = 0.0
            vDSP_vzcr(featureBuffer, 1, &zcr, vDSP_Length(frameSize))
            features[1] = zcr
            
            // Apply hardware-specific optimization
            if dacConfig.optimizeForDAC {
                normalizeFeatures(featureBuffer, count: frameSize)
            }
            
            // Update performance metrics
            let processingTime = Date().timeIntervalSince(startTime)
            metrics.update(
                latency: processingTime,
                load: Double(activeCount) / Double(kMaxChannels)
            )
            
            // Validate processing latency
            if processingTime > kMaxLatencyMs / 1000.0 {
                return .failure(TALDError.audioProcessingError(
                    code: "EXCESSIVE_LATENCY",
                    message: "Feature extraction exceeded latency threshold",
                    metadata: ErrorMetadata(
                        timestamp: Date(),
                        component: "AudioFeatureExtractor",
                        additionalInfo: [
                            "processingTime": "\(processingTime * 1000)ms",
                            "threshold": "\(kMaxLatencyMs)ms"
                        ]
                    )
                ))
            }
            
            return .success(features)
        }
    }
    
    public func extractSpectralFeatures(_ inputBuffer: AudioBuffer,
                                      channel: Int) -> Result<[Float], TALDError> {
        let startTime = Date()
        
        return lock.synchronized {
            // Process FFT spectrum
            var spectralFeatures = [Float](repeating: 0.0, count: frameSize / 2)
            
            let fftResult = fftProcessor.processSpectrum(
                featureBuffer,
                &spectralFeatures,
                frameCount: frameSize
            )
            
            guard case .success = fftResult else {
                return .failure(TALDError.audioProcessingError(
                    code: "FFT_PROCESSING_FAILED",
                    message: "Failed to process FFT spectrum",
                    metadata: ErrorMetadata(
                        timestamp: Date(),
                        component: "AudioFeatureExtractor",
                        additionalInfo: ["frameSize": "\(frameSize)"]
                    )
                ))
            }
            
            // Calculate spectral centroid
            var centroid: Float = 0.0
            vDSP_normalize(spectralFeatures, 1, &spectralFeatures, 1, &centroid, vDSP_Length(frameSize / 2))
            
            // Calculate spectral flatness
            var flatness: Float = 0.0
            vDSP_vflt(spectralFeatures, 1, &flatness, vDSP_Length(frameSize / 2))
            
            // Update metrics
            let processingTime = Date().timeIntervalSince(startTime)
            metrics.update(
                latency: processingTime,
                load: Double(frameSize) / Double(dacConfig.bufferSize)
            )
            
            return .success(spectralFeatures)
        }
    }
    
    public func reset() {
        lock.synchronized {
            isProcessing = false
            featureBuffer.initialize(repeating: 0.0, count: frameSize)
            metrics = PerformanceMetrics()
        }
    }
}

// MARK: - Feature Normalization

@inline(__always)
private func normalizeFeatures(_ features: UnsafeMutablePointer<Float>, count: Int) {
    // Calculate min/max using SIMD
    var minValue: Float = 0.0
    var maxValue: Float = 0.0
    vDSP_minv(features, 1, &minValue, vDSP_Length(count))
    vDSP_maxv(features, 1, &maxValue, vDSP_Length(count))
    
    // Apply normalization with hardware acceleration
    let scale = 1.0 / (maxValue - minValue)
    vDSP_vsmul(features, 1, &scale, features, 1, vDSP_Length(count))
    
    // Clip to valid range
    var lowerBound = kMinFeatureValue
    var upperBound = kMaxFeatureValue
    vDSP_vclip(features, 1, &lowerBound, &upperBound, features, 1, vDSP_Length(count))
}

// MARK: - Atomic Operations

private class AtomicInteger {
    private let lock = NSLock()
    private var value: Int = 0
    
    func increment() -> Int {
        lock.lock()
        defer { lock.unlock() }
        value += 1
        return value
    }
    
    func decrement() -> Int {
        lock.lock()
        defer { lock.unlock() }
        value -= 1
        return value
    }
}

// MARK: - Lock Extension

private extension NSLock {
    func synchronized<T>(_ block: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try block()
    }
}