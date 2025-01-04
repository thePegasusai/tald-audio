//
// DSPProcessorTests.swift
// TALD UNIA Audio System
//
// Comprehensive test suite for validating DSP processor components including
// audio quality verification, latency measurements, and power efficiency testing.
//
// Dependencies:
// - XCTest (Latest) - iOS unit testing framework
// - Accelerate (Latest) - High-performance DSP operations

import XCTest
import Accelerate
@testable import TALDUnia

final class DSPProcessorTests: XCTestCase {
    
    // MARK: - Constants
    
    private let kTestBufferSize: Int = 2048
    private let kTestSampleRate: Int = 192000
    private let kTestChannelCount: Int = 2
    private let kTestFFTSize: Int = 1024
    private let kLatencyThreshold: Double = 0.010 // 10ms
    private let kTHDThreshold: Double = 0.0005 // 0.05%
    private let kPowerEfficiencyThreshold: Double = 0.90 // 90%
    
    // MARK: - Properties
    
    private var dspProcessor: DSPProcessor!
    private var simdProcessor: SIMDProcessor!
    private var fftProcessor: FFTProcessor!
    private var testBuffer: UnsafeMutablePointer<Float>!
    private var outputBuffer: UnsafeMutablePointer<Float>!
    
    // MARK: - Setup/Teardown
    
    override func setUp() {
        super.setUp()
        
        // Initialize processors
        do {
            dspProcessor = try DSPProcessor(
                sampleRate: kTestSampleRate,
                bufferSize: kTestBufferSize,
                channelCount: kTestChannelCount
            )
            
            let simdConfig = SIMDConfiguration(
                vectorSize: 4,
                alignment: 16,
                maxFrames: kTestBufferSize,
                optimizationLevel: 3,
                enablePowerOptimization: true
            )
            simdProcessor = SIMDProcessor(config: simdConfig)
            
            fftProcessor = try FFTProcessor(
                fftSize: kTestFFTSize,
                hopSize: kTestFFTSize / 4
            )
            
            // Allocate test buffers
            testBuffer = UnsafeMutablePointer<Float>.allocate(capacity: kTestBufferSize)
            outputBuffer = UnsafeMutablePointer<Float>.allocate(capacity: kTestBufferSize)
            
            testBuffer.initialize(repeating: 0, count: kTestBufferSize)
            outputBuffer.initialize(repeating: 0, count: kTestBufferSize)
            
        } catch {
            XCTFail("Failed to initialize processors: \(error)")
        }
    }
    
    override func tearDown() {
        testBuffer.deallocate()
        outputBuffer.deallocate()
        super.tearDown()
    }
    
    // MARK: - Test Cases
    
    func testAudioQuality() throws {
        // Generate test signals
        let frequencies = [1000.0, 4000.0, 8000.0, 16000.0]
        var totalTHD: Double = 0.0
        
        for frequency in frequencies {
            // Generate sine wave test signal
            generateTestSignal(
                buffer: testBuffer,
                length: kTestBufferSize,
                frequency: frequency,
                sampleRate: Double(kTestSampleRate)
            )
            
            // Process through DSP chain
            try dspProcessor.processBuffer(
                testBuffer,
                outputBuffer,
                frameCount: kTestBufferSize
            )
            
            // Measure THD+N
            let thd = try measureTHD(
                inputBuffer: testBuffer,
                outputBuffer: outputBuffer,
                length: kTestBufferSize,
                fundamentalFreq: frequency
            )
            
            totalTHD += thd
            XCTAssertLessThan(thd, kTHDThreshold, "THD+N exceeds threshold at \(frequency)Hz")
        }
        
        let averageTHD = totalTHD / Double(frequencies.count)
        XCTAssertLessThan(averageTHD, kTHDThreshold, "Average THD+N exceeds threshold")
    }
    
    func testProcessingLatency() throws {
        let startTime = CACurrentMediaTime()
        
        // Generate full-scale test signal
        generateTestSignal(
            buffer: testBuffer,
            length: kTestBufferSize,
            frequency: 1000.0,
            sampleRate: Double(kTestSampleRate)
        )
        
        // Process multiple buffers to get average latency
        let iterations = 100
        var totalLatency: Double = 0.0
        
        for _ in 0..<iterations {
            let processingStart = CACurrentMediaTime()
            
            try dspProcessor.processBuffer(
                testBuffer,
                outputBuffer,
                frameCount: kTestBufferSize
            )
            
            let processingEnd = CACurrentMediaTime()
            totalLatency += processingEnd - processingStart
        }
        
        let averageLatency = totalLatency / Double(iterations)
        XCTAssertLessThan(averageLatency, kLatencyThreshold, "Processing latency exceeds threshold")
    }
    
    func testPowerEfficiency() throws {
        // Configure SIMD processing options
        let options = ProcessingOptions(
            useVectorization: true,
            monitorPerformance: true,
            powerOptimized: true
        )
        
        // Generate test signal
        generateTestSignal(
            buffer: testBuffer,
            length: kTestBufferSize,
            frequency: 1000.0,
            sampleRate: Double(kTestSampleRate)
        )
        
        // Process with SIMD optimization
        let result = simdProcessor.processVectorized(
            testBuffer,
            outputBuffer,
            frameCount: kTestBufferSize,
            options: options
        )
        
        switch result {
        case .success(let metrics):
            XCTAssertGreaterThan(
                metrics.powerEfficiency,
                kPowerEfficiencyThreshold,
                "Power efficiency below threshold"
            )
            
            // Verify SIMD optimization metrics
            XCTAssertGreaterThan(metrics.vectorizedOperations, 0)
            XCTAssertLessThan(metrics.processingTimeMs, kLatencyThreshold * 1000)
            
        case .failure(let error):
            XCTFail("SIMD processing failed: \(error)")
        }
    }
    
    func testFFTAccuracy() throws {
        // Generate test signal with known frequency components
        let testFrequencies = [1000.0, 4000.0, 8000.0]
        generateMultitoneSignal(
            buffer: testBuffer,
            length: kTestFFTSize,
            frequencies: testFrequencies,
            sampleRate: Double(kTestSampleRate)
        )
        
        // Perform FFT analysis
        let fftResults = try fftProcessor.processFFT(
            testBuffer,
            outputBuffer,
            frameCount: kTestFFTSize
        )
        
        // Verify frequency peaks
        let frequencyResolution = Double(kTestSampleRate) / Double(kTestFFTSize)
        
        for frequency in testFrequencies {
            let binIndex = Int(frequency / frequencyResolution)
            let magnitude = fftResults.magnitude[binIndex]
            
            // Check for significant magnitude at expected frequencies
            XCTAssertGreaterThan(
                magnitude,
                0.1,
                "Missing frequency component at \(frequency)Hz"
            )
        }
        
        // Verify processing metrics
        XCTAssertLessThan(
            fftResults.processingTime,
            kLatencyThreshold,
            "FFT processing time exceeds threshold"
        )
        XCTAssertGreaterThan(
            fftResults.powerEfficiency,
            kPowerEfficiencyThreshold,
            "FFT power efficiency below threshold"
        )
    }
    
    // MARK: - Helper Methods
    
    private func generateTestSignal(
        buffer: UnsafeMutablePointer<Float>,
        length: Int,
        frequency: Double,
        sampleRate: Double
    ) {
        var phase: Double = 0.0
        let phaseIncrement = 2.0 * Double.pi * frequency / sampleRate
        
        for i in 0..<length {
            buffer[i] = Float(sin(phase))
            phase += phaseIncrement
            
            if phase >= 2.0 * Double.pi {
                phase -= 2.0 * Double.pi
            }
        }
    }
    
    private func generateMultitoneSignal(
        buffer: UnsafeMutablePointer<Float>,
        length: Int,
        frequencies: [Double],
        sampleRate: Double
    ) {
        // Clear buffer
        memset(buffer, 0, length * MemoryLayout<Float>.stride)
        
        // Generate each frequency component
        for frequency in frequencies {
            var phase: Double = 0.0
            let phaseIncrement = 2.0 * Double.pi * frequency / sampleRate
            let amplitude = 1.0 / Double(frequencies.count)
            
            for i in 0..<length {
                buffer[i] += Float(amplitude * sin(phase))
                phase += phaseIncrement
                
                if phase >= 2.0 * Double.pi {
                    phase -= 2.0 * Double.pi
                }
            }
        }
    }
    
    private func measureTHD(
        inputBuffer: UnsafeMutablePointer<Float>,
        outputBuffer: UnsafeMutablePointer<Float>,
        length: Int,
        fundamentalFreq: Double
    ) throws -> Double {
        // Perform FFT analysis
        let fftResults = try fftProcessor.processFFT(
            outputBuffer,
            outputBuffer,
            frameCount: length
        )
        
        // Find fundamental frequency bin
        let frequencyResolution = Double(kTestSampleRate) / Double(kTestFFTSize)
        let fundamentalBin = Int(fundamentalFreq / frequencyResolution)
        
        // Calculate total harmonic distortion
        var fundamentalPower: Float = 0.0
        var harmonicPower: Float = 0.0
        
        for i in 0..<fftResults.magnitude.count {
            let power = fftResults.magnitude[i] * fftResults.magnitude[i]
            
            if i == fundamentalBin {
                fundamentalPower = power
            } else if i % fundamentalBin == 0 {
                harmonicPower += power
            }
        }
        
        // Calculate THD+N
        return Double(sqrt(harmonicPower / fundamentalPower))
    }
}