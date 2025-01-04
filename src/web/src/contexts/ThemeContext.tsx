import { createContext, useContext, useState, useEffect, ReactNode } from 'react'; // ^18.2.0
import { ThemeProvider as EmotionThemeProvider } from '@emotion/react'; // ^11.11.0
import { theme, Theme } from '../styles/theme';

// System preference media queries
const SYSTEM_DARK_MODE_QUERY = '(prefers-color-scheme: dark)';
const SYSTEM_REDUCED_MOTION_QUERY = '(prefers-reduced-motion: reduce)';

// Local storage keys
const STORAGE_KEY_THEME = 'tald-unia-theme-preference';
const STORAGE_KEY_MOTION = 'tald-unia-motion-preference';

// Theme context value interface
interface ThemeContextValue {
  currentTheme: Theme;
  isDarkMode: boolean;
  isReducedMotion: boolean;
  toggleTheme: () => void;
  setTheme: (isDark: boolean) => void;
}

// Theme provider props interface
interface ThemeProviderProps {
  children: ReactNode;
  initialTheme?: Partial<Theme>;
}

// Create theme context
const ThemeContext = createContext<ThemeContextValue | undefined>(undefined);

// Hook to detect system preferences
const useSystemPreferences = () => {
  const [isDarkMode, setIsDarkMode] = useState(() => {
    const stored = localStorage.getItem(STORAGE_KEY_THEME);
    if (stored !== null) return stored === 'dark';
    return window.matchMedia(SYSTEM_DARK_MODE_QUERY).matches;
  });

  const [isReducedMotion, setIsReducedMotion] = useState(() => {
    const stored = localStorage.getItem(STORAGE_KEY_MOTION);
    if (stored !== null) return stored === 'true';
    return window.matchMedia(SYSTEM_REDUCED_MOTION_QUERY).matches;
  });

  useEffect(() => {
    const darkModeQuery = window.matchMedia(SYSTEM_DARK_MODE_QUERY);
    const motionQuery = window.matchMedia(SYSTEM_REDUCED_MOTION_QUERY);

    const handleDarkModeChange = (e: MediaQueryListEvent) => {
      if (localStorage.getItem(STORAGE_KEY_THEME) === null) {
        setIsDarkMode(e.matches);
      }
    };

    const handleMotionChange = (e: MediaQueryListEvent) => {
      if (localStorage.getItem(STORAGE_KEY_MOTION) === null) {
        setIsReducedMotion(e.matches);
      }
    };

    darkModeQuery.addEventListener('change', handleDarkModeChange);
    motionQuery.addEventListener('change', handleMotionChange);

    return () => {
      darkModeQuery.removeEventListener('change', handleDarkModeChange);
      motionQuery.removeEventListener('change', handleMotionChange);
    };
  }, []);

  return { isDarkMode, setIsDarkMode, isReducedMotion, setIsReducedMotion };
};

// Theme provider component
export const ThemeProvider = ({ children, initialTheme }: ThemeProviderProps) => {
  const {
    isDarkMode,
    setIsDarkMode,
    isReducedMotion,
    setIsReducedMotion
  } = useSystemPreferences();

  // Merge base theme with dark mode overrides and initial theme
  const currentTheme: Theme = {
    ...theme,
    ...initialTheme,
    colors: {
      ...theme.colors,
      ...(isDarkMode && {
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
      }),
      ...(initialTheme?.colors || {}),
    },
    animation: {
      ...theme.animation,
      ...(isReducedMotion && {
        duration: theme.animation.reducedMotion.duration,
      }),
      ...(initialTheme?.animation || {}),
    },
  };

  const toggleTheme = () => {
    const newMode = !isDarkMode;
    setIsDarkMode(newMode);
    localStorage.setItem(STORAGE_KEY_THEME, newMode ? 'dark' : 'light');
  };

  const setTheme = (isDark: boolean) => {
    setIsDarkMode(isDark);
    localStorage.setItem(STORAGE_KEY_THEME, isDark ? 'dark' : 'light');
  };

  useEffect(() => {
    localStorage.setItem(STORAGE_KEY_MOTION, isReducedMotion.toString());
  }, [isReducedMotion]);

  const contextValue: ThemeContextValue = {
    currentTheme,
    isDarkMode,
    isReducedMotion,
    toggleTheme,
    setTheme,
  };

  return (
    <ThemeContext.Provider value={contextValue}>
      <EmotionThemeProvider theme={currentTheme}>
        {children}
      </EmotionThemeProvider>
    </ThemeContext.Provider>
  );
};

// Custom hook to use theme context
export const useThemeContext = () => {
  const context = useContext(ThemeContext);
  if (context === undefined) {
    throw new Error('useThemeContext must be used within a ThemeProvider');
  }
  return context;
};

export default ThemeProvider;