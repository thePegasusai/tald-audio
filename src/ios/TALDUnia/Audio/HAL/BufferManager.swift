// Foundation v17.0+
import Foundation
import AVFoundation

/// Constants for buffer management and optimization
private enum BufferConstants {
    static let kDefaultBufferSize: Int = 256
    static let kMaxBufferSize: Int = 1024
    static let kMinBufferSize: Int = 64
    static let kPreferredBufferSizes: [Int] = [64, 128, 256, 512, 1024]
    static let kBufferAlignment: Int = 16
    static let kMonitoringInterval: TimeInterval = 0.001
    static let kOptimizationThreshold: Double = 0.8
}

/// Metrics for monitoring buffer performance
public struct BufferMetrics {
    let utilizationRate: Double
    let underrunRisk: Double
    let latency: TimeInterval
    let memoryUsage: Int64
    let thermalState: ProcessInfo.ThermalState
    let timestamp: Date
}

/// High-performance buffer management system for TALD UNIA audio HAL
@objc public class BufferManager: NSObject {
    
    // MARK: - Properties
    
    /// Current buffer size in frames
    public private(set) var currentBufferSize: Int
    
    /// Input audio buffer
    private var inputBuffer: AudioBuffer
    
    /// Output audio buffer
    private var outputBuffer: AudioBuffer
    
    /// Thread-safe queue for buffer operations
    private let bufferQueue: DispatchQueue
    
    /// Indicates if buffer system is properly configured
    public private(set) var isBufferConfigured: Bool
    
    /// Current buffer performance metrics
    private var currentMetrics: BufferMetrics
    
    /// Atomic state for thread-safe buffer operations
    private var bufferState: UInt64
    
    /// Memory pool for efficient buffer allocation
    private var memoryPool: [AudioBuffer]
    
    /// Performance monitoring timer
    private var monitoringTimer: DispatchSourceTimer?
    
    // MARK: - Initialization
    
    /// Initializes the BufferManager with optimal configuration
    /// - Parameter initialBufferSize: Optional initial buffer size (defaults to system optimal)
    public init(initialBufferSize: Int? = nil) throws {
        // Initialize properties
        let requestedSize = initialBufferSize ?? AudioConstants.bufferSize
        self.currentBufferSize = requestedSize
        self.isBufferConfigured = false
        self.bufferState = 0
        self.memoryPool = []
        
        // Initialize metrics
        self.currentMetrics = BufferMetrics(
            utilizationRate: 0.0,
            underrunRisk: 0.0,
            latency: 0.0,
            memoryUsage: 0,
            thermalState: .nominal,
            timestamp: Date()
        )
        
        // Create high-priority queue for buffer operations
        self.bufferQueue = DispatchQueue(
            label: "com.taldunia.audio.buffer.manager",
            qos: .userInteractive,
            attributes: .concurrent
        )
        
        // Initialize base audio format
        let format = try AudioFormat(
            sampleRate: AudioConstants.sampleRate,
            bitDepth: AudioConstants.bitDepth,
            channels: AudioConstants.channelCount,
            interleaved: true
        )
        
        // Initialize buffers
        self.inputBuffer = try AudioBuffer(format: format, bufferSize: requestedSize)
        self.outputBuffer = try AudioBuffer(format: format, bufferSize: requestedSize)
        
        super.init()
        
        // Validate initial configuration
        try validateBufferConfiguration(bufferSize: requestedSize, sampleRate: AudioConstants.sampleRate)
            .get()
        
        // Setup performance monitoring
        setupPerformanceMonitoring()
        
        self.isBufferConfigured = true
    }
    
    deinit {
        monitoringTimer?.cancel()
    }
    
    // MARK: - Buffer Configuration
    
    /// Validates buffer configuration parameters for optimal performance
    /// - Parameters:
    ///   - bufferSize: Buffer size to validate
    ///   - sampleRate: Sample rate to validate against
    /// - Returns: Validation result or error
    private func validateBufferConfiguration(bufferSize: Int, sampleRate: Int) -> Result<Bool, Error> {
        // Check size range
        guard bufferSize >= BufferConstants.kMinBufferSize &&
              bufferSize <= BufferConstants.kMaxBufferSize else {
            return .failure(AppError.audioError(
                reason: "Buffer size out of supported range",
                severity: .error,
                context: ErrorContext(additionalInfo: [
                    "requestedSize": bufferSize,
                    "minSize": BufferConstants.kMinBufferSize,
                    "maxSize": BufferConstants.kMaxBufferSize
                ])
            ))
        }
        
        // Verify power of 2
        let isPowerOfTwo = (bufferSize & (bufferSize - 1)) == 0
        guard isPowerOfTwo else {
            return .failure(AppError.audioError(
                reason: "Buffer size must be power of 2",
                severity: .error,
                context: ErrorContext(additionalInfo: [
                    "requestedSize": bufferSize
                ])
            ))
        }
        
        // Calculate latency impact
        let latencyMs = (Double(bufferSize) / Double(sampleRate)) * 1000.0
        guard latencyMs <= AudioConstants.maxLatency * 1000.0 else {
            return .failure(AppError.audioError(
                reason: "Buffer configuration exceeds latency requirements",
                severity: .error,
                context: ErrorContext(additionalInfo: [
                    "calculatedLatency": latencyMs,
                    "maxLatency": AudioConstants.maxLatency * 1000.0
                ])
            ))
        }
        
        return .success(true)
    }
    
    // MARK: - Buffer Management
    
    /// Resizes audio buffers while maintaining processing continuity
    /// - Parameter newSize: New buffer size
    /// - Returns: Success or error
    public func resizeBuffers(newSize: Int) -> Result<Void, Error> {
        var result: Result<Void, Error> = .success(())
        
        bufferQueue.sync(flags: .barrier) {
            // Validate new size
            guard case .success = validateBufferConfiguration(
                bufferSize: newSize,
                sampleRate: AudioConstants.sampleRate
            ) else {
                result = .failure(AppError.audioError(
                    reason: "Invalid buffer size for resize operation",
                    severity: .error,
                    context: ErrorContext(additionalInfo: [
                        "requestedSize": newSize
                    ])
                ))
                return
            }
            
            do {
                // Create temporary buffers
                let tempInput = try AudioBuffer(
                    format: inputBuffer.format,
                    bufferSize: newSize
                )
                let tempOutput = try AudioBuffer(
                    format: outputBuffer.format,
                    bufferSize: newSize
                )
                
                // Update atomic state
                OSAtomicIncrement64(&bufferState)
                
                // Swap buffers
                memoryPool.append(inputBuffer)
                memoryPool.append(outputBuffer)
                inputBuffer = tempInput
                outputBuffer = tempOutput
                currentBufferSize = newSize
                
                // Update metrics
                updatePerformanceMetrics()
                
            } catch {
                result = .failure(error)
            }
        }
        
        return result
    }
    
    /// Optimizes buffer size based on current system performance
    /// - Returns: Recommended buffer size
    public func optimizeBufferSize() -> Int {
        let metrics = monitorBufferPerformance()
        
        // Check thermal state
        if metrics.thermalState == .serious || metrics.thermalState == .critical {
            return min(currentBufferSize * 2, BufferConstants.kMaxBufferSize)
        }
        
        // Check utilization
        if metrics.utilizationRate > BufferConstants.kOptimizationThreshold {
            return min(currentBufferSize * 2, BufferConstants.kMaxBufferSize)
        }
        
        // Check underrun risk
        if metrics.underrunRisk > 0.2 {
            return min(currentBufferSize * 2, BufferConstants.kMaxBufferSize)
        }
        
        // Check if we can reduce size
        if metrics.latency > AudioConstants.maxLatency / 2 {
            return max(currentBufferSize / 2, BufferConstants.kMinBufferSize)
        }
        
        return currentBufferSize
    }
    
    // MARK: - Performance Monitoring
    
    /// Sets up periodic performance monitoring
    private func setupPerformanceMonitoring() {
        monitoringTimer = DispatchSource.makeTimerSource(queue: bufferQueue)
        monitoringTimer?.schedule(
            deadline: .now(),
            repeating: BufferConstants.kMonitoringInterval
        )
        
        monitoringTimer?.setEventHandler { [weak self] in
            self?.updatePerformanceMetrics()
        }
        
        monitoringTimer?.resume()
    }
    
    /// Updates current performance metrics
    private func updatePerformanceMetrics() {
        let processInfo = ProcessInfo.processInfo
        
        currentMetrics = BufferMetrics(
            utilizationRate: Double(inputBuffer.pcmBuffer?.frameLength ?? 0) / Double(currentBufferSize),
            underrunRisk: calculateUnderrunRisk(),
            latency: Double(currentBufferSize) / Double(AudioConstants.sampleRate),
            memoryUsage: Int64(memoryPool.count * MemoryLayout<AudioBuffer>.size),
            thermalState: processInfo.thermalState,
            timestamp: Date()
        )
    }
    
    /// Monitors buffer performance metrics in real-time
    /// - Returns: Current buffer performance metrics
    public func monitorBufferPerformance() -> BufferMetrics {
        return currentMetrics
    }
    
    /// Calculates risk of buffer underrun based on current metrics
    private func calculateUnderrunRisk() -> Double {
        let utilizationTrend = currentMetrics.utilizationRate
        let thermalImpact = currentMetrics.thermalState == .nominal ? 0.0 : 0.3
        let memoryPressure = Double(currentMetrics.memoryUsage) / Double(ProcessInfo.processInfo.physicalMemory)
        
        return min(1.0, utilizationTrend + thermalImpact + memoryPressure)
    }
}