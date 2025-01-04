import { PipeTransform, Injectable, ArgumentMetadata, BadRequestException } from '@nestjs/common'; // ^10.0.0
import { validate } from 'class-validator'; // ^0.14.0
import { plainToClass } from 'class-transformer'; // ^0.5.1
import { HttpExceptionFilter } from '../filters/http-exception.filter';

@Injectable()
export class ValidationPipe implements PipeTransform<any> {
  private readonly isDebugMode: boolean;
  private readonly validationOptions: any;
  private readonly validationCache: Map<Function, boolean>;

  constructor() {
    // Initialize validation configuration
    this.isDebugMode = process.env.NODE_ENV === 'development';
    this.validationCache = new Map();
    
    // Configure validation options with security controls
    this.validationOptions = {
      whitelist: true, // Strip unknown properties
      forbidNonWhitelisted: true, // Throw on unknown properties
      forbidUnknownValues: true, // Prevent unknown nested objects
      validationError: {
        target: false, // Don't expose request object in errors
        value: false // Don't expose invalid values in errors
      },
      stopAtFirstError: false, // Collect all validation errors
      validationNestedObjects: true, // Validate nested objects
      skipMissingProperties: false, // Require all properties
      skipNullProperties: false, // Validate null properties
      skipUndefinedProperties: false, // Validate undefined properties
      enableDebugMessages: this.isDebugMode,
      dismissDefaultMessages: false, // Use custom messages when provided
      validateCustomDecorators: true // Enable custom validation decorators
    };
  }

  async transform(value: any, metadata: ArgumentMetadata): Promise<any> {
    const { metatype } = metadata;

    // Skip validation for primitives
    if (!metatype || !this.toValidate(metatype)) {
      return value;
    }

    try {
      // Transform plain object to class instance with sanitization
      const object = plainToClass(metatype, value, {
        enableImplicitConversion: true,
        excludeExtraneousValues: true,
        exposeDefaultValues: true,
        exposeUnsetFields: false,
        groups: metadata.data?.groups
      });

      // Validate transformed object against security rules
      const errors = await validate(object, this.validationOptions);

      if (errors.length > 0) {
        await this.handleValidationError(errors);
      }

      return object;
    } catch (error) {
      // Handle transformation errors
      throw new BadRequestException({
        message: 'Validation failed - transformation error',
        code: 'VALIDATION_TRANSFORM_ERROR',
        details: this.isDebugMode ? error.message : undefined
      });
    }
  }

  private toValidate(metatype: Function): boolean {
    // Check validation cache for performance
    if (this.validationCache.has(metatype)) {
      return this.validationCache.get(metatype);
    }

    // Determine if metatype needs validation
    const types: Function[] = [String, Boolean, Number, Array, Object];
    const shouldValidate = !types.includes(metatype);

    // Cache validation requirement
    this.validationCache.set(metatype, shouldValidate);
    return shouldValidate;
  }

  private async handleValidationError(errors: any[]): Promise<void> {
    // Format validation errors with security context
    const formattedErrors = errors.map(error => {
      const constraints = error.constraints || {};
      const messages = Object.values(constraints);

      return {
        field: error.property,
        messages: messages,
        children: error.children?.length ? this.formatChildErrors(error.children) : undefined
      };
    });

    // Throw formatted exception using HttpExceptionFilter
    throw new BadRequestException({
      message: 'Validation failed',
      code: 'VALIDATION_ERROR',
      errors: formattedErrors,
      timestamp: new Date().toISOString(),
      path: 'validation.pipe',
      type: 'ValidationError'
    });
  }

  private formatChildErrors(children: any[]): any[] {
    return children.map(child => ({
      field: child.property,
      messages: Object.values(child.constraints || {}),
      children: child.children?.length ? this.formatChildErrors(child.children) : undefined
    }));
  }
}