/**
 * @fileoverview Type definitions for TALD UNIA audio visualization components
 * @version 1.0.0
 * @package standardized-audio-context ^25.3.0
 */

import { IAudioContext } from 'standardized-audio-context';

/**
 * Constants for visualization configuration defaults and limits
 */
export const DEFAULT_FFT_SIZE = 2048;
export const DEFAULT_SMOOTHING_TIME_CONSTANT = 0.8;
export const MIN_DECIBELS = -90;
export const MAX_DECIBELS = -10;
export const MIN_FREQUENCY = 20;
export const MAX_FREQUENCY = 20000;
export const DEFAULT_UPDATE_INTERVAL = 16.67; // ~60fps
export const DEFAULT_COLOR_SCHEME = 'spectrum';
export const MAX_BUFFER_SIZE = 8192;
export const MIN_LATENCY = 10;

/**
 * Interface representing spectrum analysis data with high-precision frequency representation
 */
export interface SpectrumData {
  /** Array of frequency values in Hz */
  frequencies: Float32Array;
  /** Array of magnitude values in dB */
  magnitudes: Float32Array;
  /** Timestamp of the analysis in milliseconds */
  timestamp: number;
  /** Sample rate of the audio context */
  sampleRate: number;
  /** Frequency resolution in Hz */
  resolution: number;
}

/**
 * Interface representing waveform visualization data with audio metrics
 */
export interface WaveformData {
  /** Array of audio samples */
  samples: Float32Array;
  /** Sample rate of the audio context */
  sampleRate: number;
  /** Number of audio channels */
  channels: number;
  /** Peak level in dB */
  peakLevel: number;
  /** RMS level in dB */
  rmsLevel: number;
}

/**
 * Interface for comprehensive visualization configuration
 */
export interface VisualizationConfig {
  /** FFT size for frequency analysis (power of 2) */
  fftSize: number;
  /** Smoothing time constant for analysis (0-1) */
  smoothingTimeConstant: number;
  /** Minimum decibel value for visualization */
  minDecibels: number;
  /** Maximum decibel value for visualization */
  maxDecibels: number;
  /** Minimum frequency to display (Hz) */
  minFrequency: number;
  /** Maximum frequency to display (Hz) */
  maxFrequency: number;
  /** Update interval in milliseconds */
  updateInterval: number;
  /** Color scheme identifier for visualization */
  colorScheme: string;
}

/**
 * Interface for comprehensive audio processing status metrics
 */
export interface ProcessingStatus {
  /** CPU load percentage (0-100) */
  cpuLoad: number;
  /** Current audio buffer size in samples */
  bufferSize: number;
  /** Current processing latency in milliseconds */
  latency: number;
  /** Total Harmonic Distortion plus Noise (%) */
  thdPlusN: number;
  /** Signal-to-Noise Ratio (dB) */
  signalToNoise: number;
  /** Power efficiency percentage (0-100) */
  powerEfficiency: number;
}

/**
 * Type guard to check if FFT size is valid (power of 2)
 */
export function isValidFFTSize(size: number): boolean {
  return size > 0 && (size & (size - 1)) === 0;
}

/**
 * Type guard to check if frequency is within valid range
 */
export function isValidFrequency(freq: number): boolean {
  return freq >= MIN_FREQUENCY && freq <= MAX_FREQUENCY;
}

/**
 * Type guard to check if decibel value is within valid range
 */
export function isValidDecibels(db: number): boolean {
  return db >= MIN_DECIBELS && db <= MAX_DECIBELS;
}

/**
 * Default visualization configuration
 */
export const DEFAULT_VISUALIZATION_CONFIG: VisualizationConfig = {
  fftSize: DEFAULT_FFT_SIZE,
  smoothingTimeConstant: DEFAULT_SMOOTHING_TIME_CONSTANT,
  minDecibels: MIN_DECIBELS,
  maxDecibels: MAX_DECIBELS,
  minFrequency: MIN_FREQUENCY,
  maxFrequency: MAX_FREQUENCY,
  updateInterval: DEFAULT_UPDATE_INTERVAL,
  colorScheme: DEFAULT_COLOR_SCHEME
};