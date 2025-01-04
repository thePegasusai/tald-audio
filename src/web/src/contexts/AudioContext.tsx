/**
 * TALD UNIA Audio System - Audio Context Provider
 * Version: 1.0.0
 * 
 * High-performance React context provider for centralized audio processing state management
 * with WebGL2 acceleration support and comprehensive error handling.
 */

import {
  createContext,
  useContext,
  useState,
  useEffect,
  useCallback,
  useRef,
  ReactNode
} from 'react'; // ^18.2.0

import {
  AudioProcessor,
  initialize,
  process,
  updateConfig,
  initializeWebGL
} from '../lib/audio/audioProcessor';

import {
  AudioConfig,
  AudioProcessingState,
  AudioMetrics,
  ProcessingQuality,
  SpatialAudioConfig,
  WebGLSupport,
  ErrorState,
  AudioProcessingError,
  AudioProcessingEvent
} from '../types/audio.types';

// System constants
const DEFAULT_AUDIO_CONFIG: AudioConfig = {
  sampleRate: 192000,
  bitDepth: 32,
  channels: 2,
  bufferSize: 256,
  processingQuality: ProcessingQuality.Balanced
};

const DEFAULT_SPATIAL_CONFIG: SpatialAudioConfig = {
  enableSpatial: true,
  roomSize: { width: 10, height: 3, depth: 8 },
  listenerPosition: { x: 0, y: 0, z: 0 },
  hrtfEnabled: true,
  hrtfProfile: 'default',
  roomMaterials: [],
  reflectionModel: 'HYBRID'
};

const METRICS_UPDATE_INTERVAL = 100;
const ERROR_RECOVERY_ATTEMPTS = 3;

// Context interface definition
interface AudioContextValue {
  audioState: AudioProcessingState;
  audioMetrics: AudioMetrics | null;
  webglSupport: WebGLSupport;
  errorState: ErrorState | null;
  config: AudioConfig;
  startProcessing: () => Promise<void>;
  stopProcessing: () => void;
  updateConfig: (newConfig: Partial<AudioConfig>) => void;
  resetError: () => void;
}

// Create context with type safety
const AudioContext = createContext<AudioContextValue | null>(null);

// Provider props interface
interface AudioProviderProps {
  children: ReactNode;
}

/**
 * Audio Context Provider component with WebGL2 acceleration support
 */
export function AudioProvider({ children }: AudioProviderProps): JSX.Element {
  // Core state management
  const [audioState, setAudioState] = useState<AudioProcessingState>({
    isProcessing: false,
    currentLoad: 0,
    bufferHealth: 100,
    latency: 0,
    aiProcessingStatus: {
      enabled: true,
      modelVersion: '1.0.0',
      enhancementLevel: 1,
      processingLoad: 0,
      lastUpdateTimestamp: Date.now()
    },
    dspUtilization: 0,
    spatialProcessingActive: false
  });

  const [audioMetrics, setAudioMetrics] = useState<AudioMetrics | null>(null);
  const [config, setConfig] = useState<AudioConfig>(DEFAULT_AUDIO_CONFIG);
  const [errorState, setErrorState] = useState<ErrorState | null>(null);
  const [webglSupport, setWebglSupport] = useState<WebGLSupport>({
    supported: false,
    version: 0,
    initialized: false
  });

  // Refs for persistent instances
  const audioProcessor = useRef<AudioProcessor | null>(null);
  const metricsInterval = useRef<number | null>(null);
  const recoveryAttempts = useRef<number>(0);

  /**
   * Initialize WebGL support for audio processing
   */
  const initializeWebGLSupport = useCallback(async () => {
    try {
      const canvas = document.createElement('canvas');
      const gl = canvas.getContext('webgl2');
      
      if (!gl) {
        throw new Error('WebGL2 not supported');
      }

      setWebglSupport({
        supported: true,
        version: 2,
        initialized: true
      });

      return true;
    } catch (error) {
      console.error('WebGL initialization failed:', error);
      setWebglSupport({
        supported: false,
        version: 0,
        initialized: false
      });
      return false;
    }
  }, []);

  /**
   * Initialize audio processor with error handling
   */
  const initializeAudioProcessor = useCallback(async () => {
    try {
      if (!audioProcessor.current) {
        audioProcessor.current = new AudioProcessor(config, DEFAULT_SPATIAL_CONFIG);
        await audioProcessor.current.initialize();
        
        // Set up event listeners
        audioProcessor.current.addEventListener(
          AudioProcessingEvent.StateChange,
          (event: any) => {
            setAudioState(prevState => ({
              ...prevState,
              ...event.data
            }));
          }
        );

        audioProcessor.current.addEventListener(
          AudioProcessingEvent.Error,
          (event: any) => {
            handleError(event.data);
          }
        );
      }
      return true;
    } catch (error) {
      handleError({
        type: AudioProcessingError.ConfigurationError,
        message: 'Failed to initialize audio processor',
        error
      });
      return false;
    }
  }, [config]);

  /**
   * Start audio processing with WebGL acceleration
   */
  const startProcessing = async () => {
    try {
      if (!webglSupport.initialized) {
        await initializeWebGLSupport();
      }

      if (!audioProcessor.current) {
        const initialized = await initializeAudioProcessor();
        if (!initialized) return;
      }

      setAudioState(prev => ({ ...prev, isProcessing: true }));
      
      // Start metrics monitoring
      metricsInterval.current = window.setInterval(() => {
        if (audioProcessor.current) {
          const metrics = audioProcessor.current.getMetrics();
          setAudioMetrics(metrics);
        }
      }, METRICS_UPDATE_INTERVAL);

    } catch (error) {
      handleError({
        type: AudioProcessingError.ProcessingOverload,
        message: 'Failed to start audio processing',
        error
      });
    }
  };

  /**
   * Stop audio processing and cleanup resources
   */
  const stopProcessing = useCallback(() => {
    try {
      if (metricsInterval.current) {
        clearInterval(metricsInterval.current);
        metricsInterval.current = null;
      }

      if (audioProcessor.current) {
        audioProcessor.current.stopProcessing();
      }

      setAudioState(prev => ({ ...prev, isProcessing: false }));
    } catch (error) {
      handleError({
        type: AudioProcessingError.DeviceError,
        message: 'Error stopping audio processing',
        error
      });
    }
  }, []);

  /**
   * Update audio configuration with validation
   */
  const updateConfig = useCallback((newConfig: Partial<AudioConfig>) => {
    try {
      const updatedConfig = { ...config, ...newConfig };
      setConfig(updatedConfig);

      if (audioProcessor.current) {
        audioProcessor.current.updateConfig(updatedConfig);
      }
    } catch (error) {
      handleError({
        type: AudioProcessingError.ConfigurationError,
        message: 'Failed to update configuration',
        error
      });
    }
  }, [config]);

  /**
   * Handle and recover from errors
   */
  const handleError = useCallback((error: ErrorState) => {
    setErrorState(error);

    if (recoveryAttempts.current < ERROR_RECOVERY_ATTEMPTS) {
      recoveryAttempts.current++;
      // Attempt recovery
      stopProcessing();
      setTimeout(async () => {
        await initializeAudioProcessor();
        startProcessing();
      }, 1000);
    }
  }, []);

  /**
   * Reset error state and recovery attempts
   */
  const resetError = useCallback(() => {
    setErrorState(null);
    recoveryAttempts.current = 0;
  }, []);

  // Cleanup on unmount
  useEffect(() => {
    return () => {
      stopProcessing();
      if (audioProcessor.current) {
        audioProcessor.current = null;
      }
    };
  }, [stopProcessing]);

  const contextValue: AudioContextValue = {
    audioState,
    audioMetrics,
    webglSupport,
    errorState,
    config,
    startProcessing,
    stopProcessing,
    updateConfig,
    resetError
  };

  return (
    <AudioContext.Provider value={contextValue}>
      {children}
    </AudioContext.Provider>
  );
}

/**
 * Custom hook for accessing audio context with type safety
 */
export function useAudioContext(): AudioContextValue {
  const context = useContext(AudioContext);
  if (!context) {
    throw new Error('useAudioContext must be used within an AudioProvider');
  }
  return context;
}

export default AudioContext;