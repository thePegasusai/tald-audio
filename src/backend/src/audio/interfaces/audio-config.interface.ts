/**
 * Core interface definitions for TALD UNIA Audio System configuration
 * Implements enterprise-grade audio processing configuration with strict type safety
 * @version 1.0.0
 */

/**
 * Audio processing quality levels with CPU usage implications
 */
export enum ProcessingQuality {
    Maximum = 'MAXIMUM',      // Highest quality, highest CPU usage
    Balanced = 'BALANCED',    // Balanced quality/CPU trade-off
    PowerSaver = 'POWER_SAVER' // Lowest CPU usage, reduced quality
}

/**
 * EQ filter types supported by the system
 */
export enum EQFilterType {
    Peak = 'PEAK',
    LowShelf = 'LOW_SHELF',
    HighShelf = 'HIGH_SHELF',
    LowPass = 'LOW_PASS',
    HighPass = 'HIGH_PASS',
    Notch = 'NOTCH'
}

/**
 * AI processing modes for enhancement pipeline
 */
export enum AIProcessingMode {
    RealTime = 'REAL_TIME',   // Lowest latency, reduced quality
    Balanced = 'BALANCED',    // Balance between quality and latency
    HighQuality = 'HIGH_QUALITY' // Maximum quality, increased latency
}

// System constants
export const DEFAULT_SAMPLE_RATE = 192000;
export const DEFAULT_BIT_DEPTH = 32;
export const DEFAULT_CHANNELS = 2;
export const DEFAULT_BUFFER_SIZE = 256;
export const MAX_EQ_BANDS = 31;
export const MIN_LATENCY_MS = 1;
export const MAX_LATENCY_MS = 10;
export const THD_TARGET = 0.0005;
export const MAX_ENHANCEMENT_STRENGTH = 1.0;

/**
 * Core audio configuration interface
 * Defines hardware-level audio parameters with strict validation
 */
export interface AudioConfig {
    readonly sampleRate: number;      // Sample rate in Hz (up to 192kHz)
    readonly bitDepth: number;        // Bit depth (up to 32-bit)
    readonly channels: number;        // Number of audio channels
    readonly bufferSize: number;      // Buffer size in samples
    readonly processingQuality: ProcessingQuality;
    readonly deviceId: string;        // Unique identifier for audio device
    readonly latencyTarget: number;   // Target latency in milliseconds
}

/**
 * Equalizer band configuration
 * Defines parameters for a single EQ band with validation ranges
 */
export interface EQBand {
    readonly frequency: number;   // Center frequency in Hz (20Hz-20kHz)
    readonly gain: number;        // Gain in dB (-12 to +12)
    readonly q: number;          // Q factor (0.1 to 10.0)
    readonly type: EQFilterType;  // Filter type
}

/**
 * Dynamic range compressor settings
 * Defines precise compressor parameters with quality constraints
 */
export interface CompressorSettings {
    readonly threshold: number;   // Threshold in dB (-60 to 0)
    readonly ratio: number;       // Compression ratio (1 to 20)
    readonly attack: number;      // Attack time in ms (0.1 to 100)
    readonly release: number;     // Release time in ms (10 to 1000)
    readonly makeupGain: number;  // Makeup gain in dB (0 to 24)
    readonly kneeWidth: number;   // Knee width in dB (0 to 40)
}

/**
 * Room correction configuration
 * Defines parameters for acoustic room compensation
 */
export interface RoomCorrectionConfig {
    readonly enabled: boolean;
    readonly roomSize: number;        // Room size in cubic meters
    readonly reflectivity: number;    // Room surface reflectivity (0-1)
    readonly dampingFactor: number;   // Room damping factor (0-1)
    readonly speakerPositions: ReadonlyArray<{ x: number; y: number; z: number }>;
    readonly measurementPoints: ReadonlyArray<{ x: number; y: number; z: number }>;
}

/**
 * DSP processing configuration
 * Defines comprehensive DSP chain settings with quality safeguards
 */
export interface DSPConfig {
    readonly enableEQ: boolean;
    readonly eqBands: ReadonlyArray<EQBand>;
    readonly enableCompression: boolean;
    readonly compressorSettings: Readonly<CompressorSettings>;
    readonly enableRoomCorrection: boolean;
    readonly roomConfig: Readonly<RoomCorrectionConfig>;
    readonly thdCompensation: boolean;    // THD compensation for high quality
}

/**
 * AI enhancement configuration
 * Defines AI processing parameters with performance constraints
 */
export interface AIConfig {
    readonly enableEnhancement: boolean;
    readonly modelType: string;           // AI model identifier
    readonly enhancementStrength: number; // Enhancement level (0-1)
    readonly latencyBudget: number;       // Maximum allowed latency in ms
    readonly processingMode: AIProcessingMode;
}