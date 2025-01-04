//
// AudioEngine.swift
// TALD UNIA
//
// Core audio engine implementation with AI enhancement and hardware optimization
// Version: 1.0.0
//

import Foundation // macOS 13.0+
import AVFoundation // macOS 13.0+
import CoreAudio // macOS 13.0+

// MARK: - Global Constants

private let kDefaultBufferSize: Int = 512
private let kMaxChannelCount: Int = 8
private let kProcessingQueueLabel: String = "com.tald.unia.audio.processing"
private let kMaxLatencyMs: Double = 10.0
private let kMinSampleRate: Double = 44100.0
private let kPreferredSampleRate: Double = 192000.0

// MARK: - Audio Engine Implementation

@objc
public class AudioEngine {
    // MARK: - Properties
    
    private let avEngine: AVAudioEngine
    private let formatManager: AudioFormatManager
    private let inputBuffer: CircularAudioBuffer
    private let outputBuffer: CircularAudioBuffer
    private let dspProcessor: DSPProcessor
    private let hardwareManager: AudioHardwareManager
    private let processingQueue: DispatchQueue
    
    private(set) var isRunning: Bool = false
    private(set) var currentLatency: Double = 0.0
    private(set) var processingLoad: Double = 0.0
    private(set) var aiEnhancementEnabled: Bool = true
    
    // MARK: - Initialization
    
    public init() throws {
        // Initialize AVAudioEngine
        self.avEngine = AVAudioEngine()
        
        // Configure format manager with high-resolution settings
        let formatResult = createAudioFormat(
            sampleRate: Int(kPreferredSampleRate),
            bitDepth: AudioConstants.BIT_DEPTH,
            channelCount: kMaxChannelCount,
            isHardwareOptimized: true
        )
        
        guard case .success(let format) = formatResult else {
            throw TALDError.configurationError(
                code: "FORMAT_INIT_FAILED",
                message: "Failed to initialize audio format",
                metadata: ErrorMetadata(
                    timestamp: Date(),
                    component: "AudioEngine",
                    additionalInfo: [:]
                )
            )
        }
        
        self.formatManager = AudioFormatManager(initialFormat: format, enableHardwareOptimization: true)
        
        // Initialize audio buffers
        self.inputBuffer = CircularAudioBuffer(capacity: kDefaultBufferSize, channels: kMaxChannelCount)
        self.outputBuffer = CircularAudioBuffer(capacity: kDefaultBufferSize, channels: kMaxChannelCount)
        
        // Configure DSP processor
        let dspConfig = DSPConfiguration(
            bufferSize: kDefaultBufferSize,
            channels: kMaxChannelCount,
            sampleRate: kPreferredSampleRate,
            isOptimized: true,
            useHardwareAcceleration: true
        )
        self.dspProcessor = try DSPProcessor(config: dspConfig)
        
        // Initialize hardware manager
        let hardwareConfig = HardwareConfiguration()
        self.hardwareManager = AudioHardwareManager(config: hardwareConfig)
        
        // Configure processing queue
        self.processingQueue = DispatchQueue(
            label: kProcessingQueueLabel,
            qos: .userInteractive,
            attributes: .concurrent
        )
        
        // Configure audio engine nodes
        setupAudioEngine()
    }
    
    // MARK: - Engine Control
    
    public func start() -> Result<Bool, TALDError> {
        guard !isRunning else {
            return .success(true)
        }
        
        // Initialize hardware
        guard case .success = hardwareManager.initializeHardware() else {
            return .failure(TALDError.audioProcessingError(
                code: "HARDWARE_INIT_FAILED",
                message: "Failed to initialize audio hardware",
                metadata: ErrorMetadata(
                    timestamp: Date(),
                    component: "AudioEngine",
                    additionalInfo: [:]
                )
            ))
        }
        
        // Start audio engine
        do {
            try avEngine.start()
            isRunning = true
            startPerformanceMonitoring()
            return .success(true)
        } catch {
            return .failure(TALDError.audioProcessingError(
                code: "ENGINE_START_FAILED",
                message: "Failed to start audio engine",
                metadata: ErrorMetadata(
                    timestamp: Date(),
                    component: "AudioEngine",
                    additionalInfo: ["error": error.localizedDescription]
                )
            ))
        }
    }
    
    public func stop() {
        guard isRunning else { return }
        
        avEngine.stop()
        isRunning = false
    }
    
    // MARK: - Audio Processing
    
    public func processAudioBuffer(_ buffer: AudioBuffer) -> Result<AudioBuffer?, TALDError> {
        let startTime = Date()
        
        // Validate buffer format
        guard formatManager.validateFormat(buffer.format) else {
            return .failure(TALDError.audioProcessingError(
                code: "INVALID_FORMAT",
                message: "Invalid audio format",
                metadata: ErrorMetadata(
                    timestamp: Date(),
                    component: "AudioEngine",
                    additionalInfo: [:]
                )
            ))
        }
        
        // Write to input buffer
        guard case .success = inputBuffer.write(buffer.floatChannelData?[0], frameCount: Int(buffer.frameLength)) else {
            return .failure(TALDError.audioProcessingError(
                code: "BUFFER_WRITE_FAILED",
                message: "Failed to write to input buffer",
                metadata: ErrorMetadata(
                    timestamp: Date(),
                    component: "AudioEngine",
                    additionalInfo: [:]
                )
            ))
        }
        
        // Process through DSP chain
        guard case .success(let metrics) = dspProcessor.process(
            inputBuffer.floatChannelData?[0],
            outputBuffer.mutableAudioBufferList.mBuffers.mData?.assumingMemoryBound(to: Float.self),
            frameCount: Int(buffer.frameLength)
        ) else {
            return .failure(TALDError.audioProcessingError(
                code: "DSP_PROCESSING_FAILED",
                message: "DSP processing failed",
                metadata: ErrorMetadata(
                    timestamp: Date(),
                    component: "AudioEngine",
                    additionalInfo: [:]
                )
            ))
        }
        
        // Update performance metrics
        currentLatency = Date().timeIntervalSince(startTime)
        processingLoad = metrics.processingLoad
        
        // Validate latency requirement
        if currentLatency > kMaxLatencyMs / 1000.0 {
            return .failure(TALDError.audioProcessingError(
                code: "LATENCY_EXCEEDED",
                message: "Processing latency exceeded threshold",
                metadata: ErrorMetadata(
                    timestamp: Date(),
                    component: "AudioEngine",
                    additionalInfo: [
                        "currentLatency": "\(currentLatency * 1000.0)ms",
                        "threshold": "\(kMaxLatencyMs)ms"
                    ]
                )
            ))
        }
        
        return .success(buffer)
    }
    
    // MARK: - Private Methods
    
    private func setupAudioEngine() {
        let mainMixer = avEngine.mainMixerNode
        let input = avEngine.inputNode
        let output = avEngine.outputNode
        
        // Configure format
        let format = formatManager.currentFormat
        
        // Connect nodes
        avEngine.connect(input, to: mainMixer, format: format)
        avEngine.connect(mainMixer, to: output, format: format)
        
        // Set buffer size
        avEngine.inputNode.setBufferSize(AVAudioFrameCount(kDefaultBufferSize))
        avEngine.outputNode.setBufferSize(AVAudioFrameCount(kDefaultBufferSize))
    }
    
    private func startPerformanceMonitoring() {
        processingQueue.async { [weak self] in
            guard let self = self else { return }
            
            while self.isRunning {
                let metrics = self.hardwareManager.performanceMonitor.getCurrentMetrics()
                self.updatePerformanceMetrics(metrics)
                Thread.sleep(forTimeInterval: 0.1)
            }
        }
    }
    
    private func updatePerformanceMetrics(_ metrics: HardwareMonitor.HardwareMetrics) {
        currentLatency = metrics.currentLatency
        processingLoad = metrics.processingLoad
    }
}