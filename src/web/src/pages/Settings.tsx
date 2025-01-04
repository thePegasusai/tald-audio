import React, { useCallback, useEffect, useState } from 'react';
import { useDispatch, useSelector } from 'react-redux'; // v8.1.0
import styled from '@emotion/styled'; // v11.11.0
import debounce from 'lodash/debounce';

import MainLayout from '../components/layout/MainLayout';
import AudioSettings from '../components/settings/AudioSettings';
import AISettings from '../components/settings/AISettings';
import SpatialSettings from '../components/settings/SpatialSettings';
import { theme } from '../styles/theme';
import { selectSettings, resetSettings } from '../store/slices/settingsSlice';
import type { SystemSettings } from '../types/settings.types';

// Styled components with P3 color space support
const SettingsPage = styled.div`
  display: flex;
  flex-direction: column;
  gap: 2rem;
  padding: clamp(1rem, 5vw, 2rem);
  max-width: var(--max-content-width, 1200px);
  margin: 0 auto;
  color-space: p3;
`;

const SettingsHeader = styled.header`
  display: flex;
  justify-content: space-between;
  align-items: center;
  padding: ${theme.spacing.lg};
  background: ${theme.colors.background.secondary};
  border-radius: ${theme.spacing.xs};
  box-shadow: 0 2px 4px rgba(0, 0, 0, 0.1);
`;

const HeaderTitle = styled.h1`
  font-family: ${theme.typography.fontFamily.primary};
  font-size: ${theme.typography.fontSizes['2xl']};
  color: ${theme.colors.text.primary};
  margin: 0;
`;

const HeaderActions = styled.div`
  display: flex;
  gap: ${theme.spacing.md};
`;

const ResetButton = styled.button`
  padding: ${theme.spacing.sm} ${theme.spacing.lg};
  background: ${theme.colors.status.error};
  color: ${theme.colors.text.primary};
  border: none;
  border-radius: ${theme.spacing.xs};
  cursor: pointer;
  font-family: ${theme.typography.fontFamily.primary};
  font-size: ${theme.typography.fontSizes.md};
  transition: background ${theme.animation.duration.normal} ${theme.animation.easing.default};

  &:hover {
    background: ${theme.colors.status.error}dd;
  }

  &:focus-visible {
    outline: 2px solid ${theme.colors.primary.main};
    outline-offset: 2px;
  }

  @media (prefers-reduced-motion: reduce) {
    transition: none;
  }
`;

const SettingsSection = styled.section`
  display: flex;
  flex-direction: column;
  gap: ${theme.spacing.lg};
  padding: ${theme.spacing.xl};
  background: ${theme.colors.background.primary};
  border-radius: ${theme.spacing.xs};
  box-shadow: 0 1px 3px rgba(0, 0, 0, 0.1);

  h2 {
    font-family: ${theme.typography.fontFamily.primary};
    font-size: ${theme.typography.fontSizes.xl};
    color: ${theme.colors.text.primary};
    margin: 0;
  }
`;

const UnsavedChangesAlert = styled.div`
  position: fixed;
  bottom: ${theme.spacing.lg};
  right: ${theme.spacing.lg};
  padding: ${theme.spacing.md} ${theme.spacing.lg};
  background: ${theme.colors.status.warning};
  color: ${theme.colors.text.primary};
  border-radius: ${theme.spacing.xs};
  box-shadow: 0 2px 8px rgba(0, 0, 0, 0.2);
  z-index: 1000;
  animation: slideIn 0.3s ${theme.animation.easing.default};

  @keyframes slideIn {
    from {
      transform: translateY(100%);
      opacity: 0;
    }
    to {
      transform: translateY(0);
      opacity: 1;
    }
  }

  @media (prefers-reduced-motion: reduce) {
    animation: none;
  }
`;

const Settings: React.FC = () => {
  const dispatch = useDispatch();
  const settings = useSelector(selectSettings);
  const [hasUnsavedChanges, setHasUnsavedChanges] = useState(false);
  const [lastSaved, setLastSaved] = useState<Date>(new Date());

  // Debounced save handler
  const debouncedSave = useCallback(
    debounce((settings: SystemSettings) => {
      localStorage.setItem('tald-unia-settings', JSON.stringify(settings));
      setLastSaved(new Date());
      setHasUnsavedChanges(false);
    }, 1000),
    []
  );

  // Effect to track unsaved changes
  useEffect(() => {
    if (settings.lastUpdated > lastSaved) {
      setHasUnsavedChanges(true);
      debouncedSave(settings);
    }
  }, [settings, lastSaved, debouncedSave]);

  // Handle settings reset
  const handleReset = useCallback(() => {
    if (window.confirm('Are you sure you want to reset all settings to default values?')) {
      dispatch(resetSettings());
      setHasUnsavedChanges(false);
    }
  }, [dispatch]);

  // Handle beforeunload event for unsaved changes
  useEffect(() => {
    const handleBeforeUnload = (e: BeforeUnloadEvent) => {
      if (hasUnsavedChanges) {
        e.preventDefault();
        e.returnValue = '';
      }
    };

    window.addEventListener('beforeunload', handleBeforeUnload);
    return () => window.removeEventListener('beforeunload', handleBeforeUnload);
  }, [hasUnsavedChanges]);

  return (
    <MainLayout>
      <SettingsPage role="main" aria-label="Settings page">
        <SettingsHeader>
          <HeaderTitle>Settings</HeaderTitle>
          <HeaderActions>
            <ResetButton
              onClick={handleReset}
              aria-label="Reset all settings to default values"
            >
              Reset to Defaults
            </ResetButton>
          </HeaderActions>
        </SettingsHeader>

        <SettingsSection aria-labelledby="audio-settings-title">
          <h2 id="audio-settings-title">Audio Settings</h2>
          <AudioSettings />
        </SettingsSection>

        <SettingsSection aria-labelledby="ai-settings-title">
          <h2 id="ai-settings-title">AI Enhancement</h2>
          <AISettings />
        </SettingsSection>

        <SettingsSection aria-labelledby="spatial-settings-title">
          <h2 id="spatial-settings-title">Spatial Audio</h2>
          <SpatialSettings />
        </SettingsSection>

        {hasUnsavedChanges && (
          <UnsavedChangesAlert
            role="alert"
            aria-live="polite"
          >
            Saving changes...
          </UnsavedChangesAlert>
        )}
      </SettingsPage>
    </MainLayout>
  );
};

export default Settings;