//
// AppDelegate.swift
// TALD UNIA
//
// Main application delegate for TALD UNIA macOS application
// Version: 1.0.0
//

import Cocoa // macOS 13.0+

// Internal imports
import Configuration
import Logger
import AudioEngine

// MARK: - Global Constants

let APP_NAME: String = "TALD UNIA"
let APP_VERSION: String = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
let PERFORMANCE_MONITORING_INTERVAL: TimeInterval = 1.0

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {
    // MARK: - Properties
    
    @IBOutlet weak var window: NSWindow!
    
    private let audioEngine: AudioEngine
    private let monitoringQueue: DispatchQueue
    private var performanceMonitor: DispatchSourceTimer?
    private var isInitialized: Bool = false
    
    // MARK: - Initialization
    
    override init() {
        // Initialize with thread safety
        self.monitoringQueue = DispatchQueue(
            label: "com.tald.unia.monitoring",
            qos: .utility,
            attributes: .concurrent
        )
        
        // Initialize audio engine
        do {
            self.audioEngine = try AudioEngine()
        } catch {
            fatalError("Failed to initialize audio engine: \(error.localizedDescription)")
        }
        
        super.init()
    }
    
    // MARK: - Application Lifecycle
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        do {
            // Initialize logger with startup context
            Logger.shared.log(
                "Application starting",
                severity: .info,
                context: "AppDelegate",
                metadata: [
                    "version": APP_VERSION,
                    "buildNumber": String(BUILD_NUMBER)
                ]
            )
            
            // Load and validate configuration
            guard case .success = Configuration.shared.loadConfiguration() else {
                throw TALDError.configurationError(
                    code: "CONFIG_LOAD_FAILED",
                    message: "Failed to load application configuration",
                    metadata: ErrorMetadata(
                        timestamp: Date(),
                        component: "AppDelegate",
                        additionalInfo: [:]
                    )
                )
            }
            
            // Configure audio engine with optimal settings
            try configureAudioEngine()
            
            // Setup performance monitoring
            setupPerformanceMonitoring()
            
            // Start audio processing
            guard case .success = audioEngine.start() else {
                throw TALDError.audioProcessingError(
                    code: "ENGINE_START_FAILED",
                    message: "Failed to start audio engine",
                    metadata: ErrorMetadata(
                        timestamp: Date(),
                        component: "AppDelegate",
                        additionalInfo: [:]
                    )
                )
            }
            
            isInitialized = true
            
            Logger.shared.log(
                "Application initialized successfully",
                severity: .info,
                context: "AppDelegate",
                metadata: [
                    "audioLatency": String(format: "%.3f ms", audioEngine.currentLatency * 1000),
                    "processingLoad": String(format: "%.1f%%", audioEngine.processingLoad * 100)
                ]
            )
            
        } catch {
            Logger.shared.error(
                error,
                context: "AppDelegate",
                metadata: [
                    "state": "initialization",
                    "timestamp": ISO8601DateFormatter().string(from: Date())
                ]
            )
            
            // Show error alert to user
            let alert = NSAlert()
            alert.messageText = "Initialization Error"
            alert.informativeText = "Failed to initialize TALD UNIA: \(error.localizedDescription)"
            alert.alertStyle = .critical
            alert.runModal()
            
            NSApplication.shared.terminate(nil)
        }
    }
    
    func applicationWillTerminate(_ aNotification: Notification) {
        Logger.shared.log(
            "Application terminating",
            severity: .info,
            context: "AppDelegate"
        )
        
        // Stop performance monitoring
        performanceMonitor?.cancel()
        performanceMonitor = nil
        
        // Stop audio engine
        audioEngine.stop()
        
        // Save configuration
        if case .failure(let error) = Configuration.shared.saveConfiguration() {
            Logger.shared.error(
                error,
                context: "AppDelegate",
                metadata: ["state": "shutdown"]
            )
        }
        
        Logger.shared.log(
            "Application terminated successfully",
            severity: .info,
            context: "AppDelegate"
        )
    }
    
    // MARK: - Private Methods
    
    private func configureAudioEngine() throws {
        let config = Configuration.shared.audioConfig
        
        // Validate audio configuration
        guard config.sampleRate >= 44100,
              config.bitDepth >= 16,
              config.bufferSize >= 64 else {
            throw TALDError.configurationError(
                code: "INVALID_AUDIO_CONFIG",
                message: "Invalid audio configuration parameters",
                metadata: ErrorMetadata(
                    timestamp: Date(),
                    component: "AppDelegate",
                    additionalInfo: [
                        "sampleRate": String(config.sampleRate),
                        "bitDepth": String(config.bitDepth),
                        "bufferSize": String(config.bufferSize)
                    ]
                )
            )
        }
    }
    
    private func setupPerformanceMonitoring() {
        performanceMonitor = DispatchSource.makeTimerSource(queue: monitoringQueue)
        performanceMonitor?.schedule(
            deadline: .now(),
            repeating: PERFORMANCE_MONITORING_INTERVAL
        )
        
        performanceMonitor?.setEventHandler { [weak self] in
            guard let self = self else { return }
            
            let metrics = self.audioEngine.getPerformanceMetrics()
            
            // Log performance metrics
            Logger.shared.log(
                "Performance update",
                severity: .info,
                context: "Performance",
                metadata: [
                    "latency": String(format: "%.3f ms", metrics.currentLatency * 1000),
                    "processingLoad": String(format: "%.1f%%", metrics.processingLoad * 100),
                    "bufferUtilization": String(format: "%.1f%%", metrics.bufferUtilization * 100)
                ]
            )
            
            // Check performance thresholds
            if metrics.currentLatency > AudioConstants.TARGET_LATENCY {
                Logger.shared.log(
                    "High latency detected",
                    severity: .warning,
                    context: "Performance",
                    metadata: [
                        "currentLatency": String(format: "%.3f ms", metrics.currentLatency * 1000),
                        "threshold": String(format: "%.3f ms", AudioConstants.TARGET_LATENCY * 1000)
                    ]
                )
            }
        }
        
        performanceMonitor?.resume()
    }
}