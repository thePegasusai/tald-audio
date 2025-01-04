// Foundation v17.0+
import AVFoundation
import Accelerate
import simd

/// High-performance spatial audio processor optimized for ESS ES9038PRO DAC with HRTF-based 3D audio rendering
@objc public class SpatialProcessor: NSObject {
    
    // MARK: - Constants
    
    private enum Constants {
        static let kDefaultWetDryMix: Float = 0.7
        static let kMaxSourceDistance: Float = 100.0
        static let kMinSourceDistance: Float = 0.1
        static let kProcessingQueueQoS: DispatchQoS = .userInteractive
        static let kMaxBufferSize: Int = 2048
        static let kOptimalThreadCount: Int = ProcessInfo.processInfo.processorCount
    }
    
    // MARK: - Properties
    
    private let hrtfProcessor: HRTFProcessor
    private let roomModeling: RoomModeling
    private let inputBuffer: AudioBuffer
    private let outputBuffer: AudioBuffer
    private let processingQueue: DispatchQueue
    private let dspProcessor: DSPProcessor
    
    @objc public private(set) var wetDryMix: Float
    @objc public private(set) var isProcessing: Bool
    @objc public private(set) var processingMetrics: ProcessingMetrics
    
    private let stateLock = NSLock()
    
    // MARK: - Initialization
    
    /// Initializes spatial processor with optimized configuration for ESS ES9038PRO DAC
    /// - Parameters:
    ///   - format: Audio format configuration
    ///   - roomParams: Room acoustics parameters
    ///   - config: Processing configuration
    @objc public init(format: AVAudioFormat,
                     roomParams: RoomParameters,
                     config: ProcessingConfiguration) throws {
        
        // Initialize audio buffers with optimal size
        self.inputBuffer = try AudioBuffer(
            format: format,
            bufferSize: Constants.kMaxBufferSize,
            enableMonitoring: false
        )
        
        self.outputBuffer = try AudioBuffer(
            format: format,
            bufferSize: Constants.kMaxBufferSize,
            enableMonitoring: false
        )
        
        // Initialize HRTF processor
        self.hrtfProcessor = try HRTFProcessor(
            format: format,
            roomParams: roomParams,
            quality: .balanced
        )
        
        // Initialize room modeling engine
        self.roomModeling = try RoomModeling(
            dimensions: roomParams.dimensions,
            absorption: roomParams.absorption,
            quality: .high
        )
        
        // Initialize DSP processor for low-level operations
        self.dspProcessor = try DSPProcessor(
            sampleRate: Int(format.sampleRate),
            bufferSize: Constants.kMaxBufferSize,
            channelCount: Int(format.channelCount)
        )
        
        // Initialize processing state
        self.wetDryMix = Constants.kDefaultWetDryMix
        self.isProcessing = false
        self.processingMetrics = ProcessingMetrics()
        
        // Configure high-priority processing queue
        self.processingQueue = DispatchQueue(
            label: "com.taldunia.spatial.processor",
            qos: Constants.kProcessingQueueQoS,
            attributes: [.concurrent],
            autoreleaseFrequency: .workItem,
            target: nil
        )
        
        super.init()
        
        // Validate hardware capabilities
        try validateHardwareCapabilities(format: format)
    }
    
    // MARK: - Public Methods
    
    /// Processes audio with optimized spatial effects and room modeling
    /// - Parameters:
    ///   - input: Input audio buffer to process
    ///   - params: Spatial processing parameters
    /// - Returns: Processed audio buffer with spatial effects
    @objc public func processSpatialAudio(_ input: AudioBuffer,
                                         params: SpatialParameters) -> Result<AudioBuffer, Error> {
        stateLock.lock()
        defer { stateLock.unlock() }
        
        guard !isProcessing else {
            return .failure(AppError.spatialProcessingFailed(
                reason: "Processing already in progress",
                context: ErrorContext()
            ))
        }
        
        isProcessing = true
        let startTime = CACurrentMediaTime()
        
        return processingQueue.sync {
            do {
                // Copy input to processing buffer
                try inputBuffer.copyToBuffer(
                    input.pcmBuffer!.floatChannelData![0],
                    frames: Int(input.pcmBuffer!.frameLength)
                ).get()
                
                // Apply HRTF processing
                let hrtfResult = try hrtfProcessor.processAudio(inputBuffer).get()
                
                // Apply room modeling
                let roomResult = try roomModeling.startModeling().get()
                
                // Mix wet/dry signals using SIMD
                var wetSignal = [Float](repeating: 0, count: Constants.kMaxBufferSize)
                var drySignal = [Float](repeating: 0, count: Constants.kMaxBufferSize)
                
                vDSP_vsmul(hrtfResult.pcmBuffer!.floatChannelData![0], 1,
                          &wetDryMix,
                          &wetSignal, 1,
                          vDSP_Length(hrtfResult.pcmBuffer!.frameLength))
                
                let dryMix = 1.0 - wetDryMix
                vDSP_vsmul(input.pcmBuffer!.floatChannelData![0], 1,
                          &dryMix,
                          &drySignal, 1,
                          vDSP_Length(input.pcmBuffer!.frameLength))
                
                // Sum wet and dry signals
                vDSP_vadd(wetSignal, 1,
                         drySignal, 1,
                         outputBuffer.pcmBuffer!.floatChannelData![0], 1,
                         vDSP_Length(input.pcmBuffer!.frameLength))
                
                // Update processing metrics
                processingMetrics = ProcessingMetrics()
                processingMetrics.processingTime = CACurrentMediaTime() - startTime
                processingMetrics.qualityScore = Double(wetDryMix)
                processingMetrics.bufferUtilization = roomResult.bufferUtilization
                
                isProcessing = false
                return .success(outputBuffer)
                
            } catch {
                isProcessing = false
                return .failure(AppError.spatialProcessingFailed(
                    reason: "Spatial processing failed",
                    context: ErrorContext(additionalInfo: ["error": error])
                ))
            }
        }
    }
    
    /// Updates spatial processing parameters with thread safety
    /// - Parameter params: New spatial parameters
    @objc public func updateSpatialParameters(_ params: SpatialParameters) {
        processingQueue.async {
            self.stateLock.lock()
            defer { self.stateLock.unlock() }
            
            // Update HRTF processor
            try? self.hrtfProcessor.updateListenerPosition(
                params.listenerPosition,
                orientation: params.listenerOrientation,
                timestamp: CACurrentMediaTime()
            )
            
            // Update room modeling
            try? self.roomModeling.updateRoomParameters(
                newDimensions: params.roomDimensions,
                newAbsorption: params.absorption,
                quality: .high
            ).get()
            
            // Update mix parameters
            self.wetDryMix = min(max(params.wetDryMix, 0.0), 1.0)
        }
    }
    
    // MARK: - Private Methods
    
    /// Validates hardware capabilities for spatial processing
    private func validateHardwareCapabilities(format: AVAudioFormat) throws {
        // Verify sample rate compatibility with ESS ES9038PRO DAC
        guard format.sampleRate <= Double(AudioConstants.sampleRate) else {
            throw AppError.hardwareError(
                reason: "Sample rate exceeds DAC capabilities",
                severity: .error,
                context: ErrorContext(additionalInfo: [
                    "requestedRate": format.sampleRate,
                    "maxRate": AudioConstants.sampleRate
                ])
            )
        }
        
        // Verify processing latency requirements
        let estimatedLatency = 1000.0 / format.sampleRate * Double(Constants.kMaxBufferSize)
        guard estimatedLatency <= 10.0 else {
            throw AppError.hardwareError(
                reason: "Processing latency exceeds requirements",
                severity: .error,
                context: ErrorContext(additionalInfo: [
                    "estimatedLatency": estimatedLatency,
                    "maxLatency": 10.0
                ])
            )
        }
        
        // Verify THD+N requirements
        guard QualityConstants.targetTHD <= 0.000005 else {
            throw AppError.hardwareError(
                reason: "THD+N exceeds requirements",
                severity: .error,
                context: ErrorContext(additionalInfo: [
                    "currentTHD": QualityConstants.targetTHD,
                    "maxTHD": 0.000005
                ])
            )
        }
    }
}