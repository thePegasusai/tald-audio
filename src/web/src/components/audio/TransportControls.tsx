import React, { useCallback, useEffect, useState } from 'react';
import styled from '@emotion/styled'; // v11.11.0
import { Button } from '../common/Button';
import { useAudio } from '../../hooks/useAudio';
import { AudioProcessingError, ProcessingQuality } from '../../types/audio.types';

// Constants for haptic feedback and performance monitoring
const HAPTIC_PATTERNS = {
  play: 'standard',
  stop: 'warning',
  error: 'error',
} as const;

const PERFORMANCE_THRESHOLDS = {
  maxLatency: 10, // ms
  maxLoad: 0.4, // 40% CPU utilization
  minBufferHealth: 0.8, // 80% buffer health
} as const;

// Styled components with enterprise-grade styling
const ControlsContainer = styled.div`
  display: flex;
  align-items: center;
  gap: ${({ theme }) => theme.spacing.md};
  padding: ${({ theme }) => theme.spacing.md};
  border-radius: 4px;
  background-color: ${({ theme }) => theme.colors.background.secondary};
  position: relative;
`;

const StatusIndicator = styled.div<{ status: 'processing' | 'error' | 'inactive' }>`
  position: absolute;
  top: -4px;
  right: -4px;
  width: 8px;
  height: 8px;
  border-radius: 50%;
  background-color: ${({ theme, status }) => 
    status === 'processing' ? theme.colors.status.success :
    status === 'error' ? theme.colors.status.error :
    theme.colors.status.inactive};
  animation: ${({ status }) => status === 'processing' ? 'pulse 1s infinite' : 'none'};

  @keyframes pulse {
    0% { opacity: 1; }
    50% { opacity: 0.5; }
    100% { opacity: 1; }
  }
`;

const MetricsDisplay = styled.div`
  font-family: ${({ theme }) => theme.typography.fontFamily.mono};
  font-size: ${({ theme }) => theme.typography.fontSizes.sm};
  color: ${({ theme }) => theme.colors.text.secondary};
  margin-left: ${({ theme }) => theme.spacing.md};
`;

// Interface definitions
interface TransportControlsProps {
  className?: string;
  disabled?: boolean;
  hapticIntensity?: number;
  onError?: (error: AudioProcessingError) => void;
}

/**
 * Enhanced audio transport controls component with real-time processing visualization
 * and comprehensive error handling.
 */
export const TransportControls: React.FC<TransportControlsProps> = ({
  className,
  disabled = false,
  hapticIntensity = 1.0,
  onError,
}) => {
  // State and hooks
  const {
    audioState,
    audioMetrics,
    webglSupport,
    startProcessing,
    stopProcessing,
    handleError: handleAudioError,
  } = useAudio();

  const [status, setStatus] = useState<'processing' | 'error' | 'inactive'>('inactive');

  // Performance monitoring
  useEffect(() => {
    if (audioState.isProcessing) {
      // Monitor critical performance metrics
      const hasPerformanceIssue = 
        audioState.latency > PERFORMANCE_THRESHOLDS.maxLatency ||
        audioState.currentLoad > PERFORMANCE_THRESHOLDS.maxLoad ||
        audioState.bufferHealth < PERFORMANCE_THRESHOLDS.minBufferHealth;

      if (hasPerformanceIssue) {
        handleError(AudioProcessingError.ProcessingOverload);
      }
    }
  }, [audioState]);

  // Error handling with automatic recovery attempts
  const handleError = useCallback((error: AudioProcessingError) => {
    console.error('Transport controls error:', error);
    setStatus('error');
    
    // Trigger error haptic feedback
    if ('vibrate' in navigator) {
      navigator.vibrate([100, 50, 100]);
    }

    // Attempt recovery for certain error types
    if (error === AudioProcessingError.BufferUnderrun) {
      stopProcessing();
      setTimeout(() => {
        startProcessing();
      }, 1000);
    }

    onError?.(error);
    handleAudioError(error);
  }, [onError, handleAudioError, startProcessing, stopProcessing]);

  // Enhanced play/pause handling with WebGL2 validation
  const handlePlayPause = useCallback(async () => {
    try {
      if (!webglSupport.supported) {
        throw new Error('WebGL2 support required for audio processing');
      }

      if (audioState.isProcessing) {
        await stopProcessing();
        setStatus('inactive');
      } else {
        await startProcessing();
        setStatus('processing');
      }

      // Trigger appropriate haptic feedback
      if ('vibrate' in navigator) {
        navigator.vibrate([hapticIntensity * 50]);
      }
    } catch (error) {
      handleError(AudioProcessingError.ConfigurationError);
    }
  }, [
    audioState.isProcessing,
    webglSupport.supported,
    hapticIntensity,
    startProcessing,
    stopProcessing,
    handleError,
  ]);

  // Emergency stop functionality
  const handleEmergencyStop = useCallback(() => {
    stopProcessing();
    setStatus('inactive');
    
    // Trigger stop haptic feedback
    if ('vibrate' in navigator) {
      navigator.vibrate([100]);
    }
  }, [stopProcessing]);

  return (
    <ControlsContainer className={className}>
      <Button
        variant="transport"
        disabled={disabled || !webglSupport.supported}
        pressed={audioState.isProcessing}
        hapticPattern={audioState.isProcessing ? 'standard' : 'warning'}
        onClick={handlePlayPause}
        aria-label={audioState.isProcessing ? 'Pause' : 'Play'}
      >
        {audioState.isProcessing ? '⏸️' : '▶️'}
      </Button>

      <Button
        variant="transport"
        disabled={disabled || !audioState.isProcessing}
        hapticPattern="warning"
        onClick={handleEmergencyStop}
        aria-label="Stop"
      >
        ⏹️
      </Button>

      <StatusIndicator status={status} />

      <MetricsDisplay>
        {audioState.isProcessing && (
          <>
            <div>Load: {(audioState.currentLoad * 100).toFixed(1)}%</div>
            <div>Latency: {audioState.latency.toFixed(1)}ms</div>
            <div>THD: {(audioMetrics.thd * 100).toFixed(4)}%</div>
          </>
        )}
      </MetricsDisplay>
    </ControlsContainer>
  );
};

export default TransportControls;