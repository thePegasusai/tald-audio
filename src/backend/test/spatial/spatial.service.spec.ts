import { Test, TestingModule } from '@nestjs/testing';
import { SpatialService } from '../../src/spatial/spatial.service';
import { BeamformingProcessor } from '../../src/spatial/processors/beamforming.processor';
import { RoomModelingProcessor } from '../../src/spatial/processors/room-modeling.processor';
import { HRTFData, HRTFPosition } from '../../src/spatial/interfaces/hrtf.interface';

// Test constants aligned with technical specifications
const TEST_CONSTANTS = {
    SAMPLE_RATE: 192000,
    BUFFER_SIZE: 2048,
    MAX_LATENCY_MS: 10,
    THD_TARGET: 0.0005,
    TEST_DURATION_MS: 1000,
    SPATIAL_POSITIONS: [
        { azimuth: 0, elevation: 0, distance: 1 },
        { azimuth: 90, elevation: 45, distance: 2 },
        { azimuth: -90, elevation: -45, distance: 0.5 },
        { azimuth: 180, elevation: 30, distance: 3 }
    ]
};

// Mock HRTF dataset for testing
const mockHRTFDataset: HRTFData = {
    sampleRate: TEST_CONSTANTS.SAMPLE_RATE,
    leftImpulseResponse: new Float32Array(512).fill(0.1),
    rightImpulseResponse: new Float32Array(512).fill(0.1),
    length: 512
};

describe('SpatialService', () => {
    let service: SpatialService;
    let mockBeamformingProcessor: jest.Mocked<BeamformingProcessor>;
    let mockRoomModelingProcessor: jest.Mocked<RoomModelingProcessor>;
    let testAudioBuffer: Float32Array;

    beforeEach(async () => {
        // Initialize mock processors with detailed tracking
        mockBeamformingProcessor = {
            processFrame: jest.fn(),
            updateArrayGeometry: jest.fn(),
            getProcessingMetrics: jest.fn().mockReturnValue({
                processingTime: 1,
                noiseFloor: -120,
                directivityIndex: 0.9,
                adaptiveGain: new Array(8).fill(0.5)
            })
        } as any;

        mockRoomModelingProcessor = {
            processFrame: jest.fn(),
            updateRoomModel: jest.fn(),
            getAcousticMetrics: jest.fn().mockReturnValue({
                reverbTime: 0.3,
                clarity: 8.5,
                definition: 0.65
            })
        } as any;

        // Create test module with mocked dependencies
        const module: TestingModule = await Test.createTestingModule({
            providers: [
                SpatialService,
                {
                    provide: BeamformingProcessor,
                    useValue: mockBeamformingProcessor
                },
                {
                    provide: RoomModelingProcessor,
                    useValue: mockRoomModelingProcessor
                }
            ]
        }).compile();

        service = module.get<SpatialService>(SpatialService);

        // Initialize test audio buffer with known signal characteristics
        testAudioBuffer = new Float32Array(TEST_CONSTANTS.BUFFER_SIZE);
        for (let i = 0; i < testAudioBuffer.length; i++) {
            testAudioBuffer[i] = Math.sin(2 * Math.PI * 1000 * i / TEST_CONSTANTS.SAMPLE_RATE);
        }

        // Load test HRTF dataset
        await service.loadHRTFDataset('test_dataset');
    });

    describe('Spatial Audio Processing', () => {
        it('should process audio with performance validation', async () => {
            // Configure test position
            const testPosition: HRTFPosition = TEST_CONSTANTS.SPATIAL_POSITIONS[0];
            
            // Process test buffer and measure performance
            const startTime = performance.now();
            const processedBuffer = await service.processSpatialAudio(testAudioBuffer, testPosition);
            const processingTime = performance.now() - startTime;

            // Validate processing time against latency requirement
            expect(processingTime).toBeLessThan(TEST_CONSTANTS.MAX_LATENCY_MS);

            // Verify output buffer integrity
            expect(processedBuffer).toBeInstanceOf(Float32Array);
            expect(processedBuffer.length).toBe(testAudioBuffer.length * 2); // Stereo output

            // Calculate and validate THD+N
            const thdPlusNoise = await service.calculateTHDN(processedBuffer);
            expect(thdPlusNoise).toBeLessThan(TEST_CONSTANTS.THD_TARGET);
        });

        it('should maintain consistent performance across positions', async () => {
            const latencies: number[] = [];

            // Test processing at multiple spatial positions
            for (const position of TEST_CONSTANTS.SPATIAL_POSITIONS) {
                const latency = await service.measureLatency(testAudioBuffer, position);
                latencies.push(latency);
            }

            // Validate latency consistency
            const maxLatency = Math.max(...latencies);
            const latencyVariation = Math.max(...latencies) - Math.min(...latencies);

            expect(maxLatency).toBeLessThan(TEST_CONSTANTS.MAX_LATENCY_MS);
            expect(latencyVariation).toBeLessThan(TEST_CONSTANTS.MAX_LATENCY_MS * 0.1);
        });
    });

    describe('HRTF Processing', () => {
        it('should correctly interpolate HRTF filters', async () => {
            const testPosition: HRTFPosition = {
                azimuth: 45,
                elevation: 30,
                distance: 1
            };

            // Update position and verify HRTF interpolation
            await service.updateSpatialPosition(testPosition);

            // Process test frame and analyze spatial accuracy
            const processedBuffer = await service.processSpatialAudio(testAudioBuffer, testPosition);
            
            // Verify stereo separation and phase correlation
            const channelCorrelation = calculateChannelCorrelation(processedBuffer);
            expect(channelCorrelation).toBeGreaterThan(0.1); // Ensure stereo separation
            expect(channelCorrelation).toBeLessThan(0.9); // Avoid excessive correlation
        });

        it('should validate HRTF dataset integrity', async () => {
            const result = await service.loadHRTFDataset('test_dataset');
            expect(result).toBe(true);

            // Verify HRTF data properties
            const hrtfData = await service['getHRTFData']();
            expect(hrtfData.sampleRate).toBe(TEST_CONSTANTS.SAMPLE_RATE);
            expect(hrtfData.leftImpulseResponse).toBeInstanceOf(Float32Array);
            expect(hrtfData.rightImpulseResponse).toBeInstanceOf(Float32Array);
        });
    });

    describe('Performance Optimization', () => {
        it('should optimize processing chain', async () => {
            const iterations = 100;
            const processingTimes: number[] = [];

            // Measure processing stability over multiple iterations
            for (let i = 0; i < iterations; i++) {
                const startTime = performance.now();
                await service.processSpatialAudio(testAudioBuffer, TEST_CONSTANTS.SPATIAL_POSITIONS[0]);
                processingTimes.push(performance.now() - startTime);
            }

            // Calculate processing statistics
            const averageTime = processingTimes.reduce((a, b) => a + b) / iterations;
            const maxTime = Math.max(...processingTimes);
            const jitter = calculateJitter(processingTimes);

            expect(averageTime).toBeLessThan(TEST_CONSTANTS.MAX_LATENCY_MS * 0.8);
            expect(maxTime).toBeLessThan(TEST_CONSTANTS.MAX_LATENCY_MS);
            expect(jitter).toBeLessThan(1); // Max 1ms jitter
        });
    });

    // Helper functions for audio analysis
    function calculateChannelCorrelation(stereoBuffer: Float32Array): number {
        let correlation = 0;
        const samplesPerChannel = stereoBuffer.length / 2;

        for (let i = 0; i < samplesPerChannel; i++) {
            correlation += stereoBuffer[i * 2] * stereoBuffer[i * 2 + 1];
        }

        return Math.abs(correlation / samplesPerChannel);
    }

    function calculateJitter(times: number[]): number {
        const diffs = times.slice(1).map((time, i) => Math.abs(time - times[i]));
        return Math.max(...diffs);
    }
});