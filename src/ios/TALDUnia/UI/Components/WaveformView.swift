// Foundation v17.0+
import SwiftUI
import Accelerate
import AVFoundation

// MARK: - Constants

private enum WaveformConstants {
    static let kDefaultSampleCount: Int = 1024
    static let kMinSampleValue: Float = -1.0
    static let kMaxSampleValue: Float = 1.0
    static let kDefaultLineWidth: CGFloat = 2.0
    static let kMaxRefreshRate: Double = 60.0
    static let kBufferRecycleThreshold: Int = 8192
}

// MARK: - Display Options

public struct WaveformDisplayOptions: OptionSet {
    public let rawValue: Int
    
    public static let antiAliased = WaveformDisplayOptions(rawValue: 1 << 0)
    public static let powerEfficient = WaveformDisplayOptions(rawValue: 1 << 1)
    public static let highContrast = WaveformDisplayOptions(rawValue: 1 << 2)
    public static let reducedMotion = WaveformDisplayOptions(rawValue: 1 << 3)
    
    public init(rawValue: Int) {
        self.rawValue = rawValue
    }
}

// MARK: - Waveform View

/// A high-performance SwiftUI view that provides real-time waveform visualization of audio data
@available(iOS 14.0, *)
public struct WaveformView: View {
    // MARK: - Properties
    
    private let audioBuffer: AudioBuffer
    @State private var waveformPoints: [CGPoint] = []
    @State private var isAnimating: Bool = false
    
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.displayScale) private var displayScale
    
    private let waveformColor: Color
    private let lineWidth: CGFloat
    private let displayOptions: WaveformDisplayOptions
    
    private let displayLink: DisplayLink
    private let bufferRecycler: BufferRecycler
    
    // MARK: - Initialization
    
    /// Creates a new waveform visualization view
    /// - Parameters:
    ///   - buffer: Audio buffer to visualize
    ///   - color: Optional custom waveform color
    ///   - lineWidth: Optional custom line width
    ///   - options: Display configuration options
    public init(buffer: AudioBuffer,
                color: Color? = nil,
                lineWidth: CGFloat = WaveformConstants.kDefaultLineWidth,
                options: WaveformDisplayOptions = [.antiAliased]) {
        self.audioBuffer = buffer
        self.waveformColor = color ?? Color(Colors.waveformGradient)
        self.lineWidth = lineWidth
        self.displayOptions = options
        
        // Initialize display link with power-efficient refresh rate
        self.displayLink = DisplayLink(
            preferredFrameRate: displayOptions.contains(.powerEfficient) ? 30 : 60
        )
        
        // Initialize buffer recycler
        self.bufferRecycler = BufferRecycler(
            capacity: WaveformConstants.kBufferRecycleThreshold
        )
    }
    
    // MARK: - View Body
    
    public var body: some View {
        GeometryReader { geometry in
            Path { path in
                guard !waveformPoints.isEmpty else { return }
                
                path.move(to: waveformPoints[0])
                for point in waveformPoints.dropFirst() {
                    path.addLine(to: point)
                }
            }
            .stroke(
                waveformColor,
                style: StrokeStyle(
                    lineWidth: lineWidth,
                    lineCap: .round,
                    lineJoin: .round,
                    miterLimit: 2,
                    dash: [],
                    dashPhase: 0
                )
            )
            .animation(
                displayOptions.contains(.reducedMotion)
                    ? .none
                    : .linear(duration: 0.1),
                value: waveformPoints
            )
            .onChange(of: geometry.size) { _ in
                updateWaveform(size: geometry.size)
            }
            .onAppear {
                startWaveformUpdates(size: geometry.size)
            }
            .onDisappear {
                stopWaveformUpdates()
            }
        }
        .accessibility(label: Text("Audio waveform visualization"))
        .accessibility(value: Text(generateAccessibilityDescription()))
        .accessibilityElement(children: .ignore)
    }
    
    // MARK: - Private Methods
    
    private func startWaveformUpdates(size: CGSize) {
        displayLink.start { [weak self] in
            self?.updateWaveform(size: size)
        }
    }
    
    private func stopWaveformUpdates() {
        displayLink.stop()
        bufferRecycler.reset()
    }
    
    @inline(__always)
    private func calculateWaveformPoints(from samples: UnsafePointer<Float>,
                                       count: Int,
                                       size: CGSize,
                                       scale: Float) -> [CGPoint] {
        // Validate input parameters
        guard count > 0, size.width > 0, size.height > 0 else { return [] }
        
        // Prepare SIMD vectors for processing
        let vectorCount = (count + 3) / 4
        let vectors = UnsafeBufferPointer(start: samples, count: count)
            .withMemoryRebound(to: SIMD4<Float>.self) { $0 }
        
        // Process samples using SIMD acceleration
        var points = [CGPoint]()
        points.reserveCapacity(count)
        
        let width = Float(size.width)
        let height = Float(size.height)
        let midY = height / 2
        
        for i in 0..<vectorCount {
            let vector = vectors[i]
            let x = Float(i) * width / Float(vectorCount)
            
            // Apply anti-aliasing if enabled
            let y = displayOptions.contains(.antiAliased)
                ? simd_smoothstep(
                    SIMD4(repeating: WaveformConstants.kMinSampleValue),
                    SIMD4(repeating: WaveformConstants.kMaxSampleValue),
                    vector * scale
                )
                : vector * scale
            
            // Convert to screen coordinates
            points.append(CGPoint(
                x: Double(x),
                y: Double(midY + y.x * Float(midY))
            ))
        }
        
        return points
    }
    
    private func updateWaveform(size: CGSize) {
        // Get recycled buffer
        let buffer = bufferRecycler.nextBuffer()
        
        // Read audio samples
        let result = audioBuffer.readFromBuffer(
            into: buffer,
            frames: WaveformConstants.kDefaultSampleCount
        )
        
        guard case .success(let count) = result else { return }
        
        // Calculate scale factor based on display options
        let scale: Float = displayOptions.contains(.highContrast) ? 1.0 : 0.8
        
        // Update points with SIMD acceleration
        waveformPoints = calculateWaveformPoints(
            from: buffer,
            count: count,
            size: size,
            scale: scale
        )
    }
    
    private func generateAccessibilityDescription() -> String {
        let amplitudeDescription = waveformPoints.map { point in
            let normalizedAmplitude = (point.y - waveformPoints[0].y) /
                (WaveformConstants.kMaxSampleValue - WaveformConstants.kMinSampleValue)
            return abs(normalizedAmplitude) < 0.3 ? "low" :
                   abs(normalizedAmplitude) < 0.7 ? "medium" : "high"
        }
        
        return "Audio intensity: " + amplitudeDescription
            .reduce(into: "") { result, level in
                result += result.isEmpty ? level : ", \(level)"
            }
    }
}

// MARK: - Support Types

private final class DisplayLink {
    private var displayLink: CADisplayLink?
    private var frameCallback: (() -> Void)?
    private let preferredFrameRate: Double
    
    init(preferredFrameRate: Double = WaveformConstants.kMaxRefreshRate) {
        self.preferredFrameRate = min(
            preferredFrameRate,
            WaveformConstants.kMaxRefreshRate
        )
    }
    
    func start(callback: @escaping () -> Void) {
        frameCallback = callback
        
        displayLink = CADisplayLink(
            target: self,
            selector: #selector(handleFrame)
        )
        
        if #available(iOS 15.0, *) {
            displayLink?.preferredFrameRateRange = CAFrameRateRange(
                minimum: preferredFrameRate / 2,
                maximum: preferredFrameRate,
                preferred: preferredFrameRate
            )
        } else {
            displayLink?.preferredFramesPerSecond = Int(preferredFrameRate)
        }
        
        displayLink?.add(to: .main, forMode: .common)
    }
    
    func stop() {
        displayLink?.invalidate()
        displayLink = nil
        frameCallback = nil
    }
    
    @objc private func handleFrame() {
        frameCallback?()
    }
}

private final class BufferRecycler {
    private var buffers: [UnsafeMutablePointer<Float>]
    private var currentIndex: Int = 0
    private let capacity: Int
    
    init(capacity: Int) {
        self.capacity = capacity
        self.buffers = []
        self.buffers.reserveCapacity(2)
        
        // Pre-allocate initial buffers
        for _ in 0..<2 {
            if let buffer = allocateBuffer() {
                buffers.append(buffer)
            }
        }
    }
    
    deinit {
        reset()
    }
    
    func nextBuffer() -> UnsafeMutablePointer<Float> {
        if currentIndex >= buffers.count {
            if let buffer = allocateBuffer() {
                buffers.append(buffer)
            }
            currentIndex = 0
        }
        
        let buffer = buffers[currentIndex]
        currentIndex = (currentIndex + 1) % buffers.count
        return buffer
    }
    
    func reset() {
        buffers.forEach { $0.deallocate() }
        buffers.removeAll()
        currentIndex = 0
    }
    
    private func allocateBuffer() -> UnsafeMutablePointer<Float>? {
        return UnsafeMutablePointer<Float>.allocate(
            capacity: WaveformConstants.kDefaultSampleCount
        )
    }
}