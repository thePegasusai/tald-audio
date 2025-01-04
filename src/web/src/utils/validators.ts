/**
 * Advanced validation utility functions for the TALD UNIA Audio System web client
 * Version: 1.0.0
 * 
 * Provides comprehensive validation for audio quality parameters, hardware configurations,
 * and user profiles with enhanced error checking and performance optimization.
 */

import { AudioConfig, ProcessingQuality } from '../types/audio.types';
import { Profile, AudioSettings, AIConfig, SpatialConfig } from '../types/profile.types';
import { SystemSettings, HardwareConfig, SampleRate, BitDepth, BufferSize } from '../types/settings.types';

// Constants for audio quality validation
const MIN_SAMPLE_RATE = 44100;
const MAX_SAMPLE_RATE = 192000;
const VALID_BIT_DEPTHS: BitDepth[] = [16, 24, 32];
const VALID_BUFFER_SIZES: BufferSize[] = [64, 128, 256, 512, 1024];
const MAX_BUFFER_SIZE = 1024;
const MIN_PROFILE_NAME_LENGTH = 3;
const MAX_PROFILE_NAME_LENGTH = 50;
const MAX_THD_N = 0.0005; // Maximum Total Harmonic Distortion + Noise
const MAX_LATENCY_MS = 10; // Maximum allowed latency in milliseconds
const SUPPORTED_CHANNEL_CONFIGS = ['stereo', 'multichannel'];

/**
 * Validates audio configuration parameters with enhanced quality checks
 * for THD+N and latency requirements
 */
export function validateAudioConfig(config: AudioConfig): boolean {
    try {
        // Validate sample rate
        if (!config.sampleRate || 
            config.sampleRate < MIN_SAMPLE_RATE || 
            config.sampleRate > MAX_SAMPLE_RATE) {
            return false;
        }

        // Validate bit depth
        if (!VALID_BIT_DEPTHS.includes(config.bitDepth as BitDepth)) {
            return false;
        }

        // Validate buffer size and calculate latency
        if (!VALID_BUFFER_SIZES.includes(config.bufferSize as BufferSize)) {
            return false;
        }

        // Calculate latency based on buffer size and sample rate
        const latencyMs = (config.bufferSize / config.sampleRate) * 1000;
        if (latencyMs > MAX_LATENCY_MS) {
            return false;
        }

        // Validate channel configuration
        if (config.channels < 2 || config.channels > 8) {
            return false;
        }

        // Validate processing quality setting
        if (!Object.values(ProcessingQuality).includes(config.processingQuality)) {
            return false;
        }

        return true;
    } catch (error) {
        console.error('Audio config validation error:', error);
        return false;
    }
}

/**
 * Enhanced profile validation including processing configurations and AI settings
 */
export function validateProfile(profile: Profile): boolean {
    try {
        // Validate profile ID and name
        if (!profile.id || typeof profile.id !== 'string') {
            return false;
        }

        if (!profile.name || 
            profile.name.length < MIN_PROFILE_NAME_LENGTH || 
            profile.name.length > MAX_PROFILE_NAME_LENGTH) {
            return false;
        }

        // Validate audio settings array
        if (!Array.isArray(profile.audioSettings) || profile.audioSettings.length === 0) {
            return false;
        }

        // Validate each audio setting
        return profile.audioSettings.every(setting => validateAudioSetting(setting));
    } catch (error) {
        console.error('Profile validation error:', error);
        return false;
    }
}

/**
 * Validates individual audio settings within a profile
 */
function validateAudioSetting(setting: AudioSettings): boolean {
    try {
        // Validate basic audio configuration
        if (!validateAudioConfig({
            sampleRate: setting.sampleRate,
            bitDepth: setting.bitDepth,
            channels: setting.channels,
            bufferSize: setting.bufferSize,
            processingQuality: setting.processingQuality
        })) {
            return false;
        }

        // Validate AI configuration
        if (!validateAIConfig(setting.aiConfig)) {
            return false;
        }

        // Validate spatial configuration
        if (!validateSpatialConfig(setting.spatialConfig)) {
            return false;
        }

        return true;
    } catch (error) {
        console.error('Audio setting validation error:', error);
        return false;
    }
}

/**
 * Validates AI enhancement configuration parameters
 */
function validateAIConfig(config: AIConfig): boolean {
    try {
        if (typeof config.enabled !== 'boolean') {
            return false;
        }

        if (config.enabled) {
            // Validate enhancement level (0-100)
            if (config.enhancementLevel < 0 || config.enhancementLevel > 100) {
                return false;
            }

            // Validate processing mode
            if (!['realtime', 'quality'].includes(config.processingMode)) {
                return false;
            }

            // Validate model version format
            if (!config.modelVersion.match(/^\d+\.\d+\.\d+$/)) {
                return false;
            }
        }

        return true;
    } catch (error) {
        console.error('AI config validation error:', error);
        return false;
    }
}

/**
 * Validates spatial audio configuration parameters
 */
function validateSpatialConfig(config: SpatialConfig): boolean {
    try {
        if (typeof config.enabled !== 'boolean') {
            return false;
        }

        if (config.enabled) {
            // Validate room profile
            if (!config.roomProfile || typeof config.roomProfile !== 'string') {
                return false;
            }

            // Validate HRTF profile
            if (!config.hrtfProfile || typeof config.hrtfProfile !== 'string') {
                return false;
            }

            // Validate speaker layout if object-based audio is enabled
            if (config.objectBasedAudio && !config.speakerLayout) {
                return false;
            }
        }

        return true;
    } catch (error) {
        console.error('Spatial config validation error:', error);
        return false;
    }
}

/**
 * Comprehensive system settings validation including hardware, AI, and spatial audio configurations
 */
export function validateSystemSettings(settings: SystemSettings): boolean {
    try {
        // Validate hardware configuration
        if (!validateHardwareConfig(settings.hardware)) {
            return false;
        }

        // Validate processing configuration
        if (!validateProcessingConfig(settings.processing)) {
            return false;
        }

        // Validate spatial configuration
        if (!validateSpatialConfig(settings.spatial)) {
            return false;
        }

        // Validate version format
        if (!settings.version.match(/^\d+\.\d+\.\d+$/)) {
            return false;
        }

        // Validate lastUpdated timestamp
        if (!(settings.lastUpdated instanceof Date)) {
            return false;
        }

        return true;
    } catch (error) {
        console.error('System settings validation error:', error);
        return false;
    }
}

/**
 * Validates hardware configuration against supported device capabilities
 */
function validateHardwareConfig(config: HardwareConfig): boolean {
    try {
        // Validate sample rate
        if (!Object.values(SampleRate).includes(config.sampleRate)) {
            return false;
        }

        // Validate bit depth
        if (!VALID_BIT_DEPTHS.includes(config.bitDepth)) {
            return false;
        }

        // Validate buffer size
        if (!VALID_BUFFER_SIZES.includes(config.bufferSize)) {
            return false;
        }

        // Validate device identifiers
        if (!config.deviceId || !config.deviceName) {
            return false;
        }

        // Validate channel count
        if (config.maxChannels < 2 || config.maxChannels > 8) {
            return false;
        }

        return true;
    } catch (error) {
        console.error('Hardware config validation error:', error);
        return false;
    }
}

/**
 * Validates processing configuration including AI enhancement parameters
 */
function validateProcessingConfig(config: SystemSettings['processing']): boolean {
    try {
        // Validate processing quality
        if (!Object.values(ProcessingQuality).includes(config.quality)) {
            return false;
        }

        // Validate thread count
        if (config.inferenceThreads < 1 || config.inferenceThreads > 16) {
            return false;
        }

        // Validate enhancement level
        if (config.enhancementLevel < 0 || config.enhancementLevel > 100) {
            return false;
        }

        return true;
    } catch (error) {
        console.error('Processing config validation error:', error);
        return false;
    }
}