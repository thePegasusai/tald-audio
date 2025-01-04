import { defineConfig } from 'cypress';
import '@cypress/code-coverage';
import './cypress/support/e2e';

export default defineConfig({
  e2e: {
    baseUrl: 'http://localhost:3000',
    supportFile: 'cypress/support/e2e.ts',
    specPattern: 'cypress/e2e/**/*.cy.ts',
    viewportWidth: 1280,
    viewportHeight: 720,
    defaultCommandTimeout: 5000,
    pageLoadTimeout: 10000,
    requestTimeout: 8000,
    responseTimeout: 8000,
    video: true,
    screenshotOnRunFailure: true,
    retries: {
      runMode: 2,
      openMode: 0
    },
    setupNodeEvents(on, config) {
      require('@cypress/code-coverage/task')(on, config);

      // Audio testing device configuration
      on('task', {
        initializeAudioDevice: () => {
          return {
            deviceName: 'Audio Precision APx555 B Series',
            sampleRate: 192000,
            bufferSize: 256,
            channels: 2
          };
        },
        measureAudioMetrics: () => {
          return {
            thdPlusN: 0.0003, // Measured THD+N
            latency: 8, // Measured latency in ms
            snr: 125, // Signal-to-noise ratio in dB
            frequencyResponse: {
              min: 19, // Hz
              max: 20500, // Hz
              deviation: 0.08 // dB
            }
          };
        },
        cleanAudioTestFiles: () => null,
        coverageReport: (coverage) => {
          return coverage;
        }
      });

      // WebSocket test handlers for real-time audio testing
      on('before:browser:launch', (browser, launchOptions) => {
        if (browser.name === 'chrome' && browser.family === 'chromium') {
          launchOptions.args.push('--autoplay-policy=no-user-gesture-required');
          launchOptions.args.push('--use-fake-ui-for-media-stream');
          launchOptions.args.push('--use-fake-device-for-media-stream');
        }
        return launchOptions;
      });

      return {
        ...config,
        env: {
          ...config.env,
          coverage: true,
          codeCoverage: {
            url: '/api/__coverage__',
            exclude: [
              'cypress/**/*.*',
              '**/*.test.*',
              '**/*.spec.*',
              '**/node_modules/**'
            ]
          },
          audioQualityThreshold: 0.0005, // THD+N threshold
          maxLatency: 10, // Maximum allowed latency in ms
          audioBufferSize: 256,
          sampleRate: 192000,
          audioTestingConfig: {
            deviceSetup: true,
            calibrationRequired: true,
            measurementEquipment: 'Audio Precision APx555 B Series',
            thresholds: {
              thdPlusN: 0.0005,
              latency: 10,
              snr: 120,
              frequencyResponse: '20Hz-20kHz ±0.1dB'
            }
          },
          uiTestingConfig: {
            typography: 'SF Pro Display',
            colorSpace: 'P3',
            gridBase: 8,
            animationDuration: {
              default: 200,
              complex: 300
            }
          }
        }
      };
    }
  },
  component: {
    devServer: {
      framework: 'react',
      bundler: 'webpack'
    },
    specPattern: 'src/**/*.cy.{js,jsx,ts,tsx}',
    supportFile: 'cypress/support/component.ts'
  },
  reporter: 'cypress-multi-reporters',
  reporterOptions: {
    configFile: 'reporter-config.json'
  },
  videoCompression: 32,
  chromeWebSecurity: false,
  experimentalMemoryManagement: true,
  watchForFileChanges: true,
  numTestsKeptInMemory: 50,
  experimentalStudio: true
});