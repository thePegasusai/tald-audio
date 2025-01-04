/**
 * TALD UNIA Audio System - WebSocket Event Handlers
 * Version: 1.0.0
 * 
 * Implements high-performance WebSocket event handlers for real-time audio streaming
 * with AI enhancement, spatial audio processing, and quality monitoring.
 */

import { Socket } from 'socket.io-client'; // v4.7.2
import { AudioStreamManager } from './audioStream';
import { WebAudioContext } from '../audio/webAudioAPI';
import {
    AudioConfig,
    AudioProcessingEvent,
    AudioProcessingError,
    ProcessingQuality,
    Position3D,
    AudioMetrics,
    AIProcessingStatus,
    QualityMetrics
} from '../../types/audio.types';

// System constants
const RECONNECTION_ATTEMPTS = 3;
const RECONNECTION_DELAY_MS = 1000;
const ERROR_THRESHOLD = 5;
const STREAM_TIMEOUT_MS = 10000;
const MAX_LATENCY_MS = 10;
const BUFFER_SIZE_SAMPLES = 256;
const AI_WARMUP_TIME_MS = 500;
const QUALITY_UPDATE_INTERVAL_MS = 100;

export class WebSocketEventHandler {
    private socket: Socket;
    private streamManager: AudioStreamManager;
    private audioContext: WebAudioContext;
    private isConnected: boolean = false;
    private currentLatency: number = 0;
    private audioMetrics: AudioMetrics;
    private aiState: AIProcessingStatus;
    private spatialPosition: Position3D;
    private errorCount: number = 0;
    private qualityCheckInterval: number;
    private reconnectAttempts: number = 0;

    /**
     * Initialize WebSocket event handler with enhanced audio processing capabilities
     */
    constructor(
        socket: Socket,
        streamManager: AudioStreamManager,
        audioContext: WebAudioContext
    ) {
        this.socket = socket;
        this.streamManager = streamManager;
        this.audioContext = audioContext;
        this.initializeEventHandlers();
        this.setupQualityMonitoring();
    }

    /**
     * Handle stream start with AI enhancement and quality monitoring
     */
    public async handleStreamStart(config: AudioConfig): Promise<void> {
        try {
            // Initialize audio context with optimized settings
            await this.audioContext.initialize();

            // Configure AI processing
            await this.streamManager.configureAIProcessing({
                enabled: true,
                modelVersion: '1.0.0',
                enhancementLevel: 1.0,
                processingLoad: 0,
                lastUpdateTimestamp: Date.now()
            });

            // Start audio stream with quality monitoring
            await this.streamManager.startStream();

            // Initialize spatial audio
            this.spatialPosition = { x: 0, y: 0, z: 0 };
            this.audioContext.updateSpatialPosition(this.spatialPosition);

            // Configure latency optimization
            await this.audioContext.configureLatency(MAX_LATENCY_MS);

            this.isConnected = true;
            this.socket.emit('stream.ready', { timestamp: Date.now() });
        } catch (error) {
            this.handleError(AudioProcessingError.ConfigurationError, error);
            throw error;
        }
    }

    /**
     * Handle incoming audio data with AI enhancement and latency optimization
     */
    public async handleAudioData(data: ArrayBuffer): Promise<void> {
        if (!this.isConnected) return;

        try {
            const startTime = performance.now();

            // Process audio through stream manager
            await this.streamManager.handleAudioData(data);

            // Update latency measurement
            this.currentLatency = performance.now() - startTime;
            if (this.currentLatency > MAX_LATENCY_MS) {
                this.handleQualityIssue('High latency detected', {
                    latency: this.currentLatency,
                    threshold: MAX_LATENCY_MS
                });
            }

            // Update quality metrics
            this.audioMetrics = await this.streamManager.updateQualityMetrics();
            this.emitMetricsUpdate();

        } catch (error) {
            this.handleError(AudioProcessingError.ProcessingOverload, error);
        }
    }

    /**
     * Handle stream stop and cleanup
     */
    public async handleStreamStop(): Promise<void> {
        try {
            await this.streamManager.stopStream();
            this.isConnected = false;
            this.clearQualityMonitoring();
            this.socket.emit('stream.stopped', { timestamp: Date.now() });
        } catch (error) {
            this.handleError(AudioProcessingError.DeviceError, error);
        }
    }

    /**
     * Update spatial audio positioning with quality validation
     */
    public handleSpatialUpdate(position: Position3D): void {
        try {
            this.spatialPosition = position;
            this.audioContext.updateSpatialPosition(position);
            this.socket.emit('spatial.updated', {
                position,
                timestamp: Date.now()
            });
        } catch (error) {
            this.handleError(AudioProcessingError.DeviceError, error);
        }
    }

    /**
     * Handle WebSocket errors with recovery mechanisms
     */
    public handleError(type: AudioProcessingError, error: any): void {
        console.error(`WebSocket error: ${type}`, error);
        this.errorCount++;

        if (this.errorCount > ERROR_THRESHOLD) {
            this.attemptRecovery();
        }

        this.socket.emit('stream.error', {
            type,
            message: error.message,
            timestamp: Date.now()
        });
    }

    private initializeEventHandlers(): void {
        this.socket.on('connect', () => {
            this.isConnected = true;
            this.errorCount = 0;
            this.reconnectAttempts = 0;
        });

        this.socket.on('disconnect', () => {
            this.isConnected = false;
            this.handleStreamStop();
        });

        this.socket.on('audio.quality', (data: any) => {
            this.handleQualityUpdate(data);
        });

        this.socket.on('error', (error: any) => {
            this.handleError(AudioProcessingError.DeviceError, error);
        });
    }

    private setupQualityMonitoring(): void {
        this.qualityCheckInterval = window.setInterval(() => {
            if (this.isConnected) {
                this.checkStreamQuality();
            }
        }, QUALITY_UPDATE_INTERVAL_MS);
    }

    private clearQualityMonitoring(): void {
        if (this.qualityCheckInterval) {
            clearInterval(this.qualityCheckInterval);
        }
    }

    private async checkStreamQuality(): Promise<void> {
        const metrics = this.audioMetrics;
        if (!metrics) return;

        if (metrics.thd > 0.0005) {
            this.handleQualityIssue('THD exceeds threshold', metrics);
        }

        if (metrics.snr < 120) {
            this.handleQualityIssue('SNR below threshold', metrics);
        }

        this.emitMetricsUpdate();
    }

    private handleQualityUpdate(data: any): void {
        if (data.processingQuality !== this.streamManager.getMetrics().processingQuality) {
            this.streamManager.updateConfig({
                ...this.audioContext.config,
                processingQuality: data.processingQuality
            });
        }
    }

    private handleQualityIssue(message: string, data: any): void {
        this.socket.emit('stream.warning', {
            message,
            data,
            timestamp: Date.now()
        });
    }

    private emitMetricsUpdate(): void {
        this.socket.emit('stream.metrics', {
            metrics: this.audioMetrics,
            latency: this.currentLatency,
            aiStatus: this.aiState,
            timestamp: Date.now()
        });
    }

    private async attemptRecovery(): Promise<void> {
        if (this.reconnectAttempts >= RECONNECTION_ATTEMPTS) {
            await this.handleStreamStop();
            this.socket.emit('stream.fatal', {
                message: 'Maximum reconnection attempts exceeded',
                timestamp: Date.now()
            });
            return;
        }

        this.reconnectAttempts++;
        setTimeout(async () => {
            try {
                await this.handleStreamStart(this.audioContext.config);
                this.errorCount = 0;
            } catch (error) {
                this.handleError(AudioProcessingError.DeviceError, error);
            }
        }, RECONNECTION_DELAY_MS * this.reconnectAttempts);
    }
}