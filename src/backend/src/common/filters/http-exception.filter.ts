import { ExceptionFilter, Catch, ArgumentsHost, HttpException } from '@nestjs/common';
import { Request, Response } from 'express';
import { LoggerMiddleware } from '../middlewares/logger.middleware';

@Catch(HttpException)
export class HttpExceptionFilter implements ExceptionFilter {
  private readonly logger: any;

  constructor(private readonly loggerService: LoggerMiddleware) {
    this.logger = loggerService;
  }

  catch(exception: HttpException, host: ArgumentsHost): void {
    const ctx = host.switchToHttp();
    const request = ctx.getRequest<Request>();
    const response = ctx.getResponse<Response>();

    // Start performance tracking
    const startTime = process.hrtime();
    const startCpuUsage = process.cpuUsage();

    // Get request context from response locals
    const requestContext = response.locals.requestContext || {};

    // Format error response
    const errorResponse = this.formatError(exception, request);

    // Log error with enhanced context
    this.logger.error('HTTP Exception occurred', {
      ...errorResponse,
      ...requestContext,
      stack: process.env.NODE_ENV === 'development' ? exception.stack : undefined,
      performanceMetrics: {
        duration: process.hrtime(startTime),
        cpuUsage: process.cpuUsage(startCpuUsage)
      }
    });

    // Send error response
    response
      .status(errorResponse.statusCode)
      .json(errorResponse);
  }

  private formatError(exception: HttpException, request: Request): any {
    const status = exception.getStatus();
    const response = exception.getResponse();

    // Sanitize error message for security
    const message = typeof response === 'string' 
      ? this.sanitizeErrorMessage(response)
      : this.sanitizeErrorMessage(response['message'] || 'Internal server error');

    // Build standardized error response
    const errorResponse = {
      statusCode: status,
      timestamp: new Date().toISOString(),
      path: request.url,
      method: request.method,
      message: Array.isArray(message) ? message : [message],
      code: response['code'] || 'HTTP_ERROR',
      correlationId: request.headers['x-correlation-id'] || response['correlationId'],
      requestId: response.locals?.requestContext?.requestId
    };

    // Add stack trace in development only
    if (process.env.NODE_ENV === 'development') {
      errorResponse['stack'] = exception.stack;
    }

    return errorResponse;
  }

  private sanitizeErrorMessage(message: string | string[]): string[] {
    const sensitivePatterns = [
      /password/i,
      /token/i,
      /secret/i,
      /key/i,
      /authorization/i,
      /credential/i
    ];

    const sanitizeString = (str: string): string => {
      let sanitized = str;
      sensitivePatterns.forEach(pattern => {
        sanitized = sanitized.replace(new RegExp(`(${pattern.source}\\s*[=:])\\s*[^\\s,;]+`, 'gi'), '$1 [REDACTED]');
      });
      return sanitized;
    };

    if (Array.isArray(message)) {
      return message.map(sanitizeString);
    }
    return [sanitizeString(message)];
  }
}