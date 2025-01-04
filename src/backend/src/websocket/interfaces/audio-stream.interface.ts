/**
 * Interface definitions for real-time WebSocket audio streaming in TALD UNIA Audio System
 * Implements enterprise-grade audio streaming with comprehensive monitoring capabilities
 * @version 1.0.0
 */

import { AudioEventType } from '../events/audio-events.enum';
import { AudioConfig } from '../../audio/interfaces/audio-config.interface';
import { Buffer } from 'buffer';

// Global constants for stream management
export const MAX_BUFFER_SIZE = 32768;  // Maximum buffer size in bytes
export const MIN_SEQUENCE_NUMBER = 0;  // Minimum sequence number for packet ordering
export const MAX_SEQUENCE_NUMBER = 65535;  // Maximum sequence number before wrapping

/**
 * Comprehensive WebSocket message structure for audio streaming
 * Provides complete type safety and monitoring capabilities
 */
export interface AudioStreamMessage {
    readonly event: AudioEventType;      // Event type from audio-events enum
    readonly timestamp: number;          // High-precision timestamp (microseconds)
    readonly data: AudioStreamData;      // Audio payload data
    readonly status: AudioStreamStatus;  // Comprehensive stream status
}

/**
 * Detailed audio data structure with integrity checking
 * Supports professional-grade audio up to 32-bit/192kHz
 */
export interface AudioStreamData {
    readonly config: AudioConfig;        // Audio configuration parameters
    readonly buffer: Buffer;            // Raw audio data buffer
    readonly sequence: number;          // Packet sequence number (0-65535)
    readonly timestamp: number;         // Sample timestamp (microseconds)
    readonly checksum: string;          // Data integrity checksum
}

/**
 * Comprehensive stream status monitoring interface
 * Enables detailed performance tracking and diagnostics
 */
export interface AudioStreamStatus {
    readonly isActive: boolean;          // Stream active state
    readonly latency: number;           // Current stream latency (ms)
    readonly bufferLevel: number;       // Buffer fill level (0-100%)
    readonly dropouts: number;          // Count of audio dropouts
    readonly packetsLost: number;       // Count of lost packets
    readonly jitter: number;            // Packet timing jitter (ms)
    readonly clockDrift: number;        // Clock drift between endpoints (ppm)
    readonly bufferUnderruns: number;   // Buffer underrun count
    readonly bufferOverruns: number;    // Buffer overrun count
}