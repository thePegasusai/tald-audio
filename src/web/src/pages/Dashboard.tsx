import React, { useCallback, useEffect, useRef } from 'react';
import styled from '@emotion/styled';
import { useWebGL } from '@react-hook/webgl';
import { ErrorBoundary } from 'react-error-boundary';
import { usePerformanceMonitor } from '@react-performance-monitor';

import AudioControls from '../components/audio/AudioControls';
import ProcessingStatus from '../components/visualization/ProcessingStatus';
import SpectrumAnalyzer from '../components/visualization/SpectrumAnalyzer';
import MainLayout from '../components/layout/MainLayout';
import useTheme from '../hooks/useTheme';

// Constants for performance monitoring
const PERFORMANCE_UPDATE_INTERVAL = 100;
const CPU_LOAD_THRESHOLD = 40;
const LATENCY_THRESHOLD = 10;

// Styled components
const DashboardContainer = styled.div`
  display: grid;
  grid-template-columns: 1fr 1fr;
  grid-template-rows: auto 1fr;
  gap: ${props => props.theme.spacing.lg};
  padding: ${props => props.theme.spacing.lg};
  height: 100%;

  @media ${props => props.theme.breakpoints.md.query} {
    grid-template-columns: 1fr;
    gap: ${props => props.theme.spacing.md};
    padding: ${props => props.theme.spacing.md};
  }

  ${props => props.theme.animation.reducedMotion.query} {
    transition: none;
  }
`;

const Section = styled.div`
  background-color: ${props => props.theme.colors.background.secondary};
  border-radius: 8px;
  padding: ${props => props.theme.spacing.lg};
  box-shadow: 0 2px 4px rgba(0, 0, 0, 0.1);
  position: relative;
  overflow: hidden;

  @media (forced-colors: active) {
    border: 1px solid ButtonText;
  }
`;

const VisualizationSection = styled.div`
  grid-column: span 2;
  display: flex;
  flex-direction: column;
  gap: ${props => props.theme.spacing.md};

  @media ${props => props.theme.breakpoints.md.query} {
    grid-column: span 1;
  }

  canvas {
    touch-action: none;
  }

  [data-webgl="true"] {
    will-change: transform;
  }
`;

// Error fallback component
const ErrorFallback = ({ error, resetErrorBoundary }) => (
  <Section role="alert" aria-live="assertive">
    <h2>Dashboard Error</h2>
    <p>An error occurred while loading the dashboard: {error.message}</p>
    <button onClick={resetErrorBoundary}>Retry</button>
  </Section>
);

const Dashboard: React.FC = () => {
  const theme = useTheme();
  const { isSupported: webglSupported } = useWebGL();
  const performanceMonitor = usePerformanceMonitor({
    interval: PERFORMANCE_UPDATE_INTERVAL
  });
  const visualizationRef = useRef<HTMLDivElement>(null);

  // Handle audio configuration changes with performance optimization
  const handleAudioConfigChange = useCallback((config: any) => {
    try {
      const metrics = performanceMonitor.getMetrics();
      
      if (metrics.cpuUsage > CPU_LOAD_THRESHOLD || metrics.latency > LATENCY_THRESHOLD) {
        console.warn('Performance threshold exceeded', metrics);
      }

      // Additional audio configuration logic would go here
    } catch (error) {
      console.error('Error updating audio configuration:', error);
    }
  }, [performanceMonitor]);

  // Clean up resources on unmount
  useEffect(() => {
    return () => {
      performanceMonitor.stop();
      if (visualizationRef.current) {
        const canvas = visualizationRef.current.querySelector('canvas');
        if (canvas) {
          const gl = canvas.getContext('webgl2') || canvas.getContext('webgl');
          if (gl) {
            gl.getExtension('WEBGL_lose_context')?.loseContext();
          }
        }
      }
    };
  }, [performanceMonitor]);

  return (
    <MainLayout>
      <ErrorBoundary FallbackComponent={ErrorFallback}>
        <DashboardContainer role="main" aria-label="Audio Dashboard">
          <Section role="region" aria-label="Audio Controls">
            <AudioControls
              disabled={!webglSupported}
              onError={(error) => console.error('Audio control error:', error)}
              analyticsEnabled={true}
            />
          </Section>

          <Section role="region" aria-label="Processing Status">
            <ProcessingStatus
              showTooltips={true}
              updateInterval={PERFORMANCE_UPDATE_INTERVAL}
              thresholds={{
                cpuLoad: CPU_LOAD_THRESHOLD,
                latency: LATENCY_THRESHOLD
              }}
            />
          </Section>

          <VisualizationSection
            ref={visualizationRef}
            role="region"
            aria-label="Audio Visualization"
          >
            <SpectrumAnalyzer
              width={visualizationRef.current?.clientWidth || 800}
              height={300}
              showGrid={true}
              showLabels={true}
              enableWebGL={webglSupported}
              targetFrameRate={60}
              colorScheme="spectrum"
              showTHDN={true}
              showPeakHold={true}
            />
          </VisualizationSection>
        </DashboardContainer>
      </ErrorBoundary>
    </MainLayout>
  );
};

export default Dashboard;