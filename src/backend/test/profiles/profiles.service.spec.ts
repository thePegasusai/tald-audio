import { Test, TestingModule } from '@nestjs/testing'; // v10.2.0
import { getRepositoryToken } from '@nestjs/typeorm'; // v10.2.0
import { Repository } from 'typeorm'; // v0.3.17
import { ProfilesService } from '../../src/profiles/profiles.service';
import { Profile } from '../../src/profiles/entities/profile.entity';
import { AudioSettings } from '../../src/profiles/entities/audio-settings.entity';
import { ProcessingQuality, THD_TARGET, MAX_LATENCY_MS } from '../../src/audio/interfaces/audio-config.interface';
import { CreateProfileDto } from '../../src/profiles/dtos/create-profile.dto';
import { UpdateProfileDto } from '../../src/profiles/dtos/update-profile.dto';

describe('ProfilesService', () => {
  let service: ProfilesService;
  let profileRepository: Repository<Profile>;
  let audioSettingsRepository: Repository<AudioSettings>;

  // Mock profile data with hardware specifications
  const mockProfile = {
    id: '123e4567-e89b-12d3-a456-426614174000',
    userId: 'user123',
    name: 'Studio Reference',
    preferences: {
      hardware: {
        dacType: 'ES9038PRO',
        controllerType: 'XMOS_XU316',
        amplifierSettings: {
          gainLimit: 0,
          efficiencyTarget: 0.9
        }
      }
    },
    isDefault: false,
    audioSettings: [{
      id: 'audio123',
      profileId: '123e4567-e89b-12d3-a456-426614174000',
      sampleRate: 192000,
      bitDepth: 32,
      channels: 2,
      bufferSize: 256,
      processingQuality: ProcessingQuality.Maximum,
      dspConfig: {
        enableEQ: true,
        eqBands: [],
        enableCompression: false,
        thdCompensation: true
      },
      aiConfig: {
        enableEnhancement: true,
        modelType: 'standard',
        enhancementStrength: 0.5,
        latencyBudget: 5
      },
      spatialConfig: {
        enable3DAudio: false,
        hrtfProfile: 'generic',
        roomSimulation: false
      },
      hardwareConfig: {
        dacType: 'ES9038PRO',
        controllerType: 'XMOS_XU316'
      }
    }]
  };

  beforeEach(async () => {
    const module: TestingModule = await Test.createTestingModule({
      providers: [
        ProfilesService,
        {
          provide: getRepositoryToken(Profile),
          useClass: Repository
        },
        {
          provide: getRepositoryToken(AudioSettings),
          useClass: Repository
        },
        {
          provide: 'DataSource',
          useValue: {
            createQueryRunner: jest.fn().mockReturnValue({
              connect: jest.fn(),
              startTransaction: jest.fn(),
              commitTransaction: jest.fn(),
              rollbackTransaction: jest.fn(),
              release: jest.fn(),
              manager: {
                save: jest.fn(),
                update: jest.fn(),
                delete: jest.fn()
              }
            })
          }
        }
      ]
    }).compile();

    service = module.get<ProfilesService>(ProfilesService);
    profileRepository = module.get<Repository<Profile>>(getRepositoryToken(Profile));
    audioSettingsRepository = module.get<Repository<AudioSettings>>(getRepositoryToken(AudioSettings));
  });

  describe('create', () => {
    it('should create profile with valid hardware configuration', async () => {
      const createDto = new CreateProfileDto();
      Object.assign(createDto, {
        name: 'Studio Reference',
        userId: 'user123',
        audioSettings: {
          sampleRate: 192000,
          bitDepth: 32,
          bufferSize: 256,
          processingQuality: ProcessingQuality.Maximum,
          dspConfig: {
            enableEQ: true,
            thdCompensation: true
          }
        }
      });

      jest.spyOn(profileRepository, 'save').mockResolvedValue(mockProfile as Profile);
      
      const result = await service.create(createDto);
      expect(result).toBeDefined();
      expect(result.audioSettings[0].sampleRate).toBe(192000);
      expect(result.audioSettings[0].dspConfig.thdCompensation).toBe(true);
    });

    it('should reject invalid hardware configurations', async () => {
      const createDto = new CreateProfileDto();
      Object.assign(createDto, {
        name: 'Invalid Config',
        userId: 'user123',
        audioSettings: {
          sampleRate: 200000, // Invalid for ES9038PRO
          bitDepth: 32,
          bufferSize: 256
        }
      });

      await expect(service.create(createDto)).rejects.toThrow();
    });

    it('should validate THD+N requirements', async () => {
      const createDto = new CreateProfileDto();
      Object.assign(createDto, {
        name: 'High Quality',
        userId: 'user123',
        audioSettings: {
          processingQuality: ProcessingQuality.Maximum,
          dspConfig: {
            thdCompensation: false // Should fail THD requirement
          }
        }
      });

      await expect(service.create(createDto)).rejects.toThrow();
    });
  });

  describe('update', () => {
    it('should update profile maintaining hardware compatibility', async () => {
      const updateDto = new UpdateProfileDto();
      Object.assign(updateDto, {
        name: 'Updated Profile',
        audioSettings: {
          sampleRate: 96000,
          bitDepth: 24,
          bufferSize: 128
        }
      });

      jest.spyOn(profileRepository, 'findOne').mockResolvedValue(mockProfile as Profile);
      jest.spyOn(profileRepository, 'save').mockResolvedValue({
        ...mockProfile,
        name: 'Updated Profile'
      } as Profile);

      const result = await service.update(mockProfile.id, updateDto);
      expect(result.name).toBe('Updated Profile');
      expect(result.audioSettings[0].sampleRate).toBe(96000);
    });

    it('should reject updates violating latency requirements', async () => {
      const updateDto = new UpdateProfileDto();
      Object.assign(updateDto, {
        audioSettings: {
          bufferSize: 2048, // Will exceed 10ms latency
          sampleRate: 48000
        }
      });

      jest.spyOn(profileRepository, 'findOne').mockResolvedValue(mockProfile as Profile);

      await expect(service.update(mockProfile.id, updateDto)).rejects.toThrow();
    });
  });

  describe('findAll', () => {
    it('should return paginated profiles with hardware details', async () => {
      const mockProfiles = [mockProfile];
      const mockPaginatedResponse = {
        data: mockProfiles,
        meta: {
          page: 1,
          take: 10,
          itemCount: 1,
          pageCount: 1,
          hasPreviousPage: false,
          hasNextPage: false
        }
      };

      jest.spyOn(profileRepository, 'findAndCount').mockResolvedValue([mockProfiles as Profile[], 1]);

      const result = await service.findAll(1, 10);
      expect(result).toEqual(mockPaginatedResponse);
      expect(result.data[0].audioSettings[0].hardwareConfig.dacType).toBe('ES9038PRO');
    });

    it('should apply hardware compatibility filters', async () => {
      const filters = {
        'audioSettings.hardwareConfig.dacType': 'ES9038PRO'
      };

      jest.spyOn(profileRepository, 'findAndCount').mockResolvedValue([[mockProfile as Profile], 1]);

      const result = await service.findAll(1, 10, filters);
      expect(result.data[0].audioSettings[0].hardwareConfig.dacType).toBe('ES9038PRO');
    });
  });

  describe('findOne', () => {
    it('should return profile with validated hardware settings', async () => {
      jest.spyOn(profileRepository, 'findOne').mockResolvedValue(mockProfile as Profile);

      const result = await service.findOne(mockProfile.id);
      expect(result).toBeDefined();
      expect(result.audioSettings[0].hardwareConfig.dacType).toBe('ES9038PRO');
      expect(result.audioSettings[0].dspConfig.thdCompensation).toBe(true);
    });

    it('should validate current hardware compatibility', async () => {
      const incompatibleProfile = {
        ...mockProfile,
        audioSettings: [{
          ...mockProfile.audioSettings[0],
          hardwareConfig: {
            dacType: 'INVALID_DAC'
          }
        }]
      };

      jest.spyOn(profileRepository, 'findOne').mockResolvedValue(incompatibleProfile as Profile);

      await expect(service.findOne(mockProfile.id)).rejects.toThrow();
    });
  });

  describe('remove', () => {
    it('should remove profile and associated settings', async () => {
      const queryRunner = {
        connect: jest.fn(),
        startTransaction: jest.fn(),
        commitTransaction: jest.fn(),
        rollbackTransaction: jest.fn(),
        release: jest.fn(),
        manager: {
          delete: jest.fn()
        }
      };

      jest.spyOn(queryRunner.manager, 'delete').mockResolvedValue(undefined);

      await service.remove(mockProfile.id);
      expect(queryRunner.manager.delete).toHaveBeenCalledTimes(2);
    });
  });
});