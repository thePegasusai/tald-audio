//
// VisualizationView.swift
// TALD UNIA
//
// Professional-grade audio visualization with hardware acceleration and accessibility
// Version: 1.0.0
//

import SwiftUI // macOS 13.0+
import Combine // macOS 13.0+
import MetalKit // macOS 13.0+
import simd // macOS 13.0+

// MARK: - Constants

private let kDefaultUpdateInterval: TimeInterval = 1.0 / 120.0
private let kDefaultFFTSize: Int = 4096
private let kMaxLatencyThreshold: TimeInterval = 0.010
private let kMinimumContrastRatio: Double = 4.5

// MARK: - Visualization View

@available(macOS 13.0, *)
@MainActor
public struct VisualizationView: View {
    // MARK: - Properties
    
    @StateObject private var viewModel: VisualizationViewModel
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityHighContrast) private var highContrast
    
    private let colors: Colors
    private let metalDevice: MTLDevice?
    private let performanceMonitor: MetricsCollector
    
    // MARK: - Initialization
    
    public init(viewModel: VisualizationViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
        self.colors = Colors()
        self.metalDevice = MTLCreateSystemDefaultDevice()
        self.performanceMonitor = MetricsCollector.shared
    }
    
    // MARK: - View Body
    
    public var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Spectrum Analyzer
                SpectrumAnalyzer(
                    frame: geometry.frame(in: .local),
                    device: metalDevice
                )
                .frame(height: geometry.size.height * 0.5)
                .accessibilityLabel("Audio spectrum analyzer")
                
                // Waveform Display
                WaveformView(
                    buffer: viewModel.audioBuffer,
                    style: WaveformStyle(
                        color: colors.p3Primary,
                        lineWidth: highContrast ? 3.0 : 2.0,
                        antiAliasing: !highContrast,
                        interpolation: !reduceMotion
                    )
                )
                .frame(height: geometry.size.height * 0.3)
                .accessibilityLabel("Audio waveform display")
                
                // VU Meter
                VUMeter(
                    referenceLevel: -18.0,
                    enableTHDNMonitoring: true
                )
                .frame(height: geometry.size.height * 0.2)
                .accessibilityLabel("Volume unit meter")
            }
            .drawingGroup() // Enable Metal acceleration
            .colorSpace(.displayP3)
            .onChange(of: colorScheme) { _ in
                updateVisualizationSettings()
            }
            .onChange(of: reduceMotion) { _ in
                updateVisualizationSettings()
            }
            .onChange(of: highContrast) { _ in
                updateVisualizationSettings()
            }
        }
        .onAppear {
            configureVisualization()
        }
        .onDisappear {
            cleanupVisualization()
        }
    }
    
    // MARK: - Private Methods
    
    private func configureVisualization() {
        // Configure hardware acceleration
        viewModel.configureHardwareAcceleration()
        
        // Start visualization and monitoring
        viewModel.startVisualization()
        performanceMonitor.startCollection()
        
        // Configure initial settings
        updateVisualizationSettings()
    }
    
    private func updateVisualizationSettings() {
        let settings = VisualizationSettings(
            qualityLevel: highContrast ? 2 : 1,
            adaptiveQuality: !highContrast,
            useHardwareAcceleration: true,
            useP3ColorSpace: true,
            monitorTHDN: true
        )
        
        viewModel.updateVisualizationSettings(settings)
    }
    
    private func cleanupVisualization() {
        viewModel.stopVisualization()
        performanceMonitor.stopCollection()
    }
}

// MARK: - Preview Provider

struct VisualizationView_Previews: PreviewProvider {
    static var previews: some View {
        VisualizationView(
            viewModel: VisualizationViewModel(
                audioEngine: try! AudioEngine()
            )
        )
        .frame(width: 800, height: 400)
        .preferredColorScheme(.dark)
    }
}

// MARK: - Accessibility Extensions

extension VisualizationView {
    private func configureAccessibility() {
        // Configure accessibility properties
        let accessibilityConfig = AccessibilityConfiguration(
            reduceMotion: reduceMotion,
            highContrast: highContrast,
            minimumContrastRatio: kMinimumContrastRatio,
            useAccessibilityLabels: true
        )
        
        // Apply accessibility settings
        viewModel.updateAccessibilitySettings(accessibilityConfig)
    }
}

// MARK: - Performance Monitoring

extension VisualizationView {
    private func monitorPerformance() {
        performanceMonitor.recordAudioMetrics(
            buffer: viewModel.audioBuffer,
            startTime: .now(),
            endTime: .now()
        )
    }
}