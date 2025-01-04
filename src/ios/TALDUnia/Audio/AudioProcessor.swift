//
// AudioProcessor.swift
// TALD UNIA Audio System
//
// Core audio processing implementation providing high-quality audio processing
// with AI enhancement and power-efficient operation.
//
// Dependencies:
// - AVFoundation (Latest) - Core audio functionality
// - Accelerate (Latest) - High-performance DSP operations

import AVFoundation
import Accelerate

@objc public class AudioProcessor: NSObject {
    
    // MARK: - Constants
    
    private let kDefaultBufferSize = AudioConstants.bufferSize
    private let kMaxProcessingLatency = AudioConstants.maxLatency
    private let kDefaultSampleRate = AudioConstants.sampleRate
    private let kMinPowerEfficiency = 0.90
    private let kTargetQualityImprovement = 0.20
    
    // MARK: - Properties
    
    private let dspProcessor: DSPProcessor
    private let inputBuffer: AudioBuffer
    private let outputBuffer: AudioBuffer
    private let processingQueue: DispatchQueue
    
    public private(set) var isProcessing: Bool = false
    public private(set) var currentLatency: Double = 0.0
    public private(set) var currentQualityImprovement: Double = 0.0
    
    private var lastProcessingTime: TimeInterval = 0
    private var processingStartTime: TimeInterval = 0
    private var qualityMetrics: [String: Double] = [:]
    
    // MARK: - Initialization
    
    public init(sampleRate: Int = AudioConstants.sampleRate,
                bufferSize: Int = AudioConstants.bufferSize) throws {
        // Initialize DSP processor
        self.dspProcessor = try DSPProcessor(
            sampleRate: sampleRate,
            bufferSize: bufferSize,
            channelCount: AudioConstants.channelCount
        )
        
        // Initialize audio format
        let format = try AudioFormat(
            sampleRate: sampleRate,
            bitDepth: AudioConstants.bitDepth,
            channels: AudioConstants.channelCount,
            interleaved: true
        )
        
        // Initialize audio buffers
        self.inputBuffer = try AudioBuffer(
            format: format,
            bufferSize: bufferSize,
            enableMonitoring: true
        )
        
        self.outputBuffer = try AudioBuffer(
            format: format,
            bufferSize: bufferSize
        )
        
        // Initialize processing queue
        self.processingQueue = DispatchQueue(
            label: "com.taldunia.audio.processor",
            qos: .userInteractive,
            attributes: .concurrent
        )
        
        super.init()
    }
    
    // MARK: - Public Interface
    
    @discardableResult
    public func processAudioBuffer(_ inputBuffer: AudioBuffer,
                                 _ outputBuffer: AudioBuffer) -> Result<Void, Error> {
        guard !isProcessing else {
            return .failure(AppError.audioError(
                reason: "Processing already in progress",
                severity: .error,
                context: ErrorContext()
            ))
        }
        
        isProcessing = true
        processingStartTime = CACurrentMediaTime()
        
        return processingQueue.sync { [weak self] in
            guard let self = self else {
                return .failure(AppError.audioError(
                    reason: "AudioProcessor deallocated",
                    severity: .error,
                    context: ErrorContext()
                ))
            }
            
            do {
                // Copy input data
                guard let inputData = inputBuffer.pcmBuffer?.floatChannelData?[0],
                      let outputData = outputBuffer.pcmBuffer?.floatChannelData?[0] else {
                    throw AppError.audioError(
                        reason: "Invalid buffer data",
                        severity: .error,
                        context: ErrorContext()
                    )
                }
                
                // Process through DSP chain
                let metrics = try dspProcessor.processBuffer(
                    inputData,
                    outputData,
                    frameCount: Int(inputBuffer.pcmBuffer?.frameLength ?? 0)
                )
                
                // Update quality metrics
                updateQualityMetrics(metrics)
                
                // Update latency measurement
                self.currentLatency = CACurrentMediaTime() - processingStartTime
                
                // Validate processing results
                try validateProcessingResults()
                
                isProcessing = false
                return .success(())
                
            } catch {
                isProcessing = false
                return .failure(error)
            }
        }
    }
    
    public func updateProcessingParameters(_ parameters: [String: Any]) -> Bool {
        guard !isProcessing else { return false }
        
        do {
            // Validate parameters
            guard let enhancementLevel = parameters["enhancementLevel"] as? Float,
                  (0.0...1.0).contains(enhancementLevel) else {
                throw AppError.audioError(
                    reason: "Invalid enhancement level",
                    severity: .error,
                    context: ErrorContext()
                )
            }
            
            // Update DSP parameters
            try dspProcessor.processBuffer(
                inputBuffer.pcmBuffer?.floatChannelData?[0] ?? [],
                outputBuffer.pcmBuffer?.floatChannelData?[0] ?? [],
                frameCount: Int(inputBuffer.pcmBuffer?.frameLength ?? 0)
            )
            
            return true
            
        } catch {
            return false
        }
    }
    
    public func startProcessing() -> Result<Void, Error> {
        guard !isProcessing else {
            return .failure(AppError.audioError(
                reason: "Processing already started",
                severity: .error,
                context: ErrorContext()
            ))
        }
        
        do {
            // Initialize processing chain
            try initializeProcessingChain()
            
            // Start DSP processor
            isProcessing = true
            
            // Begin performance monitoring
            startPerformanceMonitoring()
            
            return .success(())
            
        } catch {
            return .failure(error)
        }
    }
    
    public func stopProcessing() {
        guard isProcessing else { return }
        
        // Stop processing
        isProcessing = false
        
        // Clean up resources
        cleanupProcessingChain()
        
        // Save final metrics
        saveProcessingMetrics()
    }
    
    // MARK: - Private Methods
    
    private func initializeProcessingChain() throws {
        // Validate hardware capabilities
        try validateHardwareCapabilities()
        
        // Initialize buffers
        try allocateProcessingBuffers()
        
        // Configure processing chain
        configureProcessingChain()
    }
    
    private func validateHardwareCapabilities() throws {
        // Check sample rate
        guard kDefaultSampleRate <= AudioConstants.sampleRate else {
            throw AppError.hardwareError(
                reason: "Sample rate exceeds hardware capabilities",
                severity: .error,
                context: ErrorContext()
            )
        }
        
        // Check buffer size
        guard kDefaultBufferSize >= BufferConstants.kMinBufferSize else {
            throw AppError.hardwareError(
                reason: "Buffer size below minimum requirement",
                severity: .error,
                context: ErrorContext()
            )
        }
    }
    
    private func allocateProcessingBuffers() throws {
        // Ensure buffer allocation
        guard inputBuffer.pcmBuffer != nil,
              outputBuffer.pcmBuffer != nil else {
            throw AppError.audioError(
                reason: "Failed to allocate processing buffers",
                severity: .error,
                context: ErrorContext()
            )
        }
    }
    
    private func configureProcessingChain() {
        // Configure processing parameters
        qualityMetrics = [
            "thd": QualityConstants.targetTHD,
            "snr": QualityConstants.targetSNR,
            "qualityImprovement": QualityConstants.minQualityImprovement
        ]
    }
    
    private func updateQualityMetrics(_ metrics: ProcessingMetrics) {
        currentQualityImprovement = metrics.powerEfficiency
        lastProcessingTime = metrics.processingTime
    }
    
    private func validateProcessingResults() throws {
        // Validate latency
        guard currentLatency <= kMaxProcessingLatency else {
            throw AppError.audioError(
                reason: "Processing latency exceeds maximum",
                severity: .error,
                context: ErrorContext(additionalInfo: [
                    "currentLatency": currentLatency,
                    "maxLatency": kMaxProcessingLatency
                ])
            )
        }
        
        // Validate quality improvement
        guard currentQualityImprovement >= kTargetQualityImprovement else {
            throw AppError.audioError(
                reason: "Quality improvement below target",
                severity: .warning,
                context: ErrorContext(additionalInfo: [
                    "currentImprovement": currentQualityImprovement,
                    "targetImprovement": kTargetQualityImprovement
                ])
            )
        }
    }
    
    private func startPerformanceMonitoring() {
        processingStartTime = CACurrentMediaTime()
    }
    
    private func cleanupProcessingChain() {
        // Reset buffers
        inputBuffer.pcmBuffer?.frameLength = 0
        outputBuffer.pcmBuffer?.frameLength = 0
        
        // Reset metrics
        currentLatency = 0
        lastProcessingTime = 0
    }
    
    private func saveProcessingMetrics() {
        // Save final processing metrics
        qualityMetrics["finalLatency"] = currentLatency
        qualityMetrics["finalQualityImprovement"] = currentQualityImprovement
    }
}