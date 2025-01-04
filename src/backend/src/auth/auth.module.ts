import { Module } from '@nestjs/common';
import { PassportModule } from '@nestjs/passport';
import { JwtModule } from '@nestjs/jwt';
import { ConfigModule } from '@nestjs/config';
import { ThrottlerModule } from '@nestjs/throttler';
import { CacheModule } from '@nestjs/cache-manager';

import { AuthService } from './auth.service';
import { AuthController } from './auth.controller';
import { JwtStrategy } from './strategies/jwt.strategy';
import { configuration } from '../config/configuration';

/**
 * Enhanced Authentication Module for TALD UNIA Audio System
 * Implements comprehensive security features including:
 * - JWT authentication with RS256 signing
 * - Token blacklisting and validation
 * - Rate limiting protection
 * - Security monitoring and caching
 * 
 * @version 1.0.0
 */
@Module({
  imports: [
    // Passport authentication with JWT strategy
    PassportModule.register({
      defaultStrategy: 'jwt',
      property: 'user',
      session: false
    }),

    // JWT module with enhanced security configuration
    JwtModule.registerAsync({
      imports: [ConfigModule],
      useFactory: async (config = configuration()) => ({
        secret: config.jwt.secret,
        signOptions: {
          expiresIn: config.jwt.expiration,
          algorithm: 'RS256',
          issuer: config.jwt.issuer,
          audience: config.jwt.audience,
          notBefore: 0 // Token valid immediately
        },
        verifyOptions: {
          algorithms: ['RS256'],
          issuer: config.jwt.issuer,
          audience: config.jwt.audience,
          clockTolerance: 30 // 30 seconds clock skew tolerance
        }
      })
    }),

    // Configuration module with validation
    ConfigModule.forRoot({
      load: [configuration],
      cache: true,
      validate: true,
      validationOptions: {
        allowUnknown: false,
        abortEarly: true
      }
    }),

    // Rate limiting protection
    ThrottlerModule.forRootAsync({
      imports: [ConfigModule],
      useFactory: async (config = configuration()) => ([
        {
          ttl: config.server.rateLimitWindow,
          limit: config.server.rateLimitMax,
          ignoreUserAgents: [/health-check/]
        }
      ])
    }),

    // Token caching for performance
    CacheModule.register({
      ttl: 3600, // 1 hour cache
      max: 10000, // Maximum 10000 items
      isGlobal: true
    })
  ],
  providers: [
    // Core authentication providers
    AuthService,
    JwtStrategy,

    // Security monitoring provider
    {
      provide: 'SECURITY_MONITOR',
      useFactory: () => ({
        trackEvent: (eventType: string, data: any) => {
          // Log security events (implementation in monitoring service)
          console.log(`Security Event [${eventType}]:`, data);
        }
      })
    },

    // Token blacklist provider
    {
      provide: 'TOKEN_BLACKLIST',
      useFactory: () => new Set<string>()
    }
  ],
  controllers: [AuthController],
  exports: [
    AuthService,
    JwtModule,
    PassportModule
  ]
})
export class AuthModule {}