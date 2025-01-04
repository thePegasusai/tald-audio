import React, { useCallback, useRef } from 'react';
import styled from '@emotion/styled';
import { css } from '@emotion/react';
import { useDebounce } from 'use-debounce';
import { theme } from '../../styles/theme';

// Constants
const THUMB_SIZE = 16;
const TRACK_HEIGHT = 4;
const LARGE_STEP_MULTIPLIER = 10;
const TOUCH_TARGET_SIZE = 44;
const DEBOUNCE_DELAY = 16;
const DEFAULT_PRECISION = 2;

// Interfaces
interface SliderMark {
  value: number;
  label?: string;
}

interface SliderProps {
  min: number;
  max: number;
  step: number;
  value: number;
  onChange: (value: number) => void;
  disabled?: boolean;
  vertical?: boolean;
  size?: 'small' | 'medium' | 'large';
  label: string;
  ariaValueText?: string;
  marks?: SliderMark[];
  precision?: number;
}

// Styled Components
const SliderContainer = styled.div<{ vertical?: boolean; size?: string }>`
  position: relative;
  width: ${props => props.vertical ? `${TOUCH_TARGET_SIZE}px` : '100%'};
  height: ${props => props.vertical ? '200px' : `${TOUCH_TARGET_SIZE}px`};
  display: flex;
  align-items: center;
  padding: ${theme.spacing.xs};
  
  ${props => props.vertical && css`
    flex-direction: column;
    justify-content: center;
  `}
`;

const SliderInput = styled.input<{ vertical?: boolean; size?: string }>`
  -webkit-appearance: none;
  width: ${props => props.vertical ? TRACK_HEIGHT : '100%'}px;
  height: ${props => props.vertical ? '100%' : TRACK_HEIGHT}px;
  background: transparent;
  position: relative;
  transform: ${props => props.vertical ? 'rotate(-90deg)' : 'none'};
  cursor: ${props => props.disabled ? 'not-allowed' : 'pointer'};
  opacity: ${props => props.disabled ? 0.5 : 1};

  &::-webkit-slider-thumb {
    -webkit-appearance: none;
    width: ${THUMB_SIZE}px;
    height: ${THUMB_SIZE}px;
    border-radius: 50%;
    background: ${theme.colors.primary.main};
    border: 2px solid ${theme.colors.background.primary};
    cursor: ${props => props.disabled ? 'not-allowed' : 'pointer'};
    transition: transform ${theme.animation.duration.fast} ${theme.animation.easing.default};
    transform: scale(1);
    
    &:hover {
      transform: ${props => !props.disabled && 'scale(1.1)'};
    }
    
    &:active {
      transform: ${props => !props.disabled && 'scale(0.95)'};
    }
  }

  &::-webkit-slider-runnable-track {
    width: 100%;
    height: ${TRACK_HEIGHT}px;
    background: ${theme.colors.background.secondary};
    border-radius: ${TRACK_HEIGHT / 2}px;
  }

  &:focus {
    outline: none;
    
    &::-webkit-slider-thumb {
      box-shadow: 0 0 0 2px ${theme.colors.primary.light};
    }
  }

  ${theme.animation.reducedMotion.query} {
    transition: none;
    
    &::-webkit-slider-thumb {
      transition: none;
    }
  }
`;

const SliderTrack = styled.div<{ progress: number; vertical?: boolean }>`
  position: absolute;
  left: ${theme.spacing.xs};
  right: ${theme.spacing.xs};
  height: ${TRACK_HEIGHT}px;
  background: ${theme.colors.primary.main};
  border-radius: ${TRACK_HEIGHT / 2}px;
  transform-origin: left;
  transform: scaleX(${props => props.progress});
  transition: transform ${theme.animation.duration.normal} ${theme.animation.easing.default};
  
  ${props => props.vertical && css`
    width: ${TRACK_HEIGHT}px;
    height: calc(100% - ${theme.spacing.sm});
    transform: scaleY(${props.progress});
    transform-origin: bottom;
  `}
`;

const SliderMark = styled.div<{ position: number; vertical?: boolean }>`
  position: absolute;
  ${props => props.vertical ? 'bottom' : 'left'}: ${props => props.position}%;
  transform: ${props => props.vertical ? 'translateY(50%)' : 'translateX(-50%)'};
  display: flex;
  flex-direction: column;
  align-items: center;
  
  &::before {
    content: '';
    width: 2px;
    height: 8px;
    background: ${theme.colors.text.secondary};
  }
  
  span {
    margin-top: ${theme.spacing.xs};
    font-family: ${theme.typography.fontFamily.primary};
    font-size: ${theme.typography.fontSizes.xs};
    color: ${theme.colors.text.secondary};
  }
`;

// Main Component
const Slider: React.FC<SliderProps> = ({
  min,
  max,
  step,
  value,
  onChange,
  disabled = false,
  vertical = false,
  size = 'medium',
  label,
  ariaValueText,
  marks = [],
  precision = DEFAULT_PRECISION
}) => {
  const inputRef = useRef<HTMLInputElement>(null);
  const [debouncedOnChange] = useDebounce(onChange, DEBOUNCE_DELAY);

  const normalizeValue = useCallback((value: number): number => {
    return Number(Math.min(max, Math.max(min, value)).toFixed(precision));
  }, [max, min, precision]);

  const calculateProgress = useCallback((value: number): number => {
    return (value - min) / (max - min);
  }, [max, min]);

  const handleChange = useCallback((event: React.ChangeEvent<HTMLInputElement>) => {
    if (disabled) return;
    const newValue = normalizeValue(parseFloat(event.target.value));
    debouncedOnChange(newValue);
  }, [disabled, debouncedOnChange, normalizeValue]);

  const handleKeyDown = useCallback((event: React.KeyboardEvent<HTMLInputElement>) => {
    if (disabled) return;

    const stepSize = event.shiftKey ? step * LARGE_STEP_MULTIPLIER : step;
    let newValue = value;

    switch (event.key) {
      case 'ArrowUp':
      case 'ArrowRight':
        newValue = normalizeValue(value + stepSize);
        break;
      case 'ArrowDown':
      case 'ArrowLeft':
        newValue = normalizeValue(value - stepSize);
        break;
      case 'PageUp':
        newValue = normalizeValue(value + step * LARGE_STEP_MULTIPLIER);
        break;
      case 'PageDown':
        newValue = normalizeValue(value - step * LARGE_STEP_MULTIPLIER);
        break;
      case 'Home':
        newValue = min;
        break;
      case 'End':
        newValue = max;
        break;
      default:
        return;
    }

    event.preventDefault();
    onChange(newValue);
  }, [disabled, step, value, normalizeValue, onChange, min, max]);

  return (
    <SliderContainer vertical={vertical} size={size}>
      <SliderTrack progress={calculateProgress(value)} vertical={vertical} />
      <SliderInput
        ref={inputRef}
        type="range"
        min={min}
        max={max}
        step={step}
        value={value}
        onChange={handleChange}
        onKeyDown={handleKeyDown}
        disabled={disabled}
        vertical={vertical}
        size={size}
        aria-label={label}
        aria-valuemin={min}
        aria-valuemax={max}
        aria-valuenow={value}
        aria-valuetext={ariaValueText || `${value}`}
        aria-orientation={vertical ? 'vertical' : 'horizontal'}
      />
      {marks.map(mark => (
        <SliderMark
          key={mark.value}
          position={calculateProgress(mark.value) * 100}
          vertical={vertical}
        >
          {mark.label && <span>{mark.label}</span>}
        </SliderMark>
      ))}
    </SliderContainer>
  );
};

export default Slider;