//
// VUMeter.swift
// TALD UNIA
//
// High-precision VU meter component for professional audio level visualization
// Version: 1.0.0
//

import SwiftUI // macOS 13.0+
import Combine // macOS 13.0+

// MARK: - Constants

private let VU_METER_UPDATE_INTERVAL: TimeInterval = 1.0 / 60.0 // 60Hz refresh rate
private let VU_METER_DECAY_RATE: Float = 0.9
private let VU_METER_PEAK_HOLD_TIME: TimeInterval = 2.0
private let VU_METER_OVERLOAD_THRESHOLD: Float = 0.0 // 0 dBFS
private let VU_METER_REFERENCE_LEVEL: Float = -18.0 // Professional reference level
private let VU_METER_THDN_THRESHOLD: Float = 0.0005 // THD+N requirement

// MARK: - VU Meter Reading Structure

public struct VUMeterReading: Equatable {
    let level: Float
    let thdn: Float
    let isOverloaded: Bool
    let timestamp: Date
    
    public static func == (lhs: VUMeterReading, rhs: VUMeterReading) -> Bool {
        return lhs.level == rhs.level &&
               lhs.thdn == rhs.thdn &&
               lhs.isOverloaded == rhs.isOverloaded
    }
}

// MARK: - VU Meter Implementation

@available(macOS 13.0, *)
@MainActor
public class VUMeter: View {
    // MARK: - Properties
    
    private let levelPublisher = PassthroughSubject<VUMeterReading, Never>()
    private var currentLevel: Float = VU_METER_REFERENCE_LEVEL
    private var peakLevel: Float = VU_METER_REFERENCE_LEVEL
    private var thdnLevel: Float = 0.0
    private var updateTimer: Timer?
    private var isOverloaded: Bool = false
    private var isBufferUnderrun: Bool = false
    private var currentLatency: TimeInterval = 0.0
    private var cancellables = Set<AnyCancellable>()
    
    private let audioEngine: AudioEngine
    private let audioMetrics: AudioMetrics
    private let colors: Colors
    
    // MARK: - Initialization
    
    public init(referenceLevel: Float = VU_METER_REFERENCE_LEVEL, enableTHDNMonitoring: Bool = true) {
        self.audioEngine = AudioEngine()
        self.audioMetrics = AudioMetrics.shared
        self.colors = Colors()
        
        setupMonitoring(referenceLevel: referenceLevel, enableTHDN: enableTHDNMonitoring)
    }
    
    // MARK: - Monitoring Control
    
    public func startMonitoring() {
        // Configure high-precision update timer
        updateTimer = Timer.scheduledTimer(withTimeInterval: VU_METER_UPDATE_INTERVAL, repeats: true) { [weak self] _ in
            self?.updateMeterLevels()
        }
        
        // Start audio level subscription
        audioEngine.processAudioBuffer { [weak self] buffer in
            guard let self = self else { return }
            
            let reading = self.calculateDBFS(samples: buffer.floatChannelData?[0] ?? [], referenceLevel: VU_METER_REFERENCE_LEVEL)
            self.levelPublisher.send(reading)
        }
        
        // Initialize performance tracking
        audioMetrics.measureLatency { [weak self] latency in
            self?.currentLatency = latency
        }
    }
    
    public func stopMonitoring() {
        updateTimer?.invalidate()
        updateTimer = nil
        cancellables.removeAll()
        
        currentLevel = VU_METER_REFERENCE_LEVEL
        peakLevel = VU_METER_REFERENCE_LEVEL
        thdnLevel = 0.0
        isOverloaded = false
        isBufferUnderrun = false
    }
    
    // MARK: - Level Calculation
    
    @inlinable
    private func calculateDBFS(samples: [Float], referenceLevel: Float) -> VUMeterReading {
        // Calculate RMS value using SIMD operations
        var rms: Float = 0.0
        vDSP_measqv(samples, 1, &rms, vDSP_Length(samples.count))
        
        // Convert to decibels
        var db: Float = 0.0
        vDSP_vdbcon(&rms, 1, &db, 1, 1, 0)
        
        // Apply reference level offset
        db += referenceLevel
        
        // Measure THD+N
        let thdn = audioEngine.getTHDNMeasurement()
        
        // Check for overload
        let isOverloaded = db > VU_METER_OVERLOAD_THRESHOLD
        
        return VUMeterReading(
            level: db,
            thdn: thdn,
            isOverloaded: isOverloaded,
            timestamp: Date()
        )
    }
    
    // MARK: - View Body
    
    public var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Background
                Rectangle()
                    .fill(colors.background)
                    .cornerRadius(4)
                
                // Level indicator
                Rectangle()
                    .fill(levelColor)
                    .frame(width: levelWidth(for: currentLevel, in: geometry))
                    .animation(.linear(duration: VU_METER_UPDATE_INTERVAL), value: currentLevel)
                
                // Peak indicator
                Rectangle()
                    .fill(peakColor)
                    .frame(width: 2)
                    .offset(x: levelWidth(for: peakLevel, in: geometry))
                
                // Scale markings
                ForEach(scaleMarkings, id: \.0) { level, label in
                    VStack {
                        Text(label)
                            .font(.system(size: 10))
                            .foregroundColor(colors.onBackground)
                        Rectangle()
                            .fill(colors.onBackground)
                            .frame(width: 1, height: 6)
                    }
                    .offset(x: levelWidth(for: level, in: geometry))
                }
                
                // THD+N indicator
                if thdnLevel > VU_METER_THDN_THRESHOLD {
                    Text("THD+N: \(String(format: "%.4f%%", thdnLevel * 100))")
                        .font(.system(size: 10))
                        .foregroundColor(colors.error)
                        .padding(.leading, 4)
                }
                
                // Overload warning
                if isOverloaded {
                    Text("OVERLOAD")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(colors.error)
                        .padding(.trailing, 4)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .accessibility(label: Text("Audio level overload warning"))
                }
                
                // Buffer status
                if isBufferUnderrun {
                    Text("BUFFER UNDERRUN")
                        .font(.system(size: 10))
                        .foregroundColor(colors.warning)
                        .padding(.trailing, 4)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
            .frame(height: 24)
            .onAppear {
                startMonitoring()
            }
            .onDisappear {
                stopMonitoring()
            }
        }
    }
    
    // MARK: - Helper Methods
    
    private var levelColor: Color {
        if isOverloaded {
            return colors.error
        } else if currentLevel > -6 {
            return colors.warning
        }
        return colors.primary
    }
    
    private var peakColor: Color {
        if peakLevel > VU_METER_OVERLOAD_THRESHOLD {
            return colors.error
        }
        return colors.accent
    }
    
    private func levelWidth(for level: Float, in geometry: GeometryProxy) -> CGFloat {
        let normalizedLevel = (level - VU_METER_REFERENCE_LEVEL) / abs(VU_METER_REFERENCE_LEVEL)
        return geometry.size.width * CGFloat(max(0, min(1, normalizedLevel)))
    }
    
    private var scaleMarkings: [(Float, String)] {
        [
            (-60, "-60"),
            (-40, "-40"),
            (-20, "-20"),
            (-12, "-12"),
            (-6, "-6"),
            (-3, "-3"),
            (0, "0")
        ]
    }
    
    private func updateMeterLevels() {
        levelPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] reading in
                guard let self = self else { return }
                
                // Update current level with decay
                self.currentLevel = max(
                    reading.level,
                    self.currentLevel * VU_METER_DECAY_RATE
                )
                
                // Update peak level
                if reading.level > self.peakLevel {
                    self.peakLevel = reading.level
                    
                    // Reset peak after hold time
                    DispatchQueue.main.asyncAfter(deadline: .now() + VU_METER_PEAK_HOLD_TIME) {
                        self.peakLevel = self.currentLevel
                    }
                }
                
                self.thdnLevel = reading.thdn
                self.isOverloaded = reading.isOverloaded
            }
            .store(in: &cancellables)
    }
}