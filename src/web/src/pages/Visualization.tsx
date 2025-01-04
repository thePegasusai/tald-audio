/**
 * TALD UNIA Audio System - Main Visualization Page Component
 * Version: 1.0.0
 * 
 * Integrates WebGL-accelerated spectrum analyzer, optimized waveform display,
 * professional VU meter, and enhanced processing status monitoring.
 */

import React, { useEffect, useState, useCallback, useRef, useMemo } from 'react';
import styled from '@emotion/styled';
import { useSelector, useDispatch } from 'react-redux';

// Component imports
import SpectrumAnalyzer from '../components/visualization/SpectrumAnalyzer';
import WaveformDisplay from '../components/visualization/WaveformDisplay';
import VUMeter from '../components/visualization/VUMeter';
import ProcessingStatus from '../components/visualization/ProcessingStatus';

// Hook imports
import { useVisualization } from '../hooks/useVisualization';

// Constants
const DEFAULT_UPDATE_INTERVAL_MS = 16.7; // ~60fps
const MIN_COMPONENT_WIDTH = 320;
const MIN_COMPONENT_HEIGHT = 240;
const WEBGL_CONTEXT_OPTIONS = { antialias: true, alpha: false };
const PERFORMANCE_THRESHOLDS = { cpu: 40, latency: 10 };
const ANIMATION_FRAME_BUDGET_MS = 14;

// Styled components
const VisualizationContainer = styled.div`
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(${MIN_COMPONENT_WIDTH}px, 1fr));
  gap: ${({ theme }) => theme.spacing.md};
  padding: ${({ theme }) => theme.spacing.md};
  background-color: ${({ theme }) => theme.colors.background.primary};
  min-height: 100vh;

  @media ${({ theme }) => theme.breakpoints.md.query} {
    grid-template-columns: 1fr;
  }
`;

const VisualizationPanel = styled.div`
  display: flex;
  flex-direction: column;
  gap: ${({ theme }) => theme.spacing.sm};
  background-color: ${({ theme }) => theme.colors.background.secondary};
  border-radius: 4px;
  padding: ${({ theme }) => theme.spacing.md};
  box-shadow: 0 2px 4px rgba(0, 0, 0, 0.1);
`;

interface VisualizationPageProps {
  className?: string;
  theme?: any;
  reducedMotion?: boolean;
  glOptions?: WebGLContextOptions;
}

const VisualizationPage: React.FC<VisualizationPageProps> = React.memo(({
  className,
  theme,
  reducedMotion = false,
  glOptions = WEBGL_CONTEXT_OPTIONS
}) => {
  // State and refs
  const containerRef = useRef<HTMLDivElement>(null);
  const [dimensions, setDimensions] = useState({ width: 0, height: 0 });
  const [isPlaying, setIsPlaying] = useState(false);

  // Redux state
  const dispatch = useDispatch();

  // Visualization hook
  const {
    spectrumData,
    waveformData,
    processingStatus,
    startVisualization,
    stopVisualization,
    updateConfig
  } = useVisualization({
    fftSize: 2048,
    smoothingTimeConstant: 0.8,
    minDecibels: -90,
    maxDecibels: -10,
    minFrequency: 20,
    maxFrequency: 20000,
    updateInterval: DEFAULT_UPDATE_INTERVAL_MS,
    colorScheme: 'professional'
  });

  // Handle resize with debouncing
  const handleResize = useCallback(() => {
    if (!containerRef.current) return;

    const { width, height } = containerRef.current.getBoundingClientRect();
    setDimensions({
      width: Math.max(width, MIN_COMPONENT_WIDTH),
      height: Math.max(height / 2, MIN_COMPONENT_HEIGHT)
    });
  }, []);

  // Initialize dimensions and start visualization
  useEffect(() => {
    handleResize();
    const resizeObserver = new ResizeObserver(handleResize);
    
    if (containerRef.current) {
      resizeObserver.observe(containerRef.current);
    }

    startVisualization();
    setIsPlaying(true);

    return () => {
      resizeObserver.disconnect();
      stopVisualization();
      setIsPlaying(false);
    };
  }, [handleResize, startVisualization, stopVisualization]);

  // Monitor performance and adapt quality
  useEffect(() => {
    if (processingStatus.cpuLoad > PERFORMANCE_THRESHOLDS.cpu) {
      updateConfig({
        fftSize: 1024,
        updateInterval: DEFAULT_UPDATE_INTERVAL_MS * 2
      });
    }
  }, [processingStatus.cpuLoad, updateConfig]);

  // Memoized component props
  const spectrumProps = useMemo(() => ({
    width: dimensions.width,
    height: dimensions.height * 0.4,
    showGrid: true,
    showLabels: true,
    enableWebGL: true,
    showTHDN: true,
    showPeakHold: true,
    colorScheme: 'professional'
  }), [dimensions]);

  const waveformProps = useMemo(() => ({
    width: dimensions.width,
    height: dimensions.height * 0.3,
    isPlaying,
    quality: processingStatus.cpuLoad > PERFORMANCE_THRESHOLDS.cpu ? 'balanced' : 'high',
    theme: {
      waveformColor: theme?.colors?.primary?.main || '#00ff00',
      backgroundColor: theme?.colors?.background?.secondary || '#000000',
      lineWidth: 2
    }
  }), [dimensions, isPlaying, processingStatus.cpuLoad, theme]);

  return (
    <VisualizationContainer
      ref={containerRef}
      className={className}
      role="main"
      aria-label="Audio Visualization Dashboard"
    >
      <VisualizationPanel>
        <SpectrumAnalyzer
          {...spectrumProps}
          aria-label="Frequency Spectrum Analyzer"
        />
        <WaveformDisplay
          {...waveformProps}
          aria-label="Audio Waveform Display"
        />
        <VUMeter
          audioContext={spectrumData?.audioContext}
          width={dimensions.width}
          height={dimensions.height * 0.15}
          showPeakHold={true}
          showNumericReadout={true}
          colorTheme="professional"
          aria-label="Volume Unit Meter"
        />
        <ProcessingStatus
          showTooltips={true}
          updateInterval={DEFAULT_UPDATE_INTERVAL_MS}
          thresholds={PERFORMANCE_THRESHOLDS}
          aria-label="Audio Processing Status"
        />
      </VisualizationPanel>
    </VisualizationContainer>
  );
});

VisualizationPage.displayName = 'VisualizationPage';

export default VisualizationPage;