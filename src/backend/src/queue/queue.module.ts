/**
 * TALD UNIA Audio System - Queue Module
 * Version: 1.0.0
 * 
 * Configures and manages the queue system for audio processing and AI inference tasks
 * with advanced performance monitoring and dynamic scaling capabilities.
 */

import { Module } from '@nestjs/common'; // v10.0.0
import { BullModule } from '@nestjs/bull'; // v0.6.0
import { ConfigService } from '@nestjs/config'; // v3.0.0
import { AudioProcessingQueue } from './processors/audio-processing.queue';
import { AIInferenceQueue } from './processors/ai-inference.queue';

// Queue configuration constants
const REDIS_CLUSTER_SIZE = 3;
const MAX_CONCURRENCY = 4;
const STALENESS_THRESHOLD = 10000;
const BACKOFF_DELAY = 1000;
const MEMORY_LIMIT = 1024;

/**
 * Queue configuration factory with performance optimization
 */
const configureQueues = async (configService: ConfigService) => ({
  redis: {
    host: configService.get('REDIS_HOST', 'localhost'),
    port: configService.get('REDIS_PORT', 6379),
    password: configService.get('REDIS_PASSWORD'),
    maxRetriesPerRequest: 3,
    enableReadyCheck: true,
    cluster: {
      nodes: Array(REDIS_CLUSTER_SIZE).fill(null).map((_, i) => ({
        host: configService.get(`REDIS_NODE_${i}_HOST`, 'localhost'),
        port: configService.get(`REDIS_NODE_${i}_PORT`, 6379)
      })),
      maxRedirections: 16,
      retryDelayOnFailover: 100
    }
  },
  defaultJobOptions: {
    attempts: 3,
    backoff: {
      type: 'exponential',
      delay: BACKOFF_DELAY
    },
    removeOnComplete: true,
    removeOnFail: false,
    timeout: 10000
  },
  limiter: {
    max: MAX_CONCURRENCY,
    duration: 1000
  },
  settings: {
    stalledInterval: STALENESS_THRESHOLD,
    maxStalledCount: 2,
    lockDuration: 30000
  }
});

@Module({
  imports: [
    // Configure Bull queues with performance optimization
    BullModule.forRootAsync({
      useFactory: configureQueues,
      inject: [ConfigService]
    }),
    // Register audio processing queue
    BullModule.registerQueue({
      name: 'audio-processing',
      processors: [{
        name: 'processAudio',
        concurrency: MAX_CONCURRENCY
      }],
      defaultJobOptions: {
        priority: 1,
        lifo: false
      }
    }),
    // Register AI inference queue
    BullModule.registerQueue({
      name: 'ai-inference',
      processors: [{
        name: 'processInference',
        concurrency: MAX_CONCURRENCY / 2 // Lower concurrency for GPU tasks
      }],
      defaultJobOptions: {
        priority: 2,
        lifo: false
      }
    })
  ],
  providers: [
    AudioProcessingQueue,
    AIInferenceQueue,
    {
      provide: 'QUEUE_METRICS',
      useFactory: () => ({
        collectMetrics: true,
        metricPrefix: 'tald_unia_queue',
        monitoringInterval: 1000,
        memoryThreshold: MEMORY_LIMIT,
        latencyThreshold: 10 // 10ms target latency
      })
    }
  ],
  exports: [
    BullModule,
    AudioProcessingQueue,
    AIInferenceQueue
  ]
})
export class QueueModule {
  /**
   * Configures queue module with enhanced monitoring and performance optimization
   * @param options Queue module configuration options
   */
  static forRoot(options?: any) {
    return {
      module: QueueModule,
      imports: [
        BullModule.forRootAsync({
          useFactory: async (configService: ConfigService) => ({
            ...await configureQueues(configService),
            ...options
          }),
          inject: [ConfigService]
        })
      ],
      providers: [
        {
          provide: 'QUEUE_CONFIG',
          useValue: options
        }
      ]
    };
  }
}