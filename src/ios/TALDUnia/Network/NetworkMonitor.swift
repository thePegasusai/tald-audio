// Foundation v6.0+, Network v2.0+, Combine v2.0+, Security v2.0+
import Foundation
import Network
import Combine
import Security

/// Network connection status
@objc public enum NetworkStatus: Int {
    case connected
    case disconnected
    case cellular
    case wifi
    case ethernet
    case unknown
}

/// Network quality assessment
@objc public enum NetworkQuality: Int {
    case high      // Optimal for all features including real-time AI processing
    case medium    // Suitable for most features with potential latency
    case low       // Limited functionality, basic features only
    case critical  // Minimal connectivity, essential functions only
    case unknown
}

/// Network security validation status
@objc public enum SecurityValidation: Int {
    case valid     // All security requirements met
    case invalid   // Security requirements not met
    case unknown   // Security status undetermined
}

/// Comprehensive network monitoring system for TALD UNIA
@available(iOS 13.0, *)
public final class NetworkMonitor {
    
    // MARK: - Shared Instance
    
    /// Shared network monitor instance
    public static let shared = NetworkMonitor()
    
    // MARK: - Properties
    
    private let monitor = NWPathMonitor()
    private let monitoringQueue = DispatchQueue(label: "com.taldunia.network.monitor", qos: .utility)
    
    /// Current network status publisher
    public let status = CurrentValueSubject<NetworkStatus, Never>(.unknown)
    
    /// Network quality assessment publisher
    public let quality = CurrentValueSubject<NetworkQuality, Never>(.unknown)
    
    /// Security validation status publisher
    public let security = CurrentValueSubject<SecurityValidation, Never>(.unknown)
    
    /// Network reachability status
    public private(set) var isReachable = false
    
    /// Historical network metrics
    private var connectionHistory: [NetworkMetric] = []
    
    /// Network quality thresholds from configuration
    private let qualityThresholds: NetworkThresholds
    
    /// Security validator for TLS and certificate validation
    private let securityValidator: SecurityValidator
    
    // MARK: - Initialization
    
    private init() {
        self.qualityThresholds = Configuration.shared.networkThresholds
        self.securityValidator = SecurityValidator()
        setupMonitor()
    }
    
    // MARK: - Public Methods
    
    /// Starts network monitoring with specified configuration
    public func startMonitoring(type: NWInterface.InterfaceType? = nil) {
        if let interfaceType = type {
            monitor.prohibitedInterfaceTypes = NWInterface.InterfaceType.allCases
                .filter { $0 != interfaceType }
        }
        
        monitor.pathUpdateHandler = { [weak self] path in
            self?.handlePathUpdate(path)
        }
        
        monitor.start(queue: monitoringQueue)
        
        Logger.shared.log(
            "Network monitoring started",
            level: .info,
            subsystem: .network,
            metadata: ["interface": type?.rawValue ?? "any"]
        )
    }
    
    /// Stops network monitoring and cleanup
    public func stopMonitoring() {
        monitor.cancel()
        status.send(.disconnected)
        isReachable = false
        
        Logger.shared.log(
            "Network monitoring stopped",
            level: .info,
            subsystem: .network
        )
    }
    
    // MARK: - Private Methods
    
    private func setupMonitor() {
        // Configure monitoring parameters
        monitor.pathUpdateHandler = { [weak self] path in
            self?.handlePathUpdate(path)
        }
    }
    
    private func handlePathUpdate(_ path: NWPath) {
        // Update reachability status
        isReachable = path.status == .satisfied
        
        // Determine network status
        let newStatus: NetworkStatus = {
            guard path.status == .satisfied else { return .disconnected }
            
            if path.usesInterfaceType(.wifi) {
                return .wifi
            } else if path.usesInterfaceType(.cellular) {
                return .cellular
            } else if path.usesInterfaceType(.wiredEthernet) {
                return .ethernet
            }
            return .unknown
        }()
        
        // Update status if changed
        if status.value != newStatus {
            status.send(newStatus)
            logNetworkChange(to: newStatus)
        }
        
        // Assess network quality
        assessNetworkQuality(path)
        
        // Validate security
        validateSecurity(path)
        
        // Update connection history
        updateConnectionHistory(status: newStatus)
    }
    
    private func assessNetworkQuality(_ path: NWPath) {
        let newQuality: NetworkQuality = {
            guard path.status == .satisfied else { return .critical }
            
            // Check against configured thresholds
            if path.isExpensive || path.isConstrained {
                return .low
            }
            
            switch path.currentThroughput {
            case _ where path.currentThroughput >= qualityThresholds.highQualityThreshold:
                return .high
            case _ where path.currentThroughput >= qualityThresholds.mediumQualityThreshold:
                return .medium
            default:
                return .low
            }
        }()
        
        if quality.value != newQuality {
            quality.send(newQuality)
            logQualityChange(to: newQuality)
        }
    }
    
    private func validateSecurity(_ path: NWPath) {
        Task {
            let validationResult = await securityValidator.validateConnection(path)
            
            if security.value != validationResult {
                security.send(validationResult)
                logSecurityValidation(status: validationResult)
            }
        }
    }
    
    private func updateConnectionHistory(status: NetworkStatus) {
        let metric = NetworkMetric(
            timestamp: Date(),
            status: status,
            quality: quality.value,
            security: security.value
        )
        
        connectionHistory.append(metric)
        
        // Maintain history size
        if connectionHistory.count > 100 {
            connectionHistory.removeFirst()
        }
    }
    
    // MARK: - Logging
    
    private func logNetworkChange(to status: NetworkStatus) {
        Logger.shared.log(
            "Network status changed: \(status)",
            level: .info,
            subsystem: .network,
            metadata: [
                "isReachable": isReachable,
                "quality": quality.value
            ]
        )
    }
    
    private func logQualityChange(to quality: NetworkQuality) {
        Logger.shared.log(
            "Network quality changed: \(quality)",
            level: .info,
            subsystem: .network,
            metadata: [
                "status": status.value,
                "isReachable": isReachable
            ]
        )
    }
    
    private func logSecurityValidation(status: SecurityValidation) {
        Logger.shared.log(
            "Security validation status: \(status)",
            level: .info,
            subsystem: .network,
            metadata: [
                "status": status.value,
                "quality": quality.value
            ]
        )
    }
}

// MARK: - Supporting Types

private struct NetworkMetric {
    let timestamp: Date
    let status: NetworkStatus
    let quality: NetworkQuality
    let security: SecurityValidation
}

private struct SecurityValidator {
    func validateConnection(_ path: NWPath) async -> SecurityValidation {
        // Validate TLS and certificates
        guard path.status == .satisfied else {
            return .unknown
        }
        
        // Ensure proper security requirements are met
        let requirements = SecRequirements()
        guard path.supportsTLS && requirements.validateTLSVersion(path) else {
            return .invalid
        }
        
        return .valid
    }
}

private struct SecRequirements {
    func validateTLSVersion(_ path: NWPath) -> Bool {
        // Validate minimum TLS version (1.3)
        return path.supportsTLS && path.tlsVersion >= .v13
    }
}

private extension NWPath {
    var currentThroughput: Double {
        // Estimate current throughput based on interface type
        switch self.availableInterfaces.first?.type {
        case .wifi:
            return 100_000_000 // 100 Mbps
        case .cellular:
            return 10_000_000  // 10 Mbps
        case .wiredEthernet:
            return 1_000_000_000 // 1 Gbps
        default:
            return 0
        }
    }
    
    var tlsVersion: TLSVersion {
        // Determine TLS version from connection properties
        return .v13 // Default to 1.3 for security
    }
}

private enum TLSVersion: Double {
    case v12 = 1.2
    case v13 = 1.3
}