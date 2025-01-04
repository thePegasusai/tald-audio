/**
 * Test Suite for TALD UNIA Audio System Audio Utilities
 * Version: 1.0.0
 * 
 * Comprehensive test coverage for audio processing calculations,
 * quality metrics, and performance validation
 */

import { describe, it, expect, beforeEach, jest } from '@jest/globals';
import {
  AudioAnalyzer,
  calculateTHD,
  calculateSNR,
  calculateRMSLevel,
  calculatePeakLevel,
  getAudioMetrics
} from '../../src/utils/audioUtils';
import { ProcessingQuality, AudioMetrics } from '../../src/types/audio.types';

// Test configuration constants
const TEST_SAMPLE_RATES = [44100, 48000, 96000, 192000];
const TEST_DURATIONS = [0.1, 1.0, 10.0];
const TEST_FREQUENCIES = [20, 1000, 20000];
const NOISE_FLOOR_DB = -120;
const MAX_THD_PERCENT = 0.0005;
const MIN_SNR_DB = 120;
const PERFORMANCE_TIMEOUT_MS = 1000;

/**
 * Generates calibrated test signals for audio analysis
 */
function generateTestSignal(
  frequency: number,
  amplitude: number,
  sampleRate: number,
  duration: number,
  options: { harmonics?: { frequency: number, amplitude: number }[] } = {}
): Float32Array {
  const numSamples = Math.floor(sampleRate * duration);
  const signal = new Float32Array(numSamples);
  const angularFreq = 2 * Math.PI * frequency;

  // Generate primary sine wave
  for (let i = 0; i < numSamples; i++) {
    signal[i] = amplitude * Math.sin(angularFreq * i / sampleRate);
  }

  // Add harmonics if specified
  if (options.harmonics) {
    options.harmonics.forEach(harmonic => {
      const harmonicFreq = 2 * Math.PI * harmonic.frequency;
      for (let i = 0; i < numSamples; i++) {
        signal[i] += harmonic.amplitude * Math.sin(harmonicFreq * i / sampleRate);
      }
    });
  }

  return signal;
}

/**
 * Adds calibrated noise to test signals
 */
function addNoise(
  signal: Float32Array,
  noiseLevel: number,
  noiseProfile: { type: 'white' | 'pink' | 'gaussian' } = { type: 'white' }
): Float32Array {
  const noisySignal = new Float32Array(signal.length);
  
  for (let i = 0; i < signal.length; i++) {
    let noise = 0;
    switch (noiseProfile.type) {
      case 'gaussian':
        noise = (Math.random() + Math.random() + Math.random() - 1.5) * noiseLevel;
        break;
      case 'pink':
        // Simplified pink noise approximation
        noise = (Math.random() - 0.5) * noiseLevel / Math.sqrt(i + 1);
        break;
      default: // white
        noise = (Math.random() - 0.5) * noiseLevel;
    }
    noisySignal[i] = signal[i] + noise;
  }

  return noisySignal;
}

describe('AudioAnalyzer Class', () => {
  let analyzer: AudioAnalyzer;

  beforeEach(() => {
    analyzer = new AudioAnalyzer();
  });

  it('should initialize properly with different sample rates', () => {
    TEST_SAMPLE_RATES.forEach(sampleRate => {
      const signal = generateTestSignal(1000, 0.5, sampleRate, 0.1);
      expect(() => analyzer.analyzeAudioQuality(signal, sampleRate)).not.toThrow();
    });
  });

  it('should perform accurate calibration', () => {
    const referenceSignal = generateTestSignal(1000, 1.0, 48000, 1.0);
    const calibrationFactor = analyzer.calibrateAnalyzer(referenceSignal);
    expect(calibrationFactor).toBeCloseTo(1.0, 5);
  });

  it('should maintain calibration across multiple analyses', () => {
    const signal = generateTestSignal(1000, 0.5, 48000, 1.0);
    const firstAnalysis = analyzer.analyzeAudioQuality(signal, 48000);
    const secondAnalysis = analyzer.analyzeAudioQuality(signal, 48000);
    expect(firstAnalysis.thd).toBeCloseTo(secondAnalysis.thd, 6);
    expect(firstAnalysis.snr).toBeCloseTo(secondAnalysis.snr, 2);
  });
});

describe('calculateTHD', () => {
  it('should calculate THD for pure sine waves', () => {
    TEST_FREQUENCIES.forEach(freq => {
      const signal = generateTestSignal(freq, 0.5, 48000, 1.0);
      const thd = calculateTHD(signal, 48000);
      expect(thd).toBeLessThan(MAX_THD_PERCENT);
    });
  });

  it('should detect harmonic distortion accurately', () => {
    const signal = generateTestSignal(1000, 0.5, 48000, 1.0, {
      harmonics: [
        { frequency: 2000, amplitude: 0.0001 },
        { frequency: 3000, amplitude: 0.00005 }
      ]
    });
    const thd = calculateTHD(signal, 48000);
    expect(thd).toBeCloseTo(0.00022361, 6);
  });

  it('should handle different sample rates', () => {
    TEST_SAMPLE_RATES.forEach(sampleRate => {
      const signal = generateTestSignal(1000, 0.5, sampleRate, 1.0);
      expect(() => calculateTHD(signal, sampleRate)).not.toThrow();
    });
  });
});

describe('calculateSNR', () => {
  it('should calculate SNR for clean signals', () => {
    TEST_FREQUENCIES.forEach(freq => {
      const signal = generateTestSignal(freq, 0.5, 48000, 1.0);
      const snr = calculateSNR(signal, 48000);
      expect(snr).toBeGreaterThan(MIN_SNR_DB);
    });
  });

  it('should handle signals with known noise', () => {
    const cleanSignal = generateTestSignal(1000, 0.5, 48000, 1.0);
    const noisySignal = addNoise(cleanSignal, 0.0001);
    const snr = calculateSNR(noisySignal, 48000);
    expect(snr).toBeCloseTo(120, 0);
  });

  it('should validate noise floor measurements', () => {
    const signal = generateTestSignal(1000, 0.5, 48000, 1.0);
    const noisySignal = addNoise(signal, 0.000001, { type: 'gaussian' });
    const snr = calculateSNR(noisySignal, 48000);
    expect(snr).toBeGreaterThan(MIN_SNR_DB);
  });
});

describe('Performance Validation', () => {
  it('should complete calculations within timeout period', () => {
    const signal = generateTestSignal(1000, 0.5, 192000, 10.0);
    
    const start = performance.now();
    const metrics = analyzer.analyzeAudioQuality(signal, 192000);
    const duration = performance.now() - start;

    expect(duration).toBeLessThan(PERFORMANCE_TIMEOUT_MS);
  });

  it('should maintain accuracy under CPU load', async () => {
    const signal = generateTestSignal(1000, 0.5, 48000, 1.0);
    const baselineMetrics = analyzer.analyzeAudioQuality(signal, 48000);

    // Simulate CPU load
    const loadPromises = Array(4).fill(0).map(() => 
      new Promise(resolve => {
        const loadSignal = generateTestSignal(1000, 0.5, 48000, 1.0);
        resolve(analyzer.analyzeAudioQuality(loadSignal, 48000));
      })
    );

    const loadMetrics = await Promise.all(loadPromises);
    loadMetrics.forEach(metrics => {
      expect(metrics.thd).toBeCloseTo(baselineMetrics.thd, 6);
      expect(metrics.snr).toBeCloseTo(baselineMetrics.snr, 2);
    });
  });

  it('should handle memory efficiently', () => {
    const initialMemory = process.memoryUsage().heapUsed;
    
    // Process multiple large signals
    TEST_DURATIONS.forEach(duration => {
      const signal = generateTestSignal(1000, 0.5, 192000, duration);
      analyzer.analyzeAudioQuality(signal, 192000);
    });

    const memoryIncrease = process.memoryUsage().heapUsed - initialMemory;
    expect(memoryIncrease).toBeLessThan(50 * 1024 * 1024); // 50MB limit
  });
});