//
// VectorDSP.swift
// TALD UNIA
//
// High-performance vector-based DSP operations implementation
// Version: 1.0.0
//

import Foundation // macOS 13.0+
import Accelerate // macOS 13.0+
import simd // macOS 13.0+

// MARK: - Global Constants

private let kVectorAlignment: Int = 16
private let kMaxVectorSize: Int = 256
private let kDefaultVectorSize: Int = 32
private let kMinProcessingLatency: TimeInterval = 0.001
private let kMaxProcessingLatency: TimeInterval = 0.010

// MARK: - Performance Monitoring

private struct PerformanceMonitor {
    var averageProcessingTime: Double = 0.0
    var peakProcessingTime: Double = 0.0
    var operationsCount: Int = 0
    var lastUpdateTime: Date = Date()
    
    mutating func updateMetrics(processingTime: TimeInterval) {
        averageProcessingTime = (averageProcessingTime * Double(operationsCount) + processingTime) / Double(operationsCount + 1)
        peakProcessingTime = max(peakProcessingTime, processingTime)
        operationsCount += 1
    }
}

// MARK: - Thread Safety

private class ThreadSafetyGuard {
    private let lock = NSLock()
    
    func performThreadSafe<T>(_ operation: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try operation()
    }
}

// MARK: - Vector DSP Implementation

@objc
@objcMembers
public class VectorDSP {
    // MARK: - Properties
    
    private let processingQueue: DispatchQueue
    private let vectorSize: Int
    private let isOptimized: Bool
    private let workBuffer: UnsafeMutablePointer<Float>
    private var monitor: PerformanceMonitor
    private let safetyGuard: ThreadSafetyGuard
    
    // MARK: - Initialization
    
    public init(size: Int = kDefaultVectorSize, enableOptimization: Bool = true) {
        guard size > 0 && size <= kMaxVectorSize else {
            fatalError("Invalid vector size: \(size). Must be between 1 and \(kMaxVectorSize)")
        }
        
        self.vectorSize = size
        self.isOptimized = enableOptimization
        self.processingQueue = DispatchQueue(label: "com.tald.unia.vectordsp", qos: .userInteractive)
        self.monitor = PerformanceMonitor()
        self.safetyGuard = ThreadSafetyGuard()
        
        // Allocate aligned work buffer
        let alignment = kVectorAlignment
        guard let buffer = UnsafeMutablePointer<Float>.allocate(capacity: size + alignment)
            .alignedPointer(to: Float.self, alignment: alignment) else {
            fatalError("Failed to allocate aligned work buffer")
        }
        self.workBuffer = buffer
        
        // Initialize work buffer
        workBuffer.initialize(repeating: 0.0, count: size)
    }
    
    deinit {
        workBuffer.deallocate()
    }
    
    // MARK: - Public Interface
    
    public func processBuffer(_ inputBuffer: AudioBuffer) -> Result<AudioBuffer, TALDError> {
        let startTime = Date()
        
        return safetyGuard.performThreadSafe {
            // Validate input buffer
            guard inputBuffer.availableFrames > 0 else {
                return .failure(TALDError.audioProcessingError(
                    code: "EMPTY_BUFFER",
                    message: "Input buffer is empty",
                    metadata: ErrorMetadata(
                        timestamp: Date(),
                        component: "VectorDSP",
                        additionalInfo: ["vectorSize": "\(vectorSize)"]
                    )
                ))
            }
            
            // Process buffer in vector-sized chunks
            let frameCount = inputBuffer.availableFrames
            var processedFrames = 0
            
            while processedFrames < frameCount {
                let chunkSize = min(vectorSize, frameCount - processedFrames)
                
                // Read chunk from input buffer
                guard case .success = inputBuffer.read(workBuffer, frameCount: chunkSize) else {
                    return .failure(TALDError.audioProcessingError(
                        code: "BUFFER_READ_ERROR",
                        message: "Failed to read from input buffer",
                        metadata: ErrorMetadata(
                            timestamp: Date(),
                            component: "VectorDSP",
                            additionalInfo: [
                                "processedFrames": "\(processedFrames)",
                                "frameCount": "\(frameCount)"
                            ]
                        )
                    ))
                }
                
                // Apply vector operations
                if isOptimized {
                    vDSP_vclr(workBuffer, 1, vDSP_Length(chunkSize))
                    vDSP_vneg(workBuffer, 1, workBuffer, 1, vDSP_Length(chunkSize))
                    vDSP_vabs(workBuffer, 1, workBuffer, 1, vDSP_Length(chunkSize))
                }
                
                // Write processed chunk back to buffer
                guard case .success = inputBuffer.write(workBuffer, frameCount: chunkSize) else {
                    return .failure(TALDError.audioProcessingError(
                        code: "BUFFER_WRITE_ERROR",
                        message: "Failed to write to input buffer",
                        metadata: ErrorMetadata(
                            timestamp: Date(),
                            component: "VectorDSP",
                            additionalInfo: [
                                "processedFrames": "\(processedFrames)",
                                "frameCount": "\(frameCount)"
                            ]
                        )
                    ))
                }
                
                processedFrames += chunkSize
            }
            
            // Update performance metrics
            let processingTime = Date().timeIntervalSince(startTime)
            monitor.updateMetrics(processingTime: processingTime)
            
            // Validate processing latency
            if processingTime > kMaxProcessingLatency {
                return .failure(TALDError.audioProcessingError(
                    code: "EXCESSIVE_LATENCY",
                    message: "Processing latency exceeded threshold",
                    metadata: ErrorMetadata(
                        timestamp: Date(),
                        component: "VectorDSP",
                        additionalInfo: [
                            "processingTime": "\(processingTime)",
                            "threshold": "\(kMaxProcessingLatency)"
                        ]
                    )
                ))
            }
            
            return .success(inputBuffer)
        }
    }
    
    @discardableResult
    public func applyGain(_ buffer: AudioBuffer, gain: Float) -> Result<Void, TALDError> {
        return safetyGuard.performThreadSafe {
            // Validate gain value
            guard gain >= 0.0 && gain <= 1.0 else {
                return .failure(TALDError.audioProcessingError(
                    code: "INVALID_GAIN",
                    message: "Gain value out of range",
                    metadata: ErrorMetadata(
                        timestamp: Date(),
                        component: "VectorDSP",
                        additionalInfo: ["gain": "\(gain)"]
                    )
                ))
            }
            
            let startTime = Date()
            
            // Apply gain using vector multiplication
            let frameCount = buffer.availableFrames
            var processedFrames = 0
            
            while processedFrames < frameCount {
                let chunkSize = min(vectorSize, frameCount - processedFrames)
                
                // Read chunk
                guard case .success = buffer.read(workBuffer, frameCount: chunkSize) else {
                    return .failure(TALDError.audioProcessingError(
                        code: "BUFFER_READ_ERROR",
                        message: "Failed to read from buffer",
                        metadata: ErrorMetadata(
                            timestamp: Date(),
                            component: "VectorDSP",
                            additionalInfo: ["frameCount": "\(frameCount)"]
                        )
                    ))
                }
                
                // Apply gain
                vDSP_vsmul(workBuffer, 1, &gain, workBuffer, 1, vDSP_Length(chunkSize))
                
                // Write processed chunk
                guard case .success = buffer.write(workBuffer, frameCount: chunkSize) else {
                    return .failure(TALDError.audioProcessingError(
                        code: "BUFFER_WRITE_ERROR",
                        message: "Failed to write to buffer",
                        metadata: ErrorMetadata(
                            timestamp: Date(),
                            component: "VectorDSP",
                            additionalInfo: ["frameCount": "\(frameCount)"]
                        )
                    ))
                }
                
                processedFrames += chunkSize
            }
            
            // Update performance metrics
            let processingTime = Date().timeIntervalSince(startTime)
            monitor.updateMetrics(processingTime: processingTime)
            
            return .success(())
        }
    }
}

// MARK: - Vector Operations

@inline(__always)
@discardableResult
public func vectorizedMultiply(_ inputA: UnsafePointer<Float>, _ inputB: UnsafePointer<Float>,
                              _ output: UnsafeMutablePointer<Float>, _ length: Int) -> Bool {
    guard length > 0 else { return false }
    vDSP_vmul(inputA, 1, inputB, 1, output, 1, vDSP_Length(length))
    return true
}

@inline(__always)
@discardableResult
public func vectorizedAdd(_ inputA: UnsafePointer<Float>, _ inputB: UnsafePointer<Float>,
                         _ output: UnsafeMutablePointer<Float>, _ length: Int) -> Bool {
    guard length > 0 else { return false }
    vDSP_vadd(inputA, 1, inputB, 1, output, 1, vDSP_Length(length))
    return true
}