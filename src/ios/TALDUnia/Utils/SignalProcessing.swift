//
// SignalProcessing.swift
// TALD UNIA Audio System
//
// Advanced digital signal processing utilities with AI enhancement capabilities,
// real-time performance monitoring, and optimized SIMD operations.
//
// Dependencies:
// - Accelerate (Latest) - High-performance signal processing operations
// - simd (Latest) - SIMD operations for optimized processing
// - os.signpost (Latest) - Performance monitoring and profiling

import Accelerate
import simd
import os.signpost

// MARK: - Constants

private let kDefaultBufferSize: Int = 2048
private let kMaxHarmonics: Int = 10
private let kAnalysisOverlap: Float = 0.75
private let kSmoothingFactor: Float = 0.1
private let kMaxLatencyMs: Float = 10.0
private let kMinProcessingPower: Float = 0.1
private let kAIModelVersion: String = "1.0"

// MARK: - Error Types

enum ProcessingError: Error {
    case invalidBufferSize(String)
    case processingFailed(String)
    case latencyExceeded(String)
    case aiModelError(String)
}

// MARK: - Supporting Types

struct ProcessingOptions {
    var enableAI: Bool = true
    var latencyOptimized: Bool = true
    var powerOptimized: Bool = true
    var monitorPerformance: Bool = true
}

struct ProcessingResults {
    var peakLevel: Float = 0.0
    var rmsLevel: Float = 0.0
    var thd: Float = 0.0
    var latencyMs: Float = 0.0
    var powerEfficiency: Float = 0.0
    var aiEnhancementGain: Float = 0.0
}

// MARK: - SignalProcessor Implementation

@objc
@dynamicMemberLookup
public final class SignalProcessor: NSObject {
    
    // MARK: - Properties
    
    private let fftProcessor: FFTProcessor
    private let bufferSize: Int
    private let sampleRate: Float
    private var isProcessing: Bool = false
    private let monitor: PerformanceMonitor
    private let aiProcessor: AIProcessor
    private var stats: ProcessingStats
    
    // MARK: - Initialization
    
    public init(bufferSize: Int = kDefaultBufferSize,
                sampleRate: Float = 192000,
                aiConfig: AIConfiguration) throws {
        
        // Validate initialization parameters
        guard bufferSize >= 64 && bufferSize.nonzeroBitCount == 1 else {
            throw ProcessingError.invalidBufferSize("Buffer size must be power of 2 and >= 64")
        }
        
        guard Float(bufferSize) / sampleRate * 1000.0 <= kMaxLatencyMs else {
            throw ProcessingError.latencyExceeded("Buffer size exceeds maximum latency")
        }
        
        self.bufferSize = bufferSize
        self.sampleRate = sampleRate
        
        // Initialize processors
        self.fftProcessor = try FFTProcessor(fftSize: bufferSize)
        self.aiProcessor = try AIProcessor(configuration: aiConfig)
        self.monitor = PerformanceMonitor()
        self.stats = ProcessingStats()
        
        super.init()
        
        // Configure thread priority for real-time processing
        setThreadPriority()
    }
    
    // MARK: - Public Interface
    
    @discardableResult
    public func processBuffer(_ buffer: UnsafeMutablePointer<Float>,
                            length: Int,
                            options: ProcessingOptions = ProcessingOptions()) throws -> ProcessingResults {
        
        guard !isProcessing else {
            throw ProcessingError.processingFailed("Processing already in progress")
        }
        
        isProcessing = true
        defer { isProcessing = false }
        
        // Start performance monitoring
        monitor.startProcessing()
        
        do {
            // Apply gain with overload protection
            try applyGain(buffer, length: length, gainDB: 0.0)
            
            // Perform FFT analysis
            let spectrum = try fftProcessor.processFFT(buffer, outputBuffer: buffer, frameCount: length)
            
            // Apply AI enhancement if enabled
            var aiGain: Float = 0.0
            if options.enableAI {
                aiGain = try aiProcessor.enhance(buffer, length: length, spectrum: spectrum)
            }
            
            // Calculate audio metrics
            let peakLevel = AudioMath.linearToDecibels(calculatePeakLevel(buffer, length: length))
            let rmsLevel = AudioMath.linearToDecibels(calculateRMS(buffer, length: length))
            let thd = calculateTHD(buffer, length: length)
            
            // Update processing statistics
            monitor.stopProcessing()
            updateStats(peakLevel: peakLevel, rmsLevel: rmsLevel, thd: thd)
            
            return ProcessingResults(
                peakLevel: peakLevel,
                rmsLevel: rmsLevel,
                thd: thd,
                latencyMs: monitor.processingTime * 1000,
                powerEfficiency: monitor.powerEfficiency,
                aiEnhancementGain: aiGain
            )
            
        } catch {
            throw ProcessingError.processingFailed("Processing failed: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Private Methods
    
    @inline(__always)
    private func applyGain(_ buffer: UnsafeMutablePointer<Float>,
                          length: Int,
                          gainDB: Float) throws -> Result<Void, ProcessingError> {
        
        guard length <= bufferSize else {
            return .failure(.invalidBufferSize("Buffer exceeds maximum size"))
        }
        
        // Convert gain to linear scale
        let gainLinear = AudioMath.decibelsToLinear(gainDB)
        
        // Apply gain with SIMD optimization
        var scale = gainLinear
        vDSP_vsmul(buffer, 1, &scale, buffer, 1, vDSP_Length(length))
        
        // Apply soft clipping for overload protection
        var one: Float = 1.0
        vDSP_vclip(buffer, 1, &scale, &one, buffer, 1, vDSP_Length(length))
        
        return .success(())
    }
    
    private func calculatePeakLevel(_ buffer: UnsafeMutablePointer<Float>, length: Int) -> Float {
        var peak: Float = 0.0
        vDSP_maxmgv(buffer, 1, &peak, vDSP_Length(length))
        return peak
    }
    
    private func calculateRMS(_ buffer: UnsafeMutablePointer<Float>, length: Int) -> Float {
        var rms: Float = 0.0
        vDSP_rmsqv(buffer, 1, &rms, vDSP_Length(length))
        return rms
    }
    
    private func calculateTHD(_ buffer: UnsafeMutablePointer<Float>, length: Int) -> Float {
        // Calculate THD using FFT analysis
        let spectrum = try? fftProcessor.getSpectrum()
        guard let harmonics = spectrum else { return 0.0 }
        
        var totalHarmonicPower: Float = 0.0
        var fundamentalPower: Float = harmonics[0]
        
        // Sum power of harmonics
        for i in 1..<min(kMaxHarmonics, harmonics.count) {
            totalHarmonicPower += harmonics[i]
        }
        
        // Calculate THD percentage
        return fundamentalPower > 0 ? (totalHarmonicPower / fundamentalPower) * 100.0 : 0.0
    }
    
    private func updateStats(peakLevel: Float, rmsLevel: Float, thd: Float) {
        stats.updateWithCurrentCycle(
            peakLevel: peakLevel,
            rmsLevel: rmsLevel,
            thd: thd,
            processingTime: monitor.processingTime,
            powerEfficiency: monitor.powerEfficiency
        )
    }
    
    private func setThreadPriority() {
        pthread_set_qos_class_self_np(QOS_CLASS_USER_INTERACTIVE, 0)
    }
}

// MARK: - Supporting Classes

private class PerformanceMonitor {
    private var startTime: TimeInterval = 0
    private(set) var processingTime: TimeInterval = 0
    private(set) var powerEfficiency: Float = 0.9
    
    func startProcessing() {
        startTime = CACurrentMediaTime()
    }
    
    func stopProcessing() {
        processingTime = CACurrentMediaTime() - startTime
        powerEfficiency = min(0.9, Float(1.0 - processingTime/Double(kMaxLatencyMs)))
    }
}

private struct ProcessingStats {
    var peakLevel: Float = 0.0
    var rmsLevel: Float = 0.0
    var thd: Float = 0.0
    var processingTime: TimeInterval = 0
    var powerEfficiency: Float = 0.0
    
    mutating func updateWithCurrentCycle(peakLevel: Float,
                                       rmsLevel: Float,
                                       thd: Float,
                                       processingTime: TimeInterval,
                                       powerEfficiency: Float) {
        self.peakLevel = peakLevel
        self.rmsLevel = rmsLevel
        self.thd = thd
        self.processingTime = processingTime
        self.powerEfficiency = powerEfficiency
    }
}