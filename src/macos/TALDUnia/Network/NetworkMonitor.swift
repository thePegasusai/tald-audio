//
// NetworkMonitor.swift
// TALD UNIA
//
// Network monitoring system for audio streaming and cloud processing
// Foundation version: macOS 13.0+
//

import Foundation // macOS 13.0+
import Network // macOS 13.0+

// MARK: - Constants
private let NETWORK_MONITOR_QUEUE = DispatchQueue(label: "com.tald.unia.networkmonitor", qos: .userInitiated)
private let DEFAULT_PATH_MONITORING_INTERVAL: TimeInterval = 1.0
private let AUDIO_LATENCY_THRESHOLD: TimeInterval = 0.010 // 10ms max latency
private let MIN_BANDWIDTH_REQUIREMENT: Double = 1_500_000 // 1.5 Mbps minimum
private let MAX_JITTER_TOLERANCE: TimeInterval = 0.002 // 2ms max jitter

// MARK: - Network Quality Status
public enum NetworkQualityStatus: String {
    case excellent
    case good
    case fair
    case poor
    
    var latencyThreshold: TimeInterval {
        switch self {
        case .excellent: return 0.005
        case .good: return 0.008
        case .fair: return 0.010
        case .poor: return 0.015
        }
    }
    
    var bandwidthThreshold: Double {
        switch self {
        case .excellent: return 3_000_000
        case .good: return 2_000_000
        case .fair: return 1_500_000
        case .poor: return 1_000_000
        }
    }
    
    var jitterThreshold: TimeInterval {
        switch self {
        case .excellent: return 0.001
        case .good: return 0.002
        case .fair: return 0.003
        case .poor: return 0.005
        }
    }
}

// MARK: - Audio Streaming Metrics
public struct AudioStreamingMetrics {
    var latency: TimeInterval
    var jitter: TimeInterval
    var bandwidth: Double
    var packetLoss: Double
    var quality: NetworkQualityStatus
    
    var isAcceptableForStreaming: Bool {
        return latency <= AUDIO_LATENCY_THRESHOLD &&
               bandwidth >= MIN_BANDWIDTH_REQUIREMENT &&
               jitter <= MAX_JITTER_TOLERANCE &&
               packetLoss < 0.01
    }
}

// MARK: - Network Quality Delegate
public protocol NetworkQualityDelegate: AnyObject {
    func networkQualityDidChange(_ quality: NetworkQualityStatus)
    func audioStreamingMetricsDidUpdate(_ metrics: AudioStreamingMetrics)
}

// MARK: - Network Monitor
@objc public final class NetworkMonitor {
    // MARK: - Singleton
    public static let shared = NetworkMonitor()
    
    // MARK: - Properties
    private let pathMonitor: NWPathMonitor
    private var currentQuality: NetworkQualityStatus = .good
    private var isConnected: Bool = false
    private var currentInterface: NWInterface?
    private var streamingMetrics: AudioStreamingMetrics?
    private weak var qualityDelegate: NetworkQualityDelegate?
    
    private var currentBandwidth: Double = 0
    private var currentLatency: TimeInterval = 0
    private var currentJitter: TimeInterval = 0
    
    // MARK: - Initialization
    private init() {
        self.pathMonitor = NWPathMonitor()
        self.pathMonitor.pathUpdateHandler = { [weak self] path in
            self?.handleNetworkPathUpdate(path)
        }
    }
    
    // MARK: - Public Methods
    public func startMonitoring() {
        Logger.shared.log("Starting network monitoring", context: "NetworkMonitor")
        pathMonitor.start(queue: NETWORK_MONITOR_QUEUE)
        startMetricsCollection()
    }
    
    public func stopMonitoring() {
        Logger.shared.log("Stopping network monitoring", context: "NetworkMonitor")
        pathMonitor.cancel()
        stopMetricsCollection()
    }
    
    public func setQualityDelegate(_ delegate: NetworkQualityDelegate) {
        self.qualityDelegate = delegate
    }
    
    // MARK: - Private Methods
    private func handleNetworkPathUpdate(_ path: NWPath) {
        isConnected = path.status == .satisfied
        currentInterface = path.availableInterfaces.first
        
        let previousQuality = currentQuality
        currentQuality = checkNetworkQuality()
        
        if previousQuality != currentQuality {
            NETWORK_MONITOR_QUEUE.async { [weak self] in
                guard let self = self else { return }
                self.qualityDelegate?.networkQualityDidChange(self.currentQuality)
                
                Logger.shared.log(
                    "Network quality changed to \(self.currentQuality)",
                    context: "NetworkMonitor",
                    metadata: [
                        "previousQuality": previousQuality.rawValue,
                        "newQuality": self.currentQuality.rawValue
                    ]
                )
            }
        }
        
        updateAudioStreamingMetrics()
    }
    
    private func checkNetworkQuality() -> NetworkQualityStatus {
        guard isConnected else { return .poor }
        
        let metrics = measureAudioStreamingMetrics()
        
        if metrics.latency <= NetworkQualityStatus.excellent.latencyThreshold &&
           metrics.bandwidth >= NetworkQualityStatus.excellent.bandwidthThreshold &&
           metrics.jitter <= NetworkQualityStatus.excellent.jitterThreshold {
            return .excellent
        } else if metrics.latency <= NetworkQualityStatus.good.latencyThreshold &&
                  metrics.bandwidth >= NetworkQualityStatus.good.bandwidthThreshold &&
                  metrics.jitter <= NetworkQualityStatus.good.jitterThreshold {
            return .good
        } else if metrics.latency <= NetworkQualityStatus.fair.latencyThreshold &&
                  metrics.bandwidth >= NetworkQualityStatus.fair.bandwidthThreshold &&
                  metrics.jitter <= NetworkQualityStatus.fair.jitterThreshold {
            return .fair
        } else {
            return .poor
        }
    }
    
    private func measureAudioStreamingMetrics() -> AudioStreamingMetrics {
        // Measure current network metrics
        let metrics = AudioStreamingMetrics(
            latency: currentLatency,
            jitter: currentJitter,
            bandwidth: currentBandwidth,
            packetLoss: calculatePacketLoss(),
            quality: currentQuality
        )
        
        if !metrics.isAcceptableForStreaming {
            Logger.shared.error(
                TALDError.networkError(
                    code: "STREAMING_METRICS_DEGRADED",
                    message: "Audio streaming metrics below acceptable threshold",
                    metadata: ErrorMetadata(
                        timestamp: Date(),
                        component: "NetworkMonitor",
                        additionalInfo: [
                            "latency": String(metrics.latency),
                            "bandwidth": String(metrics.bandwidth),
                            "jitter": String(metrics.jitter)
                        ]
                    )
                ),
                context: "NetworkMonitor"
            )
        }
        
        return metrics
    }
    
    private func calculatePacketLoss() -> Double {
        // Implement packet loss calculation
        // This is a placeholder implementation
        return 0.001
    }
    
    private func startMetricsCollection() {
        // Start collecting network metrics
        Timer.scheduledTimer(withTimeInterval: DEFAULT_PATH_MONITORING_INTERVAL, repeats: true) { [weak self] _ in
            self?.updateAudioStreamingMetrics()
        }
    }
    
    private func stopMetricsCollection() {
        // Stop metrics collection and clean up
        streamingMetrics = nil
    }
    
    private func updateAudioStreamingMetrics() {
        let metrics = measureAudioStreamingMetrics()
        streamingMetrics = metrics
        
        NETWORK_MONITOR_QUEUE.async { [weak self] in
            self?.qualityDelegate?.audioStreamingMetricsDidUpdate(metrics)
        }
    }
}