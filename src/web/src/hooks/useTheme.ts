import { useCallback, useEffect, useMemo } from 'react'; // ^18.2.0
import { Theme } from '@emotion/react'; // ^11.11.0
import { useThemeContext } from '../contexts/ThemeContext';
import { theme } from '../styles/theme';

// System preference media queries
const SYSTEM_DARK_MODE_QUERY = '(prefers-color-scheme: dark)';
const SYSTEM_REDUCED_MOTION_QUERY = '(prefers-reduced-motion: reduce)';
const STORAGE_KEY_THEME = 'tald-unia-theme-preference';
const THEME_TRANSITION_DURATION = 200;

/**
 * Custom hook for managing theme state, preferences, and responsive behavior
 * Provides comprehensive theme management with P3 color space support and accessibility features
 */
export const useTheme = () => {
  const {
    currentTheme,
    toggleTheme: contextToggleTheme,
    setTheme: contextSetTheme,
  } = useThemeContext();

  // Memoized theme values
  const colors = useMemo(() => currentTheme.colors, [currentTheme]);
  const typography = useMemo(() => currentTheme.typography, [currentTheme]);
  const spacing = useMemo(() => currentTheme.spacing, [currentTheme]);
  const breakpoints = useMemo(() => currentTheme.breakpoints, [currentTheme]);

  // System theme preference handler
  const handleSystemThemeChange = useCallback((event: MediaQueryListEvent) => {
    // Apply transition timing for smooth theme switch
    document.documentElement.style.transition = `background-color ${THEME_TRANSITION_DURATION}ms ${theme.animation.easing.default}`;
    
    // Update theme based on system preference
    contextSetTheme(event.matches);
    
    // Store preference
    localStorage.setItem(STORAGE_KEY_THEME, event.matches ? 'dark' : 'light');
    
    // Remove transition after switch
    setTimeout(() => {
      document.documentElement.style.transition = '';
    }, THEME_TRANSITION_DURATION);
  }, [contextSetTheme]);

  // Reduced motion preference handler
  const handleReducedMotion = useCallback((event: MediaQueryListEvent) => {
    document.documentElement.style.setProperty(
      '--transition-duration',
      event.matches ? '0ms' : `${THEME_TRANSITION_DURATION}ms`
    );
  }, []);

  // Initialize media query listeners
  useEffect(() => {
    const darkModeQuery = window.matchMedia(SYSTEM_DARK_MODE_QUERY);
    const reducedMotionQuery = window.matchMedia(SYSTEM_REDUCED_MOTION_QUERY);

    // Set initial reduced motion preference
    handleReducedMotion({ matches: reducedMotionQuery.matches } as MediaQueryListEvent);

    // Add event listeners
    darkModeQuery.addEventListener('change', handleSystemThemeChange);
    reducedMotionQuery.addEventListener('change', handleReducedMotion);

    // Cleanup listeners
    return () => {
      darkModeQuery.removeEventListener('change', handleSystemThemeChange);
      reducedMotionQuery.removeEventListener('change', handleReducedMotion);
    };
  }, [handleSystemThemeChange, handleReducedMotion]);

  // Memoized breakpoint matchers
  const breakpointMatchers = useMemo(() => ({
    isMobile: window.matchMedia(breakpoints.sm.query).matches,
    isTablet: window.matchMedia(breakpoints.md.query).matches,
    isDesktop: window.matchMedia(breakpoints.lg.query).matches,
    isWidescreen: window.matchMedia(breakpoints.xl.query).matches,
  }), [breakpoints]);

  // Memoized theme utilities
  const themeUtils = useMemo(() => ({
    // Check if system supports P3 color space
    supportsP3ColorSpace: window.CSS.supports('color', 'color(display-p3 0 0 0)'),
    
    // Get appropriate color value (P3 or fallback)
    getColor: (colorKey: keyof typeof colors) => {
      const color = colors[colorKey];
      return themeUtils.supportsP3ColorSpace ? color : color.fallback;
    },
    
    // Get fluid typography size
    getFluidTypography: (size: keyof typeof typography.fontSizes) => 
      typography.fontSizes[size],
    
    // Get spacing value
    getSpacing: (size: keyof typeof spacing) => spacing[size],
    
    // Get responsive value based on breakpoint
    getResponsiveValue: <T>(values: { [key: string]: T }): T => {
      if (breakpointMatchers.isMobile) return values.sm;
      if (breakpointMatchers.isTablet) return values.md;
      if (breakpointMatchers.isDesktop) return values.lg;
      return values.xl;
    },
  }), [colors, typography, spacing, breakpointMatchers]);

  return {
    // Theme state
    theme: currentTheme,
    toggleTheme: contextToggleTheme,
    setTheme: contextSetTheme,
    
    // Theme values
    colors,
    typography,
    spacing,
    breakpoints,
    
    // Responsive utilities
    ...breakpointMatchers,
    
    // Theme utilities
    ...themeUtils,
    
    // Accessibility
    isReducedMotion: window.matchMedia(SYSTEM_REDUCED_MOTION_QUERY).matches,
  };
};

export type UseThemeReturn = ReturnType<typeof useTheme>;
export default useTheme;