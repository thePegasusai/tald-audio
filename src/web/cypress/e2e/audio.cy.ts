import { AudioProcessingState, ProcessingQuality } from '../../src/components/audio/AudioControls';

// Constants for test configuration
const TEST_TIMEOUT = 10000;
const AUDIO_SAMPLE_RATE = 192000;
const LATENCY_THRESHOLD_MS = 10;
const THD_N_THRESHOLD = 0.0005;
const MIN_SNR_DB = 120;

// Test audio file paths
const TEST_FILES = {
  sineWave: '/fixtures/audio/sine_1khz.wav',
  whiteNoise: '/fixtures/audio/white_noise.wav',
  musicSample: '/fixtures/audio/music_sample.wav'
};

describe('TALD UNIA Audio System', () => {
  beforeEach(() => {
    // Initialize audio context and WebGL2
    cy.visit('/audio-controls', {
      onBeforeLoad: (win) => {
        // Mock AudioContext
        cy.stub(win, 'AudioContext').as('audioContext').returns({
          sampleRate: AUDIO_SAMPLE_RATE,
          state: 'running',
          createGain: () => ({
            connect: cy.stub(),
            gain: { value: 1 }
          }),
          createAnalyser: () => ({
            connect: cy.stub(),
            getFloatTimeDomainData: cy.stub()
          })
        });

        // Mock WebGL2 context
        const canvas = win.document.createElement('canvas');
        cy.stub(canvas, 'getContext').withArgs('webgl2').returns({
          getExtension: cy.stub().returns({}),
          getParameter: cy.stub().returns(2)
        });
      }
    });

    // Wait for component initialization
    cy.get('[data-testid="audio-controls"]').should('exist');
  });

  describe('Audio Controls Functionality', () => {
    it('should initialize audio system with correct configuration', () => {
      cy.get('@audioContext').should('have.been.calledWith', {
        sampleRate: AUDIO_SAMPLE_RATE,
        latencyHint: 'interactive'
      });

      cy.get('[data-testid="quality-indicator"]')
        .should('have.attr', 'aria-label', 'Audio Quality: Optimal');
    });

    it('should handle play/pause controls correctly', () => {
      // Test play button
      cy.get('[aria-label="Play"]').click();
      cy.get('[data-testid="processing-status"]')
        .should('have.text', 'Processing: Active');

      // Verify audio state
      cy.window().its('audioState').should('deep.equal', {
        isProcessing: true,
        currentLoad: 0,
        bufferHealth: 100,
        latency: 0
      });

      // Test pause button
      cy.get('[aria-label="Pause"]').click();
      cy.get('[data-testid="processing-status"]')
        .should('have.text', 'Processing: Inactive');
    });

    it('should adjust volume control with proper scaling', () => {
      cy.get('[data-testid="volume-slider"]')
        .as('volumeSlider')
        .should('have.attr', 'aria-valuemin', '-60')
        .should('have.attr', 'aria-valuemax', '12');

      // Test volume adjustment
      cy.get('@volumeSlider')
        .trigger('change', { value: 0.8 })
        .should('have.attr', 'aria-valuenow', '0')
        .should('have.attr', 'aria-valuetext', '0 dB');
    });
  });

  describe('Audio Processing Quality', () => {
    it('should maintain THD+N below threshold', () => {
      cy.intercept('POST', '/api/audio/process', (req) => {
        req.reply({
          metrics: {
            thd: THD_N_THRESHOLD - 0.0001,
            snr: MIN_SNR_DB + 5,
            rmsLevel: -20,
            peakLevel: -3
          }
        });
      }).as('processAudio');

      cy.get('[aria-label="Play"]').click();
      cy.wait('@processAudio');

      cy.get('[data-testid="thd-measurement"]')
        .should('have.text', `THD: ${(THD_N_THRESHOLD * 100).toFixed(4)}%`);
    });

    it('should maintain latency within acceptable range', () => {
      cy.get('[aria-label="Play"]').click();

      // Monitor latency over time
      cy.get('[data-testid="latency-measurement"]')
        .should(($el) => {
          const latency = parseFloat($el.text().match(/\d+\.\d+/)[0]);
          expect(latency).to.be.lessThan(LATENCY_THRESHOLD_MS);
        });
    });

    it('should adapt processing quality based on system load', () => {
      cy.window().then((win) => {
        // Simulate high CPU load
        win.audioState.currentLoad = 0.8;
      });

      cy.get('[data-testid="quality-mode"]')
        .should('have.text', ProcessingQuality.PowerSaver);
    });
  });

  describe('Accessibility Compliance', () => {
    beforeEach(() => {
      cy.injectAxe();
    });

    it('should meet WCAG 2.1 AA standards', () => {
      cy.checkA11y('[data-testid="audio-controls"]', {
        runOnly: {
          type: 'tag',
          values: ['wcag2a', 'wcag2aa']
        }
      });
    });

    it('should support keyboard navigation', () => {
      // Test tab order
      cy.get('[data-testid="audio-controls"]').focus();
      cy.realPress('Tab');
      cy.get('[aria-label="Play"]').should('have.focus');
      cy.realPress('Tab');
      cy.get('[data-testid="volume-slider"]').should('have.focus');

      // Test keyboard control
      cy.get('[aria-label="Play"]')
        .focus()
        .type(' ')
        .should('have.attr', 'aria-pressed', 'true');
    });

    it('should handle screen reader announcements', () => {
      cy.get('[data-testid="volume-slider"]')
        .should('have.attr', 'aria-valuetext')
        .and('match', /^-?\d+(\.\d+)? dB$/);

      cy.get('[data-testid="processing-status"]')
        .should('have.attr', 'aria-live', 'polite');
    });
  });

  describe('Error Handling', () => {
    it('should handle WebGL2 initialization failure', () => {
      cy.visit('/audio-controls', {
        onBeforeLoad: (win) => {
          cy.stub(win.HTMLCanvasElement.prototype, 'getContext')
            .withArgs('webgl2')
            .returns(null);
        }
      });

      cy.get('[data-testid="error-message"]')
        .should('contain', 'WebGL2 support required');
    });

    it('should recover from audio processing errors', () => {
      cy.window().then((win) => {
        // Simulate processing error
        win.dispatchEvent(new CustomEvent('audioProcessingError', {
          detail: { type: 'ProcessingOverload' }
        }));
      });

      cy.get('[data-testid="error-message"]')
        .should('be.visible')
        .should('contain', 'Processing overload detected');

      // Verify automatic recovery
      cy.get('[data-testid="processing-status"]', { timeout: 5000 })
        .should('have.text', 'Processing: Active');
    });
  });
});