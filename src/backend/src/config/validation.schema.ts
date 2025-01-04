import * as Joi from 'joi'; // ^17.9.0

/**
 * Comprehensive validation schema for TALD UNIA backend configuration
 * Ensures type safety and security constraints for all configuration parameters
 */
export const validationSchema = Joi.object({
  // Server Configuration
  server: Joi.object({
    port: Joi.number()
      .required()
      .port()
      .default(3000)
      .description('Server port number for the TALD UNIA backend service'),
    
    nodeEnv: Joi.string()
      .required()
      .valid('development', 'production', 'test')
      .default('development')
      .description('Node environment for the application'),
    
    host: Joi.string()
      .required()
      .hostname()
      .default('localhost')
      .description('Server hostname for the application')
  }).required(),

  // Database Configuration
  database: Joi.object({
    host: Joi.string()
      .required()
      .hostname()
      .default('localhost')
      .description('PostgreSQL database host'),
    
    port: Joi.number()
      .required()
      .port()
      .default(5432)
      .description('PostgreSQL database port'),
    
    username: Joi.string()
      .required()
      .min(4)
      .max(32)
      .pattern(/^[a-zA-Z0-9_]+$/)
      .description('Database username with strict format requirements'),
    
    password: Joi.string()
      .required()
      .min(12)
      .pattern(/^(?=.*[a-z])(?=.*[A-Z])(?=.*\d)(?=.*[@$!%*?&])[A-Za-z\d@$!%*?&]+$/)
      .description('Strong database password with complexity requirements'),
    
    name: Joi.string()
      .required()
      .min(1)
      .max(63)
      .pattern(/^[a-zA-Z0-9_]+$/)
      .description('Database name with PostgreSQL naming restrictions')
  }).required(),

  // Redis Cache Configuration
  redis: Joi.object({
    host: Joi.string()
      .required()
      .hostname()
      .default('localhost')
      .description('Redis cache server host'),
    
    port: Joi.number()
      .required()
      .port()
      .default(6379)
      .description('Redis cache server port'),
    
    password: Joi.string()
      .min(16)
      .pattern(/^(?=.*[a-z])(?=.*[A-Z])(?=.*\d)(?=.*[@$!%*?&])[A-Za-z\d@$!%*?&]+$/)
      .description('Optional Redis password with strong requirements')
  }).required(),

  // JWT Authentication Configuration
  jwt: Joi.object({
    secret: Joi.string()
      .required()
      .min(32)
      .pattern(/^(?=.*[a-z])(?=.*[A-Z])(?=.*\d)(?=.*[@$!%*?&])[A-Za-z\d@$!%*?&]+$/)
      .description('JWT secret key with high entropy requirements'),
    
    expiration: Joi.string()
      .required()
      .pattern(/^\d+[hdm]$/)
      .default('24h')
      .description('JWT token expiration time in hours, days, or minutes'),
    
    refreshExpiration: Joi.string()
      .required()
      .pattern(/^\d+[hdm]$/)
      .default('7d')
      .description('JWT refresh token expiration time')
  }).required(),

  // Audio Processing Configuration
  audio: Joi.object({
    sampleRate: Joi.number()
      .required()
      .valid(44100, 48000, 96000, 192000)
      .default(48000)
      .description('Audio sample rate in Hz supporting standard high-fidelity rates'),
    
    bitDepth: Joi.number()
      .required()
      .valid(16, 24, 32)
      .default(24)
      .description('Audio bit depth for processing precision'),
    
    bufferSize: Joi.number()
      .required()
      .valid(256, 512, 1024, 2048)
      .default(1024)
      .description('Audio processing buffer size in samples'),
    
    channels: Joi.number()
      .required()
      .min(1)
      .max(32)
      .default(2)
      .description('Number of audio channels supported'),
    
    spatialProcessing: Joi.boolean()
      .default(true)
      .description('Enable/disable spatial audio processing')
  }).required(),

  // AI Processing Configuration
  ai: Joi.object({
    modelPath: Joi.string()
      .required()
      .default('./models')
      .pattern(/^[\w\/\-\.]+$/)
      .description('AI model directory path with safe path validation'),
    
    inferenceThreads: Joi.number()
      .required()
      .min(1)
      .max(32)
      .default(4)
      .description('Number of AI inference threads'),
    
    modelVersion: Joi.string()
      .required()
      .pattern(/^\d+\.\d+\.\d+$/)
      .default('1.0.0')
      .description('AI model version in semantic versioning format'),
    
    enhancementLevel: Joi.string()
      .required()
      .valid('low', 'medium', 'high')
      .default('medium')
      .description('AI enhancement processing level')
  }).required()
}).required();