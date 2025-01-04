/**
 * @file ProfileManager component for TALD UNIA audio profile management
 * @version 1.0.0
 */

import React, { useState, useCallback, useMemo, Suspense, memo } from 'react';
import { ErrorBoundary } from '@sentry/react';
import { VirtualList } from 'react-window';
import styled from 'styled-components';
import { Profile, ProfilePreferences, AudioSettings, ProcessingQuality } from '../../types/profile.types';

// Constants for profile operations and sync intervals
const PROFILE_OPERATIONS = {
  CREATE: 'create',
  UPDATE: 'update',
  DELETE: 'delete',
  BATCH_UPDATE: 'batchUpdate',
  BATCH_DELETE: 'batchDelete',
} as const;

const SYNC_INTERVALS = {
  NORMAL: 5000,
  URGENT: 1000,
} as const;

// Styled components with accessibility support
const Container = styled.div`
  display: flex;
  flex-direction: column;
  gap: 24px;
  padding: 24px;
  background-color: ${({ theme }) => theme.colors.background.primary};
  border-radius: 8px;
  position: relative;
  
  /* ARIA labels for accessibility */
  [role="region"] {
    margin-bottom: 16px;
  }
`;

const SearchInput = styled.input`
  padding: 12px;
  border-radius: 4px;
  border: 1px solid ${({ theme }) => theme.colors.border.primary};
  font-size: 16px;
  width: 100%;
  
  &:focus {
    outline: 2px solid ${({ theme }) => theme.colors.focus.primary};
    outline-offset: 2px;
  }
`;

interface ProfileManagerProps {
  initialProfiles?: Profile[];
  onProfileChange?: (profile: Profile) => void;
  onSyncComplete?: () => void;
}

interface ProfileState {
  profiles: Profile[];
  selectedProfileIds: Set<string>;
  filteredProfiles: Profile[];
  isLoading: boolean;
}

interface SyncStatus {
  lastSync: Date;
  isSyncing: boolean;
  syncErrors: Error[];
}

/**
 * ProfileManager component for managing TALD UNIA audio profiles
 */
const ProfileManager: React.FC<ProfileManagerProps> = memo(({
  initialProfiles = [],
  onProfileChange,
  onSyncComplete,
}) => {
  // State management
  const [profileState, setProfileState] = useState<ProfileState>({
    profiles: initialProfiles,
    selectedProfileIds: new Set(),
    filteredProfiles: initialProfiles,
    isLoading: false,
  });

  const [syncStatus, setSyncStatus] = useState<SyncStatus>({
    lastSync: new Date(),
    isSyncing: false,
    syncErrors: [],
  });

  const [searchTerm, setSearchTerm] = useState('');

  // Memoized derived state
  const sortedProfiles = useMemo(() => {
    return [...profileState.filteredProfiles].sort((a, b) => {
      if (a.isDefault !== b.isDefault) return a.isDefault ? -1 : 1;
      return new Date(b.updatedAt).getTime() - new Date(a.updatedAt).getTime();
    });
  }, [profileState.filteredProfiles]);

  // Profile operation handlers
  const handleProfileOperation = useCallback(async (
    operationType: keyof typeof PROFILE_OPERATIONS,
    profile: Profile
  ) => {
    try {
      setProfileState(prev => ({
        ...prev,
        isLoading: true,
      }));

      // Optimistic update
      const updatedProfiles = [...profileState.profiles];
      switch (operationType) {
        case PROFILE_OPERATIONS.CREATE:
          updatedProfiles.push(profile);
          break;
        case PROFILE_OPERATIONS.UPDATE:
          const index = updatedProfiles.findIndex(p => p.id === profile.id);
          if (index !== -1) updatedProfiles[index] = profile;
          break;
        case PROFILE_OPERATIONS.DELETE:
          const filteredProfiles = updatedProfiles.filter(p => p.id !== profile.id);
          updatedProfiles.length = 0;
          updatedProfiles.push(...filteredProfiles);
          break;
      }

      setProfileState(prev => ({
        ...prev,
        profiles: updatedProfiles,
        filteredProfiles: updatedProfiles,
      }));

      // API call would go here
      onProfileChange?.(profile);

      setSyncStatus(prev => ({
        ...prev,
        lastSync: new Date(),
        syncErrors: [],
      }));
    } catch (error) {
      setSyncStatus(prev => ({
        ...prev,
        syncErrors: [...prev.syncErrors, error as Error],
      }));
      throw error;
    } finally {
      setProfileState(prev => ({
        ...prev,
        isLoading: false,
      }));
    }
  }, [profileState.profiles, onProfileChange]);

  // Search handler with debounce
  const handleProfileSearch = useCallback((searchTerm: string) => {
    setSearchTerm(searchTerm);
    const normalizedSearch = searchTerm.toLowerCase();
    
    setProfileState(prev => ({
      ...prev,
      filteredProfiles: prev.profiles.filter(profile => 
        profile.name.toLowerCase().includes(normalizedSearch) ||
        profile.audioSettings.some(setting => 
          setting.processingQuality.toLowerCase().includes(normalizedSearch)
        )
      ),
    }));
  }, []);

  // Batch operation handler
  const handleBatchOperation = useCallback(async (
    profileIds: string[],
    operation: typeof PROFILE_OPERATIONS.BATCH_UPDATE | typeof PROFILE_OPERATIONS.BATCH_DELETE
  ) => {
    try {
      setProfileState(prev => ({
        ...prev,
        isLoading: true,
      }));

      // Optimistic update for batch operations
      const updatedProfiles = operation === PROFILE_OPERATIONS.BATCH_DELETE
        ? profileState.profiles.filter(p => !profileIds.includes(p.id))
        : profileState.profiles;

      setProfileState(prev => ({
        ...prev,
        profiles: updatedProfiles,
        filteredProfiles: updatedProfiles,
        selectedProfileIds: new Set(),
      }));

      // API call would go here

      setSyncStatus(prev => ({
        ...prev,
        lastSync: new Date(),
        syncErrors: [],
      }));
    } catch (error) {
      setSyncStatus(prev => ({
        ...prev,
        syncErrors: [...syncStatus.syncErrors, error as Error],
      }));
      throw error;
    } finally {
      setProfileState(prev => ({
        ...prev,
        isLoading: false,
      }));
    }
  }, [profileState.profiles]);

  // Render virtual list row
  const renderRow = useCallback(({ index, style }: { index: number, style: React.CSSProperties }) => {
    const profile = sortedProfiles[index];
    return (
      <div style={style} role="listitem">
        <ProfileListItem
          profile={profile}
          isSelected={profileState.selectedProfileIds.has(profile.id)}
          onSelect={(id) => {
            setProfileState(prev => ({
              ...prev,
              selectedProfileIds: new Set([...prev.selectedProfileIds, id]),
            }));
          }}
          onProfileUpdate={(updatedProfile) => 
            handleProfileOperation(PROFILE_OPERATIONS.UPDATE, updatedProfile)
          }
        />
      </div>
    );
  }, [sortedProfiles, profileState.selectedProfileIds, handleProfileOperation]);

  return (
    <ErrorBoundary fallback={<div>Error loading profile manager</div>}>
      <Container role="region" aria-label="Profile Manager">
        <SearchInput
          type="search"
          placeholder="Search profiles..."
          value={searchTerm}
          onChange={(e) => handleProfileSearch(e.target.value)}
          aria-label="Search profiles"
        />
        
        <Suspense fallback={<div>Loading profiles...</div>}>
          <VirtualList
            height={400}
            width="100%"
            itemCount={sortedProfiles.length}
            itemSize={80}
            overscanCount={5}
          >
            {renderRow}
          </VirtualList>
        </Suspense>

        {profileState.isLoading && (
          <div role="status" aria-live="polite">Loading...</div>
        )}

        {syncStatus.syncErrors.length > 0 && (
          <div role="alert" aria-live="assertive">
            {syncStatus.syncErrors.map((error, index) => (
              <p key={index} className="error-message">{error.message}</p>
            ))}
          </div>
        )}
      </Container>
    </ErrorBoundary>
  );
});

ProfileManager.displayName = 'ProfileManager';

export default ProfileManager;