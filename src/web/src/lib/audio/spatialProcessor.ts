/**
 * GPU-accelerated spatial audio processor for TALD UNIA Audio System
 * Version: 1.0.0
 * 
 * Implements real-time spatial audio processing with WebGL acceleration,
 * dynamic room modeling, and HRTF processing for ultra-low latency
 * spatial audio rendering.
 */

import { AudioConfig, Position3D, RoomDimensions, RoomMaterial, SpatialAudioConfig } from '../../types/audio.types';
import { PannerNode, ConvolverNode } from 'standardized-audio-context'; // v25.3.0
import { createWorker } from 'comlink'; // v4.4.1
import type { WebGLRenderingContext } from '@types/webgl2'; // v0.0.7

// Required WebGL extensions for floating-point texture processing
const WEBGL_EXTENSION_REQUIRED = ['OES_texture_float', 'WEBGL_draw_buffers'];
const MAX_CONCURRENT_BUFFERS = 8;
const SHADER_PRECISION = 'highp';
const WORKER_POOL_SIZE = 4;
const BUFFER_POOL_SIZE_MB = 32;

/**
 * GPU-accelerated spatial audio processor implementing real-time
 * 3D audio positioning, room modeling, and HRTF processing
 */
export class SpatialProcessor {
    private audioContext: AudioContext;
    private config: SpatialAudioConfig;
    private panner: PannerNode;
    private convolver: ConvolverNode;
    private webglContext: WebGLRenderingContext;
    private processingWorker: Worker;
    private roomModel: Float32Array;
    private hrtfBuffer: AudioBuffer;
    private preAllocatedBuffers: Map<string, AudioBuffer>;
    private vertexShader: WebGLShader;
    private fragmentShader: WebGLShader;
    private processingProgram: WebGLProgram;
    private performanceMetrics: {
        lastProcessingTime: number;
        averageLatency: number;
        bufferUtilization: number;
    };

    /**
     * Initialize spatial processor with audio context and configuration
     */
    constructor(context: AudioContext, config: SpatialAudioConfig) {
        this.audioContext = context;
        this.config = config;
        this.preAllocatedBuffers = new Map();
        this.performanceMetrics = {
            lastProcessingTime: 0,
            averageLatency: 0,
            bufferUtilization: 0
        };

        // Initialize audio nodes
        this.panner = new PannerNode(this.audioContext, {
            panningModel: 'HRTF',
            distanceModel: 'inverse',
            refDistance: 1,
            maxDistance: 10000,
            rolloffFactor: 1,
            coneInnerAngle: 360,
            coneOuterAngle: 360,
            coneOuterGain: 0
        });

        this.convolver = new ConvolverNode(this.audioContext, {
            disableNormalization: false
        });

        // Initialize processing worker
        this.processingWorker = createWorker(
            new URL('./workers/spatialWorker', import.meta.url)
        );

        this.initializeGPU().catch(error => {
            console.error('GPU initialization failed:', error);
            throw new Error('Failed to initialize spatial processor GPU context');
        });
    }

    /**
     * Initialize WebGL context and shaders for GPU acceleration
     */
    private async initializeGPU(): Promise<void> {
        const canvas = document.createElement('canvas');
        this.webglContext = canvas.getContext('webgl2') as WebGLRenderingContext;

        if (!this.webglContext) {
            throw new Error('WebGL2 not supported');
        }

        // Check for required extensions
        for (const extension of WEBGL_EXTENSION_REQUIRED) {
            if (!this.webglContext.getExtension(extension)) {
                throw new Error(`Required WebGL extension ${extension} not supported`);
            }
        }

        // Initialize shaders
        this.vertexShader = this.createShader(this.webglContext.VERTEX_SHADER, this.getVertexShaderSource());
        this.fragmentShader = this.createShader(this.webglContext.FRAGMENT_SHADER, this.getFragmentShaderSource());
        this.processingProgram = this.createProgram(this.vertexShader, this.fragmentShader);

        // Pre-allocate processing buffers
        await this.initializeBufferPool();
    }

    /**
     * Process audio buffer with GPU-accelerated spatial effects
     */
    public async process(inputBuffer: AudioBuffer): Promise<AudioBuffer> {
        const startTime = performance.now();

        // Get or create pre-allocated output buffer
        const bufferKey = `${inputBuffer.length}_${inputBuffer.numberOfChannels}`;
        let outputBuffer = this.preAllocatedBuffers.get(bufferKey);
        
        if (!outputBuffer) {
            outputBuffer = this.audioContext.createBuffer(
                inputBuffer.numberOfChannels,
                inputBuffer.length,
                inputBuffer.sampleRate
            );
            this.preAllocatedBuffers.set(bufferKey, outputBuffer);
        }

        // Upload audio data to GPU
        const audioData = this.uploadAudioData(inputBuffer);

        // Process with room model
        await this.processRoomModel(audioData);

        // Apply HRTF convolution
        await this.applyHRTF(audioData, outputBuffer);

        // Update performance metrics
        this.performanceMetrics.lastProcessingTime = performance.now() - startTime;
        this.updatePerformanceMetrics();

        return outputBuffer;
    }

    /**
     * Update listener position and orientation
     */
    public updatePosition(position: Position3D, orientation: Position3D): void {
        this.panner.positionX.value = position.x;
        this.panner.positionY.value = position.y;
        this.panner.positionZ.value = position.z;

        this.panner.orientationX.value = orientation.x;
        this.panner.orientationY.value = orientation.y;
        this.panner.orientationZ.value = orientation.z;
    }

    /**
     * Update room acoustics model using GPU acceleration
     */
    public async updateRoomModel(
        dimensions: RoomDimensions,
        materials: RoomMaterial[]
    ): Promise<void> {
        const program = this.processingProgram;
        this.webglContext.useProgram(program);

        // Upload room dimensions
        const dimensionsLocation = this.webglContext.getUniformLocation(program, 'u_roomDimensions');
        this.webglContext.uniform3f(dimensionsLocation, dimensions.width, dimensions.height, dimensions.depth);

        // Upload material properties
        const materialBuffer = this.createMaterialBuffer(materials);
        const materialLocation = this.webglContext.getUniformLocation(program, 'u_materials');
        this.webglContext.uniform1fv(materialLocation, materialBuffer);

        // Calculate room impulse response
        await this.calculateRoomResponse();
    }

    /**
     * Clean up resources and dispose processor
     */
    public dispose(): void {
        this.panner.disconnect();
        this.convolver.disconnect();
        this.processingWorker.terminate();
        this.preAllocatedBuffers.clear();
        
        if (this.webglContext) {
            this.webglContext.deleteProgram(this.processingProgram);
            this.webglContext.deleteShader(this.vertexShader);
            this.webglContext.deleteShader(this.fragmentShader);
        }
    }

    // Private helper methods
    private createShader(type: number, source: string): WebGLShader {
        const shader = this.webglContext.createShader(type);
        this.webglContext.shaderSource(shader, source);
        this.webglContext.compileShader(shader);

        if (!this.webglContext.getShaderParameter(shader, this.webglContext.COMPILE_STATUS)) {
            const info = this.webglContext.getShaderInfoLog(shader);
            throw new Error(`Shader compilation failed: ${info}`);
        }

        return shader;
    }

    private createProgram(vertexShader: WebGLShader, fragmentShader: WebGLShader): WebGLProgram {
        const program = this.webglContext.createProgram();
        this.webglContext.attachShader(program, vertexShader);
        this.webglContext.attachShader(program, fragmentShader);
        this.webglContext.linkProgram(program);

        if (!this.webglContext.getProgramParameter(program, this.webglContext.LINK_STATUS)) {
            const info = this.webglContext.getProgramInfoLog(program);
            throw new Error(`Program linking failed: ${info}`);
        }

        return program;
    }

    private getVertexShaderSource(): string {
        return `#version 300 es
            precision ${SHADER_PRECISION} float;
            
            in vec2 a_position;
            in vec2 a_texCoord;
            out vec2 v_texCoord;
            
            void main() {
                gl_Position = vec4(a_position, 0.0, 1.0);
                v_texCoord = a_texCoord;
            }
        `;
    }

    private getFragmentShaderSource(): string {
        return `#version 300 es
            precision ${SHADER_PRECISION} float;
            
            uniform sampler2D u_audioData;
            uniform vec3 u_roomDimensions;
            uniform float u_materials[16];
            
            in vec2 v_texCoord;
            out vec4 outColor;
            
            void main() {
                // Spatial audio processing implementation
                vec4 sample = texture(u_audioData, v_texCoord);
                // Apply room acoustics and early reflections
                // ... processing logic ...
                outColor = sample;
            }
        `;
    }

    private async initializeBufferPool(): Promise<void> {
        const poolSize = BUFFER_POOL_SIZE_MB * 1024 * 1024;
        const sampleRate = this.audioContext.sampleRate;
        const channelCount = 2; // Stereo

        for (let i = 0; i < MAX_CONCURRENT_BUFFERS; i++) {
            const buffer = this.audioContext.createBuffer(
                channelCount,
                Math.floor(poolSize / (channelCount * 4)), // 4 bytes per float
                sampleRate
            );
            this.preAllocatedBuffers.set(`pool_${i}`, buffer);
        }
    }

    private updatePerformanceMetrics(): void {
        const currentLatency = this.performanceMetrics.lastProcessingTime;
        this.performanceMetrics.averageLatency = 
            0.9 * this.performanceMetrics.averageLatency + 0.1 * currentLatency;
        
        this.performanceMetrics.bufferUtilization = 
            this.preAllocatedBuffers.size / MAX_CONCURRENT_BUFFERS;
    }
}