import { Injectable, UnauthorizedException } from '@nestjs/common';
import { PassportStrategy } from '@nestjs/passport';
import { Strategy, ExtractJwt } from 'passport-jwt';
import { TokenBlacklist } from '@nestjs/jwt';
import { SecurityLogger } from '@nestjs/common';
import { jwt } from '../../config/configuration';

/**
 * Interface for JWT payload with strict typing
 */
interface JwtPayload {
  sub: string;
  username: string;
  roles: string[];
  iat: number;
  exp: number;
  iss: string;
  aud: string[];
}

/**
 * Interface for validated user data
 */
interface UserData {
  id: string;
  username: string;
  roles: string[];
}

/**
 * Enhanced JWT authentication strategy for TALD UNIA Audio System
 * Implements secure token validation with comprehensive security logging
 * and performance optimization
 */
@Injectable()
export class JwtStrategy extends PassportStrategy(Strategy) {
  private readonly securityLogger: SecurityLogger;
  private readonly tokenBlacklist: TokenBlacklist;

  constructor(
    tokenBlacklist: TokenBlacklist,
    securityLogger: SecurityLogger
  ) {
    super({
      jwtFromRequest: ExtractJwt.fromAuthHeaderAsBearerToken(),
      ignoreExpiration: false,
      secretOrKey: jwt.secret,
      algorithms: ['RS256'],
      issuer: jwt.issuer,
      audience: jwt.audience,
      jsonWebTokenOptions: {
        maxAge: jwt.expiresIn,
        clockTolerance: 30, // 30 seconds clock skew tolerance
        complete: true // Return decoded payload and header
      }
    });

    this.tokenBlacklist = tokenBlacklist;
    this.securityLogger = securityLogger;
  }

  /**
   * Validates JWT payload with enhanced security checks and comprehensive logging
   * @param payload - The decoded JWT payload
   * @returns Promise resolving to validated user data
   * @throws UnauthorizedException for invalid tokens
   */
  async validate(payload: JwtPayload): Promise<UserData> {
    try {
      // Check if token is blacklisted
      const isBlacklisted = await this.tokenBlacklist.isBlacklisted(payload.sub);
      if (isBlacklisted) {
        this.securityLogger.warn('Attempt to use blacklisted token', {
          userId: payload.sub,
          timestamp: new Date().toISOString()
        });
        throw new UnauthorizedException('Token has been revoked');
      }

      // Validate payload structure
      if (!payload.sub || !payload.username || !Array.isArray(payload.roles)) {
        this.securityLogger.warn('Invalid token payload structure', {
          userId: payload.sub,
          timestamp: new Date().toISOString()
        });
        throw new UnauthorizedException('Invalid token structure');
      }

      // Verify token expiration
      const currentTimestamp = Math.floor(Date.now() / 1000);
      if (payload.exp <= currentTimestamp) {
        this.securityLogger.warn('Expired token used', {
          userId: payload.sub,
          timestamp: new Date().toISOString()
        });
        throw new UnauthorizedException('Token has expired');
      }

      // Verify issuer and audience
      if (payload.iss !== jwt.issuer || !jwt.audience.includes(payload.aud[0])) {
        this.securityLogger.warn('Invalid token issuer or audience', {
          userId: payload.sub,
          timestamp: new Date().toISOString()
        });
        throw new UnauthorizedException('Invalid token issuer or audience');
      }

      // Log successful validation
      this.securityLogger.log('JWT successfully validated', {
        userId: payload.sub,
        timestamp: new Date().toISOString(),
        roles: payload.roles
      });

      // Return validated user data
      return {
        id: payload.sub,
        username: payload.username,
        roles: payload.roles
      };
    } catch (error) {
      // Log validation errors
      this.securityLogger.error('JWT validation error', {
        error: error.message,
        timestamp: new Date().toISOString(),
        userId: payload?.sub
      });
      throw new UnauthorizedException('Token validation failed');
    }
  }
}