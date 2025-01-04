//
// SpatialEngineTests.swift
// TALD UNIA
//
// Comprehensive test suite for SpatialEngine validation
// Version: 1.0.0
//

import XCTest
import simd
import Accelerate
import os.log
@testable import TALDUnia

// MARK: - Test Constants
private let kTestSampleRate: Float = 48000.0
private let kTestBufferSize: Int = 1024
private let kTestTimeout: TimeInterval = 5.0
private let kMaxLatencyThreshold: TimeInterval = 0.010 // 10ms requirement
private let kTHDNThreshold: Float = 0.0005 // Burmester-level quality requirement
private let kTestRoomPresets = ["studio", "concert", "theater"]
private let kHeadPositions: [simd_float3] = [
    simd_float3(0, 0, 0),
    simd_float3(0.1, 0, 0),
    simd_float3(0, 0.1, 0),
    simd_float3(0.1, 0.1, 0.1)
]

class SpatialEngineTests: XCTestCase {
    // MARK: - Properties
    private var spatialEngine: SpatialEngine!
    private var testBuffer: CircularAudioBuffer!
    private var processingExpectation: XCTestExpectation!
    private var testQueue: DispatchQueue!
    private let logger = OSLog(subsystem: "com.tald.unia.tests", category: "SpatialEngineTests")
    
    // MARK: - Test Lifecycle
    override func setUp() {
        super.setUp()
        
        // Initialize test queue
        testQueue = DispatchQueue(label: "com.tald.unia.tests.spatial", qos: .userInteractive)
        
        // Configure test buffer
        testBuffer = CircularAudioBuffer(capacity: kTestBufferSize, channels: 2)
        
        // Initialize spatial engine with test configuration
        do {
            spatialEngine = try SpatialEngine(
                sampleRate: kTestSampleRate,
                dacConfig: [
                    "bitDepth": 32,
                    "sampleRate": 192000,
                    "bufferSize": 256,
                    "channelCount": 2
                ]
            )
        } catch {
            XCTFail("Failed to initialize SpatialEngine: \(error)")
        }
        
        // Initialize test expectations
        processingExpectation = expectation(description: "Audio Processing")
    }
    
    override func tearDown() {
        // Stop spatial engine
        _ = spatialEngine.stop()
        
        // Clean up resources
        testBuffer = nil
        spatialEngine = nil
        processingExpectation = nil
        testQueue = nil
        
        super.tearDown()
    }
    
    // MARK: - Core Functionality Tests
    func testInitialization() {
        XCTAssertNotNil(spatialEngine, "SpatialEngine should initialize successfully")
        
        // Test start/stop functionality
        let startResult = spatialEngine.start()
        XCTAssertTrue(startResult.isSuccess, "SpatialEngine should start successfully")
        
        let stopResult = spatialEngine.stop()
        XCTAssertTrue(stopResult.isSuccess, "SpatialEngine should stop successfully")
    }
    
    func testAudioProcessing() {
        // Generate test signal
        let testSignal = generateTestSignal(frequency: 1000.0, duration: 1.0)
        
        // Configure spatial parameters
        let parameters = SpatialParameters(
            sourcePositions: [simd_float3(1.0, 0.0, 0.0)],
            listenerPosition: simd_float3(0.0, 0.0, 0.0),
            listenerOrientation: simd_float3(0.0, 0.0, 1.0),
            roomDimensions: RoomDimensions(width: 10.0, length: 8.0, height: 3.0)
        )
        
        // Process audio
        let result = spatialEngine.processAudioFrame(testSignal, parameters: parameters)
        
        switch result {
        case .success(let processedBuffer):
            XCTAssertEqual(processedBuffer.availableFrames, testSignal.availableFrames)
            validateAudioQuality(processedBuffer)
            
        case .failure(let error):
            XCTFail("Audio processing failed: \(error)")
        }
    }
    
    func testLatencyRequirements() {
        let testSignal = generateTestSignal(frequency: 1000.0, duration: 0.1)
        let parameters = createTestParameters()
        
        measure {
            let startTime = Date()
            
            let result = spatialEngine.processAudioFrame(testSignal, parameters: parameters)
            
            let processingTime = Date().timeIntervalSince(startTime)
            XCTAssertLessThanOrEqual(processingTime, kMaxLatencyThreshold,
                                   "Processing latency exceeds requirement")
            
            XCTAssertTrue(result.isSuccess, "Processing should succeed")
        }
    }
    
    func testConcurrentProcessing() {
        let concurrentExpectation = expectation(description: "Concurrent Processing")
        concurrentExpectation.expectedFulfillmentCount = 4
        
        let testSignal = generateTestSignal(frequency: 1000.0, duration: 0.1)
        let parameters = createTestParameters()
        
        for _ in 0..<4 {
            testQueue.async {
                let result = self.spatialEngine.processAudioFrame(testSignal, parameters: parameters)
                XCTAssertTrue(result.isSuccess, "Concurrent processing should succeed")
                concurrentExpectation.fulfill()
            }
        }
        
        wait(for: [concurrentExpectation], timeout: kTestTimeout)
    }
    
    // MARK: - Spatial Audio Tests
    func testHRTFProcessing() {
        let testSignal = generateTestSignal(frequency: 1000.0, duration: 0.1)
        
        for position in kHeadPositions {
            let parameters = SpatialParameters(
                sourcePositions: [position],
                listenerPosition: simd_float3(0, 0, 0),
                listenerOrientation: simd_float3(0, 0, 1),
                roomDimensions: RoomDimensions(width: 10.0, length: 8.0, height: 3.0)
            )
            
            let result = spatialEngine.processAudioFrame(testSignal, parameters: parameters)
            XCTAssertTrue(result.isSuccess, "HRTF processing should succeed for position \(position)")
        }
    }
    
    func testRoomModeling() {
        let testSignal = generateTestSignal(frequency: 1000.0, duration: 0.1)
        
        for preset in kTestRoomPresets {
            let result = spatialEngine.updateRoomPreset(preset)
            XCTAssertTrue(result.isSuccess, "Room preset update should succeed")
            
            let processingResult = spatialEngine.processAudioFrame(
                testSignal,
                parameters: createTestParameters()
            )
            XCTAssertTrue(processingResult.isSuccess, "Processing with room preset should succeed")
        }
    }
    
    // MARK: - Helper Methods
    private func generateTestSignal(frequency: Float, duration: Float) -> AudioBuffer {
        let sampleCount = Int(kTestSampleRate * duration)
        let buffer = CircularAudioBuffer(capacity: sampleCount, channels: 2)
        
        // Generate sine wave
        var phase: Float = 0.0
        let phaseIncrement = 2.0 * Float.pi * frequency / kTestSampleRate
        
        for i in 0..<sampleCount {
            let sample = sin(phase)
            phase += phaseIncrement
            
            _ = buffer.write([sample, sample], frameCount: 1)
        }
        
        return buffer
    }
    
    private func createTestParameters() -> SpatialParameters {
        return SpatialParameters(
            sourcePositions: [simd_float3(1.0, 0.0, 0.0)],
            listenerPosition: simd_float3(0.0, 0.0, 0.0),
            listenerOrientation: simd_float3(0.0, 0.0, 1.0),
            roomDimensions: RoomDimensions(width: 10.0, length: 8.0, height: 3.0)
        )
    }
    
    private func validateAudioQuality(_ buffer: AudioBuffer) {
        var thdPlusNoise: Float = 0.0
        
        // Calculate THD+N
        vDSP_measqv(
            buffer.bufferData,
            1,
            &thdPlusNoise,
            vDSP_Length(buffer.availableFrames)
        )
        
        XCTAssertLessThanOrEqual(
            thdPlusNoise,
            kTHDNThreshold,
            "Audio quality below Burmester-level requirement"
        )
    }
}