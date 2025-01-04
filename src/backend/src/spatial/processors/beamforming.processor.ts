/**
 * TALD UNIA Audio System - Beamforming Processor
 * Version: 1.0.0
 * 
 * Implements advanced adaptive beamforming algorithms for spatial audio processing
 * with real-time noise suppression and dynamic beam pattern optimization.
 */

import { Injectable } from '@nestjs/common';
import { AudioConfig } from '../../audio/interfaces/audio-config.interface';
import { HRTFPosition } from '../interfaces/hrtf.interface';
import FFT from 'fft.js'; // v4.0.3
import * as numeric from 'numeric'; // v1.2.6

/**
 * Processing metrics for performance monitoring and optimization
 */
interface ProcessingMetrics {
    processingTime: number;
    noiseFloor: number;
    directivityIndex: number;
    adaptiveGain: number[];
}

@Injectable()
export class BeamformingProcessor {
    private readonly fftProcessor: FFT;
    private readonly microphonePositions: Float32Array[];
    private readonly steeringMatrix: Float32Array[][];
    private readonly adaptiveWeights: Float32Array[][];
    private readonly noiseEstimator: Float32Array;
    private readonly spatialCorrelation: Float32Array[][];
    private readonly circularBuffer: Float32Array[];
    private readonly processingMetrics: ProcessingMetrics;

    // Constants for beamforming optimization
    private static readonly NUM_MICROPHONES = 8;
    private static readonly NOISE_ESTIMATION_FRAMES = 32;
    private static readonly ADAPTATION_RATE = 0.01;
    private static readonly MIN_NOISE_FLOOR = -120; // dB
    private static readonly SPATIAL_SMOOTHING_FACTOR = 0.7;

    constructor(private readonly config: AudioConfig) {
        // Initialize FFT processor with optimal size
        this.fftProcessor = new FFT(this.config.bufferSize);

        // Initialize microphone array geometry (circular array configuration)
        this.microphonePositions = this.initializeMicrophoneArray();

        // Pre-allocate processing buffers
        this.steeringMatrix = this.createMatrix(BeamformingProcessor.NUM_MICROPHONES, this.config.bufferSize / 2);
        this.adaptiveWeights = this.createMatrix(BeamformingProcessor.NUM_MICROPHONES, this.config.bufferSize / 2);
        this.noiseEstimator = new Float32Array(this.config.bufferSize / 2);
        this.spatialCorrelation = this.createMatrix(BeamformingProcessor.NUM_MICROPHONES, BeamformingProcessor.NUM_MICROPHONES);
        this.circularBuffer = Array(BeamformingProcessor.NOISE_ESTIMATION_FRAMES)
            .fill(null)
            .map(() => new Float32Array(this.config.bufferSize));

        // Initialize processing metrics
        this.processingMetrics = {
            processingTime: 0,
            noiseFloor: BeamformingProcessor.MIN_NOISE_FLOOR,
            directivityIndex: 0,
            adaptiveGain: new Array(BeamformingProcessor.NUM_MICROPHONES).fill(0)
        };

        this.initializeAdaptiveWeights();
    }

    /**
     * Processes microphone array input with adaptive beamforming and noise suppression
     */
    public processFrame(inputFrames: Float32Array[], steeringDirection: HRTFPosition): Float32Array {
        const startTime = performance.now();

        // Validate input parameters
        if (inputFrames.length !== BeamformingProcessor.NUM_MICROPHONES) {
            throw new Error(`Invalid input: Expected ${BeamformingProcessor.NUM_MICROPHONES} channels`);
        }

        // Apply pre-emphasis filter
        const preemphasizedFrames = this.applyPreEmphasis(inputFrames);

        // Transform to frequency domain
        const frequencyFrames = preemphasizedFrames.map(frame => {
            const complexFrame = this.fftProcessor.createComplexArray();
            this.fftProcessor.realTransform(complexFrame, frame);
            return complexFrame;
        });

        // Update steering vectors based on direction
        this.updateSteeringVectors(steeringDirection);

        // Estimate noise floor
        this.updateNoiseEstimate(frequencyFrames);

        // Calculate and apply adaptive beamforming weights
        const enhancedSpectrum = this.applyAdaptiveBeamforming(frequencyFrames);

        // Transform back to time domain
        const outputFrame = this.fftProcessor.createComplexArray();
        this.fftProcessor.inverseTransform(outputFrame, enhancedSpectrum);

        // Apply post-processing and de-emphasis
        const processedFrame = this.applyPostProcessing(outputFrame);

        // Update processing metrics
        this.processingMetrics.processingTime = performance.now() - startTime;

        return processedFrame;
    }

    /**
     * Updates microphone array geometry with real-time calibration
     */
    public updateArrayGeometry(positions: Float32Array[]): void {
        if (positions.length !== BeamformingProcessor.NUM_MICROPHONES) {
            throw new Error('Invalid microphone array geometry');
        }

        this.microphonePositions.forEach((pos, idx) => {
            pos.set(positions[idx]);
        });

        this.recalculateSteeringMatrix();
        this.initializeAdaptiveWeights();
    }

    /**
     * Calculates and returns the current beamforming pattern
     */
    public calculateBeamPattern(frequency: number): Float32Array {
        const numAngles = 360;
        const pattern = new Float32Array(numAngles);

        for (let angle = 0; angle < numAngles; angle++) {
            const position: HRTFPosition = {
                azimuth: angle,
                elevation: 0,
                distance: 1
            };

            const steeringVector = this.calculateSteeringVector(position, frequency);
            pattern[angle] = this.calculateDirectivityResponse(steeringVector);
        }

        return pattern;
    }

    /**
     * Private helper methods
     */
    private initializeMicrophoneArray(): Float32Array[] {
        const radius = 0.05; // 5cm radius
        return Array(BeamformingProcessor.NUM_MICROPHONES)
            .fill(null)
            .map((_, idx) => {
                const angle = (2 * Math.PI * idx) / BeamformingProcessor.NUM_MICROPHONES;
                return new Float32Array([
                    radius * Math.cos(angle),
                    radius * Math.sin(angle),
                    0
                ]);
            });
    }

    private createMatrix(rows: number, cols: number): Float32Array[] {
        return Array(rows)
            .fill(null)
            .map(() => new Float32Array(cols));
    }

    private applyPreEmphasis(frames: Float32Array[]): Float32Array[] {
        const alpha = 0.97;
        return frames.map(frame => {
            const emphasized = new Float32Array(frame.length);
            emphasized[0] = frame[0];
            for (let i = 1; i < frame.length; i++) {
                emphasized[i] = frame[i] - alpha * frame[i - 1];
            }
            return emphasized;
        });
    }

    private updateSteeringVectors(direction: HRTFPosition): void {
        const frequencies = this.getFrequencyBins();
        frequencies.forEach((freq, idx) => {
            const steeringVector = this.calculateSteeringVector(direction, freq);
            for (let mic = 0; mic < BeamformingProcessor.NUM_MICROPHONES; mic++) {
                this.steeringMatrix[mic][idx] = steeringVector[mic];
            }
        });
    }

    private calculateSteeringVector(position: HRTFPosition, frequency: number): Float32Array {
        const vector = new Float32Array(BeamformingProcessor.NUM_MICROPHONES);
        const k = 2 * Math.PI * frequency / 343; // wavenumber (speed of sound = 343 m/s)

        this.microphonePositions.forEach((pos, idx) => {
            const delay = this.calculateTimeDelay(pos, position);
            vector[idx] = Math.exp(-1j * k * delay);
        });

        return vector;
    }

    private calculateTimeDelay(micPosition: Float32Array, source: HRTFPosition): number {
        const sourceVector = this.sphericalToCartesian(source);
        const distance = Math.sqrt(
            Math.pow(sourceVector[0] - micPosition[0], 2) +
            Math.pow(sourceVector[1] - micPosition[1], 2) +
            Math.pow(sourceVector[2] - micPosition[2], 2)
        );
        return distance / 343; // Time delay in seconds
    }

    private sphericalToCartesian(position: HRTFPosition): Float32Array {
        const azimuth = position.azimuth * Math.PI / 180;
        const elevation = position.elevation * Math.PI / 180;
        return new Float32Array([
            position.distance * Math.cos(elevation) * Math.cos(azimuth),
            position.distance * Math.cos(elevation) * Math.sin(azimuth),
            position.distance * Math.sin(elevation)
        ]);
    }

    private getFrequencyBins(): number[] {
        return Array(this.config.bufferSize / 2)
            .fill(0)
            .map((_, idx) => (idx * this.config.sampleRate) / this.config.bufferSize);
    }

    private initializeAdaptiveWeights(): void {
        for (let mic = 0; mic < BeamformingProcessor.NUM_MICROPHONES; mic++) {
            for (let freq = 0; freq < this.config.bufferSize / 2; freq++) {
                this.adaptiveWeights[mic][freq] = 1 / BeamformingProcessor.NUM_MICROPHONES;
            }
        }
    }

    private updateNoiseEstimate(frequencyFrames: Float32Array[]): void {
        // Implement minimum statistics noise estimation
        frequencyFrames.forEach((frame, freqIdx) => {
            const power = Math.pow(frame[0], 2) + Math.pow(frame[1], 2);
            this.noiseEstimator[freqIdx] = Math.min(
                power,
                this.noiseEstimator[freqIdx] * BeamformingProcessor.SPATIAL_SMOOTHING_FACTOR +
                power * (1 - BeamformingProcessor.SPATIAL_SMOOTHING_FACTOR)
            );
        });
    }

    private applyAdaptiveBeamforming(frequencyFrames: Float32Array[]): Float32Array {
        const output = this.fftProcessor.createComplexArray();
        const numFreqs = this.config.bufferSize / 2;

        for (let freq = 0; freq < numFreqs; freq++) {
            let sumReal = 0;
            let sumImag = 0;

            for (let mic = 0; mic < BeamformingProcessor.NUM_MICROPHONES; mic++) {
                const weight = this.adaptiveWeights[mic][freq];
                const steering = this.steeringMatrix[mic][freq];
                sumReal += weight * (frequencyFrames[mic][2 * freq] * steering);
                sumImag += weight * (frequencyFrames[mic][2 * freq + 1] * steering);
            }

            output[2 * freq] = sumReal;
            output[2 * freq + 1] = sumImag;

            // Update adaptive weights using MVDR algorithm
            this.updateAdaptiveWeights(freq, frequencyFrames);
        }

        return output;
    }

    private updateAdaptiveWeights(frequency: number, frames: Float32Array[]): void {
        // Implement MVDR (Minimum Variance Distortionless Response) beamforming
        const R = this.calculateSpatialCorrelation(frequency, frames);
        const steering = this.steeringMatrix.map(row => row[frequency]);
        
        // Calculate optimal weights using matrix operations
        const Rinv = numeric.inv(R);
        const numerator = numeric.dot(Rinv, steering);
        const denominator = numeric.dot(numeric.dot(steering, Rinv), steering);
        
        // Update weights with smoothing
        for (let mic = 0; mic < BeamformingProcessor.NUM_MICROPHONES; mic++) {
            const newWeight = numerator[mic] / denominator;
            this.adaptiveWeights[mic][frequency] = 
                this.adaptiveWeights[mic][frequency] * (1 - BeamformingProcessor.ADAPTATION_RATE) +
                newWeight * BeamformingProcessor.ADAPTATION_RATE;
        }
    }

    private calculateSpatialCorrelation(frequency: number, frames: Float32Array[]): number[][] {
        const R = Array(BeamformingProcessor.NUM_MICROPHONES)
            .fill(null)
            .map(() => Array(BeamformingProcessor.NUM_MICROPHONES).fill(0));

        for (let i = 0; i < BeamformingProcessor.NUM_MICROPHONES; i++) {
            for (let j = 0; j < BeamformingProcessor.NUM_MICROPHONES; j++) {
                const xi = frames[i][2 * frequency];
                const xj = frames[j][2 * frequency];
                R[i][j] = xi * xj;
            }
        }

        return R;
    }

    private calculateDirectivityResponse(steeringVector: Float32Array): number {
        let response = 0;
        for (let mic = 0; mic < BeamformingProcessor.NUM_MICROPHONES; mic++) {
            response += this.adaptiveWeights[mic][0] * steeringVector[mic];
        }
        return Math.abs(response);
    }

    private applyPostProcessing(frame: Float32Array): Float32Array {
        const processed = new Float32Array(frame.length / 2);
        
        // Apply de-emphasis filter
        const alpha = 0.97;
        processed[0] = frame[0];
        for (let i = 1; i < processed.length; i++) {
            processed[i] = frame[2 * i] + alpha * processed[i - 1];
        }

        // Normalize output
        const maxAmp = Math.max(...processed.map(Math.abs));
        if (maxAmp > 0) {
            for (let i = 0; i < processed.length; i++) {
                processed[i] /= maxAmp;
            }
        }

        return processed;
    }
}