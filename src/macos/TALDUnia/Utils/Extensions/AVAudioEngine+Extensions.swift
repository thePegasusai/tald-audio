//
// AVAudioEngine+Extensions.swift
// TALD UNIA
//
// AVAudioEngine extensions for premium audio processing with ESS ES9038PRO DAC optimization
// Version: 1.0.0
//

import Foundation // macOS 13.0+
import AVFoundation // macOS 13.0+

// MARK: - Constants

private let kDefaultSampleRate: Double = 192000.0
private let kDefaultMaximumFrameCount: AVAudioFrameCount = 512
private let kDefaultIOBufferDuration: TimeInterval = 0.005 // 5ms for optimal latency
private let kOptimalProcessingInterval: TimeInterval = 0.003 // 3ms target for AI processing

// MARK: - AVAudioEngine Extension
extension AVAudioEngine {
    
    /// Configures AVAudioEngine with optimal settings for TALD UNIA system including ESS ES9038PRO DAC optimization
    /// - Parameters:
    ///   - format: The audio format to use for processing
    ///   - enableHardwareOptimization: Whether to enable hardware-specific optimizations
    /// - Returns: Result indicating success or failure with error details
    @discardableResult
    func optimizeForTALDUNIA(format: AudioFormat, enableHardwareOptimization: Bool = true) -> Result<Void, Error> {
        do {
            // Validate input format against hardware capabilities
            guard format.validateFormat(format.currentFormat) else {
                throw TALDError.configurationError(
                    code: "INVALID_FORMAT",
                    message: "Audio format not supported by hardware",
                    metadata: ErrorMetadata(
                        timestamp: Date(),
                        component: "AVAudioEngine",
                        additionalInfo: ["format": "\(format.currentFormat)"]
                    )
                )
            }
            
            // Configure hardware settings
            if enableHardwareOptimization {
                try AudioHardwareManager().optimizeHardwareSettings()
                try AudioHardwareManager().configureESSDAC()
            }
            
            // Set optimal buffer configuration
            inputNode.volume = 1.0
            inputNode.reset()
            outputNode.volume = 1.0
            outputNode.reset()
            
            mainMixerNode.outputVolume = 1.0
            mainMixerNode.reset()
            
            // Configure buffer settings for minimal latency
            try setIOBufferDuration(kDefaultIOBufferDuration)
            try setMaximumFrameCount(kDefaultMaximumFrameCount)
            
            // Initialize processing chain
            guard configureProcessingChain() else {
                throw TALDError.audioProcessingError(
                    code: "CHAIN_CONFIG_FAILED",
                    message: "Failed to configure audio processing chain",
                    metadata: ErrorMetadata(
                        timestamp: Date(),
                        component: "AVAudioEngine",
                        additionalInfo: ["enableHardwareOptimization": "\(enableHardwareOptimization)"]
                    )
                )
            }
            
            // Set optimal latency
            let achievedLatency = setOptimalLatency()
            guard achievedLatency <= AudioConstants.TARGET_LATENCY else {
                throw TALDError.audioProcessingError(
                    code: "LATENCY_TARGET_MISSED",
                    message: "Failed to achieve target latency",
                    metadata: ErrorMetadata(
                        timestamp: Date(),
                        component: "AVAudioEngine",
                        additionalInfo: ["achievedLatency": "\(achievedLatency)"]
                    )
                )
            }
            
            return .success(())
        } catch {
            return .failure(error)
        }
    }
    
    /// Sets up the audio processing chain with AI enhancement and spatial processing nodes
    /// - Returns: Success status of configuration
    private func configureProcessingChain() -> Bool {
        do {
            // Initialize processing nodes
            let aiProcessor = AVAudioUnit()
            let spatialProcessor = AVAudioUnit()
            
            // Configure AI enhancement node
            guard attachOptimizedNodes(aiProcessor, format: mainMixerNode.outputFormat(forBus: 0)) else {
                return false
            }
            
            // Configure spatial processing node
            guard attachOptimizedNodes(spatialProcessor, format: mainMixerNode.outputFormat(forBus: 0)) else {
                return false
            }
            
            // Connect processing chain
            connect(mainMixerNode, to: aiProcessor, format: mainMixerNode.outputFormat(forBus: 0))
            connect(aiProcessor, to: spatialProcessor, format: mainMixerNode.outputFormat(forBus: 0))
            connect(spatialProcessor, to: outputNode, format: mainMixerNode.outputFormat(forBus: 0))
            
            return true
        } catch {
            return false
        }
    }
    
    /// Attaches and configures audio processing nodes with optimal settings
    /// - Parameters:
    ///   - node: The audio node to attach
    ///   - format: The audio format to use
    /// - Returns: Success status of node attachment
    private func attachOptimizedNodes(_ node: AVAudioNode, format: AVAudioFormat) -> Bool {
        do {
            // Attach node with optimized settings
            attachNode(node)
            
            // Configure node parameters
            node.reset()
            
            // Set up performance monitoring points
            let nodeLatency = node.latency
            let outputLatency = outputNode.presentationLatency
            
            guard nodeLatency + outputLatency <= kOptimalProcessingInterval else {
                return false
            }
            
            return true
        } catch {
            return false
        }
    }
    
    /// Configures engine for optimal latency based on hardware capabilities
    /// - Returns: Achieved latency value
    private func setOptimalLatency() -> TimeInterval {
        do {
            // Configure for minimum latency
            try setIOBufferDuration(kDefaultIOBufferDuration)
            
            // Calculate actual latency
            let inputLatency = inputNode.presentationLatency
            let outputLatency = outputNode.presentationLatency
            let processingLatency = mainMixerNode.latency
            
            let totalLatency = inputLatency + outputLatency + processingLatency
            
            return totalLatency
        } catch {
            return TimeInterval.infinity
        }
    }
}