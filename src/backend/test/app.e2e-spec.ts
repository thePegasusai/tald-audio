/**
 * TALD UNIA Audio System - End-to-End Test Suite
 * Validates complete integration of audio processing, AI enhancement,
 * and spatial audio features with comprehensive quality metrics.
 * @version 1.0.0
 */

import { Test, TestingModule } from '@nestjs/testing';
import { INestApplication } from '@nestjs/common';
import * as request from 'supertest';
import * as WebSocket from 'ws';
import { PerformanceObserver, performance } from 'perf_hooks';
import { AppModule } from '../src/app.module';

describe('Audio System E2E Tests', () => {
  let app: INestApplication;
  let httpServer: any;
  let wsClient: WebSocket;
  let performanceObserver: PerformanceObserver;

  // Test audio files
  const testAudioPath = './test/test-audio-samples/reference-audio.wav';
  const spatialTestPath = './test/test-audio-samples/spatial-test.wav';

  // Quality thresholds
  const MAX_LATENCY_MS = 10;
  const THD_TARGET = 0.0005;
  const QUALITY_IMPROVEMENT_TARGET = 0.2;

  beforeAll(async () => {
    // Initialize test module
    const moduleFixture: TestingModule = await Test.createTestingModule({
      imports: [AppModule],
    }).compile();

    // Create application instance
    app = moduleFixture.createNestApplication();
    await app.init();

    // Get HTTP server instance
    httpServer = app.getHttpServer();

    // Initialize WebSocket client
    wsClient = new WebSocket(`ws://localhost:${process.env.PORT || 3000}/audio`);

    // Setup performance monitoring
    performanceObserver = new PerformanceObserver((list) => {
      const entries = list.getEntries();
      entries.forEach((entry) => {
        if (entry.duration > MAX_LATENCY_MS) {
          console.warn(`Performance threshold exceeded: ${entry.name} took ${entry.duration}ms`);
        }
      });
    });
    performanceObserver.observe({ entryTypes: ['measure'] });
  });

  afterAll(async () => {
    // Cleanup resources
    wsClient.close();
    performanceObserver.disconnect();
    await app.close();
  });

  describe('Audio Processing Pipeline', () => {
    it('should process audio with target quality metrics', async () => {
      const testAudio = new Float32Array(48000); // 1 second of audio at 48kHz
      const startTime = performance.now();

      const response = await request(httpServer)
        .post('/audio/process')
        .send({
          audioData: testAudio.buffer,
          config: {
            sampleRate: 48000,
            bitDepth: 24,
            channels: 2,
            processingQuality: 'MAXIMUM'
          }
        })
        .expect(200);

      const processingTime = performance.now() - startTime;
      expect(processingTime).toBeLessThan(MAX_LATENCY_MS);

      const { processedAudio, qualityMetrics } = response.body;
      expect(qualityMetrics.thd).toBeLessThan(THD_TARGET);
      expect(qualityMetrics.snr).toBeGreaterThan(120);
    });

    it('should handle spatial audio processing', async () => {
      const spatialAudio = new Float32Array(48000);
      const position = {
        azimuth: 45,
        elevation: 30,
        distance: 1
      };

      const response = await request(httpServer)
        .post('/spatial/process')
        .send({
          audioData: spatialAudio.buffer,
          position
        })
        .expect(200);

      expect(response.body.qualityMetrics.spatialAccuracy).toBeGreaterThan(0.9);
    });
  });

  describe('AI Enhancement', () => {
    it('should improve audio quality through AI processing', async () => {
      const testAudio = new Float32Array(48000);
      
      const response = await request(httpServer)
        .post('/ai/process')
        .send({
          audioData: testAudio.buffer,
          config: {
            enhancementLevel: 0.8,
            processingMode: 'QUALITY'
          }
        })
        .expect(200);

      const { qualityImprovement, processingLatency } = response.body.metrics;
      expect(qualityImprovement).toBeGreaterThan(QUALITY_IMPROVEMENT_TARGET);
      expect(processingLatency).toBeLessThan(MAX_LATENCY_MS);
    });
  });

  describe('WebSocket Streaming', () => {
    it('should maintain low latency in real-time streaming', (done) => {
      const streamData = new Float32Array(1024);
      let latencySum = 0;
      let packetCount = 0;

      wsClient.on('message', (data: WebSocket.Data) => {
        const response = JSON.parse(data.toString());
        latencySum += response.metrics.processingLatency;
        packetCount++;

        if (packetCount === 100) {
          const averageLatency = latencySum / packetCount;
          expect(averageLatency).toBeLessThan(MAX_LATENCY_MS);
          done();
        }
      });

      // Send 100 audio packets
      for (let i = 0; i < 100; i++) {
        wsClient.send(JSON.stringify({
          event: 'audio:stream:data',
          data: {
            buffer: streamData.buffer,
            sequence: i,
            timestamp: Date.now()
          }
        }));
      }
    });
  });

  describe('System Integration', () => {
    it('should handle concurrent processing requests', async () => {
      const requests = Array(10).fill(null).map(() => 
        request(httpServer)
          .post('/audio/process')
          .send({
            audioData: new Float32Array(48000).buffer,
            config: {
              sampleRate: 48000,
              bitDepth: 24,
              channels: 2
            }
          })
      );

      const responses = await Promise.all(requests);
      responses.forEach(response => {
        expect(response.status).toBe(200);
        expect(response.body.qualityMetrics.thd).toBeLessThan(THD_TARGET);
      });
    });

    it('should maintain performance under load', async () => {
      const startTime = performance.now();
      const iterations = 100;

      for (let i = 0; i < iterations; i++) {
        await request(httpServer)
          .post('/audio/process')
          .send({
            audioData: new Float32Array(1024).buffer,
            config: {
              sampleRate: 48000,
              bitDepth: 24,
              channels: 2
            }
          })
          .expect(200);
      }

      const averageLatency = (performance.now() - startTime) / iterations;
      expect(averageLatency).toBeLessThan(MAX_LATENCY_MS);
    });
  });
});