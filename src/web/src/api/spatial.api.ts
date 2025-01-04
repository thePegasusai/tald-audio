/**
 * TALD UNIA Spatial Audio Processing API Client
 * Version: 1.0.0
 * 
 * Enterprise-grade API client for real-time HRTF-based 3D audio processing
 * with comprehensive performance monitoring and error handling.
 */

import axios, { AxiosInstance, AxiosRequestConfig } from 'axios'; // v1.6.0
import {
    Position3D,
    SpatialAudioConfig,
    AudioProcessingError,
    AudioProcessingEvent,
    ReflectionModel,
    ProcessingQuality,
    MIN_LATENCY_MS,
    SPATIAL_PROCESSING_INTERVAL_MS,
    HRTF_UPDATE_INTERVAL_MS
} from '../types/audio.types';

/**
 * Performance metrics collector for spatial processing
 */
interface PerformanceMetrics {
    processingLatency: number;
    networkLatency: number;
    bufferUtilization: number;
    hrtfCacheHitRate: number;
    spatialUpdateRate: number;
}

/**
 * Processing options for spatial audio
 */
interface ProcessingOptions {
    quality: ProcessingQuality;
    enableHRTF: boolean;
    reflectionModel: ReflectionModel;
    maxLatency?: number;
    priority?: number;
}

/**
 * Result of processed spatial audio
 */
interface ProcessedAudioResult {
    buffer: Float32Array;
    metrics: PerformanceMetrics;
    timestamp: number;
}

/**
 * Configuration for the Spatial API Client
 */
interface SpatialApiClientConfig {
    baseUrl: string;
    timeout?: number;
    maxRetries?: number;
    enableMetrics?: boolean;
    hrtfCacheSize?: number;
}

/**
 * Enterprise-grade client for spatial audio processing with advanced monitoring
 */
export class SpatialApiClient {
    private readonly axiosInstance: AxiosInstance;
    private readonly metricsCollector: Map<string, PerformanceMetrics>;
    private readonly hrtfCache: Map<string, ArrayBuffer>;
    private readonly config: SpatialApiClientConfig;

    constructor(config: SpatialApiClientConfig) {
        this.config = {
            timeout: 5000,
            maxRetries: 3,
            enableMetrics: true,
            hrtfCacheSize: 100,
            ...config
        };

        this.axiosInstance = axios.create({
            baseURL: this.config.baseUrl,
            timeout: this.config.timeout,
            headers: {
                'Content-Type': 'application/octet-stream',
                'X-API-Version': '1.0.0'
            }
        });

        this.metricsCollector = new Map();
        this.hrtfCache = new Map();
        this.setupAxiosInterceptors();
    }

    /**
     * Process audio buffer with spatial effects and HRTF
     */
    public async processSpatialAudio(
        audioBuffer: Float32Array,
        position: Position3D,
        options: ProcessingOptions
    ): Promise<ProcessedAudioResult> {
        const startTime = performance.now();
        
        try {
            this.validateInputs(audioBuffer, position, options);
            const processingId = this.generateProcessingId();
            
            const payload = await this.prepareProcessingPayload(
                audioBuffer,
                position,
                options
            );

            const response = await this.executeWithRetry(
                () => this.axiosInstance.post('/spatial/process', payload),
                this.config.maxRetries
            );

            const processedBuffer = this.processResponse(response);
            const metrics = this.collectMetrics(processingId, startTime);

            return {
                buffer: processedBuffer,
                metrics,
                timestamp: Date.now()
            };
        } catch (error) {
            this.handleProcessingError(error);
            throw error;
        }
    }

    /**
     * Update spatial position with real-time validation
     */
    public async updateSpatialPosition(
        position: Position3D,
        config: SpatialAudioConfig
    ): Promise<void> {
        const startTime = performance.now();

        try {
            this.validatePosition(position);
            
            await this.axiosInstance.put('/spatial/position', {
                position,
                config,
                timestamp: Date.now()
            });

            this.updateMetrics('positionUpdate', {
                latency: performance.now() - startTime
            });
        } catch (error) {
            this.handleUpdateError(error);
            throw error;
        }
    }

    /**
     * Configure HRTF dataset with caching
     */
    public async configureHRTFDataset(
        profile: string,
        options?: { force?: boolean }
    ): Promise<void> {
        const cacheKey = this.generateHRTFCacheKey(profile);

        if (!options?.force && this.hrtfCache.has(cacheKey)) {
            return;
        }

        try {
            const response = await this.axiosInstance.get(
                `/spatial/hrtf/${profile}`,
                { responseType: 'arraybuffer' }
            );

            this.hrtfCache.set(cacheKey, response.data);
            this.maintainCacheSize();
        } catch (error) {
            this.handleHRTFError(error);
            throw error;
        }
    }

    /**
     * Retrieve current performance metrics
     */
    public getPerformanceMetrics(): PerformanceMetrics[] {
        return Array.from(this.metricsCollector.values());
    }

    private setupAxiosInterceptors(): void {
        this.axiosInstance.interceptors.request.use(
            (config) => {
                config.headers['X-Request-ID'] = this.generateRequestId();
                return config;
            },
            (error) => {
                this.handleRequestError(error);
                return Promise.reject(error);
            }
        );

        this.axiosInstance.interceptors.response.use(
            (response) => {
                this.updateMetrics('request', {
                    networkLatency: response.config['metadata']?.startTime
                        ? performance.now() - response.config['metadata'].startTime
                        : 0
                });
                return response;
            },
            (error) => {
                this.handleResponseError(error);
                return Promise.reject(error);
            }
        );
    }

    private async executeWithRetry<T>(
        operation: () => Promise<T>,
        retries: number
    ): Promise<T> {
        for (let attempt = 1; attempt <= retries; attempt++) {
            try {
                return await operation();
            } catch (error) {
                if (attempt === retries) throw error;
                await this.delay(Math.pow(2, attempt) * 100);
            }
        }
        throw new Error('Max retries exceeded');
    }

    private validateInputs(
        buffer: Float32Array,
        position: Position3D,
        options: ProcessingOptions
    ): void {
        if (!buffer || buffer.length === 0) {
            throw new Error(AudioProcessingError.BufferUnderrun);
        }

        if (!this.isValidPosition(position)) {
            throw new Error('Invalid spatial position');
        }

        if (options.enableHRTF && !this.hrtfCache.size) {
            throw new Error('HRTF dataset not configured');
        }
    }

    private isValidPosition(position: Position3D): boolean {
        return (
            typeof position.x === 'number' &&
            typeof position.y === 'number' &&
            typeof position.z === 'number' &&
            !isNaN(position.x) &&
            !isNaN(position.y) &&
            !isNaN(position.z)
        );
    }

    private async prepareProcessingPayload(
        buffer: Float32Array,
        position: Position3D,
        options: ProcessingOptions
    ): Promise<ArrayBuffer> {
        const headerSize = 24; // bytes
        const payload = new ArrayBuffer(headerSize + buffer.byteLength);
        const view = new DataView(payload);

        // Write header
        view.setUint32(0, buffer.length, true);
        view.setFloat32(4, position.x, true);
        view.setFloat32(8, position.y, true);
        view.setFloat32(12, position.z, true);
        view.setUint32(16, options.quality, true);
        view.setUint32(20, options.enableHRTF ? 1 : 0, true);

        // Write audio data
        new Float32Array(payload, headerSize).set(buffer);

        return payload;
    }

    private processResponse(response: any): Float32Array {
        const buffer = new Float32Array(response.data);
        
        if (buffer.length === 0) {
            throw new Error(AudioProcessingError.ProcessingOverload);
        }

        return buffer;
    }

    private updateMetrics(type: string, data: Partial<PerformanceMetrics>): void {
        if (!this.config.enableMetrics) return;

        const current = this.metricsCollector.get(type) || {};
        this.metricsCollector.set(type, { ...current, ...data });
    }

    private generateProcessingId(): string {
        return `proc_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;
    }

    private generateRequestId(): string {
        return `req_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;
    }

    private generateHRTFCacheKey(profile: string): string {
        return `hrtf_${profile}`;
    }

    private maintainCacheSize(): void {
        if (this.hrtfCache.size > this.config.hrtfCacheSize!) {
            const oldestKey = this.hrtfCache.keys().next().value;
            this.hrtfCache.delete(oldestKey);
        }
    }

    private delay(ms: number): Promise<void> {
        return new Promise(resolve => setTimeout(resolve, ms));
    }

    private handleProcessingError(error: any): void {
        console.error('Spatial processing error:', error);
        this.emitEvent(AudioProcessingEvent.Error, {
            error,
            timestamp: Date.now()
        });
    }

    private handleUpdateError(error: any): void {
        console.error('Position update error:', error);
        this.emitEvent(AudioProcessingEvent.Error, {
            error,
            timestamp: Date.now()
        });
    }

    private handleHRTFError(error: any): void {
        console.error('HRTF configuration error:', error);
        this.emitEvent(AudioProcessingEvent.Error, {
            error,
            timestamp: Date.now()
        });
    }

    private handleRequestError(error: any): void {
        console.error('Request error:', error);
        this.emitEvent(AudioProcessingEvent.Error, {
            error,
            timestamp: Date.now()
        });
    }

    private handleResponseError(error: any): void {
        console.error('Response error:', error);
        this.emitEvent(AudioProcessingEvent.Error, {
            error,
            timestamp: Date.now()
        });
    }

    private emitEvent(type: AudioProcessingEvent, payload: any): void {
        const event = new CustomEvent('spatial-audio', {
            detail: { type, payload }
        });
        window.dispatchEvent(event);
    }
}