import React, { useState, useCallback, useEffect } from 'react';
import styled from '@emotion/styled';
import { useDispatch, useSelector } from 'react-redux';
import { useUndoable } from 'use-undoable';
import { useSystemResources } from '@tald/system-resources';

import { ProcessingQuality, ProcessingConfig } from '../../types/settings.types';
import { settingsActions, selectSettings } from '../../store/slices/settingsSlice';
import Select from '../common/Select';
import Toggle from '../common/Toggle';
import { theme } from '../../styles/theme';

// Styled Components
const SettingsContainer = styled.div`
  display: flex;
  flex-direction: column;
  gap: 24px;
  padding: 24px;
  position: relative;
  transition: opacity 0.2s ease;

  @media (prefers-reduced-motion: reduce) {
    transition: none;
  }
`;

const SettingRow = styled.div`
  display: flex;
  justify-content: space-between;
  align-items: center;
  min-height: 44px;
  position: relative;
  padding: 8px 0;
`;

const SettingLabel = styled.label`
  font-family: ${theme.typography.fontFamily.primary};
  font-size: ${theme.typography.fontSizes.md};
  color: ${theme.colors.text.primary};
  user-select: none;
  display: flex;
  align-items: center;
  gap: 8px;
`;

const LoadingOverlay = styled.div`
  position: absolute;
  top: 0;
  left: 0;
  right: 0;
  bottom: 0;
  background: rgba(0, 0, 0, 0.5);
  display: flex;
  align-items: center;
  justify-content: center;
  z-index: 10;
  backdrop-filter: blur(4px);
`;

// Quality options with audio previews
const qualityOptions = [
  {
    value: ProcessingQuality.MAXIMUM,
    label: 'Maximum Quality',
    audioPreview: {
      url: '/assets/audio/preview-max-quality.mp3',
      duration: 3000
    }
  },
  {
    value: ProcessingQuality.BALANCED,
    label: 'Balanced',
    audioPreview: {
      url: '/assets/audio/preview-balanced.mp3',
      duration: 3000
    }
  },
  {
    value: ProcessingQuality.POWER_SAVER,
    label: 'Power Saver',
    audioPreview: {
      url: '/assets/audio/preview-power-saver.mp3',
      duration: 3000
    }
  }
];

const AISettings: React.FC = () => {
  const dispatch = useDispatch();
  const { processing } = useSelector(selectSettings);
  const [isLoading, setIsLoading] = useState(false);
  const { cpu, memory } = useSystemResources();
  
  // Undoable state for settings changes
  const [undoableConfig, { set: setUndoableConfig, undo, redo }] = useUndoable<ProcessingConfig>(processing);

  // Monitor system resources for quality validation
  const validateSystemResources = useCallback((quality: ProcessingQuality): boolean => {
    switch (quality) {
      case ProcessingQuality.MAXIMUM:
        return cpu.usage < 80 && memory.available > 2048;
      case ProcessingQuality.BALANCED:
        return cpu.usage < 60 && memory.available > 1024;
      case ProcessingQuality.POWER_SAVER:
        return true;
      default:
        return false;
    }
  }, [cpu, memory]);

  // Handle quality change with validation and preview
  const handleQualityChange = useCallback(async (value: string, audioPreview?: { url: string; duration: number }) => {
    const quality = value as ProcessingQuality;
    
    if (!validateSystemResources(quality)) {
      // Show resource warning and fallback to balanced mode
      console.warn('Insufficient system resources for selected quality level');
      return;
    }

    setIsLoading(true);
    try {
      const newConfig = { ...undoableConfig, quality };
      setUndoableConfig(newConfig);
      
      await dispatch(settingsActions.updateProcessingConfig(newConfig)).unwrap();
      
      // Log telemetry data
      console.info('Quality setting updated:', {
        previousQuality: undoableConfig.quality,
        newQuality: quality,
        systemResources: { cpu: cpu.usage, memory: memory.available }
      });
    } catch (error) {
      console.error('Failed to update quality settings:', error);
    } finally {
      setIsLoading(false);
    }
  }, [undoableConfig, dispatch, cpu, memory, setUndoableConfig, validateSystemResources]);

  // Handle local AI toggle with validation
  const handleLocalAIToggle = useCallback(async (enabled: boolean) => {
    if (enabled && !validateSystemResources(undoableConfig.quality)) {
      console.warn('Insufficient resources for local AI processing');
      return;
    }

    setIsLoading(true);
    try {
      const newConfig = { ...undoableConfig, localAIEnabled: enabled };
      setUndoableConfig(newConfig);
      
      await dispatch(settingsActions.updateProcessingConfig(newConfig)).unwrap();
    } catch (error) {
      console.error('Failed to toggle local AI:', error);
    } finally {
      setIsLoading(false);
    }
  }, [undoableConfig, dispatch, setUndoableConfig, validateSystemResources]);

  // Keyboard shortcuts for undo/redo
  useEffect(() => {
    const handleKeyDown = (e: KeyboardEvent) => {
      if ((e.metaKey || e.ctrlKey) && e.key === 'z') {
        if (e.shiftKey) {
          redo();
        } else {
          undo();
        }
      }
    };

    window.addEventListener('keydown', handleKeyDown);
    return () => window.removeEventListener('keydown', handleKeyDown);
  }, [undo, redo]);

  return (
    <SettingsContainer>
      {isLoading && (
        <LoadingOverlay>
          <span>Applying settings...</span>
        </LoadingOverlay>
      )}

      <SettingRow>
        <SettingLabel htmlFor="processing-quality">
          Processing Quality
        </SettingLabel>
        <Select
          id="processing-quality"
          options={qualityOptions}
          value={undoableConfig.quality}
          onChange={handleQualityChange}
          audioPreviewDelay={300}
          disabled={isLoading}
          ariaLabel="Select processing quality level"
        />
      </SettingRow>

      <SettingRow>
        <SettingLabel htmlFor="local-ai-toggle">
          Local AI Enhancement
        </SettingLabel>
        <Toggle
          id="local-ai-toggle"
          checked={undoableConfig.localAIEnabled}
          onChange={handleLocalAIToggle}
          disabled={isLoading}
          label="Enable local AI processing"
          enableHaptics
          enableAudioFeedback
          size="md"
          colorScheme="primary"
        />
      </SettingRow>

      <SettingRow>
        <SettingLabel htmlFor="room-calibration-toggle">
          Automatic Room Calibration
        </SettingLabel>
        <Toggle
          id="room-calibration-toggle"
          checked={undoableConfig.roomCalibrationEnabled}
          onChange={(enabled) => {
            const newConfig = { ...undoableConfig, roomCalibrationEnabled: enabled };
            setUndoableConfig(newConfig);
            dispatch(settingsActions.updateProcessingConfig(newConfig));
          }}
          disabled={isLoading || !undoableConfig.localAIEnabled}
          label="Enable automatic room calibration"
          enableHaptics
          enableAudioFeedback
          size="md"
          colorScheme="primary"
        />
      </SettingRow>
    </SettingsContainer>
  );
};

export default AISettings;