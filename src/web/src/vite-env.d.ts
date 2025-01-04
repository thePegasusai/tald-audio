/// <reference types="vite/client" />

/**
 * Type declarations for TALD UNIA Audio System environment variables and configurations
 * @version 4.4.0
 */

/**
 * Extended ImportMetaEnv interface for TALD UNIA specific environment variables
 */
interface ImportMetaEnv {
  /** Base URL for TALD UNIA API endpoints */
  readonly VITE_API_URL: string;
  
  /** WebSocket server URL for real-time audio processing */
  readonly VITE_WS_URL: string;
  
  /** Path to AI enhancement model files */
  readonly VITE_AI_MODEL_PATH: string;
  
  /** Audio processing buffer size (256/512/1024) */
  readonly VITE_AUDIO_BUFFER_SIZE: number;
  
  /** Audio sample rate (44100/48000/96000/192000) */
  readonly VITE_SAMPLE_RATE: number;
  
  /** Maximum supported audio channels (2/5.1/7.1) */
  readonly VITE_MAX_CHANNELS: number;
  
  /** Path to audio worklet processor scripts */
  readonly VITE_DSP_WORKLET_PATH: string;
  
  /** Path to spatial audio HRTF model files */
  readonly VITE_SPATIAL_MODEL_PATH: string;
}

/**
 * Extended ImportMeta interface to include TALD UNIA environment variables
 */
interface ImportMeta {
  readonly env: ImportMetaEnv;
}

/**
 * Audio processing configuration type definitions
 */
declare namespace AudioProcessing {
  interface BufferConfig {
    size: 256 | 512 | 1024;
    channels: 2 | 6 | 8; // Corresponds to 2.0, 5.1, 7.1
    sampleRate: 44100 | 48000 | 96000 | 192000;
  }

  interface AIEnhancementConfig {
    modelPath: string;
    processingMode: 'realtime' | 'highQuality';
    latencyTarget: number; // in milliseconds
  }

  interface SpatialAudioConfig {
    hrtfModelPath: string;
    roomSize: 'small' | 'medium' | 'large';
    reflectionModel: 'basic' | 'advanced';
  }
}

/**
 * WebSocket message type definitions for real-time audio processing
 */
declare namespace WebSocketMessages {
  interface AudioMessage {
    type: 'audioData' | 'configUpdate' | 'status';
    timestamp: number;
    payload: ArrayBuffer | AudioProcessing.BufferConfig | StatusInfo;
  }

  interface StatusInfo {
    processingLoad: number;
    bufferHealth: number;
    latency: number;
  }
}

/**
 * DSP Worklet type definitions
 */
declare namespace DSPWorklet {
  interface ProcessorOptions extends AudioWorkletNodeOptions {
    processorOptions: {
      bufferConfig: AudioProcessing.BufferConfig;
      enhancementConfig: AudioProcessing.AIEnhancementConfig;
      spatialConfig: AudioProcessing.SpatialAudioConfig;
    };
  }
}

export {};