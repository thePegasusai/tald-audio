// Foundation v17.0+, AVFoundation Latest
import Foundation
import AVFoundation
import Accelerate

/// Thread-safe room correction processor with AI-driven modeling and real-time DSP processing
@objc public final class RoomCorrection: NSObject {
    
    // MARK: - Constants
    
    private let kDefaultRoomSize: Double = 30.0
    private let kMinRoomSize: Double = 1.0
    private let kMaxRoomSize: Double = 100.0
    private let kDefaultReverbTime: Double = 0.5
    private let kMaxProcessingLatency: Double = 0.010 // 10ms as per requirements
    private let kMinQualityThreshold: Double = 0.0005 // THD+N threshold
    
    // MARK: - Properties
    
    private let audioProcessor: AudioProcessor
    private let roomCorrectionModel: RoomCorrectionModel
    private let dspProcessor: DSPProcessor
    private let processingQueue: DispatchQueue
    
    private var currentConfig: RoomConfiguration
    private var isEnabled: Bool = false
    private var processingLatency: Double = 0.0
    private var currentMetrics: ProcessingMetrics
    private let audioBufferPool: AudioBufferPool
    
    // MARK: - Initialization
    
    /// Initializes room correction with specified configuration and performance monitoring
    public init(config: RoomConfiguration = RoomConfiguration(),
               options: ProcessingOptions = ProcessingOptions()) throws {
        
        // Initialize processing components
        self.audioProcessor = try AudioProcessor(
            sampleRate: AudioConstants.sampleRate,
            bufferSize: AudioConstants.bufferSize
        )
        
        self.roomCorrectionModel = RoomCorrectionModel()
        
        self.dspProcessor = try DSPProcessor(
            sampleRate: AudioConstants.sampleRate,
            bufferSize: AudioConstants.bufferSize,
            channelCount: AudioConstants.channelCount
        )
        
        // Initialize processing queue with QoS
        self.processingQueue = DispatchQueue(
            label: "com.taldunia.audio.roomcorrection",
            qos: .userInteractive
        )
        
        // Initialize configuration and metrics
        self.currentConfig = config
        self.currentMetrics = ProcessingMetrics()
        
        // Initialize buffer pool
        self.audioBufferPool = AudioBufferPool(
            format: try AudioFormat(
                sampleRate: AudioConstants.sampleRate,
                bitDepth: AudioConstants.bitDepth,
                channels: AudioConstants.channelCount
            ),
            poolSize: 8
        )
        
        super.init()
        
        // Initialize AI model
        try roomCorrectionModel.initialize().get()
    }
    
    // MARK: - Public Interface
    
    /// Starts room correction processing with performance validation
    @discardableResult
    public func start() -> Result<ProcessingMetrics, RoomCorrectionError> {
        return processingQueue.sync {
            do {
                // Validate system resources
                try validateSystemResources()
                
                // Initialize processing chain
                try initializeProcessingChain()
                
                // Enable processing
                isEnabled = true
                
                // Start performance monitoring
                startPerformanceMonitoring()
                
                return .success(currentMetrics)
                
            } catch {
                return .failure(.processingError(error.localizedDescription))
            }
        }
    }
    
    /// Safely stops room correction processing with cleanup
    @discardableResult
    public func stop() -> Result<Void, RoomCorrectionError> {
        return processingQueue.sync {
            // Disable processing
            isEnabled = false
            
            // Stop components
            audioProcessor.stopProcessing()
            dspProcessor.cleanup()
            roomCorrectionModel.shutdown()
            
            // Clear buffers
            audioBufferPool.drain()
            
            // Reset metrics
            currentMetrics = ProcessingMetrics()
            
            return .success(())
        }
    }
    
    /// Applies room correction to an audio buffer using both AI model and DSP processing
    @discardableResult
    @inlinable
    public func applyRoomCorrection(
        inputBuffer: AVAudioPCMBuffer,
        roomParams: RoomParameters,
        metrics: ProcessingMetrics
    ) -> Result<(AVAudioPCMBuffer, ProcessingMetrics), RoomCorrectionError> {
        
        guard isEnabled else {
            return .failure(.notEnabled)
        }
        
        let processingStart = CACurrentMediaTime()
        
        return processingQueue.sync {
            do {
                // Validate input
                try validateInputBuffer(inputBuffer)
                try validateRoomParameters(roomParams)
                
                // Get buffer from pool
                guard let outputBuffer = audioBufferPool.obtain() else {
                    throw RoomCorrectionError.resourceError("Failed to obtain buffer")
                }
                
                // Apply AI-based room modeling
                let modelResult = try roomCorrectionModel.correctRoom(
                    inputBuffer: inputBuffer,
                    roomParams: roomParams
                ).get()
                
                // Process through DSP chain
                let dspMetrics = try dspProcessor.processBuffer(
                    modelResult.floatChannelData?[0] ?? [],
                    outputBuffer.floatChannelData?[0] ?? [],
                    frameCount: Int(modelResult.frameLength)
                )
                
                // Update metrics
                updateProcessingMetrics(
                    dspMetrics: dspMetrics,
                    startTime: processingStart
                )
                
                // Validate quality
                try validateProcessingQuality()
                
                return .success((outputBuffer, currentMetrics))
                
            } catch {
                return .failure(.processingError(error.localizedDescription))
            }
        }
    }
    
    /// Updates room configuration parameters with validation
    @discardableResult
    public func updateRoomConfiguration(
        _ config: RoomConfiguration,
        metrics: ValidationMetrics
    ) -> Result<ProcessingMetrics, RoomCorrectionError> {
        
        return processingQueue.sync {
            do {
                // Validate configuration
                try validateConfiguration(config)
                
                // Update AI model parameters
                try roomCorrectionModel.updateRoomParameters(
                    RoomParameters(
                        size: Float(config.roomSize),
                        reverbTime: Float(config.reverbTime)
                    )
                ).get()
                
                // Update DSP chain
                let dspResult = audioProcessor.updateProcessingParameters([
                    "roomSize": config.roomSize,
                    "reverbTime": config.reverbTime
                ])
                
                guard dspResult else {
                    throw RoomCorrectionError.configurationError("Failed to update DSP parameters")
                }
                
                // Update current configuration
                currentConfig = config
                
                return .success(currentMetrics)
                
            } catch {
                return .failure(.configurationError(error.localizedDescription))
            }
        }
    }
    
    // MARK: - Private Methods
    
    private func validateSystemResources() throws {
        guard audioProcessor.isProcessing == false else {
            throw RoomCorrectionError.resourceError("Audio processor busy")
        }
        
        guard roomCorrectionModel.isInitialized else {
            throw RoomCorrectionError.resourceError("AI model not initialized")
        }
    }
    
    private func validateInputBuffer(_ buffer: AVAudioPCMBuffer) throws {
        guard buffer.format.sampleRate == Double(AudioConstants.sampleRate),
              buffer.format.channelCount == UInt32(AudioConstants.channelCount) else {
            throw RoomCorrectionError.invalidFormat("Invalid buffer format")
        }
    }
    
    private func validateRoomParameters(_ params: RoomParameters) throws {
        guard params.size >= Float(kMinRoomSize),
              params.size <= Float(kMaxRoomSize),
              params.reverbTime > 0 else {
            throw RoomCorrectionError.invalidParameters("Invalid room parameters")
        }
    }
    
    private func validateConfiguration(_ config: RoomConfiguration) throws {
        guard config.roomSize >= kMinRoomSize,
              config.roomSize <= kMaxRoomSize,
              config.reverbTime > 0 else {
            throw RoomCorrectionError.invalidConfiguration("Invalid configuration values")
        }
    }
    
    private func validateProcessingQuality() throws {
        guard currentMetrics.thdn <= kMinQualityThreshold else {
            throw RoomCorrectionError.qualityError("THD+N exceeds threshold")
        }
        
        guard processingLatency <= kMaxProcessingLatency else {
            throw RoomCorrectionError.latencyError("Processing latency exceeds maximum")
        }
    }
    
    private func updateProcessingMetrics(dspMetrics: ProcessingMetrics,
                                       startTime: TimeInterval) {
        processingLatency = CACurrentMediaTime() - startTime
        currentMetrics = ProcessingMetrics(
            thdn: dspMetrics.thdn,
            snr: dspMetrics.snr,
            latency: processingLatency,
            processingLoad: dspMetrics.processingLoad
        )
    }
    
    private func startPerformanceMonitoring() {
        // Initialize performance monitoring
        currentMetrics = ProcessingMetrics()
        processingLatency = 0
    }
}

// MARK: - Supporting Types

/// Room correction configuration parameters
public struct RoomConfiguration {
    public let roomSize: Double
    public let reverbTime: Double
    public let absorptionCoefficients: [Double]
    
    public init(roomSize: Double = 30.0,
                reverbTime: Double = 0.5,
                absorptionCoefficients: [Double] = []) {
        self.roomSize = roomSize
        self.reverbTime = reverbTime
        self.absorptionCoefficients = absorptionCoefficients
    }
}

/// Processing options for room correction
public struct ProcessingOptions {
    public let enableGPU: Bool
    public let bufferSize: Int
    public let monitorQuality: Bool
    
    public init(enableGPU: Bool = true,
                bufferSize: Int = AudioConstants.bufferSize,
                monitorQuality: Bool = true) {
        self.enableGPU = enableGPU
        self.bufferSize = bufferSize
        self.monitorQuality = monitorQuality
    }
}

/// Room correction specific errors
public enum RoomCorrectionError: LocalizedError {
    case notEnabled
    case processingError(String)
    case configurationError(String)
    case resourceError(String)
    case invalidFormat(String)
    case invalidParameters(String)
    case invalidConfiguration(String)
    case qualityError(String)
    case latencyError(String)
    
    public var errorDescription: String? {
        switch self {
        case .notEnabled:
            return "Room correction is not enabled"
        case .processingError(let message):
            return "Processing error: \(message)"
        case .configurationError(let message):
            return "Configuration error: \(message)"
        case .resourceError(let message):
            return "Resource error: \(message)"
        case .invalidFormat(let message):
            return "Format error: \(message)"
        case .invalidParameters(let message):
            return "Parameter error: \(message)"
        case .invalidConfiguration(let message):
            return "Configuration error: \(message)"
        case .qualityError(let message):
            return "Quality error: \(message)"
        case .latencyError(let message):
            return "Latency error: \(message)"
        }
    }
}