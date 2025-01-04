/**
 * TALD UNIA Audio System - Metrics Module
 * Version: 1.0.0
 * 
 * Configures and provides comprehensive metrics collection and monitoring capabilities
 * for high-precision audio quality tracking and performance monitoring.
 */

import { Module } from '@nestjs/common'; // v10.0.0
import { MetricsController } from './metrics.controller';
import { AudioMetricsCollector } from './collectors/audio-metrics.collector';
import { AudioService } from '../audio/audio.service';

/**
 * Configuration options for the metrics module
 */
interface MetricsModuleOptions {
  /**
   * Collection interval in milliseconds
   * Default: 1000ms
   */
  collectionInterval?: number;

  /**
   * Enable detailed performance tracking
   * Default: true
   */
  enablePerformanceTracking?: boolean;

  /**
   * Retention period for metrics in hours
   * Default: 24
   */
  retentionPeriod?: number;

  /**
   * Alert thresholds configuration
   */
  alertThresholds?: {
    latencyMs: number;
    thdnPercent: number;
    enhancementTarget: number;
  };
}

/**
 * Default configuration values
 */
const DEFAULT_OPTIONS: Required<MetricsModuleOptions> = {
  collectionInterval: 1000,
  enablePerformanceTracking: true,
  retentionPeriod: 24,
  alertThresholds: {
    latencyMs: 10,
    thdnPercent: 0.0005,
    enhancementTarget: 20
  }
};

/**
 * Metrics Module for TALD UNIA Audio System
 * Provides comprehensive monitoring of audio quality, processing performance,
 * and AI enhancement metrics with Prometheus integration.
 */
@Module({
  imports: [],
  controllers: [MetricsController],
  providers: [AudioMetricsCollector, AudioService]
})
export class MetricsModule {
  private static moduleVersion = '1.0.0';
  private static collectionInterval: number;
  private static isEnabled: boolean = true;

  /**
   * Configures the metrics module with custom options
   * @param options Module configuration options
   */
  static forRoot(options?: Partial<MetricsModuleOptions>) {
    const mergedOptions = {
      ...DEFAULT_OPTIONS,
      ...options
    };

    return {
      module: MetricsModule,
      providers: [
        {
          provide: 'METRICS_OPTIONS',
          useValue: mergedOptions
        },
        {
          provide: AudioMetricsCollector,
          useFactory: () => {
            const collector = new AudioMetricsCollector(
              new AudioService(
                /* Dependencies injected by NestJS */
              )
            );
            collector.initialize(mergedOptions);
            return collector;
          }
        }
      ],
      exports: [AudioMetricsCollector]
    };
  }

  /**
   * Enables metrics collection
   */
  static enable(): void {
    MetricsModule.isEnabled = true;
  }

  /**
   * Disables metrics collection
   */
  static disable(): void {
    MetricsModule.isEnabled = false;
  }

  /**
   * Updates collection interval
   * @param intervalMs New interval in milliseconds
   */
  static setCollectionInterval(intervalMs: number): void {
    if (intervalMs < 100) {
      throw new Error('Collection interval cannot be less than 100ms');
    }
    MetricsModule.collectionInterval = intervalMs;
  }

  /**
   * Gets current module configuration
   */
  static getConfiguration(): {
    version: string;
    enabled: boolean;
    collectionInterval: number;
  } {
    return {
      version: MetricsModule.moduleVersion,
      enabled: MetricsModule.isEnabled,
      collectionInterval: MetricsModule.collectionInterval
    };
  }
}