// Foundation v17.0+
import Foundation
import AVFoundation
import Combine
import os.signpost

/// Constants for spatial audio processing
private enum Constants {
    static let kProcessingQueueQoS = DispatchQoS.userInteractive
    static let kQualityMonitoringInterval: TimeInterval = 0.100
    static let kPerformanceSignpostSubsystem = "com.tald.unia.spatial"
    static let kMaxProcessingLatency: TimeInterval = 0.010
    static let kMinQualityThreshold: Float = 0.85
    static let kDefaultRoomSize: Double = 50.0
}

/// Performance metrics for spatial audio processing
public struct PerformanceMetrics {
    var processingLatency: TimeInterval
    var cpuLoad: Double
    var qualityScore: Float
    var bufferUnderruns: Int
    var timestamp: Date
}

/// Current state of the spatial engine
public enum EngineState {
    case initializing
    case processing
    case error(Error)
    case idle
}

/// Enhanced spatial audio processing engine with quality monitoring
@available(iOS 13.0, *)
public class SpatialEngine {
    
    // MARK: - Properties
    
    private let hrtfProcessor: HRTFProcessor
    private let processingQueue: DispatchQueue
    private let stateLock = NSLock()
    private let signposter = OSSignposter()
    
    private var audioFormat: AVAudioFormat
    private var performanceMetrics = PerformanceMetrics(
        processingLatency: 0,
        cpuLoad: 0,
        qualityScore: 1.0,
        bufferUnderruns: 0,
        timestamp: Date()
    )
    
    public let statePublisher = PassthroughSubject<EngineState, Never>()
    private var qualityMonitoringTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    
    /// Initializes spatial engine with enhanced monitoring capabilities
    /// - Parameters:
    ///   - format: Audio format configuration
    ///   - config: Engine configuration
    public init(format: AVAudioFormat, config: EngineConfiguration) throws {
        self.audioFormat = format
        
        // Initialize processing queue with high priority
        self.processingQueue = DispatchQueue(
            label: "com.tald.unia.spatial.engine",
            qos: Constants.kProcessingQueueQoS,
            attributes: []
        )
        
        // Initialize HRTF processor
        do {
            self.hrtfProcessor = try HRTFProcessor(
                format: format,
                roomParams: RoomParameters(
                    size: Constants.kDefaultRoomSize,
                    reverbTime: SpatialConstants.defaultReverbTime
                ),
                quality: .maximum
            )
        } catch {
            throw AppError.spatialError(
                reason: "Failed to initialize HRTF processor",
                severity: .critical,
                context: ErrorContext(additionalInfo: ["error": error])
            )
        }
        
        // Start quality monitoring
        setupQualityMonitoring()
        statePublisher.send(.initializing)
        
        // Validate processing capabilities
        try validateProcessingCapabilities()
        statePublisher.send(.idle)
    }
    
    // MARK: - Public Methods
    
    /// Processes audio buffer with quality monitoring and adaptive enhancement
    /// - Parameter inputBuffer: Input audio buffer to process
    /// - Returns: Processed buffer with quality metrics
    public func processAudioBufferWithQuality(_ inputBuffer: AudioBuffer) -> Result<ProcessedAudioBuffer, ProcessingError> {
        let signpostID = signposter.makeSignpostID()
        let state = signposter.beginInterval("ProcessAudio", id: signpostID)
        
        stateLock.lock()
        statePublisher.send(.processing)
        
        let startTime = CACurrentMediaTime()
        
        do {
            // Process audio through HRTF
            let hrtfResult = try hrtfProcessor.processAudio(inputBuffer)
            
            switch hrtfResult {
            case .success(let processedBuffer):
                // Monitor quality metrics
                let metrics = try hrtfProcessor.getProcessingMetrics()
                updatePerformanceMetrics(
                    latency: CACurrentMediaTime() - startTime,
                    metrics: metrics
                )
                
                // Validate quality thresholds
                guard performanceMetrics.qualityScore >= Constants.kMinQualityThreshold else {
                    throw AppError.spatialError(
                        reason: "Quality threshold not met",
                        severity: .warning,
                        context: ErrorContext(additionalInfo: [
                            "qualityScore": performanceMetrics.qualityScore,
                            "threshold": Constants.kMinQualityThreshold
                        ])
                    )
                }
                
                signposter.endInterval("ProcessAudio", state)
                stateLock.unlock()
                return .success(processedBuffer)
                
            case .failure(let error):
                throw error
            }
        } catch {
            let appError = AppError.spatialProcessingFailed(
                reason: "Audio processing failed",
                context: ErrorContext(additionalInfo: ["error": error])
            )
            statePublisher.send(.error(appError))
            signposter.endInterval("ProcessAudio", state)
            stateLock.unlock()
            return .failure(.processingFailed(appError))
        }
    }
    
    /// Updates spatial position with quality monitoring
    /// - Parameters:
    ///   - position: New spatial position
    ///   - orientation: New orientation
    public func updateSpatialPosition(_ position: simd_float3, orientation: simd_float3) {
        processingQueue.async {
            self.hrtfProcessor.updateListenerPosition(
                position,
                orientation: orientation,
                timestamp: CACurrentMediaTime()
            )
        }
    }
    
    // MARK: - Private Methods
    
    private func setupQualityMonitoring() {
        qualityMonitoringTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(Constants.kQualityMonitoringInterval * 1_000_000_000))
                self?.monitorQuality()
            }
        }
    }
    
    private func monitorQuality() {
        guard let metrics = try? hrtfProcessor.getProcessingMetrics() else { return }
        
        processingQueue.async { [weak self] in
            self?.updatePerformanceMetrics(
                latency: metrics.processingLatency,
                metrics: metrics
            )
        }
    }
    
    private func updatePerformanceMetrics(latency: TimeInterval, metrics: ProcessingMetrics) {
        performanceMetrics = PerformanceMetrics(
            processingLatency: latency,
            cpuLoad: metrics.cpuLoad,
            qualityScore: metrics.qualityScore,
            bufferUnderruns: metrics.bufferUnderruns,
            timestamp: Date()
        )
    }
    
    private func validateProcessingCapabilities() throws {
        let estimatedLatency = performanceMetrics.processingLatency
        
        guard estimatedLatency <= Constants.kMaxProcessingLatency else {
            throw AppError.spatialError(
                reason: "Processing latency exceeds maximum allowed",
                severity: .error,
                context: ErrorContext(additionalInfo: [
                    "estimatedLatency": estimatedLatency,
                    "maxLatency": Constants.kMaxProcessingLatency
                ])
            )
        }
    }
    
    deinit {
        qualityMonitoringTask?.cancel()
        cancellables.removeAll()
    }
}