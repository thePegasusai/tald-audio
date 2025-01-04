/**
 * @fileoverview Defines configuration interfaces for AI models used in TALD UNIA audio processing
 * @version 1.0.0
 */

/**
 * Supported AI model types for different audio processing tasks
 */
export enum ModelType {
  /** AI-driven audio enhancement processing */
  AUDIO_ENHANCEMENT = 'AUDIO_ENHANCEMENT',
  /** Room acoustic correction and calibration */
  ROOM_CORRECTION = 'ROOM_CORRECTION',
  /** Spatial audio processing and positioning */
  SPATIAL_PROCESSING = 'SPATIAL_PROCESSING'
}

/**
 * Supported hardware acceleration types for optimal processing performance
 */
export enum AcceleratorType {
  /** CPU-based processing */
  CPU = 'CPU',
  /** GPU acceleration via CUDA/OpenCL */
  GPU = 'GPU',
  /** Google TPU acceleration */
  TPU = 'TPU'
}

/**
 * Comprehensive interface defining audio processing parameters for AI models
 */
export interface ModelParameters {
  /** Audio sample rate in Hz (e.g. 44100, 48000, 96000) */
  sampleRate: number;

  /** Processing frame size in samples */
  frameSize: number;

  /** Number of audio channels */
  channels: number;

  /** AI enhancement intensity level (0-100) */
  enhancementLevel: number;

  /** Target processing latency in milliseconds */
  latencyTarget: number;

  /** Buffer management strategy ('fixed' | 'dynamic' | 'adaptive') */
  bufferStrategy: string;

  /** Processing priority ('realtime' | 'quality' | 'balanced') */
  processingPriority: string;
}

/**
 * Main configuration interface for AI models with complete settings
 */
export interface ModelConfig {
  /** Unique identifier for the model */
  modelId: string;

  /** Model version string (semver) */
  version: string;

  /** Type of AI model processing */
  type: ModelType;

  /** Hardware acceleration configuration */
  accelerator: AcceleratorType;

  /** Model processing parameters */
  parameters: ModelParameters;

  /** Fallback configuration for degraded operation */
  fallbackConfig?: Partial<ModelParameters>;
}