/**
 * TALD UNIA Audio Processing Queue
 * Version: 1.0.0
 * 
 * Implements high-performance audio processing queue with comprehensive monitoring,
 * quality validation, and adaptive resource optimization.
 */

import { Process, Processor } from 'bull'; // v4.10.0
import { Injectable, Logger } from '@nestjs/common'; // v10.0.0
import { InjectQueue } from '@nestjs/bull'; // v0.6.0
import { AudioService } from '../../audio/audio.service';
import { AudioConfig } from '../../audio/interfaces/audio-config.interface';

// Queue configuration constants
const QUEUE_NAME = 'audio-processing';
const MAX_RETRIES = 3;
const RETRY_DELAY = 1000;
const MAX_PROCESSING_LATENCY = 10; // ms
const CONCURRENT_JOBS = 2;
const QUALITY_THRESHOLD = 0.0005; // THD+N threshold
const BUFFER_POOL_SIZE = 32;
const GRACEFUL_SHUTDOWN_TIMEOUT = 5000;
const METRICS_UPDATE_INTERVAL = 100;

/**
 * Audio processing job data interface
 */
interface AudioJobData {
    audioBuffer: Float32Array;
    config: AudioConfig;
    timestamp: number;
    priority: number;
}

/**
 * Processing result with quality metrics
 */
interface ProcessedAudioResult {
    processedBuffer: Float32Array;
    quality: {
        thd: number;
        latency: number;
        snr: number;
        enhancementQuality: number;
    };
    metrics: {
        processingTime: number;
        bufferUtilization: number;
        queueLength: number;
    };
}

/**
 * Quality monitoring system
 */
class QualityMonitor {
    private readonly metrics: Map<string, number> = new Map();
    private readonly thresholds: Map<string, number> = new Map();
    private readonly logger = new Logger('QualityMonitor');

    constructor() {
        this.initializeMetrics();
        this.setThresholds();
    }

    updateMetric(name: string, value: number): void {
        this.metrics.set(name, value);
        this.checkThreshold(name);
    }

    getMetrics(): Map<string, number> {
        return new Map(this.metrics);
    }

    private initializeMetrics(): void {
        this.metrics.set('thd', 0);
        this.metrics.set('latency', 0);
        this.metrics.set('snr', 0);
        this.metrics.set('enhancementQuality', 0);
    }

    private setThresholds(): void {
        this.thresholds.set('thd', QUALITY_THRESHOLD);
        this.thresholds.set('latency', MAX_PROCESSING_LATENCY);
        this.thresholds.set('snr', 120);
    }

    private checkThreshold(metric: string): void {
        const value = this.metrics.get(metric);
        const threshold = this.thresholds.get(metric);
        if (value && threshold && value > threshold) {
            this.logger.warn(`Quality threshold exceeded for ${metric}: ${value}`);
        }
    }
}

/**
 * Audio buffer pool for optimized memory management
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
 * Metrics collector for performance monitoring
 */
class MetricsCollector {
    private readonly metrics: Map<string, number[]> = new Map();
    private readonly logger = new Logger('MetricsCollector');

    constructor() {
        this.initializeMetrics();
        this.startPeriodicUpdate();
    }

    recordMetric(name: string, value: number): void {
        const values = this.metrics.get(name) || [];
        values.push(value);
        if (values.length > 100) values.shift();
        this.metrics.set(name, values);
    }

    getAverageMetric(name: string): number {
        const values = this.metrics.get(name) || [];
        return values.reduce((a, b) => a + b, 0) / values.length || 0;
    }

    private initializeMetrics(): void {
        this.metrics.set('processingTime', []);
        this.metrics.set('queueLength', []);
        this.metrics.set('bufferUtilization', []);
        this.metrics.set('qualityScore', []);
    }

    private startPeriodicUpdate(): void {
        setInterval(() => {
            this.logMetrics();
        }, METRICS_UPDATE_INTERVAL);
    }

    private logMetrics(): void {
        const averages = Array.from(this.metrics.entries()).reduce((acc, [key, _]) => {
            acc[key] = this.getAverageMetric(key);
            return acc;
        }, {} as Record<string, number>);

        this.logger.debug(`Performance metrics: ${JSON.stringify(averages)}`);
    }
}

@Injectable()
@Processor(QUEUE_NAME)
export class AudioProcessingQueue {
    private readonly logger = new Logger(AudioProcessingQueue.name);
    private readonly qualityMonitor: QualityMonitor;
    private readonly metrics: MetricsCollector;
    private readonly bufferPool: AudioBufferPool;

    constructor(
        private readonly audioService: AudioService,
        metrics: MetricsCollector,
        qualityMonitor: QualityMonitor
    ) {
        this.metrics = metrics;
        this.qualityMonitor = qualityMonitor;
        this.bufferPool = new AudioBufferPool(BUFFER_POOL_SIZE, 2048);
        this.initializeQueue();
    }

    @Process()
    async process(job: Job<AudioJobData>): Promise<ProcessedAudioResult> {
        const startTime = performance.now();

        try {
            // Validate job data
            this.validateJobData(job.data);

            // Acquire buffer from pool
            const processingBuffer = this.bufferPool.acquire();
            if (!processingBuffer) {
                throw new Error('Buffer pool exhausted');
            }

            // Process audio
            const processedBuffer = await this.audioService.processAudio(job.data.audioBuffer);
            const processingStats = this.audioService.getProcessingStats();

            // Validate quality
            await this.validateQuality(processedBuffer, processingStats);

            // Update metrics
            this.updateMetrics(startTime, job);

            // Release buffer
            this.bufferPool.release(processingBuffer);

            return {
                processedBuffer,
                quality: {
                    thd: processingStats.thdLevel,
                    latency: processingStats.processingLatency,
                    snr: processingStats.snr || 0,
                    enhancementQuality: processingStats.enhancementQuality
                },
                metrics: {
                    processingTime: performance.now() - startTime,
                    bufferUtilization: this.bufferPool.utilization,
                    queueLength: await job.queue.count()
                }
            };
        } catch (error) {
            await this.handleProcessingError(error, job);
            throw error;
        }
    }

    private async validateQuality(
        buffer: Float32Array,
        stats: any
    ): Promise<void> {
        // Update quality metrics
        this.qualityMonitor.updateMetric('thd', stats.thdLevel);
        this.qualityMonitor.updateMetric('latency', stats.processingLatency);
        this.qualityMonitor.updateMetric('enhancementQuality', stats.enhancementQuality);

        // Validate against thresholds
        if (stats.thdLevel > QUALITY_THRESHOLD) {
            this.logger.warn(`THD+N threshold exceeded: ${stats.thdLevel}`);
        }

        if (stats.processingLatency > MAX_PROCESSING_LATENCY) {
            this.logger.warn(`Latency threshold exceeded: ${stats.processingLatency}ms`);
        }
    }

    private validateJobData(data: AudioJobData): void {
        if (!data.audioBuffer || !(data.audioBuffer instanceof Float32Array)) {
            throw new Error('Invalid audio buffer');
        }

        if (!data.config || !data.config.sampleRate) {
            throw new Error('Invalid audio configuration');
        }
    }

    private async handleProcessingError(error: Error, job: Job<AudioJobData>): Promise<void> {
        this.logger.error(`Processing error: ${error.message}`);

        if (job.attemptsMade < MAX_RETRIES) {
            await job.retry({
                delay: RETRY_DELAY * Math.pow(2, job.attemptsMade)
            });
        } else {
            this.logger.error(`Job failed after ${MAX_RETRIES} retries`);
        }
    }

    private updateMetrics(startTime: number, job: Job<AudioJobData>): void {
        const processingTime = performance.now() - startTime;
        this.metrics.recordMetric('processingTime', processingTime);
        this.metrics.recordMetric('queueLength', job.queue.count());
        this.metrics.recordMetric('bufferUtilization', this.bufferPool.utilization);
    }

    private initializeQueue(): void {
        this.logger.log(`Initializing audio processing queue with ${CONCURRENT_JOBS} concurrent jobs`);
        
        process.on('SIGTERM', async () => {
            await this.gracefulShutdown();
        });
    }

    private async gracefulShutdown(): Promise<void> {
        this.logger.log('Initiating graceful shutdown...');

        try {
            // Wait for active jobs to complete
            await new Promise(resolve => setTimeout(resolve, GRACEFUL_SHUTDOWN_TIMEOUT));
            
            // Clean up resources
            this.metrics.recordMetric('shutdownTime', performance.now());
            
            this.logger.log('Shutdown completed successfully');
        } catch (error) {
            this.logger.error(`Shutdown error: ${error.message}`);
        }
    }
}