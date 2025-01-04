//
// AudioBuffer.swift
// TALD UNIA
//
// High-performance audio buffer system with real-time monitoring and optimization
// Version: 1.0.0
//

import Foundation // macOS 13.0+
import AVFoundation // macOS 13.0+
import Accelerate // macOS 13.0+
import os.log // macOS 13.0+

// MARK: - Global Constants

private let kDefaultBufferSize: Int = AudioConstants.BUFFER_SIZE
private let kMaxBufferCount: Int = 8
private let kBufferMonitoringInterval: TimeInterval = 0.1
private let kMaxBufferLatency: TimeInterval = 0.010 // 10ms max latency requirement

// MARK: - Buffer Statistics Structure

private struct BufferStatistics {
    var averageLatency: Double = 0.0
    var peakLatency: Double = 0.0
    var underruns: Int = 0
    var overflows: Int = 0
    var utilizationPercentage: Double = 0.0
    var lastUpdateTime: Date = Date()
}

// MARK: - Circular Audio Buffer

@objc public class CircularAudioBuffer {
    // MARK: - Properties
    
    private let bufferData: UnsafeMutablePointer<Float>
    private let capacity: Int
    private let channelCount: Int
    private var readIndex: Int = 0 {
        didSet { readIndex %= capacity }
    }
    private var writeIndex: Int = 0 {
        didSet { writeIndex %= capacity }
    }
    
    private let lock = NSLock()
    private let performanceLog = OSLog(subsystem: "com.tald.unia.audio", category: "BufferPerformance")
    private var statistics = BufferStatistics()
    private let monitoringQueue = DispatchQueue(label: "com.tald.unia.buffer.monitoring", qos: .utility)
    private var performanceMonitor: Timer?
    
    // MARK: - Initialization
    
    public init(capacity: Int = kDefaultBufferSize, channels: Int = AudioConstants.MAX_CHANNELS) {
        guard capacity > 0 && channels > 0 && channels <= AudioConstants.MAX_CHANNELS else {
            fatalError("Invalid buffer configuration: capacity=\(capacity), channels=\(channels)")
        }
        
        self.capacity = capacity
        self.channelCount = channels
        
        // Allocate buffer memory with overflow protection
        let totalSize = capacity * channels
        guard let buffer = UnsafeMutablePointer<Float>.allocate(capacity: totalSize)
            .map({ UnsafeMutablePointer<Float>($0) }) else {
            fatalError("Failed to allocate buffer memory")
        }
        buffer.initialize(repeating: 0.0, count: totalSize)
        self.bufferData = buffer
        
        // Initialize performance monitoring
        setupPerformanceMonitoring()
    }
    
    deinit {
        performanceMonitor?.invalidate()
        bufferData.deallocate()
    }
    
    // MARK: - Buffer Operations
    
    @discardableResult
    public func write(_ data: UnsafePointer<Float>, frameCount: Int) -> Result<Int, TALDError> {
        lock.lock()
        defer { lock.unlock() }
        
        // Validate write operation
        guard frameCount > 0 else {
            return .failure(TALDError.audioProcessingError(
                code: "INVALID_FRAME_COUNT",
                message: "Invalid frame count for write operation",
                metadata: ErrorMetadata(
                    timestamp: Date(),
                    component: "CircularAudioBuffer",
                    additionalInfo: ["frameCount": "\(frameCount)"]
                )
            ))
        }
        
        // Calculate available space
        let availableSpace = capacity - ((writeIndex - readIndex) & (capacity - 1))
        guard frameCount <= availableSpace else {
            statistics.overflows += 1
            os_signpost(.event, log: performanceLog, name: "Buffer Overflow")
            return .failure(TALDError.bufferOverflowError(
                code: "BUFFER_OVERFLOW",
                message: "Buffer overflow detected",
                metadata: ErrorMetadata(
                    timestamp: Date(),
                    component: "CircularAudioBuffer",
                    additionalInfo: [
                        "availableSpace": "\(availableSpace)",
                        "requestedFrames": "\(frameCount)"
                    ]
                )
            ))
        }
        
        // Perform optimized write operation
        let startTime = Date()
        
        let firstCopySize = min(frameCount, capacity - writeIndex)
        let remainingCopySize = frameCount - firstCopySize
        
        // Use SIMD operations for optimized copying
        vDSP_mmov(
            data,
            bufferData.advanced(by: writeIndex * channelCount),
            vDSP_Length(firstCopySize * channelCount),
            vDSP_Length(1),
            vDSP_Length(channelCount),
            vDSP_Length(channelCount)
        )
        
        if remainingCopySize > 0 {
            vDSP_mmov(
                data.advanced(by: firstCopySize * channelCount),
                bufferData,
                vDSP_Length(remainingCopySize * channelCount),
                vDSP_Length(1),
                vDSP_Length(channelCount),
                vDSP_Length(channelCount)
            )
        }
        
        writeIndex = (writeIndex + frameCount) % capacity
        
        // Update performance metrics
        let writeLatency = Date().timeIntervalSince(startTime)
        updatePerformanceMetrics(writeLatency: writeLatency)
        
        return .success(frameCount)
    }
    
    @discardableResult
    public func read(_ outputBuffer: UnsafeMutablePointer<Float>, frameCount: Int) -> Result<Int, TALDError> {
        lock.lock()
        defer { lock.unlock() }
        
        // Validate read operation
        guard frameCount > 0 else {
            return .failure(TALDError.audioProcessingError(
                code: "INVALID_FRAME_COUNT",
                message: "Invalid frame count for read operation",
                metadata: ErrorMetadata(
                    timestamp: Date(),
                    component: "CircularAudioBuffer",
                    additionalInfo: ["frameCount": "\(frameCount)"]
                )
            ))
        }
        
        // Calculate available data
        let availableFrames = (writeIndex - readIndex) & (capacity - 1)
        guard frameCount <= availableFrames else {
            statistics.underruns += 1
            os_signpost(.event, log: performanceLog, name: "Buffer Underrun")
            return .failure(TALDError.bufferUnderrunError(
                code: "BUFFER_UNDERRUN",
                message: "Buffer underrun detected",
                metadata: ErrorMetadata(
                    timestamp: Date(),
                    component: "CircularAudioBuffer",
                    additionalInfo: [
                        "availableFrames": "\(availableFrames)",
                        "requestedFrames": "\(frameCount)"
                    ]
                )
            ))
        }
        
        // Perform optimized read operation
        let startTime = Date()
        
        let firstCopySize = min(frameCount, capacity - readIndex)
        let remainingCopySize = frameCount - firstCopySize
        
        // Use SIMD operations for optimized copying
        vDSP_mmov(
            bufferData.advanced(by: readIndex * channelCount),
            outputBuffer,
            vDSP_Length(firstCopySize * channelCount),
            vDSP_Length(1),
            vDSP_Length(channelCount),
            vDSP_Length(channelCount)
        )
        
        if remainingCopySize > 0 {
            vDSP_mmov(
                bufferData,
                outputBuffer.advanced(by: firstCopySize * channelCount),
                vDSP_Length(remainingCopySize * channelCount),
                vDSP_Length(1),
                vDSP_Length(channelCount),
                vDSP_Length(channelCount)
            )
        }
        
        readIndex = (readIndex + frameCount) % capacity
        
        // Update performance metrics
        let readLatency = Date().timeIntervalSince(startTime)
        updatePerformanceMetrics(readLatency: readLatency)
        
        return .success(frameCount)
    }
    
    // MARK: - Performance Monitoring
    
    private func setupPerformanceMonitoring() {
        performanceMonitor = Timer(timeInterval: kBufferMonitoringInterval, repeats: true) { [weak self] _ in
            self?.monitoringQueue.async {
                self?.updateBufferStatistics()
            }
        }
        RunLoop.main.add(performanceMonitor!, forMode: .common)
    }
    
    private func updatePerformanceMetrics(writeLatency: TimeInterval? = nil, readLatency: TimeInterval? = nil) {
        if let writeLatency = writeLatency {
            statistics.peakLatency = max(statistics.peakLatency, writeLatency)
            statistics.averageLatency = (statistics.averageLatency + writeLatency) / 2.0
        }
        
        if let readLatency = readLatency {
            statistics.peakLatency = max(statistics.peakLatency, readLatency)
            statistics.averageLatency = (statistics.averageLatency + readLatency) / 2.0
        }
        
        // Log if latency exceeds threshold
        if statistics.peakLatency > kMaxBufferLatency {
            os_log(.error, log: performanceLog, "Buffer latency exceeded threshold: %.4f ms", statistics.peakLatency * 1000)
        }
    }
    
    private func updateBufferStatistics() {
        lock.lock()
        defer { lock.unlock() }
        
        let currentUtilization = Double((writeIndex - readIndex) & (capacity - 1)) / Double(capacity)
        statistics.utilizationPercentage = currentUtilization * 100.0
        
        os_signpost(.event, log: performanceLog, name: "Buffer Statistics",
                   "utilization: %.1f%%, latency: %.3fms, underruns: %d, overflows: %d",
                   statistics.utilizationPercentage,
                   statistics.averageLatency * 1000,
                   statistics.underruns,
                   statistics.overflows)
    }
    
    // MARK: - Public Interface
    
    public var currentStatistics: BufferStatistics {
        lock.lock()
        defer { lock.unlock() }
        return statistics
    }
    
    public var availableFrames: Int {
        lock.lock()
        defer { lock.unlock() }
        return (writeIndex - readIndex) & (capacity - 1)
    }
}

// MARK: - Audio Buffer Creation Utility

@discardableResult
public func createAudioBuffer(channelCount: Int = AudioConstants.MAX_CHANNELS,
                            frameCount: Int = kDefaultBufferSize,
                            format: AVAudioFormat) -> Result<AVAudioBuffer, TALDError> {
    // Validate format
    guard format.validateFormat() else {
        return .failure(TALDError.audioProcessingError(
            code: "INVALID_FORMAT",
            message: "Invalid audio format configuration",
            metadata: ErrorMetadata(
                timestamp: Date(),
                component: "AudioBuffer",
                additionalInfo: [
                    "sampleRate": "\(format.sampleRate)",
                    "channelCount": "\(channelCount)"
                ]
            )
        ))
    }
    
    // Create AVAudioPCMBuffer
    guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount)) else {
        return .failure(TALDError.audioProcessingError(
            code: "BUFFER_CREATION_FAILED",
            message: "Failed to create audio buffer",
            metadata: ErrorMetadata(
                timestamp: Date(),
                component: "AudioBuffer",
                additionalInfo: [
                    "frameCount": "\(frameCount)",
                    "channelCount": "\(channelCount)"
                ]
            )
        ))
    }
    
    return .success(buffer)
}