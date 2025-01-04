//
// FFTProcessor.swift
// TALD UNIA Audio System
//
// High-performance Fast Fourier Transform processor implementing real-time spectral analysis
// and frequency-domain processing with SIMD optimization and advanced error handling.
//
// Dependencies:
// - Accelerate (Latest) - High-performance FFT and vector operations
// - simd (Latest) - Low-level SIMD operations

import Accelerate
import simd

// MARK: - Constants

private let kFFTDefaultSize: Int = 2048
private let kFFTOverlapFactor: Int = 4
private let kFFTWindowType: WindowType = .hanning
private let kMaxFFTBins: Int = 1024
private let kSIMDAlignment: Int = 16
private let kMaxLatencyMS: Double = 10.0

// MARK: - Types

public enum WindowType {
    case hanning
    case hamming
    case blackman
    case kaiser
}

public enum FFTError: Error {
    case initializationFailed(String)
    case processingError(String)
    case alignmentError(String)
    case latencyExceeded(Double)
    case memoryError(String)
}

public struct FFTResults {
    public let magnitude: [Float]
    public let phase: [Float]
    public let timestamp: TimeInterval
    public let processingTime: TimeInterval
    public let powerEfficiency: Double
}

// MARK: - FFTProcessor Implementation

@objc
@dynamicMemberLookup
public final class FFTProcessor: NSObject {
    
    // MARK: - Properties
    
    private var fftSetup: vDSP_DFT_Setup?
    private let fftSize: Int
    private let hopSize: Int
    
    private var inputBuffer: UnsafeMutablePointer<Float>?
    private var fftBuffer: UnsafeMutablePointer<DSPComplex>?
    private var windowBuffer: UnsafeMutablePointer<Float>?
    
    private var isInitialized: Bool = false
    private let monitor: PerformanceMonitor
    
    // MARK: - Initialization
    
    public init(fftSize: Int = kFFTDefaultSize,
                hopSize: Int = kFFTDefaultSize / kFFTOverlapFactor,
                config: FFTConfiguration = FFTConfiguration()) throws {
        
        self.fftSize = fftSize
        self.hopSize = hopSize
        self.monitor = PerformanceMonitor()
        
        super.init()
        
        // Validate FFT parameters
        guard fftSize.nonzeroBitCount == 1 && fftSize >= 64 else {
            throw FFTError.initializationFailed("FFT size must be power of 2 and >= 64")
        }
        
        guard Double(fftSize) / Double(config.sampleRate) * 1000.0 <= kMaxLatencyMS else {
            throw FFTError.latencyExceeded(kMaxLatencyMS)
        }
        
        // Initialize FFT setup
        guard let setup = vDSP_DFT_zop_CreateSetup(
            nil,
            vDSP_Length(fftSize),
            vDSP_DFT_FORWARD
        ) else {
            throw FFTError.initializationFailed("Failed to create FFT setup")
        }
        fftSetup = setup
        
        // Allocate buffers with SIMD alignment
        do {
            try allocateBuffers()
            try createWindow(type: kFFTWindowType)
            isInitialized = true
        } catch {
            cleanup()
            throw error
        }
    }
    
    deinit {
        cleanup()
    }
    
    // MARK: - Public Interface
    
    public func processFFT(_ inputBuffer: UnsafeMutablePointer<Float>,
                          _ outputBuffer: UnsafeMutablePointer<Float>,
                          frameCount: Int) throws -> FFTResults {
        
        guard isInitialized else {
            throw FFTError.processingError("FFT processor not initialized")
        }
        
        monitor.startProcessing()
        
        // Verify SIMD alignment
        let inputAlignment = Int(bitPattern: inputBuffer) % kSIMDAlignment
        let outputAlignment = Int(bitPattern: outputBuffer) % kSIMDAlignment
        guard inputAlignment == 0 && outputAlignment == 0 else {
            throw FFTError.alignmentError("Buffer alignment must be \(kSIMDAlignment) bytes")
        }
        
        do {
            // Apply window function
            try applyWindow(inputBuffer, size: frameCount, windowType: kFFTWindowType)
            
            // Perform forward FFT
            vDSP_fft_zrip(
                fftSetup!,
                self.fftBuffer!,
                1,
                vDSP_Length(log2(Double(fftSize))),
                FFTDirection(FFT_FORWARD)
            )
            
            // Convert to polar form
            let results = try convertToPolar(
                self.fftBuffer!,
                magnitudeBuffer: outputBuffer,
                phaseBuffer: outputBuffer.advanced(by: fftSize/2),
                length: fftSize/2
            )
            
            monitor.stopProcessing()
            
            return FFTResults(
                magnitude: Array(UnsafeBufferPointer(start: outputBuffer, count: fftSize/2)),
                phase: Array(UnsafeBufferPointer(start: outputBuffer.advanced(by: fftSize/2), count: fftSize/2)),
                timestamp: CACurrentMediaTime(),
                processingTime: monitor.processingTime,
                powerEfficiency: monitor.powerEfficiency
            )
            
        } catch {
            throw FFTError.processingError("FFT processing failed: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Private Methods
    
    @inline(__always)
    private func applyWindow(_ buffer: UnsafeMutablePointer<Float>,
                            size: Int,
                            windowType: WindowType) throws -> Result<Void, FFTError> {
        guard size <= fftSize else {
            return .failure(.processingError("Buffer size exceeds FFT size"))
        }
        
        // Apply window function using vDSP
        vDSP_vmul(
            buffer,
            1,
            windowBuffer!,
            1,
            buffer,
            1,
            vDSP_Length(size)
        )
        
        return .success(())
    }
    
    @inline(__always)
    private func convertToPolar(_ complexBuffer: UnsafeMutablePointer<DSPComplex>,
                               magnitudeBuffer: UnsafeMutablePointer<Float>,
                               phaseBuffer: UnsafeMutablePointer<Float>,
                               length: Int) throws -> Result<FFTResults, FFTError> {
        
        // Extract magnitude
        vDSP_zvabs(
            complexBuffer,
            1,
            magnitudeBuffer,
            1,
            vDSP_Length(length)
        )
        
        // Extract phase
        vDSP_zvphas(
            complexBuffer,
            1,
            phaseBuffer,
            1,
            vDSP_Length(length)
        )
        
        // Scale magnitude values
        var scale = 1.0/Float(fftSize)
        vDSP_vsmul(
            magnitudeBuffer,
            1,
            &scale,
            magnitudeBuffer,
            1,
            vDSP_Length(length)
        )
        
        return .success(FFTResults(
            magnitude: Array(UnsafeBufferPointer(start: magnitudeBuffer, count: length)),
            phase: Array(UnsafeBufferPointer(start: phaseBuffer, count: length)),
            timestamp: CACurrentMediaTime(),
            processingTime: monitor.processingTime,
            powerEfficiency: monitor.powerEfficiency
        ))
    }
    
    private func allocateBuffers() throws {
        // Allocate input buffer
        inputBuffer = UnsafeMutablePointer<Float>.allocate(
            capacity: fftSize
        )
        inputBuffer?.initialize(repeating: 0, count: fftSize)
        
        // Allocate FFT buffer
        fftBuffer = UnsafeMutablePointer<DSPComplex>.allocate(
            capacity: fftSize/2
        )
        fftBuffer?.initialize(repeating: DSPComplex(), count: fftSize/2)
        
        // Allocate window buffer
        windowBuffer = UnsafeMutablePointer<Float>.allocate(
            capacity: fftSize
        )
        windowBuffer?.initialize(repeating: 0, count: fftSize)
        
        guard inputBuffer != nil && fftBuffer != nil && windowBuffer != nil else {
            throw FFTError.memoryError("Failed to allocate buffers")
        }
    }
    
    private func createWindow(type: WindowType) throws {
        guard let window = windowBuffer else {
            throw FFTError.memoryError("Window buffer not allocated")
        }
        
        switch type {
        case .hanning:
            vDSP_hann_window(window, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))
        case .hamming:
            vDSP_hamm_window(window, vDSP_Length(fftSize), 0)
        case .blackman:
            vDSP_blkman_window(window, vDSP_Length(fftSize), 0)
        case .kaiser:
            vDSP_kaiser_window(window, vDSP_Length(fftSize), 0)
        }
    }
    
    private func cleanup() {
        if let input = inputBuffer {
            input.deallocate()
            inputBuffer = nil
        }
        
        if let fft = fftBuffer {
            fft.deallocate()
            fftBuffer = nil
        }
        
        if let window = windowBuffer {
            window.deallocate()
            windowBuffer = nil
        }
        
        if let setup = fftSetup {
            vDSP_DFT_DestroySetup(setup)
            fftSetup = nil
        }
        
        isInitialized = false
    }
}

// MARK: - Supporting Types

private class PerformanceMonitor {
    private var startTime: TimeInterval = 0
    private(set) var processingTime: TimeInterval = 0
    private(set) var powerEfficiency: Double = 0.9
    
    func startProcessing() {
        startTime = CACurrentMediaTime()
    }
    
    func stopProcessing() {
        processingTime = CACurrentMediaTime() - startTime
        powerEfficiency = min(0.9, 1.0 - processingTime/kMaxLatencyMS)
    }
}

private struct FFTConfiguration {
    let sampleRate: Int = 192000
    let powerOptimization: Bool = true
}