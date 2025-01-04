//
// TALDUniaApp.swift
// TALD UNIA
//
// Main entry point for the TALD UNIA macOS application
// Version: 1.0.0
//

import SwiftUI // macOS 13.0+
import OSLog // macOS 13.0+
import Combine // macOS 13.0+
import AVFoundation // macOS 13.0+

// MARK: - Global Constants

let APP_NAME: String = "TALD UNIA"
let APP_VERSION: String = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
let PERFORMANCE_THRESHOLD_CPU: Double = 40.0
let PERFORMANCE_THRESHOLD_MEMORY: Double = 1024.0

// MARK: - Main Application

@main
@available(macOS 13.0, *)
struct TALDUniaApp: App {
    // MARK: - Properties
    
    @StateObject private var appState = AppState()
    @StateObject private var performanceMonitor = PerformanceMonitor()
    private let logger = Logger(subsystem: "com.tald.unia", category: "Application")
    private var audioSystem: AudioEngine?
    private var errorHandler: ErrorHandler?
    
    // MARK: - Initialization
    
    init() {
        do {
            // Configure audio session
            try AVAudioSession.sharedInstance().setCategory(
                .playAndRecord,
                mode: .default,
                options: [.allowBluetoothA2DP, .defaultToSpeaker]
            )
            
            // Initialize audio system
            try initializeAudioSystem()
            
            // Setup accessibility
            setupAccessibility()
            
            logger.info("TALD UNIA initialized successfully: \(APP_VERSION)")
            
        } catch {
            logger.error("Failed to initialize TALD UNIA: \(error.localizedDescription)")
            handleFatalError(error)
        }
    }
    
    // MARK: - App Scene
    
    var body: some Scene {
        WindowGroup {
            MainWindow()
                .environmentObject(appState)
                .environmentObject(performanceMonitor)
                .onAppear {
                    startPerformanceMonitoring()
                }
                .onDisappear {
                    stopPerformanceMonitoring()
                }
                .alert(
                    "Error",
                    isPresented: $appState.showError,
                    presenting: appState.currentError
                ) { error in
                    Button("OK") {
                        appState.clearError()
                    }
                } message: { error in
                    Text(error.localizedDescription)
                }
        }
        .commands {
            // Add custom menu commands
            CommandGroup(after: .appInfo) {
                Button("About TALD UNIA") {
                    showAboutPanel()
                }
            }
            
            CommandGroup(after: .systemServices) {
                Button("Audio Settings...") {
                    showAudioSettings()
                }
            }
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified)
    }
    
    // MARK: - Private Methods
    
    private func initializeAudioSystem() throws {
        // Create audio engine with optimal settings
        let config = AudioSettings(
            sampleRate: AudioConstants.SAMPLE_RATE,
            bitDepth: AudioConstants.BIT_DEPTH,
            bufferSize: AudioConstants.BUFFER_SIZE,
            channels: AudioConstants.MAX_CHANNELS
        )
        
        audioSystem = try AudioEngine()
        try audioSystem?.configureHardware(config)
        
        // Initialize error handler
        errorHandler = ErrorHandler { error in
            handleError(error)
        }
        
        // Start audio processing
        try audioSystem?.start()
    }
    
    private func setupAccessibility() {
        // Configure accessibility labels and features
        NSApplication.shared.accessibilityLabel = APP_NAME
        NSApplication.shared.accessibilityRole = .application
        
        // Enable VoiceOver support
        if NSWorkspace.shared.isVoiceOverEnabled {
            logger.info("VoiceOver enabled, configuring accessibility features")
        }
    }
    
    private func startPerformanceMonitoring() {
        performanceMonitor.startMonitoring { metrics in
            // Check CPU usage
            if metrics.cpuUsage > PERFORMANCE_THRESHOLD_CPU {
                logger.warning("High CPU usage detected: \(metrics.cpuUsage)%")
            }
            
            // Check memory usage
            if metrics.memoryUsage > PERFORMANCE_THRESHOLD_MEMORY {
                logger.warning("High memory usage detected: \(metrics.memoryUsage) MB")
            }
            
            // Monitor audio latency
            if metrics.audioLatency > AudioConstants.TARGET_LATENCY {
                logger.warning("Audio latency exceeded target: \(metrics.audioLatency * 1000)ms")
            }
            
            // Monitor THD+N
            if metrics.thdPlusNoise > AudioConstants.THD_N_THRESHOLD {
                logger.warning("THD+N exceeded threshold: \(metrics.thdPlusNoise)")
            }
        }
    }
    
    private func stopPerformanceMonitoring() {
        performanceMonitor.stopMonitoring()
    }
    
    private func handleError(_ error: Error) {
        logger.error("Application error: \(error.localizedDescription)")
        
        if let taldError = error as? TALDError {
            appState.setError(taldError)
        } else {
            appState.setError(TALDError.audioProcessingError(
                code: "UNKNOWN_ERROR",
                message: error.localizedDescription,
                metadata: ErrorMetadata(
                    timestamp: Date(),
                    component: "TALDUniaApp",
                    additionalInfo: [:]
                )
            ))
        }
    }
    
    private func handleFatalError(_ error: Error) {
        logger.fault("Fatal error: \(error.localizedDescription)")
        NSApplication.shared.terminate(nil)
    }
    
    private func showAboutPanel() {
        NSApplication.shared.orderFrontStandardAboutPanel(nil)
    }
    
    private func showAudioSettings() {
        // Show audio settings panel
        appState.showAudioSettings = true
    }
}

// MARK: - App State

@MainActor
final class AppState: ObservableObject {
    @Published var showError: Bool = false
    @Published var currentError: TALDError?
    @Published var showAudioSettings: Bool = false
    
    func setError(_ error: TALDError) {
        currentError = error
        showError = true
    }
    
    func clearError() {
        currentError = nil
        showError = false
    }
}

// MARK: - Performance Monitor

final class PerformanceMonitor: ObservableObject {
    private var timer: Timer?
    private var monitoringCallback: ((PerformanceMetrics) -> Void)?
    
    struct PerformanceMetrics {
        var cpuUsage: Double
        var memoryUsage: Double
        var audioLatency: TimeInterval
        var thdPlusNoise: Double
    }
    
    func startMonitoring(callback: @escaping (PerformanceMetrics) -> Void) {
        monitoringCallback = callback
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.collectMetrics()
        }
    }
    
    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
        monitoringCallback = nil
    }
    
    private func collectMetrics() {
        // Collect system and audio metrics
        let metrics = PerformanceMetrics(
            cpuUsage: ProcessInfo.processInfo.systemUptime,
            memoryUsage: ProcessInfo.processInfo.physicalMemory / 1024 / 1024,
            audioLatency: AVAudioSession.sharedInstance().outputLatency,
            thdPlusNoise: 0.0003 // Example value
        )
        
        monitoringCallback?(metrics)
    }
}