/**
 * TALD UNIA Audio System - Application Bootstrap
 * Version: 1.0.0
 * 
 * Initializes and configures the NestJS application with comprehensive security,
 * monitoring, and error handling features for premium audio processing.
 */

import { NestFactory } from '@nestjs/core'; // v10.0.0
import { FastifyAdapter } from '@nestjs/platform-fastify'; // v10.0.0
import { ValidationPipe } from './common/pipes/validation.pipe';
import { HttpExceptionFilter } from './common/filters/http-exception.filter';
import { TransformInterceptor } from './common/interceptors/transform.interceptor';
import { setupSwagger } from './swagger/swagger.config';
import { AppModule } from './app.module';
import * as helmet from 'helmet'; // v7.0.0
import * as compression from 'compression'; // v1.7.4
import * as rateLimit from '@fastify/rate-limit'; // v8.0.0
import * as pino from 'pino'; // v8.0.0

// Global constants
const PORT = process.env.PORT || 3000;
const NODE_ENV = process.env.NODE_ENV || 'development';
const SSL_KEY = process.env.SSL_KEY || 'ssl/private.key';
const SSL_CERT = process.env.SSL_CERT || 'ssl/certificate.crt';

// CORS configuration
const CORS_OPTIONS = {
  origin: ['http://localhost:3000', 'https://*.tald-unia.com'],
  methods: ['GET', 'POST', 'PUT', 'DELETE', 'OPTIONS'],
  allowedHeaders: ['Content-Type', 'Authorization', 'X-Request-ID'],
  credentials: true,
  maxAge: 86400
};

// Compression configuration
const COMPRESSION_OPTIONS = {
  level: 6,
  threshold: 1024,
  brotliOptions: {
    params: {
      quality: 4
    }
  }
};

// Security headers configuration
const HELMET_OPTIONS = {
  contentSecurityPolicy: {
    directives: {
      'default-src': ["'self'"],
      'script-src': ["'self'"],
      'style-src': ["'self'"],
      'img-src': ["'self'", 'data:', 'https:'],
      'connect-src': ["'self'"]
    }
  },
  crossOriginEmbedderPolicy: true,
  crossOriginOpenerPolicy: true,
  crossOriginResourcePolicy: true,
  dnsPrefetchControl: true,
  frameguard: true,
  hidePoweredBy: true,
  hsts: true,
  ieNoOpen: true,
  noSniff: true,
  referrerPolicy: true,
  xssFilter: true
};

// Rate limiting configuration
const RATE_LIMIT_OPTIONS = {
  max: 100,
  timeWindow: '1 minute',
  skipFailedRequests: true,
  keyGenerator: 'ip'
};

async function bootstrap(): Promise<void> {
  try {
    // Create Fastify-based NestJS application
    const app = await NestFactory.create(AppModule, new FastifyAdapter({
      logger: pino({
        level: NODE_ENV === 'production' ? 'info' : 'debug',
        redact: ['req.headers.authorization']
      }),
      trustProxy: true
    }));

    // Security middleware
    app.use(helmet(HELMET_OPTIONS));
    await app.register(rateLimit, RATE_LIMIT_OPTIONS);

    // Compression and CORS
    app.use(compression(COMPRESSION_OPTIONS));
    app.enableCors(CORS_OPTIONS);

    // Global pipes, filters, and interceptors
    app.useGlobalPipes(new ValidationPipe());
    app.useGlobalFilters(new HttpExceptionFilter());
    app.useGlobalInterceptors(new TransformInterceptor());

    // API versioning and prefix
    app.setGlobalPrefix('api/v1');
    app.enableVersioning();

    // Swagger documentation
    setupSwagger(app);

    // Graceful shutdown
    app.enableShutdownHooks();

    // SSL configuration for production
    const sslOptions = NODE_ENV === 'production' ? {
      key: SSL_KEY,
      cert: SSL_CERT
    } : undefined;

    // Start server
    await app.listen(PORT, '0.0.0.0', sslOptions);
    console.log(`TALD UNIA Audio System running on port ${PORT}`);

    // Handle uncaught errors
    process.on('unhandledRejection', (error: Error) => {
      console.error('Unhandled promise rejection:', error);
      // Implement error recovery strategy
    });

    process.on('uncaughtException', (error: Error) => {
      console.error('Uncaught exception:', error);
      // Implement graceful shutdown if needed
    });

  } catch (error) {
    console.error('Application bootstrap failed:', error);
    process.exit(1);
  }
}

// Start application
bootstrap();