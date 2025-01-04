/**
 * TALD UNIA Audio System - High-Performance Waveform Visualization Renderer
 * Version: 1.0.0
 * 
 * Implements real-time waveform visualization with optimized canvas rendering,
 * support for high-resolution audio up to 192kHz/32-bit, and adaptive performance scaling.
 */

import { WaveformData } from '../../types/visualization.types';
import { calculateRMSLevel } from '../../utils/audioUtils';
import { WebAudioContext } from '../audio/webAudioAPI';

// Constants for visualization configuration
const DEFAULT_WIDTH = 1920;
const DEFAULT_HEIGHT = 400;
const WAVEFORM_COLOR = '#00ff00';
const LINE_WIDTH = 2;
const ANIMATION_FPS = 60;
const MAX_CPU_USAGE = 40; // Maximum target CPU usage percentage
const BUFFER_SIZE = 2048;
const CACHE_SIZE = 1000;
const PIXEL_RATIO = window.devicePixelRatio || 1;

/**
 * High-performance waveform visualization renderer with adaptive optimization
 */
export class WaveformRenderer {
    private canvas: HTMLCanvasElement;
    private context: CanvasRenderingContext2D;
    private offscreenCanvas: HTMLCanvasElement;
    private offscreenContext: CanvasRenderingContext2D;
    private width: number;
    private height: number;
    private pixelRatio: number;
    private isAnimating: boolean = false;
    private waveformPath: Path2D;
    private lastFrameTime: number = 0;
    private frameCount: number = 0;
    private cpuUsage: number = 0;
    private renderCache: Map<string, any> = new Map();

    /**
     * Initialize waveform renderer with optimized canvas setup
     */
    constructor(canvas: HTMLCanvasElement, options: {
        width?: number;
        height?: number;
        color?: string;
    } = {}) {
        this.canvas = canvas;
        this.width = options.width || DEFAULT_WIDTH;
        this.height = options.height || DEFAULT_HEIGHT;
        this.pixelRatio = PIXEL_RATIO;

        // Configure main canvas
        this.canvas.width = this.width * this.pixelRatio;
        this.canvas.height = this.height * this.pixelRatio;
        this.canvas.style.width = `${this.width}px`;
        this.canvas.style.height = `${this.height}px`;
        
        this.context = this.canvas.getContext('2d', {
            alpha: false,
            desynchronized: true
        }) as CanvasRenderingContext2D;
        
        // Configure offscreen canvas for double buffering
        this.offscreenCanvas = document.createElement('canvas');
        this.offscreenCanvas.width = this.width * this.pixelRatio;
        this.offscreenCanvas.height = this.height * this.pixelRatio;
        this.offscreenContext = this.offscreenCanvas.getContext('2d', {
            alpha: false,
            desynchronized: true
        }) as CanvasRenderingContext2D;

        // Configure rendering contexts
        [this.context, this.offscreenContext].forEach(ctx => {
            ctx.scale(this.pixelRatio, this.pixelRatio);
            ctx.strokeStyle = options.color || WAVEFORM_COLOR;
            ctx.lineWidth = LINE_WIDTH;
            ctx.lineCap = 'round';
            ctx.lineJoin = 'round';
        });

        // Initialize Path2D for waveform
        this.waveformPath = new Path2D();
    }

    /**
     * Start waveform animation with performance monitoring
     */
    public start(): void {
        if (this.isAnimating) return;
        
        this.isAnimating = true;
        this.lastFrameTime = performance.now();
        this.frameCount = 0;
        this.renderCache.clear();
        
        const animate = async (timestamp: number) => {
            if (!this.isAnimating) return;

            // Calculate frame timing and CPU usage
            const frameTime = timestamp - this.lastFrameTime;
            this.frameCount++;
            
            if (this.frameCount % 60 === 0) {
                this.cpuUsage = (frameTime / (1000 / ANIMATION_FPS)) * 100;
                
                // Adapt rendering quality based on CPU usage
                if (this.cpuUsage > MAX_CPU_USAGE) {
                    this.adaptRenderingQuality();
                }
            }

            try {
                // Render frame
                await this.render({
                    samples: new Float32Array(BUFFER_SIZE),
                    sampleRate: 192000,
                    channels: 2,
                    bitDepth: 32
                });

                this.lastFrameTime = timestamp;
                requestAnimationFrame(animate);
            } catch (error) {
                console.error('Waveform rendering error:', error);
                this.stop();
            }
        };

        requestAnimationFrame(animate);
    }

    /**
     * Stop waveform animation and cleanup resources
     */
    public stop(): void {
        this.isAnimating = false;
        this.clearCanvas();
        this.renderCache.clear();
        
        // Log performance metrics
        console.debug('Waveform renderer metrics:', {
            averageCPU: this.cpuUsage.toFixed(2),
            frameCount: this.frameCount,
            cacheSize: this.renderCache.size
        });
    }

    /**
     * Render waveform frame with double buffering and optimization
     */
    public async render(data: WaveformData): Promise<void> {
        if (!this.isAnimating) return;

        // Clear offscreen canvas
        this.offscreenContext.clearRect(0, 0, this.width, this.height);

        // Generate or retrieve cached waveform path
        const pathKey = this.generatePathKey(data);
        let path = this.renderCache.get(pathKey);

        if (!path) {
            path = this.generateWaveformPath(data);
            
            // Cache path if CPU usage is acceptable
            if (this.cpuUsage < MAX_CPU_USAGE) {
                this.renderCache.set(pathKey, path);
                
                // Limit cache size
                if (this.renderCache.size > CACHE_SIZE) {
                    const firstKey = this.renderCache.keys().next().value;
                    this.renderCache.delete(firstKey);
                }
            }
        }

        // Render to offscreen canvas
        this.offscreenContext.save();
        this.offscreenContext.beginPath();
        this.offscreenContext.stroke(path);
        this.offscreenContext.restore();

        // Swap with main canvas
        this.context.clearRect(0, 0, this.width, this.height);
        this.context.drawImage(this.offscreenCanvas, 0, 0);
    }

    /**
     * Handle canvas resize with HiDPI support
     */
    public resize(width: number, height: number): void {
        this.width = width;
        this.height = height;

        // Resize both canvases
        [this.canvas, this.offscreenCanvas].forEach(canvas => {
            canvas.width = width * this.pixelRatio;
            canvas.height = height * this.pixelRatio;
        });

        this.canvas.style.width = `${width}px`;
        this.canvas.style.height = `${height}px`;

        // Reconfigure contexts
        [this.context, this.offscreenContext].forEach(ctx => {
            ctx.scale(this.pixelRatio, this.pixelRatio);
            ctx.strokeStyle = WAVEFORM_COLOR;
            ctx.lineWidth = LINE_WIDTH;
            ctx.lineCap = 'round';
            ctx.lineJoin = 'round';
        });

        // Clear cache due to dimension change
        this.renderCache.clear();
    }

    /**
     * Generate optimized waveform path from audio data
     */
    private generateWaveformPath(data: WaveformData): Path2D {
        const path = new Path2D();
        const samples = data.samples;
        const step = Math.ceil(samples.length / this.width);
        const amplitude = this.height / 2;

        path.moveTo(0, amplitude);

        for (let i = 0; i < this.width; i++) {
            const index = i * step;
            const slice = samples.slice(index, index + step);
            const rms = calculateRMSLevel(slice);
            const y = amplitude + (rms * amplitude);
            
            path.lineTo(i, y);
        }

        return path;
    }

    /**
     * Generate cache key for waveform path
     */
    private generatePathKey(data: WaveformData): string {
        const sampleSum = data.samples.reduce((a, b) => a + b, 0);
        return `${sampleSum}-${data.sampleRate}-${this.width}-${this.height}`;
    }

    /**
     * Clear canvas with optimized call
     */
    private clearCanvas(): void {
        this.context.clearRect(0, 0, this.width, this.height);
        this.offscreenContext.clearRect(0, 0, this.width, this.height);
    }

    /**
     * Adapt rendering quality based on performance metrics
     */
    private adaptRenderingQuality(): void {
        // Clear render cache to reduce memory usage
        this.renderCache.clear();
        
        // Reduce rendering resolution if needed
        if (this.cpuUsage > MAX_CPU_USAGE * 1.5) {
            this.context.imageSmoothingEnabled = false;
            this.offscreenContext.imageSmoothingEnabled = false;
        } else {
            this.context.imageSmoothingEnabled = true;
            this.offscreenContext.imageSmoothingEnabled = true;
        }
    }
}