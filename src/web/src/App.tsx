import React, { Suspense, useEffect } from 'react';
import { BrowserRouter, Routes, Route } from 'react-router-dom'; // ^6.14.0
import { GlobalStyles, CssBaseline } from '@mui/material'; // ^5.14.0
import { ErrorBoundary } from 'react-error-boundary'; // ^4.0.0
import styled from '@emotion/styled'; // ^11.11.0

import MainLayout from './components/layout/MainLayout';
import { ThemeProvider } from './contexts/ThemeContext';

// Lazy loaded route components
const Dashboard = React.lazy(() => import('./pages/Dashboard'));
const Profile = React.lazy(() => import('./pages/Profile'));
const Settings = React.lazy(() => import('./pages/Settings'));
const Visualization = React.lazy(() => import('./pages/Visualization'));

// Styled Components
const LoadingFallback = styled.div`
  display: flex;
  align-items: center;
  justify-content: center;
  height: 100vh;
  color: ${props => props.theme.colors.text.primary};
  font-family: ${props => props.theme.typography.fontFamily.primary};
`;

const ErrorFallback = styled.div`
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  height: 100vh;
  padding: ${props => props.theme.spacing.xl};
  color: ${props => props.theme.colors.status.error};
  font-family: ${props => props.theme.typography.fontFamily.primary};
  text-align: center;
`;

// Global styles with P3 color space and accessibility support
const globalStyles = theme => ({
  'html, body': {
    margin: 0,
    padding: 0,
    fontFamily: theme.typography.fontFamily.primary,
    backgroundColor: theme.colors.background.primary,
    color: theme.colors.text.primary,
    colorScheme: theme.isDarkMode ? 'dark' : 'light',
    '@media (color-gamut: p3)': {
      colorGamut: 'p3',
    },
  },
  '@media (prefers-reduced-motion: reduce)': {
    '*': {
      animationDuration: '0.001ms !important',
      animationIterationCount: '1 !important',
      transitionDuration: '0.001ms !important',
    },
  },
  ':focus-visible': {
    outline: `2px solid ${theme.colors.primary.main}`,
    outlineOffset: '2px',
  },
  '.sr-only': {
    position: 'absolute',
    width: '1px',
    height: '1px',
    padding: 0,
    margin: '-1px',
    overflow: 'hidden',
    clip: 'rect(0, 0, 0, 0)',
    whiteSpace: 'nowrap',
    border: 0,
  },
});

// Error boundary fallback component
const ErrorBoundaryFallback = ({ error }: { error: Error }) => (
  <ErrorFallback role="alert" aria-live="assertive">
    <h1>Something went wrong</h1>
    <p>{error.message}</p>
    <button onClick={() => window.location.reload()}>
      Reload Application
    </button>
  </ErrorFallback>
);

// Loading fallback component
const LoadingSpinner = () => (
  <LoadingFallback role="status" aria-live="polite">
    <span className="sr-only">Loading application...</span>
    <span aria-hidden="true">Loading...</span>
  </LoadingFallback>
);

const App: React.FC = () => {
  // Set document metadata and viewport settings
  useEffect(() => {
    document.documentElement.lang = 'en';
    document.title = 'TALD UNIA Audio System';
    
    const metaViewport = document.createElement('meta');
    metaViewport.name = 'viewport';
    metaViewport.content = 'width=device-width, initial-scale=1, viewport-fit=cover';
    document.head.appendChild(metaViewport);

    return () => {
      document.head.removeChild(metaViewport);
    };
  }, []);

  // Initialize performance monitoring
  useEffect(() => {
    if ('performance' in window && 'measure' in window.performance) {
      performance.mark('app-init');
      return () => {
        performance.measure('app-lifecycle', 'app-init');
      };
    }
  }, []);

  return (
    <ErrorBoundary FallbackComponent={ErrorBoundaryFallback}>
      <ThemeProvider>
        <CssBaseline />
        <GlobalStyles styles={globalStyles} />
        <BrowserRouter>
          <MainLayout>
            <Suspense fallback={<LoadingSpinner />}>
              <Routes>
                <Route path="/" element={<Dashboard />} />
                <Route path="/profile" element={<Profile />} />
                <Route path="/settings" element={<Settings />} />
                <Route path="/visualization" element={<Visualization />} />
                <Route path="*" element={
                  <ErrorFallback role="alert">
                    <h1>Page Not Found</h1>
                    <p>The requested page does not exist.</p>
                  </ErrorFallback>
                } />
              </Routes>
            </Suspense>
          </MainLayout>
        </BrowserRouter>
      </ThemeProvider>
    </ErrorBoundary>
  );
};

export default App;