/**
 * @fileoverview Controller for managing AI-driven audio processing endpoints in TALD UNIA system
 * @version 1.0.0
 */

import { 
  Controller, 
  Post, 
  Body, 
  Get, 
  Put, 
  UseGuards, 
  UseInterceptors, 
  ValidationPipe 
} from '@nestjs/common'; // v10.0.0
import { 
  ApiTags, 
  ApiOperation, 
  ApiResponse, 
  ApiBody, 
  ApiParam 
} from '@nestjs/swagger'; // v7.0.0
import { 
  Observable, 
  Subject, 
  BehaviorSubject, 
  map, 
  catchError, 
  timeout 
} from 'rxjs'; // v7.8.0

import { AIService } from './ai.service';
import { 
  ModelConfig, 
  ModelType, 
  ModelParameters, 
  AcceleratorType, 
  ProcessingMode 
} from './interfaces/model-config.interface';
import { ApiResponseDecorator } from '../common/decorators/api-response.decorator';

// Constants for performance monitoring and optimization
const MAX_PROCESSING_LATENCY = 10; // 10ms latency target
const QUALITY_IMPROVEMENT_TARGET = 0.2; // 20% quality improvement target
const MONITORING_INTERVAL = 1000; // 1 second monitoring interval
const PROCESSING_TIMEOUT = 15000; // 15 second processing timeout

@Controller('ai')
@ApiTags('AI Processing')
@UseGuards(AuthGuard)
@UseInterceptors(LoggingInterceptor)
export class AIController {
  private readonly metricsSubject: Subject<ProcessingMetrics>;
  private readonly configSubject: BehaviorSubject<ModelConfig>;

  constructor(private readonly aiService: AIService) {
    this.metricsSubject = new Subject<ProcessingMetrics>();
    this.configSubject = new BehaviorSubject<ModelConfig>({
      modelId: 'tald-unia-v1',
      version: '1.0.0',
      type: ModelType.AUDIO_ENHANCEMENT,
      accelerator: AcceleratorType.GPU,
      parameters: {
        sampleRate: 48000,
        frameSize: 1024,
        channels: 2,
        enhancementLevel: 0.8,
        latencyTarget: MAX_PROCESSING_LATENCY,
        bufferStrategy: 'adaptive',
        processingPriority: 'realtime'
      }
    });

    this.initializeMonitoring();
  }

  @Post('process')
  @ApiOperation({ summary: 'Process audio through AI enhancement pipeline' })
  @ApiBody({ type: AudioProcessingDto })
  @ApiResponseDecorator({
    type: AudioResponseDto,
    status: 200,
    description: 'Audio successfully processed with AI enhancement'
  })
  @UseGuards(RateLimitGuard)
  async processAudio(
    @Body(new ValidationPipe()) audioData: Float32Array,
    @Body('mode') mode: ProcessingMode = ProcessingMode.REALTIME
  ): Promise<Float32Array> {
    try {
      // Validate input data
      this.validateAudioInput(audioData);

      // Process audio with timeout protection
      const enhanced = await this.aiService.processAudioParallel(audioData)
        .pipe(
          timeout(PROCESSING_TIMEOUT),
          catchError(error => {
            throw new Error(`Audio processing failed: ${error.message}`);
          })
        )
        .toPromise();

      // Monitor processing metrics
      const metrics = await this.aiService.getPerformanceMetrics().pipe(
        map(metrics => {
          this.metricsSubject.next(metrics);
          return metrics;
        })
      ).toPromise();

      // Optimize if needed
      if (metrics.latency > MAX_PROCESSING_LATENCY) {
        await this.optimizeProcessing(metrics);
      }

      return enhanced;
    } catch (error) {
      throw new Error(`Audio processing failed: ${error.message}`);
    }
  }

  @Put('config')
  @ApiOperation({ summary: 'Update AI model configuration' })
  @ApiBody({ type: ModelConfigDto })
  @ApiResponseDecorator({
    type: ModelConfigDto,
    status: 200,
    description: 'Model configuration successfully updated'
  })
  async updateConfig(
    @Body(new ValidationPipe()) config: ModelConfig
  ): Promise<ModelConfig> {
    try {
      // Validate configuration
      await this.aiService.validateConfiguration(config);

      // Update configuration
      this.configSubject.next(config);
      await this.aiService.updateModelConfig(config);

      return config;
    } catch (error) {
      throw new Error(`Configuration update failed: ${error.message}`);
    }
  }

  @Get('metrics')
  @ApiOperation({ summary: 'Get AI processing performance metrics' })
  @ApiResponseDecorator({
    type: ProcessingMetricsDto,
    status: 200,
    description: 'Current processing metrics retrieved'
  })
  getMetrics(): Observable<ProcessingMetrics> {
    return this.metricsSubject.asObservable();
  }

  private validateAudioInput(audioData: Float32Array): void {
    if (!audioData || audioData.length === 0) {
      throw new Error('Invalid audio data');
    }
    if (audioData.length > 1024 * 1024) { // 1MB limit
      throw new Error('Audio data exceeds size limit');
    }
  }

  private async optimizeProcessing(metrics: ProcessingMetrics): Promise<void> {
    const currentConfig = this.configSubject.value;

    // Adjust enhancement level based on latency
    if (metrics.latency > MAX_PROCESSING_LATENCY) {
      currentConfig.parameters.enhancementLevel = Math.max(
        0.2,
        currentConfig.parameters.enhancementLevel * 0.9
      );
    }

    // Adjust processing mode if needed
    if (metrics.gpuLoad > 0.8) {
      currentConfig.accelerator = AcceleratorType.CPU;
    }

    await this.updateConfig(currentConfig);
  }

  private initializeMonitoring(): void {
    setInterval(async () => {
      try {
        const metrics = await this.aiService.getPerformanceMetrics()
          .pipe(take(1))
          .toPromise();
        this.metricsSubject.next(metrics);

        // Check quality improvement target
        if (metrics.quality < QUALITY_IMPROVEMENT_TARGET) {
          await this.optimizeProcessing(metrics);
        }
      } catch (error) {
        console.error('Monitoring error:', error);
      }
    }, MONITORING_INTERVAL);
  }
}