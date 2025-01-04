//
// SpatialEngine.swift
// TALD UNIA
//
// Core spatial audio engine with ESS ES9038PRO DAC optimization
// Version: 1.0.0
//

import Foundation // macOS 13.0+
import Accelerate // macOS 13.0+
import simd // macOS 13.0+

// MARK: - Global Constants

private let kDefaultUpdateRate: Double = 60.0
private let kMaxSources: Int = 32
private let kDefaultRoomPreset: String = "studio"
private let kOptimalBufferSize: Int = 256
private let kMaxLatencyMs: Double = 10.0
private let kDACOptimalSettings: [String: Any] = [
    "bitDepth": 32,
    "sampleRate": 192000,
    "bufferSize": 256,
    "channelCount": 2
]

// MARK: - Supporting Types

public struct SpatialParameters {
    let sourcePositions: [SIMD3<Float>]
    let listenerPosition: SIMD3<Float>
    let listenerOrientation: SIMD3<Float>
    let roomDimensions: RoomDimensions
}

public struct PerformanceMetrics {
    var averageLatency: Double = 0.0
    var peakLatency: Double = 0.0
    var processingLoad: Double = 0.0
    var thdPlusNoise: Double = 0.0
    var lastUpdateTime: Date = Date()
}

// MARK: - Spatial Engine Implementation

@objc
@available(macOS 13.0, *)
public final class SpatialEngine {
    // MARK: - Properties
    
    private let hrtfProcessor: HRTFProcessor
    private let roomModeling: RoomModeling
    private let headTracker: HeadTracker
    private let processingQueue: DispatchQueue
    private let monitor: PerformanceMonitor
    private let lock = NSLock()
    
    private var isActive: Bool = false
    private var sampleRate: Float
    private var dacConfig: [String: Any]
    private var activeProcesses: AtomicInteger
    private var audioBufferPool: CircularAudioBuffer
    
    // MARK: - Initialization
    
    public init(sampleRate: Float = Float(AudioConstants.SAMPLE_RATE),
                dacConfig: [String: Any] = kDACOptimalSettings) throws {
        self.sampleRate = sampleRate
        self.dacConfig = dacConfig
        self.activeProcesses = AtomicInteger()
        
        // Initialize processing components
        self.hrtfProcessor = try HRTFProcessor(
            sampleRate: sampleRate,
            quality: .premium,
            config: SpatialConstants.SPATIAL_CONFIG
        )
        
        // Initialize room modeling
        let dimensions = RoomDimensions(width: 10.0, length: 8.0, height: 3.0)
        let absorption = [0.3, 0.3, 0.3, 0.3, 0.3, 0.3] // Default absorption coefficients
        self.roomModeling = try RoomModeling(
            dimensions: dimensions,
            absorption: absorption,
            config: .ess9038Pro
        )
        
        // Initialize head tracking
        self.headTracker = HeadTracker()
        
        // Initialize processing queue
        self.processingQueue = DispatchQueue(
            label: "com.tald.unia.spatial.engine",
            qos: .userInteractive,
            attributes: .concurrent
        )
        
        // Initialize buffer pool
        self.audioBufferPool = CircularAudioBuffer(
            capacity: kOptimalBufferSize,
            channels: 2
        )
        
        // Initialize performance monitoring
        self.monitor = PerformanceMonitor()
        
        // Validate DAC configuration
        try validateDACConfiguration()
    }
    
    // MARK: - Public Interface
    
    public func start() -> Result<Bool, TALDError> {
        return lock.synchronized {
            guard !isActive else { return .success(true) }
            
            // Start head tracking
            guard headTracker.startTracking() else {
                return .failure(TALDError.spatialProcessingError(
                    code: "HEAD_TRACKING_FAILED",
                    message: "Failed to start head tracking",
                    metadata: ErrorMetadata(
                        timestamp: Date(),
                        component: "SpatialEngine",
                        additionalInfo: ["operation": "start"]
                    )
                ))
            }
            
            isActive = true
            return .success(true)
        }
    }
    
    public func processAudioFrame(_ inputBuffer: AudioBuffer,
                                parameters: SpatialParameters) -> Result<AudioBuffer, TALDError> {
        let startTime = Date()
        let processCount = activeProcesses.increment()
        defer { activeProcesses.decrement() }
        
        return lock.synchronized {
            // Validate input
            guard inputBuffer.availableFrames > 0 else {
                return .failure(TALDError.audioProcessingError(
                    code: "INVALID_BUFFER",
                    message: "Empty input buffer",
                    metadata: ErrorMetadata(
                        timestamp: Date(),
                        component: "SpatialEngine",
                        additionalInfo: ["frameCount": "0"]
                    )
                ))
            }
            
            do {
                // Update head tracking
                let orientation = headTracker.getCurrentOrientation()
                
                // Process room acoustics
                let roomResult = try roomModeling.simulateAcoustics(
                    input: inputBuffer.bufferData,
                    output: audioBufferPool.bufferData,
                    frameCount: inputBuffer.availableFrames
                ).get()
                
                // Apply HRTF processing
                for (index, position) in parameters.sourcePositions.enumerated() {
                    let hrtfResult = try hrtfProcessor.processAudio(
                        audioBufferPool,
                        sourcePosition: position,
                        options: ProcessingOptions()
                    ).get()
                    
                    // Mix processed audio
                    try calculateSpatialMix(
                        inputBuffer: hrtfResult,
                        sourcePositions: parameters.sourcePositions,
                        dacConfig: dacConfig
                    )
                }
                
                // Update performance metrics
                let processingTime = Date().timeIntervalSince(startTime)
                monitor.update(
                    latency: processingTime,
                    load: Double(processCount) / Double(ProcessInfo.processInfo.processorCount)
                )
                
                // Validate processing latency
                if processingTime > kMaxLatencyMs / 1000.0 {
                    return .failure(TALDError.spatialProcessingError(
                        code: "EXCESSIVE_LATENCY",
                        message: "Processing exceeded latency threshold",
                        metadata: ErrorMetadata(
                            timestamp: Date(),
                            component: "SpatialEngine",
                            additionalInfo: [
                                "latency": "\(processingTime * 1000)ms",
                                "threshold": "\(kMaxLatencyMs)ms"
                            ]
                        )
                    ))
                }
                
                return .success(audioBufferPool)
                
            } catch {
                return .failure(TALDError.spatialProcessingError(
                    code: "PROCESSING_FAILED",
                    message: "Spatial processing failed: \(error.localizedDescription)",
                    metadata: ErrorMetadata(
                        timestamp: Date(),
                        component: "SpatialEngine",
                        additionalInfo: ["error": error.localizedDescription]
                    )
                ))
            }
        }
    }
    
    // MARK: - Private Methods
    
    private func validateDACConfiguration() throws {
        guard let bitDepth = dacConfig["bitDepth"] as? Int,
              let sampleRate = dacConfig["sampleRate"] as? Int,
              let bufferSize = dacConfig["bufferSize"] as? Int,
              let channelCount = dacConfig["channelCount"] as? Int else {
            throw TALDError.configurationError(
                code: "INVALID_DAC_CONFIG",
                message: "Invalid DAC configuration parameters",
                metadata: ErrorMetadata(
                    timestamp: Date(),
                    component: "SpatialEngine",
                    additionalInfo: ["config": "\(dacConfig)"]
                )
            )
        }
        
        // Validate ESS ES9038PRO requirements
        guard bitDepth == 32 &&
              sampleRate == 192000 &&
              bufferSize == 256 &&
              channelCount == 2 else {
            throw TALDError.configurationError(
                code: "INCOMPATIBLE_DAC_CONFIG",
                message: "DAC configuration not compatible with ESS ES9038PRO",
                metadata: ErrorMetadata(
                    timestamp: Date(),
                    component: "SpatialEngine",
                    additionalInfo: [
                        "bitDepth": "\(bitDepth)",
                        "sampleRate": "\(sampleRate)",
                        "bufferSize": "\(bufferSize)",
                        "channelCount": "\(channelCount)"
                    ]
                )
            )
        }
    }
    
    @inline(__always)
    private func calculateSpatialMix(inputBuffer: AudioBuffer,
                                   sourcePositions: [SIMD3<Float>],
                                   dacConfig: [String: Any]) -> Result<Void, TALDError> {
        // Validate buffer alignment for DAC
        guard inputBuffer.bufferData.alignedPointer(to: Float.self, alignment: 16) != nil else {
            return .failure(TALDError.audioProcessingError(
                code: "BUFFER_ALIGNMENT",
                message: "Buffer not aligned for DAC",
                metadata: ErrorMetadata(
                    timestamp: Date(),
                    component: "SpatialEngine",
                    additionalInfo: ["alignment": "16"]
                )
            ))
        }
        
        // Apply SIMD-optimized mixing
        vDSP_mmul(
            inputBuffer.bufferData,
            1,
            inputBuffer.bufferData,
            1,
            audioBufferPool.bufferData,
            1,
            vDSP_Length(inputBuffer.availableFrames),
            vDSP_Length(2),
            vDSP_Length(1)
        )
        
        return .success(())
    }
}

// MARK: - Supporting Classes

private class PerformanceMonitor {
    private var metrics = PerformanceMetrics()
    private let lock = NSLock()
    
    func update(latency: TimeInterval, load: Double) {
        lock.lock()
        defer { lock.unlock() }
        metrics.averageLatency = (metrics.averageLatency + latency) / 2.0
        metrics.peakLatency = max(metrics.peakLatency, latency)
        metrics.processingLoad = load
        metrics.lastUpdateTime = Date()
    }
}

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