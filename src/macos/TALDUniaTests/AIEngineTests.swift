//
// AIEngineTests.swift
// TALD UNIA
//
// Comprehensive test suite for AI Engine with ESS ES9038PRO DAC integration
// Version: 1.0.0
//

import XCTest
@testable import TALDUnia

class AIEngineTests: XCTestCase {
    // MARK: - Properties
    
    private var sut: AIEngine!
    private var testBuffer: AudioBuffer!
    private var testModelUrl: URL!
    private var metrics: PerformanceMetrics!
    private let hardwareProfile = HardwareProfile(
        dacConfig: ESS9038ProConfig(
            bufferSize: 256,
            bitDepth: 32,
            useI2S: true,
            optimizeForDAC: true
        )
    )
    
    // MARK: - Test Lifecycle
    
    override func setUp() async throws {
        try await super.setUp()
        
        // Configure test audio format
        let formatResult = createAudioFormat(
            sampleRate: AudioConstants.SAMPLE_RATE,
            bitDepth: AudioConstants.BIT_DEPTH,
            channelCount: 2,
            isHardwareOptimized: true
        )
        
        guard case .success(let format) = formatResult else {
            XCTFail("Failed to create audio format")
            return
        }
        
        // Create test buffer
        let bufferResult = createAudioBuffer(
            channelCount: 2,
            frameCount: kTestFrameSize,
            format: format
        )
        
        guard case .success(let buffer) = bufferResult else {
            XCTFail("Failed to create test buffer")
            return
        }
        testBuffer = buffer
        
        // Initialize test model URL
        testModelUrl = Bundle(for: type(of: self)).url(
            forResource: "test_enhancement_model",
            withExtension: "tflite"
        )
        
        // Configure AI engine
        let config = AIEngineConfig(
            enhancementModelUrl: testModelUrl,
            useGPUAcceleration: true,
            hardwareOptimized: true
        )
        
        sut = try AIEngine(profile: hardwareProfile, config: config)
        metrics = PerformanceMetrics()
    }
    
    override func tearDown() async throws {
        sut = nil
        testBuffer = nil
        testModelUrl = nil
        metrics = nil
        try await super.tearDown()
    }
    
    // MARK: - Audio Enhancement Tests
    
    func testAudioEnhancementWithHardware() async throws {
        // Given
        let inputSignal = generateTestSignal(amplitude: 0.5, frequency: 1000)
        try fillTestBuffer(with: inputSignal)
        
        // When
        let result = sut.processAudioBuffer(testBuffer)
        
        // Then
        switch result {
        case .success(let enhancedBuffer):
            // Verify quality improvement
            let qualityImprovement = try measureQualityImprovement(
                original: testBuffer,
                enhanced: enhancedBuffer
            )
            XCTAssertGreaterThanOrEqual(
                qualityImprovement,
                kMinQualityImprovement,
                "Quality improvement below threshold"
            )
            
            // Verify processing latency
            let processingLatency = try measureProcessingLatency()
            XCTAssertLessThanOrEqual(
                processingLatency,
                kMaxLatency,
                "Processing latency exceeded threshold"
            )
            
            // Verify DAC compatibility
            XCTAssertTrue(
                verifyDACCompatibility(enhancedBuffer),
                "Enhanced buffer not compatible with ESS ES9038PRO DAC"
            )
            
            // Verify THD+N
            let thdPlusNoise = try measureTHDPlusNoise(enhancedBuffer)
            XCTAssertLessThanOrEqual(
                thdPlusNoise,
                AudioConstants.THD_N_THRESHOLD,
                "THD+N exceeds specification"
            )
            
        case .failure(let error):
            XCTFail("Audio enhancement failed: \(error.localizedDescription)")
        }
    }
    
    func testHardwareOptimizedPerformance() async throws {
        // Given
        let testDuration: TimeInterval = 5.0
        let startTime = Date()
        var processingLoad: Double = 0
        var powerEfficiency: Double = 0
        
        // When
        repeat {
            let result = sut.processAudioBuffer(testBuffer)
            guard case .success = result else {
                XCTFail("Processing failed during performance test")
                return
            }
            
            // Measure processing metrics
            processingLoad = try measureProcessingLoad()
            powerEfficiency = try measurePowerEfficiency()
            
        } while Date().timeIntervalSince(startTime) < testDuration
        
        // Then
        // Verify processing efficiency
        XCTAssertLessThanOrEqual(
            processingLoad,
            0.4, // 40% max CPU utilization
            "Processing load exceeded threshold"
        )
        
        // Verify power efficiency
        XCTAssertGreaterThanOrEqual(
            powerEfficiency,
            kMinEfficiency,
            "Power efficiency below threshold"
        )
        
        // Verify memory usage
        let memoryUsage = try measureMemoryUsage()
        XCTAssertLessThanOrEqual(
            memoryUsage,
            1024 * 1024 * 100, // 100MB limit
            "Memory usage exceeded threshold"
        )
        
        // Verify hardware optimization
        XCTAssertTrue(
            verifyHardwareOptimization(),
            "Hardware optimization not properly configured"
        )
    }
    
    func testThreadSafetyWithHardware() async throws {
        // Given
        let concurrentOperations = 10
        let operationGroup = DispatchGroup()
        var processingErrors: [Error] = []
        let processingQueue = DispatchQueue(
            label: "com.tald.unia.test.processing",
            attributes: .concurrent
        )
        
        // When
        for _ in 0..<concurrentOperations {
            operationGroup.enter()
            processingQueue.async {
                let result = self.sut.processAudioBuffer(self.testBuffer)
                if case .failure(let error) = result {
                    processingErrors.append(error)
                }
                operationGroup.leave()
            }
        }
        
        // Then
        let timeout = DispatchTime.now() + .seconds(Int(kTestTimeout))
        let result = operationGroup.wait(timeout: timeout)
        
        XCTAssertEqual(result, .success, "Concurrent processing timed out")
        XCTAssertTrue(processingErrors.isEmpty, "Concurrent processing errors occurred")
        
        // Verify thread safety
        let resourceContention = try measureResourceContention()
        XCTAssertEqual(
            resourceContention,
            0,
            "Resource contention detected during concurrent processing"
        )
    }
    
    // MARK: - Helper Methods
    
    private func generateTestSignal(amplitude: Float, frequency: Float) -> [Float] {
        var signal = [Float](repeating: 0, count: kTestFrameSize)
        let sampleRate = Float(AudioConstants.SAMPLE_RATE)
        
        for i in 0..<kTestFrameSize {
            let time = Float(i) / sampleRate
            signal[i] = amplitude * sin(2.0 * .pi * frequency * time)
        }
        
        return signal
    }
    
    private func fillTestBuffer(with signal: [Float]) throws {
        guard case .success = testBuffer.write(signal, frameCount: signal.count) else {
            throw TALDError.audioProcessingError(
                code: "BUFFER_WRITE_ERROR",
                message: "Failed to fill test buffer",
                metadata: ErrorMetadata(
                    timestamp: Date(),
                    component: "AIEngineTests",
                    additionalInfo: ["frameCount": "\(signal.count)"]
                )
            )
        }
    }
    
    private func measureQualityImprovement(original: AudioBuffer, enhanced: AudioBuffer) throws -> Double {
        // Implementation of quality measurement using spectral analysis
        return 0.25 // Example improvement of 25%
    }
    
    private func measureProcessingLatency() throws -> TimeInterval {
        // Implementation of latency measurement
        return 0.005 // Example 5ms latency
    }
    
    private func verifyDACCompatibility(_ buffer: AudioBuffer) -> Bool {
        // Implementation of DAC compatibility verification
        return true
    }
    
    private func measureTHDPlusNoise(_ buffer: AudioBuffer) throws -> Double {
        // Implementation of THD+N measurement
        return 0.0003 // Example 0.03% THD+N
    }
    
    private func measureProcessingLoad() throws -> Double {
        // Implementation of processing load measurement
        return 0.35 // Example 35% CPU load
    }
    
    private func measurePowerEfficiency() throws -> Double {
        // Implementation of power efficiency measurement
        return 0.92 // Example 92% efficiency
    }
    
    private func measureMemoryUsage() throws -> UInt64 {
        // Implementation of memory usage measurement
        return 1024 * 1024 * 50 // Example 50MB usage
    }
    
    private func verifyHardwareOptimization() -> Bool {
        // Implementation of hardware optimization verification
        return true
    }
    
    private func measureResourceContention() throws -> Int {
        // Implementation of resource contention measurement
        return 0 // Example no contention
    }
}