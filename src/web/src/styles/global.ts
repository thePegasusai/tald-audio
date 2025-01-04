import { css, Global } from '@emotion/react'; // v11.11.0
import { theme } from './theme';

const createResetStyles = () => css`
  *, *::before, *::after {
    box-sizing: border-box;
    margin: 0;
    padding: 0;
  }

  html {
    font-size: ${ROOT_FONT_SIZE}px;
    text-size-adjust: 100%;
    -webkit-text-size-adjust: 100%;
    -webkit-font-smoothing: antialiased;
    -moz-osx-font-smoothing: grayscale;
    -webkit-tap-highlight-color: transparent;
  }

  body {
    font-family: ${theme.typography.fontFamily.primary};
    line-height: ${theme.typography.lineHeights.normal};
    text-rendering: optimizeLegibility;
    -webkit-font-smoothing: antialiased;
    -moz-osx-font-smoothing: grayscale;
  }

  img, picture, video, canvas, svg {
    display: block;
    max-width: 100%;
    height: auto;
  }

  input, button, textarea, select {
    font: inherit;
    color: inherit;
  }

  p, h1, h2, h3, h4, h5, h6 {
    overflow-wrap: break-word;
  }
`;

const createGlobalStyles = () => css`
  :root {
    /* Color scheme support */
    color-scheme: ${COLOR_SCHEME_MODES};

    /* Fluid typography custom properties */
    --min-scale: ${MIN_FONT_SCALE}%;
    --max-scale: ${MAX_FONT_SCALE}%;
    --fluid-type-scale: ${FLUID_TYPE_SCALE};

    /* P3 color space with fallbacks */
    --color-primary: ${theme.colors.primary.main};
    --color-primary-fallback: ${theme.colors.primary.fallback};
    --color-background: ${theme.colors.background.primary};
    --color-background-fallback: ${theme.colors.background.fallback};

    @supports not (color: color(display-p3 0 0 0)) {
      --color-primary: ${theme.colors.primary.fallback};
      --color-background: ${theme.colors.background.fallback};
    }
  }

  /* Base styles */
  body {
    background-color: var(--color-background);
    color: ${theme.colors.text.primary};
    min-height: 100vh;
    transition: background-color ${theme.animation.duration.normal} ${theme.animation.easing.default};
  }

  /* Enhanced focus styles */
  :focus-visible {
    outline: 3px solid var(--color-primary);
    outline-offset: 2px;
  }

  /* Fluid typography implementation */
  html {
    font-size: clamp(
      ${theme.typography.fontSizes.md},
      calc(1rem + 0.5vw),
      ${theme.typography.fontSizes.lg}
    );
  }

  /* Reduced motion preferences */
  @media (prefers-reduced-motion: reduce) {
    *, *::before, *::after {
      animation-duration: 0.01ms !important;
      animation-iteration-count: 1 !important;
      transition-duration: 0.01ms !important;
      scroll-behavior: auto !important;
    }
  }

  /* High contrast mode support */
  @media (forced-colors: active) {
    :root {
      --color-primary: CanvasText;
      --color-background: Canvas;
    }
  }

  /* Responsive breakpoints */
  ${Object.entries(theme.breakpoints).map(
    ([key, value]) => css`
      ${value.query} {
        html {
          font-size: ${key === 'sm' ? '14px' : '16px'};
        }
      }
    `
  )}

  /* Print styles */
  @media print {
    body {
      background: white;
      color: black;
    }

    @page {
      margin: 2cm;
    }
  }
`;

export const GlobalStyles = () => (
  <Global
    styles={[
      createResetStyles(),
      createGlobalStyles()
    ]}
  />
);

export default GlobalStyles;