import React, { useCallback, useMemo, useState } from 'react';
import styled from '@emotion/styled';
import { analytics } from '@segment/analytics-next';
import { Slider, SliderProps, SliderChangeEvent } from '../common/Slider';
import { useAudio } from '../../hooks/useAudio';
import { ProcessingQuality, AudioProcessingError } from '../../types/audio.types';

// Constants
const MIN_ENHANCEMENT = 0;
const MAX_ENHANCEMENT = 100;
const ENHANCEMENT_STEP = 1;
const PERFORMANCE_THRESHOLD_MS = 10;
const ERROR_RETRY_ATTEMPTS = 3;

// Styled Components
const ControlsContainer = styled.div`
  display: flex;
  flex-direction: column;
  gap: ${props => props.theme.spacing.md};
  padding: ${props => props.theme.spacing.md};
  background: ${props => props.theme.colors.background.secondary};
  border-radius: 8px;
  
  @media ${props => props.theme.breakpoints.sm.query} {
    padding: ${props => props.theme.spacing.sm};
  }

  ${props => props.theme.animation.reducedMotion.query} {
    transition: none;
  }
`;

const ControlGroup = styled.div`
  display: flex;
  flex-direction: column;
  gap: ${props => props.theme.spacing.sm};
`;

const Label = styled.label`
  color: ${props => props.theme.colors.text.primary};
  font-family: ${props => props.theme.typography.fontFamily.primary};
  font-size: ${props => props.theme.typography.fontSizes.sm};
  font-weight: ${props => props.theme.typography.fontWeights.medium};
`;

const QualitySelect = styled.select`
  width: 100%;
  padding: ${props => props.theme.spacing.sm};
  background: ${props => props.theme.colors.background.primary};
  color: ${props => props.theme.colors.text.primary};
  border: 1px solid ${props => props.theme.colors.primary.main};
  border-radius: 4px;
  font-family: ${props => props.theme.typography.fontFamily.primary};
  font-size: ${props => props.theme.typography.fontSizes.sm};
  cursor: pointer;

  &:disabled {
    opacity: 0.5;
    cursor: not-allowed;
  }
`;

const StatusIndicator = styled.div<{ active: boolean }>`
  display: flex;
  align-items: center;
  gap: ${props => props.theme.spacing.sm};
  color: ${props => props.active ? props.theme.colors.status.success : props.theme.colors.text.secondary};
  font-size: ${props => props.theme.typography.fontSizes.sm};

  &::before {
    content: '';
    width: 8px;
    height: 8px;
    border-radius: 50%;
    background: ${props => props.active ? props.theme.colors.status.success : props.theme.colors.text.secondary};
  }
`;

// Interfaces
interface EnhancementControlsProps {
  disabled?: boolean;
  onQualityChange?: (quality: ProcessingQuality) => void;
  onError?: (error: AudioProcessingError) => void;
  className?: string;
}

// Main Component
const EnhancementControls: React.FC<EnhancementControlsProps> = ({
  disabled = false,
  onQualityChange,
  onError,
  className
}) => {
  const { audioState, updateConfig } = useAudio();
  const [retryCount, setRetryCount] = useState(0);

  const handleEnhancementChange = useCallback(async (value: number) => {
    try {
      // Validate enhancement level
      const enhancementLevel = Math.min(MAX_ENHANCEMENT, Math.max(MIN_ENHANCEMENT, value));

      // Update audio configuration
      await updateConfig({
        aiProcessingStatus: {
          ...audioState.aiProcessingStatus,
          enhancementLevel,
          lastUpdateTimestamp: Date.now()
        }
      });

      // Track enhancement change
      analytics.track('Audio Enhancement Changed', {
        value: enhancementLevel,
        processingLoad: audioState.currentLoad,
        timestamp: Date.now()
      });

      // Reset retry count on success
      setRetryCount(0);
    } catch (error) {
      if (retryCount < ERROR_RETRY_ATTEMPTS) {
        setRetryCount(prev => prev + 1);
        // Retry after delay
        setTimeout(() => handleEnhancementChange(value), 1000);
      } else {
        onError?.(AudioProcessingError.AIProcessingError);
      }
    }
  }, [audioState, updateConfig, onError, retryCount]);

  const handleQualityChange = useCallback((event: React.ChangeEvent<HTMLSelectElement>) => {
    const quality = event.target.value as ProcessingQuality;
    
    try {
      updateConfig({ processingQuality: quality });
      onQualityChange?.(quality);

      // Track quality change
      analytics.track('Processing Quality Changed', {
        quality,
        currentLoad: audioState.currentLoad,
        timestamp: Date.now()
      });
    } catch (error) {
      onError?.(AudioProcessingError.ConfigurationError);
    }
  }, [updateConfig, onQualityChange, onError, audioState.currentLoad]);

  const enhancementMarks = useMemo(() => [
    { value: 0, label: 'Off' },
    { value: 50, label: '50%' },
    { value: 100, label: 'Max' }
  ], []);

  return (
    <ControlsContainer className={className}>
      <ControlGroup>
        <Label htmlFor="enhancement-level">AI Enhancement Level</Label>
        <Slider
          id="enhancement-level"
          min={MIN_ENHANCEMENT}
          max={MAX_ENHANCEMENT}
          step={ENHANCEMENT_STEP}
          value={audioState.aiProcessingStatus.enhancementLevel}
          onChange={handleEnhancementChange}
          disabled={disabled}
          label="AI Enhancement Level"
          marks={enhancementMarks}
          ariaValueText={`Enhancement level ${audioState.aiProcessingStatus.enhancementLevel}%`}
        />
        <StatusIndicator active={audioState.aiProcessingStatus.enabled}>
          AI Processing {audioState.aiProcessingStatus.enabled ? 'Active' : 'Inactive'}
        </StatusIndicator>
      </ControlGroup>

      <ControlGroup>
        <Label htmlFor="processing-quality">Processing Quality</Label>
        <QualitySelect
          id="processing-quality"
          value={audioState.aiProcessingStatus.enabled ? ProcessingQuality.Maximum : ProcessingQuality.PowerSaver}
          onChange={handleQualityChange}
          disabled={disabled}
        >
          <option value={ProcessingQuality.Maximum}>Maximum Quality</option>
          <option value={ProcessingQuality.Balanced}>Balanced</option>
          <option value={ProcessingQuality.PowerSaver}>Power Saver</option>
        </QualitySelect>
      </ControlGroup>

      <StatusIndicator active={audioState.currentLoad < PERFORMANCE_THRESHOLD_MS}>
        System Load: {Math.round(audioState.currentLoad)}ms
      </StatusIndicator>
    </ControlsContainer>
  );
};

export default React.memo(EnhancementControls);