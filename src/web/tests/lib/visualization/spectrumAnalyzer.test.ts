/**
 * TALD UNIA Audio System - Spectrum Analyzer Test Suite
 * Version: 1.0.0
 * 
 * Comprehensive test suite for WebGL-accelerated spectrum analyzer with
 * high-precision audio quality validation and performance benchmarking.
 * 
 * @jest/globals ^29.0.0
 * @lunapaint/webgl-mock ^1.0.0
 * standardized-audio-context ^25.3.0
 */

import { describe, test, expect, beforeEach, afterEach, jest } from '@jest/globals';
import { WebGLRenderingContext } from '@lunapaint/webgl-mock';
import { AudioContext } from 'standardized-audio-context';
import { SpectrumAnalyzer } from '../../../src/lib/visualization/spectrumAnalyzer';
import { VisualizationConfig } from '../../../src/types/visualization.types';
import { calculateRMSLevel, calculateTHD, generateTestSignal } from '../../../src/utils/audioUtils';

// Test constants
const TEST_SAMPLE_RATE = 48000;
const TEST_FFT_SIZE = 2048;
const TEST_FREQUENCY = 1000;
const MAX_PROCESSING_TIME_MS = 10;
const THD_PRECISION = 0.000001;
const WEBGL_MEMORY_LIMIT = 64 * 1024 * 1024; // 64MB

describe('SpectrumAnalyzer', () => {
    let analyzer: SpectrumAnalyzer;
    let audioContext: AudioContext;
    let mockGLContext: WebGLRenderingContext;
    let testConfig: VisualizationConfig;
    let canvas: HTMLCanvasElement;

    beforeEach(() => {
        // Setup WebGL mock
        canvas = document.createElement('canvas');
        mockGLContext = new WebGLRenderingContext(canvas, { 
            alpha: false,
            depth: false,
            antialias: false,
            powerPreference: 'high-performance',
            preserveDrawingBuffer: false
        });

        // Mock WebGL context creation
        jest.spyOn(canvas, 'getContext').mockReturnValue(mockGLContext);

        // Initialize test configuration
        testConfig = {
            fftSize: TEST_FFT_SIZE,
            smoothingTimeConstant: 0.8,
            minDecibels: -90,
            maxDecibels: -10,
            minFrequency: 20,
            maxFrequency: 20000,
            updateInterval: 16.67,
            colorScheme: 'spectrum'
        };

        // Initialize audio context and analyzer
        audioContext = new AudioContext({ sampleRate: TEST_SAMPLE_RATE });
        analyzer = new SpectrumAnalyzer(testConfig);
    });

    afterEach(() => {
        jest.clearAllMocks();
        audioContext.close();
    });

    test('should initialize with WebGL acceleration', async () => {
        await analyzer.initialize(audioContext);
        
        expect(mockGLContext.getParameter(mockGLContext.MAX_TEXTURE_SIZE)).toBeGreaterThanOrEqual(2048);
        expect(mockGLContext.getParameter(mockGLContext.VERSION)).toContain('WebGL 2.0');
        expect(analyzer['webglPlot']).toBeDefined();
        expect(analyzer['shaderProgram']).toBeDefined();
    });

    test('should perform real-time analysis with WebGL acceleration', async () => {
        await analyzer.initialize(audioContext);

        // Generate test signal
        const testSignal = generateTestSignal(TEST_FREQUENCY, TEST_SAMPLE_RATE, TEST_FFT_SIZE);
        
        // Measure processing time
        const startTime = performance.now();
        const result = await analyzer.analyze();
        const processingTime = performance.now() - startTime;

        // Verify processing time meets real-time requirement
        expect(processingTime).toBeLessThan(MAX_PROCESSING_TIME_MS);

        // Verify frequency resolution
        const frequencyResolution = TEST_SAMPLE_RATE / TEST_FFT_SIZE;
        expect(result.resolution).toBe(frequencyResolution);

        // Verify test frequency is detected
        const testFrequencyBin = Math.round(TEST_FREQUENCY / frequencyResolution);
        expect(result.magnitudes[testFrequencyBin]).toBeGreaterThan(0);
    });

    test('should measure THD with high precision', async () => {
        await analyzer.initialize(audioContext);

        // Generate pure sine wave test signal
        const testSignal = generateTestSignal(TEST_FREQUENCY, TEST_SAMPLE_RATE, TEST_FFT_SIZE);
        
        // Process signal and get THD measurement
        const metrics = await analyzer['audioAnalyzer'].analyzeAudioQuality(
            testSignal,
            TEST_SAMPLE_RATE
        );

        // Verify THD meets high-precision requirement
        expect(metrics.thd).toBeLessThan(THD_PRECISION);
        expect(metrics.thd).toBeCloseTo(0.0005, 6);
    });

    test('should handle WebGL resource management efficiently', async () => {
        await analyzer.initialize(audioContext);

        // Monitor WebGL memory usage
        const initialMemory = mockGLContext.getParameter(mockGLContext.GPU_MEMORY_INFO_CURRENT_AVAILABLE);
        
        // Perform multiple analyses
        for (let i = 0; i < 100; i++) {
            await analyzer.analyze();
        }

        const finalMemory = mockGLContext.getParameter(mockGLContext.GPU_MEMORY_INFO_CURRENT_AVAILABLE);
        
        // Verify no significant memory leaks
        expect(initialMemory - finalMemory).toBeLessThan(WEBGL_MEMORY_LIMIT);
    });

    test('should update visualization config dynamically', async () => {
        await analyzer.initialize(audioContext);

        const newConfig: Partial<VisualizationConfig> = {
            fftSize: 4096,
            smoothingTimeConstant: 0.9
        };

        analyzer.updateConfig(newConfig);

        // Verify config update
        expect(analyzer['config'].fftSize).toBe(4096);
        expect(analyzer['config'].smoothingTimeConstant).toBe(0.9);

        // Verify WebGL buffers are resized
        expect(analyzer['frequencyData'].length).toBe(4096 / 2);
        expect(analyzer['webglPlot']).toBeDefined();
    });

    test('should maintain high precision across frequency range', async () => {
        await analyzer.initialize(audioContext);

        // Test frequencies across spectrum
        const testFrequencies = [50, 1000, 10000];
        
        for (const freq of testFrequencies) {
            const testSignal = generateTestSignal(freq, TEST_SAMPLE_RATE, TEST_FFT_SIZE);
            const result = await analyzer.analyze();

            // Verify frequency detection accuracy
            const expectedBin = Math.round(freq / (TEST_SAMPLE_RATE / TEST_FFT_SIZE));
            const detectedPeak = result.frequencies[
                Array.from(result.magnitudes).indexOf(Math.max(...result.magnitudes))
            ];

            expect(Math.abs(detectedPeak - freq)).toBeLessThan(TEST_SAMPLE_RATE / TEST_FFT_SIZE);
        }
    });

    test('should handle error conditions gracefully', async () => {
        await analyzer.initialize(audioContext);

        // Test invalid FFT size
        expect(() => {
            analyzer.updateConfig({ fftSize: 1023 }); // Not power of 2
        }).toThrow('FFT size must be a power of 2');

        // Test invalid frequency range
        expect(() => {
            analyzer.updateConfig({ minFrequency: 10 }); // Below minimum
        }).toThrow('Minimum frequency cannot be less than 20Hz');

        // Test WebGL context loss
        const contextLostEvent = new Event('webglcontextlost');
        canvas.dispatchEvent(contextLostEvent);
        
        // Verify fallback to non-WebGL mode
        const result = await analyzer.analyze();
        expect(result).toBeDefined();
    });
});