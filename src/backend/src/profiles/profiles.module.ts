import { Module } from '@nestjs/common'; // v10.2.0
import { TypeOrmModule } from '@nestjs/typeorm'; // v10.2.0
import { CacheModule } from '@nestjs/cache-manager'; // v2.0.0
import { ProfilesService } from './profiles.service';
import { ProfilesController } from './profiles.controller';
import { Profile } from './entities/profile.entity';
import { AudioSettings } from './entities/audio-settings.entity';

/**
 * NestJS module for configuring and exposing profile management functionality
 * in the TALD UNIA Audio System. Implements comprehensive profile management
 * with hardware validation and performance monitoring capabilities.
 * 
 * Features:
 * - Profile CRUD operations with hardware validation
 * - Audio settings management with quality assurance
 * - Performance monitoring and caching
 * - Hardware compatibility checks
 * 
 * @version 1.0.0
 */
@Module({
  imports: [
    // Configure TypeORM for Profile and AudioSettings entities
    TypeOrmModule.forFeature([Profile, AudioSettings]),

    // Configure caching with 5-minute TTL and 1000 items limit
    CacheModule.register({
      ttl: 300, // 5 minutes in seconds
      max: 1000, // Maximum number of cached items
      isGlobal: true
    })
  ],
  controllers: [ProfilesController],
  providers: [
    ProfilesService,
    // Add any additional providers needed for hardware validation
    {
      provide: 'HARDWARE_CONFIG',
      useValue: {
        dacType: 'ES9038PRO',
        controllerType: 'XMOS_XU316',
        maxSampleRate: 192000,
        maxBitDepth: 32,
        minBufferSize: 64,
        maxBufferSize: 1024,
        thdTarget: 0.0005,
        maxLatencyMs: 10
      }
    },
    // Add performance monitoring provider
    {
      provide: 'PERFORMANCE_MONITOR',
      useFactory: () => ({
        monitorLatency: true,
        monitorTHD: true,
        monitorCPUUsage: true,
        sampleInterval: 1000, // 1 second monitoring interval
        alertThreshold: 0.8 // 80% threshold for alerts
      })
    }
  ],
  exports: [
    ProfilesService,
    TypeOrmModule.forFeature([Profile, AudioSettings])
  ]
})
export class ProfilesModule {
  /**
   * Module version for compatibility tracking
   * @type {string}
   */
  private readonly moduleVersion: string = '1.0.0';

  /**
   * Cache timeout in seconds
   * @type {number}
   */
  private readonly cacheTimeout: number = 300;

  constructor() {
    // Module initialization can include additional setup if needed
    console.log(`Initializing ProfilesModule v${this.moduleVersion}`);
    console.log('Hardware validation enabled for ES9038PRO DAC');
    console.log('Performance monitoring configured with 1s interval');
  }
}