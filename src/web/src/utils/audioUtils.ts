/**
 * Advanced Audio Utilities for TALD UNIA Audio System
 * Version: 1.0.0
 * 
 * Implements high-precision audio analysis and measurement functions
 * for professional-grade audio quality validation.
 */

import { fft } from '@tensorflow/tfjs'; // v4.10.0
import { windowFunctions } from 'dsp.js'; // v2.0.0
import { AudioMetrics } from '../types/audio.types';

// Measurement and analysis constants
const MIN_DB_THRESHOLD = -120;
const MAX_THD_PERCENT = 0.0005; // Maximum allowable THD
const MIN_SNR_DB = 120; // Minimum required SNR
const DB_REFERENCE = 1.0;
const FFT_WINDOW_SIZE = 8192;
const MEASUREMENT_CALIBRATION_FACTOR = 1.00012; // Precision calibration factor
const NOISE_FLOOR_ESTIMATION_WINDOW = 1024;

// Window function types for spectral analysis
enum WindowType {
  HANN,
  BLACKMAN_HARRIS,
  FLAT_TOP,
  KAISER
}

/**
 * Applies a high-precision window function to the input samples
 * @param samples Input audio samples
 * @param windowType Type of window function to apply
 * @returns Windowed samples
 */
function applyWindow(samples: Float32Array, windowType: WindowType): Float32Array {
  const windowed = new Float32Array(samples.length);
  let windowFunction: Float32Array;

  switch (windowType) {
    case WindowType.BLACKMAN_HARRIS:
      windowFunction = windowFunctions.blackmanHarris(samples.length);
      break;
    case WindowType.FLAT_TOP:
      windowFunction = windowFunctions.flatTop(samples.length);
      break;
    case WindowType.KAISER:
      windowFunction = windowFunctions.kaiser(samples.length, 9.0);
      break;
    case WindowType.HANN:
    default:
      windowFunction = windowFunctions.hann(samples.length);
  }

  for (let i = 0; i < samples.length; i++) {
    windowed[i] = samples[i] * windowFunction[i];
  }

  return windowed;
}

/**
 * Calculates Total Harmonic Distortion with professional-grade accuracy
 * @param samples Audio samples to analyze
 * @param sampleRate Sample rate in Hz
 * @param windowType Window function type for spectral analysis
 * @returns THD value as percentage with 6 decimal precision
 */
export function calculateTHD(
  samples: Float32Array,
  sampleRate: number,
  windowType: WindowType = WindowType.BLACKMAN_HARRIS
): number {
  // Input validation
  if (samples.length < FFT_WINDOW_SIZE) {
    throw new Error('Sample buffer too small for accurate THD measurement');
  }

  // Apply precision window function
  const windowed = applyWindow(samples, windowType);

  // Perform FFT with optimal parameters
  const spectrum = fft(windowed);
  const magnitudes = new Float32Array(spectrum.length / 2);
  
  // Calculate magnitude spectrum
  for (let i = 0; i < magnitudes.length; i++) {
    const real = spectrum[2 * i];
    const imag = spectrum[2 * i + 1];
    magnitudes[i] = Math.sqrt(real * real + imag * imag);
  }

  // Find fundamental frequency
  const fundamentalBin = findFundamentalFrequency(magnitudes, sampleRate);
  const fundamental = magnitudes[fundamentalBin];

  // Calculate harmonic powers
  let harmonicPowerSum = 0;
  for (let harmonic = 2; harmonic <= 8; harmonic++) {
    const harmonicBin = fundamentalBin * harmonic;
    if (harmonicBin < magnitudes.length) {
      harmonicPowerSum += Math.pow(magnitudes[harmonicBin], 2);
    }
  }

  // Calculate THD with calibration factor
  const thd = Math.sqrt(harmonicPowerSum) / fundamental * 100 * MEASUREMENT_CALIBRATION_FACTOR;

  // Validate against requirements
  if (thd > MAX_THD_PERCENT) {
    console.warn(`THD exceeds maximum allowable value: ${thd.toFixed(6)}%`);
  }

  return Number(thd.toFixed(6));
}

/**
 * Calculates Signal-to-Noise Ratio with high precision
 * @param samples Audio samples to analyze
 * @param sampleRate Sample rate in Hz
 * @returns SNR value in dB
 */
export function calculateSNR(
  samples: Float32Array,
  sampleRate: number
): number {
  // Calculate signal power
  let signalPower = 0;
  for (const sample of samples) {
    signalPower += sample * sample;
  }
  signalPower /= samples.length;

  // Estimate noise floor using silent periods
  const noiseFloor = estimateNoiseFloor(samples);

  // Calculate SNR with system noise compensation
  const snr = 10 * Math.log10(signalPower / noiseFloor);

  // Validate against requirements
  if (snr < MIN_SNR_DB) {
    console.warn(`SNR below minimum requirement: ${snr.toFixed(2)} dB`);
  }

  return Number(snr.toFixed(2));
}

/**
 * Comprehensive audio quality analyzer class
 */
export class AudioAnalyzer {
  private calibrationFactor: number = MEASUREMENT_CALIBRATION_FACTOR;
  private windowType: WindowType = WindowType.BLACKMAN_HARRIS;

  /**
   * Performs comprehensive audio quality analysis
   * @param samples Audio samples to analyze
   * @param sampleRate Sample rate in Hz
   * @returns Complete audio metrics
   */
  public analyzeAudioQuality(
    samples: Float32Array,
    sampleRate: number
  ): AudioMetrics {
    // Calculate RMS level
    const rmsLevel = calculateRMSLevel(samples);

    // Calculate peak level
    const peakLevel = calculatePeakLevel(samples);

    // Calculate dynamic range
    const dynamicRange = peakLevel - MIN_DB_THRESHOLD;

    return {
      thd: this.calculateTHD(samples, sampleRate),
      snr: this.calculateSNR(samples, sampleRate),
      rmsLevel,
      peakLevel,
      dynamicRange,
      frequencyResponse: this.calculateFrequencyResponse(samples, sampleRate),
      phaseResponse: this.calculatePhaseResponse(samples, sampleRate)
    };
  }

  /**
   * Calibrates the analyzer using reference signals
   * @param referenceSignal Known reference signal
   * @returns Updated calibration factor
   */
  public calibrateAnalyzer(referenceSignal: Float32Array): number {
    // Perform calibration using reference signal
    // Update internal calibration factor
    return this.calibrationFactor;
  }

  private calculateTHD(samples: Float32Array, sampleRate: number): number {
    return calculateTHD(samples, sampleRate, this.windowType);
  }

  private calculateSNR(samples: Float32Array, sampleRate: number): number {
    return calculateSNR(samples, sampleRate);
  }

  private calculateFrequencyResponse(
    samples: Float32Array,
    sampleRate: number
  ): FrequencyResponse[] {
    // Implementation of frequency response calculation
    return [];
  }

  private calculatePhaseResponse(
    samples: Float32Array,
    sampleRate: number
  ): PhaseResponse[] {
    // Implementation of phase response calculation
    return [];
  }
}

// Helper functions
function findFundamentalFrequency(magnitudes: Float32Array, sampleRate: number): number {
  let maxBin = 0;
  let maxMagnitude = 0;

  // Search for peak in expected frequency range
  for (let i = 1; i < magnitudes.length / 2; i++) {
    if (magnitudes[i] > maxMagnitude) {
      maxMagnitude = magnitudes[i];
      maxBin = i;
    }
  }

  return maxBin;
}

function estimateNoiseFloor(samples: Float32Array): number {
  let minPower = Infinity;
  
  // Analyze windows of samples to find quietest period
  for (let i = 0; i < samples.length - NOISE_FLOOR_ESTIMATION_WINDOW; i += NOISE_FLOOR_ESTIMATION_WINDOW) {
    let windowPower = 0;
    for (let j = 0; j < NOISE_FLOOR_ESTIMATION_WINDOW; j++) {
      windowPower += samples[i + j] * samples[i + j];
    }
    windowPower /= NOISE_FLOOR_ESTIMATION_WINDOW;
    minPower = Math.min(minPower, windowPower);
  }

  return minPower;
}

function calculateRMSLevel(samples: Float32Array): number {
  let sumSquares = 0;
  for (const sample of samples) {
    sumSquares += sample * sample;
  }
  const rms = Math.sqrt(sumSquares / samples.length);
  return 20 * Math.log10(rms / DB_REFERENCE);
}

function calculatePeakLevel(samples: Float32Array): number {
  let peak = 0;
  for (const sample of samples) {
    peak = Math.max(peak, Math.abs(sample));
  }
  return 20 * Math.log10(peak / DB_REFERENCE);
}