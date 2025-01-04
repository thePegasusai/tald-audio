import { SetMetadata } from '@nestjs/common';

/**
 * Constant key used for storing role metadata on route handlers
 * @constant {string}
 */
export const ROLES_KEY = 'roles';

/**
 * Valid role format regular expression
 * Allows alphanumeric characters and underscores, 3-50 characters long
 */
const VALID_ROLE_FORMAT = /^[A-Za-z0-9_]{3,50}$/;

/**
 * Custom type for role validation errors
 */
type RoleValidationError = {
  role: string;
  reason: string;
};

/**
 * Validates a single role string format
 * @param role - Role string to validate
 * @returns True if valid, false otherwise
 */
const isValidRoleFormat = (role: string): boolean => {
  return VALID_ROLE_FORMAT.test(role);
};

/**
 * Validates an array of roles
 * @param roles - Array of role strings to validate
 * @throws Error if validation fails
 */
const validateRoles = (roles: string[]): void => {
  if (!Array.isArray(roles)) {
    throw new Error('Roles must be provided as an array of strings');
  }

  if (roles.length === 0) {
    throw new Error('At least one role must be specified');
  }

  const errors: RoleValidationError[] = [];

  roles.forEach(role => {
    if (typeof role !== 'string') {
      errors.push({
        role: String(role),
        reason: 'Role must be a string'
      });
    } else if (!isValidRoleFormat(role)) {
      errors.push({
        role,
        reason: 'Role must be 3-50 characters long and contain only alphanumeric characters and underscores'
      });
    }
  });

  if (errors.length > 0) {
    throw new Error(
      'Invalid roles provided:\n' +
      errors.map(err => `- ${err.role}: ${err.reason}`).join('\n')
    );
  }
}

/**
 * Decorator factory that creates a roles requirement metadata decorator
 * Provides type-safe role-based access control for route handlers
 * 
 * @param roles - Array of role strings required for route access
 * @returns MethodDecorator with validated role requirements metadata
 * 
 * @example
 * ```typescript
 * @Roles('ADMIN', 'POWER_USER')
 * @Get('protected-route')
 * protectedEndpoint() {
 *   // Only accessible by users with ADMIN or POWER_USER roles
 * }
 * ```
 * 
 * @throws Error if invalid roles are provided
 */
export const Roles = (...roles: string[]): MethodDecorator => {
  // Validate roles at decorator creation time
  validateRoles(roles);

  // Create unique array of roles to prevent duplicates
  const uniqueRoles = [...new Set(roles)];

  // Create and return the decorator with validated roles metadata
  return SetMetadata(ROLES_KEY, uniqueRoles);
};