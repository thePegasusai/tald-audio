/**
 * AudioSettings Entity for TALD UNIA Audio System
 * Implements comprehensive audio configuration storage with hardware integration
 * @version 1.0.0
 */

import { Entity, Column, PrimaryGeneratedColumn, ManyToOne, JoinColumn, Index } from 'typeorm'; // v0.3.17
import { 
    AudioConfig,
    ProcessingQuality,
    DEFAULT_SAMPLE_RATE,
    DEFAULT_BIT_DEPTH,
    DEFAULT_CHANNELS,
    DEFAULT_BUFFER_SIZE,
    THD_TARGET,
    MAX_LATENCY_MS
} from '../../audio/interfaces/audio-config.interface';

@Entity('audio_settings')
@Index(['profileId', 'isActive'])
@Index(['createdAt'])
export class AudioSettings {
    @PrimaryGeneratedColumn('uuid')
    id: string;

    @Column('uuid')
    profileId: string;

    @Column('int')
    sampleRate: number;

    @Column('int')
    bitDepth: number;

    @Column('int')
    channels: number;

    @Column('int')
    bufferSize: number;

    @Column('enum', { enum: ProcessingQuality })
    processingQuality: ProcessingQuality;

    @Column('jsonb')
    dspConfig: {
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

    @Column('jsonb')
    aiConfig: {
        enableEnhancement: boolean;
        modelType: string;
        enhancementStrength: number;
        latencyBudget: number;
        processingMode: string;
    };

    @Column('jsonb')
    spatialConfig: {
        enable3DAudio: boolean;
        hrtfProfile: string;
        roomSimulation: boolean;
        headTracking: boolean;
        speakerVirtualization: boolean;
    };

    @Column('jsonb')
    hardwareConfig: {
        dacType: string;
        controllerType: string;
        amplifierConfig: {
            type: string;
            gain: number;
            efficiency: number;
        };
        microphoneArray: {
            enabled: boolean;
            beamforming: boolean;
            noiseReduction: boolean;
        };
    };

    @Column('boolean', { default: true })
    isActive: boolean;

    @Column('timestamp with time zone', { default: () => 'CURRENT_TIMESTAMP' })
    createdAt: Date;

    @Column('timestamp with time zone', { default: () => 'CURRENT_TIMESTAMP', onUpdate: 'CURRENT_TIMESTAMP' })
    updatedAt: Date;

    constructor(settings?: Partial<AudioSettings>) {
        // Initialize with hardware-optimized defaults
        this.sampleRate = DEFAULT_SAMPLE_RATE; // 192kHz for ES9038PRO DAC
        this.bitDepth = DEFAULT_BIT_DEPTH; // 32-bit for maximum precision
        this.channels = DEFAULT_CHANNELS; // Stereo default
        this.bufferSize = DEFAULT_BUFFER_SIZE; // 256 samples for <10ms latency
        this.processingQuality = ProcessingQuality.Balanced;

        // Initialize DSP configuration with THD compensation
        this.dspConfig = {
            enableEQ: true,
            eqBands: [],
            enableCompression: false,
            compressorSettings: {
                threshold: -20,
                ratio: 2,
                attack: 5,
                release: 50,
                makeupGain: 0,
                kneeWidth: 10
            },
            enableRoomCorrection: false,
            roomConfig: {
                roomSize: 0,
                reflectivity: 0.5,
                dampingFactor: 0.5,
                speakerPositions: [],
                measurementPoints: []
            },
            thdCompensation: true
        };

        // Initialize AI processing with latency constraints
        this.aiConfig = {
            enableEnhancement: true,
            modelType: 'standard',
            enhancementStrength: 0.5,
            latencyBudget: MAX_LATENCY_MS,
            processingMode: 'BALANCED'
        };

        // Initialize spatial audio configuration
        this.spatialConfig = {
            enable3DAudio: false,
            hrtfProfile: 'generic',
            roomSimulation: false,
            headTracking: false,
            speakerVirtualization: false
        };

        // Initialize hardware-specific configuration
        this.hardwareConfig = {
            dacType: 'ES9038PRO',
            controllerType: 'XMOS_XU316',
            amplifierConfig: {
                type: 'TAS5805M',
                gain: 0,
                efficiency: 0.9
            },
            microphoneArray: {
                enabled: false,
                beamforming: false,
                noiseReduction: false
            }
        };

        // Override defaults with provided settings
        if (settings) {
            Object.assign(this, settings);
        }
    }

    /**
     * Validates audio settings against hardware capabilities and performance requirements
     * @returns boolean indicating if settings are valid
     */
    validateSettings(): boolean {
        // Verify sample rate compatibility with ES9038PRO DAC
        if (![44100, 48000, 88200, 96000, 176400, 192000].includes(this.sampleRate)) {
            return false;
        }

        // Check buffer size for latency requirement
        const latencyMs = (this.bufferSize / this.sampleRate) * 1000;
        if (latencyMs > MAX_LATENCY_MS) {
            return false;
        }

        // Validate DSP parameters for THD+N target
        if (this.dspConfig.thdCompensation && !this.dspConfig.enableEQ) {
            return false;
        }

        // Verify AI processing constraints
        if (this.aiConfig.enableEnhancement && 
            this.aiConfig.latencyBudget > MAX_LATENCY_MS) {
            return false;
        }

        return true;
    }

    /**
     * Transforms audio settings to a validated JSON representation
     * @returns Formatted settings object
     */
    toJSON(): object {
        return {
            id: this.id,
            profileId: this.profileId,
            audioConfig: {
                sampleRate: this.sampleRate,
                bitDepth: this.bitDepth,
                channels: this.channels,
                bufferSize: this.bufferSize,
                processingQuality: this.processingQuality
            },
            dspConfig: this.dspConfig,
            aiConfig: this.aiConfig,
            spatialConfig: this.spatialConfig,
            hardwareConfig: this.hardwareConfig,
            performance: {
                latencyMs: (this.bufferSize / this.sampleRate) * 1000,
                thdTarget: THD_TARGET,
                isActive: this.isActive
            },
            timestamps: {
                createdAt: this.createdAt,
                updatedAt: this.updatedAt
            }
        };
    }
}