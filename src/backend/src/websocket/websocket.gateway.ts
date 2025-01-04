/**
 * TALD UNIA Audio System - WebSocket Gateway
 * Version: 1.0.0
 * 
 * Implements real-time audio streaming and processing with comprehensive monitoring
 * and error handling. Targets <10ms end-to-end latency with high reliability.
 */

import { 
    WebSocketGateway, 
    WebSocketServer, 
    SubscribeMessage, 
    ConnectedSocket 
} from '@nestjs/websockets'; // v10.0.0
import { Server, Socket } from 'socket.io'; // v4.7.0
import { Logger } from '@nestjs/common'; // v10.0.0

import { AudioStreamMessage } from './interfaces/audio-stream.interface';
import { AudioEventType } from './events/audio-events.enum';
import { AudioService } from '../audio/audio.service';

// System constants
const MAX_CLIENTS = 100;
const PING_INTERVAL = 1000;
const STREAM_TIMEOUT = 5000;
const BUFFER_POOL_SIZE = 1024;
const MAX_LATENCY_MS = 10;

/**
 * Client state management for active connections
 */
interface ClientState {
    id: string;
    isStreaming: boolean;
    streamStartTime: number;
    lastPingTime: number;
    bufferLevel: number;
    latency: number;
    qualityMetrics: QualityMetrics;
}

/**
 * Quality monitoring metrics
 */
interface QualityMetrics {
    processingLatency: number;
    bufferUnderruns: number;
    packetsLost: number;
    jitter: number;
    clockDrift: number;
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

@WebSocketGateway({
    namespace: 'audio',
    transports: ['websocket'],
    pingInterval: PING_INTERVAL,
    pingTimeout: STREAM_TIMEOUT
})
export class AudioGateway {
    private readonly logger = new Logger(AudioGateway.name);
    @WebSocketServer() private readonly server: Server;
    private readonly clientStates = new Map<string, ClientState>();
    private readonly bufferPool: AudioBufferPool;
    private readonly metrics: Map<string, number> = new Map();

    constructor(private readonly audioService: AudioService) {
        this.bufferPool = new AudioBufferPool(BUFFER_POOL_SIZE, 2048);
        this.initializeMetrics();
    }

    /**
     * Handle new WebSocket client connections
     */
    async handleConnection(@ConnectedSocket() client: Socket): Promise<void> {
        try {
            // Validate connection limits
            if (this.clientStates.size >= MAX_CLIENTS) {
                throw new Error('Maximum client connections reached');
            }

            // Initialize client state
            const clientState: ClientState = {
                id: client.id,
                isStreaming: false,
                streamStartTime: 0,
                lastPingTime: Date.now(),
                bufferLevel: 0,
                latency: 0,
                qualityMetrics: {
                    processingLatency: 0,
                    bufferUnderruns: 0,
                    packetsLost: 0,
                    jitter: 0,
                    clockDrift: 0
                }
            };

            this.clientStates.set(client.id, clientState);

            // Send initial configuration
            client.emit(AudioEventType.PROCESSING_STATUS, {
                maxLatency: MAX_LATENCY_MS,
                bufferSize: BUFFER_POOL_SIZE,
                sampleRate: 192000,
                channels: 2
            });

            this.logger.log(`Client connected: ${client.id}`);
        } catch (error) {
            this.logger.error(`Connection error: ${error.message}`);
            client.disconnect(true);
        }
    }

    /**
     * Handle client disconnections with cleanup
     */
    async handleDisconnect(@ConnectedSocket() client: Socket): Promise<void> {
        try {
            const state = this.clientStates.get(client.id);
            if (state) {
                // Stop active streams
                if (state.isStreaming) {
                    await this.handleStreamStop(client);
                }

                // Clean up resources
                this.clientStates.delete(client.id);
                this.updateMetrics('activeConnections', this.clientStates.size);
            }

            this.logger.log(`Client disconnected: ${client.id}`);
        } catch (error) {
            this.logger.error(`Disconnection error: ${error.message}`);
        }
    }

    /**
     * Handle incoming audio stream data
     */
    @SubscribeMessage(AudioEventType.AUDIO_DATA)
    async handleAudioStream(
        @ConnectedSocket() client: Socket,
        message: AudioStreamMessage
    ): Promise<void> {
        const state = this.clientStates.get(client.id);
        if (!state) return;

        try {
            const startTime = performance.now();

            // Validate audio data
            this.validateAudioData(message);

            // Get buffer from pool
            const processingBuffer = this.bufferPool.acquire();
            if (!processingBuffer) {
                throw new Error('Buffer pool exhausted');
            }

            // Process audio
            const processedAudio = await this.audioService.processAudio(
                message.data.buffer
            );

            // Update metrics
            const processingTime = performance.now() - startTime;
            this.updateClientMetrics(state, processingTime);

            // Send processed audio
            client.emit(AudioEventType.AUDIO_DATA, {
                event: AudioEventType.AUDIO_DATA,
                timestamp: Date.now(),
                data: {
                    buffer: processedAudio,
                    sequence: message.data.sequence,
                    timestamp: message.data.timestamp,
                    config: message.data.config
                },
                status: this.getStreamStatus(state)
            });

            // Release buffer
            this.bufferPool.release(processingBuffer);

        } catch (error) {
            this.handleStreamError(client, error);
        }
    }

    /**
     * Handle head position updates for spatial audio
     */
    @SubscribeMessage(AudioEventType.HEAD_POSITION)
    async handleHeadPosition(
        @ConnectedSocket() client: Socket,
        message: AudioStreamMessage
    ): Promise<void> {
        const state = this.clientStates.get(client.id);
        if (!state) return;

        try {
            await this.audioService.updateConfig({
                ...message.data.config,
                headPosition: message.data
            });

            client.emit(AudioEventType.PROCESSING_STATUS, {
                event: AudioEventType.PROCESSING_STATUS,
                status: 'Head position updated'
            });
        } catch (error) {
            this.logger.error(`Head position update error: ${error.message}`);
        }
    }

    /**
     * Private helper methods
     */
    private initializeMetrics(): void {
        this.metrics.set('activeConnections', 0);
        this.metrics.set('totalProcessed', 0);
        this.metrics.set('averageLatency', 0);
        this.metrics.set('bufferUtilization', 0);
    }

    private validateAudioData(message: AudioStreamMessage): void {
        if (!message.data?.buffer || message.data.buffer.length === 0) {
            throw new Error('Invalid audio data');
        }
        if (message.data.buffer.length > MAX_BUFFER_SIZE) {
            throw new Error('Audio buffer too large');
        }
    }

    private updateClientMetrics(state: ClientState, processingTime: number): void {
        state.latency = processingTime;
        state.qualityMetrics.processingLatency = processingTime;

        if (processingTime > MAX_LATENCY_MS) {
            state.qualityMetrics.bufferUnderruns++;
            this.logger.warn(`High latency detected: ${processingTime.toFixed(2)}ms`);
        }
    }

    private getStreamStatus(state: ClientState): any {
        return {
            isActive: state.isStreaming,
            latency: state.latency,
            bufferLevel: state.bufferLevel,
            qualityMetrics: state.qualityMetrics
        };
    }

    private async handleStreamStop(client: Socket): Promise<void> {
        const state = this.clientStates.get(client.id);
        if (state) {
            state.isStreaming = false;
            client.emit(AudioEventType.STREAM_STOP, {
                timestamp: Date.now(),
                status: 'Stream stopped'
            });
        }
    }

    private handleStreamError(client: Socket, error: Error): void {
        this.logger.error(`Stream error for client ${client.id}: ${error.message}`);
        
        client.emit(AudioEventType.ERROR, {
            timestamp: Date.now(),
            error: error.message
        });

        // Update error metrics
        const state = this.clientStates.get(client.id);
        if (state) {
            state.qualityMetrics.packetsLost++;
        }
    }

    private updateMetrics(metric: string, value: number): void {
        this.metrics.set(metric, value);
    }
}