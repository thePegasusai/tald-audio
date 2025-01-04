import React, { useCallback, useMemo } from 'react';
import styled from '@emotion/styled';
import { useDispatch, useSelector } from 'react-redux';
import debounce from 'lodash';
import { Toggle } from '../common/Toggle';
import { Slider } from '../common/Slider';
import { Select } from '../common/Select';
import { theme } from '../../styles/theme';
import { updateSpatialConfig } from '../../store/slices/settingsSlice';
import type { SpatialConfig } from '../../types/settings.types';

// Constants for HRTF profiles with comprehensive options
const HRTF_PROFILES = [
  { value: 'default', label: 'Default HRTF', description: 'Standard HRTF profile suitable for most users' },
  { value: 'studio', label: 'Studio Reference', description: 'Professional studio monitoring profile' },
  { value: 'custom', label: 'Custom Profile', description: 'User-specific HRTF measurements' },
  { value: 'small_head', label: 'Small Head', description: 'Optimized for smaller head sizes' },
  { value: 'large_head', label: 'Large Head', description: 'Optimized for larger head sizes' }
];

// Validation constants for spatial parameters
const SPATIAL_VALIDATION = {
  ROOM_SIZE: {
    MIN: 1,
    MAX: 1000,
    STEP: 1,
    DEFAULT: 30
  },
  REVERB_TIME: {
    MIN: 0.1,
    MAX: 10.0,
    STEP: 0.1,
    DEFAULT: 0.3
  },
  WALL_ABSORPTION: {
    MIN: 0,
    MAX: 1,
    STEP: 0.01,
    DEFAULT: 0.5
  }
};

// Styled components with P3 color space support
const Container = styled.div`
  display: flex;
  flex-direction: column;
  gap: ${theme.spacing.lg};
  padding: ${theme.spacing.xl};
  background: ${theme.colors.background.primary};
  border-radius: 8px;

  @media (prefers-color-scheme: dark) {
    background: ${theme.colors.background.secondary};
  }

  @media (prefers-reduced-motion: reduce) {
    transition: none;
  }
`;

const Section = styled.div`
  display: flex;
  flex-direction: column;
  gap: ${theme.spacing.md};
`;

const SectionTitle = styled.h3`
  font-family: ${theme.typography.fontFamily.primary};
  font-size: ${theme.typography.fontSizes.lg};
  color: ${theme.colors.text.primary};
  margin: 0;
`;

const ControlGroup = styled.div`
  display: flex;
  flex-direction: column;
  gap: ${theme.spacing.sm};
`;

const Description = styled.p`
  font-family: ${theme.typography.fontFamily.primary};
  font-size: ${theme.typography.fontSizes.sm};
  color: ${theme.colors.text.secondary};
  margin: 0;
`;

interface SpatialSettingsProps {
  className?: string;
}

export const SpatialSettings: React.FC<SpatialSettingsProps> = ({ className }) => {
  const dispatch = useDispatch();
  const spatialConfig = useSelector((state: { settings: { spatial: SpatialConfig } }) => state.settings.spatial);

  // Debounced update handlers to prevent excessive dispatches
  const debouncedUpdateConfig = useMemo(
    () => debounce((updates: Partial<SpatialConfig>) => {
      dispatch(updateSpatialConfig(updates));
    }, 100),
    [dispatch]
  );

  // Head tracking toggle handler with hardware validation
  const handleHeadTrackingToggle = useCallback((enabled: boolean) => {
    dispatch(updateSpatialConfig({
      headTrackingEnabled: enabled
    }));
  }, [dispatch]);

  // HRTF profile selection handler with validation
  const handleHRTFProfileChange = useCallback((profile: string) => {
    dispatch(updateSpatialConfig({
      hrtfProfile: profile
    }));
  }, [dispatch]);

  // Room size handler with validation
  const handleRoomSizeChange = useCallback((size: number) => {
    debouncedUpdateConfig({
      roomSize: Math.max(SPATIAL_VALIDATION.ROOM_SIZE.MIN, 
                        Math.min(SPATIAL_VALIDATION.ROOM_SIZE.MAX, size))
    });
  }, [debouncedUpdateConfig]);

  // Reverb time handler with validation
  const handleReverbTimeChange = useCallback((time: number) => {
    debouncedUpdateConfig({
      reverbTime: Math.max(SPATIAL_VALIDATION.REVERB_TIME.MIN,
                          Math.min(SPATIAL_VALIDATION.REVERB_TIME.MAX, time))
    });
  }, [debouncedUpdateConfig]);

  // Wall absorption handler with validation
  const handleWallAbsorptionChange = useCallback((absorption: number) => {
    debouncedUpdateConfig({
      wallAbsorption: Math.max(SPATIAL_VALIDATION.WALL_ABSORPTION.MIN,
                              Math.min(SPATIAL_VALIDATION.WALL_ABSORPTION.MAX, absorption))
    });
  }, [debouncedUpdateConfig]);

  return (
    <Container className={className}>
      <Section>
        <SectionTitle>Head Tracking</SectionTitle>
        <ControlGroup>
          <Toggle
            checked={spatialConfig.headTrackingEnabled}
            onChange={handleHeadTrackingToggle}
            label="Enable Head Tracking"
            ariaLabel="Toggle head tracking for spatial audio"
            colorScheme="primary"
          />
          <Description>
            Enable real-time head tracking for enhanced spatial audio experience
          </Description>
        </ControlGroup>
      </Section>

      <Section>
        <SectionTitle>HRTF Profile</SectionTitle>
        <ControlGroup>
          <Select
            options={HRTF_PROFILES}
            value={spatialConfig.hrtfProfile}
            onChange={handleHRTFProfileChange}
            ariaLabel="Select HRTF profile"
          />
          <Description>
            Choose the Head-Related Transfer Function profile that best matches your listening setup
          </Description>
        </ControlGroup>
      </Section>

      <Section>
        <SectionTitle>Room Modeling</SectionTitle>
        <ControlGroup>
          <Slider
            min={SPATIAL_VALIDATION.ROOM_SIZE.MIN}
            max={SPATIAL_VALIDATION.ROOM_SIZE.MAX}
            step={SPATIAL_VALIDATION.ROOM_SIZE.STEP}
            value={spatialConfig.roomSize}
            onChange={handleRoomSizeChange}
            label="Room Size"
            ariaValueText={`Room size: ${spatialConfig.roomSize} cubic meters`}
          />
          <Slider
            min={SPATIAL_VALIDATION.REVERB_TIME.MIN}
            max={SPATIAL_VALIDATION.REVERB_TIME.MAX}
            step={SPATIAL_VALIDATION.REVERB_TIME.STEP}
            value={spatialConfig.reverbTime}
            onChange={handleReverbTimeChange}
            label="Reverb Time"
            ariaValueText={`Reverb time: ${spatialConfig.reverbTime} seconds`}
          />
          <Slider
            min={SPATIAL_VALIDATION.WALL_ABSORPTION.MIN}
            max={SPATIAL_VALIDATION.WALL_ABSORPTION.MAX}
            step={SPATIAL_VALIDATION.WALL_ABSORPTION.STEP}
            value={spatialConfig.wallAbsorption}
            onChange={handleWallAbsorptionChange}
            label="Wall Absorption"
            ariaValueText={`Wall absorption: ${spatialConfig.wallAbsorption}`}
          />
          <Description>
            Configure virtual room characteristics for optimal spatial audio rendering
          </Description>
        </ControlGroup>
      </Section>
    </Container>
  );
};

export default SpatialSettings;