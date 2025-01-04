/**
 * TALD UNIA Audio System - useAudio Hook Tests
 * Version: 1.0.0
 * 
 * Comprehensive test suite for the useAudio custom React hook,
 * verifying audio processing functionality, WebGL2 acceleration,
 * state management, and performance metrics.
 */

import { render, act, renderHook } from '@testing-library/react'; // v14.0.0
import { describe, it, expect, jest } from '@jest/globals'; // v29.6.0
import { mockWebGL2Context } from '@jest/canvas-mock'; // v1.0.0

import { useAudio } from '../../src/hooks/useAudio';
import {
  AudioConfig,
  ProcessingQuality,
  AudioProcessingState,
  AudioMetrics,
  WebGLContext
} from '../../src/types/audio.types';

// Test constants
const TEST_AUDIO_CONFIG: AudioConfig = {
  sampleRate: 192000,
  bitDepth: 32,
  channels: 2,
  bufferSize: 256,
  processingQuality: ProcessingQuality.Maximum,
  webglAcceleration: true
};

const MOCK_AUDIO_METRICS: AudioMetrics = {
  thd: 0.0003,
  snr: 120,
  rmsLevel: -18,
  peakLevel: -12,
  dynamicRange: 108,
  frequencyResponse: [],
  phaseResponse: []
};

const MOCK_WEBGL_CONTEXT = {
  version: 2,
  extensions: ['EXT_float_blend', 'OES_texture_float'],
  maxTextureSize: 8192,
  maxComputeUnits: 16
};

// Mock WebGL2 context
jest.mock('../../src/lib/audio/audioProcessor', () => ({
  validateWebGL2: jest.fn().mockResolvedValue({
    supported: true,
    version: 2,
    features: MOCK_WEBGL_CONTEXT
  }),
  AudioProcessor: jest.fn().mockImplementation(() => ({
    initialize: jest.fn().mockResolvedValue(undefined),
    process: jest.fn().mockResolvedValue(undefined),
    cleanup: jest.fn(),
    updateConfig: jest.fn(),
    getMetrics: jest.fn().mockReturnValue(MOCK_AUDIO_METRICS),
    addEventListener: jest.fn(),
    removeEventListener: jest.fn()
  }))
}));

describe('useAudio Hook', () => {
  beforeEach(() => {
    // Reset mocks and setup WebGL context
    jest.clearAllMocks();
    mockWebGL2Context();
  });

  it('should initialize with WebGL2 support', async () => {
    const { result } = renderHook(() => useAudio(TEST_AUDIO_CONFIG));

    await act(async () => {
      // Wait for initialization
      await new Promise(resolve => setTimeout(resolve, 0));
    });

    expect(result.current.webglSupport.supported).toBe(true);
    expect(result.current.webglSupport.version).toBe(2);
    expect(result.current.webglSupport.features).toEqual(
      expect.objectContaining(MOCK_WEBGL_CONTEXT)
    );
  });

  it('should handle WebGL2 initialization failure gracefully', async () => {
    // Mock WebGL2 validation failure
    jest.spyOn(window, 'WebGL2RenderingContext').mockImplementation(() => undefined);

    const { result } = renderHook(() => useAudio(TEST_AUDIO_CONFIG));

    await act(async () => {
      await new Promise(resolve => setTimeout(resolve, 0));
    });

    expect(result.current.webglSupport.supported).toBe(false);
    expect(result.current.audioState.isProcessing).toBe(false);
  });

  it('should start audio processing with WebGL2 acceleration', async () => {
    const { result } = renderHook(() => useAudio(TEST_AUDIO_CONFIG));

    await act(async () => {
      await new Promise(resolve => setTimeout(resolve, 0));
      await result.current.startProcessing();
    });

    expect(result.current.audioState.isProcessing).toBe(true);
    expect(result.current.audioState.currentLoad).toBeGreaterThan(0);
  });

  it('should stop audio processing and cleanup resources', async () => {
    const { result } = renderHook(() => useAudio(TEST_AUDIO_CONFIG));

    await act(async () => {
      await new Promise(resolve => setTimeout(resolve, 0));
      await result.current.startProcessing();
      result.current.stopProcessing();
    });

    expect(result.current.audioState.isProcessing).toBe(false);
    expect(result.current.audioState.currentLoad).toBe(0);
  });

  it('should update audio configuration with WebGL settings', async () => {
    const { result } = renderHook(() => useAudio(TEST_AUDIO_CONFIG));

    const newConfig: Partial<AudioConfig> = {
      processingQuality: ProcessingQuality.Balanced,
      webglAcceleration: true
    };

    await act(async () => {
      await new Promise(resolve => setTimeout(resolve, 0));
      result.current.updateConfig(newConfig);
    });

    expect(result.current.audioState.aiProcessingStatus.processingLoad).toBeDefined();
  });

  it('should monitor audio quality metrics', async () => {
    const { result } = renderHook(() => useAudio(TEST_AUDIO_CONFIG));

    await act(async () => {
      await new Promise(resolve => setTimeout(resolve, 0));
      await result.current.startProcessing();
    });

    expect(result.current.audioMetrics).toEqual(
      expect.objectContaining({
        thd: expect.any(Number),
        snr: expect.any(Number),
        rmsLevel: expect.any(Number)
      })
    );
    expect(result.current.audioMetrics.thd).toBeLessThan(0.0005);
    expect(result.current.audioMetrics.snr).toBeGreaterThan(120);
  });

  it('should handle processing errors with retries', async () => {
    const mockError = new Error('Processing overload');
    jest.spyOn(console, 'error').mockImplementation(() => {});

    const { result } = renderHook(() => useAudio(TEST_AUDIO_CONFIG));

    await act(async () => {
      await new Promise(resolve => setTimeout(resolve, 0));
      // Force error on third retry
      for (let i = 0; i < 3; i++) {
        await result.current.startProcessing();
      }
    });

    expect(console.error).toHaveBeenCalledWith(
      expect.stringContaining('Audio processing error'),
      expect.any(Error)
    );
    expect(result.current.audioState.isProcessing).toBe(false);
  });

  it('should cleanup resources on unmount', async () => {
    const { result, unmount } = renderHook(() => useAudio(TEST_AUDIO_CONFIG));

    await act(async () => {
      await new Promise(resolve => setTimeout(resolve, 0));
      await result.current.startProcessing();
    });

    unmount();

    expect(result.current.audioState.isProcessing).toBe(false);
  });

  it('should validate WebGL2 feature requirements', async () => {
    const { result } = renderHook(() => useAudio(TEST_AUDIO_CONFIG));

    await act(async () => {
      await new Promise(resolve => setTimeout(resolve, 0));
    });

    expect(result.current.webglSupport.features).toEqual(
      expect.objectContaining({
        maxTextureSize: expect.any(Number),
        maxComputeUnits: expect.any(Number)
      })
    );
    expect(result.current.webglSupport.features.maxTextureSize).toBeGreaterThanOrEqual(8192);
  });

  it('should measure processing performance metrics', async () => {
    const { result } = renderHook(() => useAudio(TEST_AUDIO_CONFIG));

    await act(async () => {
      await new Promise(resolve => setTimeout(resolve, 0));
      await result.current.startProcessing();
    });

    expect(result.current.audioState.latency).toBeLessThan(10);
    expect(result.current.audioState.currentLoad).toBeLessThan(0.4);
    expect(result.current.audioState.bufferHealth).toBeGreaterThan(90);
  });
});