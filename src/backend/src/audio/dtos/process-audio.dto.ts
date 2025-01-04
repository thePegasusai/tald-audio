/**
 * Data Transfer Object (DTO) for audio processing requests in TALD UNIA Audio System
 * Implements comprehensive validation for audio processing parameters with hardware-specific constraints
 * @version 1.0.0
 */

import { 
    IsNotEmpty, IsNumber, IsEnum, IsBoolean, ValidateNested, 
    IsOptional, Min, Max, IsInt, ArrayMinSize, ArrayMaxSize, 
    IsBuffer 
} from 'class-validator'; // v0.14.0
import { Type, Transform } from 'class-transformer'; // v0.5.1
import {
    AudioConfig, ProcessingQuality, DSPConfig, AIConfig, SpatialConfig,
    DEFAULT_SAMPLE_RATE, DEFAULT_BIT_DEPTH, DEFAULT_BUFFER_SIZE,
    MIN_LATENCY_MS, MAX_LATENCY_MS, THD_TARGET
} from '../interfaces/audio-config.interface';

// Hardware-specific constraints based on ESS ES9038PRO DAC
const MIN_SAMPLE_RATE = 44100;
const MAX_SAMPLE_RATE = 192000;
const MIN_BIT_DEPTH = 16;
const MAX_BIT_DEPTH = 32;
const MIN_BUFFER_SIZE = 64;
const MAX_BUFFER_SIZE = 8192;
const MAX_PROCESSING_LATENCY = 10; // ms

/**
 * Sanitizes and validates incoming audio buffer data
 * @param value Raw audio buffer data
 * @returns Sanitized buffer or null if invalid
 */
function sanitizeAudioData(value: any): Buffer | null {
    if (!Buffer.isBuffer(value)) {
        return null;
    }
    // Ensure buffer size meets hardware requirements
    if (value.length < MIN_BUFFER_SIZE || value.length > MAX_BUFFER_SIZE) {
        return null;
    }
    return value;
}

export class ProcessAudioDto implements Partial<AudioConfig> {
    @IsNotEmpty()
    @IsInt()
    @Min(MIN_SAMPLE_RATE)
    @Max(MAX_SAMPLE_RATE)
    readonly sampleRate: number = DEFAULT_SAMPLE_RATE;

    @IsNotEmpty()
    @IsInt()
    @Min(MIN_BIT_DEPTH)
    @Max(MAX_BIT_DEPTH)
    readonly bitDepth: number = DEFAULT_BIT_DEPTH;

    @IsNotEmpty()
    @IsEnum(ProcessingQuality)
    readonly processingQuality: ProcessingQuality = ProcessingQuality.Balanced;

    @IsOptional()
    @ValidateNested()
    @Type(() => Object)
    readonly dspConfig?: DSPConfig;

    @IsOptional()
    @ValidateNested()
    @Type(() => Object)
    readonly aiConfig?: AIConfig;

    @IsOptional()
    @ValidateNested()
    @Type(() => Object)
    readonly spatialConfig?: SpatialConfig;

    @IsNotEmpty()
    @IsBuffer()
    @Transform(({ value }) => sanitizeAudioData(value))
    readonly audioData: Buffer;

    @IsNotEmpty()
    @IsInt()
    @Min(MIN_BUFFER_SIZE)
    @Max(MAX_BUFFER_SIZE)
    readonly bufferSize: number = DEFAULT_BUFFER_SIZE;

    @IsNumber()
    @Min(MIN_LATENCY_MS)
    @Max(MAX_PROCESSING_LATENCY)
    readonly expectedLatency: number = MIN_LATENCY_MS;

    /**
     * Validates audio buffer compatibility with hardware requirements
     * @param buffer Audio buffer to validate
     * @returns boolean indicating validation result
     */
    validateAudioBuffer(buffer: Buffer): boolean {
        if (!buffer || buffer.length < this.bufferSize) {
            return false;
        }

        // Validate buffer alignment with sample rate and bit depth
        const bytesPerSample = this.bitDepth / 8;
        const expectedBufferSize = this.bufferSize * bytesPerSample;
        if (buffer.length % expectedBufferSize !== 0) {
            return false;
        }

        // Validate buffer format compatibility with ESS ES9038PRO DAC
        const maxAmplitude = Math.pow(2, this.bitDepth - 1);
        for (let i = 0; i < buffer.length; i += bytesPerSample) {
            const sample = buffer.readIntLE(i, bytesPerSample);
            if (Math.abs(sample) > maxAmplitude) {
                return false;
            }
        }

        return true;
    }
}