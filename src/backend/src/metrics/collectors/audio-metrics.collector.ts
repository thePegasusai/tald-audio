import { Injectable, Logger } from '@nestjs/common'; // v10.0.0
import { Gauge, Counter, Histogram, Registry } from 'prom-client'; // v14.2.0
import { AudioService } from '../../audio/audio.service';

// Constants for metrics configuration
const MAX_LATENCY_MS = 10;
const TARGET_THDN_PERCENT = 0.0005;
const TARGET_ENHANCEMENT_PERCENT = 20;
const METRICS_UPDATE_INTERVAL_MS = 1000;
const METRIC_BUFFER_SIZE = 1000;
const ALERT_THRESHOLD_VIOLATIONS = 3;
const TREND_ANALYSIS_WINDOW_MS = 300000; // 5 minutes

/**
 * Buffer for storing metric history for trend analysis
 */
class MetricBuffer {
    private buffer: Map<string, number[]> = new Map();
    private readonly size: number;

    constructor(size: number) {
        this.size = size;
    }

    add(metric: string, value: number): void {
        if (!this.buffer.has(metric)) {
            this.buffer.set(metric, []);
        }
        const values = this.buffer.get(metric)!;
        values.push(value);
        if (values.length > this.size) {
            values.shift();
        }
    }

    getAverage(metric: string): number {
        const values = this.buffer.get(metric);
        if (!values || values.length === 0) return 0;
        return values.reduce((a, b) => a + b, 0) / values.length;
    }

    getTrend(metric: string): number {
        const values = this.buffer.get(metric);
        if (!values || values.length < 2) return 0;
        const recentAvg = values.slice(-10).reduce((a, b) => a + b, 0) / 10;
        const oldAvg = values.slice(0, 10).reduce((a, b) => a + b, 0) / 10;
        return (recentAvg - oldAvg) / oldAvg;
    }
}

@Injectable()
export class AudioMetricsCollector {
    private readonly logger = new Logger(AudioMetricsCollector.name);
    private readonly metricRegistry: Registry;
    private readonly metricBuffer: MetricBuffer;

    // Prometheus metrics
    private readonly latencyGauge: Gauge<string>;
    private readonly thdnGauge: Gauge<string>;
    private readonly enhancementGauge: Gauge<string>;
    private readonly bufferUtilizationGauge: Gauge<string>;
    private readonly processingErrorCounter: Counter<string>;
    private readonly latencyHistogram: Histogram<string>;

    constructor(private readonly audioService: AudioService) {
        // Initialize metric registry
        this.metricRegistry = new Registry();
        this.metricBuffer = new MetricBuffer(METRIC_BUFFER_SIZE);

        // Initialize Prometheus metrics
        this.latencyGauge = new Gauge({
            name: 'audio_processing_latency_ms',
            help: 'Audio processing latency in milliseconds',
            labelNames: ['stage']
        });

        this.thdnGauge = new Gauge({
            name: 'audio_thdn_percent',
            help: 'Total Harmonic Distortion plus Noise percentage',
            labelNames: ['channel']
        });

        this.enhancementGauge = new Gauge({
            name: 'audio_enhancement_improvement_percent',
            help: 'AI enhancement quality improvement percentage',
            labelNames: ['type']
        });

        this.bufferUtilizationGauge = new Gauge({
            name: 'audio_buffer_utilization_percent',
            help: 'Audio buffer utilization percentage',
            labelNames: ['buffer_type']
        });

        this.processingErrorCounter = new Counter({
            name: 'audio_processing_errors_total',
            help: 'Total number of audio processing errors',
            labelNames: ['error_type']
        });

        this.latencyHistogram = new Histogram({
            name: 'audio_latency_distribution_ms',
            help: 'Distribution of audio processing latency',
            buckets: [1, 2, 5, 10, 20, 50]
        });

        // Register metrics
        this.metricRegistry.registerMetric(this.latencyGauge);
        this.metricRegistry.registerMetric(this.thdnGauge);
        this.metricRegistry.registerMetric(this.enhancementGauge);
        this.metricRegistry.registerMetric(this.bufferUtilizationGauge);
        this.metricRegistry.registerMetric(this.processingErrorCounter);
        this.metricRegistry.registerMetric(this.latencyHistogram);

        // Start metric collection
        this.startMetricCollection();
    }

    /**
     * Collects and records audio processing latency metrics
     */
    private async collectLatencyMetrics(): Promise<void> {
        try {
            const stats = this.audioService.getProcessingStats();
            
            // Record latency metrics
            this.latencyGauge.labels('total').set(stats.processingLatency);
            this.latencyHistogram.observe(stats.processingLatency);
            
            // Buffer for trend analysis
            this.metricBuffer.add('latency', stats.processingLatency);

            // Check latency threshold
            if (stats.processingLatency > MAX_LATENCY_MS) {
                this.logger.warn(
                    `High latency detected: ${stats.processingLatency.toFixed(2)}ms`
                );
            }

            // Record latency trend
            const latencyTrend = this.metricBuffer.getTrend('latency');
            this.latencyGauge.labels('trend').set(latencyTrend);

        } catch (error) {
            this.logger.error(`Error collecting latency metrics: ${error.message}`);
            this.processingErrorCounter.labels('latency_collection').inc();
        }
    }

    /**
     * Collects and records audio quality metrics
     */
    private async collectQualityMetrics(): Promise<void> {
        try {
            const stats = this.audioService.getQualityMetrics();
            
            // Record THD+N metrics
            this.thdnGauge.labels('left').set(stats.thdLeft);
            this.thdnGauge.labels('right').set(stats.thdRight);
            
            // Buffer for trend analysis
            this.metricBuffer.add('thdn', (stats.thdLeft + stats.thdRight) / 2);

            // Check THD+N threshold
            if (stats.thdLeft > TARGET_THDN_PERCENT || stats.thdRight > TARGET_THDN_PERCENT) {
                this.logger.warn(
                    `High THD+N detected: L=${stats.thdLeft.toFixed(4)}%, R=${stats.thdRight.toFixed(4)}%`
                );
            }

            // Record buffer utilization
            this.bufferUtilizationGauge.labels('processing').set(stats.bufferUtilization);

        } catch (error) {
            this.logger.error(`Error collecting quality metrics: ${error.message}`);
            this.processingErrorCounter.labels('quality_collection').inc();
        }
    }

    /**
     * Collects and records AI enhancement metrics
     */
    private async collectEnhancementMetrics(): Promise<void> {
        try {
            const stats = this.audioService.getEnhancementStats();
            
            // Record enhancement metrics
            this.enhancementGauge.labels('overall').set(stats.qualityImprovement);
            this.enhancementGauge.labels('spatial').set(stats.spatialAccuracy);
            
            // Buffer for trend analysis
            this.metricBuffer.add('enhancement', stats.qualityImprovement);

            // Check enhancement target
            if (stats.qualityImprovement < TARGET_ENHANCEMENT_PERCENT) {
                this.logger.warn(
                    `Low enhancement effectiveness: ${stats.qualityImprovement.toFixed(1)}%`
                );
            }

            // Record enhancement trend
            const enhancementTrend = this.metricBuffer.getTrend('enhancement');
            this.enhancementGauge.labels('trend').set(enhancementTrend);

        } catch (error) {
            this.logger.error(`Error collecting enhancement metrics: ${error.message}`);
            this.processingErrorCounter.labels('enhancement_collection').inc();
        }
    }

    /**
     * Retrieves current audio metrics with detailed statistics
     */
    public async getMetrics(): Promise<AudioMetrics> {
        return {
            latency: {
                current: this.metricBuffer.getAverage('latency'),
                trend: this.metricBuffer.getTrend('latency'),
                threshold: MAX_LATENCY_MS
            },
            quality: {
                thdn: this.metricBuffer.getAverage('thdn'),
                target: TARGET_THDN_PERCENT,
                bufferUtilization: await this.getBufferUtilization()
            },
            enhancement: {
                improvement: this.metricBuffer.getAverage('enhancement'),
                target: TARGET_ENHANCEMENT_PERCENT,
                trend: this.metricBuffer.getTrend('enhancement')
            },
            errors: {
                total: await this.getTotalErrors(),
                byType: await this.getErrorsByType()
            }
        };
    }

    /**
     * Starts periodic metric collection
     */
    private startMetricCollection(): void {
        setInterval(async () => {
            await this.collectLatencyMetrics();
            await this.collectQualityMetrics();
            await this.collectEnhancementMetrics();
        }, METRICS_UPDATE_INTERVAL_MS);
    }

    private async getBufferUtilization(): Promise<number> {
        return this.bufferUtilizationGauge.labels('processing').get();
    }

    private async getTotalErrors(): Promise<number> {
        return this.processingErrorCounter.labels('total').get();
    }

    private async getErrorsByType(): Promise<Map<string, number>> {
        const errorTypes = ['latency_collection', 'quality_collection', 'enhancement_collection'];
        const errors = new Map<string, number>();
        
        for (const type of errorTypes) {
            errors.set(type, await this.processingErrorCounter.labels(type).get());
        }
        
        return errors;
    }
}

interface AudioMetrics {
    latency: {
        current: number;
        trend: number;
        threshold: number;
    };
    quality: {
        thdn: number;
        target: number;
        bufferUtilization: number;
    };
    enhancement: {
        improvement: number;
        target: number;
        trend: number;
    };
    errors: {
        total: number;
        byType: Map<string, number>;
    };
}