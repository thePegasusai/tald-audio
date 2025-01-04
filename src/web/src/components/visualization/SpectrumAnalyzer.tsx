/**
 * High-performance WebGL-accelerated spectrum analyzer component for TALD UNIA Audio System
 * Version: 1.0.0
 * @package react ^18.2.0
 * @package @emotion/styled ^11.11.0
 * @package react-webgl ^2.1.0
 */

import React, { useEffect, useRef, useMemo, useCallback } from 'react';
import styled from '@emotion/styled';
import { WebGLCanvas } from 'react-webgl';
import { useVisualization } from '../../hooks/useVisualization';
import { SpectrumData, VisualizationConfig, AudioMetrics } from '../../types/visualization.types';
import { calculateRMSLevel, calculateTHD, calculatePeakHold } from '../../utils/audioUtils';

// Constants for visualization
const CANVAS_SCALE_FACTOR = window.devicePixelRatio || 1;
const BAR_SPACING_PX = 2;
const PEAK_HOLD_TIME_MS = 1000;
const FREQUENCY_LABELS = [20, 50, 100, 200, 500, 1000, 2000, 5000, 10000, 20000];
const MAGNITUDE_LABELS = [-90, -80, -70, -60, -50, -40, -30, -20, -10, 0];
const TARGET_FRAME_RATE = 60;
const CPU_USAGE_THRESHOLD = 40;

// WebGL shader sources
const WEBGL_VERTEX_SHADER = `
  attribute vec2 position;
  attribute float magnitude;
  uniform float scale;
  uniform vec2 resolution;
  
  void main() {
    vec2 pos = position;
    pos.y *= magnitude * scale;
    pos = (pos / resolution) * 2.0 - 1.0;
    gl_Position = vec4(pos, 0.0, 1.0);
  }
`;

const WEBGL_FRAGMENT_SHADER = `
  precision highp float;
  uniform vec3 color;
  uniform float intensity;
  
  void main() {
    gl_FragColor = vec4(color * intensity, 1.0);
  }
`;

// Styled components
const VisualizationContainer = styled.div<{ width: number; height: number }>`
  width: ${props => props.width}px;
  height: ${props => props.height}px;
  position: relative;
  background-color: #1a1a1a;
  border-radius: 4px;
  overflow: hidden;
`;

const Canvas = styled(WebGLCanvas)`
  position: absolute;
  top: 0;
  left: 0;
`;

const Labels = styled.div`
  position: absolute;
  pointer-events: none;
  color: rgba(255, 255, 255, 0.7);
  font-size: 10px;
  font-family: monospace;
`;

// Component props interface
interface SpectrumAnalyzerProps {
  width: number;
  height: number;
  config?: Partial<VisualizationConfig>;
  className?: string;
  showGrid?: boolean;
  showLabels?: boolean;
  enableWebGL?: boolean;
  targetFrameRate?: number;
  colorScheme?: string;
  showTHDN?: boolean;
  showPeakHold?: boolean;
}

export const SpectrumAnalyzer: React.FC<SpectrumAnalyzerProps> = ({
  width,
  height,
  config,
  className,
  showGrid = true,
  showLabels = true,
  enableWebGL = true,
  targetFrameRate = TARGET_FRAME_RATE,
  colorScheme = 'spectrum',
  showTHDN = true,
  showPeakHold = true,
}) => {
  // Hooks
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const webglContextRef = useRef<WebGLRenderingContext | null>(null);
  const shaderProgramRef = useRef<WebGLProgram | null>(null);
  const lastFrameTimeRef = useRef<number>(0);
  const peakHoldValuesRef = useRef<Float32Array>(new Float32Array(width));
  const peakHoldTimersRef = useRef<number[]>([]);

  const { spectrumData, processingStatus } = useVisualization(config);

  // Initialize WebGL context and shaders
  const initWebGL = useCallback(() => {
    if (!canvasRef.current || !enableWebGL) return;

    const gl = canvasRef.current.getContext('webgl', {
      alpha: false,
      antialias: false,
      depth: false,
      powerPreference: 'high-performance'
    });

    if (!gl) {
      console.error('WebGL not supported');
      return;
    }

    webglContextRef.current = gl;
    const program = createShaderProgram(gl, WEBGL_VERTEX_SHADER, WEBGL_FRAGMENT_SHADER);
    if (program) {
      shaderProgramRef.current = program;
    }
  }, [enableWebGL]);

  // WebGL rendering function
  const drawSpectrumWebGL = useCallback((data: SpectrumData) => {
    const gl = webglContextRef.current;
    const program = shaderProgramRef.current;
    if (!gl || !program || !data) return;

    gl.viewport(0, 0, width * CANVAS_SCALE_FACTOR, height * CANVAS_SCALE_FACTOR);
    gl.useProgram(program);

    // Set uniforms
    const scaleLocation = gl.getUniformLocation(program, 'scale');
    const resolutionLocation = gl.getUniformLocation(program, 'resolution');
    const colorLocation = gl.getUniformLocation(program, 'color');
    
    gl.uniform1f(scaleLocation, height / 2);
    gl.uniform2f(resolutionLocation, width, height);
    gl.uniform3f(colorLocation, 0.2, 0.8, 1.0);

    // Create and bind vertex buffer
    const vertices = createVertexArray(data.magnitudes, width, height);
    const vertexBuffer = gl.createBuffer();
    gl.bindBuffer(gl.ARRAY_BUFFER, vertexBuffer);
    gl.bufferData(gl.ARRAY_BUFFER, vertices, gl.STATIC_DRAW);

    // Set attributes
    const positionAttribute = gl.getAttribLocation(program, 'position');
    const magnitudeAttribute = gl.getAttribLocation(program, 'magnitude');
    
    gl.enableVertexAttribArray(positionAttribute);
    gl.enableVertexAttribArray(magnitudeAttribute);
    gl.vertexAttribPointer(positionAttribute, 2, gl.FLOAT, false, 12, 0);
    gl.vertexAttribPointer(magnitudeAttribute, 1, gl.FLOAT, false, 12, 8);

    // Draw spectrum bars
    gl.drawArrays(gl.TRIANGLES, 0, data.magnitudes.length * 6);

    // Update peak hold values
    if (showPeakHold) {
      updatePeakHold(data.magnitudes);
    }

    // Cleanup
    gl.deleteBuffer(vertexBuffer);
  }, [width, height, showPeakHold]);

  // Update peak hold values
  const updatePeakHold = useCallback((magnitudes: Float32Array) => {
    const currentTime = performance.now();
    
    for (let i = 0; i < magnitudes.length; i++) {
      if (magnitudes[i] > peakHoldValuesRef.current[i]) {
        peakHoldValuesRef.current[i] = magnitudes[i];
        peakHoldTimersRef.current[i] = currentTime;
      } else if (currentTime - peakHoldTimersRef.current[i] > PEAK_HOLD_TIME_MS) {
        peakHoldValuesRef.current[i] = magnitudes[i];
      }
    }
  }, []);

  // Animation frame handler
  useEffect(() => {
    let animationFrameId: number;

    const animate = (timestamp: number) => {
      if (timestamp - lastFrameTimeRef.current >= 1000 / targetFrameRate) {
        if (spectrumData && processingStatus.cpuLoad < CPU_USAGE_THRESHOLD) {
          drawSpectrumWebGL(spectrumData);
        }
        lastFrameTimeRef.current = timestamp;
      }
      animationFrameId = requestAnimationFrame(animate);
    };

    if (enableWebGL) {
      animationFrameId = requestAnimationFrame(animate);
    }

    return () => {
      if (animationFrameId) {
        cancelAnimationFrame(animationFrameId);
      }
    };
  }, [drawSpectrumWebGL, spectrumData, processingStatus, targetFrameRate, enableWebGL]);

  // Initialize WebGL on mount
  useEffect(() => {
    initWebGL();
    return () => {
      const gl = webglContextRef.current;
      if (gl) {
        const program = shaderProgramRef.current;
        if (program) {
          gl.deleteProgram(program);
        }
      }
    };
  }, [initWebGL]);

  return (
    <VisualizationContainer width={width} height={height} className={className}>
      <Canvas
        ref={canvasRef}
        width={width * CANVAS_SCALE_FACTOR}
        height={height * CANVAS_SCALE_FACTOR}
        style={{ width, height }}
      />
      {showLabels && (
        <Labels>
          {showTHDN && processingStatus.thdPlusN && (
            <div style={{ position: 'absolute', top: 8, right: 8 }}>
              THD+N: {processingStatus.thdPlusN.toFixed(6)}%
            </div>
          )}
        </Labels>
      )}
    </VisualizationContainer>
  );
};

// Helper functions
function createShaderProgram(
  gl: WebGLRenderingContext,
  vertexSource: string,
  fragmentSource: string
): WebGLProgram | null {
  const vertexShader = createShader(gl, gl.VERTEX_SHADER, vertexSource);
  const fragmentShader = createShader(gl, gl.FRAGMENT_SHADER, fragmentSource);
  
  if (!vertexShader || !fragmentShader) return null;

  const program = gl.createProgram();
  if (!program) return null;

  gl.attachShader(program, vertexShader);
  gl.attachShader(program, fragmentShader);
  gl.linkProgram(program);

  if (!gl.getProgramParameter(program, gl.LINK_STATUS)) {
    console.error('Unable to initialize shader program:', gl.getProgramInfoLog(program));
    return null;
  }

  return program;
}

function createShader(
  gl: WebGLRenderingContext,
  type: number,
  source: string
): WebGLShader | null {
  const shader = gl.createShader(type);
  if (!shader) return null;

  gl.shaderSource(shader, source);
  gl.compileShader(shader);

  if (!gl.getShaderParameter(shader, gl.COMPILE_STATUS)) {
    console.error('Shader compile error:', gl.getShaderInfoLog(shader));
    gl.deleteShader(shader);
    return null;
  }

  return shader;
}

function createVertexArray(
  magnitudes: Float32Array,
  width: number,
  height: number
): Float32Array {
  const vertices = new Float32Array(magnitudes.length * 18);
  const barWidth = (width - (magnitudes.length - 1) * BAR_SPACING_PX) / magnitudes.length;

  for (let i = 0; i < magnitudes.length; i++) {
    const x = i * (barWidth + BAR_SPACING_PX);
    const magnitude = Math.max(0, Math.min(1, (magnitudes[i] + 90) / 90));

    // Triangle 1
    vertices[i * 18 + 0] = x;
    vertices[i * 18 + 1] = 0;
    vertices[i * 18 + 2] = magnitude;

    vertices[i * 18 + 3] = x + barWidth;
    vertices[i * 18 + 4] = 0;
    vertices[i * 18 + 5] = magnitude;

    vertices[i * 18 + 6] = x;
    vertices[i * 18 + 7] = height;
    vertices[i * 18 + 8] = magnitude;

    // Triangle 2
    vertices[i * 18 + 9] = x + barWidth;
    vertices[i * 18 + 10] = 0;
    vertices[i * 18 + 11] = magnitude;

    vertices[i * 18 + 12] = x + barWidth;
    vertices[i * 18 + 13] = height;
    vertices[i * 18 + 14] = magnitude;

    vertices[i * 18 + 15] = x;
    vertices[i * 18 + 16] = height;
    vertices[i * 18 + 17] = magnitude;
  }

  return vertices;
}

export default SpectrumAnalyzer;