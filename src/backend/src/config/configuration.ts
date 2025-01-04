import * as Joi from 'joi'; // ^17.9.0
import { ConfigFactory } from '@nestjs/config'; // ^10.0.0
import { validationSchema } from './validation.schema';

/**
 * Configuration factory function for TALD UNIA Audio System
 * Provides comprehensive, type-safe configuration management with secure handling of sensitive data
 */
export const configuration: ConfigFactory = () => {
  // Pre-validation configuration object with secure defaults
  const config = {
    server: {
      port: parseInt(process.env.SERVER_PORT || '3000', 10),
      nodeEnv: process.env.NODE_ENV || 'development',
      apiVersion: process.env.API_VERSION || 'v1',
      corsOrigins: (process.env.CORS_ORIGINS || 'http://localhost:3000').split(','),
      rateLimitWindow: parseInt(process.env.RATE_LIMIT_WINDOW || '900000', 10), // 15 minutes
      rateLimitMax: parseInt(process.env.RATE_LIMIT_MAX || '100', 10),
    },

    database: {
      host: process.env.DB_HOST || 'localhost',
      port: parseInt(process.env.DB_PORT || '5432', 10),
      username: process.env.DB_USERNAME,
      password: process.env.DB_PASSWORD,
      name: process.env.DB_NAME || 'tald_unia',
      poolSize: parseInt(process.env.DB_POOL_SIZE || '10', 10),
      connectionTimeout: parseInt(process.env.DB_CONNECTION_TIMEOUT || '5000', 10),
      maxRetries: parseInt(process.env.DB_MAX_RETRIES || '5', 10),
    },

    redis: {
      host: process.env.REDIS_HOST || 'localhost',
      port: parseInt(process.env.REDIS_PORT || '6379', 10),
      password: process.env.REDIS_PASSWORD,
      db: parseInt(process.env.REDIS_DB || '0', 10),
      keyPrefix: process.env.REDIS_KEY_PREFIX || 'tald:',
      connectionTimeout: parseInt(process.env.REDIS_CONNECTION_TIMEOUT || '5000', 10),
    },

    jwt: {
      secret: process.env.JWT_SECRET,
      expiration: process.env.JWT_EXPIRATION || '24h',
      refreshExpiration: process.env.JWT_REFRESH_EXPIRATION || '7d',
      algorithm: process.env.JWT_ALGORITHM || 'RS256',
      issuer: process.env.JWT_ISSUER || 'tald-unia',
      audience: (process.env.JWT_AUDIENCE || 'tald-unia-client').split(','),
    },

    audio: {
      sampleRate: parseInt(process.env.AUDIO_SAMPLE_RATE || '48000', 10),
      bitDepth: parseInt(process.env.AUDIO_BIT_DEPTH || '24', 10),
      bufferSize: parseInt(process.env.AUDIO_BUFFER_SIZE || '1024', 10),
      channels: parseInt(process.env.AUDIO_CHANNELS || '2', 10),
      format: process.env.AUDIO_FORMAT || 'float32',
      latencyTarget: parseInt(process.env.AUDIO_LATENCY_TARGET || '10', 10),
      processingMode: process.env.AUDIO_PROCESSING_MODE || 'realtime',
      dspThreads: parseInt(process.env.AUDIO_DSP_THREADS || '4', 10),
    },

    ai: {
      modelPath: process.env.AI_MODEL_PATH || './models',
      inferenceThreads: parseInt(process.env.AI_INFERENCE_THREADS || '4', 10),
      batchSize: parseInt(process.env.AI_BATCH_SIZE || '16', 10),
      precision: process.env.AI_PRECISION || 'float32',
      accelerator: process.env.AI_ACCELERATOR || 'cuda',
      memoryLimit: parseInt(process.env.AI_MEMORY_LIMIT || '4096', 10),
      optimizationLevel: process.env.AI_OPTIMIZATION_LEVEL || 'high',
    },

    monitoring: {
      metricsEnabled: process.env.METRICS_ENABLED === 'true',
      metricsPort: parseInt(process.env.METRICS_PORT || '9090', 10),
      logLevel: process.env.LOG_LEVEL || 'info',
      tracingEnabled: process.env.TRACING_ENABLED === 'true',
      tracingSampleRate: parseFloat(process.env.TRACING_SAMPLE_RATE || '0.1'),
    },
  };

  // Validate configuration using Joi schema
  const { error, value: validatedConfig } = validationSchema.validate(config, {
    abortEarly: false,
    stripUnknown: true,
    convert: true,
  });

  if (error) {
    throw new Error(`Configuration validation error: ${error.message}`);
  }

  // Post-validation security measures
  if (validatedConfig.server.nodeEnv === 'production') {
    // Ensure secure settings in production
    if (!validatedConfig.jwt.secret || validatedConfig.jwt.secret.length < 32) {
      throw new Error('Production environment requires a strong JWT secret');
    }
    
    if (!validatedConfig.database.password || validatedConfig.database.password.length < 12) {
      throw new Error('Production environment requires a strong database password');
    }
  }

  // Apply secure defaults for sensitive settings
  validatedConfig.jwt.algorithm = validatedConfig.jwt.algorithm || 'RS256';
  validatedConfig.server.corsOrigins = validatedConfig.server.corsOrigins.map(origin => origin.trim());

  // Cache configuration for performance
  Object.freeze(validatedConfig);

  return validatedConfig;
};

// Type definitions for strongly-typed configuration access
export interface ServerConfig {
  port: number;
  nodeEnv: string;
  apiVersion: string;
  corsOrigins: string[];
  rateLimitWindow: number;
  rateLimitMax: number;
}

export interface DatabaseConfig {
  host: string;
  port: number;
  username: string;
  password: string;
  name: string;
  poolSize: number;
  connectionTimeout: number;
  maxRetries: number;
}

export interface RedisConfig {
  host: string;
  port: number;
  password?: string;
  db: number;
  keyPrefix: string;
  connectionTimeout: number;
}

export interface JwtConfig {
  secret: string;
  expiration: string;
  refreshExpiration: string;
  algorithm: string;
  issuer: string;
  audience: string[];
}

export interface AudioConfig {
  sampleRate: number;
  bitDepth: number;
  bufferSize: number;
  channels: number;
  format: string;
  latencyTarget: number;
  processingMode: string;
  dspThreads: number;
}

export interface AIConfig {
  modelPath: string;
  inferenceThreads: number;
  batchSize: number;
  precision: string;
  accelerator: string;
  memoryLimit: number;
  optimizationLevel: string;
}

export interface MonitoringConfig {
  metricsEnabled: boolean;
  metricsPort: number;
  logLevel: string;
  tracingEnabled: boolean;
  tracingSampleRate: number;
}

export interface AppConfig {
  server: ServerConfig;
  database: DatabaseConfig;
  redis: RedisConfig;
  jwt: JwtConfig;
  audio: AudioConfig;
  ai: AIConfig;
  monitoring: MonitoringConfig;
}