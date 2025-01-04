// Foundation v17.0+
import SwiftUI
import Combine
import Metal
import MetalKit
import Accelerate
import os.signpost

// MARK: - Constants

private let kDefaultPadding: CGFloat = 16.0
private let kAnimationDuration: TimeInterval = 0.3
private let kMaxRefreshRate: Double = 60.0
private let kMinRefreshRate: Double = 30.0
private let kLatencyThreshold: TimeInterval = 0.010
private let kMemoryWarningThreshold: Float = 85.0

// MARK: - VisualizationView

@available(iOS 14.0, *)
@MainActor
public struct VisualizationView: View {
    
    // MARK: - Properties
    
    @StateObject private var viewModel: VisualizationViewModel
    @State private var isFullScreen: Bool = false
    @State private var currentFPS: Double = 0.0
    @State private var memoryUsage: Float = 0.0
    
    private let spectrumAnalyzer: SpectrumAnalyzer
    private let waveformView: WaveformView
    private let vuMeter: VUMeter
    
    private let metalDevice: MTLDevice?
    private let displayLink: CADisplayLink?
    
    // MARK: - Initialization
    
    public init(viewModel: VisualizationViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
        
        // Initialize Metal device
        metalDevice = MTLCreateSystemDefaultDevice()
        
        // Initialize visualization components
        do {
            spectrumAnalyzer = try SpectrumAnalyzer(
                fftProcessor: FFTProcessor(),
                reducedMotion: UIAccessibility.isReduceMotionEnabled,
                isPowerEfficient: true
            )
            
            waveformView = WaveformView(
                buffer: AudioBuffer(
                    format: AudioFormat(),
                    bufferSize: AudioConstants.bufferSize
                ),
                color: Color(VisualizationColors.waveformGradient),
                options: [.antiAliased, .powerEfficient]
            )
            
            vuMeter = VUMeter(
                standard: .ebuR128,
                referenceLevel: 0.0
            )
            
        } catch {
            fatalError("Failed to initialize visualization components: \(error)")
        }
        
        // Configure display refresh
        displayLink = CADisplayLink(
            target: self,
            selector: #selector(handleDisplayUpdate)
        )
        displayLink?.preferredFrameRate = Int(kMaxRefreshRate)
    }
    
    // MARK: - View Body
    
    public var body: some View {
        GeometryReader { geometry in
            VStack(spacing: kDefaultPadding) {
                // Spectrum Analyzer
                MetalView(device: metalDevice) { context in
                    spectrumAnalyzer.draw(in: context)
                }
                .frame(height: geometry.size.height * 0.4)
                .cornerRadius(8)
                
                // Waveform Display
                waveformView
                    .frame(height: geometry.size.height * 0.3)
                    .cornerRadius(8)
                
                // VU Meter
                vuMeter
                    .frame(height: geometry.size.height * 0.2)
                
                // Performance Metrics
                performanceMetricsView
            }
            .padding(kDefaultPadding)
            .background(Colors.background)
            .onChange(of: geometry.size) { _ in
                updateLayout()
            }
            .onAppear {
                startVisualization()
            }
            .onDisappear {
                stopVisualization()
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Audio visualization display")
        .accessibilityValue(generateAccessibilityDescription())
    }
    
    // MARK: - Performance Metrics View
    
    private var performanceMetricsView: some View {
        HStack(spacing: kDefaultPadding) {
            // Latency Indicator
            MetricView(
                title: "Latency",
                value: String(format: "%.1f ms", viewModel.currentLatency * 1000),
                warning: viewModel.currentLatency > kLatencyThreshold
            )
            
            // Processing Load
            MetricView(
                title: "CPU Load",
                value: String(format: "%.0f%%", viewModel.processingLoad),
                warning: viewModel.processingLoad > 80
            )
            
            // Frame Rate
            MetricView(
                title: "FPS",
                value: String(format: "%.0f", currentFPS),
                warning: currentFPS < kMinRefreshRate
            )
        }
        .font(.system(.caption, design: .monospaced))
    }
    
    // MARK: - Private Methods
    
    private func startVisualization() {
        // Start visualization components
        let result = viewModel.startVisualization()
        switch result {
        case .success:
            spectrumAnalyzer.startAnalyzer()
            displayLink?.add(to: .main, forMode: .common)
        case .failure(let error):
            os_log(.error, "Failed to start visualization: %{public}@", error.localizedDescription)
        }
    }
    
    private func stopVisualization() {
        viewModel.stopVisualization()
        spectrumAnalyzer.stopAnalyzer()
        displayLink?.invalidate()
    }
    
    private func updateLayout() {
        // Update layout with animation
        withAnimation(.easeInOut(duration: kAnimationDuration)) {
            // Layout updates here
        }
    }
    
    @objc private func handleDisplayUpdate() {
        // Update performance metrics
        currentFPS = 1.0 / (displayLink?.targetTimestamp ?? 1.0 / kMaxRefreshRate)
        memoryUsage = Float(ProcessInfo.processInfo.physicalMemory) / 1024 / 1024
        
        // Check performance thresholds
        if memoryUsage > kMemoryWarningThreshold {
            os_log(.warning, "High memory usage detected: %.1f MB", memoryUsage)
        }
    }
    
    private func generateAccessibilityDescription() -> String {
        let components = [
            "Spectrum analyzer showing frequency content",
            "Waveform display showing audio amplitude",
            "VU meter showing audio levels",
            String(format: "Processing latency: %.1f milliseconds", viewModel.currentLatency * 1000),
            String(format: "CPU usage: %.0f percent", viewModel.processingLoad)
        ]
        return components.joined(separator: ", ")
    }
}

// MARK: - Supporting Views

private struct MetricView: View {
    let title: String
    let value: String
    let warning: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .foregroundColor(Colors.primary)
            Text(value)
                .foregroundColor(warning ? Colors.error : Colors.primary)
        }
        .padding(8)
        .background(Colors.surface)
        .cornerRadius(4)
    }
}

// MARK: - Metal View

private struct MetalView: UIViewRepresentable {
    let device: MTLDevice?
    let drawHandler: (MTKView) -> Void
    
    func makeUIView(context: Context) -> MTKView {
        let view = MTKView(frame: .zero, device: device)
        view.enableSetNeedsDisplay = true
        view.isPaused = false
        view.framebufferOnly = false
        return view
    }
    
    func updateUIView(_ uiView: MTKView, context: Context) {
        drawHandler(uiView)
    }
}