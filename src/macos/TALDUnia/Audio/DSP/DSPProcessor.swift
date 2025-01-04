//
// DSPProcessor.swift
// TALD UNIA
//
// High-performance DSP processor implementation with SIMD optimizations
// Version: 1.0.0
//

import Foundation // macOS 13.0+
import Accelerate // macOS 13.0+
import simd // macOS 13.0+

// MARK: - Global Constants

private let kDefaultBufferSize: Int = 1024
private let kMaxChannels: Int = 8
private let kSIMDAlignment: Int = 16
private let kProcessingQueueQoS: DispatchQoS = .userInteractive
private let kMaxLatencyMs: Double = 10.0

// MARK: - Processing Metrics

private struct ProcessingMetrics {
    var averageLatency: Double = 0.0
    var peakLatency: Double = 0.0
    var processingLoad: Double = 0.0
    var bufferUtilization: Double = 0.0
    var timestamp: Date = Date()
    
    mutating func update(latency: Double, load: Double) {
        averageLatency = (averageLatency + latency) / 2.0
        peakLatency = max(peakLatency, latency)
        processingLoad = load
        timestamp = Date()
    }
}

// MARK: - DSP Configuration

private struct DSPConfiguration {
    let bufferSize: Int
    let channels: Int
    let sampleRate: Double
    let isOptimized: Bool
    let useHardwareAcceleration: Bool
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
    
    func get() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

// MARK: - Buffer Validation

@inline(__always)
public func validateBufferConfiguration(bufferSize: Int, channels: Int) -> Result<Void, TALDError> {
    // Verify buffer size is power of 2
    if (bufferSize & (bufferSize - 1)) != 0 {
        return .failure(TALDError.audioProcessingError(
            code: "INVALID_BUFFER_SIZE",
            message: "Buffer size must be power of 2",
            metadata: ErrorMetadata(
                timestamp: Date(),
                component: "DSPProcessor",
                additionalInfo: ["bufferSize": "\(bufferSize)"]
            )
        ))
    }
    
    // Check channel count
    if channels <= 0 || channels > kMaxChannels {
        return .failure(TALDError.audioProcessingError(
            code: "INVALID_CHANNEL_COUNT",
            message: "Invalid channel count",
            metadata: ErrorMetadata(
                timestamp: Date(),
                component: "DSPProcessor",
                additionalInfo: ["channels": "\(channels)"]
            )
        ))
    }
    
    return .success(())
}

// MARK: - DSP Processor Implementation

@objc
@dynamicMemberLookup
public class DSPProcessor {
    // MARK: - Properties
    
    private let kernel: DSPKernel
    private let vectorDSP: VectorDSP
    private let processingQueue: DispatchQueue
    private let bufferSize: Int
    private let channels: Int
    private let sampleRate: Double
    private var isProcessing: Bool = false
    private var metrics: ProcessingMetrics = ProcessingMetrics()
    private let activeBuffers: AtomicInteger = AtomicInteger()
    private let configuration: DSPConfiguration
    
    // MARK: - Initialization
    
    public init(config: DSPConfiguration) throws {
        // Validate configuration
        guard case .success = validateBufferConfiguration(
            bufferSize: config.bufferSize,
            channels: config.channels
        ) else {
            throw TALDError.configurationError(
                code: "INVALID_CONFIG",
                message: "Invalid DSP configuration",
                metadata: ErrorMetadata(
                    timestamp: Date(),
                    component: "DSPProcessor",
                    additionalInfo: [
                        "bufferSize": "\(config.bufferSize)",
                        "channels": "\(config.channels)"
                    ]
                )
            )
        }
        
        self.configuration = config
        self.bufferSize = config.bufferSize
        self.channels = config.channels
        self.sampleRate = config.sampleRate
        
        // Initialize processing components
        self.kernel = try DSPKernel(sampleRate: sampleRate, channels: channels)
        self.vectorDSP = VectorDSP(size: bufferSize, enableOptimization: config.isOptimized)
        
        // Configure processing queue
        self.processingQueue = DispatchQueue(
            label: "com.tald.unia.dsp.processor",
            qos: kProcessingQueueQoS,
            attributes: .concurrent
        )
    }
    
    // MARK: - Audio Processing
    
    public func process(
        _ input: UnsafePointer<Float>,
        _ output: UnsafeMutablePointer<Float>,
        frameCount: Int
    ) -> Result<ProcessingMetrics, TALDError> {
        let startTime = Date()
        let activeCount = activeBuffers.increment()
        defer { activeBuffers.decrement() }
        
        // Validate buffer alignment
        guard input.alignedPointer(to: Float.self, alignment: kSIMDAlignment) != nil,
              output.alignedPointer(to: Float.self, alignment: kSIMDAlignment) != nil else {
            return .failure(TALDError.audioProcessingError(
                code: "BUFFER_ALIGNMENT",
                message: "Buffers not aligned for SIMD operations",
                metadata: ErrorMetadata(
                    timestamp: Date(),
                    component: "DSPProcessor",
                    additionalInfo: ["frameCount": "\(frameCount)"]
                )
            ))
        }
        
        // Process through vector DSP
        let vectorResult = vectorDSP.processBuffer(AudioBuffer(input, frameCount: frameCount))
        guard case .success = vectorResult else {
            return .failure(TALDError.audioProcessingError(
                code: "VECTOR_PROCESSING",
                message: "Vector DSP processing failed",
                metadata: ErrorMetadata(
                    timestamp: Date(),
                    component: "DSPProcessor",
                    additionalInfo: ["frameCount": "\(frameCount)"]
                )
            ))
        }
        
        // Process through DSP kernel
        kernel.process(input, output, frameCount)
        
        // Update metrics
        let processingTime = Date().timeIntervalSince(startTime)
        metrics.update(
            latency: processingTime,
            load: Double(activeCount) / Double(kMaxChannels)
        )
        
        // Validate latency requirement
        if processingTime > kMaxLatencyMs / 1000.0 {
            return .failure(TALDError.audioProcessingError(
                code: "EXCESSIVE_LATENCY",
                message: "Processing latency exceeded threshold",
                metadata: ErrorMetadata(
                    timestamp: Date(),
                    component: "DSPProcessor",
                    additionalInfo: [
                        "latency": "\(processingTime * 1000.0)ms",
                        "threshold": "\(kMaxLatencyMs)ms"
                    ]
                )
            ))
        }
        
        return .success(metrics)
    }
    
    // MARK: - Parameter Control
    
    public func setParameter(_ parameter: Int, value: Float) -> Result<Void, TALDError> {
        processingQueue.async {
            self.kernel.setParameter(parameter, value)
        }
        return .success(())
    }
    
    // MARK: - State Management
    
    public func reset() {
        processingQueue.async {
            self.kernel.reset()
            self.metrics = ProcessingMetrics()
            self.isProcessing = false
        }
    }
}