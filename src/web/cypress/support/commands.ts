// External imports with versions
import '@testing-library/cypress'; // v10.0.0
import '@cypress/code-coverage'; // v3.12.0

// Type definitions for custom commands
declare global {
  namespace Cypress {
    interface Chainable {
      setVolume(level: number, options?: Partial<{ timeout: number; force: boolean }>): Chainable<Element>;
      toggleAudioEnhancement(enable: boolean, options?: Partial<{ timeout: number }>): Chainable<Element>;
      configureSpatialAudio(spatialConfig: {
        roomSize?: 'small' | 'medium' | 'large';
        hrtfProfile?: string;
        headTracking?: boolean;
      }): Chainable<Element>;
      verifyAudioMetrics(expectedMetrics: {
        latency?: number;
        thdPlusN?: number;
        cpuUsage?: number;
        bufferHealth?: number;
      }): Chainable<Element>;
      waitForAudioProcessing(timeout?: number, options?: Partial<{ 
        checkInterval: number;
        errorThreshold: number;
      }>): Chainable<Element>;
    }
  }
}

// Constants for audio processing validation
const AUDIO_CONSTANTS = {
  MAX_LATENCY_MS: 10,
  MAX_THD_N_PERCENT: 0.0005,
  MAX_CPU_USAGE_PERCENT: 40,
  DEFAULT_TIMEOUT_MS: 5000,
  PROCESSING_CHECK_INTERVAL: 100,
  VOLUME_MIN: 0,
  VOLUME_MAX: 100
};

// Custom command to set and verify audio volume
Cypress.Commands.add('setVolume', (level: number, options = {}) => {
  const timeout = options.timeout || AUDIO_CONSTANTS.DEFAULT_TIMEOUT_MS;

  if (level < AUDIO_CONSTANTS.VOLUME_MIN || level > AUDIO_CONSTANTS.VOLUME_MAX) {
    throw new Error(`Volume level must be between ${AUDIO_CONSTANTS.VOLUME_MIN} and ${AUDIO_CONSTANTS.VOLUME_MAX}`);
  }

  return cy
    .get('[data-testid="volume-slider"]', { timeout })
    .should('be.visible')
    .clear()
    .type(`${level}`, { force: options.force })
    .should('have.value', `${level}`)
    .then(() => {
      return cy.waitForAudioProcessing()
        .then(() => {
          cy.get('[data-testid="volume-level-indicator"]')
            .should('contain', `${level}dB`);
        });
    });
});

// Custom command to toggle AI audio enhancement
Cypress.Commands.add('toggleAudioEnhancement', (enable: boolean, options = {}) => {
  const timeout = options.timeout || AUDIO_CONSTANTS.DEFAULT_TIMEOUT_MS;

  return cy
    .get('[data-testid="ai-enhancement-toggle"]', { timeout })
    .should('be.visible')
    .then($toggle => {
      const isEnabled = $toggle.hasClass('enabled');
      if (isEnabled !== enable) {
        cy.wrap($toggle).click();
        cy.waitForAudioProcessing()
          .then(() => {
            cy.get('[data-testid="ai-processing-status"]')
              .should('have.attr', 'data-status', enable ? 'active' : 'inactive');
          });
      }
    });
});

// Custom command to configure spatial audio settings
Cypress.Commands.add('configureSpatialAudio', (spatialConfig) => {
  return cy
    .get('[data-testid="spatial-audio-controls"]')
    .within(() => {
      if (spatialConfig.roomSize) {
        cy.get('[data-testid="room-size-select"]')
          .select(spatialConfig.roomSize)
          .should('have.value', spatialConfig.roomSize);
      }

      if (spatialConfig.hrtfProfile) {
        cy.get('[data-testid="hrtf-profile-select"]')
          .select(spatialConfig.hrtfProfile)
          .should('have.value', spatialConfig.hrtfProfile);
      }

      if (typeof spatialConfig.headTracking === 'boolean') {
        cy.get('[data-testid="head-tracking-toggle"]')
          .then($toggle => {
            const isEnabled = $toggle.hasClass('enabled');
            if (isEnabled !== spatialConfig.headTracking) {
              cy.wrap($toggle).click();
            }
          });
      }
    })
    .then(() => cy.waitForAudioProcessing());
});

// Custom command to verify audio processing metrics
Cypress.Commands.add('verifyAudioMetrics', (expectedMetrics) => {
  return cy
    .get('[data-testid="audio-metrics"]')
    .within(() => {
      if (expectedMetrics.latency !== undefined) {
        cy.get('[data-testid="latency-value"]')
          .invoke('text')
          .then(parseFloat)
          .should('be.lte', AUDIO_CONSTANTS.MAX_LATENCY_MS);
      }

      if (expectedMetrics.thdPlusN !== undefined) {
        cy.get('[data-testid="thd-n-value"]')
          .invoke('text')
          .then(parseFloat)
          .should('be.lte', AUDIO_CONSTANTS.MAX_THD_N_PERCENT);
      }

      if (expectedMetrics.cpuUsage !== undefined) {
        cy.get('[data-testid="cpu-usage-value"]')
          .invoke('text')
          .then(parseFloat)
          .should('be.lte', AUDIO_CONSTANTS.MAX_CPU_USAGE_PERCENT);
      }

      if (expectedMetrics.bufferHealth !== undefined) {
        cy.get('[data-testid="buffer-health-value"]')
          .invoke('text')
          .then(parseFloat)
          .should('be.gte', expectedMetrics.bufferHealth);
      }
    });
});

// Custom command to wait for audio processing completion
Cypress.Commands.add('waitForAudioProcessing', (timeout = AUDIO_CONSTANTS.DEFAULT_TIMEOUT_MS, options = {}) => {
  const checkInterval = options.checkInterval || AUDIO_CONSTANTS.PROCESSING_CHECK_INTERVAL;
  const errorThreshold = options.errorThreshold || 3;
  let errorCount = 0;

  return new Cypress.Promise((resolve, reject) => {
    const checkProcessing = () => {
      cy.get('[data-testid="processing-status"]')
        .then($status => {
          const status = $status.attr('data-status');
          
          if (status === 'error') {
            errorCount++;
            if (errorCount >= errorThreshold) {
              reject(new Error('Audio processing failed'));
              return;
            }
          }

          if (status === 'complete') {
            resolve();
            return;
          }

          if (timeout > 0) {
            timeout -= checkInterval;
            setTimeout(checkProcessing, checkInterval);
          } else {
            reject(new Error('Audio processing timeout'));
          }
        });
    };

    checkProcessing();
  });
});

// Export commands namespace
export {};