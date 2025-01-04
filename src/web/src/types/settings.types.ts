/**
 * @file Type definitions for TALD UNIA Audio System settings
 * @version 1.0.0
 * 
 * Comprehensive type definitions for hardware configuration, audio processing,
 * AI enhancement, and spatial audio settings with strict validation.
 */

/**
 * Audio processing quality level options with performance implications
 */
export enum ProcessingQuality {
    MAXIMUM = "MAXIMUM",
    BALANCED = "BALANCED",
    POWER_SAVER = "POWER_SAVER"
}

/**
 * Valid sample rate options for the audio system (in Hz)
 */
export type SampleRate = 44100 | 48000 | 96000 | 192000;

/**
 * Valid bit depth options for audio processing
 */
export type BitDepth = 16 | 24 | 32;

/**
 * Valid buffer size options for audio processing (in samples)
 */
export type BufferSize = 64 | 128 | 256 | 512 | 1024;

/**
 * Hardware-level audio configuration settings with strict validation
 */
export interface HardwareConfig {
    /** Current sample rate setting */
    sampleRate: SampleRate;
    /** Current bit depth setting */
    bitDepth: BitDepth;
    /** Audio processing buffer size */
    bufferSize: BufferSize;
    /** Unique identifier for the audio device */
    deviceId: string;
    /** Human-readable device name */
    deviceName: string;
    /** Maximum number of supported audio channels */
    maxChannels: number;
}

/**
 * Audio processing and AI enhancement configuration with comprehensive settings
 */
export interface ProcessingConfig {
    /** Selected processing quality level */
    quality: ProcessingQuality;
    /** Enable/disable local AI processing */
    localAIEnabled: boolean;
    /** Enable/disable cloud-based processing */
    cloudProcessingEnabled: boolean;
    /** Enable/disable automatic room calibration */
    roomCalibrationEnabled: boolean;
    /** Number of threads allocated for AI inference */
    inferenceThreads: number;
    /** AI enhancement intensity (0-100) */
    enhancementLevel: number;
}

/**
 * Spatial audio and room modeling configuration with detailed parameters
 */
export interface SpatialConfig {
    /** Enable/disable head tracking for spatial audio */
    headTrackingEnabled: boolean;
    /** Selected HRTF profile identifier */
    hrtfProfile: string;
    /** Virtual room size in cubic meters */
    roomSize: number;
    /** Reverb time (RT60) in seconds */
    reverbTime: number;
    /** Wall absorption coefficient (0-1) */
    wallAbsorption: number;
    /** 3D listener position coordinates */
    listenerPosition: {
        x: number;
        y: number;
        z: number;
    };
}

/**
 * Combined system-wide settings interface with version tracking
 */
export interface SystemSettings {
    /** Hardware configuration settings */
    hardware: HardwareConfig;
    /** Audio processing configuration */
    processing: ProcessingConfig;
    /** Spatial audio configuration */
    spatial: SpatialConfig;
    /** Settings schema version */
    version: string;
    /** Last settings update timestamp */
    lastUpdated: Date;
}