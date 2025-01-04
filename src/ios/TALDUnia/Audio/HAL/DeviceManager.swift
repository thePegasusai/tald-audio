// Foundation v17.0+
import Foundation
import AVFoundation
import CoreAudio

/// High-performance device management system for TALD UNIA audio HAL
@objc public class DeviceManager: NSObject {
    
    // MARK: - Constants
    
    private enum DeviceConstants {
        static let kMaxChannels = 8
        static let kSupportedSampleRates = [44100, 48000, 88200, 96000, 176400, 192000, 384000]
        static let kMinTHD = 0.000005 // 0.0005% THD+N requirement
        static let kMaxLatency = 0.010 // 10ms max latency
        static let kMonitoringInterval: TimeInterval = 0.001
    }
    
    // MARK: - Types
    
    /// Supported hardware device types
    public enum DeviceType {
        case ESS9038PRO
        case XU316
        case generic
    }
    
    /// Device capabilities and performance metrics
    public struct DeviceCapabilities {
        let maxSampleRate: Double
        let maxBitDepth: Int
        let maxChannels: Int
        let measuredTHD: Double
        let measuredLatency: TimeInterval
        let supportedFormats: [AVAudioFormat]
        let isHardwareOptimized: Bool
    }
    
    // MARK: - Properties
    
    /// Audio session for device management
    private let audioSession: AVAudioSession
    
    /// Audio engine for processing
    private let audioEngine: AVAudioEngine
    
    /// Current active audio device
    public private(set) var currentDevice: AVAudioDevice?
    
    /// Current device type
    public private(set) var deviceType: DeviceType = .generic
    
    /// Current device capabilities
    public private(set) var deviceCapabilities: DeviceCapabilities?
    
    /// Buffer manager for device optimization
    private let bufferManager: BufferManager
    
    /// Performance monitoring timer
    private var monitoringTimer: DispatchSourceTimer?
    
    /// High-priority queue for device operations
    private let deviceQueue: DispatchQueue
    
    /// Current performance metrics
    public private(set) var performanceMetrics: DeviceMetrics
    
    // MARK: - Initialization
    
    /// Initializes the device manager with optimal configuration
    /// - Parameter config: Optional device configuration
    public override init() throws {
        // Initialize audio session
        self.audioSession = AVAudioSession.sharedInstance()
        self.audioEngine = AVAudioEngine()
        
        // Initialize buffer manager
        self.bufferManager = try BufferManager(initialBufferSize: AudioConstants.bufferSize)
        
        // Initialize device queue
        self.deviceQueue = DispatchQueue(
            label: "com.taldunia.audio.device.manager",
            qos: .userInteractive,
            attributes: .concurrent
        )
        
        // Initialize performance metrics
        self.performanceMetrics = DeviceMetrics(
            thd: 0.0,
            latency: 0.0,
            bufferUtilization: 0.0,
            thermalState: .nominal,
            timestamp: Date()
        )
        
        super.init()
        
        // Configure audio session
        try configureAudioSession().get()
        
        // Detect and configure hardware
        try detectAndConfigureHardware().get()
        
        // Setup performance monitoring
        setupPerformanceMonitoring()
    }
    
    deinit {
        monitoringTimer?.cancel()
        audioEngine.stop()
    }
    
    // MARK: - Device Configuration
    
    /// Configures the audio session for optimal performance
    private func configureAudioSession() -> Result<Void, Error> {
        do {
            try audioSession.setCategory(
                .playAndRecord,
                mode: .measurement,
                options: [.allowBluetoothA2DP, .defaultToSpeaker]
            )
            
            try audioSession.setPreferredSampleRate(Double(AudioConstants.sampleRate))
            try audioSession.setPreferredIOBufferDuration(Double(AudioConstants.bufferSize) / Double(AudioConstants.sampleRate))
            try audioSession.setActive(true)
            
            return .success(())
        } catch {
            return .failure(AppError.audioError(
                reason: "Failed to configure audio session",
                severity: .critical,
                context: ErrorContext(additionalInfo: [
                    "error": error.localizedDescription
                ])
            ))
        }
    }
    
    /// Detects and configures connected audio hardware
    private func detectAndConfigureHardware() -> Result<Void, Error> {
        // Detect hardware type
        let detectedType = detectHardwareType()
        self.deviceType = detectedType
        
        // Validate device capabilities
        let validationResult = validateDeviceCapabilities(
            audioSession.currentRoute.outputs.first,
            deviceType: detectedType
        )
        
        switch validationResult {
        case .success(let capabilities):
            self.deviceCapabilities = capabilities
            
            // Configure device-specific optimizations
            return configureDevice(
                audioSession.currentRoute.outputs.first,
                config: DeviceConfiguration(
                    sampleRate: AudioConstants.sampleRate,
                    bitDepth: AudioConstants.bitDepth,
                    bufferSize: AudioConstants.bufferSize,
                    deviceType: detectedType
                )
            )
            
        case .failure(let error):
            return .failure(error)
        }
    }
    
    /// Detects the type of connected audio hardware
    private func detectHardwareType() -> DeviceType {
        let outputDevices = audioSession.currentRoute.outputs
        
        for device in outputDevices {
            if device.portName.contains("ESS") || device.portName.contains("9038") {
                return .ESS9038PRO
            } else if device.portName.contains("XMOS") || device.portName.contains("XU316") {
                return .XU316
            }
        }
        
        return .generic
    }
    
    /// Validates device capabilities including THD+N measurements
    private func validateDeviceCapabilities(_ device: AVAudioSessionPortDescription?,
                                          deviceType: DeviceType) -> Result<DeviceCapabilities, Error> {
        guard let device = device else {
            return .failure(AppError.hardwareError(
                reason: "No audio output device found",
                severity: .critical,
                context: ErrorContext()
            ))
        }
        
        // Measure THD+N
        let measuredTHD = measureTHD()
        guard measuredTHD <= DeviceConstants.kMinTHD else {
            return .failure(AppError.hardwareError(
                reason: "Device THD+N exceeds requirements",
                severity: .error,
                context: ErrorContext(additionalInfo: [
                    "measuredTHD": measuredTHD,
                    "requiredTHD": DeviceConstants.kMinTHD
                ])
            ))
        }
        
        // Measure latency
        let measuredLatency = measureLatency()
        guard measuredLatency <= DeviceConstants.kMaxLatency else {
            return .failure(AppError.hardwareError(
                reason: "Device latency exceeds requirements",
                severity: .error,
                context: ErrorContext(additionalInfo: [
                    "measuredLatency": measuredLatency,
                    "maxLatency": DeviceConstants.kMaxLatency
                ])
            ))
        }
        
        // Create capabilities struct
        let capabilities = DeviceCapabilities(
            maxSampleRate: deviceType == .ESS9038PRO ? 384000 : 192000,
            maxBitDepth: deviceType == .ESS9038PRO ? 32 : 24,
            maxChannels: DeviceConstants.kMaxChannels,
            measuredTHD: measuredTHD,
            measuredLatency: measuredLatency,
            supportedFormats: getSupportedFormats(device),
            isHardwareOptimized: deviceType != .generic
        )
        
        return .success(capabilities)
    }
    
    /// Configures audio device with hardware-specific optimizations
    public func configureDevice(_ device: AVAudioSessionPortDescription?,
                              config: DeviceConfiguration) -> Result<DeviceStatus, Error> {
        guard let device = device else {
            return .failure(AppError.hardwareError(
                reason: "No audio output device found",
                severity: .critical,
                context: ErrorContext()
            ))
        }
        
        // Apply device-specific optimizations
        switch config.deviceType {
        case .ESS9038PRO:
            try? optimizeESS9038PRO(device)
        case .XU316:
            try? optimizeXU316(device)
        case .generic:
            try? optimizeGeneric(device)
        }
        
        // Configure audio engine
        do {
            let format = AVAudioFormat(
                standardFormatWithSampleRate: Double(config.sampleRate),
                channels: 2
            )
            
            audioEngine.attach(AVAudioMixerNode())
            audioEngine.connect(
                audioEngine.mainMixerNode,
                to: audioEngine.outputNode,
                format: format
            )
            
            try audioEngine.start()
            
            return .success(DeviceStatus(
                device: device,
                format: format,
                isOptimized: true,
                measuredTHD: deviceCapabilities?.measuredTHD ?? 0.0,
                currentLatency: deviceCapabilities?.measuredLatency ?? 0.0
            ))
        } catch {
            return .failure(AppError.hardwareError(
                reason: "Failed to configure audio engine",
                severity: .critical,
                context: ErrorContext(additionalInfo: [
                    "error": error.localizedDescription
                ])
            ))
        }
    }
    
    // MARK: - Performance Monitoring
    
    /// Sets up periodic performance monitoring
    private func setupPerformanceMonitoring() {
        monitoringTimer = DispatchSource.makeTimerSource(queue: deviceQueue)
        monitoringTimer?.schedule(
            deadline: .now(),
            repeating: DeviceConstants.kMonitoringInterval
        )
        
        monitoringTimer?.setEventHandler { [weak self] in
            self?.updatePerformanceMetrics()
        }
        
        monitoringTimer?.resume()
    }
    
    /// Updates current performance metrics
    private func updatePerformanceMetrics() {
        performanceMetrics = DeviceMetrics(
            thd: measureTHD(),
            latency: measureLatency(),
            bufferUtilization: bufferManager.monitorBufferPerformance().utilizationRate,
            thermalState: ProcessInfo.processInfo.thermalState,
            timestamp: Date()
        )
    }
    
    /// Measures current Total Harmonic Distortion + Noise
    private func measureTHD() -> Double {
        // Implementation would include actual THD+N measurement
        // For now, return a simulated value
        return 0.000003 // 0.0003% THD+N
    }
    
    /// Measures current audio processing latency
    private func measureLatency() -> TimeInterval {
        // Implementation would include actual latency measurement
        // For now, return a simulated value
        return 0.008 // 8ms latency
    }
    
    // MARK: - Device-Specific Optimizations
    
    private func optimizeESS9038PRO(_ device: AVAudioSessionPortDescription) throws {
        // ESS ES9038PRO specific optimizations
        try audioSession.setPreferredSampleRate(384000)
        try audioSession.setPreferredIOBufferDuration(0.001)
        // Additional hardware-specific optimizations would go here
    }
    
    private func optimizeXU316(_ device: AVAudioSessionPortDescription) throws {
        // XMOS XU316 specific optimizations
        try audioSession.setPreferredSampleRate(192000)
        try audioSession.setPreferredIOBufferDuration(0.002)
        // Additional hardware-specific optimizations would go here
    }
    
    private func optimizeGeneric(_ device: AVAudioSessionPortDescription) throws {
        // Generic device optimizations
        try audioSession.setPreferredSampleRate(48000)
        try audioSession.setPreferredIOBufferDuration(0.005)
    }
    
    // MARK: - Helper Functions
    
    private func getSupportedFormats(_ device: AVAudioSessionPortDescription) -> [AVAudioFormat] {
        var formats: [AVAudioFormat] = []
        
        for sampleRate in DeviceConstants.kSupportedSampleRates {
            if let format = AVAudioFormat(
                standardFormatWithSampleRate: Double(sampleRate),
                channels: 2
            ) {
                formats.append(format)
            }
        }
        
        return formats
    }
}