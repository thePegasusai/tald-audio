/**
 * Defines WebSocket event types for real-time audio streaming and processing in TALD UNIA Audio System.
 * Supports low-latency communication with <10ms end-to-end latency target.
 * @version 1.0.0
 */

/**
 * Global prefix for all audio-related WebSocket events
 */
const EVENT_PREFIX = 'audio:' as const;

/**
 * Current version of the WebSocket event protocol
 */
const EVENT_VERSION = 'v1' as const;

/**
 * Comprehensive enum of WebSocket event types for audio processing
 * Used for type-safe event handling in real-time audio streaming
 */
export enum AudioEventType {
    // Stream Control Events
    STREAM_START = `${EVENT_PREFIX}${EVENT_VERSION}:stream:start`,
    STREAM_STOP = `${EVENT_PREFIX}${EVENT_VERSION}:stream:stop`,
    AUDIO_DATA = `${EVENT_PREFIX}${EVENT_VERSION}:stream:data`,
    
    // Processing Status Events
    PROCESSING_STATUS = `${EVENT_PREFIX}${EVENT_VERSION}:processing:status`,
    ERROR = `${EVENT_PREFIX}${EVENT_VERSION}:error`,
    
    // Spatial Audio Events
    HEAD_POSITION = `${EVENT_PREFIX}${EVENT_VERSION}:spatial:head_position`,
    ROOM_CALIBRATION = `${EVENT_PREFIX}${EVENT_VERSION}:spatial:room_calibration`,
    
    // Enhancement and AI Events
    ENHANCEMENT_STATUS = `${EVENT_PREFIX}${EVENT_VERSION}:enhancement:status`,
    AI_MODEL_STATUS = `${EVENT_PREFIX}${EVENT_VERSION}:ai:model_status`,
    
    // Performance Monitoring Events
    BUFFER_STATUS = `${EVENT_PREFIX}${EVENT_VERSION}:performance:buffer`,
    LATENCY_REPORT = `${EVENT_PREFIX}${EVENT_VERSION}:performance:latency`,
    
    // Debug Events
    DEBUG_INFO = `${EVENT_PREFIX}${EVENT_VERSION}:debug:info`
}