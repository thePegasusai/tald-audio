import { Injectable, NestMiddleware } from '@nestjs/common';
import { Request, Response, NextFunction } from 'express';
import { Logger, createLogger, format, transports } from 'winston';
import { v4 as uuidv4 } from 'uuid';
import { configuration } from '../../config/configuration';

@Injectable()
export class LoggerMiddleware implements NestMiddleware {
  private readonly logger: Logger;
  private readonly config: Record<string, any>;
  private readonly performanceMetrics: Map<string, { startTime: number, cpuUsage: NodeJS.CpuUsage }>;

  constructor() {
    this.config = configuration();
    this.performanceMetrics = new Map();

    // Define custom log format
    const logFormat = format.combine(
      format.timestamp(),
      format.errors({ stack: true }),
      format.metadata(),
      process.env.NODE_ENV === 'production' ? format.json() : format.prettyPrint(),
      format.colorize({ all: process.env.NODE_ENV !== 'production' })
    );

    // Initialize Winston logger with transports
    this.logger = createLogger({
      level: process.env.LOG_LEVEL || this.config.monitoring.logLevel,
      format: logFormat,
      defaultMeta: {
        service: 'tald-unia-audio',
        environment: process.env.NODE_ENV
      },
      transports: [
        new transports.Console({
          format: format.combine(
            format.timestamp(),
            format.printf(({ timestamp, level, message, metadata }) => {
              return `[${timestamp}] ${level}: ${message} ${JSON.stringify(metadata)}`;
            })
          )
        })
      ]
    });

    // Add file transport for production environment
    if (process.env.NODE_ENV === 'production') {
      this.logger.add(new transports.File({
        filename: process.env.LOG_FILE_PATH || 'logs/tald-unia.log',
        maxsize: 10 * 1024 * 1024, // 10MB
        maxFiles: 5,
        tailable: true,
        format: format.combine(
          format.timestamp(),
          format.json()
        )
      }));
    }
  }

  use(req: Request, res: Response, next: NextFunction): void {
    const requestId = uuidv4();
    const startTime = process.hrtime();
    const startCpuUsage = process.cpuUsage();

    // Store metrics for performance tracking
    this.performanceMetrics.set(requestId, {
      startTime: Date.now(),
      cpuUsage: startCpuUsage
    });

    // Create request context
    const requestContext = {
      requestId,
      method: req.method,
      url: req.url,
      userAgent: req.get('user-agent'),
      ip: req.ip,
      correlationId: req.get('x-correlation-id') || requestId
    };

    // Log incoming request
    this.logger.info('Incoming request', {
      ...requestContext,
      query: this.sanitizeData(req.query),
      headers: this.sanitizeHeaders(req.headers)
    });

    // Intercept response
    res.on('finish', () => {
      const metrics = this.performanceMetrics.get(requestId);
      if (!metrics) return;

      const duration = process.hrtime(startTime);
      const cpuUsage = process.cpuUsage(metrics.cpuUsage);
      const durationMs = (duration[0] * 1e3 + duration[1] * 1e-6).toFixed(2);

      // Log response with performance metrics
      this.logger.info('Request completed', {
        ...requestContext,
        statusCode: res.statusCode,
        duration: `${durationMs}ms`,
        cpuUser: cpuUsage.user / 1000,
        cpuSystem: cpuUsage.system / 1000,
        contentLength: res.get('content-length'),
        responseTime: Date.now() - metrics.startTime
      });

      // Cleanup metrics
      this.performanceMetrics.delete(requestId);
    });

    // Error handling
    res.on('error', (error) => {
      this.error(error, {
        ...requestContext,
        stack: error.stack
      });
      this.performanceMetrics.delete(requestId);
    });

    // Add request context to response locals for downstream use
    res.locals.requestContext = requestContext;

    next();
  }

  error(error: Error, context: Record<string, any> = {}): void {
    this.logger.error(error.message, {
      ...context,
      stack: error.stack,
      timestamp: new Date().toISOString()
    });
  }

  info(message: string, context: Record<string, any> = {}): void {
    this.logger.info(message, {
      ...context,
      timestamp: new Date().toISOString()
    });
  }

  private sanitizeData(data: any): any {
    const sensitiveFields = ['password', 'token', 'secret', 'authorization'];
    
    if (typeof data !== 'object' || data === null) {
      return data;
    }

    return Object.entries(data).reduce((acc, [key, value]) => {
      if (sensitiveFields.includes(key.toLowerCase())) {
        acc[key] = '[REDACTED]';
      } else if (typeof value === 'object') {
        acc[key] = this.sanitizeData(value);
      } else {
        acc[key] = value;
      }
      return acc;
    }, {} as Record<string, any>);
  }

  private sanitizeHeaders(headers: Record<string, any>): Record<string, any> {
    const sensitiveHeaders = ['authorization', 'cookie', 'x-api-key'];
    return Object.entries(headers).reduce((acc, [key, value]) => {
      acc[key] = sensitiveHeaders.includes(key.toLowerCase()) ? '[REDACTED]' : value;
      return acc;
    }, {} as Record<string, any>);
  }
}