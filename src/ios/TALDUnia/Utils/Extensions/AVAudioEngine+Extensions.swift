// AVFoundation v17.0+
import AVFoundation
import AudioFormat

/// Constants for ESS ES9038PRO DAC optimization
private let kDefaultMaximumFrameCount: AVAudioFrameCount = 256
private let kOptimalIOBufferDuration: TimeInterval = 0.005
private let kESS9038PRO_OptimalSampleRate: Double = 192000
private let kESS9038PRO_BitDepth: Int = 32

/// Extension providing hardware-optimized audio processing capabilities for AVAudioEngine
extension AVAudioEngine {
    
    // MARK: - High Quality Audio Configuration
    
    /// Configures the AVAudioEngine for optimal high-quality audio processing with ESS ES9038PRO DAC optimization
    /// - Parameters:
    ///   - format: The desired audio format
    ///   - enableHardwareOptimization: Whether to enable hardware-specific optimizations
    /// - Returns: Result indicating success or detailed error
    public func configureForHighQualityAudio(format: AVAudioFormat,
                                           enableHardwareOptimization: Bool = true) -> Result<Void, Error> {
        // Validate format against hardware capabilities
        guard let audioFormat = AudioFormat() else {
            return .failure(AppError.audioError(
                reason: "Failed to initialize audio format",
                severity: .critical,
                context: ErrorContext()
            ))
        }
        
        do {
            try audioFormat.validateFormat(format).get()
            
            // Configure hardware-specific settings
            if enableHardwareOptimization {
                // Set optimal I/O buffer duration for ESS ES9038PRO DAC
                try self.setIOBufferDuration(kOptimalIOBufferDuration)
                
                // Configure maximum frames per slice
                try self.mainMixerNode.setVoiceProcessingEnabled(false)
                try self.mainMixerNode.setMaximumFrameCount(kDefaultMaximumFrameCount)
                
                // Enable manual rendering mode for precise control
                try self.enableManualRenderingMode(
                    .realtime,
                    format: format,
                    maximumFrameCount: kDefaultMaximumFrameCount
                )
            }
            
            // Configure input/output nodes
            inputNode.volume = 1.0
            mainMixerNode.outputVolume = 1.0
            
            // Set format for all nodes
            inputNode.inputFormat(forBus: 0) = format
            mainMixerNode.outputFormat(forBus: 0) = format
            outputNode.outputFormat(forBus: 0) = format
            
            return .success(())
            
        } catch {
            return .failure(AppError.audioError(
                reason: "Failed to configure audio engine: \(error.localizedDescription)",
                severity: .critical,
                context: ErrorContext(additionalInfo: [
                    "format": format,
                    "hardwareOptimization": enableHardwareOptimization
                ])
            ))
        }
    }
    
    // MARK: - Processing Tap Management
    
    /// Attaches a high-quality audio processing tap with real-time AI enhancement support
    /// - Parameters:
    ///   - node: The audio node to attach the tap to
    ///   - processingCallback: Callback for audio processing
    ///   - quality: The desired processing quality
    /// - Returns: Result indicating success or detailed error
    public func attachHighQualityProcessingTap(
        to node: AVAudioNode,
        processingCallback: @escaping (AVAudioPCMBuffer) -> AVAudioPCMBuffer,
        quality: ProcessingQuality = .maximum
    ) -> Result<Void, Error> {
        do {
            // Create processing tap with specified callback
            let tap = try MTAudioProcessingTap.create(
                callbacks: MTAudioProcessingTapCallbacks(
                    version: kMTAudioProcessingTapCallbacksVersion_0,
                    initialize: { tap in
                        // Set up tap context
                        tap.storage.assumingMemoryBound(to: ProcessingContext.self).pointee = ProcessingContext()
                    },
                    finalize: { tap in
                        // Clean up tap context
                        tap.storage.assumingMemoryBound(to: ProcessingContext.self).deallocate()
                    },
                    prepare: { tap, maxFrames, processingFormat in
                        // Prepare processing resources
                        let context = tap.storage.assumingMemoryBound(to: ProcessingContext.self).pointee
                        context.prepare(maxFrames: maxFrames, format: processingFormat)
                    },
                    unprepare: { tap in
                        // Release processing resources
                        let context = tap.storage.assumingMemoryBound(to: ProcessingContext.self).pointee
                        context.unprepare()
                    },
                    process: { tap, numberFrames, flags, bufferList, outNumberFrames, outBufferList in
                        // Process audio data
                        guard let inputBuffer = AVAudioPCMBuffer(pcmFormat: node.outputFormat(forBus: 0),
                                                               frameCapacity: numberFrames) else {
                            return kMTAudioProcessingTapError_InvalidParameter
                        }
                        
                        let processedBuffer = processingCallback(inputBuffer)
                        outNumberFrames.pointee = numberFrames
                        outBufferList.pointee = processedBuffer.mutableAudioBufferList.pointee
                        
                        return noErr
                    }
                ),
                callbacks: nil,
                maxFrames: UInt32(kDefaultMaximumFrameCount),
                flags: [quality == .maximum ? .preEffects : .postEffects]
            )
            
            // Attach tap to node
            try node.installTap(
                onBus: 0,
                bufferSize: AVAudioFrameCount(kDefaultMaximumFrameCount),
                format: node.outputFormat(forBus: 0),
                block: { buffer, time in
                    // Handle tap processing
                    _ = processingCallback(buffer)
                }
            )
            
            return .success(())
            
        } catch {
            return .failure(AppError.audioError(
                reason: "Failed to attach processing tap: \(error.localizedDescription)",
                severity: .error,
                context: ErrorContext(additionalInfo: [
                    "node": node,
                    "quality": quality
                ])
            ))
        }
    }
    
    // MARK: - Processing Chain Optimization
    
    /// Performs comprehensive optimization of the audio processing chain
    public func optimizeProcessingChain() {
        // Configure thread priority for audio processing
        let audioThread = Thread {
            Thread.current.threadPriority = 1.0
            Thread.current.qualityOfService = .userInteractive
        }
        audioThread.start()
        
        // Set up DMA transfer settings for ESS ES9038PRO DAC
        outputNode.setDMABufferSize(AVAudioFrameCount(kDefaultMaximumFrameCount))
        
        // Configure automatic load balancing
        mainMixerNode.autoLoadBalance = true
        
        // Set up performance monitoring
        let monitoringQueue = DispatchQueue(
            label: "com.taldunia.audio.monitoring",
            qos: .userInitiated
        )
        
        monitoringQueue.async {
            self.startPerformanceMonitoring()
        }
    }
    
    // MARK: - Private Helpers
    
    private func startPerformanceMonitoring() {
        // Monitor CPU usage
        let timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            
            let cpuUsage = self.mainMixerNode.averageCPULoad
            if cpuUsage > 0.7 {
                NotificationCenter.default.post(
                    name: Notification.Name("TALDUniaCPUWarning"),
                    object: nil,
                    userInfo: ["cpuLoad": cpuUsage]
                )
            }
        }
        RunLoop.current.add(timer, forMode: .common)
    }
}

// MARK: - Supporting Types

/// Represents audio processing quality levels
public enum ProcessingQuality {
    case maximum
    case balanced
    case minimum
}

/// Context for audio processing tap
private struct ProcessingContext {
    var maxFrames: UInt32 = 0
    var format: AudioStreamBasicDescription?
    
    mutating func prepare(maxFrames: UInt32, format: AudioStreamBasicDescription) {
        self.maxFrames = maxFrames
        self.format = format
    }
    
    func unprepare() {
        // Clean up any allocated resources
    }
}