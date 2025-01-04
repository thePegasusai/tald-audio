import React, { useCallback, useEffect, useMemo } from 'react';
import styled from '@emotion/styled';
import VolumeControl, { VolumeControlProps } from './VolumeControl';
import TransportControls from './TransportControls';
import { useAudio } from '../../hooks/useAudio';
import useTheme from '../../hooks/useTheme';
import { ErrorBoundary } from 'react-error-boundary';
import { useWebGL2 } from '@react-hook/webgl';
import { AudioProcessingError, ProcessingQuality } from '../../types/audio.types';

// Constants for WebGL2 requirements and quality thresholds
const WEBGL2_REQUIREMENTS = {
  minTextureSize: 8192,
  floatTextureSupport: true,
  vertexArrayObjects: true
};

const QUALITY_THRESHOLDS = {
  maxLatency: 10, // ms
  maxLoad: 0.4, // 40% CPU utilization
  minBufferHealth: 0.8, // 80% buffer health
  targetTHD: 0.0005 // 0.05%
};

// Styled components
const ControlsContainer = styled.div`
  display: flex;
  flex-direction: column;
  gap: ${props => props.theme.spacing.lg};
  padding: ${props => props.theme.spacing.xl};
  background-color: ${props => props.theme.colors.background.secondary};
  border-radius: 8px;
  box-shadow: 0 4px 6px rgba(0, 0, 0, 0.1);
  width: 100%;
  max-width: 800px;
  position: relative;

  @media ${props => props.theme.breakpoints.sm.query} {
    padding: ${props => props.theme.spacing.md};
    gap: ${props => props.theme.spacing.md};
  }

  ${props => props.theme.animation.reducedMotion.query} {
    transition: none;
  }
`;

const ControlsRow = styled.div`
  display: flex;
  align-items: center;
  gap: ${props => props.theme.spacing.md};
  width: 100%;
`;

const QualityIndicator = styled.div<{ quality: number }>`
  position: absolute;
  top: ${props => props.theme.spacing.sm};
  right: ${props => props.theme.spacing.sm};
  width: 8px;
  height: 8px;
  border-radius: 50%;
  background-color: ${props => 
    props.quality > 0.9 ? props.theme.colors.status.success :
    props.quality > 0.7 ? props.theme.colors.status.warning :
    props.theme.colors.status.error
  };
  transition: background-color ${props => props.theme.animation.duration.normal} ${props => props.theme.animation.easing.default};
`;

// Error fallback component
const ErrorFallback = ({ error, resetErrorBoundary }) => (
  <div role="alert">
    <p>Audio processing error: {error.message}</p>
    <button onClick={resetErrorBoundary}>Reset Audio System</button>
  </div>
);

// Props interface
interface AudioControlsProps {
  className?: string;
  disabled?: boolean;
  onError?: (error: Error) => void;
  analyticsEnabled?: boolean;
}

const AudioControls: React.FC<AudioControlsProps> = ({
  className,
  disabled = false,
  onError,
  analyticsEnabled = true
}) => {
  const { audioState, audioMetrics, webglSupport, handleError } = useAudio();
  const theme = useTheme();
  const { isSupported: webgl2Supported } = useWebGL2();

  // Validate WebGL2 support and capabilities
  useEffect(() => {
    if (!webgl2Supported || !webglSupport.supported) {
      handleError(new Error('WebGL2 support required for high-quality audio processing'));
    }
  }, [webgl2Supported, webglSupport.supported, handleError]);

  // Calculate overall quality score
  const qualityScore = useMemo(() => {
    if (!audioState.isProcessing) return 1;

    const latencyScore = Math.max(0, 1 - (audioState.latency / QUALITY_THRESHOLDS.maxLatency));
    const loadScore = Math.max(0, 1 - (audioState.currentLoad / QUALITY_THRESHOLDS.maxLoad));
    const bufferScore = audioState.bufferHealth / QUALITY_THRESHOLDS.minBufferHealth;
    const thdScore = Math.max(0, 1 - (audioMetrics.thd / QUALITY_THRESHOLDS.targetTHD));

    return (latencyScore + loadScore + bufferScore + thdScore) / 4;
  }, [audioState, audioMetrics]);

  // Handle quality changes
  const handleQualityChange = useCallback((quality: ProcessingQuality) => {
    try {
      if (webgl2Supported && webglSupport.supported) {
        // Initialize WebGL2 context with optimal settings
        const canvas = document.createElement('canvas');
        const gl = canvas.getContext('webgl2');
        
        if (gl) {
          gl.getExtension('EXT_color_buffer_float');
          gl.getExtension('OES_texture_float_linear');
        }
      }
    } catch (error) {
      handleError(error);
      onError?.(error);
    }
  }, [webgl2Supported, webglSupport.supported, handleError, onError]);

  // Handle errors with recovery attempts
  const handleProcessingError = useCallback((error: Error) => {
    console.error('Audio processing error:', error);
    handleError(error);
    onError?.(error);
  }, [handleError, onError]);

  return (
    <ErrorBoundary
      FallbackComponent={ErrorFallback}
      onReset={() => window.location.reload()}
    >
      <ControlsContainer className={className}>
        <QualityIndicator quality={qualityScore} />
        
        <ControlsRow>
          <TransportControls
            disabled={disabled}
            hapticIntensity={1.0}
            onError={handleProcessingError}
          />
        </ControlsRow>

        <ControlsRow>
          <VolumeControl
            disabled={disabled}
            vertical={false}
            step={0.1}
            ariaLabel="Master Volume"
          />
        </ControlsRow>

        {analyticsEnabled && audioState.isProcessing && (
          <ControlsRow>
            <div>
              <div>THD: {(audioMetrics.thd * 100).toFixed(4)}%</div>
              <div>SNR: {audioMetrics.snr.toFixed(1)} dB</div>
              <div>Latency: {audioState.latency.toFixed(1)} ms</div>
            </div>
          </ControlsRow>
        )}
      </ControlsContainer>
    </ErrorBoundary>
  );
};

export default React.memo(AudioControls);