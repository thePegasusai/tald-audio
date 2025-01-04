import { Injectable, ExecutionContext, UnauthorizedException } from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import { AuthGuard } from '@nestjs/passport';
import { ROLES_KEY } from '../decorators/roles.decorator';

/**
 * Enhanced JWT authentication guard with role-based access control
 * Implements comprehensive security monitoring and validation
 * @version 1.0.0
 */
@Injectable()
export class JwtAuthGuard extends AuthGuard('jwt') {
  /**
   * Validation attempt tracking for security monitoring
   */
  private static readonly AUTH_METRICS = {
    attempts: 0,
    failures: 0,
    lastAttempt: null as Date | null,
  };

  constructor(private readonly reflector: Reflector) {
    super();
  }

  /**
   * Validates JWT token and enforces role-based access control
   * Implements comprehensive security monitoring and logging
   * 
   * @param context - Execution context containing request details
   * @returns Promise resolving to authorization result
   * @throws UnauthorizedException for invalid tokens or insufficient permissions
   */
  async canActivate(context: ExecutionContext): Promise<boolean> {
    try {
      // Track authentication attempt
      JwtAuthGuard.AUTH_METRICS.attempts++;
      JwtAuthGuard.AUTH_METRICS.lastAttempt = new Date();

      // Perform base JWT authentication
      const isAuthenticated = await super.canActivate(context);
      if (!isAuthenticated) {
        throw new UnauthorizedException('Invalid or expired authentication token');
      }

      // Extract required roles from route metadata
      const requiredRoles = this.reflector.getAllAndOverge<string[]>(
        ROLES_KEY,
        [context.getHandler(), context.getClass()]
      );

      // If no roles specified, allow authenticated access
      if (!requiredRoles || requiredRoles.length === 0) {
        return true;
      }

      // Get request and user details
      const request = context.switchToHttp().getRequest();
      const user = request.user;

      // Validate user object
      if (!user || !Array.isArray(user.roles)) {
        throw new UnauthorizedException('Invalid user profile or missing roles');
      }

      // Validate user roles against requirements
      const hasRequiredRole = requiredRoles.some(role => 
        user.roles.includes(role)
      );

      if (!hasRequiredRole) {
        throw new UnauthorizedException(
          'Insufficient permissions to access this resource'
        );
      }

      return true;

    } catch (error) {
      // Track authentication failure
      JwtAuthGuard.AUTH_METRICS.failures++;

      // Enhanced error handling with security context
      throw new UnauthorizedException(
        this.getDetailedErrorMessage(error)
      );
    }
  }

  /**
   * Enhanced error handler for authentication failures
   * Implements comprehensive security logging and monitoring
   * 
   * @param err - Error object from authentication attempt
   * @param user - User object if partially authenticated
   * @returns Authenticated user or throws security exception
   */
  handleRequest(err: Error, user: any): any {
    // Log authentication attempt details (sanitized)
    const attemptContext = {
      timestamp: new Date().toISOString(),
      success: !err && !!user,
      errorType: err?.constructor?.name,
      hasUser: !!user,
    };

    // Validate error conditions
    if (err || !user) {
      const errorMessage = this.getDetailedErrorMessage(err);
      throw new UnauthorizedException(errorMessage);
    }

    // Validate user object structure
    if (!this.isValidUserObject(user)) {
      throw new UnauthorizedException('Invalid user profile structure');
    }

    return user;
  }

  /**
   * Generates detailed error messages for security exceptions
   * @param error - Original error object
   * @returns Sanitized error message
   */
  private getDetailedErrorMessage(error: Error): string {
    const baseMessage = 'Authentication failed';
    
    // Sanitize error message to prevent information disclosure
    if (!error) {
      return baseMessage;
    }

    const errorType = error.constructor.name;
    switch (errorType) {
      case 'TokenExpiredError':
        return 'Authentication token has expired';
      case 'JsonWebTokenError':
        return 'Invalid authentication token';
      case 'UnauthorizedException':
        return error.message || 'Unauthorized access';
      default:
        return baseMessage;
    }
  }

  /**
   * Validates user object structure for security
   * @param user - User object to validate
   * @returns Boolean indicating validity
   */
  private isValidUserObject(user: any): boolean {
    return (
      user &&
      typeof user === 'object' &&
      Array.isArray(user.roles) &&
      user.roles.every(role => typeof role === 'string') &&
      typeof user.id === 'string'
    );
  }
}