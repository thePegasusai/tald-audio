// External imports with versions
import 'cypress'; // ^13.0.0
import '@testing-library/cypress'; // ^10.0.0
import '@cypress/code-coverage'; // ^3.12.0

// Import custom commands for TALD UNIA testing
import './commands';

// Constants for test configuration
const TEST_TIMEOUTS = {
  defaultCommandTimeout: 5000,
  pageLoadTimeout: 10000,
  requestTimeout: 8000,
  responseTimeout: 8000
};

const VIEWPORT_CONFIG = {
  viewportWidth: 1280,
  viewportHeight: 720,
  deviceScaleFactor: 1
};

const TEST_RETRIES = {
  runMode: 2,
  openMode: 0
};

const AUDIO_TEST_THRESHOLDS = {
  maxLatencyMs: 10,
  maxThdPlusNPercent: 0.0005,
  maxCpuUsagePercent: 40,
  bufferHealthMin: 0.95
};

// Configure Cypress globally
Cypress.config({
  ...TEST_TIMEOUTS,
  ...VIEWPORT_CONFIG,
  retries: TEST_RETRIES,
  video: true,
  videoCompression: 32,
  screenshotOnRunFailure: true,
  chromeWebSecurity: false,
  experimentalMemoryManagement: true
});

// Register global event handlers for audio testing
Cypress.on('window:before:load', (win) => {
  // Initialize audio context and analyzers
  const audioContext = new (win.AudioContext || win.webkitAudioContext)();
  win.audioTestContext = audioContext;
  
  // Setup audio analysis nodes
  const analyzer = audioContext.createAnalyser();
  analyzer.fftSize = 2048;
  win.audioAnalyzer = analyzer;
});

// Handle uncaught audio processing exceptions
Cypress.on('uncaught:exception', (err) => {
  if (err.message.includes('AudioContext')) {
    return false;
  }
  return true;
});

// Global test hooks
beforeEach(() => {
  // Reset audio processing state
  cy.window().then((win) => {
    if (win.audioTestContext) {
      win.audioTestContext.close();
    }
    win.audioTestContext = null;
    win.audioAnalyzer = null;
  });

  // Clear all WebSocket connections
  cy.window().then((win) => {
    win.WebSocket = null;
  });

  // Reset audio device settings
  cy.clearLocalStorage();
  cy.clearCookies();

  // Configure default audio test thresholds
  Cypress.env('audioTestThresholds', AUDIO_TEST_THRESHOLDS);

  // Initialize test coverage
  cy.window().then((win) => {
    win.__coverage__ = {};
  });
});

afterEach(() => {
  // Stop all active audio processing
  cy.window().then((win) => {
    if (win.audioTestContext) {
      win.audioTestContext.close();
    }
  });

  // Close WebSocket connections gracefully
  cy.window().then((win) => {
    if (win.WebSocket) {
      win.WebSocket.prototype.close();
    }
  });

  // Clean up audio test artifacts
  cy.task('cleanAudioTestFiles', null, { log: false });

  // Generate test coverage report
  cy.window().then((win) => {
    if (win.__coverage__) {
      cy.task('coverageReport', win.__coverage__, { log: false });
    }
  });
});

// Configure Testing Library
Cypress.SelectorPlayground.defaults({
  selectorPriority: [
    'data-testid',
    'aria-label',
    'id',
    'class',
    'tag',
    'attributes',
    'nth-child'
  ]
});

// Add custom assertions for audio testing
chai.Assertion.addMethod('withinAudioThreshold', function(expected, threshold) {
  const actual = this._obj;
  const diff = Math.abs(actual - expected);
  this.assert(
    diff <= threshold,
    `expected #{this} to be within ${threshold} of ${expected}`,
    `expected #{this} not to be within ${threshold} of ${expected}`,
    expected,
    actual
  );
});

// Export type definitions for custom commands
export {};