/**
 * Profile Entity for TALD UNIA Audio System
 * Implements comprehensive user profile storage with hardware configuration support
 * @version 1.0.0
 */

import { Entity, Column, PrimaryGeneratedColumn, OneToMany, CreateDateColumn, UpdateDateColumn, Index } from 'typeorm'; // v0.3.17
import { AudioSettings } from './audio-settings.entity';

@Entity('profiles')
@Index(['userId'])
@Index(['isDefault'])
export class Profile {
    @PrimaryGeneratedColumn('uuid')
    id: string;

    @Column('varchar', { length: 255 })
    userId: string;

    @Column('varchar', { length: 100 })
    name: string;

    @Column('jsonb')
    preferences: {
        theme: string;
        language: string;
        notifications: {
            enabled: boolean;
            types: string[];
        };
        hardware: {
            dacType: string;
            controllerType: string;
            amplifierSettings: {
                gainLimit: number;
                efficiencyTarget: number;
            };
            microphoneArray: {
                enabled: boolean;
                beamformingPreset: string;
            };
        };
        audioDefaults: {
            preferredSampleRate: number;
            preferredBitDepth: number;
            preferredBufferSize: number;
            processingQuality: string;
        };
        aiProcessing: {
            enabled: boolean;
            modelPreference: string;
            enhancementStrength: number;
        };
        spatialAudio: {
            enabled: boolean;
            hrtfProfile: string;
            roomSimulation: boolean;
        };
    };

    @Column('boolean', { default: false })
    isDefault: boolean;

    @OneToMany(() => AudioSettings, audioSettings => audioSettings.profileId, {
        cascade: ['insert', 'update'],
        eager: true
    })
    audioSettings: AudioSettings[];

    @CreateDateColumn({ type: 'timestamp with time zone' })
    createdAt: Date;

    @UpdateDateColumn({ type: 'timestamp with time zone' })
    updatedAt: Date;

    constructor(profile?: Partial<Profile>) {
        // Initialize with secure defaults
        this.preferences = {
            theme: 'system',
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
                },
                microphoneArray: {
                    enabled: false,
                    beamformingPreset: 'standard'
                }
            },
            audioDefaults: {
                preferredSampleRate: 192000,
                preferredBitDepth: 32,
                preferredBufferSize: 256,
                processingQuality: 'BALANCED'
            },
            aiProcessing: {
                enabled: true,
                modelPreference: 'standard',
                enhancementStrength: 0.5
            },
            spatialAudio: {
                enabled: false,
                hrtfProfile: 'generic',
                roomSimulation: false
            }
        };

        // Override defaults with provided profile data if valid
        if (profile) {
            if (profile.preferences && this.validatePreferences(profile.preferences)) {
                this.preferences = { ...this.preferences, ...profile.preferences };
            }
            if (profile.name) this.name = profile.name;
            if (profile.userId) this.userId = profile.userId;
            if (typeof profile.isDefault === 'boolean') this.isDefault = profile.isDefault;
        }
    }

    /**
     * Validates preferences schema against hardware requirements
     * @param preferences - Profile preferences to validate
     * @returns boolean indicating if preferences are valid
     */
    private validatePreferences(preferences: any): boolean {
        // Validate hardware configuration
        if (preferences.hardware) {
            if (!['ES9038PRO'].includes(preferences.hardware.dacType)) {
                return false;
            }
            if (!['XMOS_XU316'].includes(preferences.hardware.controllerType)) {
                return false;
            }
            if (preferences.hardware.amplifierSettings) {
                const { gainLimit, efficiencyTarget } = preferences.hardware.amplifierSettings;
                if (typeof gainLimit !== 'number' || gainLimit < -12 || gainLimit > 12) {
                    return false;
                }
                if (typeof efficiencyTarget !== 'number' || efficiencyTarget < 0 || efficiencyTarget > 1) {
                    return false;
                }
            }
        }

        // Validate audio defaults
        if (preferences.audioDefaults) {
            const validSampleRates = [44100, 48000, 88200, 96000, 176400, 192000];
            const validBitDepths = [16, 24, 32];
            const validBufferSizes = [64, 128, 256, 512, 1024];
            const validQualities = ['MAXIMUM', 'BALANCED', 'POWER_SAVER'];

            if (!validSampleRates.includes(preferences.audioDefaults.preferredSampleRate)) {
                return false;
            }
            if (!validBitDepths.includes(preferences.audioDefaults.preferredBitDepth)) {
                return false;
            }
            if (!validBufferSizes.includes(preferences.audioDefaults.preferredBufferSize)) {
                return false;
            }
            if (!validQualities.includes(preferences.audioDefaults.processingQuality)) {
                return false;
            }
        }

        // Validate AI processing settings
        if (preferences.aiProcessing) {
            if (typeof preferences.aiProcessing.enhancementStrength !== 'number' ||
                preferences.aiProcessing.enhancementStrength < 0 ||
                preferences.aiProcessing.enhancementStrength > 1) {
                return false;
            }
        }

        return true;
    }

    /**
     * Transforms profile entity to a secure JSON representation
     * @returns Filtered JSON representation of profile
     */
    toJSON(): object {
        return {
            id: this.id,
            userId: this.userId,
            name: this.name,
            preferences: this.preferences,
            isDefault: this.isDefault,
            audioSettings: this.audioSettings?.map(setting => setting.toJSON()),
            timestamps: {
                createdAt: this.createdAt,
                updatedAt: this.updatedAt
            }
        };
    }
}