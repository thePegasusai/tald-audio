/**
 * TALD UNIA Audio System - WebSocket Context Provider
 * Version: 1.0.0
 * 
 * Implements high-performance WebSocket context for real-time audio streaming
 * with AI enhancement, quality monitoring, and spatial audio processing.
 */

import React, { createContext, useContext, useEffect, useCallback, useState, useRef } from 'react';
import { io, Socket } from 'socket.io-client'; // v4.7.2
import { AudioStreamManager } from '../../lib/websocket/audioStream';
import { WebSocketEventHandler } from '../../lib/websocket/eventHandlers';
import { WebAudioContext } from '../../lib/audio/webAudioAPI';
import {
    AudioConfig,
    AudioProcessingEvent,
    AudioProcessingError,
    ProcessingQuality,
    AudioMetrics,
    AIProcessingStatus,
    SpatialAudioConfig,
    Position3D
} from '../../types/audio.types';

// System constants
const SOCKET_URL = process.env.REACT_APP_WEBSOCKET_URL || 'wss://audio.tald-unia.com';
const RECONNECTION_ATTEMPTS = 5;
const RECONNECTION_DELAY_MS = 1000;
const STREAM_TIMEOUT_MS = 5000;
const QUALITY_THRESHOLD_THD = 0.0005;
const AI_UPDATE_INTERVAL_MS = 100;
const SPATIAL_UPDATE_RATE_HZ = 60;

// Default audio configuration
const defaultAudioConfig: AudioConfig = {
    sampleRate: 192000,
    bitDepth: 32,
    channels: 2,
    bufferSize: 256,
    processingQuality: ProcessingQuality.Maximum
};

// Default spatial configuration
const defaultSpatialConfig: SpatialAudioConfig = {
    enableSpatial: true,
    roomSize: { width: 10, height: 3, depth: 10 },
    listenerPosition: { x: 0, y: 0, z: 0 },
    hrtfEnabled: true,
    hrtfProfile: 'default',
    roomMaterials: [],
    reflectionModel: 'HYBRID'
};

interface WebSocketContextState {
    socket: Socket | null;
    isConnected: boolean;
    isStreaming: boolean;
    qualityMetrics: AudioMetrics | null;
    aiStatus: AIProcessingStatus | null;
    spatialPosition: Position3D;
    startStream: (config?: AudioConfig) => Promise<void>;
    stopStream: () => Promise<void>;
    updateSpatialPosition: (position: Position3D) => void;
    updateQuality: (quality: ProcessingQuality) => void;
}

const WebSocketContext = createContext<WebSocketContextState | null>(null);

export const useWebSocket = () => {
    const context = useContext(WebSocketContext);
    if (!context) {
        throw new Error('useWebSocket must be used within a WebSocketProvider');
    }
    return context;
};

interface WebSocketProviderProps {
    children: React.ReactNode;
    config?: AudioConfig;
    spatialConfig?: SpatialAudioConfig;
}

export const WebSocketProvider: React.FC<WebSocketProviderProps> = ({
    children,
    config = defaultAudioConfig,
    spatialConfig = defaultSpatialConfig
}) => {
    const [socket, setSocket] = useState<Socket | null>(null);
    const [isConnected, setIsConnected] = useState(false);
    const [isStreaming, setIsStreaming] = useState(false);
    const [qualityMetrics, setQualityMetrics] = useState<AudioMetrics | null>(null);
    const [aiStatus, setAIStatus] = useState<AIProcessingStatus | null>(null);
    const [spatialPosition, setSpatialPosition] = useState<Position3D>({ x: 0, y: 0, z: 0 });

    const streamManagerRef = useRef<AudioStreamManager | null>(null);
    const eventHandlerRef = useRef<WebSocketEventHandler | null>(null);
    const audioContextRef = useRef<WebAudioContext | null>(null);

    // Initialize WebSocket connection with enhanced configuration
    const initializeSocket = useCallback(async () => {
        const newSocket = io(SOCKET_URL, {
            transports: ['websocket'],
            reconnectionAttempts: RECONNECTION_ATTEMPTS,
            reconnectionDelay: RECONNECTION_DELAY_MS,
            timeout: STREAM_TIMEOUT_MS
        });

        // Initialize audio components
        audioContextRef.current = new WebAudioContext(config, spatialConfig);
        streamManagerRef.current = new AudioStreamManager(config);
        eventHandlerRef.current = new WebSocketEventHandler(
            newSocket,
            streamManagerRef.current,
            audioContextRef.current
        );

        // Setup WebSocket event listeners
        newSocket.on('connect', () => {
            setIsConnected(true);
            console.log('WebSocket connected');
        });

        newSocket.on('disconnect', () => {
            setIsConnected(false);
            setIsStreaming(false);
            console.log('WebSocket disconnected');
        });

        newSocket.on('audio.metrics', (metrics: AudioMetrics) => {
            setQualityMetrics(metrics);
            if (metrics.thd > QUALITY_THRESHOLD_THD) {
                console.warn(`THD exceeds threshold: ${metrics.thd}`);
            }
        });

        newSocket.on('ai.status', (status: AIProcessingStatus) => {
            setAIStatus(status);
        });

        newSocket.on('error', (error: any) => {
            console.error('WebSocket error:', error);
            eventHandlerRef.current?.handleError(
                AudioProcessingError.DeviceError,
                error
            );
        });

        setSocket(newSocket);
    }, [config, spatialConfig]);

    // Start audio streaming with enhanced configuration
    const startStream = useCallback(async (streamConfig?: AudioConfig) => {
        if (!socket || !eventHandlerRef.current) return;

        try {
            await eventHandlerRef.current.handleStreamStart(streamConfig || config);
            setIsStreaming(true);
        } catch (error) {
            console.error('Failed to start stream:', error);
            setIsStreaming(false);
        }
    }, [socket, config]);

    // Stop audio streaming and cleanup resources
    const stopStream = useCallback(async () => {
        if (!socket || !eventHandlerRef.current) return;

        try {
            await eventHandlerRef.current.handleStreamStop();
            setIsStreaming(false);
        } catch (error) {
            console.error('Failed to stop stream:', error);
        }
    }, [socket]);

    // Update spatial audio position with quality validation
    const updateSpatialPosition = useCallback((position: Position3D) => {
        if (!eventHandlerRef.current) return;

        try {
            eventHandlerRef.current.handleSpatialUpdate(position);
            setSpatialPosition(position);
        } catch (error) {
            console.error('Failed to update spatial position:', error);
        }
    }, []);

    // Update audio processing quality
    const updateQuality = useCallback((quality: ProcessingQuality) => {
        if (!streamManagerRef.current) return;

        try {
            streamManagerRef.current.updateConfig({
                ...config,
                processingQuality: quality
            });
        } catch (error) {
            console.error('Failed to update quality:', error);
        }
    }, [config]);

    // Initialize WebSocket connection on mount
    useEffect(() => {
        initializeSocket();

        return () => {
            socket?.disconnect();
            streamManagerRef.current?.stopStream();
        };
    }, [initializeSocket]);

    // Monitor spatial position updates
    useEffect(() => {
        if (!isStreaming) return;

        const spatialInterval = setInterval(() => {
            if (eventHandlerRef.current) {
                eventHandlerRef.current.handleSpatialUpdate(spatialPosition);
            }
        }, 1000 / SPATIAL_UPDATE_RATE_HZ);

        return () => clearInterval(spatialInterval);
    }, [isStreaming, spatialPosition]);

    const contextValue: WebSocketContextState = {
        socket,
        isConnected,
        isStreaming,
        qualityMetrics,
        aiStatus,
        spatialPosition,
        startStream,
        stopStream,
        updateSpatialPosition,
        updateQuality
    };

    return (
        <WebSocketContext.Provider value={contextValue}>
            {children}
        </WebSocketContext.Provider>
    );
};

export default WebSocketContext;