//
// DSPProcessorTests.swift
// TALD UNIA
//
// Comprehensive test suite for validating DSP processing functionality
// Version: 1.0.0
//

import XCTest
import Accelerate
import AVFoundation
@testable import TALDUnia

// MARK: - Test Constants

private let kTestSampleRate: Double = 192000.0
private let kTestBufferSize: Int = 256
private let kTestChannels: Int = 2
private let kMaxLatencyMs: Double = 10.0
private let kTargetTHDN: Double = 0.0005
private let kMinEfficiency: Double = 0.90

class DSPProcessorTests: XCTestCase {
    // MARK: - Properties
    
    private var processor: DSPProcessor!
    private var testBuffer: UnsafeMutablePointer<Float>!
    private var referenceBuffer: UnsafeMutablePointer<Float>!
    private var processingQueue: DispatchQueue!
    private var audioFormat: AVAudioFormat!
    private var simdProcessor: SIMDProcessor!
    
    // MARK: - Test Lifecycle
    
    override func setUp() {
        super.setUp()
        
        // Initialize DSP processor with test configuration
        let config = DSPConfiguration(
            bufferSize: kTestBufferSize,
            channels: kTestChannels,
            sampleRate: kTestSampleRate,
            isOptimized: true,
            useHardwareAcceleration: true
        )
        
        do {
            processor = try DSPProcessor(config: config)
            simdProcessor = try SIMDProcessor(channels: kTestChannels)
            
            // Create aligned test buffers
            testBuffer = UnsafeMutablePointer<Float>.allocate(
                capacity: kTestBufferSize * kTestChannels
            ).alignedPointer(to: Float.self, alignment: 16)!
            
            referenceBuffer = UnsafeMutablePointer<Float>.allocate(
                capacity: kTestBufferSize * kTestChannels
            ).alignedPointer(to: Float.self, alignment: 16)!
            
            // Initialize test buffers
            testBuffer.initialize(repeating: 0.0, count: kTestBufferSize * kTestChannels)
            referenceBuffer.initialize(repeating: 0.0, count: kTestBufferSize * kTestChannels)
            
            // Configure processing queue
            processingQueue = DispatchQueue(
                label: "com.tald.unia.dsp.tests",
                qos: .userInteractive
            )
            
            // Create audio format
            let formatResult = createAudioFormat(
                sampleRate: Int(kTestSampleRate),
                bitDepth: 32,
                channelCount: kTestChannels,
                isHardwareOptimized: true
            )
            audioFormat = try formatResult.get()
            
        } catch {
            XCTFail("Failed to initialize test environment: \(error)")
        }
    }
    
    override func tearDown() {
        // Clean up resources
        testBuffer.deallocate()
        referenceBuffer.deallocate()
        processor = nil
        simdProcessor = nil
        processingQueue = nil
        audioFormat = nil
        
        super.tearDown()
    }
    
    // MARK: - Audio Quality Tests
    
    func testAudioQuality() {
        // Generate test tones at multiple frequencies
        let testFrequencies = [20.0, 1000.0, 4000.0, 16000.0]
        
        for frequency in testFrequencies {
            // Generate reference sine wave
            for i in 0..<kTestBufferSize {
                let value = sin(2.0 * Double.pi * frequency * Double(i) / kTestSampleRate)
                referenceBuffer[i] = Float(value)
            }
            
            // Process through DSP chain
            let result = processor.process(
                referenceBuffer,
                testBuffer,
                frameCount: kTestBufferSize
            )
            
            guard case .success(let metrics) = result else {
                XCTFail("Processing failed for frequency \(frequency)Hz")
                continue
            }
            
            // Measure THD+N
            var thdPlusNoise: Float = 0.0
            vDSP_measqv(testBuffer, 1, &thdPlusNoise, vDSP_Length(kTestBufferSize))
            
            // Verify audio quality meets specifications
            XCTAssertLessThan(
                Double(thdPlusNoise),
                kTargetTHDN,
                "THD+N exceeds target at \(frequency)Hz: \(thdPlusNoise)"
            )
            
            // Verify processing metrics
            XCTAssertLessThan(
                metrics.averageLatency,
                kMaxLatencyMs / 1000.0,
                "Processing latency exceeds maximum at \(frequency)Hz"
            )
        }
    }
    
    func testProcessingLatency() {
        let testDurations = [1.0, 2.0, 5.0] // Test durations in seconds
        
        for duration in testDurations {
            let frameCount = Int(duration * kTestSampleRate)
            var totalLatency: Double = 0.0
            var maxLatency: Double = 0.0
            let iterations = frameCount / kTestBufferSize
            
            for _ in 0..<iterations {
                let startTime = Date()
                
                let result = processor.process(
                    referenceBuffer,
                    testBuffer,
                    frameCount: kTestBufferSize
                )
                
                guard case .success = result else {
                    XCTFail("Processing failed during latency test")
                    continue
                }
                
                let latency = Date().timeIntervalSince(startTime)
                totalLatency += latency
                maxLatency = max(maxLatency, latency)
                
                // Verify each iteration meets latency requirement
                XCTAssertLessThan(
                    latency,
                    kMaxLatencyMs / 1000.0,
                    "Individual processing latency exceeds maximum"
                )
            }
            
            // Verify average latency
            let averageLatency = totalLatency / Double(iterations)
            XCTAssertLessThan(
                averageLatency,
                kMaxLatencyMs / 1000.0,
                "Average processing latency exceeds maximum for \(duration)s duration"
            )
        }
    }
    
    func testHardwareIntegration() {
        // Test ESS ES9038PRO DAC integration
        let dacConfig = HardwareConfig.ess9038Pro
        
        do {
            // Initialize SIMD processor with DAC configuration
            let dacProcessor = try SIMDProcessor(
                channels: kTestChannels,
                config: dacConfig
            )
            
            // Generate test signal
            for i in 0..<kTestBufferSize {
                let value = sin(2.0 * Double.pi * 1000.0 * Double(i) / kTestSampleRate)
                referenceBuffer[i] = Float(value)
            }
            
            // Process through hardware-optimized chain
            let result = dacProcessor.processVector(
                referenceBuffer,
                testBuffer,
                frameCount: kTestBufferSize
            )
            
            guard case .success(let metrics) = result else {
                XCTFail("Hardware-optimized processing failed")
                return
            }
            
            // Verify hardware processing metrics
            XCTAssertLessThan(
                metrics.averageLatency,
                kMaxLatencyMs / 1000.0,
                "Hardware processing latency exceeds maximum"
            )
            
            XCTAssertGreaterThan(
                metrics.processingLoad,
                kMinEfficiency,
                "Hardware processing efficiency below target"
            )
            
            // Verify bit depth and alignment
            XCTAssertEqual(
                dacConfig.bitDepth,
                32,
                "Incorrect bit depth for ESS ES9038PRO DAC"
            )
            
            XCTAssertTrue(
                dacConfig.useI2S,
                "I2S interface not enabled for DAC"
            )
            
        } catch {
            XCTFail("Hardware integration test failed: \(error)")
        }
    }
    
    func testSIMDOptimization() {
        // Test SIMD-optimized processing
        let vectorSize = 8
        let testSignal = generateTestSignal(frequency: 1000.0, duration: 0.1)
        
        do {
            let result = simdProcessor.processVector(
                testSignal,
                testBuffer,
                frameCount: kTestBufferSize
            )
            
            guard case .success(let metrics) = result else {
                XCTFail("SIMD processing failed")
                return
            }
            
            // Verify SIMD processing performance
            XCTAssertLessThan(
                metrics.averageLatency,
                kMaxLatencyMs / 1000.0,
                "SIMD processing latency exceeds maximum"
            )
            
            // Verify vector alignment
            let alignment = MemoryLayout<Float>.alignment
            XCTAssertEqual(
                Int(bitPattern: testBuffer) % alignment,
                0,
                "Buffer not properly aligned for SIMD operations"
            )
        }
    }
    
    // MARK: - Helper Methods
    
    private func generateTestSignal(frequency: Double, duration: Double) -> UnsafePointer<Float> {
        let sampleCount = Int(duration * kTestSampleRate)
        let signal = UnsafeMutablePointer<Float>.allocate(capacity: sampleCount)
        
        for i in 0..<sampleCount {
            let value = sin(2.0 * Double.pi * frequency * Double(i) / kTestSampleRate)
            signal[i] = Float(value)
        }
        
        return UnsafePointer(signal)
    }
}