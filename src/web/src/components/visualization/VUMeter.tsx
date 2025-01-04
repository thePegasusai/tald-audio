import React, { useEffect, useRef, useState, useMemo } from 'react';
import styled from 'styled-components';
import { calculateRMSLevel, calculatePeakLevel } from '../../utils/audioUtils';
import { WebAudioContext } from '../../lib/audio/webAudioAPI';

// Constants for meter configuration
const METER_MIN_DB = -60;
const METER_MAX_DB = 12;
const PEAK_HOLD_TIME_MS = 2000;
const UPDATE_INTERVAL_MS = 16.7; // ~60fps
const METER_SCALE_POINTS = [-60, -50, -40, -30, -20, -10, 0, 3, 6, 12];
const REFERENCE_LEVEL_DB = 0;
const OVERLOAD_THRESHOLD_DB = 3;
const BALLISTICS_ATTACK_MS = 5;
const BALLISTICS_RELEASE_MS = 100;

// Styled components
const MeterContainer = styled.div<{ width: number; height: number }>`
  width: ${props => props.width}px;
  height: ${props => props.height}px;
  position: relative;
  background-color: #1a1a1a;
  border-radius: 4px;
  overflow: hidden;
  box-shadow: 0 2px 4px rgba(0, 0, 0, 0.2);
`;

const Canvas = styled.canvas`
  position: absolute;
  top: 0;
  left: 0;
`;

const NumericDisplay = styled.div`
  position: absolute;
  right: 8px;
  top: 50%;
  transform: translateY(-50%);
  color: #ffffff;
  font-family: 'SF Mono', monospace;
  font-size: 12px;
  text-shadow: 0 1px 2px rgba(0, 0, 0, 0.5);
`;

interface VUMeterProps {
  audioContext: WebAudioContext;
  width: number;
  height: number;
  showPeakHold?: boolean;
  showNumericReadout?: boolean;
  colorTheme?: 'classic' | 'modern' | 'professional';
  referenceLevel?: number;
}

export const VUMeter: React.FC<VUMeterProps> = ({
  audioContext,
  width,
  height,
  showPeakHold = true,
  showNumericReadout = true,
  colorTheme = 'professional',
  referenceLevel = REFERENCE_LEVEL_DB
}) => {
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const [rmsLevel, setRmsLevel] = useState<number>(METER_MIN_DB);
  const [peakLevel, setPeakLevel] = useState<number>(METER_MIN_DB);
  const [peakHoldLevel, setPeakHoldLevel] = useState<number>(METER_MIN_DB);
  const [overloadCount, setOverloadCount] = useState<number>(0);
  const animationFrameRef = useRef<number>();
  const lastUpdateTimeRef = useRef<number>(0);
  const peakHoldTimeoutRef = useRef<NodeJS.Timeout>();

  // Memoize color gradient based on theme
  const colorGradient = useMemo(() => {
    const ctx = canvasRef.current?.getContext('2d');
    if (!ctx) return null;

    const gradient = ctx.createLinearGradient(0, 0, width, 0);
    switch (colorTheme) {
      case 'classic':
        gradient.addColorStop(0, '#2ecc71');
        gradient.addColorStop(0.6, '#f1c40f');
        gradient.addColorStop(0.8, '#e67e22');
        gradient.addColorStop(1, '#e74c3c');
        break;
      case 'modern':
        gradient.addColorStop(0, '#00ff88');
        gradient.addColorStop(0.7, '#00ffff');
        gradient.addColorStop(0.9, '#ff00ff');
        gradient.addColorStop(1, '#ff0000');
        break;
      case 'professional':
      default:
        gradient.addColorStop(0, '#1abc9c');
        gradient.addColorStop(0.5, '#3498db');
        gradient.addColorStop(0.75, '#f39c12');
        gradient.addColorStop(0.9, '#e74c3c');
        gradient.addColorStop(1, '#c0392b');
    }
    return gradient;
  }, [colorTheme, width]);

  // Initialize canvas and start animation
  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;

    canvas.width = width * window.devicePixelRatio;
    canvas.height = height * window.devicePixelRatio;
    canvas.style.width = `${width}px`;
    canvas.style.height = `${height}px`;

    const ctx = canvas.getContext('2d');
    if (!ctx) return;
    ctx.scale(window.devicePixelRatio, window.devicePixelRatio);

    const updateMeter = (timestamp: number) => {
      if (timestamp - lastUpdateTimeRef.current >= UPDATE_INTERVAL_MS) {
        const analyzerData = audioContext.getAnalyserData();
        const highResData = audioContext.getHighResolutionData();

        // Calculate levels with industry-standard ballistics
        const instantRms = calculateRMSLevel(analyzerData);
        const instantPeak = calculatePeakLevel(highResData);

        // Apply ballistics
        const deltaTime = timestamp - lastUpdateTimeRef.current;
        const attackCoeff = Math.exp(-deltaTime / BALLISTICS_ATTACK_MS);
        const releaseCoeff = Math.exp(-deltaTime / BALLISTICS_RELEASE_MS);

        setRmsLevel(prev => {
          if (instantRms > prev) {
            return prev * attackCoeff + instantRms * (1 - attackCoeff);
          }
          return prev * releaseCoeff + instantRms * (1 - releaseCoeff);
        });

        setPeakLevel(prev => {
          if (instantPeak > prev) {
            return instantPeak;
          }
          return prev * releaseCoeff + instantPeak * (1 - releaseCoeff);
        });

        // Update peak hold
        if (showPeakHold && instantPeak > peakHoldLevel) {
          setPeakHoldLevel(instantPeak);
          if (peakHoldTimeoutRef.current) {
            clearTimeout(peakHoldTimeoutRef.current);
          }
          peakHoldTimeoutRef.current = setTimeout(() => {
            setPeakHoldLevel(METER_MIN_DB);
          }, PEAK_HOLD_TIME_MS);
        }

        // Check for overload
        if (instantPeak > OVERLOAD_THRESHOLD_DB) {
          setOverloadCount(prev => prev + 1);
        }

        lastUpdateTimeRef.current = timestamp;
        renderMeter(ctx);
      }

      animationFrameRef.current = requestAnimationFrame(updateMeter);
    };

    animationFrameRef.current = requestAnimationFrame(updateMeter);

    return () => {
      if (animationFrameRef.current) {
        cancelAnimationFrame(animationFrameRef.current);
      }
      if (peakHoldTimeoutRef.current) {
        clearTimeout(peakHoldTimeoutRef.current);
      }
    };
  }, [audioContext, width, height, showPeakHold, colorTheme]);

  const renderMeter = (ctx: CanvasRenderingContext2D) => {
    ctx.clearRect(0, 0, width, height);

    // Draw background
    ctx.fillStyle = '#1a1a1a';
    ctx.fillRect(0, 0, width, height);

    // Draw scale markings
    ctx.fillStyle = '#333333';
    METER_SCALE_POINTS.forEach(db => {
      const x = dbToPosition(db);
      ctx.fillRect(x, 0, 1, height);
      
      // Draw scale labels
      ctx.fillStyle = '#666666';
      ctx.font = '10px SF Mono';
      ctx.textAlign = 'center';
      ctx.fillText(`${db}`, x, height - 4);
    });

    // Draw reference level line
    const refX = dbToPosition(referenceLevel);
    ctx.fillStyle = '#ffffff';
    ctx.fillRect(refX, 0, 1, height);

    // Draw RMS level
    const rmsWidth = dbToPosition(rmsLevel);
    ctx.fillStyle = colorGradient || '#3498db';
    ctx.fillRect(0, height * 0.25, rmsWidth, height * 0.5);

    // Draw peak level
    const peakX = dbToPosition(peakLevel);
    ctx.fillStyle = '#ffffff';
    ctx.fillRect(peakX - 1, 0, 2, height);

    // Draw peak hold
    if (showPeakHold && peakHoldLevel > METER_MIN_DB) {
      const holdX = dbToPosition(peakHoldLevel);
      ctx.fillStyle = '#e74c3c';
      ctx.fillRect(holdX - 1, 0, 2, height);
    }

    // Draw overload indicator
    if (overloadCount > 0) {
      ctx.fillStyle = '#e74c3c';
      ctx.beginPath();
      ctx.arc(width - 10, height / 2, 4, 0, Math.PI * 2);
      ctx.fill();
    }
  };

  const dbToPosition = (db: number): number => {
    const normalizedDb = Math.max(METER_MIN_DB, Math.min(METER_MAX_DB, db));
    return (width * (normalizedDb - METER_MIN_DB)) / (METER_MAX_DB - METER_MIN_DB);
  };

  return (
    <MeterContainer width={width} height={height}>
      <Canvas ref={canvasRef} />
      {showNumericReadout && (
        <NumericDisplay>
          {rmsLevel.toFixed(1)} dB
          {overloadCount > 0 && ' (!!)'}
        </NumericDisplay>
      )}
    </MeterContainer>
  );
};

export default VUMeter;