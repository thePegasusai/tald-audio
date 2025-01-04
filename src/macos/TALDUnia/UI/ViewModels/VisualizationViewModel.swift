//
// VisualizationViewModel.swift
// TALD UNIA
//
// High-performance visualization view model with real-time audio monitoring
// Version: 1.0.0
//

import SwiftUI // macOS 13.0+
import Combine // macOS 13.0+

// MARK: - Constants

private let kVisualizationUpdateInterval: TimeInterval = 1.0 / 60.0
private let kMaxBufferSize: Int = 2048
private let kDefaultFFTSize: Int = 2048
private let kBufferPoolSize: Int = 8
private let kMaxLatencyThreshold: TimeInterval = 0.010

// MARK: - VisualizationViewModel

@MainActor
@Observable
public final class VisualizationViewModel {
    // MARK: - Properties
    
    private let audioEngine: AudioEngine
    private let spectrumAnalyzer: SpectrumAnalyzer
    private let waveformView: WaveformView
    private let vuMeter: VUMeter
    private let audioBufferPublisher = PassthroughSubject<AudioBuffer, Never>()
    private var updateTimer: Timer?
    private var isProcessing: Bool = false
    private var cancellables = Set<AnyCancellable>()
    
    // Performance monitoring
    private var currentLatency: TimeInterval = 0
    private var processingLoad: Double = 0
    private var thdPlusNoise: Double = 0
    private var bufferUnderruns: Int = 0
    
    // Quality management
    private var qualityLevel: Int = 2 // 0-2 scale
    private var hardwareAccelerated: Bool = true
    private var adaptiveQuality: Bool = true
    
    // MARK: - Initialization
    
    public init(audioEngine: AudioEngine) throws {
        self.audioEngine = audioEngine
        
        // Initialize visualization components with hardware acceleration
        self.spectrumAnalyzer = try SpectrumAnalyzer(
            frame: .zero,
            device: MTLCreateSystemDefaultDevice()
        )
        
        self.waveformView = WaveformView(
            buffer: CircularAudioBuffer(
                capacity: kMaxBufferSize,
                channels: AudioConstants.MAX_CHANNELS
            )
        )
        
        self.vuMeter = VUMeter(
            referenceLevel: -18.0,
            enableTHDNMonitoring: true
        )
        
        // Configure hardware acceleration
        configureHardwareAcceleration()
        
        // Setup update timer
        setupUpdateTimer()
        
        // Configure audio buffer subscription
        setupAudioBufferSubscription()
    }
    
    // MARK: - Public Interface
    
    public func startVisualization() {
        guard !isProcessing else { return }
        isProcessing = true
        
        // Start visualization components
        vuMeter.startMonitoring()
        updateTimer?.resume()
        
        // Configure hardware-optimized processing
        spectrumAnalyzer.configureHardwareAcceleration()
        waveformView.configureSIMDAcceleration()
        
        // Start performance monitoring
        startPerformanceMonitoring()
    }
    
    public func stopVisualization() {
        guard isProcessing else { return }
        isProcessing = false
        
        // Stop visualization components
        vuMeter.stopMonitoring()
        updateTimer?.suspend()
        
        // Clean up resources
        audioBufferPublisher.send(completion: .finished)
        cancellables.removeAll()
    }
    
    public func updateVisualizationSettings(_ settings: VisualizationSettings) {
        // Update quality settings
        qualityLevel = settings.qualityLevel
        adaptiveQuality = settings.adaptiveQuality
        
        // Configure components with new settings
        spectrumAnalyzer.setQualityLevel(qualityLevel)
        waveformView.setColorSpace(settings.useP3ColorSpace ? .displayP3 : .sRGB)
        vuMeter.setTHDNMonitoring(settings.monitorTHDN)
        
        // Update hardware acceleration if needed
        if hardwareAccelerated != settings.useHardwareAcceleration {
            hardwareAccelerated = settings.useHardwareAcceleration
            configureHardwareAcceleration()
        }
    }
    
    // MARK: - Private Methods
    
    private func configureHardwareAcceleration() {
        if hardwareAccelerated {
            spectrumAnalyzer.configureHardwareAcceleration()
            waveformView.configureSIMDAcceleration()
        }
    }
    
    private func setupUpdateTimer() {
        updateTimer = Timer(
            timeInterval: kVisualizationUpdateInterval,
            target: self,
            selector: #selector(processVisualizationUpdate),
            userInfo: nil,
            repeats: true
        )
        RunLoop.main.add(updateTimer!, forMode: .common)
    }
    
    private func setupAudioBufferSubscription() {
        audioBufferPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] buffer in
                self?.processVisualizationUpdate(buffer)
            }
            .store(in: &cancellables)
    }
    
    @objc private func processVisualizationUpdate(_ buffer: AudioBuffer) {
        let startTime = Date()
        
        // Update spectrum analyzer
        spectrumAnalyzer.updateSpectrum(buffer.floatChannelData?[0] ?? [])
        
        // Update waveform display
        waveformView.updateWaveform(buffer)
        
        // Update VU meter
        vuMeter.calibrate()
        
        // Monitor performance
        let processingTime = Date().timeIntervalSince(startTime)
        updatePerformanceMetrics(processingTime: processingTime)
        
        // Adjust quality if needed
        if adaptiveQuality {
            adjustQualityLevel(processingTime: processingTime)
        }
    }
    
    private func startPerformanceMonitoring() {
        // Reset metrics
        currentLatency = 0
        processingLoad = 0
        thdPlusNoise = 0
        bufferUnderruns = 0
    }
    
    private func updatePerformanceMetrics(processingTime: TimeInterval) {
        currentLatency = processingTime
        processingLoad = audioEngine.processingLoad
        thdPlusNoise = vuMeter.currentTHDN
        
        if processingTime > kMaxLatencyThreshold {
            bufferUnderruns += 1
        }
    }
    
    private func adjustQualityLevel(processingTime: TimeInterval) {
        if processingTime > kMaxLatencyThreshold && qualityLevel > 0 {
            qualityLevel -= 1
            spectrumAnalyzer.setQualityLevel(qualityLevel)
        } else if processingTime < kMaxLatencyThreshold * 0.5 && qualityLevel < 2 {
            qualityLevel += 1
            spectrumAnalyzer.setQualityLevel(qualityLevel)
        }
    }
}

// MARK: - Supporting Types

public struct VisualizationSettings {
    let qualityLevel: Int
    let adaptiveQuality: Bool
    let useHardwareAcceleration: Bool
    let useP3ColorSpace: Bool
    let monitorTHDN: Bool
}