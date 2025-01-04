import '@testing-library/jest-dom';
import type { Config } from 'jest';

// Version comments for external dependencies
// @testing-library/jest-dom: ^6.1.0
// jest-environment-jsdom: ^29.0.0 
// jest-webgl-canvas-mock: ^0.2.3

/**
 * Mock implementation of AudioContext for high-fidelity audio testing
 * Supports 192kHz sample rate and advanced audio processing simulation
 */
class MockAudioContext {
  public readonly sampleRate: number = 192000;
  public readonly baseLatency: number = 0.005; // 5ms base latency
  public readonly destination: AudioDestinationNode;
  private processingOverhead: number = 0;

  constructor() {
    this.destination = {
      channelCount: 2,
      channelCountMode: 'explicit',
      channelInterpretation: 'speakers',
      maxChannelCount: 2,
    } as unknown as AudioDestinationNode;
  }

  createAnalyser(): AnalyserNode {
    return new MockAnalyserNode();
  }

  createGain(): GainNode {
    return new MockGainNode();
  }

  createBuffer(channels: number, length: number, sampleRate: number): AudioBuffer {
    return {
      length,
      numberOfChannels: channels,
      sampleRate,
      duration: length / sampleRate,
      getChannelData: (channel: number) => new Float32Array(length),
    } as AudioBuffer;
  }

  getOutputTimestamp(): AudioTimestamp {
    return {
      contextTime: performance.now() / 1000,
      performanceTime: performance.now(),
    };
  }
}

/**
 * Mock implementation of AnalyserNode for spectrum analysis testing
 * Supports FFT sizes up to 2048 for detailed frequency analysis
 */
class MockAnalyserNode {
  public fftSize: number = 2048;
  public frequencyBinCount: number = this.fftSize / 2;
  public minDecibels: number = -100;
  public maxDecibels: number = -30;
  public smoothingTimeConstant: number = 0.8;

  getFloatFrequencyData(array: Float32Array): void {
    // Simulate realistic frequency data
    for (let i = 0; i < array.length; i++) {
      array[i] = Math.random() * (this.maxDecibels - this.minDecibels) + this.minDecibels;
    }
  }

  getFloatTimeDomainData(array: Float32Array): void {
    // Simulate realistic waveform data
    for (let i = 0; i < array.length; i++) {
      array[i] = Math.sin(i / array.length * Math.PI * 2);
    }
  }
}

/**
 * Mock implementation of AudioWorkletNode for processing simulation
 * Supports performance benchmarking and memory tracking
 */
class MockAudioWorkletNode {
  private processingLoad: number = 0;
  private memoryUsage: number = 0;

  constructor(context: AudioContext, name: string, options?: AudioWorkletNodeOptions) {
    this.processingLoad = 0;
    this.memoryUsage = 0;
  }

  connect(destination: AudioNode): void {
    // Simulate processing overhead
    this.processingLoad += 5;
    this.memoryUsage += 1024 * 1024; // 1MB per connection
  }

  disconnect(): void {
    this.processingLoad = Math.max(0, this.processingLoad - 5);
    this.memoryUsage = Math.max(0, this.memoryUsage - 1024 * 1024);
  }

  getProcessingLoad(): number {
    return this.processingLoad;
  }

  getMemoryUsage(): number {
    return this.memoryUsage;
  }
}

/**
 * Mock implementation of GainNode for volume control testing
 */
class MockGainNode {
  public gain: AudioParam = {
    value: 1,
    defaultValue: 1,
    minValue: 0,
    maxValue: 1,
  } as AudioParam;

  connect(): void {}
  disconnect(): void {}
}

/**
 * Configures Jest DOM environment and extends Jest with custom DOM matchers
 */
export function setupJestDom(): void {
  // Configure viewport for responsive testing
  Object.defineProperty(window, 'innerWidth', { value: 1920 });
  Object.defineProperty(window, 'innerHeight', { value: 1080 });

  // Setup custom error handler
  window.onerror = (message, source, line, column, error) => {
    console.error('Test environment error:', { message, source, line, column, error });
  };

  // Configure performance API
  window.performance = {
    ...window.performance,
    now: () => Date.now(),
  };
}

/**
 * Implements comprehensive mocks for Web Audio API testing
 */
export function setupAudioMocks(): void {
  // Mock Web Audio API globals
  global.AudioContext = MockAudioContext as any;
  global.AudioWorkletNode = MockAudioWorkletNode as any;
  global.AnalyserNode = MockAnalyserNode as any;

  // Setup audio processing thread simulation
  jest.mock('worker-loader!./audio-processor.worker', () => {
    return class MockWorker {
      onmessage: ((event: MessageEvent) => void) | null = null;
      postMessage(data: any): void {
        if (this.onmessage) {
          this.onmessage(new MessageEvent('message', { data }));
        }
      }
    };
  });
}

/**
 * Configures WebGL context mocking for visualization testing
 */
export function setupWebGLMocks(): void {
  const mockWebGLContext = {
    canvas: document.createElement('canvas'),
    getExtension: () => ({}),
    createShader: () => ({}),
    createProgram: () => ({}),
    createBuffer: () => ({}),
    createTexture: () => ({}),
    viewport: () => {},
    clear: () => {},
    drawArrays: () => {},
  };

  // Mock canvas getContext for WebGL
  HTMLCanvasElement.prototype.getContext = function(contextType: string) {
    if (contextType === 'webgl' || contextType === 'webgl2') {
      return mockWebGLContext;
    }
    return null;
  };
}

// Configure global test environment
setupJestDom();
setupAudioMocks();
setupWebGLMocks();