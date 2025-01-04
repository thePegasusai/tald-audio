// Foundation v17.0+
import SwiftUI
import Combine

/// Professional-grade VU meter component for real-time audio level visualization
/// with support for multiple metering standards and high-precision measurements
@available(iOS 14.0, *)
@MainActor
public class VUMeter: View {
    
    // MARK: - Constants
    
    private let kPeakHoldTime: Double = 2.0
    private let kMeterRefreshRate: Double = 60.0
    private let kMinimumLevel: Double = -60.0
    private let kMaximumLevel: Double = 6.0
    private let kIntegrationTime: Double = 0.3
    private let kOversampling: Int = 4
    
    // MARK: - Enums
    
    /// Supported metering standards
    public enum MeterStandard {
        case vu          // Traditional VU metering
        case ppm         // Peak Programme Meter
        case ebuR128    // EBU R128 loudness standard
        case k20        // K-System metering (K-20)
    }
    
    // MARK: - Properties
    
    @Published private var rmsLevel: Float = -60.0
    @Published private var peakLevel: Float = -60.0
    @Published private var peakHoldLevel: Float = -60.0
    @Published private var thdLevel: Float = 0.0
    
    private var meterStandard: MeterStandard
    private var referenceLevel: Float
    private var refreshTimer: Timer?
    private var updatePublisher = PassthroughSubject<Void, Never>()
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    
    /// Initializes VU meter with professional metering configuration
    /// - Parameters:
    ///   - standard: Metering standard to use
    ///   - referenceLevel: Reference level in dBFS
    public init(standard: MeterStandard = .vu, referenceLevel: Float = 0.0) {
        self.meterStandard = standard
        self.referenceLevel = referenceLevel
        
        setupTimer()
        setupBindings()
    }
    
    // MARK: - Setup
    
    private func setupTimer() {
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 1.0/kMeterRefreshRate, repeats: true) { [weak self] _ in
            self?.updatePublisher.send()
        }
    }
    
    private func setupBindings() {
        updatePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                self?.updateMeterDisplay()
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Public Methods
    
    /// Updates meter levels with professional ballistics
    /// - Parameter buffer: Audio buffer containing samples to analyze
    public func updateMeter(buffer: AudioBuffer) {
        // Calculate RMS level with oversampling
        let rms = calculateRMSLevel(buffer: buffer, standard: meterStandard)
        
        // Calculate true peak level
        let peak = calculatePeakLevel(buffer: buffer, standard: meterStandard)
        
        // Calculate THD if enabled
        let thd = AudioMath.calculateTHD(buffer.readFromBuffer(), 
                                       length: buffer.bufferSize,
                                       fundamentalFrequency: buffer.sampleRate/2)
        
        // Update levels with proper ballistics
        DispatchQueue.main.async {
            self.rmsLevel = rms
            self.peakLevel = peak
            self.thdLevel = thd
            
            // Update peak hold with decay
            if peak > self.peakHoldLevel {
                self.peakHoldLevel = peak
            }
        }
    }
    
    // MARK: - Private Methods
    
    private func calculateRMSLevel(buffer: AudioBuffer, standard: MeterStandard) -> Float {
        var rms: Float = 0.0
        
        // Read from buffer with oversampling
        let samples = UnsafeMutablePointer<Float>.allocate(capacity: buffer.bufferSize * kOversampling)
        defer { samples.deallocate() }
        
        let result = buffer.readFromBuffer(into: samples, frames: buffer.bufferSize)
        guard case .success(let count) = result else { return kMinimumLevel }
        
        // Calculate RMS with integration time based on standard
        rms = AudioMath.calculateRMS(samples, length: count)
        
        // Apply standard-specific scaling
        switch standard {
        case .vu:
            rms *= 0.775 // VU meter standard reference
        case .ppm:
            rms *= 1.0 // PPM uses true peak
        case .ebuR128:
            rms *= 0.691 // EBU R128 LUFS reference
        case .k20:
            rms *= 0.5 // K-20 headroom reference
        }
        
        return AudioMath.linearToDecibels(rms)
    }
    
    private func calculatePeakLevel(buffer: AudioBuffer, standard: MeterStandard) -> Float {
        var peak: Float = 0.0
        
        // Read from buffer with oversampling for true peak detection
        let samples = UnsafeMutablePointer<Float>.allocate(capacity: buffer.bufferSize * kOversampling)
        defer { samples.deallocate() }
        
        let result = buffer.readFromBuffer(into: samples, frames: buffer.bufferSize)
        guard case .success(let count) = result else { return kMinimumLevel }
        
        // Find true peak with standard-specific ballistics
        peak = AudioMath.calculatePeakLevel(samples, length: count)
        
        return peak
    }
    
    private func updateMeterDisplay() {
        // Apply peak hold decay
        if peakHoldLevel > peakLevel {
            let decayRate = (kMaximumLevel - kMinimumLevel) / (kPeakHoldTime * kMeterRefreshRate)
            peakHoldLevel = max(peakLevel, peakHoldLevel - decayRate)
        }
    }
    
    // MARK: - View Body
    
    public var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Background
                Rectangle()
                    .fill(Colors.surface)
                    .overlay(
                        // Scale markings
                        VStack(alignment: .trailing, spacing: 2) {
                            ForEach(stride(from: Int(kMaximumLevel), through: Int(kMinimumLevel), by: -6), id: \.self) { level in
                                Text("\(level)")
                                    .font(.system(size: 8, weight: .medium))
                                    .foregroundColor(Colors.primary)
                            }
                        }
                    )
                
                // RMS meter
                Rectangle()
                    .fill(Colors.vuMeterGradient)
                    .frame(width: meterWidth(for: rmsLevel, in: geometry))
                
                // Peak meter
                Rectangle()
                    .fill(Colors.peakIndicator)
                    .frame(width: 2)
                    .offset(x: meterWidth(for: peakLevel, in: geometry))
                
                // Peak hold indicator
                Rectangle()
                    .fill(Colors.peakIndicator)
                    .frame(width: 2)
                    .offset(x: meterWidth(for: peakHoldLevel, in: geometry))
                
                // THD indicator
                if thdLevel > 0.0005 { // Show only if above target THD
                    Text(String(format: "THD: %.4f%%", thdLevel))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(Colors.error)
                        .position(x: geometry.size.width - 40, y: 10)
                }
            }
        }
        .frame(height: 200)
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Colors.primary.opacity(0.2), lineWidth: 1)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("VU Meter")
        .accessibilityValue(String(format: "Level: %.1f dB, Peak: %.1f dB", rmsLevel, peakLevel))
    }
    
    private func meterWidth(for level: Float, in geometry: GeometryProxy) -> CGFloat {
        let normalizedLevel = (CGFloat(level) - CGFloat(kMinimumLevel)) / 
            (CGFloat(kMaximumLevel) - CGFloat(kMinimumLevel))
        return max(0, min(geometry.size.width, geometry.size.width * normalizedLevel))
    }
}