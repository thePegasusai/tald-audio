import { Controller, Post, Body, Get, Put, Param, UseGuards, UseInterceptors } from '@nestjs/common';
import { ApiTags, ApiOperation, ApiResponse, ApiBody, ApiParam } from '@nestjs/swagger';
import { RateLimit } from '@nestjs/throttler';
import { PerformanceMonitor } from '@nestjs/core';
import { SpatialService } from './spatial.service';
import { HRTFData, HRTFPosition } from './interfaces/hrtf.interface';
import { ApiResponseDecorator } from '../common/decorators/api-response.decorator';

/**
 * TALD UNIA Audio System - Spatial Audio Controller
 * Implements high-performance spatial audio processing endpoints with <10ms latency
 * @version 1.0.0
 */
@Controller('spatial')
@ApiTags('spatial')
@UseGuards(AuthGuard)
@UseInterceptors(LoggingInterceptor, PerformanceInterceptor)
@RateLimit({ ttl: 60, limit: 100 })
export class SpatialController {
    constructor(
        private readonly spatialService: SpatialService,
        private readonly performanceMonitor: PerformanceMonitor
    ) {}

    /**
     * Process audio buffer with spatial effects and HRTF rendering
     */
    @Post('process')
    @ApiOperation({ summary: 'Process audio with spatial effects' })
    @ApiBody({ 
        type: Object,
        schema: {
            properties: {
                audioBuffer: {
                    type: 'array',
                    items: { type: 'number' },
                    description: 'Audio samples as Float32Array'
                },
                position: {
                    type: 'object',
                    properties: {
                        azimuth: { type: 'number', minimum: -180, maximum: 180 },
                        elevation: { type: 'number', minimum: -90, maximum: 90 },
                        distance: { type: 'number', minimum: 0 }
                    }
                }
            }
        }
    })
    @ApiResponseDecorator({
        type: Float32Array,
        status: 200,
        description: 'Processed audio buffer with spatial effects'
    })
    async processSpatialAudio(
        @Body('audioBuffer') audioBuffer: Float32Array,
        @Body('position') position: HRTFPosition
    ): Promise<Float32Array> {
        const startTime = performance.now();

        try {
            // Validate input parameters
            if (!audioBuffer || audioBuffer.length === 0) {
                throw new Error('Invalid audio buffer');
            }

            // Process audio with performance monitoring
            const processedBuffer = await this.performanceMonitor.trackOperation(
                'spatial-processing',
                () => this.spatialService.processSpatialAudio(audioBuffer, position)
            );

            // Verify processing latency
            const latency = performance.now() - startTime;
            if (latency > 10) { // 10ms latency target
                console.warn(`Processing latency exceeded target: ${latency}ms`);
            }

            return processedBuffer;
        } catch (error) {
            console.error('Spatial processing error:', error);
            throw error;
        }
    }

    /**
     * Update spatial position with real-time tracking
     */
    @Put('position')
    @ApiOperation({ summary: 'Update spatial position' })
    @ApiBody({ type: HRTFPosition })
    @ApiResponseDecorator({
        type: Boolean,
        status: 200,
        description: 'Position update status'
    })
    async updatePosition(@Body() position: HRTFPosition): Promise<boolean> {
        try {
            await this.spatialService.updateSpatialPosition(position);
            return true;
        } catch (error) {
            console.error('Position update error:', error);
            throw error;
        }
    }

    /**
     * Load HRTF dataset for spatial processing
     */
    @Put('hrtf/:datasetId')
    @ApiOperation({ summary: 'Load HRTF dataset' })
    @ApiParam({ name: 'datasetId', type: 'string' })
    @ApiResponseDecorator({
        type: Boolean,
        status: 200,
        description: 'Dataset load status'
    })
    async loadHRTFDataset(@Param('datasetId') datasetId: string): Promise<boolean> {
        try {
            return await this.spatialService.loadHRTFDataset(datasetId);
        } catch (error) {
            console.error('HRTF dataset load error:', error);
            throw error;
        }
    }

    /**
     * Get spatial processing metrics
     */
    @Get('metrics')
    @ApiOperation({ summary: 'Get processing metrics' })
    @ApiResponseDecorator({
        type: Object,
        status: 200,
        description: 'Spatial processing metrics'
    })
    async getMetrics(): Promise<{
        processingTime: number;
        latency: number;
        thdPlusNoise: number;
    }> {
        try {
            return await this.spatialService.getProcessingMetrics();
        } catch (error) {
            console.error('Metrics retrieval error:', error);
            throw error;
        }
    }
}