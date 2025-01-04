/**
 * TALD UNIA Audio System - High-Performance Spectrum Analyzer
 * Version: 1.0.0
 * 
 * WebGL-accelerated real-time spectrum analyzer with THD+N visualization
 * and sub-10ms latency performance monitoring.
 * 
 * @package webgl-plot ^0.7.0
 * @package standardized-audio-context ^25.3.0
 */

import { WebAudioContext } from '../audio/webAudioAPI';
import { SpectrumData, VisualizationConfig } from '../../types/visualization.types';
import { calculateRMSLevel, calculateTHD } from '../../utils/audioUtils';
import { WebGLPlot, WebGLLine } from 'webgl-plot'; // v0.7.0

// System constants
const DEFAULT_FFT_SIZE = 2048;
const DEFAULT_SMOOTHING_TIME_CONSTANT = 0.8;
const MIN_DECIBELS = -90;
const MAX_DECIBELS = -10;
const MIN_FREQUENCY = 20;
const MAX_FREQUENCY = 20000;
const BUFFER_POOL_SIZE = 8;
const TARGET_FRAME_TIME = 10; // 10ms target for real-time performance

// WebGL shader constants
const WEBGL_VERTEX_SHADER = `
  precision mediump float;
  attribute vec2 position;
  void main() {
    gl_Position = vec4(position, 0.0, 1.0);
  }
`;

const WEBGL_FRAGMENT_SHADER = `
  precision mediump float;
  uniform vec4 color;
  void main() {
    gl_FragColor = color;
  }
`;

/**
 * High-performance spectrum analyzer with WebGL acceleration
 * and THD+N visualization capabilities
 */
export class SpectrumAnalyzer {
  private analyserNode: AnalyserNode;
  private config: VisualizationConfig;
  private frequencyData: Float32Array;
  private timeData: Float32Array;
  private sampleRate: number;
  private webglPlot: WebGLPlot | null = null;
  private spectrumLine: WebGLLine | null = null;
  private bufferPool: Float32Array[];
  private lastFrameTime: number = 0;
  private canvas: HTMLCanvasElement;
  private gl: WebGLRenderingContext | null = null;
  private shaderProgram: WebGLProgram | null = null;

  /**
   * Initialize spectrum analyzer with WebGL support
   */
  constructor(config: VisualizationConfig) {
    this.validateConfig(config);
    this.config = {
      ...config,
      fftSize: config.fftSize || DEFAULT_FFT_SIZE,
      smoothingTimeConstant: config.smoothingTimeConstant || DEFAULT_SMOOTHING_TIME_CONSTANT
    };

    // Initialize buffer pool for memory efficiency
    this.bufferPool = Array(BUFFER_POOL_SIZE).fill(null).map(() => 
      new Float32Array(this.config.fftSize)
    );

    // Setup WebGL context if supported
    this.setupWebGL();
  }

  /**
   * Initialize analyzer node with optimal configuration
   */
  public async initialize(audioContext: WebAudioContext): Promise<void> {
    try {
      this.analyserNode = await audioContext.createAnalyserNode({
        fftSize: this.config.fftSize,
        smoothingTimeConstant: this.config.smoothingTimeConstant,
        minDecibels: this.config.minDecibels,
        maxDecibels: this.config.maxDecibels
      });

      this.sampleRate = audioContext.getAnalyserData().sampleRate;
      this.frequencyData = new Float32Array(this.analyserNode.frequencyBinCount);
      this.timeData = new Float32Array(this.config.fftSize);

      // Initialize WebGL plot if available
      if (this.gl && this.webglPlot) {
        this.spectrumLine = new WebGLLine(this.frequencyData.length);
        this.webglPlot.addLine(this.spectrumLine);
      }
    } catch (error) {
      console.error('Spectrum analyzer initialization failed:', error);
      throw error;
    }
  }

  /**
   * Perform real-time spectrum analysis with WebGL acceleration
   */
  public analyze(): SpectrumData {
    const startTime = performance.now();

    // Get current frequency data using buffer pool
    const currentBuffer = this.getNextBuffer();
    this.analyserNode.getFloatFrequencyData(currentBuffer);

    // Get time domain data for THD calculation
    this.analyserNode.getFloatTimeDomainData(this.timeData);

    // Calculate THD+N
    const thd = calculateTHD(this.timeData, this.sampleRate);
    const rmsLevel = calculateRMSLevel(this.timeData);

    // Apply frequency scaling and normalization
    const frequencies = this.calculateFrequencyScale();
    const magnitudes = this.normalizeFrequencyData(currentBuffer);

    // Render using WebGL if available
    if (this.webglPlot && this.spectrumLine) {
      this.updateWebGLPlot(magnitudes);
    }

    // Calculate frame timing
    const frameTime = performance.now() - startTime;
    if (frameTime > TARGET_FRAME_TIME) {
      console.warn(`Frame time exceeded target: ${frameTime.toFixed(2)}ms`);
    }
    this.lastFrameTime = frameTime;

    return {
      frequencies,
      magnitudes,
      timestamp: Date.now(),
      sampleRate: this.sampleRate,
      resolution: this.sampleRate / this.config.fftSize
    };
  }

  /**
   * Update analyzer configuration with performance optimization
   */
  public updateConfig(newConfig: Partial<VisualizationConfig>): void {
    this.validateConfig({ ...this.config, ...newConfig });
    
    const requiresResize = newConfig.fftSize && newConfig.fftSize !== this.config.fftSize;
    
    if (requiresResize) {
      this.resizeBuffers(newConfig.fftSize!);
    }

    Object.assign(this.config, newConfig);
    
    if (this.analyserNode) {
      this.updateAnalyserNode();
    }

    if (this.webglPlot && requiresResize) {
      this.updateWebGLPlot(new Float32Array(this.frequencyData.length));
    }
  }

  private setupWebGL(): void {
    this.canvas = document.createElement('canvas');
    this.gl = this.canvas.getContext('webgl2');

    if (this.gl) {
      this.shaderProgram = this.createShaderProgram();
      this.webglPlot = new WebGLPlot(this.canvas);
    } else {
      console.warn('WebGL acceleration not available, falling back to Canvas rendering');
    }
  }

  private createShaderProgram(): WebGLProgram {
    const gl = this.gl!;
    const program = gl.createProgram()!;

    const vertexShader = this.compileShader(WEBGL_VERTEX_SHADER, gl.VERTEX_SHADER);
    const fragmentShader = this.compileShader(WEBGL_FRAGMENT_SHADER, gl.FRAGMENT_SHADER);

    gl.attachShader(program, vertexShader);
    gl.attachShader(program, fragmentShader);
    gl.linkProgram(program);

    if (!gl.getProgramParameter(program, gl.LINK_STATUS)) {
      throw new Error('Failed to initialize WebGL shader program');
    }

    return program;
  }

  private compileShader(source: string, type: number): WebGLShader {
    const gl = this.gl!;
    const shader = gl.createShader(type)!;
    
    gl.shaderSource(shader, source);
    gl.compileShader(shader);

    if (!gl.getShaderParameter(shader, gl.COMPILE_STATUS)) {
      throw new Error(`Shader compilation failed: ${gl.getShaderInfoLog(shader)}`);
    }

    return shader;
  }

  private updateWebGLPlot(magnitudes: Float32Array): void {
    if (!this.webglPlot || !this.spectrumLine) return;

    this.spectrumLine.setData(magnitudes);
    this.webglPlot.update();
  }

  private getNextBuffer(): Float32Array {
    return this.bufferPool[Date.now() % BUFFER_POOL_SIZE];
  }

  private calculateFrequencyScale(): Float32Array {
    const frequencies = new Float32Array(this.frequencyData.length);
    for (let i = 0; i < frequencies.length; i++) {
      frequencies[i] = (i * this.sampleRate) / (2 * this.frequencyData.length);
    }
    return frequencies;
  }

  private normalizeFrequencyData(data: Float32Array): Float32Array {
    const normalized = new Float32Array(data.length);
    const range = this.config.maxDecibels - this.config.minDecibels;

    for (let i = 0; i < data.length; i++) {
      normalized[i] = (data[i] - this.config.minDecibels) / range;
    }

    return normalized;
  }

  private resizeBuffers(newSize: number): void {
    this.frequencyData = new Float32Array(newSize / 2);
    this.timeData = new Float32Array(newSize);
    this.bufferPool = Array(BUFFER_POOL_SIZE).fill(null).map(() => 
      new Float32Array(newSize)
    );
  }

  private updateAnalyserNode(): void {
    if (!this.analyserNode) return;

    this.analyserNode.fftSize = this.config.fftSize;
    this.analyserNode.smoothingTimeConstant = this.config.smoothingTimeConstant;
    this.analyserNode.minDecibels = this.config.minDecibels;
    this.analyserNode.maxDecibels = this.config.maxDecibels;
  }

  private validateConfig(config: Partial<VisualizationConfig>): void {
    if (config.fftSize && (config.fftSize < 32 || config.fftSize > 32768 || (config.fftSize & (config.fftSize - 1)) !== 0)) {
      throw new Error('FFT size must be a power of 2 between 32 and 32768');
    }

    if (config.smoothingTimeConstant && (config.smoothingTimeConstant < 0 || config.smoothingTimeConstant > 1)) {
      throw new Error('Smoothing time constant must be between 0 and 1');
    }

    if (config.minFrequency && config.minFrequency < MIN_FREQUENCY) {
      throw new Error(`Minimum frequency cannot be less than ${MIN_FREQUENCY}Hz`);
    }

    if (config.maxFrequency && config.maxFrequency > MAX_FREQUENCY) {
      throw new Error(`Maximum frequency cannot exceed ${MAX_FREQUENCY}Hz`);
    }
  }
}