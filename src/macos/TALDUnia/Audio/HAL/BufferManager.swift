//
// BufferManager.swift
// TALD UNIA
//
// High-performance audio buffer management with hardware optimization
// Version: 1.0.0
//

import Foundation // macOS 13.0+
import CoreAudio // macOS 13.0+
import Atomics // 1.0.0+

// MARK: - Global Constants

/// Default number of buffers in the pool
private let kDefaultBufferCount: Int = 3

/// Maximum allowed buffer size
private let kMaxBufferSize: Int = AudioConstants.BUFFER_SIZE * 2

/// Minimum allowed buffer size
private let kMinBufferSize: Int = 64

/// Optimal buffer sizes for different scenarios
private let kOptimalBufferSizes: [Int] = [64, 128, 256, 512, 1024]

// MARK: - Buffer Metrics

/// Structure to track buffer performance metrics
private struct BufferMetrics {
    var averageLatency: Double = 0.0
    var peakLatency: Double = 0.0
    var underruns: Int = 0
    var overruns: Int = 0
    var utilizationPercentage: Double = 0.0
    var lastUpdateTime: Date = Date()
}

// MARK: - Buffer Manager

@objc public class BufferManager {
    // MARK: - Properties
    
    /// High-priority queue for buffer operations
    private let bufferQueue: DispatchQueue
    
    /// Thread-safe reference to input buffers
    private let inputBuffers: AtomicReference<[CircularAudioBuffer]>
    
    /// Thread-safe reference to output buffers
    private let outputBuffers: AtomicReference<[CircularAudioBuffer]>
    
    /// Current buffer size
    private let currentBufferSize: AtomicInteger
    
    /// Current channel count
    private let channelCount: AtomicInteger
    
    /// Performance metrics
    private var metrics: BufferMetrics
    
    /// Performance monitoring timer
    private var monitoringTimer: DispatchSourceTimer?
    
    // MARK: - Initialization
    
    /// Initializes the buffer manager with hardware-optimized configuration
    /// - Parameters:
    ///   - initialBufferSize: Initial buffer size in frames
    ///   - channels: Number of audio channels
    ///   - deviceID: Audio device identifier for hardware optimization
    public init(initialBufferSize: Int = AudioConstants.BUFFER_SIZE,
                channels: Int = AudioConstants.MAX_CHANNELS,
                deviceID: AudioDeviceID) {
        
        // Initialize atomic properties
        self.currentBufferSize = AtomicInteger(initialBufferSize)
        self.channelCount = AtomicInteger(channels)
        self.metrics = BufferMetrics()
        
        // Create high-priority buffer queue
        self.bufferQueue = DispatchQueue(
            label: "com.tald.unia.buffer.manager",
            qos: .userInteractive,
            attributes: .concurrent
        )
        
        // Initialize buffer pools
        self.inputBuffers = AtomicReference([])
        self.outputBuffers = AtomicReference([])
        
        // Configure initial buffers
        configureBuffers(deviceID: deviceID, config: BufferConfiguration(
            size: initialBufferSize,
            count: kDefaultBufferCount,
            channels: channels
        ))
        
        // Setup performance monitoring
        setupPerformanceMonitoring()
    }
    
    deinit {
        monitoringTimer?.cancel()
    }
    
    // MARK: - Buffer Configuration
    
    /// Configures buffer pools with hardware-specific optimizations
    /// - Parameters:
    ///   - deviceID: Audio device identifier
    ///   - config: Buffer configuration parameters
    /// - Returns: Result indicating success or error
    @discardableResult
    public func configureBuffers(deviceID: AudioDeviceID, config: BufferConfiguration) -> Result<Void, Error> {
        // Validate configuration
        guard config.size >= kMinBufferSize && config.size <= kMaxBufferSize else {
            return .failure(TALDError.audioProcessingError(
                code: "INVALID_BUFFER_SIZE",
                message: "Buffer size out of valid range",
                metadata: ErrorMetadata(
                    timestamp: Date(),
                    component: "BufferManager",
                    additionalInfo: ["size": "\(config.size)"]
                )
            ))
        }
        
        // Allocate input buffers
        var newInputBuffers: [CircularAudioBuffer] = []
        for _ in 0..<config.count {
            let result = allocateBuffer(
                size: config.size,
                channels: config.channels,
                deviceID: deviceID
            )
            
            switch result {
            case .success(let buffer):
                newInputBuffers.append(buffer)
            case .failure(let error):
                return .failure(error)
            }
        }
        
        // Allocate output buffers
        var newOutputBuffers: [CircularAudioBuffer] = []
        for _ in 0..<config.count {
            let result = allocateBuffer(
                size: config.size,
                channels: config.channels,
                deviceID: deviceID
            )
            
            switch result {
            case .success(let buffer):
                newOutputBuffers.append(buffer)
            case .failure(let error):
                return .failure(error)
            }
        }
        
        // Update atomic references
        inputBuffers.store(newInputBuffers)
        outputBuffers.store(newOutputBuffers)
        currentBufferSize.store(config.size)
        channelCount.store(config.channels)
        
        return .success(())
    }
    
    // MARK: - Buffer Allocation
    
    /// Allocates a new audio buffer with specified parameters and hardware optimization
    /// - Parameters:
    ///   - size: Buffer size in frames
    ///   - channels: Number of channels
    ///   - deviceID: Audio device identifier
    /// - Returns: Result containing new buffer or error
    @inlinable
    private func allocateBuffer(size: Int, channels: Int, deviceID: AudioDeviceID) -> Result<CircularAudioBuffer, Error> {
        // Validate parameters
        guard size >= kMinBufferSize && size <= kMaxBufferSize else {
            return .failure(TALDError.audioProcessingError(
                code: "INVALID_BUFFER_SIZE",
                message: "Buffer size out of valid range",
                metadata: ErrorMetadata(
                    timestamp: Date(),
                    component: "BufferManager",
                    additionalInfo: ["size": "\(size)"]
                )
            ))
        }
        
        // Create optimized buffer
        let buffer = CircularAudioBuffer(capacity: size, channels: channels)
        return .success(buffer)
    }
    
    // MARK: - Performance Monitoring
    
    /// Sets up performance monitoring timer
    private func setupPerformanceMonitoring() {
        monitoringTimer = DispatchSource.makeTimerSource(queue: bufferQueue)
        monitoringTimer?.schedule(deadline: .now(), repeating: .milliseconds(100))
        monitoringTimer?.setEventHandler { [weak self] in
            self?.updateMetrics()
        }
        monitoringTimer?.resume()
    }
    
    /// Updates buffer performance metrics
    private func updateMetrics() {
        let inputBuffers = self.inputBuffers.load()
        let outputBuffers = self.outputBuffers.load()
        
        var totalUtilization: Double = 0
        var maxLatency: Double = 0
        var underruns = 0
        var overruns = 0
        
        // Collect metrics from input buffers
        for buffer in inputBuffers {
            let stats = buffer.currentStatistics
            totalUtilization += stats.utilizationPercentage
            maxLatency = max(maxLatency, stats.peakLatency)
            underruns += stats.underruns
            overruns += stats.overflows
        }
        
        // Collect metrics from output buffers
        for buffer in outputBuffers {
            let stats = buffer.currentStatistics
            totalUtilization += stats.utilizationPercentage
            maxLatency = max(maxLatency, stats.peakLatency)
            underruns += stats.underruns
            overruns += stats.overflows
        }
        
        // Update metrics
        metrics.utilizationPercentage = totalUtilization / Double(inputBuffers.count + outputBuffers.count)
        metrics.peakLatency = maxLatency
        metrics.underruns = underruns
        metrics.overruns = overruns
        metrics.lastUpdateTime = Date()
    }
    
    // MARK: - Public Interface
    
    /// Returns current buffer performance metrics
    @objc public func monitorPerformance() -> BufferMetrics {
        return metrics
    }
}

// MARK: - Supporting Types

/// Configuration parameters for buffer setup
private struct BufferConfiguration {
    let size: Int
    let count: Int
    let channels: Int
}