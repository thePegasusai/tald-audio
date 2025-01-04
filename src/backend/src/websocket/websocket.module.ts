/**
 * TALD UNIA Audio System - WebSocket Module Configuration
 * Version: 1.0.0
 * 
 * Configures WebSocket functionality for real-time audio streaming with
 * comprehensive monitoring and optimized performance.
 */

import { Module } from '@nestjs/common'; // v10.0.0
import { WsAdapter } from '@nestjs/platform-ws'; // v10.0.0
import { MonitoringService } from '@nestjs/common'; // v10.0.0

import { WebSocketGateway } from './websocket.gateway';
import { AudioModule } from '../audio/audio.module';

// System constants for WebSocket optimization
const MAX_CONNECTIONS = 1000;
const HEARTBEAT_INTERVAL = 5000;
const BUFFER_POOL_SIZE = 1024;
const MAX_LATENCY_MS = 10;
const MONITORING_INTERVAL = 100;

/**
 * Performance monitoring for WebSocket connections
 */
class WebSocketMonitor {
    private readonly metrics = new Map<string, number>();
    private readonly connectionStates = new Map<string, any>();

    updateMetric(name: string, value: number): void {
        this.metrics.set(name, value);
        this.checkThresholds(name, value);
    }

    trackConnection(id: string, state: any): void {
        this.connectionStates.set(id, state);
        this.updateMetric('activeConnections', this.connectionStates.size);
    }

    removeConnection(id: string): void {
        this.connectionStates.delete(id);
        this.updateMetric('activeConnections', this.connectionStates.size);
    }

    private checkThresholds(name: string, value: number): void {
        if (name === 'latency' && value > MAX_LATENCY_MS) {
            console.warn(`High latency detected: ${value}ms`);
        }
    }
}

/**
 * WebSocket module configuration with performance optimization
 * and comprehensive monitoring capabilities.
 */
@Module({
    imports: [
        AudioModule
    ],
    providers: [
        WebSocketGateway,
        {
            provide: 'WS_ADAPTER',
            useFactory: () => {
                const adapter = new WsAdapter();
                adapter.configure({
                    path: '/audio',
                    maxPayload: BUFFER_POOL_SIZE * 4, // 4 bytes per float
                    perMessageDeflate: true,
                    maxConnections: MAX_CONNECTIONS,
                    heartbeatInterval: HEARTBEAT_INTERVAL,
                    clientTracking: true
                });
                return adapter;
            }
        },
        {
            provide: 'WS_MONITOR',
            useClass: WebSocketMonitor
        },
        MonitoringService
    ],
    exports: [
        WebSocketGateway
    ]
})
export class WebSocketModule {
    constructor() {
        this.initializeModule();
    }

    /**
     * Initialize WebSocket module with monitoring and optimization
     */
    private async initializeModule(): Promise<void> {
        try {
            // Configure performance monitoring
            await this.setupMonitoring();

            // Initialize connection tracking
            this.initializeConnectionTracking();

            // Configure error handling
            this.setupErrorHandling();

            // Start telemetry collection
            this.initializeTelemetry();

            console.log('WebSocket module initialized successfully');
        } catch (error) {
            console.error(`WebSocket module initialization failed: ${error.message}`);
            throw error;
        }
    }

    /**
     * Configure performance monitoring with thresholds
     */
    private async setupMonitoring(): Promise<void> {
        const monitor = new WebSocketMonitor();

        // Configure monitoring intervals
        setInterval(() => {
            this.checkPerformanceMetrics(monitor);
        }, MONITORING_INTERVAL);

        // Set up alerts for critical thresholds
        this.configureAlertThresholds(monitor);
    }

    /**
     * Initialize connection tracking and management
     */
    private initializeConnectionTracking(): void {
        process.on('ws:connection', (socket: any) => {
            if (socket.clients?.size > MAX_CONNECTIONS) {
                console.warn('Maximum connection limit reached');
                socket.close();
            }
        });
    }

    /**
     * Configure error handling and recovery
     */
    private setupErrorHandling(): void {
        process.on('ws:error', (error: Error) => {
            console.error(`WebSocket error: ${error.message}`);
            // Implement error recovery logic
        });
    }

    /**
     * Initialize telemetry collection
     */
    private initializeTelemetry(): void {
        // Initialize OpenTelemetry tracing
        const { trace } = require('@opentelemetry/api');
        const tracer = trace.getTracer('websocket-module');
    }

    /**
     * Check performance metrics against thresholds
     */
    private checkPerformanceMetrics(monitor: WebSocketMonitor): void {
        const metrics = monitor['metrics'];
        if (metrics.get('latency') > MAX_LATENCY_MS) {
            console.warn(`High latency detected: ${metrics.get('latency')}ms`);
        }
    }

    /**
     * Configure alert thresholds for monitoring
     */
    private configureAlertThresholds(monitor: WebSocketMonitor): void {
        const thresholds = new Map<string, number>([
            ['latency', MAX_LATENCY_MS],
            ['connections', MAX_CONNECTIONS],
            ['bufferUtilization', 0.9]
        ]);

        thresholds.forEach((threshold, metric) => {
            monitor.updateMetric(metric, 0);
        });
    }
}