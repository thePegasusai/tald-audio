/**
 * TALD UNIA Audio System - Advanced API Client Module
 * Version: 1.0.0
 * 
 * High-performance audio processing API client with comprehensive monitoring,
 * error handling, and quality assurance features.
 */

import axios, { AxiosInstance, AxiosRequestConfig } from 'axios'; // ^1.6.0
import { io, Socket } from 'socket.io-client'; // ^4.7.0
import {
    AudioConfig,
    ProcessingQuality,
    AudioProcessingState,
    AudioMetrics,
    AudioProcessingError,
    AudioProcessingEvent,
    AudioProcessingEventPayload,
    SpatialAudioConfig,
    DeviceCapabilities
} from '../types/audio.types';

// Global constants for API configuration
const DEFAULT_BASE_URL = '/api/v1';
const SOCKET_TIMEOUT_MS = 5000;
const MAX_RETRY_ATTEMPTS = 3;
const QUALITY_THRESHOLD_THD = 0.0005;
const MIN_BUFFER_HEALTH = 0.8;
const RECONNECT_BACKOFF_MS = 1000;
const PERFORMANCE_SAMPLE_RATE_MS = 100;

/**
 * Connection pool configuration for optimized API performance
 */
interface ConnectionPool {
    maxConnections: number;
    minConnections: number;
    idleTimeoutMs: number;
}

/**
 * Retry configuration for resilient API communication
 */
interface RetryConfiguration {
    maxAttempts: number;
    baseDelayMs: number;
    maxDelayMs: number;
    timeoutMs: number;
}

/**
 * Stream health tracking metrics
 */
interface StreamHealthTracker {
    bufferHealth: number;
    latency: number;
    dropouts: number;
    lastUpdateTimestamp: number;
}

/**
 * Quality monitoring system for audio processing
 */
class QualityMonitor {
    private metrics: AudioMetrics;
    private thresholds: Map<string, number>;
    private listeners: Set<(metrics: AudioMetrics) => void>;

    constructor() {
        this.metrics = this.initializeMetrics();
        this.thresholds = new Map([
            ['thd', QUALITY_THRESHOLD_THD],
            ['bufferHealth', MIN_BUFFER_HEALTH]
        ]);
        this.listeners = new Set();
    }

    private initializeMetrics(): AudioMetrics {
        return {
            thd: 0,
            snr: 0,
            rmsLevel: 0,
            peakLevel: 0,
            dynamicRange: 0,
            frequencyResponse: [],
            phaseResponse: []
        };
    }

    public updateMetrics(newMetrics: Partial<AudioMetrics>): void {
        this.metrics = { ...this.metrics, ...newMetrics };
        this.checkThresholds();
        this.notifyListeners();
    }

    private checkThresholds(): void {
        for (const [metric, threshold] of this.thresholds) {
            if (this.metrics[metric] > threshold) {
                this.handleThresholdExceeded(metric, this.metrics[metric]);
            }
        }
    }

    private handleThresholdExceeded(metric: string, value: number): void {
        console.warn(`Quality threshold exceeded for ${metric}: ${value}`);
    }

    private notifyListeners(): void {
        this.listeners.forEach(listener => listener(this.metrics));
    }
}

/**
 * Advanced client-side API wrapper for TALD UNIA Audio System
 */
export class AudioAPI {
    private readonly http: AxiosInstance;
    private socket: Socket;
    private config: AudioConfig;
    private retryConfig: RetryConfiguration;
    private connectionPool: ConnectionPool;
    private qualityMonitor: QualityMonitor;
    private streamHealth: StreamHealthTracker;

    constructor(
        baseUrl: string = DEFAULT_BASE_URL,
        initialConfig: AudioConfig,
        retryConfig: RetryConfiguration
    ) {
        this.config = initialConfig;
        this.retryConfig = retryConfig;
        this.qualityMonitor = new QualityMonitor();
        this.streamHealth = this.initializeStreamHealth();

        // Initialize HTTP client with connection pooling
        this.http = axios.create({
            baseURL: baseUrl,
            timeout: retryConfig.timeoutMs,
            maxRedirects: 5,
            withCredentials: true
        });

        // Initialize WebSocket connection
        this.socket = this.initializeWebSocket(baseUrl);
        
        // Initialize connection pool
        this.connectionPool = {
            maxConnections: 10,
            minConnections: 2,
            idleTimeoutMs: 30000
        };

        this.setupHttpInterceptors();
        this.setupWebSocketHandlers();
    }

    /**
     * Process audio buffer through REST API with quality monitoring
     */
    public async processAudio(
        audioData: ArrayBuffer,
        options: {
            quality?: ProcessingQuality;
            spatial?: SpatialAudioConfig;
        } = {}
    ): Promise<{ 
        processedAudio: ArrayBuffer;
        metrics: AudioMetrics;
    }> {
        try {
            const startTime = performance.now();
            
            const response = await this.http.post('/audio/process', {
                audio: audioData,
                config: {
                    ...this.config,
                    quality: options.quality || this.config.processingQuality,
                    spatial: options.spatial
                }
            }, {
                responseType: 'arraybuffer',
                headers: {
                    'Content-Type': 'application/octet-stream'
                }
            });

            const processingTime = performance.now() - startTime;
            this.updateProcessingMetrics(processingTime);

            const metrics = JSON.parse(response.headers['x-audio-metrics']);
            this.qualityMonitor.updateMetrics(metrics);

            return {
                processedAudio: response.data,
                metrics
            };
        } catch (error) {
            throw this.handleProcessingError(error);
        }
    }

    /**
     * Start real-time audio streaming session with health monitoring
     */
    public async startStream(options: {
        quality?: ProcessingQuality;
        spatial?: SpatialAudioConfig;
    } = {}): Promise<string> {
        return new Promise((resolve, reject) => {
            try {
                const sessionId = crypto.randomUUID();
                
                this.socket.emit('stream:start', {
                    sessionId,
                    config: {
                        ...this.config,
                        quality: options.quality || this.config.processingQuality,
                        spatial: options.spatial
                    }
                });

                this.socket.on(`stream:ready:${sessionId}`, () => {
                    this.initializeStreamMonitoring(sessionId);
                    resolve(sessionId);
                });

                this.socket.on(`stream:error:${sessionId}`, (error) => {
                    reject(new Error(error.message));
                });
            } catch (error) {
                reject(this.handleStreamError(error));
            }
        });
    }

    /**
     * Stop real-time audio streaming with statistics
     */
    public async stopStream(sessionId: string): Promise<AudioMetrics> {
        return new Promise((resolve, reject) => {
            try {
                this.socket.emit('stream:stop', { sessionId });
                
                this.socket.on(`stream:stopped:${sessionId}`, (finalMetrics: AudioMetrics) => {
                    this.cleanupStreamMonitoring(sessionId);
                    resolve(finalMetrics);
                });
            } catch (error) {
                reject(this.handleStreamError(error));
            }
        });
    }

    /**
     * Update audio processing configuration with validation
     */
    public async updateConfig(newConfig: Partial<AudioConfig>): Promise<void> {
        try {
            const validatedConfig = await this.validateConfig({
                ...this.config,
                ...newConfig
            });

            await this.http.put('/audio/config', validatedConfig);
            this.config = validatedConfig;

            this.socket.emit('config:update', validatedConfig);
        } catch (error) {
            throw this.handleConfigError(error);
        }
    }

    /**
     * Retrieve comprehensive audio processing statistics
     */
    public async getProcessingStats(): Promise<AudioProcessingState> {
        try {
            const response = await this.http.get('/audio/stats');
            return response.data;
        } catch (error) {
            throw this.handleStatsError(error);
        }
    }

    private initializeWebSocket(baseUrl: string): Socket {
        return io(`${baseUrl}/audio`, {
            transports: ['websocket'],
            reconnection: true,
            reconnectionDelay: RECONNECT_BACKOFF_MS,
            reconnectionAttempts: MAX_RETRY_ATTEMPTS,
            timeout: SOCKET_TIMEOUT_MS
        });
    }

    private initializeStreamHealth(): StreamHealthTracker {
        return {
            bufferHealth: 1.0,
            latency: 0,
            dropouts: 0,
            lastUpdateTimestamp: Date.now()
        };
    }

    private setupHttpInterceptors(): void {
        this.http.interceptors.request.use(
            (config) => {
                config.headers['X-Client-Version'] = '1.0.0';
                return config;
            },
            (error) => Promise.reject(error)
        );

        this.http.interceptors.response.use(
            (response) => response,
            (error) => this.handleHttpError(error)
        );
    }

    private setupWebSocketHandlers(): void {
        this.socket.on('connect', () => {
            console.log('WebSocket connected');
        });

        this.socket.on('disconnect', (reason) => {
            console.warn(`WebSocket disconnected: ${reason}`);
        });

        this.socket.on('error', (error) => {
            console.error('WebSocket error:', error);
        });

        this.socket.on('metrics', (metrics: AudioMetrics) => {
            this.qualityMonitor.updateMetrics(metrics);
        });
    }

    private async validateConfig(config: AudioConfig): Promise<AudioConfig> {
        const deviceCaps = await this.getDeviceCapabilities();
        
        if (config.sampleRate > deviceCaps.maxSampleRate) {
            throw new Error(`Sample rate ${config.sampleRate} exceeds device maximum ${deviceCaps.maxSampleRate}`);
        }

        if (config.bitDepth > deviceCaps.maxBitDepth) {
            throw new Error(`Bit depth ${config.bitDepth} exceeds device maximum ${deviceCaps.maxBitDepth}`);
        }

        return config;
    }

    private async getDeviceCapabilities(): Promise<DeviceCapabilities> {
        const response = await this.http.get('/audio/capabilities');
        return response.data;
    }

    private updateProcessingMetrics(processingTime: number): void {
        const event: AudioProcessingEventPayload = {
            type: AudioProcessingEvent.MetricsUpdate,
            timestamp: Date.now(),
            data: { processingTime },
            source: 'AudioAPI'
        };
        this.socket.emit('metrics:update', event);
    }

    private handleProcessingError(error: any): Error {
        console.error('Audio processing error:', error);
        return new Error(`Audio processing failed: ${error.message}`);
    }

    private handleStreamError(error: any): Error {
        console.error('Stream error:', error);
        return new Error(`Streaming failed: ${error.message}`);
    }

    private handleConfigError(error: any): Error {
        console.error('Configuration error:', error);
        return new Error(`Configuration update failed: ${error.message}`);
    }

    private handleStatsError(error: any): Error {
        console.error('Stats error:', error);
        return new Error(`Failed to retrieve stats: ${error.message}`);
    }

    private handleHttpError(error: any): Promise<never> {
        if (error.response) {
            console.error('HTTP Error Response:', error.response.data);
            throw new Error(`HTTP ${error.response.status}: ${error.response.data.message}`);
        }
        throw error;
    }

    private initializeStreamMonitoring(sessionId: string): void {
        setInterval(() => {
            this.socket.emit('stream:health', {
                sessionId,
                health: this.streamHealth
            });
        }, PERFORMANCE_SAMPLE_RATE_MS);
    }

    private cleanupStreamMonitoring(sessionId: string): void {
        this.socket.off(`stream:ready:${sessionId}`);
        this.socket.off(`stream:error:${sessionId}`);
        this.socket.off(`stream:stopped:${sessionId}`);
    }
}