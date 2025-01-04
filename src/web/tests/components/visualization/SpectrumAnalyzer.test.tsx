/**
 * Comprehensive test suite for TALD UNIA Audio System's SpectrumAnalyzer component
 * Version: 1.0.0
 * @package @testing-library/react ^14.0.0
 * @package @testing-library/jest-dom ^6.1.0
 * @package jest-webgl-canvas-mock ^1.0.0
 */

import React from 'react';
import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import '@testing-library/jest-dom';
import { SpectrumAnalyzer } from '../../../src/components/visualization/SpectrumAnalyzer';
import { useVisualization } from '../../../src/hooks/useVisualization';
import { VisualizationConfig } from '../../../src/types/visualization.types';
import 'jest-webgl-canvas-mock';

// Mock WebGL context and canvas
const mockWebGLContext = {
  createShader: jest.fn(),
  shaderSource: jest.fn(),
  compileShader: jest.fn(),
  getShaderParameter: jest.fn(() => true),
  createProgram: jest.fn(),
  attachShader: jest.fn(),
  linkProgram: jest.fn(),
  getProgramParameter: jest.fn(() => true),
  useProgram: jest.fn(),
  getAttribLocation: jest.fn(),
  getUniformLocation: jest.fn(),
  enableVertexAttribArray: jest.fn(),
  createBuffer: jest.fn(),
  bindBuffer: jest.fn(),
  bufferData: jest.fn(),
  vertexAttribPointer: jest.fn(),
  drawArrays: jest.fn(),
  deleteBuffer: jest.fn(),
  viewport: jest.fn(),
  uniform1f: jest.fn(),
  uniform2f: jest.fn(),
  uniform3f: jest.fn(),
};

// Mock visualization hook
jest.mock('../../../src/hooks/useVisualization', () => ({
  useVisualization: jest.fn()
}));

// Test configuration constants
const TEST_CONFIG = {
  width: 800,
  height: 400,
  fftSize: 2048,
  minDecibels: -90,
  maxDecibels: -10,
  smoothingTimeConstant: 0.8,
  targetFrameRate: 60
};

// Mock spectrum data generator
const generateMockSpectrumData = (size: number = TEST_CONFIG.fftSize / 2) => {
  const frequencies = new Float32Array(size);
  const magnitudes = new Float32Array(size);
  
  for (let i = 0; i < size; i++) {
    frequencies[i] = (i * 24000) / size;
    magnitudes[i] = -90 + Math.random() * 80;
  }
  
  return {
    frequencies,
    magnitudes,
    timestamp: performance.now(),
    sampleRate: 48000,
    resolution: 24000 / size
  };
};

describe('SpectrumAnalyzer Component', () => {
  beforeEach(() => {
    // Reset all mocks
    jest.clearAllMocks();
    
    // Mock performance.now for consistent timing tests
    jest.spyOn(performance, 'now').mockImplementation(() => 1000);
    
    // Mock requestAnimationFrame
    jest.spyOn(window, 'requestAnimationFrame').mockImplementation(cb => setTimeout(cb, 16));
    
    // Mock WebGL context
    HTMLCanvasElement.prototype.getContext = jest.fn(() => mockWebGLContext);
    
    // Setup default visualization hook mock
    (useVisualization as jest.Mock).mockReturnValue({
      spectrumData: generateMockSpectrumData(),
      processingStatus: {
        cpuLoad: 20,
        bufferSize: 256,
        latency: 5,
        thdPlusN: 0.0003,
        signalToNoise: 120,
        powerEfficiency: 95
      }
    });
  });

  afterEach(() => {
    jest.restoreAllMocks();
  });

  test('should initialize with correct WebGL context and shaders', async () => {
    render(
      <SpectrumAnalyzer
        width={TEST_CONFIG.width}
        height={TEST_CONFIG.height}
        config={{ fftSize: TEST_CONFIG.fftSize }}
      />
    );

    await waitFor(() => {
      expect(HTMLCanvasElement.prototype.getContext).toHaveBeenCalledWith('webgl', {
        alpha: false,
        antialias: false,
        depth: false,
        powerPreference: 'high-performance'
      });
    });

    expect(mockWebGLContext.createShader).toHaveBeenCalledTimes(2);
    expect(mockWebGLContext.createProgram).toHaveBeenCalled();
  });

  test('should render spectrum with correct dimensions and scaling', async () => {
    const { container } = render(
      <SpectrumAnalyzer
        width={TEST_CONFIG.width}
        height={TEST_CONFIG.height}
        showGrid={true}
        showLabels={true}
      />
    );

    const canvas = container.querySelector('canvas');
    expect(canvas).toBeInTheDocument();
    expect(canvas).toHaveAttribute('width', String(TEST_CONFIG.width * window.devicePixelRatio));
    expect(canvas).toHaveAttribute('height', String(TEST_CONFIG.height * window.devicePixelRatio));
  });

  test('should maintain performance within specified limits', async () => {
    const performanceMonitor = {
      frames: 0,
      startTime: performance.now(),
      measureFrameRate: function() {
        const elapsed = performance.now() - this.startTime;
        return (this.frames / elapsed) * 1000;
      }
    };

    render(
      <SpectrumAnalyzer
        width={TEST_CONFIG.width}
        height={TEST_CONFIG.height}
        targetFrameRate={TEST_CONFIG.targetFrameRate}
      />
    );

    // Simulate 1 second of rendering
    await waitFor(() => {
      performanceMonitor.frames++;
    }, { timeout: 1000 });

    const frameRate = performanceMonitor.measureFrameRate();
    expect(frameRate).toBeLessThanOrEqual(TEST_CONFIG.targetFrameRate);
    expect(frameRate).toBeGreaterThanOrEqual(TEST_CONFIG.targetFrameRate * 0.9);
  });

  test('should accurately visualize THD+N measurements', async () => {
    const thdnValue = 0.0003; // 0.0003% THD+N
    (useVisualization as jest.Mock).mockReturnValue({
      spectrumData: generateMockSpectrumData(),
      processingStatus: {
        ...TEST_CONFIG,
        thdPlusN: thdnValue
      }
    });

    render(
      <SpectrumAnalyzer
        width={TEST_CONFIG.width}
        height={TEST_CONFIG.height}
        showTHDN={true}
      />
    );

    await waitFor(() => {
      const thdnDisplay = screen.getByText(/THD\+N:/);
      expect(thdnDisplay).toHaveTextContent(`THD+N: ${thdnValue.toFixed(6)}%`);
    });
  });

  test('should handle WebGL context loss and restoration', async () => {
    const { container } = render(
      <SpectrumAnalyzer
        width={TEST_CONFIG.width}
        height={TEST_CONFIG.height}
      />
    );

    const canvas = container.querySelector('canvas');
    expect(canvas).toBeInTheDocument();

    // Simulate context loss
    const contextLossEvent = new Event('webglcontextlost');
    fireEvent(canvas!, contextLossEvent);

    // Simulate context restoration
    const contextRestoredEvent = new Event('webglcontextrestored');
    fireEvent(canvas!, contextRestoredEvent);

    await waitFor(() => {
      expect(mockWebGLContext.createProgram).toHaveBeenCalledTimes(2);
    });
  });

  test('should update visualization config dynamically', async () => {
    const { rerender } = render(
      <SpectrumAnalyzer
        width={TEST_CONFIG.width}
        height={TEST_CONFIG.height}
        config={{ fftSize: TEST_CONFIG.fftSize }}
      />
    );

    // Update config
    const newConfig: Partial<VisualizationConfig> = {
      fftSize: 4096,
      smoothingTimeConstant: 0.9
    };

    rerender(
      <SpectrumAnalyzer
        width={TEST_CONFIG.width}
        height={TEST_CONFIG.height}
        config={newConfig}
      />
    );

    await waitFor(() => {
      expect(useVisualization).toHaveBeenCalledWith(expect.objectContaining(newConfig));
    });
  });

  test('should handle high-resolution displays correctly', async () => {
    // Mock high DPI display
    Object.defineProperty(window, 'devicePixelRatio', {
      value: 2,
      writable: true
    });

    const { container } = render(
      <SpectrumAnalyzer
        width={TEST_CONFIG.width}
        height={TEST_CONFIG.height}
      />
    );

    const canvas = container.querySelector('canvas');
    expect(canvas).toHaveAttribute('width', String(TEST_CONFIG.width * 2));
    expect(canvas).toHaveAttribute('height', String(TEST_CONFIG.height * 2));
  });
});