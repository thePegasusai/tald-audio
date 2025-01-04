import { DocumentBuilder, SwaggerModule } from '@nestjs/swagger'; // ^7.0.0
import { INestApplication } from '@nestjs/common'; // ^10.0.0
import { configuration } from '../config/configuration'; // Import configuration settings

/**
 * Swagger API documentation configuration constants
 */
const SWAGGER_CONFIG = {
  title: 'TALD UNIA Audio System API',
  description: `
    Premium audio processing system with AI-driven enhancement capabilities.
    Provides high-fidelity audio processing, spatial audio rendering, and comprehensive user profile management.
    
    Key Features:
    - Real-time audio processing with AI enhancement
    - Spatial audio processing with head tracking
    - User profile and settings management
    - Advanced DSP capabilities
    - System monitoring and analytics
  `,
  version: '1.0',
  tags: [
    { name: 'Audio Processing', description: 'Audio processing and enhancement endpoints' },
    { name: 'Spatial Audio', description: 'Spatial audio processing and head tracking' },
    { name: 'User Profiles', description: 'User profile and settings management' },
    { name: 'AI Enhancement', description: 'AI-driven audio enhancement controls' },
    { name: 'System Management', description: 'System configuration and monitoring' },
    { name: 'Authentication', description: 'Authentication and authorization endpoints' }
  ]
};

/**
 * Configures and initializes Swagger documentation for the TALD UNIA Audio System API
 * @param app - NestJS application instance
 */
export const setupSwagger = (app: INestApplication): void => {
  const config = configuration();
  
  const documentBuilder = new DocumentBuilder()
    .setTitle(SWAGGER_CONFIG.title)
    .setDescription(SWAGGER_CONFIG.description)
    .setVersion(SWAGGER_CONFIG.version)
    // JWT Authentication
    .addBearerAuth(
      {
        type: 'http',
        scheme: 'bearer',
        bearerFormat: 'JWT',
        name: 'JWT',
        description: 'Enter JWT token',
        in: 'header'
      },
      'JWT-auth'
    )
    // OAuth2 Authentication
    .addOAuth2({
      type: 'oauth2',
      flows: {
        password: {
          tokenUrl: `${config.server.apiVersion}/auth/login`,
          refreshUrl: `${config.server.apiVersion}/auth/refresh`,
          scopes: {
            'read:audio': 'Read audio processing settings',
            'write:audio': 'Modify audio processing settings',
            'read:profile': 'Read user profile information',
            'write:profile': 'Modify user profile settings',
            'admin': 'Full system administration access'
          }
        }
      }
    })
    // API Tags
    .addTags(...SWAGGER_CONFIG.tags.map(tag => tag.name))
    // API Servers
    .addServer(`http://localhost:${config.server.port}`, 'Local Development')
    .addServer('https://api.tald-unia.com', 'Production Environment')
    // Global Security Requirements
    .addSecurity('JWT-auth', {
      type: 'http',
      scheme: 'bearer'
    })
    .build();

  const document = SwaggerModule.createDocument(app, documentBuilder, {
    deepScanRoutes: true,
    operationIdFactory: (
      controllerKey: string,
      methodKey: string
    ) => methodKey,
    extraModels: [], // Add any additional models here
  });

  SwaggerModule.setup('api/docs', app, document, {
    explorer: true,
    swaggerOptions: {
      persistAuthorization: true,
      tagsSorter: 'alpha',
      operationsSorter: 'alpha',
      docExpansion: 'none',
      filter: true,
      showRequestDuration: true,
      syntaxHighlight: {
        theme: 'monokai'
      }
    },
    customCss: '.swagger-ui .topbar { display: none }',
    customSiteTitle: 'TALD UNIA API Documentation',
    customfavIcon: '/favicon.ico'
  });
};

/**
 * Response models for common API responses
 */
export const ApiResponses = {
  Unauthorized: {
    status: 401,
    description: 'Unauthorized access - valid authentication credentials required'
  },
  Forbidden: {
    status: 403,
    description: 'Forbidden - insufficient permissions for the requested operation'
  },
  NotFound: {
    status: 404,
    description: 'Requested resource not found'
  },
  ValidationError: {
    status: 422,
    description: 'Validation error - invalid input parameters'
  },
  InternalError: {
    status: 500,
    description: 'Internal server error occurred'
  }
};