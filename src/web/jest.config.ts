import type { Config } from '@jest/types'; // ^29.0.0
import { setupJestDom } from './tests/setup';

/**
 * Jest configuration for TALD UNIA web client testing environment
 * Provides comprehensive test settings for audio processing and visualization components
 */
const createJestConfig = (): Config.InitialOptions => ({
  // Use jsdom environment with Web Audio API support
  testEnvironment: 'jsdom',

  // Setup files to run before tests
  setupFilesAfterEnv: [
    '<rootDir>/tests/setup.ts'
  ],

  // Configure file transformers
  transform: {
    '^.+\\.(ts|tsx)$': 'ts-jest',
    '^.+\\.(js|jsx)$': 'babel-jest',
    '\\.(jpg|jpeg|png|gif|svg)$': 'jest-transform-stub',
    '\\.wav$': 'jest-audio-transformer',
    '\\.mp3$': 'jest-audio-transformer'
  },

  // Module resolution configuration
  moduleNameMapper: {
    '^@/(.*)$': '<rootDir>/src/$1',
    '\\.(css|less|scss|sass)$': 'identity-obj-proxy',
    '^@audio/(.*)$': '<rootDir>/src/audio/$1'
  },

  // Test file patterns
  testRegex: '(/__tests__/.*|(\\.|/)(test|spec))\\.(jsx?|tsx?)$',

  // Supported file extensions
  moduleFileExtensions: [
    'ts',
    'tsx',
    'js',
    'jsx',
    'json',
    'node',
    'wav',
    'mp3'
  ],

  // Coverage configuration
  collectCoverage: true,
  collectCoverageFrom: [
    'src/**/*.{ts,tsx}',
    '!src/**/*.d.ts',
    '!src/vite-env.d.ts',
    '!src/main.tsx',
    'src/audio/**/*.{ts,tsx}'
  ],
  coverageDirectory: 'coverage',
  coverageReporters: [
    'text',
    'lcov',
    'json-summary',
    'audio-metrics'
  ],

  // Coverage thresholds
  coverageThreshold: {
    global: {
      branches: 80,
      functions: 80,
      lines: 80,
      statements: 80
    },
    'src/audio/**/*.{ts,tsx}': {
      branches: 90,
      functions: 90,
      lines: 90,
      statements: 90
    }
  },

  // Test timeout configuration (10 seconds as per SLA requirements)
  testTimeout: 10000,

  // Global configuration
  globals: {
    'ts-jest': {
      tsconfig: 'tsconfig.json'
    },
    'AUDIO_PROCESSING_ENABLED': true,
    'NODE_ENV': 'test'
  }
});

// Export the configuration
export default createJestConfig();