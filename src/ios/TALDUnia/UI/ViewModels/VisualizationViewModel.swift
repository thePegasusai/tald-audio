//
// VisualizationViewModel.swift
// TALD UNIA Audio System
//
// View model managing real-time audio visualization with optimized performance
// monitoring and power-efficient updates.
//
// Dependencies:
// - SwiftUI (Latest) - Core SwiftUI framework for UI state management
// - Combine (Latest) - Reactive updates and data binding

import SwiftUI
import Combine

// MARK: - Constants

private enum VisualizationConstants {
    static let updateInterval: TimeInterval = 0.016 // ~60 FPS
    static let warningLatencyThreshold: Double = 10.0 // ms
    static let maxProcessingLoad: Float = 100.0
    static let powerEfficiencyThreshold: Float = 90.0
    static let memoryWarningThreshold: Float = 85.0
    static let batchUpdateSize: Int = 64
}

// MARK: - Supporting Types

public enum VisualizationState {
    case inactive
    case active
    case warning(String)
    case error(String)
}

public struct VisualizationConfig {
    let updateInterval: TimeInterval
    let powerOptimized: Bool
    let enableWarnings: Bool
    
    public init(
        updateInterval: TimeInterval = VisualizationConstants.updateInterval,
        powerOptimized: Bool = true,
        enableWarnings: Bool = true
    ) {
        self.updateInterval = updateInterval
        self.powerOptimized = powerOptimized
        self.enableWarnings = enableWarnings
    }
}

public enum VisualizationError: Error {
    case initializationFailed(String)
    case processingError(String)
    case resourceError(String)
}

// MARK: - VisualizationViewModel Implementation

@MainActor
public final class VisualizationViewModel: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published private(set) var isActive: Bool = false
    @Published private(set) var currentLatency: Double = 0.0
    @Published private(set) var processingLoad: Float = 0.0
    @Published private(set) var powerEfficiency: Float = 0.0
    @Published private(set) var showWarning: Bool = false
    @Published private(set) var currentState: VisualizationState = .inactive
    
    // MARK: - Private Properties
    
    private let spectrumAnalyzer: SpectrumAnalyzer
    private let audioProcessor: AudioProcessor
    private let config: VisualizationConfig
    private var subscriptions = Set<AnyCancellable>()
    private let batchProcessor: BatchProcessor
    private let performanceMonitor: PerformanceMonitor
    
    // MARK: - Initialization
    
    public init(
        spectrumAnalyzer: SpectrumAnalyzer,
        audioProcessor: AudioProcessor,
        config: VisualizationConfig = VisualizationConfig()
    ) {
        self.spectrumAnalyzer = spectrumAnalyzer
        self.audioProcessor = audioProcessor
        self.config = config
        self.batchProcessor = BatchProcessor(batchSize: VisualizationConstants.batchUpdateSize)
        self.performanceMonitor = PerformanceMonitor()
        
        setupOptimizedSubscriptions()
    }
    
    // MARK: - Public Interface
    
    public func startVisualization() -> Result<Void, VisualizationError> {
        guard !isActive else { return .success(()) }
        
        do {
            // Start spectrum analyzer with power optimization
            spectrumAnalyzer.startAnalyzer()
            
            // Configure performance monitoring
            performanceMonitor.startMonitoring()
            
            // Set up optimized update timer
            setupOptimizedSubscriptions()
            
            isActive = true
            currentState = .active
            
            return .success(())
            
        } catch {
            return .failure(.initializationFailed(error.localizedDescription))
        }
    }
    
    public func stopVisualization() {
        guard isActive else { return }
        
        // Stop all monitoring
        spectrumAnalyzer.stopAnalyzer()
        performanceMonitor.stopMonitoring()
        
        // Cancel subscriptions
        subscriptions.forEach { $0.cancel() }
        subscriptions.removeAll()
        
        // Reset state
        isActive = false
        currentState = .inactive
        showWarning = false
    }
    
    // MARK: - Private Methods
    
    private func setupOptimizedSubscriptions() {
        // Monitor audio processor metrics
        Timer.publish(every: config.updateInterval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.updateProcessingMetrics()
            }
            .store(in: &subscriptions)
        
        // Monitor performance warnings
        performanceMonitor.$warningState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] warning in
                if let warning = warning {
                    self?.currentState = .warning(warning)
                    self?.showWarning = true
                } else {
                    self?.showWarning = false
                }
            }
            .store(in: &subscriptions)
    }
    
    private func updateProcessingMetrics() {
        guard isActive else { return }
        
        // Update metrics using batch processor for efficiency
        batchProcessor.processBatch { [weak self] in
            guard let self = self else { return }
            
            // Update latency
            self.currentLatency = self.audioProcessor.currentLatency
            
            // Update processing load
            self.processingLoad = Float(self.audioProcessor.processingLoad)
            
            // Update power efficiency
            self.powerEfficiency = Float(self.audioProcessor.powerEfficiency)
            
            // Check warning thresholds
            self.checkWarningThresholds()
        }
    }
    
    private func checkWarningThresholds() {
        if currentLatency > VisualizationConstants.warningLatencyThreshold {
            currentState = .warning("High latency detected")
            showWarning = true
        } else if processingLoad > VisualizationConstants.maxProcessingLoad {
            currentState = .warning("High processing load")
            showWarning = true
        } else if powerEfficiency < VisualizationConstants.powerEfficiencyThreshold {
            currentState = .warning("Low power efficiency")
            showWarning = true
        } else {
            showWarning = false
        }
    }
}

// MARK: - Supporting Classes

private final class BatchProcessor {
    private let batchSize: Int
    private var currentBatch: Int = 0
    
    init(batchSize: Int) {
        self.batchSize = batchSize
    }
    
    func processBatch(operation: () -> Void) {
        currentBatch += 1
        if currentBatch >= batchSize {
            operation()
            currentBatch = 0
        }
    }
}

private final class PerformanceMonitor {
    @Published private(set) var warningState: String?
    private var isMonitoring: Bool = false
    
    func startMonitoring() {
        isMonitoring = true
    }
    
    func stopMonitoring() {
        isMonitoring = false
        warningState = nil
    }
}