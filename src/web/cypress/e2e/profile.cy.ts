/**
 * End-to-end tests for TALD UNIA profile management functionality
 * @version 1.0.0
 */

import { ProcessingQuality, type Profile, type AudioSettings } from '../../src/types/profile.types';
import '@testing-library/cypress';

// Test fixtures for audio profiles
const defaultAudioSettings: AudioSettings = {
  id: 'test-settings-1',
  profileId: 'test-profile-1',
  sampleRate: 192000,
  bitDepth: 32,
  channels: 2,
  bufferSize: 256,
  processingQuality: ProcessingQuality.Maximum,
  dspConfig: {
    enableEQ: true,
    eqBands: [],
    enableCompression: true,
    compressorSettings: {
      threshold: -24,
      ratio: 4,
      attack: 5,
      release: 50,
      knee: 6,
      makeupGain: 0,
      enabled: true
    },
    enableRoomCorrection: true,
    roomConfig: {
      enabled: true,
      roomSize: 'medium',
      correctionStrength: 0.8
    }
  },
  aiConfig: {
    enabled: true,
    enhancementLevel: 0.8,
    noiseReduction: true,
    spatialUpsampling: true,
    modelVersion: '1.0.0',
    processingMode: 'realtime'
  },
  spatialConfig: {
    enabled: true,
    roomProfile: 'studio',
    hrtfProfile: 'default',
    headTracking: true,
    binauralRendering: true,
    objectBasedAudio: true,
    speakerLayout: 'stereo'
  },
  isActive: true
};

describe('Profile Management', () => {
  beforeEach(() => {
    // Reset database state and visit profile page
    cy.task('db:reset');
    cy.visit('/profiles');
    cy.injectAxe(); // Initialize accessibility testing

    // Wait for profile list to load
    cy.get('[data-cy=profile-list]').should('exist');
  });

  it('should create new profile with valid settings', () => {
    // Click create profile button
    cy.get('[data-cy=create-profile-btn]').click();

    // Fill profile details
    cy.get('[data-cy=profile-name-input]').type('Studio Profile');
    cy.get('[data-cy=processing-quality-select]').select(ProcessingQuality.Maximum);

    // Configure audio settings
    cy.get('[data-cy=sample-rate-select]').select('192000');
    cy.get('[data-cy=bit-depth-select]').select('32');

    // Enable AI processing
    cy.get('[data-cy=ai-enhancement-toggle]').click();
    cy.get('[data-cy=enhancement-level-slider]').invoke('val', 0.8).trigger('change');

    // Configure spatial audio
    cy.get('[data-cy=spatial-audio-toggle]').click();
    cy.get('[data-cy=room-profile-select]').select('studio');
    cy.get('[data-cy=head-tracking-toggle]').click();

    // Save profile
    cy.get('[data-cy=save-profile-btn]').click();

    // Verify profile creation
    cy.get('[data-cy=profile-list]')
      .should('contain', 'Studio Profile')
      .and('contain', ProcessingQuality.Maximum);

    // Verify audio settings were saved correctly
    cy.get('[data-cy=profile-item]').first().click();
    cy.get('[data-cy=audio-settings]').should('deep.equal', defaultAudioSettings);
  });

  it('should validate audio settings constraints', () => {
    cy.get('[data-cy=create-profile-btn]').click();

    // Try invalid sample rate
    cy.get('[data-cy=sample-rate-select]').select('384000');
    cy.get('[data-cy=sample-rate-error]')
      .should('be.visible')
      .and('contain', 'Maximum supported sample rate is 192kHz');

    // Try invalid AI enhancement level
    cy.get('[data-cy=ai-enhancement-toggle]').click();
    cy.get('[data-cy=enhancement-level-slider]').invoke('val', 1.5).trigger('change');
    cy.get('[data-cy=enhancement-level-error]')
      .should('be.visible')
      .and('contain', 'Enhancement level must be between 0 and 1');
  });

  it('should maintain performance under load', () => {
    // Create profile with maximum quality settings
    cy.createProfileWithSettings(defaultAudioSettings);

    // Start audio processing
    cy.get('[data-cy=start-processing-btn]').click();

    // Monitor performance metrics
    cy.get('[data-cy=performance-metrics]', { timeout: 10000 }).should(($metrics) => {
      const metrics = JSON.parse($metrics.attr('data-metrics'));
      expect(metrics.processingLoad).to.be.lessThan(0.4); // Max 40% CPU
      expect(metrics.latency).to.be.lessThan(10); // Max 10ms latency
      expect(metrics.bufferHealth).to.be.greaterThan(0.95); // Min 95% buffer health
    });
  });

  it('should handle profile updates correctly', () => {
    // Create initial profile
    cy.createProfileWithSettings(defaultAudioSettings);

    // Modify profile settings
    cy.get('[data-cy=profile-item]').first().click();
    cy.get('[data-cy=edit-profile-btn]').click();

    // Update audio settings
    cy.get('[data-cy=processing-quality-select]').select(ProcessingQuality.Balanced);
    cy.get('[data-cy=enhancement-level-slider]').invoke('val', 0.6).trigger('change');

    // Save changes
    cy.get('[data-cy=save-changes-btn]').click();

    // Verify updates
    cy.get('[data-cy=profile-item]').first().should('contain', ProcessingQuality.Balanced);
    cy.get('[data-cy=enhancement-level-value]').should('contain', '0.6');
  });

  it('should meet accessibility requirements', () => {
    // Check for accessibility violations
    cy.checkA11y('[data-cy=profile-management]', {
      rules: {
        'color-contrast': { enabled: true },
        'aria-required-parent': { enabled: true },
        'aria-required-children': { enabled: true }
      }
    });

    // Test keyboard navigation
    cy.get('[data-cy=create-profile-btn]').focus().type('{enter}');
    cy.get('[data-cy=profile-name-input]').should('have.focus');

    // Verify screen reader labels
    cy.get('[data-cy=enhancement-level-slider]')
      .should('have.attr', 'aria-label')
      .and('contain', 'AI Enhancement Level');
  });

  // Custom command to verify audio settings
  Cypress.Commands.add('verifyAudioSettings', (settings: AudioSettings) => {
    cy.get('[data-cy=audio-settings]').should(($el) => {
      const actualSettings = JSON.parse($el.attr('data-settings'));
      expect(actualSettings).to.deep.equal(settings);
    });
  });

  // Custom command to create profile with settings
  Cypress.Commands.add('createProfileWithSettings', (settings: AudioSettings) => {
    cy.get('[data-cy=create-profile-btn]').click();
    cy.get('[data-cy=profile-name-input]').type('Test Profile');
    cy.window().then((win) => {
      win.postMessage({ type: 'setAudioSettings', settings }, '*');
    });
    cy.get('[data-cy=save-profile-btn]').click();
  });
});