/**
 * @fileoverview AI-driven audio enhancement processor implementation
 * Provides real-time audio quality improvement with comprehensive monitoring
 * @version 1.0.0
 */

import { Injectable, Logger } from '@nestjs/common'; // v10.0.0
import { AudioConfig, ProcessingQuality } from '../interfaces/audio-config.interface';
import { AudioEnhancementModel } from '../../ai/models/audio-enhancement.model';

// Processing constants
const MAX_PROCESSING_LATENCY_MS = 10;
const MIN_ENHANCEMENT_STRENGTH = 0.0;
const MAX_ENHANCEMENT_STRENGTH = 1.0;
const BUFFER_POOL_SIZE = 32;
const MONITORING_INTERVAL_MS = 100;
const ERROR_RETRY_ATTEMPTS = 3;

/**
 * Statistics for monitoring enhancement processing performance
 */
interface ProcessingStats {
    averageLatency: number;
    peakLatency: number;
    qualityImprovement: number;
    cpuUsage: number;
    memoryUsage: number;
    bufferUtilization: number;
    errorRate: number;
    enhancementStrength: number;
    isHealthy: boolean;
}

/**
 * Audio buffer pool for memory optimization
 */
class AudioBufferPool {
    private readonly buffers: Float32Array[] = [];
    private readonly size: number;

    constructor(size: number, bufferLength: number) {
        this.size = size;
        for (let i = 0; i < size; i++) {
            this.buffers.push(new Float32Array(bufferLength));
        }
    }

    acquire(): Float32Array | null {
        return this.buffers.pop() || null;
    }

    release(buffer: Float32Array): void {
        if (this.buffers.length < this.size) {
            this.buffers.push(buffer);
        }
    }

    get utilization(): number {
        return 1 - (this.buffers.length / this.size);
    }
}

/**
 * Performance monitoring for enhancement processing
 */
class PerformanceMonitor {
    private readonly latencyHistory: number[] = [];
    private readonly qualityHistory: number[] = [];
    private errorCount: number = 0;
    private startTime: number = 0;

    startProcessing(): void {
        this.startTime = performance.now();
    }

    recordLatency(): number {
        const latency = performance.now() - this.startTime;
        this.latencyHistory.push(latency);
        if (this.latencyHistory.length > 100) {
            this.latencyHistory.shift();
        }
        return latency;
    }

    recordQuality(improvement: number): void {
        this.qualityHistory.push(improvement);
        if (this.qualityHistory.length > 100) {
            this.qualityHistory.shift();
        }
    }

    recordError(): void {
        this.errorCount++;
    }

    getStats(): Partial<ProcessingStats> {
        return {
            averageLatency: this.getAverageLatency(),
            peakLatency: Math.max(...this.latencyHistory),
            qualityImprovement: this.getAverageQuality(),
            errorRate: this.errorCount / this.latencyHistory.length,
            isHealthy: this.isHealthy()
        };
    }

    private getAverageLatency(): number {
        return this.latencyHistory.reduce((a, b) => a + b, 0) / this.latencyHistory.length;
    }

    private getAverageQuality(): number {
        return this.qualityHistory.reduce((a, b) => a + b, 0) / this.qualityHistory.length;
    }

    private isHealthy(): boolean {
        return this.getAverageLatency() < MAX_PROCESSING_LATENCY_MS && 
               this.errorCount / this.latencyHistory.length < 0.01;
    }
}

@Injectable()
export class EnhancementProcessor {
    private readonly logger = new Logger(EnhancementProcessor.name);
    private readonly performanceMonitor = new PerformanceMonitor();
    private readonly bufferPool: AudioBufferPool;
    private isInitialized: boolean = false;
    private processingStats: ProcessingStats;

    constructor(
        private readonly enhancementModel: AudioEnhancementModel,
        private config: AudioConfig
    ) {
        this.validateConfig(config);
        this.bufferPool = new AudioBufferPool(BUFFER_POOL_SIZE, config.bufferSize);
        this.initializeProcessor();
    }

    /**
     * Process audio buffer through AI enhancement
     * @param inputBuffer Input audio buffer
     * @returns Enhanced audio buffer
     */
    async processBuffer(inputBuffer: Float32Array): Promise<Float32Array> {
        if (!this.isInitialized) {
            throw new Error('Enhancement processor not initialized');
        }

        this.performanceMonitor.startProcessing();

        try {
            // Acquire buffer from pool
            const processingBuffer = this.bufferPool.acquire();
            if (!processingBuffer) {
                throw new Error('Buffer pool exhausted');
            }

            // Copy input for processing
            inputBuffer.copyTo(processingBuffer);

            // Apply AI enhancement
            const enhancedBuffer = await this.enhancementModel.enhance(processingBuffer);

            // Update monitoring stats
            const latency = this.performanceMonitor.recordLatency();
            const quality = await this.calculateQualityImprovement(inputBuffer, enhancedBuffer);
            this.performanceMonitor.recordQuality(quality);

            // Update processing stats
            this.updateProcessingStats();

            // Release buffer back to pool
            this.bufferPool.release(processingBuffer);

            return enhancedBuffer;
        } catch (error) {
            this.handleProcessingError(error);
            return inputBuffer; // Fallback to original audio
        }
    }

    /**
     * Update processor configuration
     * @param newConfig Updated audio configuration
     */
    async updateConfig(newConfig: AudioConfig): Promise<void> {
        this.validateConfig(newConfig);

        try {
            // Check if reinitialization is needed
            const requiresReInit = this.requiresReinitialization(newConfig);

            // Update configuration
            this.config = newConfig;

            if (requiresReInit) {
                await this.initializeProcessor();
            }

            this.logger.log(`Configuration updated: ${JSON.stringify(newConfig)}`);
        } catch (error) {
            this.logger.error(`Configuration update failed: ${error.message}`);
            throw error;
        }
    }

    /**
     * Get current processing statistics
     * @returns Processing statistics and health metrics
     */
    getProcessingStats(): ProcessingStats {
        return {
            ...this.processingStats,
            ...this.performanceMonitor.getStats(),
            bufferUtilization: this.bufferPool.utilization,
            enhancementStrength: this.config.enhancementStrength,
            cpuUsage: process.cpuUsage().user / 1000000,
            memoryUsage: process.memoryUsage().heapUsed / 1024 / 1024
        };
    }

    private async initializeProcessor(): Promise<void> {
        try {
            this.isInitialized = false;

            // Initialize processing statistics
            this.processingStats = {
                averageLatency: 0,
                peakLatency: 0,
                qualityImprovement: 0,
                cpuUsage: 0,
                memoryUsage: 0,
                bufferUtilization: 0,
                errorRate: 0,
                enhancementStrength: this.config.enhancementStrength,
                isHealthy: true
            };

            // Initialize enhancement model
            await this.enhancementModel.loadModel({
                modelId: 'audio-enhancement-v1',
                version: '1.0.0',
                type: 'AUDIO_ENHANCEMENT',
                accelerator: this.determineAccelerator(),
                parameters: {
                    sampleRate: this.config.sampleRate,
                    frameSize: this.config.bufferSize,
                    channels: 2,
                    enhancementLevel: this.config.enhancementStrength * 100,
                    latencyTarget: MAX_PROCESSING_LATENCY_MS,
                    bufferStrategy: 'adaptive',
                    processingPriority: this.mapQualityToProcessingPriority()
                }
            });

            this.isInitialized = true;
            this.logger.log('Enhancement processor initialized successfully');
        } catch (error) {
            this.logger.error(`Initialization failed: ${error.message}`);
            throw error;
        }
    }

    private validateConfig(config: AudioConfig): void {
        if (!config.sampleRate || config.sampleRate < 44100) {
            throw new Error('Invalid sample rate');
        }
        if (!config.bufferSize || config.bufferSize < 64) {
            throw new Error('Invalid buffer size');
        }
        if (config.enhancementStrength < MIN_ENHANCEMENT_STRENGTH || 
            config.enhancementStrength > MAX_ENHANCEMENT_STRENGTH) {
            throw new Error('Invalid enhancement strength');
        }
    }

    private requiresReinitialization(newConfig: AudioConfig): boolean {
        return newConfig.sampleRate !== this.config.sampleRate ||
               newConfig.bufferSize !== this.config.bufferSize ||
               newConfig.processingQuality !== this.config.processingQuality;
    }

    private determineAccelerator(): string {
        // Determine best accelerator based on processing quality
        switch (this.config.processingQuality) {
            case ProcessingQuality.Maximum:
                return 'GPU';
            case ProcessingQuality.Balanced:
                return 'CPU';
            case ProcessingQuality.PowerSaver:
                return 'CPU';
            default:
                return 'CPU';
        }
    }

    private mapQualityToProcessingPriority(): string {
        switch (this.config.processingQuality) {
            case ProcessingQuality.Maximum:
                return 'quality';
            case ProcessingQuality.Balanced:
                return 'balanced';
            case ProcessingQuality.PowerSaver:
                return 'realtime';
            default:
                return 'balanced';
        }
    }

    private async calculateQualityImprovement(
        original: Float32Array,
        enhanced: Float32Array
    ): Promise<number> {
        // Calculate signal-to-noise ratio improvement
        const originalRMS = Math.sqrt(original.reduce((acc, val) => acc + val * val, 0) / original.length);
        const enhancedRMS = Math.sqrt(enhanced.reduce((acc, val) => acc + val * val, 0) / enhanced.length);
        return (enhancedRMS - originalRMS) / originalRMS;
    }

    private updateProcessingStats(): void {
        const monitorStats = this.performanceMonitor.getStats();
        this.processingStats = {
            ...this.processingStats,
            ...monitorStats
        };

        // Log warnings if performance degrades
        if (monitorStats.averageLatency > MAX_PROCESSING_LATENCY_MS) {
            this.logger.warn(`High latency detected: ${monitorStats.averageLatency.toFixed(2)}ms`);
        }
        if (!monitorStats.isHealthy) {
            this.logger.warn('Enhancement processor health check failed');
        }
    }

    private handleProcessingError(error: Error): void {
        this.performanceMonitor.recordError();
        this.logger.error(`Processing error: ${error.message}`);
        
        // Update health status
        this.processingStats.isHealthy = false;
        
        // Attempt recovery if needed
        if (this.processingStats.errorRate > 0.1) {
            this.logger.warn('High error rate detected, scheduling reinitialization');
            setTimeout(() => this.initializeProcessor(), 1000);
        }
    }
}