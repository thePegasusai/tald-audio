// XCTest v14.0+
import XCTest
import AVFoundation
@testable import TALDUnia

/// Constants for spatial audio testing
private enum TestConstants {
    static let kSampleRate: Double = 192000
    static let kBitDepth: Int = 32
    static let kBufferSize: Int = 256
    static let kTestDuration: TimeInterval = 1.0
    static let kLatencyThreshold: TimeInterval = 0.010
    static let kQualityThresholdTHD: Double = 0.000005  // 0.0005%
    static let kQualityThresholdSNR: Double = 120.0     // 120dB
    static let kTestFrequencyRange: ClosedRange<Double> = 20.0...20000.0
    static let kRoomSize: Double = 50.0
    static let kReverbTime: Double = 0.3
}

/// Comprehensive test suite for validating SpatialEngine functionality
final class SpatialEngineTests: XCTestCase {
    
    // MARK: - Properties
    
    private var spatialEngine: SpatialEngine!
    private var audioBuffer: AudioBuffer!
    private var audioFormat: AudioFormat!
    private var qualityAnalyzer: AudioQualityAnalyzer!
    private var latencyMonitor: LatencyMonitor!
    private var testSignalGenerator: TestSignalGenerator!
    
    // MARK: - Setup & Teardown
    
    override func setUp() async throws {
        try await super.setUp()
        
        // Initialize high-resolution audio format
        audioFormat = try AudioFormat(
            sampleRate: Int(TestConstants.kSampleRate),
            bitDepth: TestConstants.kBitDepth,
            channels: AudioConstants.channelCount,
            interleaved: false
        )
        
        // Initialize test components
        audioBuffer = try AudioBuffer(
            format: audioFormat,
            bufferSize: TestConstants.kBufferSize,
            enableMonitoring: true
        )
        
        spatialEngine = try SpatialEngine(
            format: audioFormat.currentFormat!,
            config: EngineConfiguration(quality: .maximum)
        )
        
        qualityAnalyzer = AudioQualityAnalyzer(
            sampleRate: TestConstants.kSampleRate,
            fftSize: 4096
        )
        
        latencyMonitor = LatencyMonitor(
            sampleRate: TestConstants.kSampleRate,
            bufferSize: TestConstants.kBufferSize
        )
        
        testSignalGenerator = TestSignalGenerator(
            format: audioFormat,
            frequencyRange: TestConstants.kTestFrequencyRange
        )
    }
    
    override func tearDown() async throws {
        spatialEngine = nil
        audioBuffer = nil
        audioFormat = nil
        qualityAnalyzer = nil
        latencyMonitor = nil
        testSignalGenerator = nil
        try await super.tearDown()
    }
    
    // MARK: - Audio Quality Tests
    
    func testAudioQuality() async throws {
        // Generate test signals across frequency range
        let testSignals = try await testSignalGenerator.generateSweepSignal(
            duration: TestConstants.kTestDuration
        )
        
        // Process audio through spatial engine
        var processedBuffers: [AudioBuffer] = []
        
        for signal in testSignals {
            let result = spatialEngine.processAudioBufferWithQuality(signal)
            switch result {
            case .success(let processedBuffer):
                processedBuffers.append(processedBuffer)
            case .failure(let error):
                XCTFail("Audio processing failed: \(error)")
                return
            }
        }
        
        // Analyze audio quality metrics
        let qualityMetrics = try await qualityAnalyzer.analyzeBuffers(processedBuffers)
        
        // Validate THD+N
        XCTAssertLessThanOrEqual(
            qualityMetrics.thd,
            TestConstants.kQualityThresholdTHD,
            "THD+N exceeds Burmester-level requirement"
        )
        
        // Validate SNR
        XCTAssertGreaterThanOrEqual(
            qualityMetrics.snr,
            TestConstants.kQualityThresholdSNR,
            "SNR below premium audio requirement"
        )
        
        // Validate frequency response
        for (frequency, amplitude) in qualityMetrics.frequencyResponse {
            XCTAssertTrue(
                TestConstants.kTestFrequencyRange.contains(frequency),
                "Frequency response outside specified range"
            )
            
            // Check for flat response within ±0.1dB
            XCTAssertEqual(
                amplitude,
                0.0,
                accuracy: 0.1,
                "Frequency response deviation exceeds ±0.1dB at \(frequency)Hz"
            )
        }
    }
    
    // MARK: - Latency Tests
    
    func testProcessingLatency() async throws {
        let testBuffer = try await testSignalGenerator.generateImpulseSignal()
        
        // Measure processing latency
        let startTime = CACurrentMediaTime()
        
        let result = spatialEngine.processAudioBufferWithQuality(testBuffer)
        
        let processingTime = CACurrentMediaTime() - startTime
        
        // Validate processing result
        switch result {
        case .success:
            XCTAssertLessThanOrEqual(
                processingTime,
                TestConstants.kLatencyThreshold,
                "Processing latency exceeds 10ms requirement"
            )
        case .failure(let error):
            XCTFail("Processing failed: \(error)")
        }
        
        // Analyze jitter
        let jitterMetrics = latencyMonitor.analyzeJitter(processingTime)
        XCTAssertLessThanOrEqual(
            jitterMetrics.maxJitter,
            QualityConstants.maxJitter,
            "Processing jitter exceeds maximum allowed"
        )
    }
    
    // MARK: - Spatial Audio Tests
    
    func testSpatialPositioning() async throws {
        // Test positions covering full 360° horizontal plane
        let testPositions: [simd_float3] = [
            simd_float3(0, 0, 1),   // Front
            simd_float3(1, 0, 0),   // Right
            simd_float3(0, 0, -1),  // Back
            simd_float3(-1, 0, 0)   // Left
        ]
        
        let testSignal = try await testSignalGenerator.generateWhiteNoise(
            duration: 0.5
        )
        
        for position in testPositions {
            // Update spatial position
            spatialEngine.updateSpatialPosition(
                position,
                orientation: simd_float3(0, 0, 1)
            )
            
            // Process audio
            let result = spatialEngine.processAudioBufferWithQuality(testSignal)
            
            switch result {
            case .success(let processedBuffer):
                // Analyze spatial accuracy
                let spatialMetrics = try await qualityAnalyzer.analyzeSpatialAccuracy(
                    processedBuffer,
                    expectedPosition: position
                )
                
                XCTAssertLessThanOrEqual(
                    spatialMetrics.positionError,
                    0.1,
                    "Spatial positioning error exceeds 0.1 units"
                )
                
                XCTAssertGreaterThanOrEqual(
                    spatialMetrics.channelSeparation,
                    90.0,
                    "Channel separation below 90dB"
                )
                
            case .failure(let error):
                XCTFail("Spatial processing failed: \(error)")
            }
        }
    }
    
    func testRoomAcoustics() async throws {
        // Configure room parameters
        try spatialEngine.setRoomParameters(
            size: TestConstants.kRoomSize,
            reverbTime: TestConstants.kReverbTime
        )
        
        let impulseResponse = try await testSignalGenerator.generateImpulseSignal()
        
        // Process impulse response
        let result = spatialEngine.processAudioBufferWithQuality(impulseResponse)
        
        switch result {
        case .success(let processedBuffer):
            // Analyze room acoustics
            let acousticMetrics = try await qualityAnalyzer.analyzeRoomAcoustics(
                processedBuffer,
                expectedRT60: TestConstants.kReverbTime
            )
            
            // Validate reverb time
            XCTAssertEqual(
                acousticMetrics.rt60,
                TestConstants.kReverbTime,
                accuracy: 0.05,
                "Reverb time deviation exceeds ±50ms"
            )
            
            // Validate early reflections
            XCTAssertGreaterThanOrEqual(
                acousticMetrics.clarityC50,
                0.0,
                "Speech clarity (C50) below reference level"
            )
            
        case .failure(let error):
            XCTFail("Room acoustics processing failed: \(error)")
        }
    }
    
    func testHeadTracking() async throws {
        let headPositions: [simd_float3] = [
            simd_float3(0, 0, 0),      // Center
            simd_float3(0.1, 0, 0),    // Right tilt
            simd_float3(-0.1, 0, 0),   // Left tilt
            simd_float3(0, 0.1, 0)     // Up tilt
        ]
        
        let testSignal = try await testSignalGenerator.generatePinkNoise(
            duration: 0.2
        )
        
        for position in headPositions {
            // Update head position
            spatialEngine.updateHeadPosition(
                position,
                timestamp: CACurrentMediaTime()
            )
            
            // Process audio
            let result = spatialEngine.processAudioBufferWithQuality(testSignal)
            
            switch result {
            case .success(let processedBuffer):
                // Analyze head tracking accuracy
                let trackingMetrics = try await qualityAnalyzer.analyzeHeadTracking(
                    processedBuffer,
                    expectedPosition: position
                )
                
                XCTAssertLessThanOrEqual(
                    trackingMetrics.positionError,
                    0.01,
                    "Head tracking position error exceeds 0.01 units"
                )
                
                XCTAssertLessThanOrEqual(
                    trackingMetrics.latency,
                    0.005,
                    "Head tracking latency exceeds 5ms"
                )
                
            case .failure(let error):
                XCTFail("Head tracking processing failed: \(error)")
            }
        }
    }
}