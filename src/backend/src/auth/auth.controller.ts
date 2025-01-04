import { Controller, Post, Body, UseGuards, HttpStatus, HttpException, Logger } from '@nestjs/common'; // ^9.0.0
import { ApiTags, ApiOperation, ApiResponse, ApiSecurity } from '@nestjs/swagger'; // ^6.0.0
import { SecurityHeaders } from '@nestjs/helmet'; // ^8.0.0
import { ThrottlerGuard } from '@nestjs/throttler'; // ^4.0.0

import { AuthService } from './auth.service';
import { JwtAuthGuard } from './guards/jwt-auth.guard';
import { Roles } from './decorators/roles.decorator';

/**
 * Interface for login request validation
 */
interface LoginDto {
  username: string;
  password: string;
}

/**
 * Authentication controller implementing secure user authentication endpoints
 * with comprehensive security features and monitoring
 */
@Controller('auth')
@ApiTags('auth')
@ApiSecurity('bearer')
@SecurityHeaders()
export class AuthController {
  private readonly logger = new Logger(AuthController.name);
  private readonly loginMetrics = {
    attempts: 0,
    failures: 0,
    lastAttempt: null as Date | null
  };

  constructor(private readonly authService: AuthService) {}

  /**
   * Authenticates user and generates secure JWT token
   * Implements rate limiting and security monitoring
   * 
   * @param loginDto - Login credentials
   * @returns JWT access token with expiration
   */
  @Post('login')
  @UseGuards(ThrottlerGuard)
  @ApiOperation({ summary: 'Authenticate user' })
  @ApiResponse({ status: HttpStatus.OK, description: 'Login successful' })
  @ApiResponse({ status: HttpStatus.UNAUTHORIZED, description: 'Invalid credentials' })
  @ApiResponse({ status: HttpStatus.TOO_MANY_REQUESTS, description: 'Too many requests' })
  async login(
    @Body() loginDto: LoginDto
  ): Promise<{ access_token: string; expires_in: number }> {
    try {
      // Track login attempt
      this.loginMetrics.attempts++;
      this.loginMetrics.lastAttempt = new Date();

      // Validate request parameters
      if (!loginDto.username || !loginDto.password) {
        throw new HttpException(
          'Username and password are required',
          HttpStatus.BAD_REQUEST
        );
      }

      // Validate credentials and get user data
      const user = await this.authService.validateUser(
        loginDto.username,
        loginDto.password
      );

      // Generate JWT token
      const { access_token } = await this.authService.login(user);

      // Calculate token expiration
      const expires_in = 24 * 60 * 60; // 24 hours in seconds

      // Log successful authentication
      this.logger.log(`Successful authentication for user: ${loginDto.username}`);

      return { access_token, expires_in };

    } catch (error) {
      // Track failed attempt
      this.loginMetrics.failures++;

      // Log authentication failure (sanitized)
      this.logger.warn(
        `Authentication failed: ${error.message}`,
        { username: loginDto.username }
      );

      throw new HttpException(
        'Authentication failed',
        error.status || HttpStatus.UNAUTHORIZED
      );
    }
  }

  /**
   * Validates JWT token with comprehensive security checks
   * Requires admin role for access
   * 
   * @param token - JWT token to validate
   * @returns Token validation result with payload
   */
  @Post('validate')
  @UseGuards(JwtAuthGuard)
  @Roles('admin')
  @ApiOperation({ summary: 'Validate JWT token' })
  @ApiResponse({ status: HttpStatus.OK, description: 'Token valid' })
  @ApiResponse({ status: HttpStatus.UNAUTHORIZED, description: 'Invalid token' })
  @ApiResponse({ status: HttpStatus.FORBIDDEN, description: 'Insufficient permissions' })
  async validateToken(
    @Body('token') token: string
  ): Promise<{ valid: boolean; payload: any }> {
    try {
      // Validate token parameter
      if (!token) {
        throw new HttpException(
          'Token is required',
          HttpStatus.BAD_REQUEST
        );
      }

      // Verify token and check blacklist
      const payload = await this.authService.verifyToken(token);
      const isBlacklisted = await this.authService.checkTokenBlacklist(token);

      if (isBlacklisted) {
        throw new HttpException(
          'Token has been revoked',
          HttpStatus.UNAUTHORIZED
        );
      }

      // Log successful validation
      this.logger.log('Token successfully validated', {
        tokenId: payload.sub,
        roles: payload.roles
      });

      return {
        valid: true,
        payload: {
          sub: payload.sub,
          username: payload.username,
          roles: payload.roles,
          exp: payload.exp
        }
      };

    } catch (error) {
      // Log validation failure (sanitized)
      this.logger.warn(`Token validation failed: ${error.message}`);

      throw new HttpException(
        'Token validation failed',
        error.status || HttpStatus.UNAUTHORIZED
      );
    }
  }
}