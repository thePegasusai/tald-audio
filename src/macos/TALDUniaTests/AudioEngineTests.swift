//
// AudioEngineTests.swift
// TALD UNIA
//
// Comprehensive test suite for validating audio engine functionality and performance
// Version: 1.0.0
//

import XCTest
import AVFoundation
@testable import TALDUnia

class AudioEngineTests: XCTestCase {
    // MARK: - Constants
    
    private let kTestBufferSize: Int = 512
    private let kTestSampleRate: Double = 192000.0
    private let kTestChannelCount: Int = 2
    private let kMaxLatencyThreshold: TimeInterval = 0.010 // 10ms requirement
    private let kMinEfficiencyThreshold: Double = 0.90 // 90% efficiency requirement
    private let kMaxTHDThreshold: Double = 0.000005 // 0.0005% THD+N requirement
    
    // MARK: - Properties
    
    private var audioEngine: AudioEngine!
    private var dspProcessor: DSPProcessor!
    private var testBuffer: CircularAudioBuffer!
    private var performanceMonitor: HardwareMonitor!
    private var powerMonitor: PowerMonitor!
    
    // MARK: - Setup/Teardown
    
    override func setUp() {
        super.setUp()
        
        // Initialize audio engine with test configuration
        let engineConfig = try! createAudioFormat(
            sampleRate: Int(kTestSampleRate),
            bitDepth: AudioConstants.BIT_DEPTH,
            channelCount: kTestChannelCount,
            isHardwareOptimized: true
        )
        
        audioEngine = try! AudioEngine()
        
        // Configure DSP processor
        let dspConfig = DSPConfiguration(
            bufferSize: kTestBufferSize,
            channels: kTestChannelCount,
            sampleRate: kTestSampleRate,
            isOptimized: true,
            useHardwareAcceleration: true
        )
        dspProcessor = try! DSPProcessor(config: dspConfig)
        
        // Initialize test buffer
        testBuffer = CircularAudioBuffer(
            capacity: kTestBufferSize,
            channels: kTestChannelCount
        )
        
        // Setup monitoring
        performanceMonitor = HardwareMonitor()
        powerMonitor = PowerMonitor()
    }
    
    override func tearDown() {
        // Stop and cleanup audio engine
        audioEngine.stop()
        audioEngine = nil
        
        // Release DSP resources
        dspProcessor = nil
        
        // Clean up test buffers
        testBuffer = nil
        
        // Stop monitoring
        performanceMonitor = nil
        powerMonitor = nil
        
        super.tearDown()
    }
    
    // MARK: - Audio Quality Tests
    
    func testAudioQuality() {
        // Generate test signal
        let testSignal = generateTestSignal(frequency: 1000.0, duration: 1.0)
        
        // Process through audio engine
        let result = audioEngine.processAudioBuffer(testSignal)
        
        guard case .success(let processedBuffer) = result else {
            XCTFail("Audio processing failed")
            return
        }
        
        // Measure THD+N
        let thdResult = dspProcessor.measureTHD(processedBuffer)
        
        guard case .success(let thdValue) = thdResult else {
            XCTFail("THD measurement failed")
            return
        }
        
        // Verify THD+N requirement
        XCTAssertLessThanOrEqual(
            thdValue,
            kMaxTHDThreshold,
            "THD+N exceeds maximum threshold of 0.0005%"
        )
        
        // Analyze frequency response
        let frequencyResponse = analyzeFrequencyResponse(processedBuffer)
        XCTAssertTrue(validateFrequencyResponse(frequencyResponse))
        
        // Check signal-to-noise ratio
        let snr = measureSNR(processedBuffer)
        XCTAssertGreaterThan(snr, 120.0, "SNR below required threshold")
    }
    
    // MARK: - Latency Tests
    
    func testProcessingLatency() {
        // Configure high-precision timing
        let timer = HighResolutionTimer()
        
        // Generate test buffer
        let testSignal = generateTestSignal(frequency: 1000.0, duration: 0.1)
        
        // Measure processing latency
        timer.start()
        let result = audioEngine.processAudioBuffer(testSignal)
        let latency = timer.stop()
        
        guard case .success = result else {
            XCTFail("Audio processing failed")
            return
        }
        
        // Verify latency requirement
        XCTAssertLessThanOrEqual(
            latency,
            kMaxLatencyThreshold,
            "Processing latency exceeds maximum threshold of 10ms"
        )
        
        // Analyze processing chain delays
        let processingMetrics = dspProcessor.analyzeLatency()
        XCTAssertLessThanOrEqual(
            processingMetrics.bufferLatency,
            0.002, // 2ms buffer latency
            "Buffer latency too high"
        )
        XCTAssertLessThanOrEqual(
            processingMetrics.dspLatency,
            0.005, // 5ms DSP latency
            "DSP processing latency too high"
        )
    }
    
    // MARK: - Power Efficiency Tests
    
    func testPowerEfficiency() {
        // Start power monitoring
        powerMonitor.startMonitoring()
        
        // Run calibrated load test
        let testDuration: TimeInterval = 10.0
        let testStartTime = Date()
        
        while Date().timeIntervalSince(testStartTime) < testDuration {
            let testSignal = generateTestSignal(frequency: 1000.0, duration: 0.1)
            let _ = audioEngine.processAudioBuffer(testSignal)
        }
        
        // Get power metrics
        let powerMetrics = powerMonitor.getCurrentMetrics()
        
        // Verify efficiency requirement
        XCTAssertGreaterThanOrEqual(
            powerMetrics.efficiency,
            kMinEfficiencyThreshold,
            "Power efficiency below 90% requirement"
        )
        
        // Check thermal performance
        XCTAssertLessThan(
            powerMetrics.temperature,
            85.0, // Maximum 85°C
            "Operating temperature too high"
        )
        
        // Verify power consumption
        XCTAssertLessThan(
            powerMetrics.powerDraw,
            10.0, // Maximum 10W
            "Power consumption too high"
        )
    }
    
    // MARK: - Helper Methods
    
    private func generateTestSignal(frequency: Double, duration: TimeInterval) -> AudioBuffer {
        let sampleCount = Int(duration * kTestSampleRate)
        let buffer = try! createAudioBuffer(
            channelCount: kTestChannelCount,
            frameCount: sampleCount,
            format: audioEngine.currentFormat
        )
        
        // Generate sine wave test signal
        var phase: Double = 0.0
        let phaseIncrement = 2.0 * Double.pi * frequency / kTestSampleRate
        
        for i in 0..<sampleCount {
            let sample = Float(sin(phase))
            buffer.floatChannelData?[0][i] = sample
            buffer.floatChannelData?[1][i] = sample
            phase += phaseIncrement
        }
        
        return buffer
    }
    
    private func analyzeFrequencyResponse(_ buffer: AudioBuffer) -> [Double] {
        // Perform FFT analysis
        let fft = FFTAnalyzer(size: kTestBufferSize)
        return fft.analyze(buffer.floatChannelData?[0] ?? [], sampleRate: kTestSampleRate)
    }
    
    private func validateFrequencyResponse(_ response: [Double]) -> Bool {
        // Verify flat frequency response within ±0.1dB from 20Hz to 20kHz
        let tolerance = 0.1 // ±0.1dB
        let referenceLevel = response[0]
        
        return response.allSatisfy { level in
            abs(level - referenceLevel) <= tolerance
        }
    }
    
    private func measureSNR(_ buffer: AudioBuffer) -> Double {
        // Calculate signal and noise power
        var signalPower: Double = 0.0
        var noisePower: Double = 0.0
        
        let samples = buffer.floatChannelData?[0] ?? []
        let sampleCount = Int(buffer.frameLength)
        
        for i in 0..<sampleCount {
            let sample = Double(samples[i])
            signalPower += sample * sample
        }
        
        // Calculate SNR in dB
        return 10.0 * log10(signalPower / noisePower)
    }
}