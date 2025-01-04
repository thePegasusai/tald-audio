/**
 * @fileoverview Redux slice for TALD UNIA audio visualization state management
 * @version 1.0.0
 * @package @reduxjs/toolkit ^1.9.0
 */

import { createSlice, PayloadAction } from '@reduxjs/toolkit';
import {
  SpectrumData,
  ProcessingStatus,
  VisualizationConfig,
  DEFAULT_VISUALIZATION_CONFIG,
  isValidFFTSize,
  isValidFrequency,
  isValidDecibels,
  MIN_FREQUENCY,
  MAX_FREQUENCY
} from '../../types/visualization.types';

/**
 * Interface for the visualization state
 */
interface VisualizationState {
  spectrumData: SpectrumData | null;
  waveformData: Float32Array | null;
  processingStatus: ProcessingStatus;
  config: VisualizationConfig & {
    accessibilityMode: boolean;
  };
  lastUpdateTimestamp: number;
}

/**
 * Initial state with performance-optimized defaults
 */
const initialState: VisualizationState = {
  spectrumData: null,
  waveformData: null,
  processingStatus: {
    cpuLoad: 0,
    bufferSize: 0,
    latency: 0,
    thdPlusN: 0,
    signalToNoise: 0,
    powerEfficiency: 0
  },
  config: {
    ...DEFAULT_VISUALIZATION_CONFIG,
    accessibilityMode: false
  },
  lastUpdateTimestamp: 0
};

/**
 * Redux slice for visualization state management
 */
const visualizationSlice = createSlice({
  name: 'visualization',
  initialState,
  reducers: {
    /**
     * Updates spectrum analyzer data with performance optimization
     */
    updateSpectrumData: (state, action: PayloadAction<SpectrumData>) => {
      const { frequencies, magnitudes, timestamp, sampleRate, resolution } = action.payload;

      // Validate frequency range and data integrity
      if (!frequencies || !magnitudes || frequencies.length !== magnitudes.length) {
        console.error('Invalid spectrum data format');
        return;
      }

      // Verify frequency bounds
      const minFreq = frequencies[0];
      const maxFreq = frequencies[frequencies.length - 1];
      if (!isValidFrequency(minFreq) || !isValidFrequency(maxFreq)) {
        console.error('Frequency range out of bounds');
        return;
      }

      // Performance optimization: only update if sufficient time has passed
      const timeDelta = timestamp - state.lastUpdateTimestamp;
      if (timeDelta < state.config.updateInterval) {
        return;
      }

      // Update state with new spectrum data
      state.spectrumData = {
        frequencies: frequencies,
        magnitudes: magnitudes,
        timestamp,
        sampleRate,
        resolution
      };
      state.lastUpdateTimestamp = timestamp;
    },

    /**
     * Updates processing status with threshold validation
     */
    updateProcessingStatus: (state, action: PayloadAction<ProcessingStatus>) => {
      const { cpuLoad, bufferSize, latency, thdPlusN, signalToNoise, powerEfficiency } = action.payload;

      // Validate performance metrics against requirements
      const isValid = 
        cpuLoad <= 40 && // CPU load requirement
        latency <= 10 && // Latency requirement
        thdPlusN <= 0.0005 && // THD+N requirement
        signalToNoise >= 120 && // SNR requirement
        powerEfficiency >= 90; // Power efficiency requirement

      if (!isValid) {
        console.warn('Performance metrics out of specification');
      }

      // Update processing status
      state.processingStatus = {
        cpuLoad,
        bufferSize,
        latency,
        thdPlusN,
        signalToNoise,
        powerEfficiency
      };
    },

    /**
     * Updates visualization configuration with validation
     */
    updateVisualizationConfig: (state, action: PayloadAction<Partial<VisualizationConfig & { accessibilityMode: boolean }>>) => {
      const newConfig = { ...state.config, ...action.payload };

      // Validate configuration parameters
      if (newConfig.fftSize && !isValidFFTSize(newConfig.fftSize)) {
        console.error('Invalid FFT size');
        return;
      }

      if (!isValidDecibels(newConfig.minDecibels) || !isValidDecibels(newConfig.maxDecibels)) {
        console.error('Invalid decibel range');
        return;
      }

      if (!isValidFrequency(newConfig.minFrequency) || !isValidFrequency(newConfig.maxFrequency)) {
        console.error('Invalid frequency range');
        return;
      }

      // Update configuration
      state.config = newConfig;
    },

    /**
     * Resets visualization state to initial values
     */
    resetVisualizationState: (state) => {
      Object.assign(state, initialState);
    }
  }
});

// Export actions
export const {
  updateSpectrumData,
  updateProcessingStatus,
  updateVisualizationConfig,
  resetVisualizationState
} = visualizationSlice.actions;

// Export reducer
export default visualizationSlice.reducer;

// Export selector helpers
export const selectSpectrumData = (state: { visualization: VisualizationState }) => state.visualization.spectrumData;
export const selectProcessingStatus = (state: { visualization: VisualizationState }) => state.visualization.processingStatus;
export const selectVisualizationConfig = (state: { visualization: VisualizationState }) => state.visualization.config;