/**
 * Data Transfer Object (DTO) for creating and validating new user profiles
 * Implements comprehensive validation for audio settings and hardware capabilities
 * @version 1.0.0
 */

import { IsString, IsNotEmpty, IsBoolean, IsObject, ValidateNested, IsNumber, Min, Max } from 'class-validator'; // v0.14.0
import { Type } from 'class-transformer'; // v0.5.1
import { ApiProperty } from '@nestjs/swagger'; // v7.1.0
import { Profile } from '../entities/profile.entity';
import { AudioSettings } from '../entities/audio-settings.entity';
import { AudioConfig, ProcessingQuality, MAX_LATENCY_MS, THD_TARGET } from '../../audio/interfaces/audio-config.interface';

/**
 * DTO for validating audio settings against hardware capabilities
 */
export class AudioSettingsDto {
    @IsNumber()
    @Min(44100)
    @Max(192000)
    @ApiProperty({ 
        description: 'Sample rate in Hz',
        example: 192000,
        minimum: 44100,
        maximum: 192000
    })
    sampleRate: number;

    @IsNumber()
    @Min(16)
    @Max(32)
    @ApiProperty({
        description: 'Bit depth',
        example: 32,
        minimum: 16,
        maximum: 32
    })
    bitDepth: number;

    @IsNumber()
    @Min(64)
    @Max(1024)
    @ApiProperty({
        description: 'Buffer size in samples',
        example: 256,
        minimum: 64,
        maximum: 1024
    })
    bufferSize: number;

    @IsString()
    @IsNotEmpty()
    @ApiProperty({
        description: 'Processing quality level',
        enum: ProcessingQuality,
        example: ProcessingQuality.Balanced
    })
    processingQuality: ProcessingQuality;

    @IsObject()
    @ApiProperty({
        description: 'DSP configuration parameters',
        example: {
            enableEQ: true,
            eqBands: [],
            enableCompression: false,
            thdCompensation: true
        }
    })
    dspConfig: {
        enableEQ: boolean;
        eqBands: Array<{
            frequency: number;
            gain: number;
            q: number;
            type: string;
        }>;
        enableCompression: boolean;
        thdCompensation: boolean;
    };

    @IsObject()
    @ApiProperty({
        description: 'AI enhancement configuration',
        example: {
            enableEnhancement: true,
            modelType: 'standard',
            enhancementStrength: 0.5
        }
    })
    aiConfig: {
        enableEnhancement: boolean;
        modelType: string;
        enhancementStrength: number;
    };

    @IsObject()
    @ApiProperty({
        description: 'Spatial audio configuration',
        example: {
            enable3DAudio: false,
            hrtfProfile: 'generic',
            roomSimulation: false
        }
    })
    spatialConfig: {
        enable3DAudio: boolean;
        hrtfProfile: string;
        roomSimulation: boolean;
    };

    /**
     * Validates settings against hardware capabilities
     * @param hardwareConfig - Audio hardware configuration
     * @returns boolean indicating if settings are compatible
     */
    validateHardwareCapabilities(hardwareConfig: AudioConfig): boolean {
        // Validate sample rate compatibility
        if (this.sampleRate > hardwareConfig.sampleRate) {
            return false;
        }

        // Validate bit depth support
        if (this.bitDepth > hardwareConfig.bitDepth) {
            return false;
        }

        // Validate buffer size constraints
        if (this.bufferSize < hardwareConfig.bufferSize || 
            this.bufferSize > 1024) {
            return false;
        }

        // Calculate latency
        const latencyMs = (this.bufferSize / this.sampleRate) * 1000;
        if (latencyMs > MAX_LATENCY_MS) {
            return false;
        }

        return true;
    }

    /**
     * Validates settings meet performance requirements
     * @returns boolean indicating if performance criteria are met
     */
    validatePerformanceRequirements(): boolean {
        // Validate latency requirements
        const latencyMs = (this.bufferSize / this.sampleRate) * 1000;
        if (latencyMs > MAX_LATENCY_MS) {
            return false;
        }

        // Validate THD compensation for high quality
        if (this.processingQuality === ProcessingQuality.Maximum && 
            !this.dspConfig.thdCompensation) {
            return false;
        }

        // Validate AI processing constraints
        if (this.aiConfig.enableEnhancement && 
            this.aiConfig.enhancementStrength > 1.0) {
            return false;
        }

        return true;
    }
}

/**
 * DTO for creating new user profiles with comprehensive validation
 */
export class CreateProfileDto {
    @IsString()
    @IsNotEmpty()
    @ApiProperty({
        description: 'Profile name',
        example: 'Studio Profile'
    })
    name: string;

    @IsString()
    @IsNotEmpty()
    @ApiProperty({
        description: 'User ID',
        example: '123e4567-e89b-12d3-a456-426614174000'
    })
    userId: string;

    @IsObject()
    @ApiProperty({
        description: 'User preferences',
        example: {
            theme: 'dark',
            language: 'en'
        }
    })
    preferences: Record<string, any>;

    @IsBoolean()
    @ApiProperty({
        description: 'Set as default profile',
        example: false
    })
    isDefault: boolean;

    @ValidateNested()
    @Type(() => AudioSettingsDto)
    @ApiProperty({
        description: 'Audio settings configuration',
        type: () => AudioSettingsDto
    })
    audioSettings: AudioSettingsDto;

    /**
     * Converts validated DTO to Profile entity
     * @returns New Profile entity instance
     */
    toEntity(): Profile {
        const profile = new Profile({
            name: this.name,
            userId: this.userId,
            preferences: this.preferences,
            isDefault: this.isDefault
        });

        const audioSettings = new AudioSettings({
            sampleRate: this.audioSettings.sampleRate,
            bitDepth: this.audioSettings.bitDepth,
            bufferSize: this.audioSettings.bufferSize,
            processingQuality: this.audioSettings.processingQuality,
            dspConfig: this.audioSettings.dspConfig,
            aiConfig: this.audioSettings.aiConfig,
            spatialConfig: this.audioSettings.spatialConfig
        });

        profile.audioSettings = [audioSettings];
        return profile;
    }
}