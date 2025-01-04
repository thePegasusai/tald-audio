/**
 * TALD UNIA Audio System - WebSocket API Client
 * Version: 1.0.0
 * 
 * High-performance WebSocket client implementation for real-time audio streaming
 * with AI enhancement, spatial audio processing, and comprehensive error handling.
 */

import { io, Socket } from 'socket.io-client'; // v4.7.2
import { Buffer } from 'buffer'; // v6.0.3
import { AudioStreamManager } from '../lib/websocket/audioStream';
import { WebSocketEventHandler } from '../lib/websocket/eventHandlers';
import { AudioEventType } from '../../../backend/src/websocket/events/audio-events.enum';

// System constants
const DEFAULT_RECONNECTION_ATTEMPTS = 5;
const DEFAULT_RECONNECTION_DELAY = 3000;
const DEFAULT_BUFFER_SIZE = 1024;
const DEFAULT_SAMPLE_RATE = 48000;
const MAX_LATENCY_MS = 10;
const MIN_QUALITY_THRESHOLD = 0.85;
const HEALTH_CHECK_INTERVAL = 1000;
const ERROR_RETRY_LIMIT = 3;

/**
 * WebSocket configuration interface
 */
interface WebSocketConfig {
    reconnectionAttempts?: number;
    reconnectionDelay?: number;
    bufferSize?: number;
    sampleRate?: number;
}

/**
 * Audio quality configuration interface
 */
interface AudioQualityConfig {
    targetLatency?: number;
    minQuality?: number;
    enableAIEnhancement?: boolean;
}

/**
 * Connection metrics interface
 */
interface ConnectionMetrics {
    latency: number;
    bufferHealth: number;
    processingLoad: number;
    qualityScore: number;
}

/**
 * Enhanced WebSocket API client for TALD UNIA Audio System
 */
export class WebSocketAPI {
    private socket: Socket;
    private streamManager: AudioStreamManager;
    private eventHandler: WebSocketEventHandler;
    private isConnected: boolean = false;
    private metrics: ConnectionMetrics;
    private config: WebSocketConfig;
    private qualityConfig: AudioQualityConfig;
    private healthCheckInterval: NodeJS.Timeout;
    private errorCount: number = 0;

    /**
     * Initialize WebSocket API client with enhanced configuration
     */
    constructor(
        serverUrl: string,
        config: WebSocketConfig = {},
        qualityConfig: AudioQualityConfig = {}
    ) {
        this.config = {
            reconnectionAttempts: config.reconnectionAttempts || DEFAULT_RECONNECTION_ATTEMPTS,
            reconnectionDelay: config.reconnectionDelay || DEFAULT_RECONNECTION_DELAY,
            bufferSize: config.bufferSize || DEFAULT_BUFFER_SIZE,
            sampleRate: config.sampleRate || DEFAULT_SAMPLE_RATE
        };

        this.qualityConfig = {
            targetLatency: qualityConfig.targetLatency || MAX_LATENCY_MS,
            minQuality: qualityConfig.minQuality || MIN_QUALITY_THRESHOLD,
            enableAIEnhancement: qualityConfig.enableAIEnhancement ?? true
        };

        this.initializeSocket(serverUrl);
        this.initializeStreamManager();
    }

    /**
     * Establish WebSocket connection with enhanced error handling
     */
    public async connect(): Promise<void> {
        try {
            if (this.isConnected) {
                throw new Error('WebSocket connection already established');
            }

            await new Promise<void>((resolve, reject) => {
                this.socket.connect();

                this.socket.once('connect', () => {
                    this.isConnected = true;
                    this.startHealthCheck();
                    resolve();
                });

                this.socket.once('connect_error', (error) => {
                    reject(error);
                });

                // Set connection timeout
                setTimeout(() => {
                    reject(new Error('Connection timeout'));
                }, this.config.reconnectionDelay);
            });
        } catch (error) {
            this.handleError('Connection failed', error);
            throw error;
        }
    }

    /**
     * Gracefully disconnect WebSocket connection
     */
    public async disconnect(): Promise<void> {
        try {
            if (!this.isConnected) return;

            await this.stopAudioStream();
            this.clearHealthCheck();
            this.socket.disconnect();
            this.isConnected = false;
        } catch (error) {
            this.handleError('Disconnection failed', error);
            throw error;
        }
    }

    /**
     * Start optimized audio streaming session
     */
    public async startAudioStream(config?: AudioQualityConfig): Promise<void> {
        try {
            if (!this.isConnected) {
                throw new Error('WebSocket not connected');
            }

            const streamConfig = {
                ...this.qualityConfig,
                ...config
            };

            await this.streamManager.startStream();
            this.socket.emit(AudioEventType.STREAM_START, {
                timestamp: Date.now(),
                config: streamConfig
            });

            this.setupStreamEventHandlers();
        } catch (error) {
            this.handleError('Stream start failed', error);
            throw error;
        }
    }

    /**
     * Stop audio streaming session
     */
    public async stopAudioStream(): Promise<void> {
        try {
            await this.streamManager.stopStream();
            this.socket.emit(AudioEventType.STREAM_STOP, {
                timestamp: Date.now()
            });
        } catch (error) {
            this.handleError('Stream stop failed', error);
            throw error;
        }
    }

    private initializeSocket(serverUrl: string): void {
        this.socket = io(serverUrl, {
            transports: ['websocket'],
            reconnectionAttempts: this.config.reconnectionAttempts,
            reconnectionDelay: this.config.reconnectionDelay,
            autoConnect: false
        });

        this.setupSocketEventHandlers();
    }

    private initializeStreamManager(): void {
        this.streamManager = new AudioStreamManager({
            sampleRate: this.config.sampleRate,
            bufferSize: this.config.bufferSize,
            enableAIEnhancement: this.qualityConfig.enableAIEnhancement
        });

        this.eventHandler = new WebSocketEventHandler(
            this.socket,
            this.streamManager,
            null // WebAudioContext will be initialized on stream start
        );
    }

    private setupSocketEventHandlers(): void {
        this.socket.on('disconnect', () => {
            this.isConnected = false;
            this.clearHealthCheck();
        });

        this.socket.on('error', (error) => {
            this.handleError('Socket error', error);
        });

        this.socket.on(AudioEventType.ERROR, (error) => {
            this.handleError('Stream error', error);
        });

        this.socket.on(AudioEventType.PROCESSING_STATUS, (status) => {
            this.updateMetrics(status);
        });
    }

    private setupStreamEventHandlers(): void {
        this.socket.on(AudioEventType.AUDIO_DATA, async (data) => {
            try {
                await this.eventHandler.handleAudioData(data);
            } catch (error) {
                this.handleError('Audio processing error', error);
            }
        });

        this.socket.on(AudioEventType.BUFFER_STATUS, (status) => {
            this.metrics.bufferHealth = status.health;
            this.checkStreamHealth();
        });

        this.socket.on(AudioEventType.LATENCY_REPORT, (report) => {
            this.metrics.latency = report.latency;
            this.checkStreamHealth();
        });
    }

    private startHealthCheck(): void {
        this.healthCheckInterval = setInterval(() => {
            this.checkStreamHealth();
        }, HEALTH_CHECK_INTERVAL);
    }

    private clearHealthCheck(): void {
        if (this.healthCheckInterval) {
            clearInterval(this.healthCheckInterval);
        }
    }

    private checkStreamHealth(): void {
        if (this.metrics.latency > this.qualityConfig.targetLatency) {
            this.handleQualityIssue('High latency detected', this.metrics);
        }

        if (this.metrics.bufferHealth < MIN_QUALITY_THRESHOLD) {
            this.handleQualityIssue('Low buffer health', this.metrics);
        }

        if (this.metrics.qualityScore < this.qualityConfig.minQuality) {
            this.handleQualityIssue('Quality below threshold', this.metrics);
        }
    }

    private updateMetrics(status: any): void {
        this.metrics = {
            ...this.metrics,
            ...status,
            timestamp: Date.now()
        };
    }

    private handleError(context: string, error: any): void {
        console.error(`WebSocket API Error (${context}):`, error);
        this.errorCount++;

        if (this.errorCount >= ERROR_RETRY_LIMIT) {
            this.socket.emit(AudioEventType.ERROR, {
                context,
                error: error.message,
                timestamp: Date.now()
            });
        }

        // Attempt recovery if needed
        if (this.errorCount >= ERROR_RETRY_LIMIT && this.isConnected) {
            this.attemptRecovery();
        }
    }

    private handleQualityIssue(issue: string, metrics: ConnectionMetrics): void {
        console.warn(`Stream quality issue: ${issue}`, metrics);
        this.socket.emit(AudioEventType.PROCESSING_STATUS, {
            issue,
            metrics,
            timestamp: Date.now()
        });
    }

    private async attemptRecovery(): Promise<void> {
        try {
            await this.stopAudioStream();
            await this.disconnect();
            await this.connect();
            await this.startAudioStream();
            this.errorCount = 0;
        } catch (error) {
            this.handleError('Recovery failed', error);
        }
    }
}