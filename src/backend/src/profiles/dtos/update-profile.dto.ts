import { IsString, IsOptional, IsBoolean, IsObject, ValidateNested, IsNumber, Max, Min } from 'class-validator'; // v0.14.0
import { Type } from 'class-transformer'; // v0.5.1
import { ApiProperty, PartialType } from '@nestjs/swagger'; // v7.1.0
import { Profile } from '../entities/profile.entity';
import { AudioSettings } from '../entities/audio-settings.entity';

export class UpdateProfileDto {
    @ApiProperty({
        description: 'Profile name',
        example: 'Studio Reference',
        maxLength: 100
    })
    @IsOptional()
    @IsString()
    name?: string;

    @ApiProperty({
        description: 'Profile preferences including hardware and audio settings',
        example: {
            theme: 'dark',
            language: 'en',
            notifications: {
                enabled: true,
                types: ['system', 'updates']
            },
            hardware: {
                dacType: 'ES9038PRO',
                controllerType: 'XMOS_XU316',
                amplifierSettings: {
                    gainLimit: 0,
                    efficiencyTarget: 0.9
                }
            }
        }
    })
    @IsOptional()
    @IsObject()
    preferences?: {
        theme?: string;
        language?: string;
        notifications?: {
            enabled: boolean;
            types: string[];
        };
        hardware?: {
            dacType: string;
            controllerType: string;
            amplifierSettings: {
                gainLimit: number;
                efficiencyTarget: number;
            };
            microphoneArray?: {
                enabled: boolean;
                beamformingPreset: string;
            };
        };
        audioDefaults?: {
            preferredSampleRate: number;
            preferredBitDepth: number;
            preferredBufferSize: number;
            processingQuality: string;
        };
        aiProcessing?: {
            enabled: boolean;
            modelPreference: string;
            enhancementStrength: number;
        };
        spatialAudio?: {
            enabled: boolean;
            hrtfProfile: string;
            roomSimulation: boolean;
        };
    };

    @ApiProperty({
        description: 'Set as default profile',
        example: false
    })
    @IsOptional()
    @IsBoolean()
    isDefault?: boolean;

    @ApiProperty({
        description: 'Audio settings configuration',
        type: () => AudioSettings
    })
    @IsOptional()
    @IsObject()
    @ValidateNested()
    @Type(() => AudioSettings)
    audioSettings?: {
        sampleRate?: number;
        bitDepth?: number;
        channels?: number;
        bufferSize?: number;
        processingQuality?: string;
        dspConfig?: {
            enableEQ: boolean;
            eqBands: Array<{
                frequency: number;
                gain: number;
                q: number;
                type: string;
            }>;
            enableCompression: boolean;
            compressorSettings: {
                threshold: number;
                ratio: number;
                attack: number;
                release: number;
                makeupGain: number;
                kneeWidth: number;
            };
            enableRoomCorrection: boolean;
            roomConfig: {
                roomSize: number;
                reflectivity: number;
                dampingFactor: number;
                speakerPositions: Array<{ x: number; y: number; z: number }>;
                measurementPoints: Array<{ x: number; y: number; z: number }>;
            };
            thdCompensation: boolean;
        };
        aiConfig?: {
            enableEnhancement: boolean;
            modelType: string;
            enhancementStrength: number;
            latencyBudget: number;
            processingMode: string;
        };
        spatialConfig?: {
            enable3DAudio: boolean;
            hrtfProfile: string;
            roomSimulation: boolean;
            headTracking: boolean;
            speakerVirtualization: boolean;
        };
    };

    @ApiProperty({
        description: 'Hardware-specific configuration',
        example: {
            dacType: 'ES9038PRO',
            controllerType: 'XMOS_XU316'
        }
    })
    @IsOptional()
    @IsObject()
    hardwareConfig?: {
        dacType: string;
        controllerType: string;
        amplifierConfig?: {
            type: string;
            gain: number;
            efficiency: number;
        };
        microphoneArray?: {
            enabled: boolean;
            beamforming: boolean;
            noiseReduction: boolean;
        };
    };

    /**
     * Converts DTO to partial Profile entity with hardware validation
     * @param existingProfile - Existing profile to merge with updates
     * @returns Partial Profile entity with validated settings
     */
    toEntity(existingProfile: Profile): Partial<Profile> {
        // Validate hardware compatibility if audio settings are provided
        if (this.audioSettings && !this.validateHardwareCompatibility(this.audioSettings)) {
            throw new Error('Invalid hardware configuration or audio settings');
        }

        // Create partial profile with validated updates
        const partialProfile: Partial<Profile> = {
            ...existingProfile,
            ...this
        };

        // Merge preferences while preserving existing structure
        if (this.preferences) {
            partialProfile.preferences = {
                ...existingProfile.preferences,
                ...this.preferences
            };
        }

        return partialProfile;
    }

    /**
     * Validates hardware-specific requirements and audio quality constraints
     * @param settings - Audio settings to validate
     * @returns boolean indicating hardware compatibility
     */
    private validateHardwareCompatibility(settings: any): boolean {
        // Validate sample rate (max 192kHz for ES9038PRO)
        if (settings.sampleRate && 
            ![44100, 48000, 88200, 96000, 176400, 192000].includes(settings.sampleRate)) {
            return false;
        }

        // Validate bit depth (max 32-bit)
        if (settings.bitDepth && ![16, 24, 32].includes(settings.bitDepth)) {
            return false;
        }

        // Validate buffer size for latency requirement (<10ms)
        if (settings.bufferSize && settings.sampleRate) {
            const latencyMs = (settings.bufferSize / settings.sampleRate) * 1000;
            if (latencyMs > 10) {
                return false;
            }
        }

        // Validate THD+N requirement (<0.0005%)
        if (settings.dspConfig?.thdCompensation === false) {
            return false;
        }

        // Validate AI processing latency
        if (settings.aiConfig?.latencyBudget > 10) {
            return false;
        }

        return true;
    }
}