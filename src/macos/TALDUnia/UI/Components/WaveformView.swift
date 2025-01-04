//
// WaveformView.swift
// TALD UNIA
//
// High-performance SwiftUI waveform visualization with SIMD acceleration and P3 color space support
// Version: 1.0.0
//

import SwiftUI // macOS 13.0+
import Combine // macOS 13.0+
import CoreGraphics // macOS 13.0+
import simd // macOS 13.0+

// MARK: - Constants

private let kDefaultSampleCount: Int = 1024
private let kMaxAmplitude: Float = 1.0
private let kUpdateInterval: TimeInterval = 1.0 / 60.0
private let kBufferPoolSize: Int = 8
private let kMaxFrameLatency: TimeInterval = 0.010
private let kSIMDVectorSize: Int = 8

// MARK: - Waveform Style

public struct WaveformStyle {
    let color: Color
    let lineWidth: CGFloat
    let antiAliasing: Bool
    let interpolation: Bool
    
    public init(
        color: Color = .primary,
        lineWidth: CGFloat = 2.0,
        antiAliasing: Bool = true,
        interpolation: Bool = true
    ) {
        self.color = color
        self.lineWidth = lineWidth
        self.antiAliasing = antiAliasing
        self.interpolation = interpolation
    }
}

// MARK: - Performance Monitoring

private struct PerformanceMetrics {
    var renderTime: TimeInterval = 0
    var updateLatency: TimeInterval = 0
    var bufferUtilization: Double = 0
    var frameDrops: Int = 0
    
    mutating func update(renderTime: TimeInterval, latency: TimeInterval) {
        self.renderTime = renderTime
        self.updateLatency = latency
        if latency > kMaxFrameLatency {
            frameDrops += 1
        }
    }
}

// MARK: - Waveform View

@available(macOS 13.0, *)
@MainActor
public struct WaveformView: View {
    // MARK: - Properties
    
    private let audioBuffer: AudioBuffer
    private let bufferPublisher: PassthroughSubject<AudioBuffer, Never>
    private var updateSubscription: AnyCancellable?
    @State private var waveformPath: Path = Path()
    @State private var waveformColor: Color
    @State private var lineWidth: CGFloat
    @State private var metrics: PerformanceMetrics = PerformanceMetrics()
    
    // MARK: - Initialization
    
    public init(buffer: AudioBuffer, style: WaveformStyle = WaveformStyle()) {
        self.audioBuffer = buffer
        self.bufferPublisher = PassthroughSubject<AudioBuffer, Never>()
        self.waveformColor = style.color
        self.lineWidth = style.lineWidth
        
        // Configure update subscription
        self.updateSubscription = bufferPublisher
            .throttle(for: .seconds(kUpdateInterval), scheduler: DispatchQueue.main, latest: true)
            .sink { [weak self] buffer in
                self?.updateWaveform(buffer)
            }
    }
    
    // MARK: - View Body
    
    public var body: some View {
        GeometryReader { geometry in
            Canvas { context, size in
                // Apply P3 color space and hardware acceleration
                context.addFilter(.colorMultiply(waveformColor))
                context.scaleBy(x: 1.0, y: size.height / 2)
                context.translateBy(x: 0, y: 1.0)
                
                // Draw optimized waveform path
                context.stroke(
                    waveformPath,
                    with: .color(waveformColor),
                    lineWidth: lineWidth
                )
            }
            .drawingGroup() // Enable Metal acceleration
            .colorSpace(.displayP3) // Use P3 color space
            .onChange(of: geometry.size) { _ in
                updateWaveform(audioBuffer)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Audio waveform visualization")
    }
    
    // MARK: - Private Methods
    
    private func updateWaveform(_ buffer: AudioBuffer) {
        let startTime = Date()
        
        // Calculate waveform path using SIMD acceleration
        let bounds = CGRect(x: 0, y: 0, width: UIScreen.main.bounds.width, height: UIScreen.main.bounds.height)
        waveformPath = calculateWaveformPath(buffer: buffer, bounds: bounds)
        
        // Update performance metrics
        let updateTime = Date().timeIntervalSince(startTime)
        metrics.update(
            renderTime: updateTime,
            latency: buffer.currentStatistics.averageLatency
        )
    }
    
    @inlinable
    private func calculateWaveformPath(buffer: AudioBuffer, bounds: CGRect) -> Path {
        var path = Path()
        
        // Read audio data using SIMD vectors
        let samples = UnsafeMutablePointer<Float>.allocate(capacity: kDefaultSampleCount)
        defer { samples.deallocate() }
        
        guard case .success = buffer.readThreadSafe(samples, frameCount: kDefaultSampleCount) else {
            return path
        }
        
        // Process samples using SIMD
        let vectorCount = kDefaultSampleCount / kSIMDVectorSize
        let vectors = UnsafeBufferPointer(start: samples, count: kDefaultSampleCount)
            .withMemoryRebound(to: SIMD8<Float>.self) { $0 }
        
        // Calculate points with SIMD acceleration
        let width = bounds.width
        let height = bounds.height
        let pointSpacing = width / CGFloat(kDefaultSampleCount - 1)
        
        path.move(to: CGPoint(x: 0, y: height / 2))
        
        for i in 0..<vectorCount {
            let vector = vectors[i]
            for j in 0..<kSIMDVectorSize {
                let x = CGFloat(i * kSIMDVectorSize + j) * pointSpacing
                let y = CGFloat(vector[j]) * height / 2
                path.addLine(to: CGPoint(x: x, y: y + height / 2))
            }
        }
        
        return path
    }
}

// MARK: - Public Interface

extension WaveformView {
    public func setAppearance(_ style: WaveformStyle) {
        waveformColor = style.color
        lineWidth = style.lineWidth
    }
    
    public func getPerformanceMetrics() -> PerformanceMetrics {
        return metrics
    }
}