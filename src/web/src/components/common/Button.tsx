import React, { useCallback } from 'react';
import styled from '@emotion/styled'; // v11.11.0
import { css } from '@emotion/react'; // v11.11.0
import { theme } from '../../styles/theme';

// Types and interfaces
type ButtonVariant = 'primary' | 'secondary' | 'outline' | 'text' | 'transport' | 'volume' | 'preset';
type ButtonSize = 'small' | 'medium' | 'large';
type HapticPattern = 'standard' | 'success' | 'error' | 'warning';

interface ButtonProps extends React.ButtonHTMLAttributes<HTMLButtonElement> {
  variant?: ButtonVariant;
  size?: ButtonSize;
  disabled?: boolean;
  loading?: boolean;
  pressed?: boolean;
  fullWidth?: boolean;
  hapticPattern?: HapticPattern;
  children: React.ReactNode;
}

// Utility function for haptic feedback
const triggerHapticFeedback = (pattern: HapticPattern = 'standard') => {
  if (!window.navigator.vibrate) return;
  
  const patterns = {
    standard: [50],
    success: [50, 30, 50],
    error: [100, 30, 100],
    warning: [70, 30, 70],
  };
  
  window.navigator.vibrate(patterns[pattern]);
};

// Style generation functions
const getBaseStyles = css`
  position: relative;
  min-height: 44px;
  min-width: 44px;
  padding: ${theme.spacing.md} ${theme.spacing.lg};
  border: none;
  border-radius: 4px;
  font-family: ${theme.typography.fontFamily.primary};
  font-size: ${theme.typography.fontSizes.md};
  font-weight: ${theme.typography.fontWeights.medium};
  line-height: ${theme.typography.lineHeights.normal};
  text-align: center;
  cursor: pointer;
  transition: all ${theme.animation.duration.normal} ${theme.animation.easing.default};
  user-select: none;
  -webkit-tap-highlight-color: transparent;

  &:focus-visible {
    outline: 2px solid ${theme.colors.primary.main};
    outline-offset: 2px;
  }

  ${theme.animation.reducedMotion.query} {
    transition-duration: 0ms;
  }
`;

const getVariantStyles = (variant: ButtonVariant, pressed: boolean) => {
  const variants = {
    primary: css`
      background-color: ${theme.colors.primary.main};
      color: ${theme.colors.text.primary};
      
      &:hover:not(:disabled) {
        background-color: ${theme.colors.primary.light};
      }
      
      &:active:not(:disabled) {
        background-color: ${theme.colors.primary.dark};
      }
    `,
    transport: css`
      background-color: ${theme.colors.primary.main};
      color: ${theme.colors.text.primary};
      border-radius: 50%;
      width: 44px;
      height: 44px;
      padding: 0;
      display: flex;
      align-items: center;
      justify-content: center;
      
      ${pressed && `
        background-color: ${theme.colors.primary.dark};
        transform: scale(0.95);
      `}
    `,
    volume: css`
      background-color: ${theme.colors.secondary.main};
      color: ${theme.colors.text.primary};
      width: 44px;
      padding: ${theme.spacing.sm};
      
      &:hover:not(:disabled) {
        background-color: ${theme.colors.secondary.light};
      }
    `,
    preset: css`
      background-color: ${theme.colors.background.secondary};
      color: ${theme.colors.text.primary};
      border: 2px solid ${pressed ? theme.colors.primary.main : 'transparent'};
      
      &:hover:not(:disabled) {
        border-color: ${theme.colors.primary.light};
      }
    `,
    // Additional variants follow similar pattern...
  };

  return variants[variant] || variants.primary;
};

const getSizeStyles = (size: ButtonSize) => {
  const sizes = {
    small: css`
      padding: ${theme.spacing.sm} ${theme.spacing.md};
      font-size: ${theme.typography.fontSizes.sm};
    `,
    medium: css`
      padding: ${theme.spacing.md} ${theme.spacing.lg};
      font-size: ${theme.typography.fontSizes.md};
    `,
    large: css`
      padding: ${theme.spacing.lg} ${theme.spacing.xl};
      font-size: ${theme.typography.fontSizes.lg};
    `,
  };

  return sizes[size];
};

// Styled component
const StyledButton = styled.button<ButtonProps>`
  ${getBaseStyles}
  ${({ variant = 'primary', pressed = false }) => getVariantStyles(variant, pressed)}
  ${({ size = 'medium' }) => getSizeStyles(size)}
  ${({ fullWidth }) => fullWidth && 'width: 100%;'}
  
  &:disabled {
    opacity: 0.5;
    cursor: not-allowed;
    pointer-events: none;
  }

  ${({ loading }) =>
    loading &&
    css`
      color: transparent;
      pointer-events: none;
      
      &::after {
        content: '';
        position: absolute;
        top: 50%;
        left: 50%;
        width: 20px;
        height: 20px;
        margin: -10px 0 0 -10px;
        border: 2px solid ${theme.colors.text.primary};
        border-top-color: transparent;
        border-radius: 50%;
        animation: button-loading 0.8s linear infinite;
      }
    `}

  @keyframes button-loading {
    to {
      transform: rotate(360deg);
    }
  }
`;

// Button component
export const Button: React.FC<ButtonProps> = ({
  variant = 'primary',
  size = 'medium',
  disabled = false,
  loading = false,
  pressed = false,
  fullWidth = false,
  hapticPattern = 'standard',
  children,
  onClick,
  ...props
}) => {
  const handleClick = useCallback(
    (event: React.MouseEvent<HTMLButtonElement>) => {
      if (disabled || loading) return;

      triggerHapticFeedback(hapticPattern);
      onClick?.(event);
    },
    [disabled, loading, hapticPattern, onClick]
  );

  return (
    <StyledButton
      variant={variant}
      size={size}
      disabled={disabled || loading}
      loading={loading}
      pressed={pressed}
      fullWidth={fullWidth}
      onClick={handleClick}
      aria-pressed={pressed}
      aria-busy={loading}
      {...props}
    >
      {children}
    </StyledButton>
  );
};

export default Button;