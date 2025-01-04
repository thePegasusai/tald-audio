/**
 * TALD UNIA Audio System - Redux Audio State Management
 * Version: 1.0.0
 */

import { createSlice, PayloadAction } from '@reduxjs/toolkit'; // v1.9.5
import {
  AudioConfig,
  ProcessingQuality,
  AudioProcessingState,
  AudioMetrics,
  SpatialAudioConfig,
  Position3D,
  AIProcessingStatus,
  PipelineStage,
  ErrorState,
  OptimizationState,
  CalibrationState,
  HRTFProfile,
  BufferHealth,
  QualityValidation
} from '../../types/audio.types';
import { AudioProcessor } from '../../lib/audio/audioProcessor';

// Initial state configuration with optimal defaults
const initialState = {
  config: {
    sampleRate: 192000,
    bitDepth: 32,
    channels: 2,
    bufferSize: 256,
    processingQuality: ProcessingQuality.Maximum
  } as AudioConfig,

  spatialConfig: {
    enableSpatial: true,
    hrtfEnabled: true,
    listenerPosition: { x: 0, y: 0, z: 0 },
    roomSize: { width: 10, height: 3, depth: 10 },
    hrtfProfile: 'custom',
    calibrationState: 'completed'
  } as SpatialAudioConfig,

  processingState: {
    isProcessing: false,
    currentLoad: 0,
    bufferHealth: 100,
    latency: 0,
    pipelineStages: {
      dsp: 'idle',
      ai: 'ready',
      spatial: 'active'
    },
    errorState: null,
    optimizationStatus: 'optimal'
  } as AudioProcessingState,

  metrics: {
    thd: 0,
    snr: 120,
    rmsLevel: -60,
    aiQualityImprovement: 0,
    realTimeValidation: {
      status: 'passing',
      lastCheck: 0
    }
  } as AudioMetrics
};

const audioSlice = createSlice({
  name: 'audio',
  initialState,
  reducers: {
    updateConfig(state, action: PayloadAction<AudioConfig>) {
      const newConfig = action.payload;
      // Validate configuration against system capabilities
      if (newConfig.sampleRate > 0 && newConfig.bufferSize > 0) {
        const latency = (newConfig.bufferSize / newConfig.sampleRate) * 1000;
        if (latency <= 10) { // Ensure < 10ms latency requirement
          state.config = newConfig;
          state.processingState.latency = latency;
        }
      }
    },

    updateSpatialConfig(state, action: PayloadAction<SpatialAudioConfig>) {
      state.spatialConfig = {
        ...state.spatialConfig,
        ...action.payload
      };
    },

    updateListenerPosition(state, action: PayloadAction<Position3D>) {
      state.spatialConfig.listenerPosition = action.payload;
    },

    updateProcessingState(state, action: PayloadAction<Partial<AudioProcessingState>>) {
      state.processingState = {
        ...state.processingState,
        ...action.payload
      };
    },

    updatePipelineStage(state, action: PayloadAction<{ stage: keyof PipelineStage; status: string }>) {
      const { stage, status } = action.payload;
      state.processingState.pipelineStages[stage] = status;
    },

    updateMetrics(state, action: PayloadAction<AudioMetrics>) {
      state.metrics = action.payload;
      // Validate THD requirement
      if (state.metrics.thd > 0.0005) {
        state.processingState.errorState = {
          type: 'QUALITY_VIOLATION',
          message: 'THD exceeds maximum threshold'
        };
      }
    },

    setErrorState(state, action: PayloadAction<ErrorState>) {
      state.processingState.errorState = action.payload;
    },

    updateOptimizationStatus(state, action: PayloadAction<OptimizationState>) {
      state.processingState.optimizationStatus = action.payload;
    },

    updateBufferHealth(state, action: PayloadAction<BufferHealth>) {
      state.processingState.bufferHealth = action.payload;
    },

    updateAIProcessingStatus(state, action: PayloadAction<AIProcessingStatus>) {
      if (state.processingState.pipelineStages.ai === 'ready') {
        state.processingState.aiProcessingStatus = action.payload;
      }
    },

    updateCalibrationState(state, action: PayloadAction<CalibrationState>) {
      state.spatialConfig.calibrationState = action.payload;
    },

    updateHRTFProfile(state, action: PayloadAction<HRTFProfile>) {
      if (state.spatialConfig.hrtfEnabled) {
        state.spatialConfig.hrtfProfile = action.payload;
      }
    },

    validateQuality(state, action: PayloadAction<QualityValidation>) {
      state.metrics.realTimeValidation = {
        status: action.payload.status,
        lastCheck: Date.now()
      };
    },

    resetState() {
      return initialState;
    }
  }
});

export const audioActions = audioSlice.actions;
export default audioSlice.reducer;

// Selectors
export const selectAudioConfig = (state: { audio: typeof initialState }) => state.audio.config;
export const selectSpatialConfig = (state: { audio: typeof initialState }) => state.audio.spatialConfig;
export const selectProcessingState = (state: { audio: typeof initialState }) => state.audio.processingState;
export const selectAudioMetrics = (state: { audio: typeof initialState }) => state.audio.metrics;
export const selectBufferHealth = (state: { audio: typeof initialState }) => state.audio.processingState.bufferHealth;
export const selectErrorState = (state: { audio: typeof initialState }) => state.audio.processingState.errorState;
export const selectOptimizationStatus = (state: { audio: typeof initialState }) => state.audio.processingState.optimizationStatus;