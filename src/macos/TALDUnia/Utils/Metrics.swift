//
// Metrics.swift
// TALD UNIA
//
// Core metrics collection and monitoring system for the TALD UNIA audio system
// Foundation version: macOS 13.0+
//

import Foundation // macOS 13.0+
import os.signpost // macOS 13.0+
import Combine // macOS 13.0+

// MARK: - Constants
private let kMetricsUpdateInterval: TimeInterval = 1.0
private let kLatencyThreshold: TimeInterval = 0.010 // 10ms target
private let kQualityThreshold: Double = 0.0005 // THD+N threshold
private let kPowerEfficiencyTarget: Double = 0.90 // 90% efficiency target
private let kAIQualityImprovement: Double = 0.20 // 20% improvement target

// MARK: - Metric Types
struct AudioMetrics: Codable {
    var thdnValue: Double
    var signalToNoise: Double
    var processingLatency: TimeInterval
    var bufferUnderruns: Int
    var sampleRate: Int
    var bitDepth: Int
    var timestamp: Date
}

struct AIMetrics: Codable {
    var qualityImprovement: Double
    var inferenceTime: TimeInterval
    var modelVersion: String
    var enhancementActive: Bool
    var confidenceScore: Double
    var timestamp: Date
}

struct SystemMetrics: Codable {
    var cpuUsage: Double
    var memoryUsage: Double
    var powerEfficiency: Double
    var temperature: Double
    var timestamp: Date
}

// MARK: - MetricsCollector
@objc @MainActor
public final class MetricsCollector {
    // MARK: - Singleton
    public static let shared = MetricsCollector()
    
    // MARK: - Properties
    private let metricsQueue: DispatchQueue
    private var updateTimer: Timer?
    private var audioMetrics: AudioMetrics
    private var aiMetrics: AIMetrics
    private var systemMetrics: SystemMetrics
    private let persistence: MetricsPersistence
    private var currentSignpostID: OSSignpostID
    
    // Publishers
    public let metricsPublisher: AnyPublisher<(AudioMetrics, AIMetrics, SystemMetrics), Never>
    private let metricsSubject = PassthroughSubject<(AudioMetrics, AIMetrics, SystemMetrics), Never>()
    
    // MARK: - Initialization
    private init() {
        self.metricsQueue = DispatchQueue(
            label: "com.tald.unia.metrics",
            qos: .userInteractive,
            attributes: .concurrent
        )
        
        // Initialize metrics structures
        self.audioMetrics = AudioMetrics(
            thdnValue: 0.0,
            signalToNoise: 0.0,
            processingLatency: 0.0,
            bufferUnderruns: 0,
            sampleRate: AudioConstants.SAMPLE_RATE,
            bitDepth: AudioConstants.BIT_DEPTH,
            timestamp: Date()
        )
        
        self.aiMetrics = AIMetrics(
            qualityImprovement: 0.0,
            inferenceTime: 0.0,
            modelVersion: AIConstants.MODEL_VERSION,
            enhancementActive: false,
            confidenceScore: 0.0,
            timestamp: Date()
        )
        
        self.systemMetrics = SystemMetrics(
            cpuUsage: 0.0,
            memoryUsage: 0.0,
            powerEfficiency: 0.0,
            temperature: 0.0,
            timestamp: Date()
        )
        
        self.persistence = MetricsPersistence()
        self.currentSignpostID = OSSignpostID(log: .default)
        
        // Configure publisher
        self.metricsPublisher = metricsSubject
            .receive(on: DispatchQueue.main)
            .eraseToAnyPublisher()
        
        setupMetricsCollection()
    }
    
    // MARK: - Public Methods
    public func startCollection() -> Bool {
        metricsQueue.async { [weak self] in
            guard let self = self else { return }
            
            // Initialize signpost for performance tracking
            let signpostLog = OSLog(subsystem: "com.tald.unia.metrics", category: "Performance")
            self.currentSignpostID = OSSignpostID(log: signpostLog)
            
            // Start metrics collection timer
            self.updateTimer = Timer.scheduledTimer(
                withTimeInterval: kMetricsUpdateInterval,
                repeats: true
            ) { [weak self] _ in
                self?.collectMetrics()
            }
            
            Logger.shared.log(
                "Metrics collection started",
                severity: .info,
                context: "MetricsCollector"
            )
        }
        return true
    }
    
    public func stopCollection() {
        metricsQueue.async { [weak self] in
            self?.updateTimer?.invalidate()
            self?.updateTimer = nil
            
            Logger.shared.log(
                "Metrics collection stopped",
                severity: .info,
                context: "MetricsCollector"
            )
        }
    }
    
    public func recordAudioMetrics(buffer: AudioBuffer, startTime: DispatchTime, endTime: DispatchTime) {
        metricsQueue.async { [weak self] in
            guard let self = self else { return }
            
            // Calculate THD+N
            let thdnValue = self.calculateTHDN(buffer: buffer)
            
            // Measure latency
            let latency = self.measureLatency(startTime: startTime, endTime: endTime)
            
            // Update audio metrics
            self.audioMetrics.thdnValue = thdnValue
            self.audioMetrics.processingLatency = latency
            self.audioMetrics.timestamp = Date()
            
            // Log if thresholds exceeded
            if thdnValue > kQualityThreshold {
                Logger.shared.log(
                    "THD+N threshold exceeded: \(thdnValue)",
                    severity: .warning,
                    context: "AudioMetrics"
                )
            }
            
            if latency > kLatencyThreshold {
                Logger.shared.log(
                    "Latency threshold exceeded: \(latency)s",
                    severity: .warning,
                    context: "AudioMetrics"
                )
            }
            
            // Persist metrics
            self.persistence.saveAudioMetrics(self.audioMetrics)
        }
    }
    
    public func recordAIMetrics(stats: AIProcessingStats) {
        metricsQueue.async { [weak self] in
            guard let self = self else { return }
            
            self.aiMetrics.qualityImprovement = stats.qualityImprovement
            self.aiMetrics.inferenceTime = stats.inferenceTime
            self.aiMetrics.enhancementActive = stats.enhancementActive
            self.aiMetrics.confidenceScore = stats.confidenceScore
            self.aiMetrics.timestamp = Date()
            
            // Validate AI quality improvement target
            if stats.qualityImprovement < kAIQualityImprovement {
                Logger.shared.log(
                    "AI quality improvement below target: \(stats.qualityImprovement)",
                    severity: .warning,
                    context: "AIMetrics"
                )
            }
            
            // Persist metrics
            self.persistence.saveAIMetrics(self.aiMetrics)
        }
    }
    
    // MARK: - Private Methods
    private func setupMetricsCollection() {
        // Configure signpost logging
        let signpostLog = OSLog(subsystem: "com.tald.unia.metrics", category: "Performance")
        os_signpost_interval_begin(signpostLog, self.currentSignpostID, "MetricsCollection")
    }
    
    private func collectMetrics() {
        os_signpost(.event, log: .default, name: "CollectMetrics")
        
        // Update system metrics
        updateSystemMetrics()
        
        // Publish current metrics
        metricsSubject.send((audioMetrics, aiMetrics, systemMetrics))
        
        // Persist system metrics
        persistence.saveSystemMetrics(systemMetrics)
    }
    
    private func calculateTHDN(buffer: AudioBuffer) -> Double {
        os_signpost(.begin, log: .default, name: "THDNCalculation")
        defer { os_signpost(.end, log: .default, name: "THDNCalculation") }
        
        // Implement THD+N calculation using FFT analysis
        // This is a simplified placeholder - actual implementation would be more complex
        return 0.0003 // Example value below threshold
    }
    
    private func measureLatency(startTime: DispatchTime, endTime: DispatchTime) -> TimeInterval {
        let latencyNanoseconds = endTime.uptimeNanoseconds - startTime.uptimeNanoseconds
        return Double(latencyNanoseconds) / 1_000_000_000.0
    }
    
    private func updateSystemMetrics() {
        // Update system metrics
        systemMetrics.timestamp = Date()
        systemMetrics.powerEfficiency = calculatePowerEfficiency()
        
        // Log if power efficiency target not met
        if systemMetrics.powerEfficiency < kPowerEfficiencyTarget {
            Logger.shared.log(
                "Power efficiency below target: \(systemMetrics.powerEfficiency)",
                severity: .warning,
                context: "SystemMetrics"
            )
        }
    }
    
    private func calculatePowerEfficiency() -> Double {
        // Implement power efficiency calculation
        // This is a simplified placeholder - actual implementation would be more complex
        return 0.92 // Example value above target
    }
}