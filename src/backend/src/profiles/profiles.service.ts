import { Injectable } from '@nestjs/common'; // v10.2.0
import { InjectRepository } from '@nestjs/typeorm'; // v10.2.0
import { Repository, FindOptionsWhere, QueryRunner, DataSource } from 'typeorm'; // v0.3.17
import { Profile } from './entities/profile.entity';
import { AudioSettings } from './entities/audio-settings.entity';
import { CreateProfileDto } from './dtos/create-profile.dto';
import { UpdateProfileDto } from './dtos/update-profile.dto';
import { PaginatedResponse } from '../common/interfaces/paginated-response.interface';
import { ProcessingQuality, THD_TARGET, MAX_LATENCY_MS } from '../audio/interfaces/audio-config.interface';

@Injectable()
export class ProfilesService {
    constructor(
        @InjectRepository(Profile)
        private readonly profileRepository: Repository<Profile>,
        @InjectRepository(AudioSettings)
        private readonly audioSettingsRepository: Repository<AudioSettings>,
        private readonly dataSource: DataSource
    ) {}

    /**
     * Creates a new user profile with hardware validation
     * @param createProfileDto - Profile creation data
     * @returns Newly created profile
     */
    async create(createProfileDto: CreateProfileDto): Promise<Profile> {
        const queryRunner = this.dataSource.createQueryRunner();
        await queryRunner.connect();
        await queryRunner.startTransaction();

        try {
            // Validate hardware compatibility
            const audioSettings = createProfileDto.audioSettings;
            if (!this.validateHardwareRequirements(audioSettings)) {
                throw new Error('Audio settings do not meet hardware requirements');
            }

            // Check performance requirements
            if (!this.validatePerformanceConstraints(audioSettings)) {
                throw new Error('Audio settings do not meet performance requirements');
            }

            // Handle default profile setting
            if (createProfileDto.isDefault) {
                await this.clearExistingDefaultProfiles(queryRunner, createProfileDto.userId);
            }

            // Create profile entity
            const profile = createProfileDto.toEntity();
            const savedProfile = await queryRunner.manager.save(Profile, profile);

            // Create audio settings with hardware validation
            const audioSettingsEntity = profile.audioSettings[0];
            audioSettingsEntity.profileId = savedProfile.id;
            await queryRunner.manager.save(AudioSettings, audioSettingsEntity);

            await queryRunner.commitTransaction();
            return savedProfile;

        } catch (error) {
            await queryRunner.rollbackTransaction();
            throw error;
        } finally {
            await queryRunner.release();
        }
    }

    /**
     * Retrieves paginated list of profiles with performance metrics
     * @param page - Page number
     * @param limit - Items per page
     * @param filters - Optional profile filters
     * @returns Paginated profile response
     */
    async findAll(
        page: number = 1,
        limit: number = 10,
        filters?: FindOptionsWhere<Profile>
    ): Promise<PaginatedResponse<Profile>> {
        const [profiles, total] = await this.profileRepository.findAndCount({
            where: filters,
            skip: (page - 1) * limit,
            take: limit,
            relations: ['audioSettings'],
            order: {
                createdAt: 'DESC'
            }
        });

        const pageCount = Math.ceil(total / limit);

        return {
            data: profiles,
            meta: {
                page,
                take: limit,
                itemCount: profiles.length,
                pageCount,
                hasPreviousPage: page > 1,
                hasNextPage: page < pageCount
            }
        };
    }

    /**
     * Retrieves a single profile by ID with hardware validation
     * @param id - Profile ID
     * @returns Profile with validated settings
     */
    async findOne(id: string): Promise<Profile> {
        const profile = await this.profileRepository.findOne({
            where: { id },
            relations: ['audioSettings']
        });

        if (!profile) {
            throw new Error('Profile not found');
        }

        // Validate current hardware compatibility
        if (!this.validateHardwareRequirements(profile.audioSettings[0])) {
            throw new Error('Profile settings incompatible with current hardware');
        }

        return profile;
    }

    /**
     * Updates profile with hardware validation
     * @param id - Profile ID
     * @param updateProfileDto - Profile update data
     * @returns Updated profile
     */
    async update(id: string, updateProfileDto: UpdateProfileDto): Promise<Profile> {
        const queryRunner = this.dataSource.createQueryRunner();
        await queryRunner.connect();
        await queryRunner.startTransaction();

        try {
            const existingProfile = await this.findOne(id);
            
            // Handle default profile updates
            if (updateProfileDto.isDefault) {
                await this.clearExistingDefaultProfiles(queryRunner, existingProfile.userId);
            }

            // Validate hardware compatibility for updates
            if (updateProfileDto.audioSettings) {
                const mergedSettings = {
                    ...existingProfile.audioSettings[0],
                    ...updateProfileDto.audioSettings
                };

                if (!this.validateHardwareRequirements(mergedSettings)) {
                    throw new Error('Updated audio settings do not meet hardware requirements');
                }

                if (!this.validatePerformanceConstraints(mergedSettings)) {
                    throw new Error('Updated settings do not meet performance requirements');
                }

                // Update audio settings
                await queryRunner.manager.update(
                    AudioSettings,
                    { profileId: id },
                    updateProfileDto.audioSettings
                );
            }

            // Update profile
            const updatedProfile = updateProfileDto.toEntity(existingProfile);
            await queryRunner.manager.save(Profile, updatedProfile);

            await queryRunner.commitTransaction();
            return this.findOne(id);

        } catch (error) {
            await queryRunner.rollbackTransaction();
            throw error;
        } finally {
            await queryRunner.release();
        }
    }

    /**
     * Removes a profile and associated settings
     * @param id - Profile ID
     */
    async remove(id: string): Promise<void> {
        const queryRunner = this.dataSource.createQueryRunner();
        await queryRunner.connect();
        await queryRunner.startTransaction();

        try {
            await queryRunner.manager.delete(AudioSettings, { profileId: id });
            await queryRunner.manager.delete(Profile, id);
            await queryRunner.commitTransaction();
        } catch (error) {
            await queryRunner.rollbackTransaction();
            throw error;
        } finally {
            await queryRunner.release();
        }
    }

    /**
     * Validates hardware compatibility requirements
     * @param settings - Audio settings to validate
     * @returns boolean indicating if requirements are met
     */
    private validateHardwareRequirements(settings: any): boolean {
        // Validate sample rate compatibility with ES9038PRO DAC
        if (![44100, 48000, 88200, 96000, 176400, 192000].includes(settings.sampleRate)) {
            return false;
        }

        // Validate bit depth support
        if (![16, 24, 32].includes(settings.bitDepth)) {
            return false;
        }

        // Validate buffer size for latency requirements
        const latencyMs = (settings.bufferSize / settings.sampleRate) * 1000;
        if (latencyMs > MAX_LATENCY_MS) {
            return false;
        }

        // Validate hardware-specific configurations
        if (settings.hardwareConfig) {
            if (settings.hardwareConfig.dacType !== 'ES9038PRO' ||
                settings.hardwareConfig.controllerType !== 'XMOS_XU316') {
                return false;
            }
        }

        return true;
    }

    /**
     * Validates performance constraints for audio processing
     * @param settings - Audio settings to validate
     * @returns boolean indicating if performance requirements are met
     */
    private validatePerformanceConstraints(settings: any): boolean {
        // Validate THD compensation for high quality
        if (settings.processingQuality === ProcessingQuality.Maximum &&
            (!settings.dspConfig?.thdCompensation || 
             !settings.dspConfig?.enableEQ)) {
            return false;
        }

        // Validate AI processing constraints
        if (settings.aiConfig?.enableEnhancement) {
            if (settings.aiConfig.latencyBudget > MAX_LATENCY_MS ||
                settings.aiConfig.enhancementStrength > 1.0) {
                return false;
            }
        }

        // Validate spatial audio processing
        if (settings.spatialConfig?.enable3DAudio &&
            settings.bufferSize < 256) {
            return false;
        }

        return true;
    }

    /**
     * Clears existing default profiles for a user
     * @param queryRunner - Database query runner
     * @param userId - User ID
     */
    private async clearExistingDefaultProfiles(
        queryRunner: QueryRunner,
        userId: string
    ): Promise<void> {
        await queryRunner.manager.update(
            Profile,
            { userId, isDefault: true },
            { isDefault: false }
        );
    }
}