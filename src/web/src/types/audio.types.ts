/**
 * Core TypeScript type definitions for the TALD UNIA Audio System web client
 * Version: 1.0.0
 */

// Global constants for audio system configuration
export const DEFAULT_SAMPLE_RATE = 192000;
export const DEFAULT_BIT_DEPTH = 32;
export const DEFAULT_CHANNELS = 2;
export const DEFAULT_BUFFER_SIZE = 256;
export const MIN_LATENCY_MS = 10;
export const MAX_THD = 0.0005;
export const MIN_SNR_DB = 120;
export const MAX_PROCESSING_LOAD = 0.4;
export const HRTF_UPDATE_INTERVAL_MS = 100;
export const SPATIAL_PROCESSING_INTERVAL_MS = 16;

/**
 * Available audio processing quality levels
 */
export enum ProcessingQuality {
    Maximum = 'MAXIMUM',
    Balanced = 'BALANCED',
    PowerSaver = 'POWER_SAVER'
}

/**
 * Core audio configuration parameters
 */
export interface AudioConfig {
    sampleRate: number;
    bitDepth: number;
    channels: number;
    bufferSize: number;
    processingQuality: ProcessingQuality;
}

/**
 * AI processing status tracking
 */
export interface AIProcessingStatus {
    enabled: boolean;
    modelVersion: string;
    enhancementLevel: number;
    processingLoad: number;
    lastUpdateTimestamp: number;
}

/**
 * Real-time audio processing state
 */
export interface AudioProcessingState {
    isProcessing: boolean;
    currentLoad: number;
    bufferHealth: number;
    latency: number;
    aiProcessingStatus: AIProcessingStatus;
    dspUtilization: number;
    spatialProcessingActive: boolean;
}

/**
 * Frequency response data point
 */
export interface FrequencyResponse {
    frequency: number;
    magnitude: number;
    phase: number;
}

/**
 * Phase response data point
 */
export interface PhaseResponse {
    frequency: number;
    phase: number;
    groupDelay: number;
}

/**
 * Comprehensive audio quality metrics
 */
export interface AudioMetrics {
    thd: number;
    snr: number;
    rmsLevel: number;
    peakLevel: number;
    dynamicRange: number;
    frequencyResponse: FrequencyResponse[];
    phaseResponse: PhaseResponse[];
}

/**
 * 3D position for spatial audio
 */
export interface Position3D {
    x: number;
    y: number;
    z: number;
}

/**
 * Room dimensions for acoustic modeling
 */
export interface RoomDimensions {
    width: number;
    height: number;
    depth: number;
}

/**
 * Room material acoustic properties
 */
export interface RoomMaterial {
    surface: string;
    absorptionCoefficient: number;
    scatteringCoefficient: number;
}

/**
 * Acoustic reflection model types
 */
export enum ReflectionModel {
    ImageSource = 'IMAGE_SOURCE',
    RayTracing = 'RAY_TRACING',
    Hybrid = 'HYBRID'
}

/**
 * Comprehensive spatial audio configuration
 */
export interface SpatialAudioConfig {
    enableSpatial: boolean;
    roomSize: RoomDimensions;
    listenerPosition: Position3D;
    hrtfEnabled: boolean;
    hrtfProfile: string;
    roomMaterials: RoomMaterial[];
    reflectionModel: ReflectionModel;
}

/**
 * Hardware device capabilities
 */
export interface DeviceCapabilities {
    maxSampleRate: number;
    maxBitDepth: number;
    maxChannels: number;
    minBufferSize: number;
    maxBufferSize: number;
    supportsHRTF: boolean;
    supportsSpatialAudio: boolean;
    supportsAIProcessing: boolean;
}

/**
 * Audio processing error types
 */
export enum AudioProcessingError {
    BufferUnderrun = 'BUFFER_UNDERRUN',
    ProcessingOverload = 'PROCESSING_OVERLOAD',
    DeviceError = 'DEVICE_ERROR',
    ConfigurationError = 'CONFIGURATION_ERROR',
    AIProcessingError = 'AI_PROCESSING_ERROR'
}

/**
 * Audio processing event types
 */
export enum AudioProcessingEvent {
    QualityChange = 'QUALITY_CHANGE',
    StateChange = 'STATE_CHANGE',
    MetricsUpdate = 'METRICS_UPDATE',
    Error = 'ERROR',
    Warning = 'WARNING'
}

/**
 * Audio processing event payload
 */
export interface AudioProcessingEventPayload {
    type: AudioProcessingEvent;
    timestamp: number;
    data: any;
    source: string;
}