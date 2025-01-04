/**
 * TALD UNIA Audio System - Audio Controller Test Suite
 * Version: 1.0.0
 * 
 * Comprehensive test suite for AudioController verifying audio processing quality,
 * performance, security, and hardware integration requirements.
 */

import { Test, TestingModule } from '@nestjs/testing'; // v10.0.0
import { jest } from '@jest/globals'; // v29.0.0
import now from 'performance-now'; // v2.1.0

import { AudioController } from '../../src/audio/audio.controller';
import { AudioService } from '../../src/audio/audio.service';
import { ProcessAudioDto } from '../../src/audio/dtos/process-audio.dto';
import { ProcessingQuality } from '../../src/audio/interfaces/audio-config.interface';

// Test constants based on technical requirements
const THD_TARGET = 0.0005;
const MAX_LATENCY_MS = 10;
const SAMPLE_RATE = 192000;
const BIT_DEPTH = 32;
const BUFFER_SIZE = 1024;

/**
 * Mock AudioService with quality metrics and hardware validation
 */
class MockAudioService {
    processAudio = jest.fn().mockImplementation((buffer: Float32Array) => {
        return {
            processedAudio: buffer,
            qualityMetrics: {
                thd: 0.0003,
                snr: 120,
                latency: 5
            },
            processingStats: {
                cpuUsage: 30,
                bufferUtilization: 0.5,
                temperature: 45
            }
        };
    });

    updateConfig = jest.fn().mockResolvedValue({
        status: 'success',
        validation: {
            hardwareCompatible: true,
            qualityThresholds: true
        }
    });

    getQualityMetrics = jest.fn().mockReturnValue({
        thd: 0.0003,
        snr: 120,
        latency: 5,
        enhancementQuality: 0.95
    });

    validateHardwareCapabilities = jest.fn().mockReturnValue(true);
}

describe('AudioController', () => {
    let controller: AudioController;
    let service: MockAudioService;
    let module: TestingModule;

    beforeEach(async () => {
        // Initialize test module with enhanced mocks
        module = await Test.createTestingModule({
            controllers: [AudioController],
            providers: [
                {
                    provide: AudioService,
                    useClass: MockAudioService
                }
            ]
        }).compile();

        controller = module.get<AudioController>(AudioController);
        service = module.get<AudioService>(AudioService) as unknown as MockAudioService;
    });

    afterEach(() => {
        jest.clearAllMocks();
    });

    describe('processAudio', () => {
        let testDto: ProcessAudioDto;

        beforeEach(() => {
            // Initialize test DTO with hardware-compliant values
            testDto = new ProcessAudioDto();
            testDto.sampleRate = SAMPLE_RATE;
            testDto.bitDepth = BIT_DEPTH;
            testDto.bufferSize = BUFFER_SIZE;
            testDto.processingQuality = ProcessingQuality.Maximum;
            testDto.audioData = Buffer.alloc(BUFFER_SIZE * (BIT_DEPTH / 8));
        });

        it('should process audio within latency requirements', async () => {
            const startTime = now();
            await controller.processAudio(testDto);
            const processingTime = now() - startTime;

            expect(processingTime).toBeLessThan(MAX_LATENCY_MS);
        });

        it('should maintain THD below target threshold', async () => {
            const result = await controller.processAudio(testDto);
            expect(result.qualityMetrics.thd).toBeLessThan(THD_TARGET);
        });

        it('should validate hardware capabilities', async () => {
            const validateSpy = jest.spyOn(testDto, 'validateAudioBuffer');
            await controller.processAudio(testDto);
            expect(validateSpy).toHaveBeenCalled();
        });

        it('should handle buffer overflow conditions', async () => {
            const largeBuffer = Buffer.alloc(MAX_LATENCY_MS * SAMPLE_RATE * (BIT_DEPTH / 8));
            testDto.audioData = largeBuffer;
            await expect(controller.processAudio(testDto)).rejects.toThrow();
        });

        it('should enforce rate limiting', async () => {
            const requests = Array(1100).fill(testDto);
            const results = await Promise.allSettled(
                requests.map(req => controller.processAudio(req))
            );
            const rejected = results.filter(r => r.status === 'rejected');
            expect(rejected.length).toBeGreaterThan(0);
        });

        it('should validate input format', async () => {
            testDto.bitDepth = 8; // Invalid bit depth
            await expect(controller.processAudio(testDto)).rejects.toThrow();
        });

        it('should monitor processing quality', async () => {
            const result = await controller.processAudio(testDto);
            expect(result.processingStats).toBeDefined();
            expect(result.processingStats.cpuUsage).toBeDefined();
            expect(result.processingStats.bufferUtilization).toBeDefined();
        });
    });

    describe('updateConfig', () => {
        const testConfig = {
            sampleRate: SAMPLE_RATE,
            bitDepth: BIT_DEPTH,
            bufferSize: BUFFER_SIZE,
            processingQuality: ProcessingQuality.Maximum,
            deviceId: 'test-device',
            latencyTarget: 5
        };

        it('should validate hardware compatibility', async () => {
            const result = await controller.updateConfig(testConfig);
            expect(result.validation.hardwareCompatible).toBe(true);
        });

        it('should maintain quality thresholds', async () => {
            const result = await controller.updateConfig(testConfig);
            expect(result.validation.qualityThresholds).toBe(true);
        });

        it('should handle capability mismatches', async () => {
            const invalidConfig = { ...testConfig, sampleRate: 384000 };
            await expect(controller.updateConfig(invalidConfig)).rejects.toThrow();
        });

        it('should preserve existing config on failure', async () => {
            service.updateConfig.mockRejectedValueOnce(new Error('Update failed'));
            const originalConfig = await controller.getProcessingStats();
            await expect(controller.updateConfig(testConfig)).rejects.toThrow();
            const newConfig = await controller.getProcessingStats();
            expect(newConfig).toEqual(originalConfig);
        });
    });

    describe('getQualityStats', () => {
        it('should return accurate THD+N measurements', async () => {
            const stats = await controller.getProcessingStats();
            expect(stats.quality.thd).toBeDefined();
            expect(stats.quality.thd).toBeLessThan(THD_TARGET);
        });

        it('should track processing latency', async () => {
            const stats = await controller.getProcessingStats();
            expect(stats.performance.latency).toBeDefined();
            expect(stats.performance.latency).toBeLessThan(MAX_LATENCY_MS);
        });

        it('should monitor hardware performance', async () => {
            const stats = await controller.getProcessingStats();
            expect(stats.hardware.temperature).toBeDefined();
            expect(stats.hardware.bufferUtilization).toBeDefined();
        });

        it('should aggregate quality metrics', async () => {
            const stats = await controller.getProcessingStats();
            expect(stats.quality.enhancementQuality).toBeDefined();
            expect(stats.quality.snr).toBeDefined();
        });

        it('should handle measurement errors', async () => {
            service.getQualityMetrics.mockRejectedValueOnce(new Error('Measurement failed'));
            await expect(controller.getProcessingStats()).rejects.toThrow();
        });
    });
});