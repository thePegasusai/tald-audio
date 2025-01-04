import { VisualizationConfig, ProcessingStatus } from '../../src/types/visualization.types';
import '@testing-library/cypress';

// Test audio files with different frequency characteristics
const TEST_AUDIO_FILES = [
  'cypress/fixtures/test-audio-low.wav',  // 20Hz-200Hz content
  'cypress/fixtures/test-audio-mid.wav',  // 200Hz-2kHz content
  'cypress/fixtures/test-audio-high.wav'  // 2kHz-20kHz content
];

// Mock data for spectrum analysis
const MOCK_SPECTRUM_DATA = {
  frequencies: new Float32Array(2048).fill(0).map((_, i) => 20 * Math.pow(2, i / 170)), // Log scale 20Hz-20kHz
  magnitudes: new Float32Array(2048),
  timestamp: Date.now(),
  sampleRate: 192000,
  resolution: 20000 / 2048
};

// Mock processing status data
const MOCK_PROCESSING_STATUS: ProcessingStatus = {
  cpuLoad: 35,
  bufferSize: 256,
  latency: 8,
  thdPlusN: 0.0004,
  signalToNoise: 122,
  powerEfficiency: 92
};

describe('Audio Visualization Components', () => {
  beforeEach(() => {
    // Set viewport for consistent testing
    cy.viewport(1920, 1080);

    // Visit visualization page with custom command
    cy.visitVisualization();

    // Mock WebSocket connection for real-time data
    cy.mockWebSocket('ws://localhost:8080/audio', {
      onConnect: (socket) => {
        // Send initial data
        socket.send(JSON.stringify({
          type: 'spectrum',
          data: MOCK_SPECTRUM_DATA
        }));
        socket.send(JSON.stringify({
          type: 'status',
          data: MOCK_PROCESSING_STATUS
        }));
      }
    });

    // Wait for components to be ready
    cy.get('[data-testid="visualization-container"]', { timeout: 10000 })
      .should('be.visible');
  });

  describe('Spectrum Analyzer', () => {
    it('should render with correct dimensions and axes', () => {
      cy.get('[data-testid="spectrum-analyzer"]')
        .should('be.visible')
        .and('have.css', 'width', '800px')
        .and('have.css', 'height', '400px');

      // Verify frequency axis labels
      cy.get('[data-testid="frequency-axis"]')
        .should('contain', '20Hz')
        .and('contain', '1kHz')
        .and('contain', '20kHz');

      // Verify magnitude axis labels
      cy.get('[data-testid="magnitude-axis"]')
        .should('contain', '-90dB')
        .and('contain', '-10dB');
    });

    it('should update in real-time with WebSocket data', () => {
      // Send updated spectrum data
      cy.window().then((win) => {
        win.postMessage({
          type: 'spectrum',
          data: {
            ...MOCK_SPECTRUM_DATA,
            magnitudes: new Float32Array(2048).fill(-50)
          }
        }, '*');
      });

      // Verify bars update
      cy.get('[data-testid="spectrum-bars"]')
        .should('have.length.gt', 0)
        .and('have.attr', 'height')
        .and('not.equal', '0');
    });

    it('should handle different frequency ranges', () => {
      // Test low frequency focus
      cy.get('[data-testid="frequency-range-selector"]')
        .select('low');
      cy.get('[data-testid="frequency-axis"]')
        .should('contain', '20Hz')
        .and('contain', '200Hz');

      // Test high frequency focus
      cy.get('[data-testid="frequency-range-selector"]')
        .select('high');
      cy.get('[data-testid="frequency-axis"]')
        .should('contain', '2kHz')
        .and('contain', '20kHz');
    });

    it('should be accessible', () => {
      cy.checkA11y('[data-testid="spectrum-analyzer"]', {
        rules: {
          'color-contrast': { enabled: true },
          'aria-allowed-attr': { enabled: true }
        }
      });
    });
  });

  describe('Waveform Display', () => {
    it('should render with proper scaling', () => {
      cy.get('[data-testid="waveform-display"]')
        .should('be.visible')
        .and('have.css', 'width', '800px')
        .and('have.css', 'height', '200px');

      // Verify time axis
      cy.get('[data-testid="time-axis"]')
        .should('contain', '0ms')
        .and('contain', '500ms');
    });

    it('should update with audio playback', () => {
      // Load test audio file
      cy.fixture(TEST_AUDIO_FILES[0]).then((audioData) => {
        cy.window().then((win) => {
          win.postMessage({
            type: 'audio',
            data: audioData
          }, '*');
        });
      });

      // Verify waveform updates
      cy.get('[data-testid="waveform-path"]')
        .should('have.attr', 'd')
        .and('not.equal', '');
    });

    it('should support zoom and pan controls', () => {
      // Test zoom in
      cy.get('[data-testid="zoom-in"]').click();
      cy.get('[data-testid="time-axis"]')
        .should('contain', '0ms')
        .and('contain', '250ms');

      // Test pan
      cy.get('[data-testid="waveform-display"]')
        .trigger('mousedown', { clientX: 400, clientY: 100 })
        .trigger('mousemove', { clientX: 300, clientY: 100 })
        .trigger('mouseup');
    });
  });

  describe('Processing Status', () => {
    it('should display all performance metrics', () => {
      cy.get('[data-testid="processing-status"]')
        .should('be.visible');

      // Verify CPU load
      cy.get('[data-testid="cpu-load"]')
        .should('contain', '35%')
        .and('have.css', 'color', 'rgb(0, 128, 0)'); // Green for normal load

      // Verify latency
      cy.get('[data-testid="latency"]')
        .should('contain', '8ms')
        .and('have.css', 'color', 'rgb(0, 128, 0)'); // Green for low latency

      // Verify THD+N
      cy.get('[data-testid="thd-n"]')
        .should('contain', '0.0004%')
        .and('have.css', 'color', 'rgb(0, 128, 0)'); // Green for good quality
    });

    it('should show warnings for threshold violations', () => {
      // Simulate high CPU load
      cy.window().then((win) => {
        win.postMessage({
          type: 'status',
          data: {
            ...MOCK_PROCESSING_STATUS,
            cpuLoad: 85
          }
        }, '*');
      });

      // Verify warning display
      cy.get('[data-testid="cpu-load"]')
        .should('have.css', 'color', 'rgb(255, 165, 0)') // Orange for warning
        .and('contain', '85%');
    });

    it('should handle error states gracefully', () => {
      // Simulate connection loss
      cy.window().then((win) => {
        win.postMessage({
          type: 'error',
          data: 'WebSocket disconnected'
        }, '*');
      });

      // Verify error display
      cy.get('[data-testid="error-message"]')
        .should('be.visible')
        .and('contain', 'Connection lost');
    });
  });

  describe('Accessibility and Performance', () => {
    it('should meet WCAG 2.1 AA standards', () => {
      cy.checkA11y();
    });

    it('should maintain performance under load', () => {
      // Simulate continuous data updates
      const interval = setInterval(() => {
        cy.window().then((win) => {
          win.postMessage({
            type: 'spectrum',
            data: {
              ...MOCK_SPECTRUM_DATA,
              timestamp: Date.now()
            }
          }, '*');
        });
      }, 16);

      // Check performance after 5 seconds
      cy.wait(5000).then(() => {
        clearInterval(interval);
        cy.get('[data-testid="frame-rate"]')
          .should('contain.text', '60');
      });
    });
  });
});