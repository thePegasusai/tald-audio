import React, { useCallback, useState, useEffect } from 'react';
import styled from '@emotion/styled';
import { debounce } from 'lodash/debounce';
import Slider from '../common/Slider';
import Toggle from '../common/Toggle';
import { theme } from '../../styles/theme';

// Constants
const MIN_ROOM_DIMENSION = 1;
const MAX_ROOM_DIMENSION = 30;
const MIN_POSITION = -10;
const MAX_POSITION = 10;
const POSITION_STEP = 0.1;
const ROOM_DIMENSION_STEP = 0.5;
const ACOUSTIC_UPDATE_DEBOUNCE = 100;

// Interfaces
interface RoomDimensions {
  width: number;
  height: number;
  depth: number;
}

interface Position {
  x: number;
  y: number;
  z: number;
}

interface RoomMaterialPreset {
  id: string;
  name: string;
  absorption: number;
  reflection: number;
  diffusion: number;
}

interface SpatialAudioConfig {
  enabled: boolean;
  roomDimensions: RoomDimensions;
  listenerPosition: Position;
  sourcePosition: Position;
  materialPreset: RoomMaterialPreset;
  hrtfEnabled: boolean;
  headTracking: boolean;
}

interface SpatialControlsProps {
  config: SpatialAudioConfig;
  onChange: (config: SpatialAudioConfig) => void;
  disabled?: boolean;
  materialPresets?: RoomMaterialPreset[];
}

// Styled Components
const Container = styled.div`
  display: flex;
  flex-direction: column;
  gap: ${theme.spacing.md};
  padding: ${theme.spacing.lg};
  background: ${theme.colors.background.secondary};
  border-radius: 8px;
  
  @media ${theme.breakpoints.sm.query} {
    padding: ${theme.spacing.md};
  }
`;

const Section = styled.div`
  display: flex;
  flex-direction: column;
  gap: ${theme.spacing.sm};
`;

const SectionTitle = styled.h3`
  font-family: ${theme.typography.fontFamily.primary};
  font-size: ${theme.typography.fontSizes.lg};
  color: ${theme.colors.text.primary};
  margin: 0;
`;

const ControlGrid = styled.div`
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(250px, 1fr));
  gap: ${theme.spacing.md};
`;

const VisualizationPanel = styled.div<{ disabled?: boolean }>`
  width: 100%;
  height: 200px;
  background: ${theme.colors.background.primary};
  border-radius: 4px;
  opacity: ${props => props.disabled ? 0.5 : 1};
  position: relative;
  overflow: hidden;
  
  canvas {
    width: 100%;
    height: 100%;
  }
`;

// Helper Functions
const createPositionMarks = () => [
  { value: MIN_POSITION, label: `${MIN_POSITION}m` },
  { value: 0, label: '0m' },
  { value: MAX_POSITION, label: `${MAX_POSITION}m` }
];

const createDimensionMarks = () => [
  { value: MIN_ROOM_DIMENSION, label: `${MIN_ROOM_DIMENSION}m` },
  { value: MAX_ROOM_DIMENSION / 2, label: `${MAX_ROOM_DIMENSION / 2}m` },
  { value: MAX_ROOM_DIMENSION, label: `${MAX_ROOM_DIMENSION}m` }
];

// Main Component
const SpatialControls: React.FC<SpatialControlsProps> = ({
  config,
  onChange,
  disabled = false,
  materialPresets = []
}) => {
  const [localConfig, setLocalConfig] = useState<SpatialAudioConfig>(config);
  
  useEffect(() => {
    setLocalConfig(config);
  }, [config]);

  const handleRoomSizeChange = useCallback(
    debounce((dimension: keyof RoomDimensions, value: number) => {
      const newConfig = {
        ...localConfig,
        roomDimensions: {
          ...localConfig.roomDimensions,
          [dimension]: value
        }
      };
      setLocalConfig(newConfig);
      onChange(newConfig);
    }, ACOUSTIC_UPDATE_DEBOUNCE),
    [localConfig, onChange]
  );

  const handlePositionChange = useCallback(
    debounce((type: 'listener' | 'source', axis: keyof Position, value: number) => {
      const newConfig = {
        ...localConfig,
        [`${type}Position`]: {
          ...localConfig[`${type}Position`],
          [axis]: value
        }
      };
      setLocalConfig(newConfig);
      onChange(newConfig);
    }, ACOUSTIC_UPDATE_DEBOUNCE),
    [localConfig, onChange]
  );

  const handleToggleChange = useCallback((setting: keyof SpatialAudioConfig) => {
    const newConfig = {
      ...localConfig,
      [setting]: !localConfig[setting]
    };
    setLocalConfig(newConfig);
    onChange(newConfig);
  }, [localConfig, onChange]);

  const handleMaterialChange = useCallback((preset: RoomMaterialPreset) => {
    const newConfig = {
      ...localConfig,
      materialPreset: preset
    };
    setLocalConfig(newConfig);
    onChange(newConfig);
  }, [localConfig, onChange]);

  return (
    <Container>
      <Section>
        <Toggle
          checked={localConfig.enabled}
          onChange={() => handleToggleChange('enabled')}
          label="Enable Spatial Audio"
          disabled={disabled}
          colorScheme="primary"
          enableHaptics
        />
      </Section>

      <Section>
        <SectionTitle>Room Dimensions</SectionTitle>
        <ControlGrid>
          {(['width', 'height', 'depth'] as const).map(dimension => (
            <Slider
              key={dimension}
              label={`Room ${dimension}`}
              min={MIN_ROOM_DIMENSION}
              max={MAX_ROOM_DIMENSION}
              step={ROOM_DIMENSION_STEP}
              value={localConfig.roomDimensions[dimension]}
              onChange={(value) => handleRoomSizeChange(dimension, value)}
              disabled={disabled || !localConfig.enabled}
              marks={createDimensionMarks()}
              ariaValueText={`${localConfig.roomDimensions[dimension]} meters`}
            />
          ))}
        </ControlGrid>
      </Section>

      <Section>
        <SectionTitle>Listener Position</SectionTitle>
        <ControlGrid>
          {(['x', 'y', 'z'] as const).map(axis => (
            <Slider
              key={`listener-${axis}`}
              label={`Listener ${axis.toUpperCase()}`}
              min={MIN_POSITION}
              max={MAX_POSITION}
              step={POSITION_STEP}
              value={localConfig.listenerPosition[axis]}
              onChange={(value) => handlePositionChange('listener', axis, value)}
              disabled={disabled || !localConfig.enabled}
              marks={createPositionMarks()}
              ariaValueText={`${localConfig.listenerPosition[axis]} meters`}
            />
          ))}
        </ControlGrid>
      </Section>

      <Section>
        <SectionTitle>Source Position</SectionTitle>
        <ControlGrid>
          {(['x', 'y', 'z'] as const).map(axis => (
            <Slider
              key={`source-${axis}`}
              label={`Source ${axis.toUpperCase()}`}
              min={MIN_POSITION}
              max={MAX_POSITION}
              step={POSITION_STEP}
              value={localConfig.sourcePosition[axis]}
              onChange={(value) => handlePositionChange('source', axis, value)}
              disabled={disabled || !localConfig.enabled}
              marks={createPositionMarks()}
              ariaValueText={`${localConfig.sourcePosition[axis]} meters`}
            />
          ))}
        </ControlGrid>
      </Section>

      <Section>
        <SectionTitle>Room Acoustics</SectionTitle>
        <ControlGrid>
          {materialPresets.map(preset => (
            <Toggle
              key={preset.id}
              checked={localConfig.materialPreset.id === preset.id}
              onChange={() => handleMaterialChange(preset)}
              label={preset.name}
              disabled={disabled || !localConfig.enabled}
              colorScheme="secondary"
            />
          ))}
        </ControlGrid>
      </Section>

      <Section>
        <SectionTitle>Advanced Settings</SectionTitle>
        <ControlGrid>
          <Toggle
            checked={localConfig.hrtfEnabled}
            onChange={() => handleToggleChange('hrtfEnabled')}
            label="HRTF Processing"
            disabled={disabled || !localConfig.enabled}
            colorScheme="primary"
          />
          <Toggle
            checked={localConfig.headTracking}
            onChange={() => handleToggleChange('headTracking')}
            label="Head Tracking"
            disabled={disabled || !localConfig.enabled}
            colorScheme="primary"
          />
        </ControlGrid>
      </Section>

      <VisualizationPanel disabled={disabled || !localConfig.enabled}>
        <canvas id="spatial-visualization" aria-label="Spatial audio visualization" />
      </VisualizationPanel>
    </Container>
  );
};

export default SpatialControls;