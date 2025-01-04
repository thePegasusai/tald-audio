/**
 * @file Test suite for ProfileManager component
 * @version 1.0.0
 */

import React from 'react';
import { render, screen, fireEvent, waitFor, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { vi, describe, it, expect, beforeEach, afterEach } from 'vitest';
import { axe, toHaveNoViolations } from 'jest-axe';
import { ErrorBoundary } from 'react-error-boundary';
import { ThemeProvider } from 'styled-components';

import ProfileManager from '../../../src/components/profile/ProfileManager';
import { Profile, ProcessingQuality } from '../../../src/types/profile.types';
import { ProfileContext } from '../../../src/contexts/ProfileContext';

expect.extend(toHaveNoViolations);

// Mock theme for styled-components
const theme = {
  colors: {
    background: { primary: '#ffffff' },
    border: { primary: '#e0e0e0' },
    focus: { primary: '#0066cc' }
  }
};

// Mock profile data
const mockProfiles: Profile[] = [
  {
    id: '1',
    userId: 'user1',
    name: 'Studio Profile',
    preferences: {
      theme: 'dark',
      language: 'en',
      notifications: true,
      autoSave: true
    },
    isDefault: true,
    audioSettings: [{
      id: 'as1',
      profileId: '1',
      sampleRate: 192000,
      bitDepth: 32,
      channels: 2,
      bufferSize: 256,
      processingQuality: ProcessingQuality.Maximum,
      isActive: true
    }],
    createdAt: '2024-01-20T00:00:00Z',
    updatedAt: '2024-01-20T00:00:00Z'
  }
];

// Mock profile context
const mockProfileContext = {
  profiles: mockProfiles,
  currentProfile: mockProfiles[0],
  loading: false,
  error: null,
  loadProfiles: vi.fn(),
  createProfile: vi.fn(),
  updateProfile: vi.fn(),
  deleteProfile: vi.fn(),
  setCurrentProfile: vi.fn(),
  updateAudioSettings: vi.fn()
};

// Enhanced render helper with providers
const renderWithProviders = (
  ui: React.ReactElement,
  { providerProps = {}, ...renderOptions } = {}
) => {
  return render(
    <ErrorBoundary fallback={<div>Error Boundary</div>}>
      <ThemeProvider theme={theme}>
        <ProfileContext.Provider value={{ ...mockProfileContext, ...providerProps }}>
          {ui}
        </ProfileContext.Provider>
      </ThemeProvider>
    </ErrorBoundary>,
    renderOptions
  );
};

describe('ProfileManager Component', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  afterEach(() => {
    vi.resetAllMocks();
  });

  describe('Accessibility', () => {
    it('should have no accessibility violations', async () => {
      const { container } = renderWithProviders(<ProfileManager />);
      const results = await axe(container);
      expect(results).toHaveNoViolations();
    });

    it('should support keyboard navigation', async () => {
      renderWithProviders(<ProfileManager />);
      const searchInput = screen.getByRole('searchbox');
      
      await userEvent.tab();
      expect(searchInput).toHaveFocus();
      
      await userEvent.keyboard('{Tab}');
      const firstProfile = screen.getByRole('listitem');
      expect(firstProfile).toHaveFocus();
    });

    it('should announce loading states to screen readers', async () => {
      renderWithProviders(<ProfileManager />, {
        providerProps: { loading: true }
      });
      
      expect(screen.getByRole('status')).toHaveAttribute('aria-live', 'polite');
      expect(screen.getByText('Loading...')).toBeInTheDocument();
    });
  });

  describe('Profile Management', () => {
    it('should render profile list correctly', () => {
      renderWithProviders(<ProfileManager />);
      expect(screen.getByText('Studio Profile')).toBeInTheDocument();
    });

    it('should filter profiles based on search input', async () => {
      renderWithProviders(<ProfileManager />);
      const searchInput = screen.getByRole('searchbox');
      
      await userEvent.type(searchInput, 'Studio');
      expect(screen.getByText('Studio Profile')).toBeInTheDocument();
      
      await userEvent.clear(searchInput);
      await userEvent.type(searchInput, 'NonExistent');
      expect(screen.queryByText('Studio Profile')).not.toBeInTheDocument();
    });

    it('should handle profile selection', async () => {
      renderWithProviders(<ProfileManager />);
      const profileItem = screen.getByText('Studio Profile').closest('div');
      expect(profileItem).toBeInTheDocument();
      
      if (profileItem) {
        await userEvent.click(profileItem);
        expect(mockProfileContext.setCurrentProfile).toHaveBeenCalledWith(mockProfiles[0]);
      }
    });
  });

  describe('Error Handling', () => {
    it('should display error messages when profile operations fail', async () => {
      const error = new Error('Failed to update profile');
      renderWithProviders(<ProfileManager />, {
        providerProps: { error }
      });
      
      expect(screen.getByRole('alert')).toBeInTheDocument();
      expect(screen.getByText(error.message)).toBeInTheDocument();
    });

    it('should recover from errors when retrying operations', async () => {
      const error = new Error('Operation failed');
      const { rerender } = renderWithProviders(<ProfileManager />, {
        providerProps: { error }
      });

      expect(screen.getByRole('alert')).toBeInTheDocument();
      
      rerender(
        <ProfileManager />
      );
      
      expect(screen.queryByRole('alert')).not.toBeInTheDocument();
    });
  });

  describe('Performance', () => {
    it('should efficiently render large profile lists', async () => {
      const largeProfileList = Array.from({ length: 100 }, (_, i) => ({
        ...mockProfiles[0],
        id: `profile-${i}`,
        name: `Profile ${i}`
      }));

      const { container } = renderWithProviders(<ProfileManager />, {
        providerProps: { profiles: largeProfileList }
      });

      const virtualList = container.querySelector('.react-window-list');
      expect(virtualList).toBeInTheDocument();

      // Verify only visible items are rendered
      const renderedItems = screen.getAllByRole('listitem');
      expect(renderedItems.length).toBeLessThan(largeProfileList.length);
    });

    it('should debounce search input', async () => {
      vi.useFakeTimers();
      renderWithProviders(<ProfileManager />);
      
      const searchInput = screen.getByRole('searchbox');
      await userEvent.type(searchInput, 'test');
      
      expect(mockProfileContext.loadProfiles).not.toHaveBeenCalled();
      
      vi.runAllTimers();
      
      expect(mockProfileContext.loadProfiles).toHaveBeenCalledTimes(1);
      vi.useRealTimers();
    });
  });

  describe('Real-time Sync', () => {
    it('should update UI when profiles are modified externally', async () => {
      const { rerender } = renderWithProviders(<ProfileManager />);
      
      const updatedProfiles = [
        {
          ...mockProfiles[0],
          name: 'Updated Profile'
        }
      ];

      rerender(
        <ProfileManager />
      );

      await waitFor(() => {
        expect(screen.getByText('Updated Profile')).toBeInTheDocument();
      });
    });

    it('should handle concurrent profile updates', async () => {
      renderWithProviders(<ProfileManager />);
      
      const profileItem = screen.getByText('Studio Profile').closest('div');
      if (profileItem) {
        await userEvent.click(profileItem);
        await userEvent.click(profileItem);
        
        expect(mockProfileContext.setCurrentProfile).toHaveBeenCalledTimes(1);
      }
    });
  });
});