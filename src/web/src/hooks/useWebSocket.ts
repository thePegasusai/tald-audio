/**
 * TALD UNIA Audio System - WebSocket Hook
 * Version: 1.0.0
 * 
 * High-performance React hook for managing WebSocket connections with real-time
 * audio streaming, AI enhancement, and comprehensive quality monitoring.
 */

import { useEffect, useState, useCallback } from 'react'; // v18.2.0
import { io, Socket } from 'socket.io-client'; // v4.7.2
import { AudioStreamManager } from '../../lib/websocket/audioStream';
import { WebSocketEventHandler } from '../../lib/websocket/eventHandlers';
import {
    AudioConfig,
    AudioProcessingEvent,
    AudioProcessingError,
    AudioMetrics,
    AIProcessingStatus,
    Position3D,
    ProcessingQuality
} from '../../types/audio.types';

// System constants
const RECONNECTION_TIMEOUT = 5000;
const MAX_RECONNECTION_ATTEMPTS = 3;
const HEARTBEAT_INTERVAL = 30000;
const BUFFER_SIZE = 256;
const MAX_LATENCY_MS = 10;
const METRICS_UPDATE_INTERVAL = 1000;

interface WebSocketState {
    isConnected: boolean;
    error: Error | null;
    metrics: AudioMetrics | null;
    aiProcessingState: AIProcessingStatus | null;
    spatialPosition: Position3D | null;
    reconnectAttempts: number;
}

interface UseWebSocketOptions {
    url: string;
    config: AudioConfig;
    aiOptions?: {
        enabled: boolean;
        enhancementLevel: number;
    };
}

/**
 * High-performance WebSocket hook for real-time audio streaming
 */
export function useWebSocket({ url, config, aiOptions }: UseWebSocketOptions) {
    // Connection state management
    const [state, setState] = useState<WebSocketState>({
        isConnected: false,
        error: null,
        metrics: null,
        aiProcessingState: null,
        spatialPosition: null,
        reconnectAttempts: 0
    });

    // Socket and manager instances
    const [socket, setSocket] = useState<Socket | null>(null);
    const [streamManager, setStreamManager] = useState<AudioStreamManager | null>(null);
    const [eventHandler, setEventHandler] = useState<WebSocketEventHandler | null>(null);

    /**
     * Initialize WebSocket connection with optimized settings
     */
    const initializeSocket = useCallback(() => {
        const newSocket = io(url, {
            transports: ['websocket'],
            reconnectionDelay: RECONNECTION_TIMEOUT,
            reconnectionAttempts: MAX_RECONNECTION_ATTEMPTS,
            autoConnect: false,
            query: {
                bufferSize: BUFFER_SIZE,
                sampleRate: config.sampleRate,
                processingQuality: config.processingQuality
            }
        });

        setSocket(newSocket);
        return newSocket;
    }, [url, config]);

    /**
     * Initialize audio stream manager with AI enhancement
     */
    const initializeStreamManager = useCallback((socket: Socket) => {
        const manager = new AudioStreamManager(config);
        const handler = new WebSocketEventHandler(socket, manager, null);

        setStreamManager(manager);
        setEventHandler(handler);

        return { manager, handler };
    }, [config]);

    /**
     * Connect to WebSocket server with quality monitoring
     */
    const connect = useCallback(async () => {
        if (state.isConnected) return;

        try {
            const newSocket = socket || initializeSocket();
            const { manager, handler } = streamManager && eventHandler ? 
                { manager: streamManager, handler: eventHandler } : 
                initializeStreamManager(newSocket);

            // Configure AI processing
            if (aiOptions?.enabled) {
                await manager.configureAIProcessing({
                    enabled: true,
                    modelVersion: '1.0.0',
                    enhancementLevel: aiOptions.enhancementLevel,
                    processingLoad: 0,
                    lastUpdateTimestamp: Date.now()
                });
            }

            // Setup event handlers
            setupEventHandlers(newSocket, handler);

            // Connect socket
            newSocket.connect();

            setState(prev => ({
                ...prev,
                isConnected: true,
                error: null,
                reconnectAttempts: 0
            }));
        } catch (error) {
            handleError(new Error(`Connection failed: ${error.message}`));
        }
    }, [state.isConnected, socket, streamManager, eventHandler, aiOptions, initializeSocket, initializeStreamManager]);

    /**
     * Disconnect from WebSocket server with cleanup
     */
    const disconnect = useCallback(async () => {
        if (!state.isConnected || !socket) return;

        try {
            await eventHandler?.handleStreamStop();
            socket.disconnect();

            setState(prev => ({
                ...prev,
                isConnected: false,
                metrics: null,
                aiProcessingState: null,
                spatialPosition: null
            }));
        } catch (error) {
            handleError(new Error(`Disconnection failed: ${error.message}`));
        }
    }, [state.isConnected, socket, eventHandler]);

    /**
     * Update spatial audio position
     */
    const updateSpatialPosition = useCallback((position: Position3D) => {
        if (!state.isConnected || !eventHandler) return;
        eventHandler.handleSpatialUpdate(position);
        setState(prev => ({ ...prev, spatialPosition: position }));
    }, [state.isConnected, eventHandler]);

    /**
     * Handle WebSocket errors with recovery
     */
    const handleError = useCallback((error: Error) => {
        console.error('WebSocket error:', error);

        setState(prev => {
            const attempts = prev.reconnectAttempts + 1;
            if (attempts <= MAX_RECONNECTION_ATTEMPTS) {
                setTimeout(connect, RECONNECTION_TIMEOUT);
            }
            return {
                ...prev,
                error,
                reconnectAttempts: attempts
            };
        });
    }, [connect]);

    /**
     * Setup WebSocket event handlers with quality monitoring
     */
    const setupEventHandlers = useCallback((socket: Socket, handler: WebSocketEventHandler) => {
        socket.on('connect', () => {
            setState(prev => ({ ...prev, isConnected: true, error: null }));
        });

        socket.on('disconnect', () => {
            setState(prev => ({ ...prev, isConnected: false }));
        });

        socket.on('audio.metrics', (metrics: AudioMetrics) => {
            setState(prev => ({ ...prev, metrics }));
        });

        socket.on('ai.status', (aiProcessingState: AIProcessingStatus) => {
            setState(prev => ({ ...prev, aiProcessingState }));
        });

        socket.on('error', (error: Error) => {
            handleError(error);
        });

        // Setup heartbeat
        const heartbeat = setInterval(() => {
            if (socket.connected) {
                socket.emit('heartbeat', { timestamp: Date.now() });
            }
        }, HEARTBEAT_INTERVAL);

        return () => {
            clearInterval(heartbeat);
            socket.removeAllListeners();
        };
    }, [handleError]);

    // Cleanup on unmount
    useEffect(() => {
        return () => {
            disconnect();
        };
    }, [disconnect]);

    return {
        connect,
        disconnect,
        updateSpatialPosition,
        isConnected: state.isConnected,
        error: state.error,
        metrics: state.metrics,
        aiProcessingState: state.aiProcessingState,
        spatialPosition: state.spatialPosition
    };
}