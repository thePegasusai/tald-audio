/**
 * @file AudioSettings component for TALD UNIA Audio System
 * @version 1.0.0
 * 
 * Provides a comprehensive interface for configuring audio hardware,
 * processing, and spatial settings with real-time validation and preview.
 */

import React, { useCallback, useEffect, useMemo } from 'react';
import { useDispatch, useSelector } from 'react-redux';
import styled from '@emotion/styled';
import debounce from 'lodash/debounce';

import {
  SystemSettings,
  ProcessingQuality,
  HardwareConfig,
  ProcessingConfig,
  SpatialConfig,
  DeviceCapabilities
} from '../../types/settings.types';

import {
  settingsActions,
  selectSettings,
  selectDeviceCapabilities
} from '../../store/slices/settingsSlice';

// Constants for valid configuration options
const SAMPLE_RATES = [44100, 48000, 96000, 192000];
const BUFFER_SIZES = [64, 128, 256, 512, 1024];
const BIT_DEPTHS = [16, 24, 32];
const HRTF_PROFILES = ['Default', 'Custom', 'Studio', 'Gaming'];
const ROOM_MODELS = ['Small', 'Medium', 'Large', 'Custom'];

// Styled components with accessibility enhancements
const SettingsContainer = styled.div`
  display: flex;
  flex-direction: column;
  gap: 24px;
  padding: 24px;
  max-width: 800px;
  margin: 0 auto;
  color: ${props => props.theme.colors.text.primary};
`;

const SettingsSection = styled.section`
  display: flex;
  flex-direction: column;
  gap: 16px;
  padding: 20px;
  background: ${props => props.theme.colors.surface};
  border-radius: 8px;
  box-shadow: 0 2px 4px rgba(0, 0, 0, 0.1);
`;

const SectionTitle = styled.h2`
  font-size: 1.25rem;
  font-weight: 600;
  margin: 0;
  color: ${props => props.theme.colors.text.primary};
`;

const SettingRow = styled.div`
  display: flex;
  justify-content: space-between;
  align-items: center;
  padding: 8px 0;
`;

const Select = styled.select`
  padding: 8px 12px;
  border-radius: 4px;
  border: 1px solid ${props => props.theme.colors.border};
  background: ${props => props.theme.colors.background};
  color: ${props => props.theme.colors.text.primary};
  min-width: 200px;
`;

const Slider = styled.input`
  width: 200px;
  margin: 0;
`;

const Switch = styled.input`
  margin: 0;
`;

const AudioSettings: React.FC = () => {
  const dispatch = useDispatch();
  const settings = useSelector(selectSettings);
  const deviceCapabilities = useSelector(selectDeviceCapabilities);

  // Memoized validation functions
  const validateHardwareConfig = useMemo(() => (
    config: Partial<HardwareConfig>
  ): boolean => {
    if (config.sampleRate && !SAMPLE_RATES.includes(config.sampleRate)) return false;
    if (config.bufferSize && !BUFFER_SIZES.includes(config.bufferSize)) return false;
    if (config.bitDepth && !BIT_DEPTHS.includes(config.bitDepth)) return false;
    return true;
  }, []);

  // Debounced handlers for real-time updates
  const handleHardwareConfigChange = useCallback(
    debounce(async (config: Partial<HardwareConfig>) => {
      if (!validateHardwareConfig(config)) return;
      
      try {
        await dispatch(settingsActions.updateHardwareConfig(config));
      } catch (error) {
        console.error('Failed to update hardware config:', error);
      }
    }, 250),
    [dispatch, validateHardwareConfig]
  );

  const handleProcessingConfigChange = useCallback(
    debounce(async (config: Partial<ProcessingConfig>) => {
      try {
        await dispatch(settingsActions.updateProcessingConfig(config));
      } catch (error) {
        console.error('Failed to update processing config:', error);
      }
    }, 250),
    [dispatch]
  );

  const handleSpatialConfigChange = useCallback(
    debounce(async (config: Partial<SpatialConfig>) => {
      try {
        await dispatch(settingsActions.updateSpatialConfig(config));
      } catch (error) {
        console.error('Failed to update spatial config:', error);
      }
    }, 250),
    [dispatch]
  );

  // Effect for device capability updates
  useEffect(() => {
    if (deviceCapabilities) {
      handleHardwareConfigChange({
        maxChannels: deviceCapabilities.maxChannels,
      });
    }
  }, [deviceCapabilities, handleHardwareConfigChange]);

  return (
    <SettingsContainer role="region" aria-label="Audio Settings">
      <SettingsSection aria-labelledby="hardware-settings-title">
        <SectionTitle id="hardware-settings-title">Hardware Configuration</SectionTitle>
        
        <SettingRow>
          <label htmlFor="sample-rate">Sample Rate</label>
          <Select
            id="sample-rate"
            value={settings.hardware.sampleRate}
            onChange={(e) => handleHardwareConfigChange({
              sampleRate: Number(e.target.value)
            })}
          >
            {SAMPLE_RATES.map(rate => (
              <option key={rate} value={rate}>{rate} Hz</option>
            ))}
          </Select>
        </SettingRow>

        <SettingRow>
          <label htmlFor="buffer-size">Buffer Size</label>
          <Select
            id="buffer-size"
            value={settings.hardware.bufferSize}
            onChange={(e) => handleHardwareConfigChange({
              bufferSize: Number(e.target.value)
            })}
          >
            {BUFFER_SIZES.map(size => (
              <option key={size} value={size}>{size} samples</option>
            ))}
          </Select>
        </SettingRow>

        <SettingRow>
          <label htmlFor="bit-depth">Bit Depth</label>
          <Select
            id="bit-depth"
            value={settings.hardware.bitDepth}
            onChange={(e) => handleHardwareConfigChange({
              bitDepth: Number(e.target.value)
            })}
          >
            {BIT_DEPTHS.map(depth => (
              <option key={depth} value={depth}>{depth}-bit</option>
            ))}
          </Select>
        </SettingRow>
      </SettingsSection>

      <SettingsSection aria-labelledby="processing-settings-title">
        <SectionTitle id="processing-settings-title">Processing Configuration</SectionTitle>
        
        <SettingRow>
          <label htmlFor="processing-quality">Processing Quality</label>
          <Select
            id="processing-quality"
            value={settings.processing.quality}
            onChange={(e) => handleProcessingConfigChange({
              quality: e.target.value as ProcessingQuality
            })}
          >
            {Object.values(ProcessingQuality).map(quality => (
              <option key={quality} value={quality}>{quality}</option>
            ))}
          </Select>
        </SettingRow>

        <SettingRow>
          <label htmlFor="local-ai">Local AI Processing</label>
          <Switch
            id="local-ai"
            type="checkbox"
            checked={settings.processing.localAIEnabled}
            onChange={(e) => handleProcessingConfigChange({
              localAIEnabled: e.target.checked
            })}
          />
        </SettingRow>

        <SettingRow>
          <label htmlFor="enhancement-level">Enhancement Level</label>
          <Slider
            id="enhancement-level"
            type="range"
            min="0"
            max="100"
            value={settings.processing.enhancementLevel}
            onChange={(e) => handleProcessingConfigChange({
              enhancementLevel: Number(e.target.value)
            })}
          />
        </SettingRow>
      </SettingsSection>

      <SettingsSection aria-labelledby="spatial-settings-title">
        <SectionTitle id="spatial-settings-title">Spatial Audio</SectionTitle>
        
        <SettingRow>
          <label htmlFor="head-tracking">Head Tracking</label>
          <Switch
            id="head-tracking"
            type="checkbox"
            checked={settings.spatial.headTrackingEnabled}
            onChange={(e) => handleSpatialConfigChange({
              headTrackingEnabled: e.target.checked
            })}
          />
        </SettingRow>

        <SettingRow>
          <label htmlFor="hrtf-profile">HRTF Profile</label>
          <Select
            id="hrtf-profile"
            value={settings.spatial.hrtfProfile}
            onChange={(e) => handleSpatialConfigChange({
              hrtfProfile: e.target.value
            })}
          >
            {HRTF_PROFILES.map(profile => (
              <option key={profile} value={profile.toLowerCase()}>{profile}</option>
            ))}
          </Select>
        </SettingRow>

        <SettingRow>
          <label htmlFor="room-size">Room Size</label>
          <Slider
            id="room-size"
            type="range"
            min="0"
            max="1000"
            value={settings.spatial.roomSize}
            onChange={(e) => handleSpatialConfigChange({
              roomSize: Number(e.target.value)
            })}
          />
        </SettingRow>
      </SettingsSection>
    </SettingsContainer>
  );
};

export default AudioSettings;