import type { Config } from '@types/jest';

const config: Config = {
  // Specify file extensions Jest will look for
  moduleFileExtensions: ['js', 'json', 'ts'],

  // Set root directory for tests
  rootDir: '.',

  // Use Node.js as test environment
  testEnvironment: 'node',

  // Pattern for test files
  testRegex: '.spec.ts$',

  // Configure TypeScript transformation
  transform: {
    '^.+\\.(t|j)s$': 'ts-jest'
  },

  // Configure coverage collection
  collectCoverageFrom: [
    '**/*.(t|j)s'
  ],

  // Coverage output directory
  coverageDirectory: './coverage',

  // Test timeout in milliseconds
  testTimeout: 30000,

  // Module path aliases for clean imports
  moduleNameMapper: {
    '^@app/(.*)$': '<rootDir>/src/$1',
    '^@common/(.*)$': '<rootDir>/src/common/$1',
    '^@config/(.*)$': '<rootDir>/src/config/$1',
    '^@audio/(.*)$': '<rootDir>/src/audio/$1',
    '^@ai/(.*)$': '<rootDir>/src/ai/$1',
    '^@spatial/(.*)$': '<rootDir>/src/spatial/$1',
    '^@profiles/(.*)$': '<rootDir>/src/profiles/$1'
  },

  // Coverage report formats
  coverageReporters: [
    'text',
    'lcov',
    'json-summary'
  ],

  // Coverage thresholds to enforce
  coverageThreshold: {
    global: {
      branches: 80,
      functions: 80,
      lines: 80,
      statements: 80
    }
  },

  // Enable verbose output
  verbose: true,

  // Detect async operations that weren't cleaned up
  detectOpenHandles: true,

  // Force exit after tests complete
  forceExit: true
};

export default config;