//
// MetalAccelerator.swift
// TALD UNIA
//
// High-performance GPU acceleration for AI audio processing using Metal framework
// Version: 1.0.0
//

import Foundation // macOS 13.0+
import Metal // macOS 13.0+
import MetalPerformanceShaders // macOS 13.0+

// MARK: - Global Constants

private let kMaxBufferSize: Int = 8192
private let kDefaultThreadsPerThreadgroup: MTLSize = MTLSizeMake(256, 1, 1)
private let kMetalDeviceQueueLabel: String = "com.tald.unia.metal.queue"
private let kPowerStateUpdateInterval: TimeInterval = 0.1
private let kPerformanceMetricsInterval: TimeInterval = 1.0

// MARK: - Error Types

private enum MetalError: Error {
    case deviceNotFound
    case pipelineCreationFailed
    case bufferAllocationFailed
    case invalidConfiguration
    case processingError
}

// MARK: - Device Capabilities

private struct DeviceCapabilities {
    let maxBufferLength: Int
    let maxThreadgroupSize: MTLSize
    let supportsSIMD: Bool
    let supportsNonuniformThreadgroups: Bool
    let powerStates: [MTLPowerState]
}

// MARK: - Performance Metrics

private struct PerformanceMetrics {
    var processingLatency: TimeInterval = 0
    var gpuUtilization: Double = 0
    var powerConsumption: Double = 0
    var thdPlusNoise: Double = 0
    var lastUpdateTime: Date = Date()
    
    mutating func update(latency: TimeInterval, utilization: Double) {
        processingLatency = latency
        gpuUtilization = utilization
        lastUpdateTime = Date()
    }
}

// MARK: - Metal Accelerator Implementation

@available(macOS 13.0, *)
public class MetalAccelerator {
    // MARK: - Properties
    
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let featureExtractionPipeline: MTLComputePipelineState
    private let audioProcessingPipeline: MTLComputePipelineState
    private let metalQueue: DispatchQueue
    private let powerManager: PowerStateManager
    private let performanceMonitor: PerformanceMonitor
    private let bufferManager: BufferManager
    private var metrics = PerformanceMetrics()
    private let lock = NSLock()
    
    // MARK: - Initialization
    
    public init(preferredGPU: Bool = true, config: ProcessingConfiguration) throws {
        // Select optimal Metal device
        guard let selectedDevice = selectOptimalDevice(preferGPU: preferredGPU) else {
            throw MetalError.deviceNotFound
        }
        self.device = selectedDevice
        
        // Validate device capabilities
        let capabilities = try validateMetalDevice(device: selectedDevice, powerConfig: config.powerConfig)
        
        // Create command queue with optimization flags
        guard let queue = device.makeCommandQueue(descriptor: {
            let descriptor = MTLCommandQueueDescriptor()
            descriptor.maxCommandBufferCount = config.maxBufferCount
            return descriptor
        }()) else {
            throw MetalError.deviceNotFound
        }
        self.commandQueue = queue
        
        // Initialize power state manager
        self.powerManager = PowerStateManager(device: device, capabilities: capabilities)
        
        // Create compute pipelines
        self.featureExtractionPipeline = try createFeatureExtractionPipeline(device: device)
        self.audioProcessingPipeline = try createAudioProcessingPipeline(device: device)
        
        // Initialize buffer manager
        self.bufferManager = BufferManager(device: device, maxBufferSize: kMaxBufferSize)
        
        // Configure performance monitoring
        self.performanceMonitor = PerformanceMonitor(updateInterval: kPerformanceMetricsInterval)
        
        // Initialize processing queue
        self.metalQueue = DispatchQueue(label: kMetalDeviceQueueLabel, qos: .userInteractive)
    }
    
    // MARK: - Public Interface
    
    public func processBuffer(_ inputBuffer: AudioBuffer, config: ProcessingConfiguration) -> Result<ProcessedAudio, ProcessingError> {
        let startTime = Date()
        
        return lock.synchronized {
            // Validate input buffer
            guard inputBuffer.availableFrames > 0 else {
                return .failure(ProcessingError.invalidInput("Empty input buffer"))
            }
            
            // Optimize GPU power state for workload
            powerManager.optimizePowerState(for: inputBuffer.availableFrames)
            
            // Prepare Metal buffers
            guard let commandBuffer = commandQueue.makeCommandBuffer(),
                  let inputMetalBuffer = bufferManager.createBuffer(from: inputBuffer),
                  let outputMetalBuffer = bufferManager.createBuffer(size: inputBuffer.availableFrames) else {
                return .failure(ProcessingError.resourceAllocation("Failed to allocate Metal buffers"))
            }
            
            // Configure compute command encoder
            guard let computeEncoder = commandBuffer.makeComputeCommandEncoder() else {
                return .failure(ProcessingError.encoderCreation("Failed to create compute encoder"))
            }
            
            // Set up audio processing pipeline
            computeEncoder.setComputePipelineState(audioProcessingPipeline)
            computeEncoder.setBuffer(inputMetalBuffer, offset: 0, index: 0)
            computeEncoder.setBuffer(outputMetalBuffer, offset: 0, index: 1)
            
            // Calculate optimal threadgroup size
            let threadgroupSize = MTLSizeMake(
                audioProcessingPipeline.threadExecutionWidth,
                1,
                1
            )
            let threadgroups = MTLSizeMake(
                (inputBuffer.availableFrames + threadgroupSize.width - 1) / threadgroupSize.width,
                1,
                1
            )
            
            // Dispatch compute work
            computeEncoder.dispatchThreadgroups(threadgroups, threadsPerThreadgroup: threadgroupSize)
            computeEncoder.endEncoding()
            
            // Commit command buffer
            commandBuffer.commit()
            commandBuffer.waitUntil(Date().addingTimeInterval(kMaxProcessingLatency))
            
            // Update performance metrics
            let processingTime = Date().timeIntervalSince(startTime)
            metrics.update(
                latency: processingTime,
                utilization: powerManager.currentUtilization
            )
            
            // Validate processing latency
            if processingTime > kMaxProcessingLatency {
                return .failure(ProcessingError.excessiveLatency("Processing latency exceeded threshold"))
            }
            
            // Create processed audio result
            let processedAudio = ProcessedAudio(
                buffer: outputMetalBuffer,
                frameCount: inputBuffer.availableFrames,
                metrics: metrics
            )
            
            return .success(processedAudio)
        }
    }
    
    // MARK: - Private Helpers
    
    private func selectOptimalDevice(preferGPU: Bool) -> MTLDevice? {
        let devices = MTLCopyAllDevices()
        
        if preferGPU {
            // Select discrete GPU if available
            return devices.first { $0.isLowPower == false }
        }
        
        // Fall back to default system device
        return MTLCreateSystemDefaultDevice()
    }
    
    private func createFeatureExtractionPipeline(device: MTLDevice) throws -> MTLComputePipelineState {
        guard let library = device.makeDefaultLibrary(),
              let function = library.makeFunction(name: "extractAudioFeatures") else {
            throw MetalError.pipelineCreationFailed
        }
        
        return try device.makeComputePipelineState(function: function)
    }
    
    private func createAudioProcessingPipeline(device: MTLDevice) throws -> MTLComputePipelineState {
        guard let library = device.makeDefaultLibrary(),
              let function = library.makeFunction(name: "processAudioBuffer") else {
            throw MetalError.pipelineCreationFailed
        }
        
        return try device.makeComputePipelineState(function: function)
    }
}

// MARK: - Power State Management

private class PowerStateManager {
    private let device: MTLDevice
    private let capabilities: DeviceCapabilities
    private var currentState: MTLPowerState?
    private let updateTimer: DispatchSourceTimer
    
    var currentUtilization: Double {
        return device.sampleBufferAttachments?.gpuUtilization ?? 0
    }
    
    init(device: MTLDevice, capabilities: DeviceCapabilities) {
        self.device = device
        self.capabilities = capabilities
        
        // Configure power state update timer
        self.updateTimer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        updateTimer.schedule(deadline: .now(), repeating: kPowerStateUpdateInterval)
        updateTimer.setEventHandler { [weak self] in
            self?.updatePowerState()
        }
        updateTimer.resume()
    }
    
    func optimizePowerState(for frameCount: Int) {
        let requiredPerformance = Double(frameCount) / Double(kMaxBufferSize)
        let optimalState = capabilities.powerStates.first {
            $0.powerUtilization >= requiredPerformance
        }
        
        if let state = optimalState, state != currentState {
            device.setPowerState(state)
            currentState = state
        }
    }
    
    private func updatePowerState() {
        // Monitor and adjust power state based on utilization
        let currentUtilization = self.currentUtilization
        optimizePowerState(for: Int(currentUtilization * Double(kMaxBufferSize)))
    }
}

// MARK: - Buffer Management

private class BufferManager {
    private let device: MTLDevice
    private let maxBufferSize: Int
    private var bufferCache: [Int: MTLBuffer] = [:]
    
    init(device: MTLDevice, maxBufferSize: Int) {
        self.device = device
        self.maxBufferSize = maxBufferSize
    }
    
    func createBuffer(from audioBuffer: AudioBuffer) -> MTLBuffer? {
        let size = audioBuffer.availableFrames * MemoryLayout<Float>.stride
        
        if let cachedBuffer = bufferCache[size] {
            return cachedBuffer
        }
        
        guard let buffer = device.makeBuffer(length: size, options: .storageModeShared) else {
            return nil
        }
        
        bufferCache[size] = buffer
        return buffer
    }
    
    func createBuffer(size: Int) -> MTLBuffer? {
        let byteSize = size * MemoryLayout<Float>.stride
        
        if let cachedBuffer = bufferCache[byteSize] {
            return cachedBuffer
        }
        
        guard let buffer = device.makeBuffer(length: byteSize, options: .storageModeShared) else {
            return nil
        }
        
        bufferCache[byteSize] = buffer
        return buffer
    }
}

// MARK: - Performance Monitoring

private class PerformanceMonitor {
    private let updateInterval: TimeInterval
    private let updateTimer: DispatchSourceTimer
    private var metrics = PerformanceMetrics()
    
    init(updateInterval: TimeInterval) {
        self.updateInterval = updateInterval
        
        self.updateTimer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        updateTimer.schedule(deadline: .now(), repeating: updateInterval)
        updateTimer.setEventHandler { [weak self] in
            self?.updateMetrics()
        }
        updateTimer.resume()
    }
    
    private func updateMetrics() {
        // Collect and update performance metrics
        metrics.lastUpdateTime = Date()
    }
}

// MARK: - Lock Extension

private extension NSLock {
    func synchronized<T>(_ block: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try block()
    }
}