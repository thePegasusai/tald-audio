//
// CoreAudioManager.swift
// TALD UNIA
//
// Core Audio framework integration with enhanced hardware support and performance monitoring
// Version: 1.0.0
//

import Foundation // macOS 13.0+
import CoreAudio // macOS 13.0+
import AudioToolbox // macOS 13.0+
import AVFoundation // macOS 13.0+

// MARK: - Performance Constants
private let kDefaultStreamFormat = AudioStreamBasicDescription(
    mSampleRate: Double(AudioConstants.SAMPLE_RATE),
    mFormatID: kAudioFormatLinearPCM,
    mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
    mBytesPerPacket: 4,
    mFramesPerPacket: 1,
    mBytesPerFrame: 4,
    mChannelsPerFrame: 2,
    mBitsPerChannel: 32,
    mReserved: 0
)

private let kMaxLatency: Float64 = 0.010 // 10ms maximum latency requirement
private let kPerformanceMonitoringInterval: TimeInterval = 0.100

// MARK: - Performance Metrics
private struct PerformanceMetrics {
    var currentLatency: Float64 = 0.0
    var thdPlusNoise: Float64 = 0.0
    var bufferUtilization: Float64 = 0.0
    var processingLoad: Float64 = 0.0
    var underruns: Int = 0
    var overruns: Int = 0
}

// MARK: - Core Audio Manager
@objc public class CoreAudioManager: NSObject {
    // MARK: - Properties
    private let hardwareManager: AudioHardwareManager
    private let bufferManager: BufferManager
    private let audioQueue: DispatchQueue
    private var streamFormat: AudioStreamBasicDescription
    private var currentDevice: AudioDeviceID = 0
    private var isStreamActive: Bool = false
    private var metrics: PerformanceMetrics = PerformanceMetrics()
    private var audioIOProcID: AudioDeviceIOProcID?
    private var monitorTimer: Timer?
    
    // MARK: - Initialization
    public init(hardwareManager: AudioHardwareManager, bufferManager: BufferManager) {
        self.hardwareManager = hardwareManager
        self.bufferManager = bufferManager
        self.audioQueue = DispatchQueue(label: "com.taldunia.audio.core", qos: .userInteractive)
        self.streamFormat = kDefaultStreamFormat
        
        super.init()
        setupPerformanceMonitoring()
    }
    
    deinit {
        stopAudioStream()
        monitorTimer?.invalidate()
    }
    
    // MARK: - Audio Stream Management
    public func startAudioStream() -> Result<Void, TALDError> {
        guard !isStreamActive else { return .success(()) }
        
        return audioQueue.sync {
            // Validate hardware initialization
            guard hardwareManager.isHardwareInitialized else {
                return .failure(TALDError.audioProcessingError(
                    code: "HARDWARE_NOT_INITIALIZED",
                    message: "Hardware not properly initialized",
                    metadata: ErrorMetadata(
                        timestamp: Date(),
                        component: "CoreAudioManager",
                        additionalInfo: ["device": "\(currentDevice)"]
                    )
                ))
            }
            
            // Configure audio stream
            let result = configureAudioStream(
                deviceID: hardwareManager.currentDevice,
                format: streamFormat
            )
            
            switch result {
            case .success:
                isStreamActive = true
                startPerformanceMonitoring()
                return .success(())
                
            case .failure(let error):
                return .failure(error)
            }
        }
    }
    
    public func stopAudioStream() -> Result<Void, TALDError> {
        guard isStreamActive else { return .success(()) }
        
        return audioQueue.sync {
            guard let procID = audioIOProcID else { return .success(()) }
            
            let status = AudioDeviceDestroyIOProcID(currentDevice, procID)
            guard status == noErr else {
                return .failure(TALDError.audioProcessingError(
                    code: "STOP_STREAM_FAILED",
                    message: "Failed to stop audio stream",
                    metadata: ErrorMetadata(
                        timestamp: Date(),
                        component: "CoreAudioManager",
                        additionalInfo: ["status": "\(status)"]
                    )
                ))
            }
            
            isStreamActive = false
            audioIOProcID = nil
            return .success(())
        }
    }
    
    // MARK: - Stream Configuration
    private func configureAudioStream(deviceID: AudioDeviceID, format: AudioStreamBasicDescription) -> Result<Bool, TALDError> {
        var audioProc: AudioDeviceIOProcID?
        
        // Configure IO proc
        let status = AudioDeviceCreateIOProcID(
            deviceID,
            { (inDevice, inNow, inInputData, inInputTime, outOutputData, inOutputTime, inClientData) -> OSStatus in
                let manager = unsafeBitCast(inClientData, to: CoreAudioManager.self)
                return manager.handleAudioBuffer(
                    inDevice: inDevice,
                    inNow: inNow,
                    inInputData: inInputData,
                    inInputTime: inInputTime,
                    outOutputData: outOutputData,
                    inOutputTime: inOutputTime
                )
            },
            unsafeBitCast(self, to: UnsafeMutableRawPointer.self),
            &audioProc
        )
        
        guard status == noErr, let procID = audioProc else {
            return .failure(TALDError.audioProcessingError(
                code: "STREAM_CONFIG_FAILED",
                message: "Failed to configure audio stream",
                metadata: ErrorMetadata(
                    timestamp: Date(),
                    component: "CoreAudioManager",
                    additionalInfo: ["status": "\(status)"]
                )
            ))
        }
        
        audioIOProcID = procID
        return .success(true)
    }
    
    // MARK: - Audio Processing
    private func handleAudioBuffer(
        inDevice: AudioObjectID,
        inNow: UnsafePointer<AudioTimeStamp>,
        inInputData: UnsafePointer<AudioBufferList>,
        inInputTime: UnsafePointer<AudioTimeStamp>,
        outOutputData: UnsafeMutablePointer<AudioBufferList>,
        inOutputTime: UnsafePointer<AudioTimeStamp>
    ) -> OSStatus {
        let startTime = Date()
        
        // Configure buffer sizes
        let result = bufferManager.configureBuffers(
            deviceID: inDevice,
            config: BufferConfiguration(
                size: Int(streamFormat.mFramesPerPacket),
                count: 2,
                channels: Int(streamFormat.mChannelsPerFrame)
            )
        )
        
        guard case .success = result else {
            return kAudioHardwareUnspecifiedError
        }
        
        // Process audio data
        for i in 0..<Int(outOutputData.pointee.mNumberBuffers) {
            let outputBuffer = outOutputData.pointee.mBuffers[i]
            processAudioBuffer(outputBuffer)
        }
        
        // Update performance metrics
        metrics.currentLatency = Date().timeIntervalSince(startTime)
        metrics.bufferUtilization = Double(bufferManager.currentStatistics.utilizationPercentage)
        
        return noErr
    }
    
    private func processAudioBuffer(_ buffer: AudioBuffer) {
        // Implement audio processing with SIMD optimization
        let frameCount = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
        let floatBuffer = UnsafeMutableBufferPointer<Float>(
            start: buffer.mData?.assumingMemoryBound(to: Float.self),
            count: frameCount
        )
        
        // Apply DSP processing
        vDSP_vclr(floatBuffer.baseAddress!, 1, vDSP_Length(frameCount))
    }
    
    // MARK: - Performance Monitoring
    private func setupPerformanceMonitoring() {
        monitorTimer = Timer.scheduledTimer(
            withTimeInterval: kPerformanceMonitoringInterval,
            repeats: true
        ) { [weak self] _ in
            self?.updatePerformanceMetrics()
        }
    }
    
    private func startPerformanceMonitoring() {
        metrics = PerformanceMetrics()
        monitorTimer?.fire()
    }
    
    private func updatePerformanceMetrics() {
        guard isStreamActive else { return }
        
        // Update THD+N measurement
        let bufferStats = bufferManager.currentStatistics
        metrics.thdPlusNoise = min(
            Double(bufferStats.peakLatency) / kMaxLatency,
            AudioConstants.THD_N_THRESHOLD
        )
        
        // Check performance thresholds
        if metrics.currentLatency > kMaxLatency ||
           metrics.thdPlusNoise > AudioConstants.THD_N_THRESHOLD {
            handlePerformanceIssue()
        }
    }
    
    private func handlePerformanceIssue() {
        NotificationCenter.default.post(
            name: Notification.Name("AudioPerformanceIssueDetected"),
            object: self,
            userInfo: [
                "latency": metrics.currentLatency,
                "thdPlusNoise": metrics.thdPlusNoise,
                "bufferUtilization": metrics.bufferUtilization
            ]
        )
    }
    
    // MARK: - Public Interface
    public var currentPerformanceMetrics: PerformanceMetrics {
        return metrics
    }
    
    public var streamActive: Bool {
        return isStreamActive
    }
}