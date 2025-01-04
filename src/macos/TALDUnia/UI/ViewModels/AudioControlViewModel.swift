//
// AudioControlViewModel.swift
// TALD UNIA
//
// ViewModel for managing audio control interface with enhanced performance monitoring
// Version: 1.0.0
//

import Foundation // macOS 13.0+
import Combine // macOS 13.0+
import SwiftUI // macOS 13.0+
import os.log // macOS 13.0+

// MARK: - Constants

private let kDefaultVolume: Double = 0.75
private let kMinVolume: Double = 0.0
private let kMaxVolume: Double = 1.0
private let kVolumeUpdateThreshold: TimeInterval = 0.05
private let kMaxProcessingLatency: TimeInterval = 0.010
private let kPerformanceMonitoringInterval: TimeInterval = 1.0
private let kErrorRecoveryAttempts: Int = 3

// MARK: - Performance Metrics

private struct PerformanceMetrics {
    var currentLatency: Double = 0.0
    var processingLoad: Double = 0.0
    var thdPlusNoise: Double = 0.0
    var bufferUtilization: Double = 0.0
    var timestamp: Date = Date()
}

// MARK: - Audio Control ViewModel

@MainActor
@Observable
public final class AudioControlViewModel {
    // MARK: - Properties
    
    private let audioEngine: AudioEngine
    private let spatialProcessor: SpatialProcessor
    private let performanceLog: OSLog
    private let processingQueue: DispatchQueue
    
    private var volumeUpdateSubscription: AnyCancellable?
    private var performanceMonitor: Timer?
    private var errorRecoveryCount: Int = 0
    
    // Published state
    @Published private(set) var currentMetrics = PerformanceMetrics()
    @Published private(set) var isPlaying: Bool = false
    @Published private(set) var volume: Double = kDefaultVolume
    @Published private(set) var isEnhancementEnabled: Bool = true
    @Published private(set) var isSpatialEnabled: Bool = true
    @Published private(set) var errorMessage: String?
    
    // Performance monitoring
    private let metricsPublisher = CurrentValueSubject<PerformanceMetrics, Never>(PerformanceMetrics())
    private let volumeUpdatePublisher = PassthroughSubject<Void, Never>()
    
    // MARK: - Initialization
    
    public init() throws {
        // Initialize audio components
        self.audioEngine = try AudioEngine()
        self.spatialProcessor = try SpatialProcessor(config: SpatialConfiguration())
        
        // Configure processing queue
        self.processingQueue = DispatchQueue(
            label: "com.tald.unia.audiocontrol",
            qos: .userInteractive
        )
        
        // Initialize performance logging
        self.performanceLog = OSLog(
            subsystem: "com.tald.unia.audio",
            category: "AudioControl"
        )
        
        // Setup volume update debouncing
        setupVolumeDebouncing()
        
        // Start performance monitoring
        startPerformanceMonitoring()
    }
    
    // MARK: - Public Interface
    
    public func togglePlayback() -> Result<Void, TALDError> {
        let startTime = Date()
        
        do {
            if isPlaying {
                audioEngine.stop()
            } else {
                guard case .success = try audioEngine.start() else {
                    throw TALDError.audioProcessingError(
                        code: "START_FAILED",
                        message: "Failed to start audio engine",
                        metadata: ErrorMetadata(
                            timestamp: Date(),
                            component: "AudioControlViewModel",
                            additionalInfo: [:]
                        )
                    )
                }
            }
            
            isPlaying.toggle()
            
            // Update performance metrics
            let processingTime = Date().timeIntervalSince(startTime)
            updatePerformanceMetrics(latency: processingTime)
            
            return .success(())
        } catch {
            handleError(error)
            return .failure(error as? TALDError ?? TALDError.audioProcessingError(
                code: "PLAYBACK_ERROR",
                message: error.localizedDescription,
                metadata: ErrorMetadata(
                    timestamp: Date(),
                    component: "AudioControlViewModel",
                    additionalInfo: [:]
                )
            ))
        }
    }
    
    public func updateVolume(_ newVolume: Double) -> Result<Void, TALDError> {
        let startTime = Date()
        
        // Validate volume range
        guard case .success(let validatedVolume) = validateVolumeRange(newVolume) else {
            return .failure(TALDError.audioProcessingError(
                code: "INVALID_VOLUME",
                message: "Volume value out of range",
                metadata: ErrorMetadata(
                    timestamp: Date(),
                    component: "AudioControlViewModel",
                    additionalInfo: ["volume": "\(newVolume)"]
                )
            ))
        }
        
        // Update volume state
        volume = validatedVolume
        
        // Trigger debounced update
        volumeUpdatePublisher.send()
        
        // Update performance metrics
        let processingTime = Date().timeIntervalSince(startTime)
        updatePerformanceMetrics(latency: processingTime)
        
        return .success(())
    }
    
    public func toggleEnhancement() -> Result<Void, TALDError> {
        isEnhancementEnabled.toggle()
        return updateEngineConfiguration()
    }
    
    public func toggleSpatialAudio() -> Result<Void, TALDError> {
        isSpatialEnabled.toggle()
        return updateEngineConfiguration()
    }
    
    // MARK: - Private Methods
    
    private func setupVolumeDebouncing() {
        volumeUpdateSubscription = volumeUpdatePublisher
            .debounce(for: .seconds(kVolumeUpdateThreshold), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                guard let self = self else { return }
                _ = self.updateEngineConfiguration()
            }
    }
    
    private func startPerformanceMonitoring() {
        performanceMonitor = Timer.scheduledTimer(
            withTimeInterval: kPerformanceMonitoringInterval,
            repeats: true
        ) { [weak self] _ in
            self?.monitorPerformance()
        }
    }
    
    private func monitorPerformance() {
        processingQueue.async { [weak self] in
            guard let self = self else { return }
            
            // Collect metrics from audio engine
            let engineMetrics = self.audioEngine.getPerformanceMetrics()
            let spatialMetrics = self.spatialProcessor.monitorPerformance()
            
            // Update current metrics
            let metrics = PerformanceMetrics(
                currentLatency: engineMetrics.currentLatency,
                processingLoad: engineMetrics.processingLoad,
                thdPlusNoise: engineMetrics.thdPlusNoise,
                bufferUtilization: engineMetrics.bufferUtilization,
                timestamp: Date()
            )
            
            // Publish metrics
            Task { @MainActor in
                self.currentMetrics = metrics
                self.metricsPublisher.send(metrics)
            }
            
            // Log performance data
            os_signpost(.event, log: self.performanceLog,
                       name: "Performance Update",
                       "latency: %.3fms, load: %.1f%%, THD+N: %.6f%%",
                       metrics.currentLatency * 1000,
                       metrics.processingLoad * 100,
                       metrics.thdPlusNoise * 100)
        }
    }
    
    private func updateEngineConfiguration() -> Result<Void, TALDError> {
        let startTime = Date()
        
        do {
            try audioEngine.updateEngineConfiguration(
                volume: volume,
                enhancementEnabled: isEnhancementEnabled,
                spatialEnabled: isSpatialEnabled
            )
            
            let processingTime = Date().timeIntervalSince(startTime)
            updatePerformanceMetrics(latency: processingTime)
            
            return .success(())
        } catch {
            handleError(error)
            return .failure(error as? TALDError ?? TALDError.audioProcessingError(
                code: "CONFIG_UPDATE_FAILED",
                message: error.localizedDescription,
                metadata: ErrorMetadata(
                    timestamp: Date(),
                    component: "AudioControlViewModel",
                    additionalInfo: [:]
                )
            ))
        }
    }
    
    private func validateVolumeRange(_ value: Double) -> Result<Double, TALDError> {
        guard value >= kMinVolume && value <= kMaxVolume else {
            return .failure(TALDError.audioProcessingError(
                code: "INVALID_VOLUME",
                message: "Volume out of valid range",
                metadata: ErrorMetadata(
                    timestamp: Date(),
                    component: "AudioControlViewModel",
                    additionalInfo: ["value": "\(value)"]
                )
            ))
        }
        return .success(value)
    }
    
    private func updatePerformanceMetrics(latency: TimeInterval) {
        if latency > kMaxProcessingLatency {
            os_signpost(.event, log: performanceLog,
                       name: "Excessive Latency",
                       "Processing time exceeded threshold: %.3fms",
                       latency * 1000)
        }
        
        currentMetrics.currentLatency = latency
        metricsPublisher.send(currentMetrics)
    }
    
    private func handleError(_ error: Error) {
        errorRecoveryCount += 1
        
        if errorRecoveryCount <= kErrorRecoveryAttempts {
            // Attempt recovery
            do {
                try audioEngine.resetEngine()
                errorRecoveryCount = 0
            } catch {
                errorMessage = error.localizedDescription
            }
        } else {
            errorMessage = error.localizedDescription
        }
        
        Logger.shared.error(
            error,
            context: "AudioControlViewModel",
            metadata: [
                "recoveryAttempt": "\(errorRecoveryCount)",
                "isPlaying": "\(isPlaying)"
            ]
        )
    }
}