import styled from '@emotion/styled'; // v11.11.0
import { css } from '@emotion/react'; // v11.11.0
import { colors, typography, spacing, breakpoints } from './theme';
import { createAnimation } from './animations';

// Constants for accessibility and performance
const MIN_TOUCH_TARGET = 44;
const TRANSITION_DURATION = 200;
const MIN_CONTRAST_RATIO = 4.5;
const ANIMATION_FPS = 60;

// Base button styles with enhanced accessibility
const baseButtonStyles = css`
  min-width: ${MIN_TOUCH_TARGET}px;
  min-height: ${MIN_TOUCH_TARGET}px;
  padding: ${spacing.sm} ${spacing.md};
  font-family: ${typography.fontFamily.primary};
  font-size: ${typography.fontSizes.md};
  font-weight: ${typography.fontWeights.medium};
  color: ${colors.text.primary};
  background: ${colors.primary.main};
  border: none;
  border-radius: 8px;
  cursor: pointer;
  transition: transform ${TRANSITION_DURATION}ms ${colors.animation.easing.default},
              background ${TRANSITION_DURATION}ms ${colors.animation.easing.default};
  will-change: transform, background;
  transform: translate3d(0, 0, 0);
  
  &:hover {
    background: ${colors.primary.light};
    transform: translate3d(0, -2px, 0);
  }

  &:active {
    transform: translate3d(0, 1px, 0);
  }

  &:focus-visible {
    outline: 2px solid ${colors.primary.light};
    outline-offset: 2px;
  }

  @media (prefers-reduced-motion: reduce) {
    transition: none;
    transform: none;

    &:hover, &:active {
      transform: none;
    }
  }

  ${breakpoints.sm.query} {
    width: 100%;
  }
`;

// Enhanced button component
export const Button = styled.button`
  ${baseButtonStyles}
`;

// Audio control slider with optimized performance
export const Slider = styled.input`
  width: 100%;
  height: ${spacing.md};
  margin: ${spacing.sm} 0;
  background: ${colors.background.secondary};
  border-radius: 4px;
  cursor: pointer;
  -webkit-appearance: none;

  &::-webkit-slider-thumb {
    -webkit-appearance: none;
    width: ${MIN_TOUCH_TARGET}px;
    height: ${MIN_TOUCH_TARGET}px;
    background: ${colors.primary.main};
    border-radius: 50%;
    transition: transform ${TRANSITION_DURATION}ms ${colors.animation.easing.default};
    will-change: transform;
    transform: translate3d(0, 0, 0);
  }

  &::-webkit-slider-thumb:hover {
    transform: scale(1.1) translate3d(0, 0, 0);
  }

  @media (prefers-reduced-motion: reduce) {
    &::-webkit-slider-thumb {
      transition: none;
    }
  }
`;

// GPU-accelerated VU meter component
export const VUMeter = styled.div<{ level: number }>`
  width: 100%;
  height: ${spacing.lg};
  background: ${colors.background.secondary};
  border-radius: 4px;
  overflow: hidden;
  will-change: transform;
  transform: translate3d(0, 0, 0);

  &::after {
    content: '';
    display: block;
    width: ${props => props.level}%;
    height: 100%;
    background: ${colors.primary.main};
    transition: width ${1000 / ANIMATION_FPS}ms linear;
    will-change: width;
    transform: translate3d(0, 0, 0);
  }

  @media (prefers-reduced-motion: reduce) {
    &::after {
      transition: none;
    }
  }
`;

// WebGL-accelerated waveform display
export const WaveformDisplay = styled.canvas`
  width: 100%;
  height: ${spacing['2xl']};
  background: ${colors.background.secondary};
  border-radius: 4px;
  will-change: transform;
  transform: translate3d(0, 0, 0);
`;

// High-performance spectrum analyzer
export const SpectrumAnalyzer = styled.div`
  width: 100%;
  height: ${spacing['2xl']};
  display: grid;
  grid-template-columns: repeat(32, 1fr);
  gap: 2px;
  background: ${colors.background.secondary};
  border-radius: 4px;
  padding: ${spacing.xs};
  will-change: transform;
  transform: translate3d(0, 0, 0);
`;

// Frequency band bar component
export const FrequencyBand = styled.div<{ intensity: number }>`
  height: ${props => props.intensity}%;
  background: ${colors.primary.main};
  border-radius: 2px;
  transition: height ${1000 / ANIMATION_FPS}ms linear;
  will-change: height;
  transform: translate3d(0, 0, 0);

  @media (prefers-reduced-motion: reduce) {
    transition: none;
  }
`;

// Container for audio controls with proper spacing
export const AudioControlsContainer = styled.div`
  display: flex;
  flex-direction: column;
  gap: ${spacing.md};
  padding: ${spacing.lg};
  background: ${colors.background.primary};
  border-radius: 8px;

  ${breakpoints.sm.query} {
    padding: ${spacing.md};
  }
`;

// Enhanced touch feedback for mobile devices
export const TouchFeedback = styled.div`
  position: absolute;
  width: ${MIN_TOUCH_TARGET}px;
  height: ${MIN_TOUCH_TARGET}px;
  border-radius: 50%;
  background: ${colors.primary.main};
  opacity: 0;
  pointer-events: none;
  will-change: transform, opacity;
  transform: translate3d(0, 0, 0) scale(0);
  
  ${createAnimation('ripple', TRANSITION_DURATION, colors.animation.easing.default)}

  @keyframes ripple {
    0% {
      transform: translate3d(0, 0, 0) scale(0);
      opacity: 0.5;
    }
    100% {
      transform: translate3d(0, 0, 0) scale(2);
      opacity: 0;
    }
  }
`;

// Visualization container with proper aspect ratio
export const VisualizationContainer = styled.div`
  position: relative;
  width: 100%;
  padding-top: 56.25%; // 16:9 aspect ratio
  background: ${colors.background.secondary};
  border-radius: 8px;
  overflow: hidden;

  canvas {
    position: absolute;
    top: 0;
    left: 0;
    width: 100%;
    height: 100%;
  }
`;