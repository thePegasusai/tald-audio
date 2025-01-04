//
// AudioEngine.swift
// TALD UNIA Audio System
//
// Core audio engine implementation providing high-quality audio processing with
// power efficiency optimization and comprehensive performance monitoring.
//
// Dependencies:
// - AVFoundation (Latest) - Core audio functionality
// - Accelerate (Latest) - High-performance DSP operations
// - os.signpost (Latest) - Performance monitoring

import AVFoundation
import Accelerate
import os.signpost

@available(iOS 13.0, *)
public class AudioEngine: NSObject {
    
    // MARK: - Constants
    
    private let kDefaultSampleRate = AudioConstants.sampleRate
    private let kDefaultBufferSize = AudioConstants.bufferSize
    private let kMaxChannels = AudioConstants.channelCount
    private let kMaxLatencyMs = AudioConstants.maxLatency
    private let kPowerEfficiencyThreshold = 0.90
    
    // MARK: - Types
    
    public enum PowerMode {
        case highQuality
        case balanced
        case powerEfficient
    }
    
    public struct PerformanceMetrics {
        var currentLatency: TimeInterval
        var powerEfficiency: Double
        var bufferUnderruns: Int
        var processingLoad: Double
    }
    
    // MARK: - Properties
    
    private let avEngine: AVAudioEngine
    private let audioProcessor: AudioProcessor
    private let powerMonitor: PowerEfficiencyMonitor
    private let signposter = OSSignposter()
    
    private var isRunning: Bool = false {
        didSet { updateEngineState() }
    }
    
    private var currentLatency: Double = 0.0
    private var currentPowerEfficiency: Double = 1.0
    
    private let processingQueue: DispatchQueue
    private let stateQueue: DispatchQueue
    
    // MARK: - Initialization
    
    public init(format: AudioFormat? = nil,
                bufferSize: Int = AudioConstants.bufferSize,
                powerMode: PowerMode = .balanced) throws {
        
        // Initialize queues
        self.processingQueue = DispatchQueue(
            label: "com.taldunia.audio.processing",
            qos: .userInteractive
        )
        
        self.stateQueue = DispatchQueue(
            label: "com.taldunia.audio.state",
            qos: .userInitiated
        )
        
        // Initialize audio engine
        self.avEngine = AVAudioEngine()
        
        // Initialize audio processor
        self.audioProcessor = try AudioProcessor(
            sampleRate: AudioConstants.sampleRate,
            bufferSize: bufferSize
        )
        
        // Initialize power monitor
        self.powerMonitor = PowerEfficiencyMonitor(
            targetEfficiency: kPowerEfficiencyThreshold
        )
        
        super.init()
        
        // Configure audio session
        try configureAudioSession(powerMode: powerMode).get()
        
        // Configure processing chain
        try setupProcessingChain(format: format).get()
        
        // Setup performance monitoring
        setupPerformanceMonitoring()
    }
    
    // MARK: - Public Interface
    
    public func start() -> Result<Void, Error> {
        return stateQueue.sync {
            guard !isRunning else {
                return .failure(AppError.audioError(
                    reason: "Engine already running",
                    severity: .warning,
                    context: ErrorContext()
                ))
            }
            
            do {
                // Start audio processor
                try audioProcessor.startProcessing().get()
                
                // Start AVAudioEngine
                try avEngine.start()
                
                isRunning = true
                return .success(())
                
            } catch {
                return .failure(error)
            }
        }
    }
    
    public func stop() {
        stateQueue.sync {
            guard isRunning else { return }
            
            // Stop processing
            audioProcessor.stopProcessing()
            
            // Stop engine
            avEngine.stop()
            
            isRunning = false
        }
    }
    
    public func optimizePowerConsumption(for mode: PowerMode) -> Result<Double, Error> {
        return stateQueue.sync {
            let signpostID = signposter.makeSignpostID()
            let state = signposter.beginInterval("OptimizePower", id: signpostID)
            
            defer { signposter.endInterval("OptimizePower", state) }
            
            do {
                // Update audio session
                try configureAudioSession(powerMode: mode).get()
                
                // Update processing parameters
                let parameters: [String: Any] = [
                    "enhancementLevel": mode == .powerEfficient ? 0.6 : 0.8,
                    "bufferSize": mode == .powerEfficient ? 512 : kDefaultBufferSize
                ]
                
                guard audioProcessor.updateProcessingParameters(parameters) else {
                    throw AppError.audioError(
                        reason: "Failed to update processing parameters",
                        severity: .error,
                        context: ErrorContext()
                    )
                }
                
                // Monitor power efficiency
                currentPowerEfficiency = powerMonitor.getCurrentEfficiency()
                
                return .success(currentPowerEfficiency)
                
            } catch {
                return .failure(error)
            }
        }
    }
    
    public func getPerformanceMetrics() -> PerformanceMetrics {
        return stateQueue.sync {
            return PerformanceMetrics(
                currentLatency: currentLatency,
                powerEfficiency: currentPowerEfficiency,
                bufferUnderruns: powerMonitor.getUnderrunCount(),
                processingLoad: powerMonitor.getCurrentLoad()
            )
        }
    }
    
    // MARK: - Private Methods
    
    private func configureAudioSession(powerMode: PowerMode) -> Result<Void, Error> {
        let session = AVAudioSession.sharedInstance()
        
        do {
            // Configure category and mode
            try session.setCategory(
                .playAndRecord,
                mode: .measurement,
                options: [.allowBluetoothA2DP, .defaultToSpeaker]
            )
            
            // Configure buffer duration based on power mode
            let preferredIOBufferDuration: TimeInterval
            switch powerMode {
            case .highQuality:
                preferredIOBufferDuration = 0.005 // 5ms
            case .balanced:
                preferredIOBufferDuration = 0.010 // 10ms
            case .powerEfficient:
                preferredIOBufferDuration = 0.020 // 20ms
            }
            
            try session.setPreferredIOBufferDuration(preferredIOBufferDuration)
            
            // Set sample rate
            try session.setPreferredSampleRate(Double(kDefaultSampleRate))
            
            // Activate session
            try session.setActive(true)
            
            return .success(())
            
        } catch {
            return .failure(AppError.audioError(
                reason: "Failed to configure audio session: \(error.localizedDescription)",
                severity: .error,
                context: ErrorContext()
            ))
        }
    }
    
    private func setupProcessingChain(format: AudioFormat?) -> Result<Void, Error> {
        let signpostID = signposter.makeSignpostID()
        let state = signposter.beginInterval("SetupProcessing", id: signpostID)
        
        defer { signposter.endInterval("SetupProcessing", state) }
        
        do {
            // Configure main mixer
            let mainMixer = avEngine.mainMixerNode
            mainMixer.outputVolume = 1.0
            
            // Configure input node if needed
            if let inputNode = avEngine.inputNode {
                let inputFormat = format?.currentFormat ?? inputNode.outputFormat(forBus: 0)
                avEngine.connect(
                    inputNode,
                    to: mainMixer,
                    format: inputFormat
                )
            }
            
            // Configure output node
            let outputNode = avEngine.outputNode
            let outputFormat = format?.currentFormat ?? outputNode.inputFormat(forBus: 0)
            avEngine.connect(
                mainMixer,
                to: outputNode,
                format: outputFormat
            )
            
            // Prepare engine
            try avEngine.enableManualRenderingMode(
                .realtime,
                format: outputFormat,
                maximumFrameCount: AVAudioFrameCount(kDefaultBufferSize)
            )
            
            try avEngine.start()
            
            return .success(())
            
        } catch {
            return .failure(AppError.audioError(
                reason: "Failed to setup processing chain: \(error.localizedDescription)",
                severity: .error,
                context: ErrorContext()
            ))
        }
    }
    
    private func setupPerformanceMonitoring() {
        // Setup periodic monitoring
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.processingQueue.async {
                self?.monitorPerformance()
            }
        }
    }
    
    private func monitorPerformance() {
        let signpostID = signposter.makeSignpostID()
        let state = signposter.beginInterval("MonitorPerformance", id: signpostID)
        
        defer { signposter.endInterval("MonitorPerformance", state) }
        
        // Update metrics
        currentLatency = avEngine.outputLatency + avEngine.inputLatency
        currentPowerEfficiency = powerMonitor.getCurrentEfficiency()
        
        // Log performance data
        os_signpost(.event, log: .default, name: "AudioPerformance",
                   "latency: %f, efficiency: %f",
                   currentLatency, currentPowerEfficiency)
    }
    
    private func updateEngineState() {
        os_signpost(.event, log: .default, name: "EngineState",
                   "running: %d", isRunning)
    }
}

// MARK: - Power Efficiency Monitor

private class PowerEfficiencyMonitor {
    private let targetEfficiency: Double
    private var measurements: [Double] = []
    private var underrunCount: Int = 0
    private let queue = DispatchQueue(label: "com.taldunia.power.monitor")
    
    init(targetEfficiency: Double) {
        self.targetEfficiency = targetEfficiency
    }
    
    func getCurrentEfficiency() -> Double {
        return queue.sync {
            let efficiency = measurements.reduce(0.0, +) / Double(max(1, measurements.count))
            measurements = Array(measurements.suffix(100))
            return efficiency
        }
    }
    
    func getCurrentLoad() -> Double {
        return queue.sync {
            return ProcessInfo.processInfo.systemUptime
        }
    }
    
    func getUnderrunCount() -> Int {
        return queue.sync { underrunCount }
    }
}