import { Injectable, NestInterceptor, ExecutionContext, CallHandler, Logger } from '@nestjs/common';
import { Observable } from 'rxjs';
import { map } from 'rxjs/operators';
import { PaginatedResponse } from '../interfaces/paginated-response.interface';

/**
 * Generic interface for standardized API responses with enhanced type safety and metadata support
 * @interface Response<T>
 * @template T - Type of the response data
 */
export interface Response<T> {
  /**
   * Response payload with generic type support
   * @type {T}
   */
  data: T;

  /**
   * ISO format response timestamp for tracking
   * @type {string}
   */
  timestamp: string;

  /**
   * HTTP status code from response
   * @type {number}
   */
  statusCode: number;

  /**
   * Optional metadata for additional response information
   * @type {Record<string, any>}
   */
  meta?: Record<string, any>;
}

/**
 * Advanced interceptor for transforming API responses with enhanced features including
 * monitoring, security, and standardized formatting
 * @class TransformInterceptor
 * @implements {NestInterceptor<T, Response<T>>}
 */
@Injectable()
export class TransformInterceptor<T> implements NestInterceptor<T, Response<T>> {
  private readonly logger = new Logger(TransformInterceptor.name);

  /**
   * Intercepts and transforms API responses with enhanced features
   * @param {ExecutionContext} context - Execution context containing request/response details
   * @param {CallHandler} next - Call handler for processing the response
   * @returns {Observable<Response<T>>} Transformed response observable with standardized format
   */
  intercept(context: ExecutionContext, next: CallHandler): Observable<Response<T>> {
    const ctx = context.switchToHttp();
    const response = ctx.getResponse();
    const startTime = Date.now();

    return next.handle().pipe(
      map(data => {
        const statusCode = response.statusCode;
        const timestamp = new Date().toISOString();
        const responseTime = Date.now() - startTime;

        // Check if response is paginated using type guard
        const isPaginatedResponse = (response: any): 
          response is PaginatedResponse<T> => {
          return response?.meta?.hasOwnProperty('page') && 
                 Array.isArray(response?.data);
        };

        // Construct standardized response
        const transformedResponse: Response<T> = {
          data: isPaginatedResponse(data) ? data.data : data,
          timestamp,
          statusCode,
          meta: isPaginatedResponse(data) ? {
            ...data.meta,
            responseTime
          } : {
            responseTime
          }
        };

        // Log response metrics
        this.logger.debug(
          `Response transformed [${statusCode}] - ${responseTime}ms`,
          {
            path: context.getArgByIndex(0).url,
            method: context.getArgByIndex(0).method,
            responseTime,
            timestamp
          }
        );

        return transformedResponse;
      })
    );
  }
}