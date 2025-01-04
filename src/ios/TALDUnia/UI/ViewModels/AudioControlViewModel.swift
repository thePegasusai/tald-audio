// Foundation Latest
import Foundation
import Combine
import SwiftUI

/// Thread-safe ViewModel managing audio control state and user interactions with comprehensive error handling and performance monitoring
@MainActor
public final class AudioControlViewModel: ObservableObject {
    // MARK: - Constants
    
    private let kDefaultVolume: Float = 0.75
    private let kMinVolume: Float = 0.0
    private let kMaxVolume: Float = 1.0
    private let kVolumeStep: Float = 0.05
    private let kMaxRetryAttempts: Int = 3
    private let kRetryDelay: TimeInterval = 0.5
    private let kLatencyThreshold: TimeInterval = 0.010
    
    // MARK: - Published Properties
    
    @Published private(set) var currentVolume: Float
    @Published private(set) var isProcessing: Bool = false
    @Published private(set) var isEnhancementEnabled: Bool = true
    @Published private(set) var isSpatialEnabled: Bool = true
    @Published private(set) var currentLatency: TimeInterval = 0
    @Published private(set) var lastError: AudioControlError?
    
    // MARK: - Publishers
    
    let volumeChanged = PassthroughSubject<Float, Never>()
    let processingStateChanged = PassthroughSubject<Bool, Never>()
    let errorOccurred = PassthroughSubject<AudioControlError, Never>()
    
    // MARK: - Private Properties
    
    private let audioEngine: AudioEngine
    private let profileManager: ProfileManager
    private var cancellables = Set<AnyCancellable>()
    private let processingQueue = DispatchQueue(
        label: "com.taldunia.audio.processing",
        qos: .userInteractive
    )
    
    // MARK: - Initialization
    
    public init(audioEngine: AudioEngine) {
        self.audioEngine = audioEngine
        self.profileManager = ProfileManager.shared
        self.currentVolume = kDefaultVolume
        
        setupObservers()
        loadActiveProfile()
        setupPerformanceMonitoring()
    }
    
    // MARK: - Public Methods
    
    /// Handles volume changes with error handling and updates the audio engine
    public func handleVolumeChange(_ newValue: Float) -> Result<Void, AudioControlError> {
        guard newValue >= kMinVolume && newValue <= kMaxVolume else {
            return .failure(.invalidVolume(value: newValue))
        }
        
        do {
            // Update volume with retry mechanism
            try withRetry(maxAttempts: kMaxRetryAttempts) {
                try self.audioEngine.updateConfiguration([
                    "volume": newValue,
                    "enhancementEnabled": self.isEnhancementEnabled,
                    "spatialEnabled": self.isSpatialEnabled
                ]).get()
            }
            
            // Update state and notify observers
            currentVolume = newValue
            volumeChanged.send(newValue)
            
            // Update active profile
            Task {
                await updateActiveProfile()
            }
            
            return .success(())
            
        } catch {
            let controlError = AudioControlError.volumeUpdateFailed(
                error: error.localizedDescription
            )
            handleError(controlError)
            return .failure(controlError)
        }
    }
    
    /// Starts the audio processing chain with comprehensive error handling
    public func startAudioProcessing() -> Result<Void, AudioControlError> {
        guard !isProcessing else {
            return .failure(.alreadyProcessing)
        }
        
        do {
            isProcessing = true
            processingStateChanged.send(true)
            
            // Start audio engine with retry mechanism
            try withRetry(maxAttempts: kMaxRetryAttempts) {
                try self.audioEngine.start().get()
            }
            
            // Monitor performance
            monitorPerformance()
            
            return .success(())
            
        } catch {
            isProcessing = false
            processingStateChanged.send(false)
            
            let controlError = AudioControlError.processingFailed(
                error: error.localizedDescription
            )
            handleError(controlError)
            return .failure(controlError)
        }
    }
    
    /// Stops audio processing with cleanup
    public func stopAudioProcessing() {
        audioEngine.stop()
        isProcessing = false
        processingStateChanged.send(false)
    }
    
    /// Toggles AI enhancement with state update
    public func toggleEnhancement() -> Result<Void, AudioControlError> {
        isEnhancementEnabled.toggle()
        
        return updateAudioConfiguration([
            "enhancementEnabled": isEnhancementEnabled
        ])
    }
    
    /// Toggles spatial audio processing with state update
    public func toggleSpatialAudio() -> Result<Void, AudioControlError> {
        isSpatialEnabled.toggle()
        
        return updateAudioConfiguration([
            "spatialEnabled": isSpatialEnabled
        ])
    }
    
    // MARK: - Private Methods
    
    private func setupObservers() {
        // Monitor audio engine state changes
        audioEngine.publisher(for: \.isRunning)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isRunning in
                self?.isProcessing = isRunning
                self?.processingStateChanged.send(isRunning)
            }
            .store(in: &cancellables)
        
        // Monitor latency changes
        audioEngine.publisher(for: \.currentLatency)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] latency in
                self?.currentLatency = latency
                self?.validateLatency(latency)
            }
            .store(in: &cancellables)
    }
    
    private func loadActiveProfile() {
        Task {
            if let profile = try? await profileManager.getProfile(withId: UUID()).get() {
                // Apply profile settings
                if let volume = profile.preferences["volume"] as? Float {
                    _ = handleVolumeChange(volume)
                }
                if let enhancement = profile.preferences["enhancementEnabled"] as? Bool {
                    isEnhancementEnabled = enhancement
                }
                if let spatial = profile.preferences["spatialEnabled"] as? Bool {
                    isSpatialEnabled = spatial
                }
            }
        }
    }
    
    private func updateActiveProfile() async {
        let settings: [String: Any] = [
            "volume": currentVolume,
            "enhancementEnabled": isEnhancementEnabled,
            "spatialEnabled": isSpatialEnabled
        ]
        
        if let profile = try? await profileManager.getProfile(withId: UUID()).get() {
            _ = try? await profileManager.updateProfile(profile).get()
        }
    }
    
    private func setupPerformanceMonitoring() {
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.monitorPerformance()
        }
    }
    
    private func monitorPerformance() {
        let metrics = audioEngine.getPerformanceMetrics()
        currentLatency = metrics.currentLatency
        validateLatency(metrics.currentLatency)
    }
    
    private func validateLatency(_ latency: TimeInterval) {
        if latency > kLatencyThreshold {
            handleError(.latencyExceeded(current: latency, threshold: kLatencyThreshold))
        }
    }
    
    private func updateAudioConfiguration(_ parameters: [String: Any]) -> Result<Void, AudioControlError> {
        do {
            try withRetry(maxAttempts: kMaxRetryAttempts) {
                try self.audioEngine.updateConfiguration(parameters).get()
            }
            return .success(())
        } catch {
            let controlError = AudioControlError.configurationFailed(
                error: error.localizedDescription
            )
            handleError(controlError)
            return .failure(controlError)
        }
    }
    
    private func withRetry<T>(
        maxAttempts: Int,
        delay: TimeInterval = kRetryDelay,
        operation: () throws -> T
    ) throws -> T {
        var lastError: Error?
        
        for attempt in 1...maxAttempts {
            do {
                return try operation()
            } catch {
                lastError = error
                if attempt < maxAttempts {
                    Thread.sleep(forTimeInterval: delay)
                }
            }
        }
        
        throw lastError ?? AudioControlError.maxRetryAttemptsExceeded
    }
    
    private func handleError(_ error: AudioControlError) {
        lastError = error
        errorOccurred.send(error)
    }
}

// MARK: - Error Types

public enum AudioControlError: LocalizedError {
    case invalidVolume(value: Float)
    case volumeUpdateFailed(error: String)
    case processingFailed(error: String)
    case configurationFailed(error: String)
    case alreadyProcessing
    case maxRetryAttemptsExceeded
    case latencyExceeded(current: TimeInterval, threshold: TimeInterval)
    
    public var errorDescription: String? {
        switch self {
        case .invalidVolume(let value):
            return "Invalid volume value: \(value)"
        case .volumeUpdateFailed(let error):
            return "Failed to update volume: \(error)"
        case .processingFailed(let error):
            return "Audio processing failed: \(error)"
        case .configurationFailed(let error):
            return "Configuration update failed: \(error)"
        case .alreadyProcessing:
            return "Audio processing already in progress"
        case .maxRetryAttemptsExceeded:
            return "Maximum retry attempts exceeded"
        case .latencyExceeded(let current, let threshold):
            return "Latency threshold exceeded: \(current)s > \(threshold)s"
        }
    }
}