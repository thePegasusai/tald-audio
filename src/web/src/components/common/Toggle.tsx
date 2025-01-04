import React from 'react'; // v18.2.0
import styled from '@emotion/styled'; // v11.11.0
import { css } from '@emotion/react'; // v11.11.0
import { theme } from '../../styles/theme';

// Types and Enums
export type ToggleSize = 'sm' | 'md' | 'lg';
export type ColorScheme = 'primary' | 'secondary' | 'success' | 'warning';

interface ToggleProps {
  checked: boolean;
  onChange: (checked: boolean) => void;
  label: string;
  id?: string;
  disabled?: boolean;
  ariaLabel?: string;
  size?: ToggleSize;
  colorScheme?: ColorScheme;
  enableHaptics?: boolean;
  enableAudioFeedback?: boolean;
}

// Utility functions
const getSizeValue = (size: ToggleSize = 'md'): number => {
  switch (size) {
    case 'sm': return 44;
    case 'lg': return 64;
    default: return 52;
  }
};

const getKnobSize = (size: ToggleSize = 'md'): string => {
  switch (size) {
    case 'sm': return '16px';
    case 'lg': return '28px';
    default: return '22px';
  }
};

const getKnobPosition = (size: ToggleSize = 'md'): string => {
  switch (size) {
    case 'sm': return 'calc(100% - 18px)';
    case 'lg': return 'calc(100% - 30px)';
    default: return 'calc(100% - 24px)';
  }
};

const getBackgroundColor = (checked: boolean, colorScheme: ColorScheme = 'primary'): string => {
  if (!checked) return theme.colors.background.secondary;
  
  switch (colorScheme) {
    case 'secondary': return theme.colors.secondary.main;
    case 'success': return theme.colors.status.success;
    case 'warning': return theme.colors.status.warning;
    default: return theme.colors.primary.main;
  }
};

const getP3BackgroundColor = (checked: boolean, colorScheme: ColorScheme = 'primary'): string => {
  if (!checked) return theme.colors.background.secondary;
  
  switch (colorScheme) {
    case 'secondary': return theme.colors.secondary.main;
    case 'success': return theme.colors.status.success;
    case 'warning': return theme.colors.status.warning;
    default: return theme.colors.primary.main;
  }
};

// Styled components
const ToggleContainer = styled.label<{ disabled?: boolean }>`
  display: inline-flex;
  align-items: center;
  cursor: pointer;
  user-select: none;
  min-height: 44px;
  padding: ${theme.spacing.sm};
  opacity: ${props => props.disabled ? 0.5 : 1};
  pointer-events: ${props => props.disabled ? 'none' : 'auto'};
  font-family: ${theme.typography.fontFamily.primary};
  font-size: ${theme.typography.fontSizes.md};
  color: ${theme.colors.text.primary};
  gap: ${theme.spacing.sm};

  &:focus-visible {
    outline: 2px solid ${theme.colors.primary.main};
    outline-offset: 2px;
  }

  @media (prefers-reduced-motion: reduce) {
    transition: none;
  }
`;

const ToggleSwitch = styled.div<{
  checked: boolean;
  size: ToggleSize;
  colorScheme: ColorScheme;
}>`
  position: relative;
  width: ${props => getSizeValue(props.size)}px;
  height: ${props => getSizeValue(props.size) / 2}px;
  background: ${props => getBackgroundColor(props.checked, props.colorScheme)};
  border-radius: ${props => getSizeValue(props.size) / 4}px;
  transition: background ${theme.animation.duration.normal} ${theme.animation.easing.default};

  @media (prefers-reduced-motion: reduce) {
    transition: none;
  }

  @media (color-gamut: p3) {
    background: ${props => getP3BackgroundColor(props.checked, props.colorScheme)};
  }
`;

const ToggleKnob = styled.div<{
  checked: boolean;
  size: ToggleSize;
}>`
  position: absolute;
  top: 2px;
  left: ${props => props.checked ? getKnobPosition(props.size) : '2px'};
  width: ${props => getKnobSize(props.size)};
  height: ${props => getKnobSize(props.size)};
  background: ${theme.colors.text.primary};
  border-radius: 50%;
  transition: left ${theme.animation.duration.normal} ${theme.animation.easing.default};
  box-shadow: 0 2px 4px rgba(0, 0, 0, 0.2);

  @media (prefers-reduced-motion: reduce) {
    transition: none;
  }
`;

const ToggleLabel = styled.span`
  font-family: ${theme.typography.fontFamily.primary};
  font-size: ${theme.typography.fontSizes.md};
  color: ${theme.colors.text.primary};
`;

// Main component
export const Toggle: React.FC<ToggleProps> = React.memo(({
  checked,
  onChange,
  label,
  id,
  disabled = false,
  ariaLabel,
  size = 'md',
  colorScheme = 'primary',
  enableHaptics = false,
  enableAudioFeedback = false,
}) => {
  const toggleId = id || `toggle-${Math.random().toString(36).substr(2, 9)}`;

  const triggerHapticFeedback = () => {
    if (enableHaptics && window.navigator.vibrate) {
      window.navigator.vibrate(10);
    }
  };

  const playAudioFeedback = () => {
    if (enableAudioFeedback) {
      const audio = new Audio();
      audio.src = checked ? 'assets/audio/toggle-on.mp3' : 'assets/audio/toggle-off.mp3';
      audio.play().catch(() => {}); // Ignore errors if audio playback fails
    }
  };

  const handleKeyDown = (event: React.KeyboardEvent) => {
    if (event.key === ' ' || event.key === 'Enter') {
      event.preventDefault();
      if (!disabled) {
        triggerHapticFeedback();
        playAudioFeedback();
        onChange(!checked);
      }
    }
  };

  const handleClick = (event: React.MouseEvent) => {
    event.preventDefault();
    if (!disabled) {
      triggerHapticFeedback();
      playAudioFeedback();
      onChange(!checked);
    }
  };

  return (
    <ToggleContainer
      htmlFor={toggleId}
      disabled={disabled}
      onClick={handleClick}
      onKeyDown={handleKeyDown}
      tabIndex={disabled ? -1 : 0}
      role="switch"
      aria-checked={checked}
      aria-label={ariaLabel || label}
      aria-disabled={disabled}
    >
      <ToggleSwitch
        checked={checked}
        size={size}
        colorScheme={colorScheme}
      >
        <ToggleKnob
          checked={checked}
          size={size}
        />
      </ToggleSwitch>
      <ToggleLabel>{label}</ToggleLabel>
    </ToggleContainer>
  );
});

Toggle.displayName = 'Toggle';

export default Toggle;