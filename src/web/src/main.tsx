/**
 * TALD UNIA Audio System - Main Application Entry Point
 * Version: 1.0.0
 * 
 * Initializes the React application with WebGL2 acceleration support,
 * theme context, audio processing context, and error boundaries.
 */

import React, { StrictMode, useEffect } from 'react';
import ReactDOM from 'react-dom/client'; // ^18.2.0
import { ErrorBoundary } from 'react-error-boundary'; // ^4.0.0

// Internal imports
import App from './App';
import { ThemeProvider } from './contexts/ThemeContext';
import { AudioProvider } from './contexts/AudioContext';

// Constants
const ROOT_ELEMENT_ID = 'root';
const WEBGL_VERSION = 2;
const REQUIRED_WEBGL_EXTENSIONS = ['OES_texture_float'];

/**
 * Validates WebGL2 support and capabilities for audio processing
 */
const checkWebGL2Support = (): boolean => {
  const canvas = document.createElement('canvas');
  const gl = canvas.getContext('webgl2');

  if (!gl) {
    console.error('WebGL2 is not supported');
    return false;
  }

  // Verify required extensions
  for (const extension of REQUIRED_WEBGL_EXTENSIONS) {
    if (!gl.getExtension(extension)) {
      console.error(`Required WebGL extension ${extension} is not supported`);
      return false;
    }
  }

  // Verify memory limits
  const maxTextureSize = gl.getParameter(gl.MAX_TEXTURE_SIZE);
  const maxRenderBufferSize = gl.getParameter(gl.MAX_RENDERBUFFER_SIZE);

  if (maxTextureSize < 8192 || maxRenderBufferSize < 8192) {
    console.error('Insufficient WebGL resources for audio processing');
    return false;
  }

  return true;
};

/**
 * Error fallback component with retry capability
 */
const ErrorFallback = ({ error, resetErrorBoundary }: { 
  error: Error; 
  resetErrorBoundary: () => void;
}) => (
  <div role="alert" style={{ 
    padding: '20px', 
    margin: '20px', 
    border: '1px solid #ff0000',
    borderRadius: '4px',
    backgroundColor: '#fff1f0' 
  }}>
    <h2>Application Error</h2>
    <pre style={{ whiteSpace: 'pre-wrap' }}>{error.message}</pre>
    <button 
      onClick={resetErrorBoundary}
      style={{ 
        padding: '8px 16px',
        marginTop: '10px',
        borderRadius: '4px',
        border: 'none',
        backgroundColor: '#1890ff',
        color: 'white',
        cursor: 'pointer'
      }}
    >
      Retry Application
    </button>
  </div>
);

/**
 * Performance monitoring initialization
 */
const initializePerformanceMonitoring = () => {
  if ('PerformanceObserver' in window) {
    // Monitor Core Web Vitals
    const vitalsObserver = new PerformanceObserver((entryList) => {
      entryList.getEntries().forEach((entry) => {
        console.debug('[Performance]', entry.name, entry.value);
      });
    });

    vitalsObserver.observe({ 
      entryTypes: ['largest-contentful-paint', 'first-input', 'layout-shift'] 
    });

    // Monitor long tasks
    const longTasksObserver = new PerformanceObserver((entryList) => {
      entryList.getEntries().forEach((entry) => {
        console.warn('[Long Task]', entry.duration, 'ms');
      });
    });

    longTasksObserver.observe({ entryTypes: ['longtask'] });
  }
};

/**
 * Root application wrapper with all providers
 */
const Root = () => {
  useEffect(() => {
    // Initialize performance monitoring
    initializePerformanceMonitoring();

    // Set document metadata
    document.title = 'TALD UNIA Audio System';
    document.documentElement.lang = 'en';

    // Configure viewport for optimal mobile experience
    const metaViewport = document.createElement('meta');
    metaViewport.name = 'viewport';
    metaViewport.content = 'width=device-width, initial-scale=1, viewport-fit=cover';
    document.head.appendChild(metaViewport);

    return () => {
      document.head.removeChild(metaViewport);
    };
  }, []);

  return (
    <StrictMode>
      <ErrorBoundary 
        FallbackComponent={ErrorFallback}
        onReset={() => window.location.reload()}
        onError={(error) => {
          console.error('[ErrorBoundary]', error);
          // Here you would send error to your error tracking service
        }}
      >
        <ThemeProvider>
          <AudioProvider>
            <App />
          </AudioProvider>
        </ThemeProvider>
      </ErrorBoundary>
    </StrictMode>
  );
};

/**
 * Application initialization
 */
const initializeApp = async () => {
  // Verify WebGL2 support
  if (!checkWebGL2Support()) {
    throw new Error('WebGL2 support is required for audio processing');
  }

  // Create root element if it doesn't exist
  let rootElement = document.getElementById(ROOT_ELEMENT_ID);
  if (!rootElement) {
    rootElement = document.createElement('div');
    rootElement.id = ROOT_ELEMENT_ID;
    document.body.appendChild(rootElement);
  }

  // Set root element attributes
  rootElement.setAttribute('data-color-space', 'p3');
  rootElement.setAttribute('role', 'application');
  rootElement.setAttribute('aria-label', 'TALD UNIA Audio System');

  // Create and render root
  const root = ReactDOM.createRoot(rootElement);
  root.render(<Root />);
};

// Initialize application with error handling
initializeApp().catch((error) => {
  console.error('Failed to initialize application:', error);
  
  // Render error state
  const rootElement = document.getElementById(ROOT_ELEMENT_ID);
  if (rootElement) {
    ReactDOM.createRoot(rootElement).render(
      <ErrorFallback 
        error={error} 
        resetErrorBoundary={() => window.location.reload()} 
      />
    );
  }
});