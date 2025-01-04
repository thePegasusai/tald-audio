/**
 * TALD UNIA Audio System - AudioProcessor Test Suite
 * Version: 1.0.0
 * 
 * Comprehensive test suite validating high-fidelity audio processing capabilities
 * including AI enhancement, spatial audio, and quality metrics monitoring.
 */

import { describe, beforeEach, afterEach, test, expect, jest } from '@jest/globals';
import * as tf from '@tensorflow/tfjs'; // v4.10.0
import { 
    AudioProcessor 
} from '../../../src/lib/audio/audioProcessor';
import { 
    AudioConfig,
    SpatialAudioConfig,
    Position3D,
    AudioMetrics,
    ProcessingQuality,
    AudioProcessingEvent,
    ReflectionModel
} from '../../../src/types/audio.types';
import {
    calculateRMSLevel,
    calculateTHD,
    calculateSNR,
    AudioAnalyzer
} from '../../../src/utils/audioUtils';

// Test constants matching system requirements
const TEST_SAMPLE_RATE = 192000;
const TEST_BUFFER_SIZE = 256;
const TEST_LATENCY_THRESHOLD_MS = 10;
const TEST_THD_THRESHOLD = 0.0005;
const TEST_SNR_THRESHOLD_DB = 120;
const TEST_AI_QUALITY_IMPROVEMENT = 20;
const TEST_SPATIAL_ACCURACY_THRESHOLD = 0.1;

describe('AudioProcessor', () => {
    let audioProcessor: AudioProcessor;
    let mockAudioContext: jest.Mocked<AudioContext>;
    let mockAnalyser: jest.Mocked<AnalyserNode>;
    let mockGainNode: jest.Mocked<GainNode>;
    let mockPannerNode: jest.Mocked<PannerNode>;
    let mockConvolverNode: jest.Mocked<ConvolverNode>;
    let mockCompressorNode: jest.Mocked<DynamicsCompressorNode>;
    let mockCanvas: HTMLCanvasElement;
    let mockGLContext: jest.Mocked<WebGLRenderingContext>;

    // Test configuration objects
    const defaultConfig: AudioConfig = {
        sampleRate: TEST_SAMPLE_RATE,
        bitDepth: 32,
        channels: 2,
        bufferSize: TEST_BUFFER_SIZE,
        processingQuality: ProcessingQuality.Maximum
    };

    const defaultSpatialConfig: SpatialAudioConfig = {
        enableSpatial: true,
        roomSize: { width: 5, height: 3, depth: 4 },
        listenerPosition: { x: 0, y: 0, z: 0 },
        hrtfEnabled: true,
        hrtfProfile: 'default',
        roomMaterials: [
            { surface: 'wall', absorptionCoefficient: 0.3, scatteringCoefficient: 0.2 }
        ],
        reflectionModel: ReflectionModel.Hybrid
    };

    beforeEach(async () => {
        // Mock WebGL context
        mockCanvas = document.createElement('canvas');
        mockGLContext = {
            getParameter: jest.fn().mockReturnValue(2),
            VERSION: 2
        } as unknown as jest.Mocked<WebGLRenderingContext>;
        jest.spyOn(mockCanvas, 'getContext').mockReturnValue(mockGLContext);
        document.createElement = jest.fn().mockReturnValue(mockCanvas);

        // Mock Web Audio API nodes
        mockAnalyser = {
            fftSize: 2048,
            smoothingTimeConstant: 0.8,
            connect: jest.fn(),
            disconnect: jest.fn(),
            getFloatTimeDomainData: jest.fn(),
            frequencyBinCount: 1024
        } as unknown as jest.Mocked<AnalyserNode>;

        mockGainNode = {
            connect: jest.fn(),
            disconnect: jest.fn(),
            gain: { value: 1 }
        } as unknown as jest.Mocked<GainNode>;

        mockPannerNode = {
            connect: jest.fn(),
            disconnect: jest.fn(),
            setPosition: jest.fn()
        } as unknown as jest.Mocked<PannerNode>;

        mockConvolverNode = {
            connect: jest.fn(),
            disconnect: jest.fn(),
            buffer: null
        } as unknown as jest.Mocked<ConvolverNode>;

        mockCompressorNode = {
            connect: jest.fn(),
            disconnect: jest.fn(),
            threshold: { value: -24 },
            knee: { value: 30 },
            ratio: { value: 12 },
            attack: { value: 0.003 },
            release: { value: 0.25 }
        } as unknown as jest.Mocked<DynamicsCompressorNode>;

        // Mock AudioContext
        mockAudioContext = {
            createAnalyser: jest.fn().mockReturnValue(mockAnalyser),
            createGain: jest.fn().mockReturnValue(mockGainNode),
            createPanner: jest.fn().mockReturnValue(mockPannerNode),
            createConvolver: jest.fn().mockReturnValue(mockConvolverNode),
            createDynamicsCompressor: jest.fn().mockReturnValue(mockCompressorNode),
            destination: {} as AudioDestinationNode,
            sampleRate: TEST_SAMPLE_RATE,
            decodeAudioData: jest.fn()
        } as unknown as jest.Mocked<AudioContext>;

        // Mock TensorFlow.js
        jest.spyOn(tf, 'loadLayersModel').mockResolvedValue({
            predict: jest.fn().mockReturnValue(tf.tensor(new Float32Array(1024)))
        } as unknown as tf.LayersModel);

        // Initialize AudioProcessor
        audioProcessor = new AudioProcessor(defaultConfig, defaultSpatialConfig);
        await audioProcessor.initialize();
    });

    afterEach(() => {
        jest.clearAllMocks();
    });

    test('should initialize with correct configuration', async () => {
        expect(audioProcessor['isInitialized']).toBe(true);
        expect(mockAudioContext.sampleRate).toBe(TEST_SAMPLE_RATE);
        expect(mockAnalyser.fftSize).toBe(2048);
        expect(mockCompressorNode.threshold.value).toBe(-24);
    });

    test('should process audio within latency requirements', async () => {
        const inputBuffer = new Float32Array(TEST_BUFFER_SIZE);
        const startTime = performance.now();
        
        const processedBuffer = await audioProcessor.process(inputBuffer);
        const processingTime = performance.now() - startTime;

        expect(processingTime).toBeLessThan(TEST_LATENCY_THRESHOLD_MS);
        expect(processedBuffer.length).toBe(TEST_BUFFER_SIZE);
    });

    test('should maintain THD below threshold', async () => {
        const inputBuffer = new Float32Array(TEST_BUFFER_SIZE).fill(0.5);
        const processedBuffer = await audioProcessor.process(inputBuffer);
        
        const thd = calculateTHD(processedBuffer, TEST_SAMPLE_RATE);
        expect(thd).toBeLessThanOrEqual(TEST_THD_THRESHOLD);
    });

    test('should achieve target SNR', async () => {
        const inputBuffer = new Float32Array(TEST_BUFFER_SIZE).fill(0.5);
        const processedBuffer = await audioProcessor.process(inputBuffer);
        
        const snr = calculateSNR(processedBuffer, TEST_SAMPLE_RATE);
        expect(snr).toBeGreaterThanOrEqual(TEST_SNR_THRESHOLD_DB);
    });

    test('should improve audio quality with AI enhancement', async () => {
        const inputBuffer = new Float32Array(TEST_BUFFER_SIZE).fill(0.5);
        const analyzer = new AudioAnalyzer();
        
        const initialMetrics = analyzer.analyzeAudioQuality(inputBuffer, TEST_SAMPLE_RATE);
        const processedBuffer = await audioProcessor.process(inputBuffer);
        const enhancedMetrics = analyzer.analyzeAudioQuality(processedBuffer, TEST_SAMPLE_RATE);

        const qualityImprovement = (
            (enhancedMetrics.snr - initialMetrics.snr) / initialMetrics.snr
        ) * 100;

        expect(qualityImprovement).toBeGreaterThanOrEqual(TEST_AI_QUALITY_IMPROVEMENT);
    });

    test('should accurately update spatial position', () => {
        const position: Position3D = { x: 1, y: 0.5, z: -1 };
        audioProcessor.updateSpatialPosition(position);

        expect(mockPannerNode.setPosition).toHaveBeenCalledWith(
            position.x,
            position.y,
            position.z
        );
    });

    test('should emit metrics updates', async () => {
        const metricsCallback = jest.fn();
        audioProcessor.addEventListener(AudioProcessingEvent.MetricsUpdate, metricsCallback);

        const inputBuffer = new Float32Array(TEST_BUFFER_SIZE);
        await audioProcessor.process(inputBuffer);

        expect(metricsCallback).toHaveBeenCalled();
        const metrics = audioProcessor.getMetrics();
        expect(metrics).toBeDefined();
        expect(metrics.thd).toBeLessThanOrEqual(TEST_THD_THRESHOLD);
    });

    test('should handle configuration updates', () => {
        const newConfig: AudioConfig = {
            ...defaultConfig,
            processingQuality: ProcessingQuality.Balanced
        };

        audioProcessor.updateConfig(newConfig);
        const metrics = audioProcessor.getMetrics();
        
        expect(metrics).toBeDefined();
        expect(metrics.thd).toBeLessThanOrEqual(TEST_THD_THRESHOLD);
    });

    test('should validate HRTF processing accuracy', async () => {
        const position: Position3D = { x: 1, y: 0, z: 0 };
        const inputBuffer = new Float32Array(TEST_BUFFER_SIZE);
        
        audioProcessor.updateSpatialPosition(position);
        const processedBuffer = await audioProcessor.process(inputBuffer);
        
        // Verify spatial processing accuracy through phase analysis
        const analyzer = new AudioAnalyzer();
        const metrics = analyzer.analyzeAudioQuality(processedBuffer, TEST_SAMPLE_RATE);
        
        expect(metrics.phaseResponse.length).toBeGreaterThan(0);
        expect(Math.abs(metrics.phaseResponse[0].phase)).toBeLessThanOrEqual(
            TEST_SPATIAL_ACCURACY_THRESHOLD
        );
    });
});