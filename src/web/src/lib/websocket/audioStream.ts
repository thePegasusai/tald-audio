/**
 * TALD UNIA Audio System - WebSocket Audio Stream Manager
 * Version: 1.0.0
 * 
 * Implements high-performance WebSocket-based audio streaming with AI enhancement,
 * real-time quality monitoring, and automatic adaptation capabilities.
 */

import { io, Socket } from 'socket.io-client'; // v4.7.2
import { Buffer } from 'buffer'; // v6.0.3
import { WebAudioContext } from '../audio/webAudioAPI';
import { 
    AudioConfig,
    AudioProcessingEvent,
    AudioProcessingError,
    ProcessingQuality,
    AudioMetrics
} from '../../types/audio.types';

// System constants
const BUFFER_LOW_THRESHOLD = 0.2;
const BUFFER_HIGH_THRESHOLD = 0.8;
const MAX_BUFFER_SIZE = 8192;
const RECONNECTION_TIMEOUT_MS = 5000;
const QUALITY_CHECK_INTERVAL_MS = 1000;
const MIN_ACCEPTABLE_QUALITY = 0.95;
const MAX_LATENCY_MS = 10;

export class AudioStreamManager {
    private socket: Socket;
    private audioContext: WebAudioContext;
    private config: AudioConfig;
    private isStreaming: boolean = false;
    private bufferLevel: number = 0;
    private latency: number = 0;
    private qualityMetric: number = 1.0;
    private performanceMetrics: Map<string, number>;
    private qualityCheckInterval: number;
    private streamBuffer: Float32Array[];
    private processingChain: AudioNode[];
    private lastMetrics: AudioMetrics;

    /**
     * Initialize audio stream manager with WebSocket and quality monitoring
     */
    constructor(config: AudioConfig) {
        this.validateConfig(config);
        this.config = config;
        this.performanceMetrics = new Map();
        this.streamBuffer = [];
        this.initializeWebSocket();
    }

    /**
     * Start audio streaming with quality monitoring and adaptation
     */
    public async startStream(): Promise<void> {
        if (this.isStreaming) {
            throw new Error('Stream already active');
        }

        try {
            // Initialize audio context and processing chain
            this.audioContext = new WebAudioContext(this.config, {
                enableSpatial: true,
                hrtfProfile: 'default'
            });
            await this.audioContext.initialize();

            // Setup WebSocket event handlers
            this.setupSocketHandlers();

            // Initialize quality monitoring
            this.startQualityMonitoring();

            this.isStreaming = true;
            this.emitStreamEvent(AudioProcessingEvent.StateChange, { streaming: true });
        } catch (error) {
            this.handleError(AudioProcessingError.ConfigurationError, error);
            throw error;
        }
    }

    /**
     * Stop audio streaming and cleanup resources
     */
    public async stopStream(): Promise<void> {
        if (!this.isStreaming) return;

        try {
            // Stop quality monitoring
            if (this.qualityCheckInterval) {
                clearInterval(this.qualityCheckInterval);
            }

            // Clean up audio context
            await this.audioContext?.disconnect();

            // Clear buffers
            this.streamBuffer = [];
            this.bufferLevel = 0;

            // Update state
            this.isStreaming = false;
            this.emitStreamEvent(AudioProcessingEvent.StateChange, { streaming: false });
        } catch (error) {
            this.handleError(AudioProcessingError.DeviceError, error);
        }
    }

    /**
     * Update stream configuration with quality preservation
     */
    public async updateConfig(newConfig: AudioConfig): Promise<void> {
        this.validateConfig(newConfig);

        try {
            const wasStreaming = this.isStreaming;
            if (wasStreaming) {
                await this.stopStream();
            }

            this.config = newConfig;
            
            if (wasStreaming) {
                await this.startStream();
            }

            this.emitStreamEvent(AudioProcessingEvent.QualityChange, { config: newConfig });
        } catch (error) {
            this.handleError(AudioProcessingError.ConfigurationError, error);
        }
    }

    /**
     * Get current stream performance metrics
     */
    public getMetrics(): AudioMetrics {
        return this.lastMetrics;
    }

    private initializeWebSocket(): void {
        this.socket = io('wss://audio.tald-unia.com', {
            transports: ['websocket'],
            reconnectionDelay: RECONNECTION_TIMEOUT_MS,
            reconnectionAttempts: Infinity
        });
    }

    private setupSocketHandlers(): void {
        this.socket.on('audio.stream', async (data: ArrayBuffer) => {
            try {
                await this.handleAudioData(data);
            } catch (error) {
                this.handleError(AudioProcessingError.ProcessingOverload, error);
            }
        });

        this.socket.on('audio.status', (status: any) => {
            this.updateStreamStatus(status);
        });

        this.socket.on('disconnect', () => {
            this.handleDisconnection();
        });

        this.socket.on('error', (error: any) => {
            this.handleError(AudioProcessingError.DeviceError, error);
        });
    }

    private async handleAudioData(data: ArrayBuffer): Promise<void> {
        // Convert incoming data to Float32Array
        const audioData = new Float32Array(data);

        // Buffer management
        if (this.streamBuffer.length < MAX_BUFFER_SIZE) {
            this.streamBuffer.push(audioData);
            this.bufferLevel = this.streamBuffer.length / MAX_BUFFER_SIZE;
        } else {
            this.handleError(
                AudioProcessingError.BufferOverflow,
                'Stream buffer overflow'
            );
        }

        // Process audio through Web Audio API
        if (this.streamBuffer.length > this.config.bufferSize) {
            const processBuffer = this.streamBuffer.splice(0, this.config.bufferSize);
            const concatenated = this.concatenateBuffers(processBuffer);
            await this.processAudioBuffer(concatenated);
        }

        // Update metrics
        this.updateStreamMetrics();
    }

    private async processAudioBuffer(buffer: Float32Array): Promise<void> {
        try {
            const startTime = performance.now();
            
            // Process through audio context
            const processed = await this.audioContext.process(buffer);
            
            // Update latency measurement
            this.latency = performance.now() - startTime;
            
            if (this.latency > MAX_LATENCY_MS) {
                this.handleQualityIssue('High latency detected', { latency: this.latency });
            }

            // Update quality metrics
            this.lastMetrics = this.audioContext.updateQualityMetrics();
            this.emitStreamEvent(AudioProcessingEvent.MetricsUpdate, this.lastMetrics);
        } catch (error) {
            this.handleError(AudioProcessingError.ProcessingOverload, error);
        }
    }

    private startQualityMonitoring(): void {
        this.qualityCheckInterval = window.setInterval(() => {
            this.checkStreamQuality();
        }, QUALITY_CHECK_INTERVAL_MS);
    }

    private checkStreamQuality(): void {
        const metrics = this.getMetrics();
        
        // Check buffer health
        if (this.bufferLevel < BUFFER_LOW_THRESHOLD) {
            this.handleQualityIssue('Buffer level low', { level: this.bufferLevel });
        }

        // Check latency
        if (this.latency > MAX_LATENCY_MS) {
            this.adaptQuality('down');
        }

        // Check audio quality metrics
        if (metrics.thd > this.config.maxTHD || metrics.snr < this.config.minSNR) {
            this.handleQualityIssue('Audio quality degraded', metrics);
        }
    }

    private adaptQuality(direction: 'up' | 'down'): void {
        const currentQuality = this.config.processingQuality;
        let newQuality: ProcessingQuality;

        if (direction === 'down') {
            newQuality = currentQuality === ProcessingQuality.Maximum ? 
                ProcessingQuality.Balanced : ProcessingQuality.PowerSaver;
        } else {
            newQuality = currentQuality === ProcessingQuality.PowerSaver ? 
                ProcessingQuality.Balanced : ProcessingQuality.Maximum;
        }

        this.updateConfig({ ...this.config, processingQuality: newQuality });
    }

    private concatenateBuffers(buffers: Float32Array[]): Float32Array {
        const totalLength = buffers.reduce((sum, buf) => sum + buf.length, 0);
        const result = new Float32Array(totalLength);
        let offset = 0;
        
        for (const buffer of buffers) {
            result.set(buffer, offset);
            offset += buffer.length;
        }
        
        return result;
    }

    private handleDisconnection(): void {
        this.isStreaming = false;
        this.emitStreamEvent(AudioProcessingEvent.Error, {
            type: AudioProcessingError.DeviceError,
            message: 'WebSocket disconnected'
        });
    }

    private handleError(type: AudioProcessingError, error: any): void {
        console.error(`Audio stream error: ${type}`, error);
        this.emitStreamEvent(AudioProcessingEvent.Error, { type, error });
    }

    private handleQualityIssue(message: string, data: any): void {
        this.emitStreamEvent(AudioProcessingEvent.Warning, { message, data });
    }

    private emitStreamEvent(event: AudioProcessingEvent, data: any): void {
        this.socket.emit('stream.event', {
            type: event,
            timestamp: Date.now(),
            data
        });
    }

    private validateConfig(config: AudioConfig): void {
        if (!config.sampleRate || config.sampleRate < 44100) {
            throw new Error('Invalid sample rate configuration');
        }
        if (!config.bufferSize || config.bufferSize < 128) {
            throw new Error('Invalid buffer size configuration');
        }
        const latency = (config.bufferSize / config.sampleRate) * 1000;
        if (latency > MAX_LATENCY_MS) {
            throw new Error(`Configuration would exceed maximum latency: ${latency}ms`);
        }
    }

    private updateStreamStatus(status: any): void {
        this.performanceMetrics.set('serverLoad', status.load);
        this.performanceMetrics.set('clientCount', status.clients);
        this.performanceMetrics.set('bandwidth', status.bandwidth);
    }

    private updateStreamMetrics(): void {
        this.performanceMetrics.set('bufferLevel', this.bufferLevel);
        this.performanceMetrics.set('latency', this.latency);
        this.performanceMetrics.set('qualityMetric', this.qualityMetric);
    }
}