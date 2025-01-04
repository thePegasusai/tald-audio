import { Controller, Get, Post, Put, Delete, Body, Param, Query, UseGuards, UseInterceptors, Logger, HttpStatus, BadRequestException, NotFoundException } from '@nestjs/common'; // v10.2.0
import { ApiTags, ApiOperation, ApiParam, ApiQuery, ApiResponse } from '@nestjs/swagger'; // v7.1.0
import { ProfilesService } from './profiles.service';
import { CreateProfileDto } from './dtos/create-profile.dto';
import { UpdateProfileDto } from './dtos/update-profile.dto';
import { ApiResponseDecorator } from '../common/decorators/api-response.decorator';
import { Profile } from './entities/profile.entity';
import { PaginatedResponse } from '../common/interfaces/paginated-response.interface';
import { ProcessingQuality, THD_TARGET, MAX_LATENCY_MS } from '../audio/interfaces/audio-config.interface';

@Controller('profiles')
@ApiTags('profiles')
@UseGuards(JwtAuthGuard)
@UseInterceptors(PerformanceInterceptor)
export class ProfilesController {
    private readonly logger = new Logger(ProfilesController.name);

    constructor(private readonly profilesService: ProfilesService) {}

    @Post()
    @ApiOperation({ summary: 'Create new audio profile with hardware validation' })
    @ApiResponseDecorator({
        type: Profile,
        status: HttpStatus.CREATED,
        description: 'Profile created successfully with validated audio settings'
    })
    @ApiResponse({ 
        status: HttpStatus.BAD_REQUEST, 
        description: 'Invalid hardware configuration or audio settings'
    })
    async create(@Body() createProfileDto: CreateProfileDto): Promise<Profile> {
        this.logger.debug(`Creating new profile for user: ${createProfileDto.userId}`);

        // Validate hardware compatibility
        const isHardwareCompatible = await this.profilesService.validateHardwareCompatibility(
            createProfileDto.audioSettings
        );
        if (!isHardwareCompatible) {
            throw new BadRequestException('Audio settings incompatible with hardware capabilities');
        }

        // Validate audio quality requirements
        const meetsQualityStandards = await this.profilesService.validateAudioQuality({
            thdTarget: THD_TARGET,
            maxLatency: MAX_LATENCY_MS,
            settings: createProfileDto.audioSettings
        });
        if (!meetsQualityStandards) {
            throw new BadRequestException('Audio settings do not meet quality requirements');
        }

        return this.profilesService.create(createProfileDto);
    }

    @Get()
    @ApiOperation({ summary: 'Retrieve paginated list of audio profiles' })
    @ApiQuery({ name: 'page', required: false, type: Number })
    @ApiQuery({ name: 'limit', required: false, type: Number })
    @ApiQuery({ name: 'userId', required: false, type: String })
    @ApiResponseDecorator({
        type: Profile,
        status: HttpStatus.OK,
        isPaginated: true,
        description: 'Successfully retrieved profiles list'
    })
    async findAll(
        @Query('page') page?: number,
        @Query('limit') limit?: number,
        @Query('userId') userId?: string
    ): Promise<PaginatedResponse<Profile>> {
        this.logger.debug(`Retrieving profiles page ${page} with limit ${limit}`);
        
        const filters = userId ? { userId } : undefined;
        return this.profilesService.findAll(page, limit, filters);
    }

    @Get(':id')
    @ApiOperation({ summary: 'Retrieve single audio profile by ID' })
    @ApiParam({ name: 'id', type: String })
    @ApiResponseDecorator({
        type: Profile,
        status: HttpStatus.OK,
        description: 'Successfully retrieved profile'
    })
    @ApiResponse({ 
        status: HttpStatus.NOT_FOUND, 
        description: 'Profile not found'
    })
    async findOne(@Param('id') id: string): Promise<Profile> {
        this.logger.debug(`Retrieving profile with ID: ${id}`);
        
        const profile = await this.profilesService.findOne(id);
        if (!profile) {
            throw new NotFoundException('Profile not found');
        }
        return profile;
    }

    @Put(':id')
    @ApiOperation({ summary: 'Update audio profile with hardware validation' })
    @ApiParam({ name: 'id', type: String })
    @ApiResponseDecorator({
        type: Profile,
        status: HttpStatus.OK,
        description: 'Profile updated successfully'
    })
    @ApiResponse({ 
        status: HttpStatus.BAD_REQUEST, 
        description: 'Invalid hardware configuration or audio settings'
    })
    async update(
        @Param('id') id: string,
        @Body() updateProfileDto: UpdateProfileDto
    ): Promise<Profile> {
        this.logger.debug(`Updating profile with ID: ${id}`);

        // Validate hardware compatibility if audio settings are updated
        if (updateProfileDto.audioSettings) {
            const isHardwareCompatible = await this.profilesService.validateHardwareCompatibility(
                updateProfileDto.audioSettings
            );
            if (!isHardwareCompatible) {
                throw new BadRequestException('Updated audio settings incompatible with hardware');
            }

            // Validate updated audio quality requirements
            const meetsQualityStandards = await this.profilesService.validateAudioQuality({
                thdTarget: THD_TARGET,
                maxLatency: MAX_LATENCY_MS,
                settings: updateProfileDto.audioSettings
            });
            if (!meetsQualityStandards) {
                throw new BadRequestException('Updated settings do not meet quality requirements');
            }
        }

        return this.profilesService.update(id, updateProfileDto);
    }

    @Delete(':id')
    @ApiOperation({ summary: 'Delete audio profile' })
    @ApiParam({ name: 'id', type: String })
    @ApiResponse({ status: HttpStatus.NO_CONTENT })
    @ApiResponse({ 
        status: HttpStatus.NOT_FOUND, 
        description: 'Profile not found'
    })
    async remove(@Param('id') id: string): Promise<void> {
        this.logger.debug(`Deleting profile with ID: ${id}`);
        
        const profile = await this.profilesService.findOne(id);
        if (!profile) {
            throw new NotFoundException('Profile not found');
        }
        await this.profilesService.remove(id);
    }
}