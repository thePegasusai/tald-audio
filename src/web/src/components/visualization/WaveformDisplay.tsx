/**
 * TALD UNIA Audio System - High-Performance Waveform Display Component
 * Version: 1.0.0
 * 
 * Implements real-time waveform visualization with WebGL acceleration,
 * double buffering, and adaptive performance scaling.
 * 
 * @package react ^18.2.0
 * @package @emotion/styled ^11.11.0
 */

import React, { useEffect, useRef, useCallback, useMemo } from 'react';
import styled from '@emotion/styled';
import { WaveformData } from '../../types/visualization.types';
import { WaveformRenderer } from '../../lib/visualization/waveformRenderer';
import { useVisualization } from '../../hooks/useVisualization';

// Constants for visualization configuration
const DEFAULT_WIDTH = 800;
const DEFAULT_HEIGHT = 200;
const ANIMATION_FPS = 60;
const BUFFER_SIZE = 2048;
const MIN_FRAME_TIME = 16.67; // ~60fps
const PIXEL_RATIO = window.devicePixelRatio || 1;
const ERROR_RETRY_LIMIT = 3;

// Styled components for visualization container
const VisualizationContainer = styled.div<{ width: number; height: number }>`
  width: ${props => props.width}px;
  height: ${props => props.height}px;
  position: relative;
  background-color: #000;
  border-radius: 4px;
  overflow: hidden;
`;

const Canvas = styled.canvas`
  position: absolute;
  top: 0;
  left: 0;
  width: 100%;
  height: 100%;
`;

const ErrorOverlay = styled.div`
  position: absolute;
  top: 0;
  left: 0;
  width: 100%;
  height: 100%;
  display: flex;
  align-items: center;
  justify-content: center;
  background-color: rgba(0, 0, 0, 0.8);
  color: #ff4444;
  font-size: 14px;
  padding: 16px;
  text-align: center;
`;

// Interface for waveform display theme
interface WaveformTheme {
  waveformColor: string;
  backgroundColor: string;
  lineWidth: number;
}

// Interface for performance configuration
interface PerformanceConfig {
  enableAdaptiveQuality: boolean;
  targetFPS: number;
  maxCPUUsage: number;
}

// Props interface for the WaveformDisplay component
interface WaveformDisplayProps {
  width?: number;
  height?: number;
  className?: string;
  isPlaying: boolean;
  quality: 'high' | 'balanced' | 'low';
  theme?: WaveformTheme;
  performanceConfig?: PerformanceConfig;
}

/**
 * High-performance waveform visualization component with WebGL acceleration
 */
const WaveformDisplay: React.FC<WaveformDisplayProps> = React.memo(({
  width = DEFAULT_WIDTH,
  height = DEFAULT_HEIGHT,
  className,
  isPlaying,
  quality,
  theme = {
    waveformColor: '#00ff00',
    backgroundColor: '#000000',
    lineWidth: 2
  },
  performanceConfig = {
    enableAdaptiveQuality: true,
    targetFPS: ANIMATION_FPS,
    maxCPUUsage: 40
  }
}) => {
  // Refs for canvas and renderer
  const containerRef = useRef<HTMLDivElement>(null);
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const rendererRef = useRef<WaveformRenderer | null>(null);
  const errorCountRef = useRef(0);

  // Use visualization hook for state management and performance monitoring
  const {
    waveformData,
    processingStatus,
    startVisualization,
    stopVisualization,
    updateConfig
  } = useVisualization();

  // Initialize WebGL renderer with error handling
  const initializeRenderer = useCallback(async () => {
    if (!canvasRef.current) return;

    try {
      rendererRef.current = new WaveformRenderer(canvasRef.current, {
        width,
        height,
        color: theme.waveformColor
      });

      await rendererRef.current.initialize();
      errorCountRef.current = 0;
    } catch (error) {
      console.error('Failed to initialize waveform renderer:', error);
      errorCountRef.current++;

      if (errorCountRef.current < ERROR_RETRY_LIMIT) {
        setTimeout(initializeRenderer, 1000);
      }
    }
  }, [width, height, theme.waveformColor]);

  // Handle canvas resize with debouncing
  const handleResize = useCallback((entries: ResizeObserverEntry[]) => {
    if (!rendererRef.current || !canvasRef.current) return;

    const entry = entries[0];
    const { width, height } = entry.contentRect;
    const scaledWidth = width * PIXEL_RATIO;
    const scaledHeight = height * PIXEL_RATIO;

    canvasRef.current.width = scaledWidth;
    canvasRef.current.height = scaledHeight;
    rendererRef.current.resize(scaledWidth, scaledHeight);
  }, []);

  // Set up resize observer
  useEffect(() => {
    const resizeObserver = new ResizeObserver(handleResize);
    if (containerRef.current) {
      resizeObserver.observe(containerRef.current);
    }

    return () => resizeObserver.disconnect();
  }, [handleResize]);

  // Handle visualization lifecycle
  useEffect(() => {
    initializeRenderer();

    return () => {
      if (rendererRef.current) {
        rendererRef.current.stop();
        rendererRef.current = null;
      }
      stopVisualization();
    };
  }, [initializeRenderer, stopVisualization]);

  // Handle playback state changes
  useEffect(() => {
    if (isPlaying && rendererRef.current) {
      rendererRef.current.start();
      startVisualization();
    } else if (rendererRef.current) {
      rendererRef.current.stop();
      stopVisualization();
    }
  }, [isPlaying, startVisualization, stopVisualization]);

  // Update renderer quality settings
  useEffect(() => {
    if (rendererRef.current) {
      rendererRef.current.updateQuality(quality);
    }
  }, [quality]);

  // Render waveform data
  useEffect(() => {
    if (!rendererRef.current || !waveformData) return;

    const renderFrame = async () => {
      try {
        await rendererRef.current?.render(waveformData);
      } catch (error) {
        console.error('Waveform rendering error:', error);
      }
    };

    renderFrame();
  }, [waveformData]);

  // Monitor performance and adapt quality if needed
  useEffect(() => {
    if (!performanceConfig.enableAdaptiveQuality) return;

    const { cpuLoad } = processingStatus;
    if (cpuLoad > performanceConfig.maxCPUUsage) {
      updateConfig({ quality: 'low' });
    } else if (cpuLoad < performanceConfig.maxCPUUsage * 0.5) {
      updateConfig({ quality: 'high' });
    }
  }, [processingStatus, performanceConfig, updateConfig]);

  // Memoized error state
  const hasError = useMemo(() => {
    return errorCountRef.current >= ERROR_RETRY_LIMIT;
  }, []);

  return (
    <VisualizationContainer
      ref={containerRef}
      width={width}
      height={height}
      className={className}
    >
      <Canvas
        ref={canvasRef}
        width={width * PIXEL_RATIO}
        height={height * PIXEL_RATIO}
        style={{
          width: `${width}px`,
          height: `${height}px`
        }}
      />
      {hasError && (
        <ErrorOverlay>
          Failed to initialize waveform visualization.
          Please check your browser's WebGL support.
        </ErrorOverlay>
      )}
    </VisualizationContainer>
  );
});

WaveformDisplay.displayName = 'WaveformDisplay';

export default WaveformDisplay;