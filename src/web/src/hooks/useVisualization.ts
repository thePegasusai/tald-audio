/**
 * @fileoverview Enhanced React hook for real-time audio visualization with WebGL acceleration
 * @version 1.0.0
 * @package react ^18.2.0
 * @package @webgl/spectrum-analyzer ^2.0.0
 * @package @webgl/waveform-renderer ^1.0.0
 * @package @performance-monitor/core ^1.0.0
 */

import { useState, useEffect, useCallback, useRef } from 'react';
import { useErrorBoundary } from 'react';
import {
  SpectrumData,
  WaveformData,
  VisualizationConfig,
  ProcessingStatus,
  DEFAULT_VISUALIZATION_CONFIG,
  isValidFFTSize,
  isValidFrequency,
  isValidDecibels
} from '../../types/visualization.types';
import { WebGLSpectrumAnalyzer } from '@webgl/spectrum-analyzer';
import { OptimizedWaveformRenderer } from '@webgl/waveform-renderer';
import { PerformanceMonitor } from '@performance-monitor/core';

// Constants for performance optimization
const ANIMATION_FRAME_RATE = 60;
const UPDATE_INTERVAL_MS = 1000 / ANIMATION_FRAME_RATE;
const MAX_CPU_USAGE_PERCENT = 40;
const WEBGL_CONTEXT_ATTRIBUTES = {
  alpha: false,
  antialias: false,
  depth: false,
  powerPreference: 'high-performance'
};
const PERFORMANCE_ALERT_THRESHOLD = 35;
const LATENCY_THRESHOLD_MS = 10;

/**
 * Custom hook for managing real-time audio visualization with WebGL acceleration
 * and comprehensive performance monitoring
 */
export const useVisualization = (config: VisualizationConfig = DEFAULT_VISUALIZATION_CONFIG) => {
  // State management
  const [spectrumData, setSpectrumData] = useState<SpectrumData | null>(null);
  const [waveformData, setWaveformData] = useState<WaveformData | null>(null);
  const [processingStatus, setProcessingStatus] = useState<ProcessingStatus>({
    cpuLoad: 0,
    bufferSize: 0,
    latency: 0,
    thdPlusN: 0,
    signalToNoise: 0,
    powerEfficiency: 0
  });
  const [isActive, setIsActive] = useState(false);

  // Refs for performance optimization
  const animationFrameRef = useRef<number>();
  const lastUpdateTimeRef = useRef<number>(0);
  const webglContextRef = useRef<WebGLRenderingContext | null>(null);
  const spectrumAnalyzerRef = useRef<WebGLSpectrumAnalyzer | null>(null);
  const waveformRendererRef = useRef<OptimizedWaveformRenderer | null>(null);
  const performanceMonitorRef = useRef<PerformanceMonitor | null>(null);

  // Error boundary integration
  const { showBoundary } = useErrorBoundary();

  /**
   * Initialize WebGL context with fallback handling
   */
  const initializeWebGLContext = useCallback(() => {
    try {
      const canvas = document.createElement('canvas');
      const context = canvas.getContext('webgl2', WEBGL_CONTEXT_ATTRIBUTES) ||
                     canvas.getContext('webgl', WEBGL_CONTEXT_ATTRIBUTES);
      
      if (!context) {
        throw new Error('WebGL not supported');
      }

      webglContextRef.current = context;
      return context;
    } catch (error) {
      showBoundary(error);
      return null;
    }
  }, [showBoundary]);

  /**
   * Initialize visualization components
   */
  const initializeComponents = useCallback(() => {
    if (!webglContextRef.current) return;

    try {
      spectrumAnalyzerRef.current = new WebGLSpectrumAnalyzer(webglContextRef.current, {
        fftSize: config.fftSize,
        smoothingTimeConstant: config.smoothingTimeConstant,
        minDecibels: config.minDecibels,
        maxDecibels: config.maxDecibels
      });

      waveformRendererRef.current = new OptimizedWaveformRenderer(webglContextRef.current, {
        bufferSize: config.fftSize * 2,
        colorScheme: config.colorScheme
      });

      performanceMonitorRef.current = new PerformanceMonitor({
        sampleInterval: UPDATE_INTERVAL_MS,
        maxSamples: 60
      });
    } catch (error) {
      showBoundary(error);
    }
  }, [config, showBoundary]);

  /**
   * Monitor and update performance metrics
   */
  const updatePerformanceMetrics = useCallback(() => {
    if (!performanceMonitorRef.current) return;

    const metrics = performanceMonitorRef.current.getMetrics();
    const cpuLoad = metrics.cpuUsage;
    const latency = metrics.processingLatency;

    // Alert on performance issues
    if (cpuLoad > PERFORMANCE_ALERT_THRESHOLD || latency > LATENCY_THRESHOLD_MS) {
      console.warn('Performance degradation detected', { cpuLoad, latency });
    }

    setProcessingStatus(prev => ({
      ...prev,
      cpuLoad,
      latency,
      powerEfficiency: metrics.powerEfficiency
    }));
  }, []);

  /**
   * Main visualization loop with frame throttling
   */
  const visualizationLoop = useCallback(() => {
    if (!isActive) return;

    const currentTime = performance.now();
    const timeSinceLastUpdate = currentTime - lastUpdateTimeRef.current;

    if (timeSinceLastUpdate >= UPDATE_INTERVAL_MS) {
      try {
        // Update spectrum analysis
        if (spectrumAnalyzerRef.current) {
          const spectrumResult = spectrumAnalyzerRef.current.analyze();
          setSpectrumData(spectrumResult);
        }

        // Update waveform visualization
        if (waveformRendererRef.current) {
          const waveformResult = waveformRendererRef.current.render();
          setWaveformData(waveformResult);
        }

        updatePerformanceMetrics();
        lastUpdateTimeRef.current = currentTime;
      } catch (error) {
        showBoundary(error);
      }
    }

    animationFrameRef.current = requestAnimationFrame(visualizationLoop);
  }, [isActive, updatePerformanceMetrics, showBoundary]);

  /**
   * Start visualization
   */
  const startVisualization = useCallback(() => {
    if (!webglContextRef.current) {
      initializeWebGLContext();
      initializeComponents();
    }
    setIsActive(true);
  }, [initializeWebGLContext, initializeComponents]);

  /**
   * Stop visualization
   */
  const stopVisualization = useCallback(() => {
    setIsActive(false);
    if (animationFrameRef.current) {
      cancelAnimationFrame(animationFrameRef.current);
    }
  }, []);

  /**
   * Update visualization configuration
   */
  const updateConfig = useCallback((newConfig: Partial<VisualizationConfig>) => {
    if (newConfig.fftSize && !isValidFFTSize(newConfig.fftSize)) {
      throw new Error('Invalid FFT size');
    }
    if (newConfig.minFrequency && !isValidFrequency(newConfig.minFrequency)) {
      throw new Error('Invalid minimum frequency');
    }
    if (newConfig.maxFrequency && !isValidFrequency(newConfig.maxFrequency)) {
      throw new Error('Invalid maximum frequency');
    }
    if (newConfig.minDecibels && !isValidDecibels(newConfig.minDecibels)) {
      throw new Error('Invalid minimum decibels');
    }

    // Update component configurations
    if (spectrumAnalyzerRef.current) {
      spectrumAnalyzerRef.current.updateConfig(newConfig);
    }
    if (waveformRendererRef.current) {
      waveformRendererRef.current.updateConfig(newConfig);
    }
  }, []);

  // Effect for visualization loop management
  useEffect(() => {
    if (isActive) {
      animationFrameRef.current = requestAnimationFrame(visualizationLoop);
    }
    return () => {
      if (animationFrameRef.current) {
        cancelAnimationFrame(animationFrameRef.current);
      }
    };
  }, [isActive, visualizationLoop]);

  // Cleanup effect
  useEffect(() => {
    return () => {
      stopVisualization();
      if (spectrumAnalyzerRef.current) {
        spectrumAnalyzerRef.current.dispose();
      }
      if (waveformRendererRef.current) {
        waveformRendererRef.current.dispose();
      }
      if (performanceMonitorRef.current) {
        performanceMonitorRef.current.dispose();
      }
    };
  }, [stopVisualization]);

  return {
    spectrumData,
    waveformData,
    processingStatus,
    isActive,
    startVisualization,
    stopVisualization,
    updateConfig
  };
};