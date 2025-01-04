/**
 * @fileoverview Test suite for AIService verifying AI-driven audio processing functionality
 * @version 1.0.0
 */

import { Test, TestingModule } from '@nestjs/testing'; // v10.0.0
import { performance } from 'perf_hooks';
import { AIService } from '../../src/ai/ai.service';
import { AudioEnhancementModel } from '../../src/ai/models/audio-enhancement.model';
import { ModelConfig, ModelType, AcceleratorType } from '../../src/ai/interfaces/model-config.interface';

// Test constants
const TEST_AUDIO_LENGTH = 48000; // 1 second at 48kHz
const TEST_AUDIO_DATA = new Float32Array(TEST_AUDIO_LENGTH).map(() => Math.random() * 2 - 1);
const LATENCY_THRESHOLD_MS = 10;
const QUALITY_IMPROVEMENT_TARGET = 0.2;
const THDN_LIMIT = 0.0005;
const TEST_ITERATIONS = 100;

const MOCK_MODEL_CONFIG: ModelConfig = {
  modelId: 'test-model-v1',
  version: '1.0.0',
  type: ModelType.AUDIO_ENHANCEMENT,
  accelerator: AcceleratorType.GPU,
  parameters: {
    sampleRate: 48000,
    frameSize: 1024,
    channels: 2,
    enhancementLevel: 0.8,
    latencyTarget: 10,
    bufferStrategy: 'adaptive',
    processingPriority: 'realtime'
  }
};

describe('AIService', () => {
  let service: AIService;
  let module: TestingModule;
  let enhancementModel: AudioEnhancementModel;
  let latencyMeasurements: number[] = [];
  let qualityMeasurements: number[] = [];

  beforeEach(async () => {
    // Create mock enhancement model
    const mockEnhancementModel = {
      loadModel: jest.fn().mockResolvedValue(undefined),
      enhance: jest.fn().mockImplementation(async (audio: Float32Array) => {
        // Simulate enhancement with quality improvement
        return audio.map(sample => sample * 1.2);
      }),
      optimizePerformance: jest.fn().mockResolvedValue(undefined),
      getModelMetrics: jest.fn().mockReturnValue({
        latency: 5,
        quality: 0.85,
        memory: 1024 * 1024
      })
    };

    module = await Test.createTestingModule({
      providers: [
        AIService,
        {
          provide: AudioEnhancementModel,
          useValue: mockEnhancementModel
        }
      ]
    }).compile();

    service = module.get<AIService>(AIService);
    enhancementModel = module.get<AudioEnhancementModel>(AudioEnhancementModel);

    // Reset measurements
    latencyMeasurements = [];
    qualityMeasurements = [];
  });

  afterEach(async () => {
    await module.close();
  });

  describe('Audio Processing', () => {
    it('should process audio within latency requirements', async () => {
      for (let i = 0; i < TEST_ITERATIONS; i++) {
        const startTime = performance.now();
        const enhancedAudio = await service.processAudioParallel(TEST_AUDIO_DATA);
        const latency = performance.now() - startTime;
        
        latencyMeasurements.push(latency);
        
        expect(latency).toBeLessThanOrEqual(LATENCY_THRESHOLD_MS);
        expect(enhancedAudio).toBeInstanceOf(Float32Array);
        expect(enhancedAudio.length).toBe(TEST_AUDIO_DATA.length);
      }

      const averageLatency = latencyMeasurements.reduce((a, b) => a + b) / TEST_ITERATIONS;
      expect(averageLatency).toBeLessThanOrEqual(LATENCY_THRESHOLD_MS);
    });

    it('should achieve target quality improvement', async () => {
      const enhancedAudio = await service.processAudioParallel(TEST_AUDIO_DATA);
      
      // Calculate quality improvement
      const originalRMS = Math.sqrt(TEST_AUDIO_DATA.reduce((acc, val) => acc + val * val, 0) / TEST_AUDIO_DATA.length);
      const enhancedRMS = Math.sqrt(enhancedAudio.reduce((acc, val) => acc + val * val, 0) / enhancedAudio.length);
      const improvement = (enhancedRMS - originalRMS) / originalRMS;
      
      expect(improvement).toBeGreaterThanOrEqual(QUALITY_IMPROVEMENT_TARGET);
    });

    it('should maintain THD+N below threshold', async () => {
      const enhancedAudio = await service.processAudioParallel(TEST_AUDIO_DATA);
      
      // Calculate THD+N using enhancement model's internal method
      const metrics = await enhancementModel.getModelMetrics();
      const thdn = 1 - metrics.quality;
      
      expect(thdn).toBeLessThanOrEqual(THDN_LIMIT);
    });
  });

  describe('Performance Optimization', () => {
    it('should optimize processing based on metrics', async () => {
      const metrics = {
        latency: 12, // Above threshold
        quality: 0.8,
        memory: 1024 * 1024,
        cpuLoad: 0.4,
        gpuLoad: 0.6
      };

      await service.optimizeProcessing(metrics);
      
      // Verify optimization was triggered
      expect(enhancementModel.optimizePerformance).toHaveBeenCalledWith(AcceleratorType.GPU);
    });

    it('should adapt to different hardware configurations', async () => {
      // Test CPU fallback
      const cpuConfig = { ...MOCK_MODEL_CONFIG, accelerator: AcceleratorType.CPU };
      await service.processAudioParallel(TEST_AUDIO_DATA);
      
      // Verify hardware adaptation
      expect(enhancementModel.loadModel).toHaveBeenCalledWith(expect.objectContaining({
        accelerator: expect.any(String)
      }));
    });

    it('should handle parallel processing efficiently', async () => {
      const largeAudio = new Float32Array(TEST_AUDIO_LENGTH * 4);
      const startTime = performance.now();
      
      await service.processAudioParallel(largeAudio);
      const processingTime = performance.now() - startTime;
      
      // Verify parallel processing efficiency
      expect(processingTime).toBeLessThanOrEqual(LATENCY_THRESHOLD_MS * 2);
    });
  });

  describe('Error Handling', () => {
    it('should handle initialization failures gracefully', async () => {
      enhancementModel.loadModel.mockRejectedValueOnce(new Error('Initialization failed'));
      
      await expect(service.processAudioParallel(TEST_AUDIO_DATA))
        .rejects
        .toThrow('AI Service not initialized');
    });

    it('should recover from processing errors', async () => {
      enhancementModel.enhance.mockRejectedValueOnce(new Error('Processing error'));
      
      await expect(service.processAudioParallel(TEST_AUDIO_DATA))
        .rejects
        .toThrow('Audio processing failed');
      
      // Verify service can still process subsequent requests
      const enhancedAudio = await service.processAudioParallel(TEST_AUDIO_DATA);
      expect(enhancedAudio).toBeInstanceOf(Float32Array);
    });
  });

  describe('Resource Management', () => {
    it('should manage memory efficiently during processing', async () => {
      const initialMemory = process.memoryUsage().heapUsed;
      
      // Process multiple audio chunks
      for (let i = 0; i < 10; i++) {
        await service.processAudioParallel(TEST_AUDIO_DATA);
      }
      
      const finalMemory = process.memoryUsage().heapUsed;
      const memoryIncrease = (finalMemory - initialMemory) / initialMemory;
      
      // Verify memory usage stays within reasonable bounds
      expect(memoryIncrease).toBeLessThan(0.5); // Less than 50% increase
    });
  });
});