//
// Equalizer.swift
// TALD UNIA Audio System
//
// High-precision parametric equalizer implementation providing premium-quality 
// frequency response shaping with minimal phase distortion and real-time THD+N monitoring.
//
// Dependencies:
// - AVFoundation (Latest) - Core audio functionality
// - Accelerate (Latest) - SIMD-optimized DSP operations

import AVFoundation
import Accelerate

/// High-precision parametric equalizer with real-time quality monitoring
@available(iOS 13.0, *)
public class Equalizer: NSObject {
    
    // MARK: - Constants
    
    private let kMaxBands: Int = 31
    private let kMinFrequency: Double = 20.0
    private let kMaxFrequency: Double = 20000.0
    private let kMaxGainDB: Double = 12.0
    private let kMinGainDB: Double = -12.0
    private let kDefaultQ: Double = 1.4142
    private let kProcessingBufferSize: Int = 512
    private let kMaxProcessingLatencyMs: Double = 10.0
    private let kTargetTHDN: Double = 0.0005
    
    // MARK: - Properties
    
    private let dspProcessor: DSPProcessor
    private let processingQueue: DispatchQueue
    private var bands: [EQBand] = []
    private var isEnabled: Bool = true
    private var masterGain: Double = 1.0
    private var processingMetrics: ProcessingMetrics
    
    // MARK: - Initialization
    
    public override init() throws {
        // Initialize DSP processor with high-quality settings
        self.dspProcessor = try DSPProcessor(
            sampleRate: AudioConstants.sampleRate,
            bufferSize: AudioConstants.bufferSize,
            channelCount: AudioConstants.channelCount
        )
        
        // Initialize processing queue with high priority
        self.processingQueue = DispatchQueue(
            label: "com.taldunia.audio.eq",
            qos: .userInteractive,
            attributes: .concurrent
        )
        
        // Initialize processing metrics
        self.processingMetrics = ProcessingMetrics()
        
        super.init()
        
        // Configure initial EQ bands
        try setupDefaultBands()
    }
    
    // MARK: - Public Interface
    
    /// Process audio buffer through the equalizer chain
    /// - Parameters:
    ///   - inputBuffer: Input audio buffer
    ///   - outputBuffer: Output audio buffer
    ///   - frameCount: Number of frames to process
    /// - Returns: Processing metrics or error
    public func processBuffer(_ inputBuffer: UnsafeMutablePointer<Float>,
                            _ outputBuffer: UnsafeMutablePointer<Float>,
                            frameCount: Int) -> Result<ProcessingMetrics, Error> {
        guard isEnabled else {
            // Pass through if disabled
            memcpy(outputBuffer, inputBuffer, frameCount * MemoryLayout<Float>.size)
            return .success(processingMetrics)
        }
        
        return processingQueue.sync { [weak self] in
            guard let self = self else {
                return .failure(AppError.audioError(
                    reason: "Equalizer deallocated",
                    severity: .error,
                    context: ErrorContext()
                ))
            }
            
            do {
                let startTime = CACurrentMediaTime()
                
                // Process each band
                for band in bands where band.enabled {
                    try band.processEQBand(
                        inputBuffer,
                        frameCount: frameCount,
                        metrics: &processingMetrics
                    ).get()
                }
                
                // Apply master gain
                vDSP_vsmul(
                    inputBuffer,
                    1,
                    &masterGain,
                    outputBuffer,
                    1,
                    vDSP_Length(frameCount)
                )
                
                // Measure THD+N
                let thdn = try dspProcessor.measureTHDN(
                    outputBuffer,
                    frameCount: frameCount
                )
                
                // Update metrics
                processingMetrics.updateWithCurrentCycle(
                    processingTime: CACurrentMediaTime() - startTime,
                    thdnLevel: thdn,
                    latency: currentLatency
                )
                
                // Validate quality metrics
                try validateQualityMetrics()
                
                return .success(processingMetrics)
                
            } catch {
                return .failure(error)
            }
        }
    }
    
    /// Update band parameters with validation
    /// - Parameters:
    ///   - bandIndex: Index of the band to update
    ///   - frequency: Optional new frequency
    ///   - gain: Optional new gain
    ///   - q: Optional new Q factor
    /// - Returns: Success or error
    public func updateBand(at bandIndex: Int,
                         frequency: Double? = nil,
                         gain: Double? = nil,
                         q: Double? = nil) -> Result<Bool, Error> {
        guard bandIndex >= 0 && bandIndex < bands.count else {
            return .failure(AppError.audioError(
                reason: "Invalid band index",
                severity: .error,
                context: ErrorContext()
            ))
        }
        
        return bands[bandIndex].updateParameters(
            frequency: frequency,
            gain: gain,
            q: q
        )
    }
    
    // MARK: - Private Methods
    
    private func setupDefaultBands() throws {
        // Calculate frequencies for 31-band EQ
        let frequencyStep = pow(kMaxFrequency / kMinFrequency, 1.0 / Double(kMaxBands - 1))
        var frequency = kMinFrequency
        
        for _ in 0..<kMaxBands {
            let band = try EQBand(
                frequency: frequency,
                gain: 0.0,
                q: kDefaultQ
            )
            bands.append(band)
            frequency *= frequencyStep
        }
    }
    
    private var currentLatency: TimeInterval {
        return Double(kProcessingBufferSize) / Double(AudioConstants.sampleRate)
    }
    
    private func validateQualityMetrics() throws {
        // Validate THD+N
        guard processingMetrics.thdnLevel <= kTargetTHDN else {
            throw AppError.audioError(
                reason: "THD+N exceeds target level",
                severity: .warning,
                context: ErrorContext(additionalInfo: [
                    "current": processingMetrics.thdnLevel,
                    "target": kTargetTHDN
                ])
            )
        }
        
        // Validate latency
        guard currentLatency <= kMaxProcessingLatencyMs / 1000.0 else {
            throw AppError.audioError(
                reason: "Processing latency exceeds maximum",
                severity: .warning,
                context: ErrorContext(additionalInfo: [
                    "current": currentLatency,
                    "maximum": kMaxProcessingLatencyMs / 1000.0
                ])
            )
        }
    }
}

// MARK: - Supporting Types

private class EQBand {
    private(set) var frequency: Double
    private(set) var gain: Double
    private(set) var q: Double
    private(set) var enabled: Bool = true
    
    private var filterState: UnsafeMutablePointer<Double>
    private let processingLock = NSLock()
    private var isProcessing: Bool = false
    
    init(frequency: Double, gain: Double, q: Double) throws {
        // Validate parameters
        guard (20.0...20000.0).contains(frequency) else {
            throw AppError.audioError(
                reason: "Invalid frequency",
                severity: .error,
                context: ErrorContext()
            )
        }
        
        guard (-12.0...12.0).contains(gain) else {
            throw AppError.audioError(
                reason: "Invalid gain",
                severity: .error,
                context: ErrorContext()
            )
        }
        
        guard q > 0 else {
            throw AppError.audioError(
                reason: "Invalid Q factor",
                severity: .error,
                context: ErrorContext()
            )
        }
        
        self.frequency = frequency
        self.gain = gain
        self.q = q
        
        // Allocate filter state
        self.filterState = UnsafeMutablePointer<Double>.allocate(capacity: 4)
        self.filterState.initialize(repeating: 0.0, count: 4)
    }
    
    deinit {
        filterState.deallocate()
    }
    
    func processEQBand(_ buffer: UnsafeMutablePointer<Float>,
                      frameCount: Int,
                      metrics: inout ProcessingMetrics) -> Result<Bool, Error> {
        processingLock.lock()
        defer { processingLock.unlock() }
        
        guard enabled else { return .success(true) }
        
        do {
            // Calculate filter coefficients
            let coefficients = try calculateFilterCoefficients(
                frequency: frequency,
                gain: gain,
                q: q,
                sampleRate: Double(AudioConstants.sampleRate)
            )
            
            // Apply biquad filter
            vDSP_biquadm(
                buffer,
                1,
                coefficients.0,
                filterState,
                buffer,
                1,
                vDSP_Length(frameCount),
                1
            )
            
            return .success(true)
            
        } catch {
            return .failure(error)
        }
    }
    
    func updateParameters(frequency: Double? = nil,
                        gain: Double? = nil,
                        q: Double? = nil) -> Result<Bool, Error> {
        processingLock.lock()
        defer { processingLock.unlock() }
        
        do {
            // Update frequency if provided
            if let frequency = frequency {
                guard (20.0...20000.0).contains(frequency) else {
                    throw AppError.audioError(
                        reason: "Invalid frequency",
                        severity: .error,
                        context: ErrorContext()
                    )
                }
                self.frequency = frequency
            }
            
            // Update gain if provided
            if let gain = gain {
                guard (-12.0...12.0).contains(gain) else {
                    throw AppError.audioError(
                        reason: "Invalid gain",
                        severity: .error,
                        context: ErrorContext()
                    )
                }
                self.gain = gain
            }
            
            // Update Q if provided
            if let q = q {
                guard q > 0 else {
                    throw AppError.audioError(
                        reason: "Invalid Q factor",
                        severity: .error,
                        context: ErrorContext()
                    )
                }
                self.q = q
            }
            
            return .success(true)
            
        } catch {
            return .failure(error)
        }
    }
}

private struct ProcessingMetrics {
    var processingTime: TimeInterval = 0
    var thdnLevel: Double = 0
    var latency: TimeInterval = 0
    
    mutating func updateWithCurrentCycle(processingTime: TimeInterval,
                                       thdnLevel: Double,
                                       latency: TimeInterval) {
        self.processingTime = processingTime
        self.thdnLevel = thdnLevel
        self.latency = latency
    }
}