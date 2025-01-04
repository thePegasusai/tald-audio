//
// AudioDeviceManager.swift
// TALD UNIA
//
// High-level audio device management with hardware optimization and performance monitoring
// Version: 1.0.0
//

import Foundation // macOS 13.0+
import CoreAudio // macOS 13.0+
import AudioToolbox // macOS 13.0+
import AVFoundation // macOS 13.0+

// MARK: - Global Constants

private let kDefaultDeviceName = "TALD UNIA Audio Device"
private let kDeviceSearchInterval: TimeInterval = 1.0
private let kMaxDevices = 16
private let kPerformanceMonitoringInterval: TimeInterval = 0.1

// MARK: - Audio Device Structure

private struct AudioDevice {
    let deviceID: AudioDeviceID
    let name: String
    let sampleRate: Float64
    let channelCount: UInt32
    let isInput: Bool
    let isOutput: Bool
    let bufferFrameSize: UInt32
}

// MARK: - Audio Device Manager

@objc public class AudioDeviceManager: NSObject {
    // MARK: - Properties
    
    private let hardwareManager: AudioHardwareManager
    private let coreAudioManager: CoreAudioManager
    private let bufferManager: BufferManager
    private let deviceQueue: DispatchQueue
    private var deviceMonitorTimer: Timer?
    private(set) var isDeviceInitialized: Bool = false
    
    // MARK: - Initialization
    
    public init(hardwareManager: AudioHardwareManager,
                coreAudioManager: CoreAudioManager,
                bufferManager: BufferManager) {
        self.hardwareManager = hardwareManager
        self.coreAudioManager = coreAudioManager
        self.bufferManager = bufferManager
        self.deviceQueue = DispatchQueue(label: "com.taldunia.device.manager", qos: .userInteractive)
        
        super.init()
        setupDeviceMonitoring()
    }
    
    deinit {
        deviceMonitorTimer?.invalidate()
    }
    
    // MARK: - Device Management
    
    /// Retrieves list of available audio devices with their capabilities
    public func getAvailableDevices() -> [AudioDevice] {
        var deviceList = [AudioDevice]()
        
        // Get all audio devices
        var propertySize: UInt32 = 0
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var status = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &propertySize
        )
        
        guard status == noErr else { return [] }
        
        let deviceCount = Int(propertySize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)
        
        status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &propertySize,
            &deviceIDs
        )
        
        guard status == noErr else { return [] }
        
        // Get device details
        for deviceID in deviceIDs {
            if let device = getDeviceInfo(deviceID: deviceID) {
                deviceList.append(device)
            }
        }
        
        return deviceList.filter { validateDeviceCapabilities(deviceID: $0.deviceID) == .success(true) }
    }
    
    /// Initializes selected audio device with optimal settings
    public func initializeDevice(deviceID: AudioDeviceID) -> Result<Void, TALDError> {
        return deviceQueue.sync {
            // Validate device capabilities
            guard case .success(true) = validateDeviceCapabilities(deviceID: deviceID) else {
                return .failure(TALDError.hardwareError(
                    code: "DEVICE_VALIDATION_FAILED",
                    message: "Device does not meet requirements",
                    metadata: ErrorMetadata(
                        timestamp: Date(),
                        component: "AudioDeviceManager",
                        additionalInfo: ["deviceID": "\(deviceID)"]
                    )
                ))
            }
            
            // Initialize hardware
            let hardwareResult = hardwareManager.initializeHardware()
            guard case .success = hardwareResult else {
                return .failure(TALDError.hardwareError(
                    code: "HARDWARE_INIT_FAILED",
                    message: "Failed to initialize hardware",
                    metadata: ErrorMetadata(
                        timestamp: Date(),
                        component: "AudioDeviceManager",
                        additionalInfo: ["deviceID": "\(deviceID)"]
                    )
                ))
            }
            
            // Configure buffers
            let bufferResult = bufferManager.configureBuffers(
                deviceID: deviceID,
                config: BufferConfiguration(
                    size: AudioConstants.BUFFER_SIZE,
                    count: 3,
                    channels: AudioConstants.MAX_CHANNELS
                )
            )
            
            guard case .success = bufferResult else {
                return .failure(TALDError.audioProcessingError(
                    code: "BUFFER_CONFIG_FAILED",
                    message: "Failed to configure audio buffers",
                    metadata: ErrorMetadata(
                        timestamp: Date(),
                        component: "AudioDeviceManager",
                        additionalInfo: ["deviceID": "\(deviceID)"]
                    )
                ))
            }
            
            isDeviceInitialized = true
            startDeviceMonitoring()
            
            return .success(())
        }
    }
    
    /// Switches audio playback to different device
    public func switchDevice(newDeviceID: AudioDeviceID) -> Result<Bool, TALDError> {
        return deviceQueue.sync {
            // Stop current audio stream
            let stopResult = coreAudioManager.stopAudioStream()
            guard case .success = stopResult else {
                return .failure(TALDError.audioProcessingError(
                    code: "STREAM_STOP_FAILED",
                    message: "Failed to stop current audio stream",
                    metadata: ErrorMetadata(
                        timestamp: Date(),
                        component: "AudioDeviceManager",
                        additionalInfo: ["deviceID": "\(newDeviceID)"]
                    )
                ))
            }
            
            // Initialize new device
            let initResult = initializeDevice(deviceID: newDeviceID)
            guard case .success = initResult else {
                return .failure(TALDError.hardwareError(
                    code: "DEVICE_SWITCH_FAILED",
                    message: "Failed to initialize new device",
                    metadata: ErrorMetadata(
                        timestamp: Date(),
                        component: "AudioDeviceManager",
                        additionalInfo: ["deviceID": "\(newDeviceID)"]
                    )
                ))
            }
            
            // Start audio stream
            let startResult = coreAudioManager.startAudioStream()
            guard case .success = startResult else {
                return .failure(TALDError.audioProcessingError(
                    code: "STREAM_START_FAILED",
                    message: "Failed to start audio stream",
                    metadata: ErrorMetadata(
                        timestamp: Date(),
                        component: "AudioDeviceManager",
                        additionalInfo: ["deviceID": "\(newDeviceID)"]
                    )
                ))
            }
            
            return .success(true)
        }
    }
    
    // MARK: - Private Methods
    
    private func validateDeviceCapabilities(deviceID: AudioDeviceID) -> Result<Bool, TALDError> {
        guard let device = getDeviceInfo(deviceID: deviceID) else {
            return .failure(TALDError.hardwareError(
                code: "DEVICE_NOT_FOUND",
                message: "Device information not available",
                metadata: ErrorMetadata(
                    timestamp: Date(),
                    component: "AudioDeviceManager",
                    additionalInfo: ["deviceID": "\(deviceID)"]
                )
            ))
        }
        
        // Validate sample rate
        guard device.sampleRate >= Float64(AudioConstants.SAMPLE_RATE) else {
            return .success(false)
        }
        
        // Validate channel count
        guard device.channelCount >= UInt32(AudioConstants.MAX_CHANNELS) else {
            return .success(false)
        }
        
        // Validate buffer size
        guard device.bufferFrameSize <= UInt32(AudioConstants.BUFFER_SIZE * 2) else {
            return .success(false)
        }
        
        return .success(true)
    }
    
    private func getDeviceInfo(deviceID: AudioDeviceID) -> AudioDevice? {
        var name: String = ""
        var propertySize: UInt32 = 256
        var deviceNameProperty = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var deviceNameBuffer = [UInt8](repeating: 0, count: Int(propertySize))
        var status = AudioObjectGetPropertyData(
            deviceID,
            &deviceNameProperty,
            0,
            nil,
            &propertySize,
            &deviceNameBuffer
        )
        
        if status == noErr {
            name = String(bytes: deviceNameBuffer.prefix(Int(propertySize)), encoding: .utf8) ?? ""
        }
        
        // Get sample rate
        var sampleRate: Float64 = 0.0
        propertySize = UInt32(MemoryLayout<Float64>.size)
        var sampleRateProperty = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        status = AudioObjectGetPropertyData(
            deviceID,
            &sampleRateProperty,
            0,
            nil,
            &propertySize,
            &sampleRate
        )
        
        guard status == noErr else { return nil }
        
        // Get channel count and I/O status
        var channelCount: UInt32 = 0
        var channelCountProperty = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        
        propertySize = 0
        status = AudioObjectGetPropertyDataSize(
            deviceID,
            &channelCountProperty,
            0,
            nil,
            &propertySize
        )
        
        guard status == noErr else { return nil }
        
        let bufferList = UnsafeMutablePointer<AudioBufferList>.allocate(capacity: Int(propertySize))
        defer { bufferList.deallocate() }
        
        status = AudioObjectGetPropertyData(
            deviceID,
            &channelCountProperty,
            0,
            nil,
            &propertySize,
            bufferList
        )
        
        guard status == noErr else { return nil }
        
        for i in 0..<Int(bufferList.pointee.mNumberBuffers) {
            channelCount += bufferList.pointee.mBuffers[i].mNumberChannels
        }
        
        // Get buffer frame size
        var bufferFrameSize: UInt32 = 0
        propertySize = UInt32(MemoryLayout<UInt32>.size)
        var bufferSizeProperty = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyBufferFrameSize,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        status = AudioObjectGetPropertyData(
            deviceID,
            &bufferSizeProperty,
            0,
            nil,
            &propertySize,
            &bufferFrameSize
        )
        
        guard status == noErr else { return nil }
        
        return AudioDevice(
            deviceID: deviceID,
            name: name,
            sampleRate: sampleRate,
            channelCount: channelCount,
            isInput: true,
            isOutput: true,
            bufferFrameSize: bufferFrameSize
        )
    }
    
    private func setupDeviceMonitoring() {
        deviceMonitorTimer = Timer.scheduledTimer(
            withTimeInterval: kDeviceSearchInterval,
            repeats: true
        ) { [weak self] _ in
            self?.monitorDeviceStatus()
        }
    }
    
    private func startDeviceMonitoring() {
        deviceMonitorTimer?.fire()
    }
    
    @objc private func monitorDeviceStatus() {
        guard isDeviceInitialized else { return }
        
        // Monitor hardware metrics
        let hardwareMetrics = hardwareManager.currentDevice
        
        // Monitor buffer performance
        let bufferMetrics = bufferManager.monitorPerformance()
        
        // Check for performance issues
        if bufferMetrics.underruns > 0 || bufferMetrics.overruns > 0 {
            NotificationCenter.default.post(
                name: Notification.Name("AudioDevicePerformanceIssue"),
                object: self,
                userInfo: [
                    "underruns": bufferMetrics.underruns,
                    "overruns": bufferMetrics.overruns
                ]
            )
        }
    }
}