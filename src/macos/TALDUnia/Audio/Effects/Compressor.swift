//
// Compressor.swift
// TALD UNIA
//
// High-performance dynamic range compressor with SIMD optimization and ESS ES9038PRO DAC integration
// Version: 1.0.0
//

import Foundation // macOS 13.0+
import Accelerate // macOS 13.0+
import simd // macOS 13.0+
import os.log // macOS 13.0+
import CoreAudio // macOS 13.0+

// MARK: - Global Constants

private let kDefaultThreshold: Float = -20.0
private let kDefaultRatio: Float = 4.0
private let kDefaultAttackTime: Float = 0.005
private let kDefaultReleaseTime: Float = 0.050
private let kDefaultKneeWidth: Float = 6.0
private let kDefaultMakeupGain: Float = 0.0
private let kMaxBufferSize: Int = 2048
private let kOptimalSIMDWidth: Int = 16
private let kDACBitDepth: Int = 32

// MARK: - Performance Monitoring

private struct CompressorMetrics {
    var gainReduction: Float = 0.0
    var inputLevel: Float = 0.0
    var outputLevel: Float = 0.0
    var processingLatency: TimeInterval = 0.0
    var thdPlusNoise: Double = 0.0
    var timestamp: Date = Date()
}

// MARK: - Compressor Implementation

@objc
@dynamicMemberLookup
public class Compressor {
    // MARK: - Properties
    
    private let lock = NSLock()
    private let performanceLog = OSLog(subsystem: "com.tald.unia.audio", category: "Compressor")
    
    // Atomic parameters
    private var _threshold = AtomicProperty<Float>(kDefaultThreshold)
    private var _ratio = AtomicProperty<Float>(kDefaultRatio)
    private var _attackTime = AtomicProperty<Float>(kDefaultAttackTime)
    private var _releaseTime = AtomicProperty<Float>(kDefaultReleaseTime)
    private var _kneeWidth = AtomicProperty<Float>(kDefaultKneeWidth)
    private var _makeupGain = AtomicProperty<Float>(kDefaultMakeupGain)
    
    // Processing components
    private let simdProcessor: SIMDProcessor
    private let dspProcessor: DSPProcessor
    private let vectorDSP: VectorDSP
    private var metrics: CompressorMetrics
    private var isProcessing: Bool = false
    
    // Hardware optimization
    private let dacConfig: HardwareConfig
    private let alignedBuffer: UnsafeMutablePointer<Float>
    private var envelopeBuffer: UnsafeMutablePointer<Float>
    
    // MARK: - Initialization
    
    public init(config: HardwareConfig = .ess9038Pro) throws {
        // Initialize hardware configuration
        self.dacConfig = config
        
        // Initialize processing components
        self.simdProcessor = try SIMDProcessor(
            channels: AudioConstants.MAX_CHANNELS,
            vectorSize: kOptimalSIMDWidth,
            config: config
        )
        
        let dspConfig = DSPConfiguration(
            bufferSize: config.bufferSize,
            channels: AudioConstants.MAX_CHANNELS,
            sampleRate: Double(AudioConstants.SAMPLE_RATE),
            isOptimized: true,
            useHardwareAcceleration: true
        )
        self.dspProcessor = try DSPProcessor(config: dspConfig)
        
        self.vectorDSP = VectorDSP(
            size: config.bufferSize,
            enableOptimization: true
        )
        
        // Allocate aligned buffers
        guard let buffer = UnsafeMutablePointer<Float>.allocate(capacity: kMaxBufferSize)
            .alignedPointer(to: Float.self, alignment: kOptimalSIMDWidth) else {
            throw TALDError.audioProcessingError(
                code: "BUFFER_ALLOCATION_FAILED",
                message: "Failed to allocate aligned buffer",
                metadata: ErrorMetadata(
                    timestamp: Date(),
                    component: "Compressor",
                    additionalInfo: ["bufferSize": "\(kMaxBufferSize)"]
                )
            )
        }
        self.alignedBuffer = buffer
        
        guard let envBuffer = UnsafeMutablePointer<Float>.allocate(capacity: kMaxBufferSize)
            .alignedPointer(to: Float.self, alignment: kOptimalSIMDWidth) else {
            throw TALDError.audioProcessingError(
                code: "ENVELOPE_BUFFER_ALLOCATION_FAILED",
                message: "Failed to allocate envelope buffer",
                metadata: ErrorMetadata(
                    timestamp: Date(),
                    component: "Compressor",
                    additionalInfo: ["bufferSize": "\(kMaxBufferSize)"]
                )
            )
        }
        self.envelopeBuffer = envBuffer
        
        // Initialize metrics
        self.metrics = CompressorMetrics()
    }
    
    deinit {
        alignedBuffer.deallocate()
        envelopeBuffer.deallocate()
    }
    
    // MARK: - Audio Processing
    
    public func process(
        _ input: UnsafePointer<Float>,
        _ output: UnsafeMutablePointer<Float>,
        frameCount: Int
    ) -> Result<CompressorMetrics, TALDError> {
        let startTime = Date()
        
        return lock.synchronized {
            // Validate frame count
            guard frameCount > 0 && frameCount <= kMaxBufferSize else {
                return .failure(TALDError.audioProcessingError(
                    code: "INVALID_FRAME_COUNT",
                    message: "Invalid frame count for compression",
                    metadata: ErrorMetadata(
                        timestamp: Date(),
                        component: "Compressor",
                        additionalInfo: ["frameCount": "\(frameCount)"]
                    )
                ))
            }
            
            // Copy input to aligned buffer
            memcpy(alignedBuffer, input, frameCount * MemoryLayout<Float>.stride)
            
            // Calculate input level using SIMD
            var inputLevel: Float = 0.0
            vDSP_maxmgv(alignedBuffer, 1, &inputLevel, vDSP_Length(frameCount))
            
            // Calculate gain reduction
            let gainReduction = calculateGainReduction(
                inputLevel: inputLevel,
                threshold: _threshold.value,
                ratio: _ratio.value,
                kneeWidth: _kneeWidth.value
            )
            
            // Apply envelope following
            applyEnvelope(
                gainReduction: gainReduction,
                attackTime: _attackTime.value,
                releaseTime: _releaseTime.value,
                frameCount: frameCount
            )
            
            // Apply gain reduction using SIMD
            let result = simdProcessor.processVector(
                alignedBuffer,
                output,
                frameCount: frameCount
            )
            
            guard case .success(let simdMetrics) = result else {
                return .failure(TALDError.audioProcessingError(
                    code: "SIMD_PROCESSING_FAILED",
                    message: "SIMD processing failed",
                    metadata: ErrorMetadata(
                        timestamp: Date(),
                        component: "Compressor",
                        additionalInfo: ["frameCount": "\(frameCount)"]
                    )
                ))
            }
            
            // Apply makeup gain
            if _makeupGain.value != 0.0 {
                vectorDSP.applyGain(AudioBuffer(output, frameCount: frameCount), gain: _makeupGain.value)
            }
            
            // Update metrics
            let processingTime = Date().timeIntervalSince(startTime)
            metrics.gainReduction = gainReduction
            metrics.inputLevel = inputLevel
            metrics.processingLatency = processingTime
            metrics.thdPlusNoise = simdMetrics.thdPlusNoise
            metrics.timestamp = Date()
            
            // Validate THD+N requirement
            if metrics.thdPlusNoise > AudioConstants.THD_N_THRESHOLD {
                os_signpost(.event, log: performanceLog, name: "High THD+N",
                           "THD+N exceeded threshold: %.6f%%", metrics.thdPlusNoise * 100)
            }
            
            // Validate processing latency
            if processingTime > kMaxProcessingLatency {
                return .failure(TALDError.audioProcessingError(
                    code: "EXCESSIVE_LATENCY",
                    message: "Processing latency exceeded threshold",
                    metadata: ErrorMetadata(
                        timestamp: Date(),
                        component: "Compressor",
                        additionalInfo: [
                            "latency": "\(processingTime * 1000)ms",
                            "threshold": "\(kMaxProcessingLatency * 1000)ms"
                        ]
                    )
                ))
            }
            
            return .success(metrics)
        }
    }
    
    // MARK: - Parameter Control
    
    public var threshold: Float {
        get { _threshold.value }
        set { _threshold.value = newValue }
    }
    
    public var ratio: Float {
        get { _ratio.value }
        set { _ratio.value = newValue }
    }
    
    public var attackTime: Float {
        get { _attackTime.value }
        set { _attackTime.value = newValue }
    }
    
    public var releaseTime: Float {
        get { _releaseTime.value }
        set { _releaseTime.value = newValue }
    }
    
    public var kneeWidth: Float {
        get { _kneeWidth.value }
        set { _kneeWidth.value = newValue }
    }
    
    public var makeupGain: Float {
        get { _makeupGain.value }
        set { _makeupGain.value = newValue }
    }
    
    // MARK: - Private Helpers
    
    @inline(__always)
    private func calculateGainReduction(
        inputLevel: Float,
        threshold: Float,
        ratio: Float,
        kneeWidth: Float
    ) -> Float {
        let inputDb = 20.0 * log10f(max(inputLevel, Float.leastNormalMagnitude))
        let kneeStart = threshold - (kneeWidth / 2.0)
        let kneeEnd = threshold + (kneeWidth / 2.0)
        
        if inputDb < kneeStart {
            return 0.0
        } else if inputDb > kneeEnd {
            return (inputDb - threshold) * (1.0 - (1.0 / ratio))
        } else {
            let kneePosition = (inputDb - kneeStart) / kneeWidth
            return (inputDb - threshold) * (1.0 - (1.0 / ratio)) * (kneePosition * kneePosition)
        }
    }
    
    @inline(__always)
    private func applyEnvelope(
        gainReduction: Float,
        attackTime: Float,
        releaseTime: Float,
        frameCount: Int
    ) {
        let attackCoeff = exp(-1.0 / (attackTime * Float(AudioConstants.SAMPLE_RATE)))
        let releaseCoeff = exp(-1.0 / (releaseTime * Float(AudioConstants.SAMPLE_RATE)))
        
        var envelope: Float = 0.0
        for i in 0..<frameCount {
            let coeff = gainReduction > envelope ? attackCoeff : releaseCoeff
            envelope = gainReduction + coeff * (envelope - gainReduction)
            envelopeBuffer[i] = envelope
        }
    }
}

// MARK: - Thread Safety

private extension NSLock {
    func synchronized<T>(_ block: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try block()
    }
}

// MARK: - Atomic Property

private class AtomicProperty<T> {
    private let lock = NSLock()
    private var _value: T
    
    init(_ initialValue: T) {
        self._value = initialValue
    }
    
    var value: T {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _value
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            _value = newValue
        }
    }
}