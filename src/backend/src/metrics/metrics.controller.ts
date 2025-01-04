import { Controller, Get, Header, UseGuards, UseInterceptors } from '@nestjs/common'; // v10.0.0
import { ApiTags, ApiOperation, ApiResponse, ApiSecurity } from '@nestjs/swagger'; // v7.0.0
import { CacheInterceptor } from '@nestjs/cache-manager'; // v2.0.0
import { AuthGuard } from '@nestjs/passport'; // v10.0.0
import { AudioMetricsCollector } from './collectors/audio-metrics.collector';

/**
 * Controller for exposing Prometheus-compatible metrics endpoints for TALD UNIA Audio System
 * Provides comprehensive monitoring of audio processing performance, quality, and AI enhancement
 */
@Controller('metrics')
@ApiTags('Metrics')
@UseGuards(AuthGuard('metrics'))
@UseInterceptors(CacheInterceptor)
export class MetricsController {
    constructor(
        private readonly metricsCollector: AudioMetricsCollector
    ) {}

    /**
     * Get Prometheus-formatted metrics for system monitoring
     * Includes audio quality, latency, and AI enhancement metrics
     */
    @Get()
    @Header('Content-Type', 'text/plain')
    @ApiOperation({ summary: 'Get Prometheus metrics' })
    @ApiResponse({ 
        status: 200, 
        description: 'Prometheus metrics retrieved successfully'
    })
    @ApiResponse({ 
        status: 429, 
        description: 'Rate limit exceeded'
    })
    @ApiSecurity('metrics-key')
    async getMetrics(): Promise<string> {
        const metrics = await this.metricsCollector.getMetrics();
        return this.formatPrometheusMetrics(metrics);
    }

    /**
     * Get detailed audio processing metrics with validation
     * Provides comprehensive stats for audio quality monitoring
     */
    @Get('audio')
    @ApiOperation({ summary: 'Get detailed audio metrics' })
    @ApiResponse({ 
        status: 200, 
        description: 'Audio metrics retrieved successfully'
    })
    @ApiResponse({ 
        status: 429, 
        description: 'Rate limit exceeded'
    })
    @ApiSecurity('metrics-key')
    async getAudioMetrics(): Promise<AudioMetrics> {
        const latencyMetrics = await this.metricsCollector.collectLatencyMetrics();
        const qualityMetrics = await this.metricsCollector.collectQualityMetrics();
        const enhancementMetrics = await this.metricsCollector.collectEnhancementMetrics();

        return {
            latency: {
                current: latencyMetrics.current,
                trend: latencyMetrics.trend,
                threshold: latencyMetrics.threshold,
                violations: latencyMetrics.violations
            },
            quality: {
                thdn: qualityMetrics.thdn,
                snr: qualityMetrics.snr,
                bufferUtilization: qualityMetrics.bufferUtilization,
                target: qualityMetrics.target
            },
            enhancement: {
                improvement: enhancementMetrics.improvement,
                spatialAccuracy: enhancementMetrics.spatialAccuracy,
                target: enhancementMetrics.target,
                trend: enhancementMetrics.trend
            },
            system: {
                cpuUsage: qualityMetrics.cpuUsage,
                memoryUsage: qualityMetrics.memoryUsage,
                bufferUnderruns: qualityMetrics.bufferUnderruns,
                errorRate: qualityMetrics.errorRate
            }
        };
    }

    /**
     * Format metrics into Prometheus exposition format
     */
    private formatPrometheusMetrics(metrics: AudioMetrics): string {
        const lines: string[] = [];

        // Audio Processing Latency
        lines.push('# HELP audio_processing_latency_ms Current audio processing latency');
        lines.push('# TYPE audio_processing_latency_ms gauge');
        lines.push(`audio_processing_latency_ms{type="current"} ${metrics.latency.current}`);
        lines.push(`audio_processing_latency_ms{type="trend"} ${metrics.latency.trend}`);

        // Audio Quality Metrics
        lines.push('# HELP audio_thdn_percent Total Harmonic Distortion plus Noise');
        lines.push('# TYPE audio_thdn_percent gauge');
        lines.push(`audio_thdn_percent{} ${metrics.quality.thdn}`);

        lines.push('# HELP audio_snr_db Signal-to-Noise Ratio');
        lines.push('# TYPE audio_snr_db gauge');
        lines.push(`audio_snr_db{} ${metrics.quality.snr}`);

        // Enhancement Metrics
        lines.push('# HELP audio_enhancement_improvement_percent AI enhancement quality improvement');
        lines.push('# TYPE audio_enhancement_improvement_percent gauge');
        lines.push(`audio_enhancement_improvement_percent{type="overall"} ${metrics.enhancement.improvement}`);
        lines.push(`audio_enhancement_improvement_percent{type="spatial"} ${metrics.enhancement.spatialAccuracy}`);

        // System Metrics
        lines.push('# HELP audio_system_cpu_usage_percent CPU usage for audio processing');
        lines.push('# TYPE audio_system_cpu_usage_percent gauge');
        lines.push(`audio_system_cpu_usage_percent{} ${metrics.system.cpuUsage}`);

        lines.push('# HELP audio_buffer_utilization_percent Audio buffer utilization');
        lines.push('# TYPE audio_buffer_utilization_percent gauge');
        lines.push(`audio_buffer_utilization_percent{} ${metrics.quality.bufferUtilization}`);

        lines.push('# HELP audio_processing_errors_total Total number of processing errors');
        lines.push('# TYPE audio_processing_errors_total counter');
        lines.push(`audio_processing_errors_total{} ${metrics.system.errorRate}`);

        return lines.join('\n');
    }
}

/**
 * Interface for comprehensive audio metrics
 */
interface AudioMetrics {
    latency: {
        current: number;
        trend: number;
        threshold: number;
        violations: number;
    };
    quality: {
        thdn: number;
        snr: number;
        bufferUtilization: number;
        target: number;
    };
    enhancement: {
        improvement: number;
        spatialAccuracy: number;
        target: number;
        trend: number;
    };
    system: {
        cpuUsage: number;
        memoryUsage: number;
        bufferUnderruns: number;
        errorRate: number;
    };
}