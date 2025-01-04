import { applyDecorators, Type } from '@nestjs/common';
import { ApiExtraModels, ApiResponse, getSchemaPath } from '@nestjs/swagger';
import { PaginatedResponse } from '../interfaces/paginated-response.interface';

/**
 * Configuration options for the API response decorator
 * @interface ApiResponseOptions
 */
export interface ApiResponseOptions {
  /**
   * Response data type for schema generation and validation
   * @type {Type<any>}
   */
  type: Type<any>;

  /**
   * HTTP status code for the response
   * @type {number}
   */
  status: number;

  /**
   * Flag indicating if response should use pagination schema
   * @type {boolean}
   */
  isPaginated?: boolean;

  /**
   * Detailed description for Swagger documentation
   * @type {string}
   */
  description?: string;
}

/**
 * Factory function that creates a combined decorator for comprehensive API response
 * documentation and validation. Supports both paginated and non-paginated responses
 * with proper schema validation and Swagger documentation.
 * 
 * @param options - Configuration options for the API response documentation and validation
 * @returns Combined decorator that can be applied to methods or classes
 * 
 * @example
 * // For a paginated response
 * @ApiResponseDecorator({
 *   type: UserDto,
 *   status: HttpStatus.OK,
 *   isPaginated: true,
 *   description: 'Successfully retrieved users list'
 * })
 * 
 * @example
 * // For a single response
 * @ApiResponseDecorator({
 *   type: UserDto,
 *   status: HttpStatus.CREATED,
 *   description: 'User successfully created'
 * })
 */
export const ApiResponseDecorator = (options: ApiResponseOptions): MethodDecorator & ClassDecorator => {
  // Validate required options
  if (!options.type) {
    throw new Error('API response type must be specified');
  }
  if (!options.status) {
    throw new Error('HTTP status code must be specified');
  }

  // Default description if not provided
  const description = options.description || `Response with status ${options.status}`;

  if (options.isPaginated) {
    return applyDecorators(
      ApiExtraModels(PaginatedResponse, options.type),
      ApiResponse({
        status: options.status,
        description,
        schema: {
          allOf: [
            { $ref: getSchemaPath(PaginatedResponse) },
            {
              properties: {
                data: {
                  type: 'array',
                  items: { $ref: getSchemaPath(options.type) },
                },
                meta: {
                  type: 'object',
                  properties: {
                    page: { type: 'number' },
                    take: { type: 'number' },
                    itemCount: { type: 'number' },
                    pageCount: { type: 'number' },
                    hasPreviousPage: { type: 'boolean' },
                    hasNextPage: { type: 'boolean' }
                  }
                }
              }
            }
          ]
        }
      })
    );
  }

  return applyDecorators(
    ApiExtraModels(options.type),
    ApiResponse({
      status: options.status,
      description,
      schema: {
        allOf: [
          { $ref: getSchemaPath(options.type) }
        ]
      }
    })
  );
};