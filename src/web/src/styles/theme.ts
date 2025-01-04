import { css } from '@emotion/react'; // v11.11.0

// Base constants
const BASE_SPACING_UNIT = 8;
const BASE_FONT_SIZE = 16;
const TRANSITION_DURATION = 200;
const MIN_CONTRAST_RATIO = 4.5;

// Utility functions
const createSpacing = (multiplier: number, isNegative: boolean = false): string => {
  const value = BASE_SPACING_UNIT * multiplier;
  return `${isNegative ? -value : value}px`;
};

const createFluidTypography = (
  minSize: number,
  maxSize: number,
  minWidth: number = 768,
  maxWidth: number = 1920
): string => {
  const minSizeRem = minSize / BASE_FONT_SIZE;
  const maxSizeRem = maxSize / BASE_FONT_SIZE;
  return `clamp(${minSizeRem}rem, ${minSizeRem}rem + ${(maxSizeRem - minSizeRem) * 100}vw, ${maxSizeRem}rem)`;
};

const checkColorContrast = (foreground: string, background: string): boolean => {
  // Simplified contrast check - production code would need full WCAG calculation
  return true; // Placeholder - implement full WCAG contrast calculation
};

// Theme configuration
export const theme = {
  colors: {
    primary: {
      main: 'color(display-p3 0.2 0.4 0.8)',
      light: 'color(display-p3 0.3 0.5 0.9)',
      dark: 'color(display-p3 0.1 0.3 0.7)',
      fallback: '#3366CC',
    },
    secondary: {
      main: 'color(display-p3 0.6 0.2 0.8)',
      light: 'color(display-p3 0.7 0.3 0.9)',
      dark: 'color(display-p3 0.5 0.1 0.7)',
      fallback: '#9933CC',
    },
    background: {
      primary: 'color(display-p3 0.1 0.1 0.12)',
      secondary: 'color(display-p3 0.15 0.15 0.17)',
      fallback: '#1A1A1F',
    },
    text: {
      primary: 'color(display-p3 1 1 1)',
      secondary: 'color(display-p3 0.7 0.7 0.7)',
      disabled: 'color(display-p3 0.5 0.5 0.5)',
    },
    status: {
      error: 'color(display-p3 0.9 0.2 0.2)',
      success: 'color(display-p3 0.2 0.8 0.4)',
      warning: 'color(display-p3 0.9 0.6 0.1)',
    },
  },

  typography: {
    fontFamily: {
      primary: 'SF Pro Display, system-ui, -apple-system, sans-serif',
      secondary: 'Roboto, Arial, sans-serif',
      mono: 'SF Mono, Consolas, monospace',
    },
    fontSizes: {
      xs: createFluidTypography(12, 14),
      sm: createFluidTypography(14, 16),
      md: createFluidTypography(16, 18),
      lg: createFluidTypography(18, 20),
      xl: createFluidTypography(20, 24),
      '2xl': createFluidTypography(24, 30),
      '3xl': createFluidTypography(30, 36),
    },
    fontWeights: {
      regular: '400',
      medium: '500',
      semibold: '600',
      bold: '700',
    },
    lineHeights: {
      tight: '1.2',
      normal: '1.5',
      relaxed: '1.75',
      loose: '2',
    },
  },

  spacing: {
    xs: createSpacing(0.5),
    sm: createSpacing(1),
    md: createSpacing(2),
    lg: createSpacing(3),
    xl: createSpacing(4),
    '2xl': createSpacing(6),
    negative: {
      xs: createSpacing(0.5, true),
      sm: createSpacing(1, true),
      md: createSpacing(2, true),
      lg: createSpacing(3, true),
      xl: createSpacing(4, true),
      '2xl': createSpacing(6, true),
    },
  },

  breakpoints: {
    sm: {
      width: '768px',
      query: '@media (max-width: 767px)',
    },
    md: {
      width: '1024px',
      query: '@media (max-width: 1023px)',
    },
    lg: {
      width: '1440px',
      query: '@media (max-width: 1439px)',
    },
    xl: {
      width: '1920px',
      query: '@media (max-width: 1919px)',
    },
  },

  animation: {
    duration: {
      fast: '150ms',
      normal: `${TRANSITION_DURATION}ms`,
      slow: '300ms',
    },
    easing: {
      default: 'cubic-bezier(0.4, 0, 0.2, 1)',
      easeIn: 'cubic-bezier(0.4, 0, 1, 1)',
      easeOut: 'cubic-bezier(0, 0, 0.2, 1)',
      sharp: 'cubic-bezier(0.4, 0, 0.6, 1)',
    },
    reducedMotion: {
      query: '@media (prefers-reduced-motion: reduce)',
      duration: {
        fast: '0ms',
        normal: '0ms',
        slow: '0ms',
      },
    },
  },
} as const;

// Type definitions for theme
export type Theme = typeof theme;
export type ThemeColors = typeof theme.colors;
export type ThemeTypography = typeof theme.typography;
export type ThemeSpacing = typeof theme.spacing;
export type ThemeBreakpoints = typeof theme.breakpoints;
export type ThemeAnimation = typeof theme.animation;

// Helper to create CSS-in-JS styles with theme
export const createStyles = (styles: any) => css(styles);

export default theme;