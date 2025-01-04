import React, { useCallback, useMemo } from 'react';
import styled from '@emotion/styled';
import { useSelector, useDispatch } from 'react-redux';
import Slider, { SliderProps } from '../common/Slider';
import { useAudio } from '../../hooks/useAudio';
import useTheme from '../../hooks/useTheme';

// Constants for volume control
const MIN_DB = -60;
const MAX_DB = 12;
const DB_STEP = 0.1;
const VOLUME_RAMP_MS = 50;
const VOLUME_UPDATE_DEBOUNCE = 16;

// Interface for component props
interface VolumeControlProps {
  disabled?: boolean;
  vertical?: boolean;
  className?: string;
  step?: number;
  ariaLabel?: string;
}

// Styled components
const VolumeControlContainer = styled.div<{ vertical: boolean }>`
  display: flex;
  flex-direction: ${props => props.vertical ? 'column' : 'row'};
  align-items: center;
  gap: ${props => props.theme.spacing.md};
  width: ${props => props.vertical ? '44px' : '100%'};
  height: ${props => props.vertical ? '200px' : '44px'};
  padding: ${props => props.theme.spacing.xs};
  position: relative;

  @media ${props => props.theme.breakpoints.sm.query} {
    width: ${props => props.vertical ? '44px' : '100%'};
    height: ${props => props.vertical ? '150px' : '44px'};
  }

  ${props => props.theme.animation.reducedMotion.query} {
    transition: none;
  }
`;

const VolumeLabel = styled.span`
  font-family: ${props => props.theme.typography.fontFamily.mono};
  font-size: ${props => props.theme.typography.fontSizes.sm};
  color: ${props => props.theme.colors.text.primary};
  min-width: 64px;
  text-align: right;
  user-select: none;
  
  @media (forced-colors: active) {
    color: CanvasText;
  }
`;

// Convert between linear and dB scales
const linearToDb = (value: number): number => {
  if (value <= 0) return MIN_DB;
  return 20 * Math.log10(value);
};

const dbToLinear = (db: number): number => {
  if (db <= MIN_DB) return 0;
  return Math.pow(10, db / 20);
};

const VolumeControl: React.FC<VolumeControlProps> = ({
  disabled = false,
  vertical = false,
  className,
  step = DB_STEP,
  ariaLabel = 'Volume Control'
}) => {
  const { audioState, updateConfig } = useAudio();
  const theme = useTheme();

  // Convert dB value to linear for slider
  const normalizedValue = useMemo(() => {
    const currentDb = audioState.volume || 0;
    return (currentDb - MIN_DB) / (MAX_DB - MIN_DB);
  }, [audioState.volume]);

  // Format volume label with proper dB notation
  const formatVolumeLabel = useCallback((value: number) => {
    const db = linearToDb(value);
    if (db <= MIN_DB) return '-∞ dB';
    const formattedDb = db.toFixed(1);
    return `${db > 0 ? '+' : ''}${formattedDb} dB`;
  }, []);

  // Handle volume changes with smooth transitions
  const handleVolumeChange = useCallback((value: number) => {
    if (disabled) return;

    try {
      // Convert linear slider value to dB
      const dbValue = linearToDb(value);
      
      // Clamp and round to nearest step
      const clampedDb = Math.max(MIN_DB, Math.min(MAX_DB, dbValue));
      const roundedDb = Math.round(clampedDb / DB_STEP) * DB_STEP;

      // Update audio configuration with ramping
      updateConfig({
        volume: roundedDb,
        rampTimeMs: VOLUME_RAMP_MS
      });
    } catch (error) {
      console.error('Error updating volume:', error);
    }
  }, [disabled, updateConfig]);

  const sliderProps: SliderProps = {
    min: 0,
    max: 1,
    step: step / (MAX_DB - MIN_DB),
    value: normalizedValue,
    onChange: handleVolumeChange,
    disabled,
    vertical,
    label: ariaLabel,
    ariaValueText: formatVolumeLabel(normalizedValue),
    marks: [
      { value: 0, label: MIN_DB.toString() },
      { value: 0.5, label: '0' },
      { value: 1, label: `+${MAX_DB}` }
    ]
  };

  return (
    <VolumeControlContainer 
      vertical={vertical} 
      className={className}
      role="group"
      aria-label={ariaLabel}
    >
      <VolumeLabel aria-live="polite">
        {formatVolumeLabel(normalizedValue)}
      </VolumeLabel>
      <Slider {...sliderProps} />
    </VolumeControlContainer>
  );
};

export default VolumeControl;