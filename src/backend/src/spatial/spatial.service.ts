import { Injectable } from '@nestjs/common';
import { HRTFData, HRTFPosition } from './interfaces/hrtf.interface';
import { BeamformingProcessor } from './processors/beamforming.processor';
import { RoomModelingProcessor } from './processors/room-modeling.processor';
import { fft } from 'fft.js'; // v4.0.3

/**
 * Performance monitoring interface for spatial processing
 */
interface PerformanceMetrics {
    processingTime: number;
    bufferUtilization: number;
    latency: number;
    qualityMetrics: {
        thdPlusNoise: number;
        signalToNoise: number;
        spatialAccuracy: number;
    };
}

/**
 * Cache structure for processed HRTF data
 */
interface ProcessedHRTFData {
    leftFilter: Float32Array;
    rightFilter: Float32Array;
    position: HRTFPosition;
    timestamp: number;
}

/**
 * TALD UNIA Audio System - Spatial Audio Service
 * Implements high-performance spatial audio processing with comprehensive error handling
 * @version 1.0.0
 */
@Injectable()
export class SpatialService {
    private readonly fftProcessor: typeof fft;
    private readonly hrtfDataset: Map<string, HRTFData>;
    private readonly hrtfCache: Map<string, ProcessedHRTFData>;
    private currentPosition: HRTFPosition;
    private readonly performanceMetrics: PerformanceMetrics;
    private readonly CACHE_SIZE = 64;
    private readonly MAX_LATENCY_MS = 10;
    private readonly THD_TARGET = 0.0005;

    constructor(
        private readonly beamformingProcessor: BeamformingProcessor,
        private readonly roomModelingProcessor: RoomModelingProcessor
    ) {
        // Initialize FFT processor with optimal settings
        this.fftProcessor = new fft(2048);

        // Initialize HRTF dataset and cache
        this.hrtfDataset = new Map();
        this.hrtfCache = new Map();

        // Initialize default spatial position
        this.currentPosition = {
            azimuth: 0,
            elevation: 0,
            distance: 1
        };

        // Initialize performance monitoring
        this.performanceMetrics = {
            processingTime: 0,
            bufferUtilization: 0,
            latency: 0,
            qualityMetrics: {
                thdPlusNoise: 0,
                signalToNoise: 120,
                spatialAccuracy: 1.0
            }
        };
    }

    /**
     * Process audio buffer with spatial effects and quality validation
     * @param inputBuffer Input audio buffer
     * @param position Target spatial position
     * @returns Processed audio buffer with spatial effects
     */
    public async processSpatialAudio(
        inputBuffer: Float32Array,
        position: HRTFPosition
    ): Promise<Float32Array> {
        const startTime = performance.now();

        try {
            // Validate input parameters
            this.validateInputParameters(inputBuffer, position);

            // Apply beamforming for directional audio
            const beamformedAudio = this.beamformingProcessor.processFrame(
                [inputBuffer],
                position
            );

            // Apply room acoustics modeling
            const roomProcessedAudio = this.roomModelingProcessor.processFrame(
                beamformedAudio
            );

            // Apply HRTF convolution
            const spatializedAudio = await this.applyHRTFProcessing(
                roomProcessedAudio,
                position
            );

            // Update performance metrics
            this.updatePerformanceMetrics(startTime);

            // Validate output quality
            this.validateOutputQuality(spatializedAudio);

            return spatializedAudio;
        } catch (error) {
            this.handleProcessingError(error);
            throw error;
        }
    }

    /**
     * Update spatial position with smooth interpolation
     * @param newPosition New spatial position
     */
    public async updateSpatialPosition(newPosition: HRTFPosition): Promise<void> {
        try {
            // Validate position parameters
            this.validatePosition(newPosition);

            // Calculate interpolation parameters
            const interpolationSteps = this.calculateInterpolationSteps(
                this.currentPosition,
                newPosition
            );

            // Update HRTF cache for new position
            await this.updateHRTFCache(newPosition);

            // Update beamforming array configuration
            this.beamformingProcessor.updateArrayGeometry(
                this.calculateArrayGeometry(newPosition)
            );

            // Store new position
            this.currentPosition = newPosition;
        } catch (error) {
            this.handlePositionUpdateError(error);
            throw error;
        }
    }

    /**
     * Load and validate HRTF dataset
     * @param datasetPath Path to HRTF dataset
     * @returns Success status
     */
    public async loadHRTFDataset(datasetPath: string): Promise<boolean> {
        try {
            // Clear existing dataset
            this.hrtfDataset.clear();
            this.hrtfCache.clear();

            // Load and validate HRTF data
            const hrtfData = await this.loadAndValidateHRTFData(datasetPath);

            // Initialize dataset with validated data
            this.initializeHRTFDataset(hrtfData);

            return true;
        } catch (error) {
            this.handleDatasetLoadError(error);
            return false;
        }
    }

    /**
     * Private helper methods
     */
    private validateInputParameters(
        inputBuffer: Float32Array,
        position: HRTFPosition
    ): void {
        if (!inputBuffer || inputBuffer.length === 0) {
            throw new Error('Invalid input buffer');
        }
        this.validatePosition(position);
    }

    private validatePosition(position: HRTFPosition): void {
        if (
            position.azimuth < -180 || position.azimuth > 180 ||
            position.elevation < -90 || position.elevation > 90 ||
            position.distance <= 0
        ) {
            throw new Error('Invalid spatial position parameters');
        }
    }

    private async applyHRTFProcessing(
        input: Float32Array,
        position: HRTFPosition
    ): Promise<Float32Array> {
        const cacheKey = this.generateCacheKey(position);
        let hrtfData = this.hrtfCache.get(cacheKey);

        if (!hrtfData) {
            hrtfData = await this.processHRTFData(position);
            this.updateCache(cacheKey, hrtfData);
        }

        return this.convolveHRTF(input, hrtfData);
    }

    private async processHRTFData(
        position: HRTFPosition
    ): Promise<ProcessedHRTFData> {
        const nearestHRTF = this.findNearestHRTF(position);
        const interpolatedHRTF = this.interpolateHRTF(nearestHRTF, position);

        return {
            leftFilter: interpolatedHRTF.leftImpulseResponse,
            rightFilter: interpolatedHRTF.rightImpulseResponse,
            position,
            timestamp: Date.now()
        };
    }

    private convolveHRTF(
        input: Float32Array,
        hrtfData: ProcessedHRTFData
    ): Float32Array {
        const output = new Float32Array(input.length * 2);
        const leftChannel = this.performConvolution(input, hrtfData.leftFilter);
        const rightChannel = this.performConvolution(input, hrtfData.rightFilter);

        // Interleave channels
        for (let i = 0; i < input.length; i++) {
            output[i * 2] = leftChannel[i];
            output[i * 2 + 1] = rightChannel[i];
        }

        return output;
    }

    private performConvolution(
        input: Float32Array,
        filter: Float32Array
    ): Float32Array {
        const result = new Float32Array(input.length);
        const fftSize = this.nextPowerOfTwo(input.length + filter.length - 1);
        
        const inputFreq = this.fftProcessor.forward(this.padArray(input, fftSize));
        const filterFreq = this.fftProcessor.forward(this.padArray(filter, fftSize));

        // Complex multiplication in frequency domain
        const resultFreq = new Float32Array(fftSize * 2);
        for (let i = 0; i < fftSize; i += 2) {
            resultFreq[i] = inputFreq[i] * filterFreq[i] - inputFreq[i + 1] * filterFreq[i + 1];
            resultFreq[i + 1] = inputFreq[i] * filterFreq[i + 1] + inputFreq[i + 1] * filterFreq[i];
        }

        const timeResult = this.fftProcessor.inverse(resultFreq);
        result.set(timeResult.subarray(0, input.length));

        return result;
    }

    private updatePerformanceMetrics(startTime: number): void {
        this.performanceMetrics.processingTime = performance.now() - startTime;
        this.performanceMetrics.latency = this.calculateLatency();
        this.performanceMetrics.bufferUtilization = this.calculateBufferUtilization();
    }

    private validateOutputQuality(output: Float32Array): void {
        const thd = this.calculateTHD(output);
        if (thd > this.THD_TARGET) {
            console.warn(`THD exceeds target: ${thd}`);
        }
    }

    private calculateArrayGeometry(position: HRTFPosition): Float32Array[] {
        // Calculate microphone array positions based on spatial position
        const radius = 0.05; // 5cm radius
        const numMics = 8;
        return Array(numMics).fill(null).map((_, i) => {
            const angle = (2 * Math.PI * i) / numMics;
            return new Float32Array([
                radius * Math.cos(angle),
                radius * Math.sin(angle),
                0
            ]);
        });
    }

    private nextPowerOfTwo(value: number): number {
        return Math.pow(2, Math.ceil(Math.log2(value)));
    }

    private padArray(array: Float32Array, length: number): Float32Array {
        const padded = new Float32Array(length);
        padded.set(array);
        return padded;
    }

    private handleProcessingError(error: Error): void {
        console.error('Spatial processing error:', error);
        // Implement error recovery strategy
    }

    private handlePositionUpdateError(error: Error): void {
        console.error('Position update error:', error);
        // Implement position recovery strategy
    }

    private handleDatasetLoadError(error: Error): void {
        console.error('Dataset load error:', error);
        // Implement dataset fallback strategy
    }
}