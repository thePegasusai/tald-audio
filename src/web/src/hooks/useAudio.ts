/**
 * TALD UNIA Audio System - Audio Processing Hook
 * Version: 1.0.0
 * 
 * Custom React hook for managing high-fidelity audio processing with
 * AI enhancement, spatial audio, and WebGL2 acceleration.
 */

import { useState, useEffect, useCallback } from 'react'; // v18.2.0
import { 
  AudioProcessor,
  initialize,
  process,
  updateConfig,
  getMetrics,
  validateWebGL2,
  cleanup
} from '../lib/audio/audioProcessor';

import {
  AudioConfig,
  AudioProcessingState,
  AudioMetrics,
  ProcessingQuality,
  AudioProcessingError,
  AudioProcessingEvent,
  WebGLSupport
} from '../types/audio.types';

// System constants
const DEFAULT_AUDIO_CONFIG: AudioConfig = {
  sampleRate: 192000,
  bitDepth: 32,
  channels: 2,
  bufferSize: 256,
  processingQuality: ProcessingQuality.Balanced
};

const METRICS_UPDATE_INTERVAL = 100; // ms
const ERROR_RETRY_ATTEMPTS = 3;
const WEBGL_FEATURE_REQUIREMENTS = {
  textureSize: 8192,
  floatTextures: true,
  vertexArrayObjects: true
};

/**
 * Custom hook for managing audio processing state and controls
 * with WebGL2 acceleration and comprehensive error handling
 */
export function useAudio(initialConfig: AudioConfig = DEFAULT_AUDIO_CONFIG) {
  // Core state
  const [audioProcessor, setAudioProcessor] = useState<AudioProcessor | null>(null);
  const [audioState, setAudioState] = useState<AudioProcessingState>({
    isProcessing: false,
    currentLoad: 0,
    bufferHealth: 100,
    latency: 0,
    aiProcessingStatus: {
      enabled: false,
      modelVersion: '',
      enhancementLevel: 0,
      processingLoad: 0,
      lastUpdateTimestamp: 0
    },
    dspUtilization: 0,
    spatialProcessingActive: false
  });

  // Metrics and monitoring state
  const [audioMetrics, setAudioMetrics] = useState<AudioMetrics>({
    thd: 0,
    snr: 0,
    rmsLevel: 0,
    peakLevel: 0,
    dynamicRange: 0,
    frequencyResponse: [],
    phaseResponse: []
  });

  // WebGL support state
  const [webglSupport, setWebglSupport] = useState<WebGLSupport>({
    supported: false,
    version: 0,
    features: {}
  });

  /**
   * Initialize audio processor with WebGL2 validation
   */
  const initializeProcessor = useCallback(async () => {
    try {
      // Validate WebGL2 support and capabilities
      const webglValidation = await validateWebGL2(WEBGL_FEATURE_REQUIREMENTS);
      setWebglSupport(webglValidation);

      if (!webglValidation.supported) {
        throw new Error('WebGL2 support required for audio processing');
      }

      // Initialize audio processor with optimal configuration
      const processor = new AudioProcessor(initialConfig);
      await processor.initialize();

      // Set up event listeners
      processor.addEventListener(AudioProcessingEvent.StateChange, 
        (state: AudioProcessingState) => setAudioState(state));
      processor.addEventListener(AudioProcessingEvent.MetricsUpdate,
        (metrics: AudioMetrics) => setAudioMetrics(metrics));
      processor.addEventListener(AudioProcessingEvent.Error,
        handleError);

      setAudioProcessor(processor);
    } catch (error) {
      handleError(AudioProcessingError.ConfigurationError, error);
    }
  }, [initialConfig]);

  /**
   * Start audio processing with error handling and retries
   */
  const startProcessing = useCallback(async () => {
    if (!audioProcessor) return;

    let attempts = 0;
    while (attempts < ERROR_RETRY_ATTEMPTS) {
      try {
        await audioProcessor.process();
        setAudioState(prev => ({ ...prev, isProcessing: true }));
        break;
      } catch (error) {
        attempts++;
        if (attempts === ERROR_RETRY_ATTEMPTS) {
          handleError(AudioProcessingError.ProcessingOverload, error);
        }
        await new Promise(resolve => setTimeout(resolve, 1000));
      }
    }
  }, [audioProcessor]);

  /**
   * Stop audio processing safely
   */
  const stopProcessing = useCallback(() => {
    if (!audioProcessor) return;

    try {
      audioProcessor.cleanup();
      setAudioState(prev => ({ ...prev, isProcessing: false }));
    } catch (error) {
      handleError(AudioProcessingError.DeviceError, error);
    }
  }, [audioProcessor]);

  /**
   * Update audio configuration with validation
   */
  const updateAudioConfig = useCallback((newConfig: Partial<AudioConfig>) => {
    if (!audioProcessor) return;

    try {
      const updatedConfig = { ...initialConfig, ...newConfig };
      audioProcessor.updateConfig(updatedConfig);
    } catch (error) {
      handleError(AudioProcessingError.ConfigurationError, error);
    }
  }, [audioProcessor, initialConfig]);

  /**
   * Handle audio processing errors
   */
  const handleError = useCallback((type: AudioProcessingError, error: any) => {
    console.error(`Audio processing error: ${type}`, error);
    setAudioState(prev => ({ 
      ...prev, 
      isProcessing: false,
      currentLoad: 0
    }));
  }, []);

  /**
   * Set up metrics collection interval
   */
  useEffect(() => {
    if (!audioProcessor) return;

    const metricsInterval = setInterval(() => {
      const metrics = audioProcessor.getMetrics();
      setAudioMetrics(metrics);
    }, METRICS_UPDATE_INTERVAL);

    return () => clearInterval(metricsInterval);
  }, [audioProcessor]);

  /**
   * Initialize processor on mount
   */
  useEffect(() => {
    initializeProcessor();

    return () => {
      if (audioProcessor) {
        audioProcessor.cleanup();
      }
    };
  }, [initializeProcessor]);

  return {
    audioState,
    audioMetrics,
    webglSupport,
    startProcessing,
    stopProcessing,
    updateConfig: updateAudioConfig,
    handleError
  };
}