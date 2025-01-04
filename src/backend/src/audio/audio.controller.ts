/**
 * TALD UNIA Audio System - Audio Processing Controller
 * Version: 1.0.0
 * 
 * Implements high-performance audio processing endpoints with comprehensive
 * quality monitoring and hardware-aware validation.
 */

import { 
    Controller, Post, Body, Get, Put, UseGuards, 
    UsePipes, ValidationPipe, UseInterceptors, Logger,
    HttpException, HttpStatus
} from '@nestjs/common'; // v10.0.0
import { 
    ApiTags, ApiOperation, ApiBody, ApiResponse, 
    ApiSecurity 
} from '@nestjs/swagger'; // v7.0.0
import { RateLimit } from '@nestjs/throttler'; // v5.0.0

import { AudioService } from './audio.service';
import { ProcessAudioDto } from './dtos/process-audio.dto';
import { AudioMetricsInterceptor } from '../interceptors/audio-metrics.interceptor';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { 
    AudioConfig, ProcessingQuality, 
    MIN_LATENCY_MS, MAX_LATENCY_MS, THD_TARGET 
} from './interfaces/audio-config.interface';

// System constants
const RATE_LIMIT_TTL = 60;
const RATE_LIMIT_MAX = 1000;
const QUALITY_CHECK_INTERVAL_MS = 100;

@Controller('audio')
@ApiTags('audio')
@UseGuards(JwtAuthGuard)
@UsePipes(new ValidationPipe({ transform: true }))
@UseInterceptors(AudioMetricsInterceptor)
export class AudioController {
    private readonly logger = new Logger(AudioController.name);

    constructor(private readonly audioService: AudioService) {}

    /**
     * Process audio buffer with quality monitoring and hardware validation
     */
    @Post('process')
    @ApiOperation({ 
        summary: 'Process audio with AI enhancement and spatial processing',
        description: 'Processes audio buffer with quality monitoring and hardware validation'
    })
    @ApiBody({ type: ProcessAudioDto })
    @ApiResponse({ 
        status: 200, 
        description: 'Audio processed successfully with quality metrics'
    })
    @ApiSecurity('jwt')
    @RateLimit({ ttl: RATE_LIMIT_TTL, limit: RATE_LIMIT_MAX })
    async processAudio(@Body() processAudioDto: ProcessAudioDto): Promise<{
        processedAudio: Buffer;
        qualityMetrics: any;
        processingStats: any;
    }> {
        try {
            // Validate hardware compatibility
            if (!processAudioDto.validateAudioBuffer(processAudioDto.audioData)) {
                throw new HttpException(
                    'Invalid audio buffer format',
                    HttpStatus.BAD_REQUEST
                );
            }

            const startTime = performance.now();

            // Convert buffer to Float32Array for processing
            const inputArray = this.convertBufferToFloat32Array(
                processAudioDto.audioData,
                processAudioDto.bitDepth
            );

            // Process audio
            const processedArray = await this.audioService.processAudio(inputArray);

            // Get quality metrics
            const qualityMetrics = await this.audioService.getQualityMetrics();
            
            // Validate processing quality
            this.validateProcessingQuality(qualityMetrics, startTime);

            // Convert back to buffer
            const processedBuffer = this.convertFloat32ArrayToBuffer(
                processedArray,
                processAudioDto.bitDepth
            );

            return {
                processedAudio: processedBuffer,
                qualityMetrics,
                processingStats: this.audioService.getProcessingStats()
            };
        } catch (error) {
            this.logger.error(`Audio processing failed: ${error.message}`);
            throw new HttpException(
                error.message,
                HttpStatus.INTERNAL_SERVER_ERROR
            );
        }
    }

    /**
     * Update audio processing configuration with hardware validation
     */
    @Put('config')
    @ApiOperation({ 
        summary: 'Update audio processing configuration',
        description: 'Updates audio configuration with hardware validation'
    })
    @ApiBody({ type: AudioConfig })
    @ApiResponse({ 
        status: 200, 
        description: 'Configuration updated successfully'
    })
    @ApiSecurity('jwt')
    async updateConfig(@Body() config: AudioConfig): Promise<{
        status: string;
        validation: any;
    }> {
        try {
            // Validate hardware compatibility
            this.validateHardwareConfig(config);

            // Update service configuration
            await this.audioService.updateConfig(config);

            return {
                status: 'Configuration updated successfully',
                validation: await this.audioService.getQualityMetrics()
            };
        } catch (error) {
            this.logger.error(`Configuration update failed: ${error.message}`);
            throw new HttpException(
                error.message,
                HttpStatus.BAD_REQUEST
            );
        }
    }

    /**
     * Get comprehensive audio processing statistics
     */
    @Get('stats')
    @ApiOperation({ 
        summary: 'Get audio processing statistics',
        description: 'Returns comprehensive processing and quality metrics'
    })
    @ApiResponse({ 
        status: 200, 
        description: 'Statistics retrieved successfully'
    })
    @ApiSecurity('jwt')
    async getProcessingStats(): Promise<{
        quality: any;
        performance: any;
        hardware: any;
    }> {
        try {
            const [quality, performance] = await Promise.all([
                this.audioService.getQualityMetrics(),
                this.audioService.getProcessingStats()
            ]);

            return {
                quality,
                performance,
                hardware: await this.getHardwareStatus()
            };
        } catch (error) {
            this.logger.error(`Failed to retrieve stats: ${error.message}`);
            throw new HttpException(
                error.message,
                HttpStatus.INTERNAL_SERVER_ERROR
            );
        }
    }

    /**
     * Private helper methods
     */
    private convertBufferToFloat32Array(
        buffer: Buffer,
        bitDepth: number
    ): Float32Array {
        const bytesPerSample = bitDepth / 8;
        const samples = new Float32Array(buffer.length / bytesPerSample);
        const maxValue = Math.pow(2, bitDepth - 1);

        for (let i = 0; i < samples.length; i++) {
            const sample = buffer.readIntLE(i * bytesPerSample, bytesPerSample);
            samples[i] = sample / maxValue;
        }

        return samples;
    }

    private convertFloat32ArrayToBuffer(
        array: Float32Array,
        bitDepth: number
    ): Buffer {
        const bytesPerSample = bitDepth / 8;
        const buffer = Buffer.alloc(array.length * bytesPerSample);
        const maxValue = Math.pow(2, bitDepth - 1);

        for (let i = 0; i < array.length; i++) {
            const sample = Math.max(-1, Math.min(1, array[i])) * maxValue;
            buffer.writeIntLE(Math.round(sample), i * bytesPerSample, bytesPerSample);
        }

        return buffer;
    }

    private validateProcessingQuality(
        metrics: any,
        startTime: number
    ): void {
        const processingTime = performance.now() - startTime;

        if (processingTime > MAX_LATENCY_MS) {
            this.logger.warn(`High latency detected: ${processingTime.toFixed(2)}ms`);
        }

        if (metrics.thd > THD_TARGET) {
            this.logger.warn(`THD exceeds target: ${metrics.thd.toFixed(6)}`);
        }
    }

    private validateHardwareConfig(config: AudioConfig): void {
        if (config.sampleRate > 192000) {
            throw new Error('Sample rate exceeds hardware capabilities');
        }

        if (config.bitDepth > 32) {
            throw new Error('Bit depth exceeds hardware capabilities');
        }

        if (config.bufferSize < 64 || config.bufferSize > 8192) {
            throw new Error('Invalid buffer size for hardware');
        }
    }

    private async getHardwareStatus(): Promise<any> {
        // Implement hardware status monitoring
        return {
            temperature: await this.getHardwareTemperature(),
            bufferUtilization: await this.getBufferUtilization(),
            clockStatus: await this.getClockStatus()
        };
    }

    private async getHardwareTemperature(): Promise<number> {
        // Implement hardware temperature monitoring
        return 0;
    }

    private async getBufferUtilization(): Promise<number> {
        // Implement buffer utilization monitoring
        return 0;
    }

    private async getClockStatus(): Promise<string> {
        // Implement clock status monitoring
        return 'locked';
    }
}