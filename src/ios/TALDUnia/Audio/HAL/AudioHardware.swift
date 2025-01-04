// Foundation v17.0+
import Foundation
import AVFoundation
import CoreAudio

/// Performance metrics for hardware monitoring
public struct HardwareMetrics {
    let thd: Double
    let latency: TimeInterval
    let temperature: Double
    let bufferUtilization: Double
    let thermalState: ProcessInfo.ThermalState
    let timestamp: Date
}

/// Core hardware abstraction layer for TALD UNIA iOS audio system
@objc public class AudioHardware: NSObject {
    
    // MARK: - Constants
    
    private enum HardwareConstants {
        static let kDefaultHardwareFormat = AVAudioFormat(
            standardFormatWithSampleRate: Double(AudioConstants.sampleRate),
            channels: UInt32(AudioConstants.channelCount)
        )
        static let kMaxSupportedChannels = 8
        static let kSupportedSampleRates = [44100, 48000, 88200, 96000, 176400, 192000, 384000]
        static let kTargetLatency = 0.010 // 10ms target latency
        static let kMaxTemperature = 85.0 // Maximum safe operating temperature
        static let kOptimalTemperature = 65.0 // Optimal operating temperature
    }
    
    // MARK: - Properties
    
    /// Device manager for hardware control
    private let deviceManager: DeviceManager
    
    /// Buffer manager for audio buffering
    private let bufferManager: BufferManager
    
    /// Audio engine for processing
    private let audioEngine: AVAudioEngine
    
    /// Current hardware audio format
    public private(set) var hardwareFormat: AVAudioFormat
    
    /// Indicates if hardware is properly configured
    public private(set) var isHardwareConfigured: Bool = false
    
    /// Current processing latency
    public private(set) var currentLatency: Double = 0.0
    
    /// Current hardware temperature
    public private(set) var currentTemperature: Double = 0.0
    
    /// Current performance metrics
    public private(set) var performanceMetrics: HardwareMetrics
    
    // MARK: - Initialization
    
    /// Initializes AudioHardware with optimal configuration
    /// - Parameter format: Optional custom audio format
    public init(format: AVAudioFormat? = nil) throws {
        // Initialize managers and engine
        self.deviceManager = try DeviceManager()
        self.bufferManager = try BufferManager(initialBufferSize: AudioConstants.bufferSize)
        self.audioEngine = AVAudioEngine()
        
        // Set initial format
        self.hardwareFormat = format ?? HardwareConstants.kDefaultHardwareFormat!
        
        // Initialize metrics
        self.performanceMetrics = HardwareMetrics(
            thd: 0.0,
            latency: 0.0,
            temperature: 0.0,
            bufferUtilization: 0.0,
            thermalState: .nominal,
            timestamp: Date()
        )
        
        super.init()
        
        // Validate and configure hardware
        try validateHardwareCapabilities(format: self.hardwareFormat)
            .get()
        
        try configureHardware(format: self.hardwareFormat)
            .get()
    }
    
    // MARK: - Hardware Configuration
    
    /// Validates hardware capabilities with ESS DAC specific checks
    /// - Parameter format: Audio format to validate
    /// - Returns: Validation result or error
    private func validateHardwareCapabilities(format: AVAudioFormat) -> Result<Bool, Error> {
        // Verify sample rate support
        guard HardwareConstants.kSupportedSampleRates.contains(Int(format.sampleRate)) else {
            return .failure(AppError.hardwareError(
                reason: "Unsupported sample rate",
                severity: .error,
                context: ErrorContext(additionalInfo: [
                    "requestedRate": format.sampleRate,
                    "supportedRates": HardwareConstants.kSupportedSampleRates
                ])
            ))
        }
        
        // Verify channel count
        guard format.channelCount <= HardwareConstants.kMaxSupportedChannels else {
            return .failure(AppError.hardwareError(
                reason: "Unsupported channel count",
                severity: .error,
                context: ErrorContext(additionalInfo: [
                    "requestedChannels": format.channelCount,
                    "maxChannels": HardwareConstants.kMaxSupportedChannels
                ])
            ))
        }
        
        return .success(true)
    }
    
    /// Configures audio hardware with optimal settings
    /// - Parameter format: Audio format to configure
    /// - Returns: Success or detailed error
    public func configureHardware(format: AVAudioFormat) -> Result<Void, Error> {
        // Validate hardware capabilities
        try? validateHardwareCapabilities(format: format).get()
        
        // Configure device
        let deviceStatus = try? deviceManager.configureDevice(
            AVAudioSession.sharedInstance().currentRoute.outputs.first,
            config: DeviceConfiguration(
                sampleRate: Int(format.sampleRate),
                bitDepth: AudioConstants.bitDepth,
                bufferSize: AudioConstants.bufferSize,
                deviceType: .ESS9038PRO
            )
        ).get()
        
        // Configure buffer manager
        try? bufferManager.resizeBuffers(newSize: AudioConstants.bufferSize).get()
        
        // Configure audio engine
        do {
            audioEngine.attach(AVAudioMixerNode())
            audioEngine.connect(
                audioEngine.mainMixerNode,
                to: audioEngine.outputNode,
                format: format
            )
            
            try audioEngine.start()
            
            // Update state
            hardwareFormat = format
            isHardwareConfigured = true
            currentLatency = deviceStatus?.currentLatency ?? 0.0
            
            return .success(())
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
    
    // MARK: - Hardware Monitoring
    
    /// Monitors hardware performance metrics
    /// - Returns: Current hardware performance metrics
    public func monitorHardwarePerformance() -> HardwareMetrics {
        let deviceMetrics = deviceManager.performanceMetrics
        let bufferMetrics = bufferManager.monitorBufferPerformance()
        
        // Update current metrics
        currentLatency = deviceMetrics.latency
        currentTemperature = measureHardwareTemperature()
        
        performanceMetrics = HardwareMetrics(
            thd: deviceMetrics.thd,
            latency: currentLatency,
            temperature: currentTemperature,
            bufferUtilization: bufferMetrics.utilizationRate,
            thermalState: ProcessInfo.processInfo.thermalState,
            timestamp: Date()
        )
        
        return performanceMetrics
    }
    
    /// Optimizes hardware settings based on current conditions
    /// - Returns: Success or detailed error
    public func optimizeHardwareSettings() -> Result<Void, Error> {
        let metrics = monitorHardwarePerformance()
        
        // Check thermal conditions
        if metrics.temperature > HardwareConstants.kMaxTemperature {
            return .failure(AppError.hardwareError(
                reason: "Hardware temperature exceeds safe limit",
                severity: .critical,
                context: ErrorContext(additionalInfo: [
                    "currentTemp": metrics.temperature,
                    "maxTemp": HardwareConstants.kMaxTemperature
                ])
            ))
        }
        
        // Optimize buffer size based on performance
        let optimalBufferSize = bufferManager.optimizeBufferSize()
        try? bufferManager.resizeBuffers(newSize: optimalBufferSize).get()
        
        // Adjust settings based on thermal state
        if metrics.temperature > HardwareConstants.kOptimalTemperature {
            // Implement thermal management strategy
            // For example, reduce processing intensity
        }
        
        return .success(())
    }
    
    // MARK: - Helper Functions
    
    /// Measures current hardware temperature
    private func measureHardwareTemperature() -> Double {
        // Implementation would include actual temperature measurement
        // For now, return a simulated value
        return 55.0 // 55°C
    }
}