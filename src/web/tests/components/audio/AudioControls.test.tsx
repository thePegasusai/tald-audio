import React from 'react';
import { render, screen, fireEvent, waitFor, within } from '@testing-library/react';
import { describe, it, expect, jest, beforeEach, afterEach } from '@jest/globals';
import { axe } from '@axe-core/react';

import AudioControls from '../../../src/components/audio/AudioControls';
import { useAudio } from '../../../src/hooks/useAudio';
import { setupJestDom, setupAudioMocks, setupWebGL2Mocks, setupPerformanceMetrics } from '../../setup';
import { AudioProcessingError, ProcessingQuality } from '../../../src/types/audio.types';

// Mock useAudio hook
jest.mock('../../../src/hooks/useAudio');

// Test constants matching technical specifications
const QUALITY_THRESHOLDS = {
  maxLatency: 10, // ms
  maxLoad: 0.4, // 40% CPU utilization
  minBufferHealth: 0.8, // 80% buffer health
  targetTHD: 0.0005 // 0.05% THD+N
};

describe('AudioControls Component', () => {
  // Setup before each test
  beforeEach(() => {
    setupJestDom();
    setupAudioMocks();
    setupWebGL2Mocks();
    setupPerformanceMetrics();

    // Mock useAudio hook with premium quality defaults
    (useAudio as jest.Mock).mockReturnValue({
      audioState: {
        isProcessing: false,
        currentLoad: 0,
        bufferHealth: 1,
        latency: 5,
        aiProcessingStatus: {
          enabled: true,
          modelVersion: '1.0.0',
          enhancementLevel: 1,
          processingLoad: 0.2
        }
      },
      audioMetrics: {
        thd: 0.0003,
        snr: 120,
        rmsLevel: -20,
        peakLevel: -10,
        dynamicRange: 110,
        frequencyResponse: [],
        phaseResponse: []
      },
      webglSupport: {
        supported: true,
        version: 2,
        features: {
          floatTextures: true,
          vertexArrayObjects: true
        }
      },
      updateConfig: jest.fn(),
      handleError: jest.fn()
    });
  });

  afterEach(() => {
    jest.clearAllMocks();
  });

  it('renders with premium quality defaults', async () => {
    const { container } = render(<AudioControls />);

    // Verify core audio controls presence
    expect(screen.getByRole('group', { name: /audio controls/i })).toBeInTheDocument();
    expect(screen.getByRole('slider', { name: /master volume/i })).toBeInTheDocument();
    expect(screen.getByLabelText(/quality indicator/i)).toBeInTheDocument();

    // Verify quality metrics display
    const metrics = screen.getByRole('region', { name: /audio metrics/i });
    expect(within(metrics).getByText(/thd: 0\.0003%/i)).toBeInTheDocument();
    expect(within(metrics).getByText(/snr: 120 db/i)).toBeInTheDocument();
    expect(within(metrics).getByText(/latency: 5\.0 ms/i)).toBeInTheDocument();

    // Check accessibility
    const results = await axe(container);
    expect(results).toHaveNoViolations();
  });

  it('handles premium audio processing state changes', async () => {
    const mockUpdateConfig = jest.fn();
    (useAudio as jest.Mock).mockImplementation(() => ({
      ...jest.requireActual('../../../src/hooks/useAudio'),
      updateConfig: mockUpdateConfig
    }));

    render(<AudioControls />);

    // Simulate volume change
    const volumeSlider = screen.getByRole('slider', { name: /master volume/i });
    fireEvent.change(volumeSlider, { target: { value: '0.8' } });

    await waitFor(() => {
      expect(mockUpdateConfig).toHaveBeenCalledWith(
        expect.objectContaining({
          volume: expect.any(Number),
          rampTimeMs: expect.any(Number)
        })
      );
    });

    // Verify quality indicator updates
    const qualityIndicator = screen.getByLabelText(/quality indicator/i);
    expect(qualityIndicator).toHaveAttribute('data-quality', 'high');
  });

  it('maintains performance standards under load', async () => {
    const { rerender } = render(<AudioControls />);

    // Simulate processing load
    (useAudio as jest.Mock).mockImplementation(() => ({
      ...jest.requireActual('../../../src/hooks/useAudio'),
      audioState: {
        isProcessing: true,
        currentLoad: 0.35,
        bufferHealth: 0.9,
        latency: 8
      },
      audioMetrics: {
        thd: 0.0004,
        snr: 118
      }
    }));

    rerender(<AudioControls />);

    // Verify performance metrics
    const metrics = screen.getByRole('region', { name: /audio metrics/i });
    expect(within(metrics).getByText(/load: 35%/i)).toBeInTheDocument();
    expect(within(metrics).getByText(/latency: 8\.0 ms/i)).toBeInTheDocument();
    expect(within(metrics).getByText(/thd: 0\.0004%/i)).toBeInTheDocument();

    // Verify all metrics are within specification
    expect(parseFloat(within(metrics).getByText(/latency/i).textContent!))
      .toBeLessThan(QUALITY_THRESHOLDS.maxLatency);
    expect(parseFloat(within(metrics).getByText(/load/i).textContent!))
      .toBeLessThan(QUALITY_THRESHOLDS.maxLoad * 100);
  });

  it('handles WebGL2 acceleration requirements', async () => {
    // Test WebGL2 support detection
    (useAudio as jest.Mock).mockImplementation(() => ({
      ...jest.requireActual('../../../src/hooks/useAudio'),
      webglSupport: {
        supported: false,
        version: 1,
        features: {}
      }
    }));

    render(<AudioControls />);

    // Verify WebGL2 warning is displayed
    expect(screen.getByText(/webgl2 support required/i)).toBeInTheDocument();
    expect(screen.getByRole('button', { name: /play/i })).toBeDisabled();
  });

  it('provides comprehensive error handling', async () => {
    const mockHandleError = jest.fn();
    const mockOnError = jest.fn();

    render(
      <AudioControls 
        onError={mockOnError}
      />
    );

    // Simulate processing error
    (useAudio as jest.Mock).mockImplementation(() => ({
      ...jest.requireActual('../../../src/hooks/useAudio'),
      audioState: {
        isProcessing: true,
        currentLoad: 0.9, // Overload condition
        bufferHealth: 0.5,
        latency: 15
      }
    }));

    // Verify error handling
    await waitFor(() => {
      expect(mockOnError).toHaveBeenCalledWith(
        expect.objectContaining({
          type: AudioProcessingError.ProcessingOverload
        })
      );
    });

    // Verify error UI updates
    expect(screen.getByRole('alert')).toBeInTheDocument();
    expect(screen.getByText(/processing overload/i)).toBeInTheDocument();
  });

  it('complies with accessibility standards', async () => {
    const { container } = render(<AudioControls />);

    // Verify ARIA attributes
    expect(screen.getByRole('group', { name: /audio controls/i }))
      .toHaveAttribute('aria-label');
    expect(screen.getByRole('slider', { name: /master volume/i }))
      .toHaveAttribute('aria-valuetext');

    // Test keyboard navigation
    const volumeSlider = screen.getByRole('slider', { name: /master volume/i });
    fireEvent.keyDown(volumeSlider, { key: 'ArrowRight' });
    expect(volumeSlider).toHaveAttribute('aria-valuenow', expect.any(String));

    // Verify color contrast
    const results = await axe(container);
    expect(results).toHaveNoViolations();
  });
});