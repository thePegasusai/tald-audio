//
// AppDelegate.swift
// TALD UNIA Audio System
//
// Main application delegate handling lifecycle events, core system initialization,
// and power efficiency management.
//
// Dependencies:
// - UIKit (Latest) - iOS application lifecycle
// - Configuration (Internal) - System configuration management
// - Logger (Internal) - Enhanced system logging
// - AudioEngine (Internal) - Core audio processing

import UIKit

/// Power efficiency monitoring system
private class PowerEfficiencyMonitor {
    private let targetEfficiency = kPowerEfficiencyThreshold
    private var measurements: [Double] = []
    private let monitoringQueue = DispatchQueue(label: "com.taldunia.power.monitor")
    
    func getCurrentEfficiency() -> Double {
        monitoringQueue.sync {
            let efficiency = measurements.reduce(0.0, +) / Double(max(1, measurements.count))
            measurements = Array(measurements.suffix(100))
            return efficiency
        }
    }
    
    func addMeasurement(_ value: Double) {
        monitoringQueue.async {
            self.measurements.append(value)
        }
    }
}

/// Performance metrics tracking system
private class PerformanceMetricsManager {
    private var metrics: [String: Double] = [:]
    private let metricsQueue = DispatchQueue(label: "com.taldunia.metrics")
    
    func updateMetric(_ key: String, value: Double) {
        metricsQueue.async {
            self.metrics[key] = value
            Logger.shared.logPerformanceMetric(key, value: value)
        }
    }
    
    func getCurrentMetrics() -> [String: Double] {
        metricsQueue.sync { metrics }
    }
}

/// System state recovery management
private class StateRecoveryManager {
    private var lastKnownState: [String: Any] = [:]
    private let stateQueue = DispatchQueue(label: "com.taldunia.state")
    
    func saveState(_ state: [String: Any]) {
        stateQueue.async {
            self.lastKnownState = state
        }
    }
    
    func restoreState() -> [String: Any] {
        stateQueue.sync { lastKnownState }
    }
}

@main
class AppDelegate: UIResponder, UIApplicationDelegate {
    
    // MARK: - Properties
    
    var window: UIWindow?
    private var audioEngine: AudioEngine?
    private let powerEfficiencyMonitor = PowerEfficiencyMonitor()
    private let performanceMetrics = PerformanceMetricsManager()
    private let recoveryManager = StateRecoveryManager()
    
    // MARK: - Application Lifecycle
    
    func application(_ application: UIApplication, 
                    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        
        // Initialize logging system
        Logger.shared.log("TALD UNIA Audio System v\(kAppVersion) starting...",
                         level: .info,
                         subsystem: .audio)
        
        do {
            // Load and validate configuration
            try Configuration.shared.loadConfiguration().validate()
            
            // Validate hardware capabilities
            try Configuration.shared.validateHardwareCapabilities()
            
            // Initialize audio engine with power optimization
            audioEngine = try AudioEngine(
                powerMode: .balanced
            )
            
            // Configure window and root view controller
            window = UIWindow(frame: UIScreen.main.bounds)
            window?.makeKeyAndVisible()
            
            // Start performance monitoring
            setupPerformanceMonitoring()
            
            Logger.shared.log("Application launch successful",
                            level: .info,
                            subsystem: .audio)
            
            return true
            
        } catch {
            Logger.shared.logError(error, subsystem: .audio, isFatal: true)
            return false
        }
    }
    
    func applicationWillResignActive(_ application: UIApplication) {
        // Optimize power state for background
        if let engine = audioEngine {
            _ = engine.optimizePowerConsumption(for: .powerEfficient)
        }
        
        // Save current state
        let currentState = [
            "powerEfficiency": powerEfficiencyMonitor.getCurrentEfficiency(),
            "metrics": performanceMetrics.getCurrentMetrics()
        ]
        recoveryManager.saveState(currentState)
        
        Logger.shared.log("Application entering background",
                         level: .info,
                         subsystem: .audio)
    }
    
    func applicationDidBecomeActive(_ application: UIApplication) {
        do {
            // Restore previous state
            let savedState = recoveryManager.restoreState()
            
            // Restore audio engine state
            if let engine = audioEngine {
                try engine.start().get()
            }
            
            // Update power efficiency monitoring
            if let efficiency = savedState["powerEfficiency"] as? Double {
                powerEfficiencyMonitor.addMeasurement(efficiency)
            }
            
            Logger.shared.log("Application restored to active state",
                            level: .info,
                            subsystem: .audio)
            
        } catch {
            Logger.shared.logError(error, subsystem: .audio)
        }
    }
    
    func applicationWillTerminate(_ application: UIApplication) {
        // Stop audio processing
        audioEngine?.stop()
        
        // Save final metrics
        let finalMetrics = performanceMetrics.getCurrentMetrics()
        Logger.shared.log("Final performance metrics: \(finalMetrics)",
                         level: .info,
                         subsystem: .audio)
        
        Logger.shared.log("Application terminating",
                         level: .info,
                         subsystem: .audio)
    }
    
    // MARK: - Private Methods
    
    private func setupPerformanceMonitoring() {
        // Monitor power efficiency
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self,
                  let engine = self.audioEngine else { return }
            
            let metrics = engine.getPerformanceMetrics()
            
            self.performanceMetrics.updateMetric("latency", value: metrics.currentLatency)
            self.performanceMetrics.updateMetric("powerEfficiency", value: metrics.powerEfficiency)
            
            // Check power efficiency threshold
            if metrics.powerEfficiency < kPowerEfficiencyThreshold {
                Logger.shared.log("Power efficiency below threshold",
                                level: .warning,
                                subsystem: .audio)
                
                // Attempt recovery
                _ = engine.optimizePowerConsumption(for: .powerEfficient)
            }
        }
    }
}