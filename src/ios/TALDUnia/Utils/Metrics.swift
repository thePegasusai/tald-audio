// Foundation v6.0+, os.signpost v2.0+
import Foundation
import os.signpost

/// Thread-safe metrics collection and monitoring system for TALD UNIA
@objc public final class Metrics {
    
    // MARK: - Constants
    
    private let TARGET_LATENCY_MS: Double = 10.0
    private let TARGET_THDN_PERCENT: Double = 0.0005
    private let TARGET_ENHANCEMENT_PERCENT: Double = 20.0
    private let TARGET_POWER_EFFICIENCY: Double = 90.0
    private let METRICS_UPDATE_INTERVAL: TimeInterval = 1.0
    private let HISTORY_CAPACITY: Int = 1000
    private let ALERT_THRESHOLD_VIOLATIONS: Int = 3
    
    // MARK: - Singleton
    
    /// Shared metrics instance
    public static let shared = Metrics()
    
    // MARK: - Properties
    
    private let audioEngine: AudioEngine
    private let logger: Logger
    private var updateTimer: Timer?
    private let metricsQueue: DispatchQueue
    private let signposter: OSSignposter
    
    // Circular buffers for metrics history
    private var latencyHistory: CircularBuffer<Double>
    private var thdnHistory: CircularBuffer<Double>
    private var enhancementHistory: CircularBuffer<Double>
    private var powerEfficiencyHistory: CircularBuffer<Double>
    private var mlPerformanceHistory: CircularBuffer<MLPerformanceMetrics>
    
    // Threshold violation tracking
    private var alertThresholdViolations: AtomicCounter
    
    // MARK: - Initialization
    
    private init() {
        // Initialize core components
        self.audioEngine = AudioEngine()
        self.logger = Logger.shared
        self.signposter = OSSignposter()
        
        // Initialize dedicated metrics queue
        self.metricsQueue = DispatchQueue(
            label: "com.taldunia.metrics",
            qos: .userInitiated,
            attributes: .concurrent
        )
        
        // Initialize circular buffers
        self.latencyHistory = CircularBuffer(capacity: HISTORY_CAPACITY)
        self.thdnHistory = CircularBuffer(capacity: HISTORY_CAPACITY)
        self.enhancementHistory = CircularBuffer(capacity: HISTORY_CAPACITY)
        self.powerEfficiencyHistory = CircularBuffer(capacity: HISTORY_CAPACITY)
        self.mlPerformanceHistory = CircularBuffer(capacity: HISTORY_CAPACITY)
        
        // Initialize threshold violation counter
        self.alertThresholdViolations = AtomicCounter()
    }
    
    // MARK: - Public Interface
    
    /// Starts comprehensive metrics collection
    public func startMonitoring() {
        metricsQueue.async { [weak self] in
            guard let self = self else { return }
            
            let signpostID = self.signposter.makeSignpostID()
            let state = self.signposter.beginInterval("MetricsCollection", id: signpostID)
            
            // Verify audio engine state
            guard self.audioEngine.isRunning else {
                self.logger.log(
                    "Cannot start metrics collection - Audio engine not running",
                    level: .error,
                    subsystem: .audio
                )
                return
            }
            
            // Start periodic collection
            self.updateTimer = Timer.scheduledTimer(
                withTimeInterval: METRICS_UPDATE_INTERVAL,
                repeats: true
            ) { [weak self] _ in
                self?.collectMetrics()
            }
            
            self.logger.log(
                "Metrics collection started",
                level: .info,
                subsystem: .audio,
                metadata: ["interval": METRICS_UPDATE_INTERVAL]
            )
            
            self.signposter.endInterval("MetricsCollection", state)
        }
    }
    
    /// Stops metrics collection
    public func stopMonitoring() {
        metricsQueue.async { [weak self] in
            self?.updateTimer?.invalidate()
            self?.updateTimer = nil
            
            self?.logger.log(
                "Metrics collection stopped",
                level: .info,
                subsystem: .audio
            )
        }
    }
    
    /// Exports collected metrics for analysis
    public func exportMetrics(for period: TimeInterval) -> MetricsExport {
        return metricsQueue.sync {
            let signpostID = signposter.makeSignpostID()
            let state = signposter.beginInterval("MetricsExport", id: signpostID)
            
            defer { signposter.endInterval("MetricsExport", state) }
            
            return MetricsExport(
                latency: latencyHistory.averageValue(),
                thdn: thdnHistory.averageValue(),
                enhancement: enhancementHistory.averageValue(),
                powerEfficiency: powerEfficiencyHistory.averageValue(),
                mlPerformance: mlPerformanceHistory.recentValues(count: 10),
                period: period
            )
        }
    }
    
    // MARK: - Private Methods
    
    private func collectMetrics() {
        let signpostID = signposter.makeSignpostID()
        let state = signposter.beginInterval("MetricsCollection", id: signpostID)
        
        // Collect audio quality metrics
        let currentLatency = audioEngine.currentLatency
        latencyHistory.append(currentLatency)
        
        if currentLatency > TARGET_LATENCY_MS {
            handleThresholdViolation("Latency exceeded target", value: currentLatency)
        }
        
        // Collect power efficiency metrics
        let powerEfficiency = collectPowerEfficiencyMetrics()
        powerEfficiencyHistory.append(powerEfficiency)
        
        if powerEfficiency < TARGET_POWER_EFFICIENCY {
            handleThresholdViolation("Power efficiency below target", value: powerEfficiency)
        }
        
        // Collect ML performance metrics
        let mlMetrics = collectMLPerformanceMetrics()
        mlPerformanceHistory.append(mlMetrics)
        
        if mlMetrics.enhancementImprovement < TARGET_ENHANCEMENT_PERCENT {
            handleThresholdViolation(
                "AI enhancement below target",
                value: mlMetrics.enhancementImprovement
            )
        }
        
        signposter.endInterval("MetricsCollection", state)
    }
    
    private func collectPowerEfficiencyMetrics() -> Double {
        let signpostID = signposter.makeSignpostID()
        let state = signposter.beginInterval("PowerEfficiencyMetrics", id: signpostID)
        
        let efficiency = audioEngine.powerEfficiency
        
        // Log power efficiency data
        logger.log(
            "Power efficiency metrics collected",
            level: .info,
            subsystem: .hardware,
            metadata: ["efficiency": efficiency]
        )
        
        signposter.endInterval("PowerEfficiencyMetrics", state)
        return efficiency
    }
    
    private func collectMLPerformanceMetrics() -> MLPerformanceMetrics {
        let signpostID = signposter.makeSignpostID()
        let state = signposter.beginInterval("MLPerformanceMetrics", id: signpostID)
        
        let performance = audioEngine.mlModelPerformance
        
        // Log ML performance data
        logger.log(
            "ML performance metrics collected",
            level: .info,
            subsystem: .ai,
            metadata: [
                "enhancement": performance.enhancementImprovement,
                "inferenceTime": performance.inferenceTime
            ]
        )
        
        signposter.endInterval("MLPerformanceMetrics", state)
        return performance
    }
    
    private func handleThresholdViolation(_ message: String, value: Double) {
        alertThresholdViolations.increment()
        
        if alertThresholdViolations.value >= ALERT_THRESHOLD_VIOLATIONS {
            logger.log(
                message,
                level: .warning,
                subsystem: .audio,
                metadata: [
                    "value": value,
                    "violations": alertThresholdViolations.value
                ]
            )
            alertThresholdViolations.reset()
        }
    }
}

// MARK: - Supporting Types

/// Represents ML model performance metrics
private struct MLPerformanceMetrics {
    let enhancementImprovement: Double
    let inferenceTime: TimeInterval
    let memoryUsage: UInt64
}

/// Thread-safe metrics export container
public struct MetricsExport {
    public let latency: Double
    public let thdn: Double
    public let enhancement: Double
    public let powerEfficiency: Double
    public let mlPerformance: [MLPerformanceMetrics]
    public let period: TimeInterval
}

/// Thread-safe circular buffer for metrics history
private class CircularBuffer<T> {
    private var buffer: [T]
    private let capacity: Int
    private let queue = DispatchQueue(label: "com.taldunia.circularbuffer")
    
    init(capacity: Int) {
        self.capacity = capacity
        self.buffer = []
        buffer.reserveCapacity(capacity)
    }
    
    func append(_ element: T) {
        queue.sync {
            if buffer.count >= capacity {
                buffer.removeFirst()
            }
            buffer.append(element)
        }
    }
    
    func averageValue() -> Double where T == Double {
        queue.sync {
            guard !buffer.isEmpty else { return 0.0 }
            return buffer.reduce(0.0, +) / Double(buffer.count)
        }
    }
    
    func recentValues(count: Int) -> [T] {
        queue.sync {
            let start = max(0, buffer.count - count)
            return Array(buffer[start...])
        }
    }
}

/// Thread-safe atomic counter
private class AtomicCounter {
    private var _value: Int = 0
    private let queue = DispatchQueue(label: "com.taldunia.atomiccounter")
    
    var value: Int {
        queue.sync { _value }
    }
    
    func increment() {
        queue.sync { _value += 1 }
    }
    
    func reset() {
        queue.sync { _value = 0 }
    }
}