/**
 * @fileoverview Advanced queue processor for AI inference tasks in TALD UNIA Audio System
 * @version 1.0.0
 */

import { Injectable } from '@nestjs/common'; // v10.0.0
import { Process, Processor, OnQueueError, OnQueueFailed } from '@nestjs/bull'; // v0.6.0
import { Job, Queue, JobOptions } from 'bull'; // v4.10.0
import * as promClient from 'prom-client'; // v14.0.0

import { AIService } from '../../ai/ai.service';
import { ModelConfig, ModelType, AcceleratorType } from '../../ai/interfaces/model-config.interface';

// Constants for queue configuration and optimization
const MAX_RETRY_ATTEMPTS = 3;
const PROCESSING_TIMEOUT_MS = 5000;
const MIN_BATCH_SIZE = 64;
const MAX_BATCH_SIZE = 1024;
const MEMORY_THRESHOLD_MB = 8192;
const CIRCUIT_BREAKER_THRESHOLD = 0.5;
const METRICS_INTERVAL_MS = 1000;
const CLEANUP_INTERVAL_MS = 5000;

// Interface for inference job data
interface InferenceJob {
  audioData: Float32Array;
  modelConfig: ModelConfig;
  priority: number;
  timestamp: number;
}

// Interface for queue metrics
interface QueueMetrics {
  processingLatency: number;
  successRate: number;
  throughput: number;
  memoryUsage: number;
  gpuUtilization: number;
  activeJobs: number;
  failedJobs: number;
  retryCount: number;
}

@Injectable()
@Processor('ai-inference')
export class AIInferenceQueue {
  private processingLatency: number = 0;
  private isProcessing: boolean = false;
  private readonly metricsCollector: promClient.Counter;
  private readonly latencyHistogram: promClient.Histogram;
  private readonly memoryGauge: promClient.Gauge;
  private readonly circuitBreakerState: { failures: number; total: number; };
  private currentBatchSize: number = MIN_BATCH_SIZE;

  constructor(
    private readonly aiService: AIService
  ) {
    // Initialize metrics collectors
    this.metricsCollector = new promClient.Counter({
      name: 'ai_inference_processed_total',
      help: 'Total number of processed AI inference jobs'
    });

    this.latencyHistogram = new promClient.Histogram({
      name: 'ai_inference_latency_ms',
      help: 'AI inference processing latency in milliseconds',
      buckets: [1, 2, 5, 10, 20, 50]
    });

    this.memoryGauge = new promClient.Gauge({
      name: 'ai_inference_memory_usage_mb',
      help: 'Memory usage of AI inference processing'
    });

    this.circuitBreakerState = {
      failures: 0,
      total: 0
    };

    this.initializeMonitoring();
  }

  /**
   * Processes AI inference jobs with performance optimization
   * @param job Bull queue job containing audio data and configuration
   */
  @Process()
  public async process(job: Job<InferenceJob>): Promise<Float32Array> {
    const startTime = performance.now();
    this.isProcessing = true;

    try {
      // Validate job data
      this.validateJobData(job.data);

      // Check circuit breaker
      if (this.isCircuitBreakerOpen()) {
        throw new Error('Circuit breaker is open');
      }

      // Monitor memory usage
      await this.checkMemoryUsage();

      // Optimize batch size based on current performance
      this.optimizeBatchSize();

      // Process audio through AI service
      const enhancedAudio = await this.aiService.processAudioParallel(job.data.audioData);

      // Update metrics
      this.processingLatency = performance.now() - startTime;
      this.updateMetrics(true);
      this.latencyHistogram.observe(this.processingLatency);

      // Perform memory cleanup if needed
      if (this.processingLatency > job.data.modelConfig.parameters.latencyTarget) {
        await this.performMemoryCleanup();
      }

      return enhancedAudio;
    } catch (error) {
      this.updateMetrics(false);
      throw error;
    } finally {
      this.isProcessing = false;
    }
  }

  /**
   * Handles queue errors with advanced error recovery
   * @param error Error object from failed job
   * @param job Failed job instance
   */
  @OnQueueError()
  public async handleError(error: Error, job: Job<InferenceJob>): Promise<void> {
    // Update circuit breaker state
    this.circuitBreakerState.failures++;
    this.circuitBreakerState.total++;

    // Log detailed error information
    console.error(`AI Inference Error - Job ${job.id}:`, {
      error: error.message,
      stack: error.stack,
      jobData: job.data,
      attempts: job.attemptsMade,
      timestamp: new Date().toISOString()
    });

    // Implement retry strategy
    if (job.attemptsMade < MAX_RETRY_ATTEMPTS) {
      const backoff = Math.pow(2, job.attemptsMade) * 1000;
      await job.retry({
        delay: backoff,
        attempts: job.attemptsMade + 1
      });
    } else {
      // Trigger circuit breaker if failure rate is too high
      if (this.getFailureRate() > CIRCUIT_BREAKER_THRESHOLD) {
        await this.triggerCircuitBreaker();
      }
    }
  }

  /**
   * Retrieves comprehensive processing metrics
   */
  public async getMetrics(): Promise<QueueMetrics> {
    const metrics = await this.aiService.getPerformanceMetrics().toPromise();
    
    return {
      processingLatency: this.processingLatency,
      successRate: 1 - this.getFailureRate(),
      throughput: this.metricsCollector.get().values[0].value,
      memoryUsage: metrics.memory,
      gpuUtilization: metrics.gpuLoad,
      activeJobs: this.isProcessing ? 1 : 0,
      failedJobs: this.circuitBreakerState.failures,
      retryCount: this.circuitBreakerState.total - this.circuitBreakerState.failures
    };
  }

  /**
   * Validates incoming job data
   * @private
   */
  private validateJobData(data: InferenceJob): void {
    if (!data.audioData || !data.modelConfig) {
      throw new Error('Invalid job data');
    }
    if (data.modelConfig.type !== ModelType.AUDIO_ENHANCEMENT) {
      throw new Error('Unsupported model type');
    }
  }

  /**
   * Checks system memory usage
   * @private
   */
  private async checkMemoryUsage(): Promise<void> {
    const metrics = await this.aiService.getPerformanceMetrics().toPromise();
    this.memoryGauge.set(metrics.memory / 1024 / 1024);

    if (metrics.memory / 1024 / 1024 > MEMORY_THRESHOLD_MB) {
      await this.performMemoryCleanup();
    }
  }

  /**
   * Optimizes batch size based on performance
   * @private
   */
  private optimizeBatchSize(): void {
    if (this.processingLatency > 10) {
      this.currentBatchSize = Math.max(MIN_BATCH_SIZE, this.currentBatchSize / 2);
    } else if (this.processingLatency < 5) {
      this.currentBatchSize = Math.min(MAX_BATCH_SIZE, this.currentBatchSize * 2);
    }
  }

  /**
   * Performs memory cleanup
   * @private
   */
  private async performMemoryCleanup(): Promise<void> {
    await this.aiService.optimizeProcessing({
      latency: this.processingLatency,
      quality: 0,
      memory: 0,
      cpuLoad: 0,
      gpuLoad: 0
    });
  }

  /**
   * Updates processing metrics
   * @private
   */
  private updateMetrics(success: boolean): void {
    this.metricsCollector.inc();
    this.circuitBreakerState.total++;
    if (!success) {
      this.circuitBreakerState.failures++;
    }
  }

  /**
   * Calculates current failure rate
   * @private
   */
  private getFailureRate(): number {
    return this.circuitBreakerState.total === 0 ? 0 :
      this.circuitBreakerState.failures / this.circuitBreakerState.total;
  }

  /**
   * Checks if circuit breaker is open
   * @private
   */
  private isCircuitBreakerOpen(): boolean {
    return this.getFailureRate() > CIRCUIT_BREAKER_THRESHOLD;
  }

  /**
   * Triggers circuit breaker protection
   * @private
   */
  private async triggerCircuitBreaker(): Promise<void> {
    // Reset processing state
    this.isProcessing = false;
    
    // Attempt recovery
    await this.aiService.optimizeProcessing({
      latency: this.processingLatency,
      quality: 0,
      memory: 0,
      cpuLoad: 0,
      gpuLoad: 0
    });

    // Reset circuit breaker state after recovery attempt
    this.circuitBreakerState.failures = 0;
    this.circuitBreakerState.total = 0;
  }

  /**
   * Initializes monitoring systems
   * @private
   */
  private initializeMonitoring(): void {
    // Monitor metrics periodically
    setInterval(async () => {
      const metrics = await this.getMetrics();
      this.memoryGauge.set(metrics.memoryUsage);
    }, METRICS_INTERVAL_MS);

    // Periodic cleanup
    setInterval(async () => {
      if (!this.isProcessing) {
        await this.performMemoryCleanup();
      }
    }, CLEANUP_INTERVAL_MS);
  }
}