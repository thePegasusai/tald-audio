/**
 * @fileoverview NestJS module for AI-driven audio processing in TALD UNIA system
 * @version 1.0.0
 */

import { Module } from '@nestjs/common'; // v10.0.0
import { AIController } from './ai.controller';
import { AIService } from './ai.service';
import { InferenceProcessor } from './processors/inference.processor';

/**
 * AIModule configures and provides AI-driven audio processing capabilities
 * with hardware acceleration, parallel processing, and dynamic optimization
 * to achieve premium audio quality with <10ms latency.
 * 
 * Key features:
 * - Multi-layer AI processing pipeline
 * - Hardware-accelerated inference
 * - Dynamic performance optimization
 * - Real-time quality monitoring
 * - Parallel processing support
 */
@Module({
  imports: [],
  controllers: [AIController],
  providers: [
    {
      provide: AIService,
      useFactory: () => {
        const service = new AIService(
          // Initialize with audio enhancement model
          {
            modelId: 'tald-unia-v1',
            version: '1.0.0',
            type: 'AUDIO_ENHANCEMENT',
            accelerator: 'GPU',
            parameters: {
              sampleRate: 48000,
              frameSize: 1024,
              channels: 2,
              enhancementLevel: 0.8,
              latencyTarget: 10, // 10ms target latency
              bufferStrategy: 'adaptive',
              processingPriority: 'realtime'
            }
          },
          // Initialize with room correction model
          {
            modelId: 'tald-unia-room-v1',
            version: '1.0.0',
            type: 'ROOM_CORRECTION',
            accelerator: 'GPU',
            parameters: {
              sampleRate: 48000,
              frameSize: 2048,
              channels: 2,
              enhancementLevel: 0.8,
              latencyTarget: 10,
              bufferStrategy: 'adaptive',
              processingPriority: 'realtime'
            }
          },
          // Initialize inference processor
          new InferenceProcessor()
        );
        return service;
      }
    },
    {
      provide: InferenceProcessor,
      useFactory: () => {
        const processor = new InferenceProcessor();
        // Configure hardware acceleration
        processor.optimizeInference('GPU', {
          acceleratorType: 'GPU',
          computeCapability: 1.0,
          memoryLimit: 4096 * 1024 * 1024, // 4GB
          warmupLatency: 5
        });
        return processor;
      }
    }
  ],
  exports: [AIService]
})
export class AIModule {
  /**
   * Hardware acceleration configuration for optimal processing performance
   */
  private readonly hardwareAcceleration = {
    enabled: true,
    type: 'GPU',
    memoryLimit: 4096, // MB
    optimizationInterval: 5000 // ms
  };

  /**
   * Parallel processing configuration for reduced latency
   */
  private readonly parallelProcessing = {
    enabled: true,
    maxWorkers: 4,
    chunkSize: 1024,
    schedulingStrategy: 'dynamic'
  };

  /**
   * Dynamic optimization parameters for quality and performance
   */
  private readonly dynamicOptimization = {
    enabled: true,
    targetLatency: 10, // ms
    qualityThreshold: 0.2, // 20% improvement target
    adaptiveScaling: true
  };

  constructor() {
    // Module initialization is handled by NestJS DI system
    // Additional setup is performed in provider factories
  }
}