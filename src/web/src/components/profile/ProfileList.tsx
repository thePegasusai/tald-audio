/**
 * @file ProfileList component for displaying and managing TALD UNIA audio profiles
 * @version 1.0.0
 */

import React, { useState, useCallback, useMemo, useRef } from 'react';
import styled from '@emotion/styled';
import { ErrorBoundary } from 'react-error-boundary';
import { useVirtualizer } from '@tanstack/react-virtual';
import { useTranslation } from 'react-i18next';
import { analytics } from '@segment/analytics-next';

import { Profile } from '../../types/profile.types';
import { useProfile } from '../../contexts/ProfileContext';

// Constants
const VIRTUAL_LIST_OVERSCAN = 5;
const SEARCH_DEBOUNCE_MS = 300;
const CONFIRM_DELETE_MESSAGE = 'Are you sure you want to delete this profile? This action cannot be undone.';

// Props interface
interface ProfileListProps {
  className?: string;
  onProfileSelect?: (profileId: string) => void;
  initialFilter?: string;
  sortOrder?: 'asc' | 'desc';
  groupBy?: 'category' | 'status' | 'none';
}

// Styled components
const ListContainer = styled.div`
  display: flex;
  flex-direction: column;
  max-height: 600px;
  overflow: auto;
  background: ${({ theme }) => theme.colors.background.primary};
  border: 1px solid ${({ theme }) => theme.colors.border.primary};
  border-radius: ${({ theme }) => theme.borderRadius.medium};
  padding: ${({ theme }) => theme.spacing.medium};

  @media (prefers-reduced-motion: no-preference) {
    transition: all 0.2s ease;
  }

  @media (prefers-color-scheme: dark) {
    background: ${({ theme }) => theme.colors.background.dark};
  }

  &:focus-visible {
    outline: 2px solid ${({ theme }) => theme.colors.focus};
    outline-offset: 2px;
  }
`;

const ProfileItem = styled.div<{ isSelected: boolean }>`
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: ${({ theme }) => theme.spacing.medium};
  background: ${({ isSelected, theme }) => 
    isSelected ? theme.colors.background.selected : 'transparent'};
  border-radius: ${({ theme }) => theme.borderRadius.small};
  cursor: pointer;

  &:hover {
    background: ${({ theme }) => theme.colors.background.hover};
  }

  &:focus-visible {
    outline: 2px solid ${({ theme }) => theme.colors.focus};
    outline-offset: -2px;
  }
`;

const SearchInput = styled.input`
  padding: ${({ theme }) => theme.spacing.small};
  margin-bottom: ${({ theme }) => theme.spacing.medium};
  border: 1px solid ${({ theme }) => theme.colors.border.primary};
  border-radius: ${({ theme }) => theme.borderRadius.small};
  width: 100%;

  &:focus-visible {
    outline: 2px solid ${({ theme }) => theme.colors.focus};
    outline-offset: 2px;
  }
`;

const NoResults = styled.div`
  text-align: center;
  padding: ${({ theme }) => theme.spacing.large};
  color: ${({ theme }) => theme.colors.text.secondary};
`;

const ErrorFallback = styled.div`
  padding: ${({ theme }) => theme.spacing.medium};
  color: ${({ theme }) => theme.colors.error};
  text-align: center;
`;

export const ProfileList: React.FC<ProfileListProps> = ({
  className,
  onProfileSelect,
  initialFilter = '',
  sortOrder = 'desc',
  groupBy = 'none'
}) => {
  const { t } = useTranslation();
  const { profiles, selectedProfile, selectProfile, deleteProfile } = useProfile();
  const [searchTerm, setSearchTerm] = useState(initialFilter);
  const [isDeleting, setIsDeleting] = useState(false);
  const containerRef = useRef<HTMLDivElement>(null);
  const searchTimeoutRef = useRef<NodeJS.Timeout>();

  // Filter and sort profiles
  const filteredProfiles = useMemo(() => {
    let result = profiles.filter(profile =>
      profile.name.toLowerCase().includes(searchTerm.toLowerCase())
    );

    if (sortOrder === 'asc') {
      result.sort((a, b) => a.name.localeCompare(b.name));
    } else {
      result.sort((a, b) => b.name.localeCompare(a.name));
    }

    if (groupBy !== 'none') {
      result.sort((a, b) => a[groupBy].localeCompare(b[groupBy]));
    }

    return result;
  }, [profiles, searchTerm, sortOrder, groupBy]);

  // Virtual list setup
  const rowVirtualizer = useVirtualizer({
    count: filteredProfiles.length,
    getScrollElement: () => containerRef.current,
    estimateSize: () => 64,
    overscan: VIRTUAL_LIST_OVERSCAN
  });

  // Handle profile selection
  const handleProfileSelect = useCallback(async (profileId: string) => {
    try {
      analytics.track('Profile Selected', { profileId });
      
      await selectProfile(profileId);
      onProfileSelect?.(profileId);

      // Announce selection to screen readers
      const profile = profiles.find(p => p.id === profileId);
      if (profile) {
        const announcement = t('profile.selected', { name: profile.name });
        const ariaLive = document.getElementById('profile-announcer');
        if (ariaLive) ariaLive.textContent = announcement;
      }
    } catch (error) {
      console.error('Profile selection failed:', error);
    }
  }, [selectProfile, onProfileSelect, profiles, t]);

  // Handle profile deletion
  const handleProfileDelete = useCallback(async (profileId: string) => {
    if (!window.confirm(t('profile.deleteConfirmation', { defaultValue: CONFIRM_DELETE_MESSAGE }))) {
      return;
    }

    try {
      setIsDeleting(true);
      analytics.track('Profile Deleted', { profileId });
      
      await deleteProfile(profileId);

      // Announce deletion to screen readers
      const announcement = t('profile.deleted');
      const ariaLive = document.getElementById('profile-announcer');
      if (ariaLive) ariaLive.textContent = announcement;
    } catch (error) {
      console.error('Profile deletion failed:', error);
    } finally {
      setIsDeleting(false);
    }
  }, [deleteProfile, t]);

  // Handle search input
  const handleSearch = useCallback((event: React.ChangeEvent<HTMLInputElement>) => {
    const value = event.target.value;
    
    if (searchTimeoutRef.current) {
      clearTimeout(searchTimeoutRef.current);
    }

    searchTimeoutRef.current = setTimeout(() => {
      setSearchTerm(value);
      analytics.track('Profile Search', { searchTerm: value });
    }, SEARCH_DEBOUNCE_MS);
  }, []);

  return (
    <ErrorBoundary
      FallbackComponent={({ error }) => (
        <ErrorFallback role="alert">
          {t('profile.error', { message: error.message })}
        </ErrorFallback>
      )}
    >
      <ListContainer
        ref={containerRef}
        className={className}
        role="listbox"
        aria-label={t('profile.listLabel')}
      >
        <SearchInput
          type="search"
          placeholder={t('profile.searchPlaceholder')}
          onChange={handleSearch}
          defaultValue={initialFilter}
          aria-label={t('profile.searchLabel')}
        />

        <div
          style={{
            height: `${rowVirtualizer.getTotalSize()}px`,
            width: '100%',
            position: 'relative'
          }}
        >
          {rowVirtualizer.getVirtualItems().map(virtualRow => {
            const profile = filteredProfiles[virtualRow.index];
            const isSelected = selectedProfile?.id === profile.id;

            return (
              <ProfileItem
                key={profile.id}
                style={{
                  position: 'absolute',
                  top: 0,
                  left: 0,
                  width: '100%',
                  height: `${virtualRow.size}px`,
                  transform: `translateY(${virtualRow.start}px)`
                }}
                isSelected={isSelected}
                role="option"
                aria-selected={isSelected}
                onClick={() => handleProfileSelect(profile.id)}
                onKeyDown={(e) => {
                  if (e.key === 'Enter' || e.key === ' ') {
                    e.preventDefault();
                    handleProfileSelect(profile.id);
                  }
                }}
                tabIndex={0}
              >
                <div>
                  <strong>{profile.name}</strong>
                  <div>{new Date(profile.updatedAt).toLocaleDateString()}</div>
                </div>
                <button
                  onClick={(e) => {
                    e.stopPropagation();
                    handleProfileDelete(profile.id);
                  }}
                  disabled={isDeleting || profile.isDefault}
                  aria-label={t('profile.deleteLabel', { name: profile.name })}
                >
                  {t('profile.delete')}
                </button>
              </ProfileItem>
            );
          })}
        </div>

        {filteredProfiles.length === 0 && (
          <NoResults role="status">
            {t('profile.noResults')}
          </NoResults>
        )}

        <div
          id="profile-announcer"
          role="status"
          aria-live="polite"
          className="sr-only"
        />
      </ListContainer>
    </ErrorBoundary>
  );
};

export default ProfileList;