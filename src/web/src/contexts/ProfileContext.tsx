/**
 * @file React Context provider for managing TALD UNIA user profiles and audio settings
 * @version 1.0.0
 */

import React, { createContext, useContext, useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { useDispatch, useSelector } from 'react-redux';
import { useErrorBoundary } from 'react-error-boundary';
import { z } from 'zod';

import { 
  Profile, 
  ProfilePreferences, 
  AudioSettings, 
  ProcessingQuality,
  ProfileResponse 
} from '../types/profile.types';
import ProfileAPI from '../api/profile.api';

// Context error messages
const PROFILE_CONTEXT_ERROR = 'useProfile must be used within a ProfileProvider';
const DEFAULT_PAGE_SIZE = 10;
const CACHE_TIMEOUT = 300000; // 5 minutes
const MAX_RETRY_ATTEMPTS = 3;

// Profile context state interface
interface ProfileContextState {
  profiles: Profile[];
  currentProfile: Profile | null;
  loading: boolean;
  error: Error | null;
}

// Profile context actions interface
interface ProfileContextActions {
  loadProfiles: () => Promise<void>;
  createProfile: (profile: Omit<Profile, 'id'>) => Promise<Profile>;
  updateProfile: (id: string, updates: Partial<Profile>) => Promise<Profile>;
  deleteProfile: (id: string) => Promise<void>;
  setCurrentProfile: (profile: Profile) => void;
  updateAudioSettings: (profileId: string, settingsId: string, updates: Partial<AudioSettings>) => Promise<AudioSettings>;
}

// Combined context type
type ProfileContextType = ProfileContextState & ProfileContextActions;

// Create the context
const ProfileContext = createContext<ProfileContextType | null>(null);

// Profile validation schema
const profileSchema = z.object({
  id: z.string().optional(),
  userId: z.string(),
  name: z.string().min(1),
  preferences: z.object({
    theme: z.enum(['light', 'dark']),
    language: z.string(),
    notifications: z.boolean(),
    autoSave: z.boolean()
  }),
  audioSettings: z.array(z.object({
    id: z.string().optional(),
    processingQuality: z.nativeEnum(ProcessingQuality),
    sampleRate: z.number(),
    bitDepth: z.number(),
    channels: z.number(),
    isActive: z.boolean()
  }))
});

// Provider props interface
interface ProfileProviderProps {
  children: React.ReactNode;
  apiBaseUrl: string;
  initialProfile?: Profile;
}

/**
 * Profile Provider Component
 */
export const ProfileProvider: React.FC<ProfileProviderProps> = ({ 
  children, 
  apiBaseUrl, 
  initialProfile 
}) => {
  const [state, setState] = useState<ProfileContextState>({
    profiles: [],
    currentProfile: initialProfile || null,
    loading: false,
    error: null
  });

  const dispatch = useDispatch();
  const { showBoundary } = useErrorBoundary();
  const apiRef = useRef<ProfileAPI>();
  const cacheTimeoutRef = useRef<NodeJS.Timeout>();

  // Initialize API client
  useEffect(() => {
    apiRef.current = new ProfileAPI(apiBaseUrl, {
      timeout: 5000,
      retryCount: MAX_RETRY_ATTEMPTS,
      cacheTimeout: CACHE_TIMEOUT,
      enableRateLimiting: true
    });

    return () => {
      if (cacheTimeoutRef.current) {
        clearTimeout(cacheTimeoutRef.current);
      }
    };
  }, [apiBaseUrl]);

  // Load profiles
  const loadProfiles = useCallback(async () => {
    if (!apiRef.current) return;

    try {
      setState(prev => ({ ...prev, loading: true, error: null }));
      const response = await apiRef.current.getProfiles(1, DEFAULT_PAGE_SIZE);
      
      if (response.success) {
        setState(prev => ({
          ...prev,
          profiles: response.profiles,
          loading: false
        }));
      } else {
        throw new Error('Failed to load profiles');
      }
    } catch (error) {
      const err = error instanceof Error ? error : new Error('Unknown error');
      setState(prev => ({ ...prev, error: err, loading: false }));
      showBoundary(err);
    }
  }, [showBoundary]);

  // Create profile
  const createProfile = useCallback(async (profile: Omit<Profile, 'id'>) => {
    if (!apiRef.current) throw new Error('API client not initialized');

    try {
      const validatedProfile = profileSchema.parse(profile);
      const created = await apiRef.current.createProfile(validatedProfile);
      
      setState(prev => ({
        ...prev,
        profiles: [...prev.profiles, created]
      }));

      return created;
    } catch (error) {
      const err = error instanceof Error ? error : new Error('Profile creation failed');
      showBoundary(err);
      throw err;
    }
  }, [showBoundary]);

  // Update profile
  const updateProfile = useCallback(async (id: string, updates: Partial<Profile>) => {
    if (!apiRef.current) throw new Error('API client not initialized');

    try {
      const updated = await apiRef.current.updateProfile(id, updates);
      
      setState(prev => ({
        ...prev,
        profiles: prev.profiles.map(p => p.id === id ? updated : p),
        currentProfile: prev.currentProfile?.id === id ? updated : prev.currentProfile
      }));

      return updated;
    } catch (error) {
      const err = error instanceof Error ? error : new Error('Profile update failed');
      showBoundary(err);
      throw err;
    }
  }, [showBoundary]);

  // Delete profile
  const deleteProfile = useCallback(async (id: string) => {
    if (!apiRef.current) throw new Error('API client not initialized');

    try {
      await apiRef.current.deleteProfile(id);
      
      setState(prev => ({
        ...prev,
        profiles: prev.profiles.filter(p => p.id !== id),
        currentProfile: prev.currentProfile?.id === id ? null : prev.currentProfile
      }));
    } catch (error) {
      const err = error instanceof Error ? error : new Error('Profile deletion failed');
      showBoundary(err);
      throw err;
    }
  }, [showBoundary]);

  // Update audio settings
  const updateAudioSettings = useCallback(async (
    profileId: string,
    settingsId: string,
    updates: Partial<AudioSettings>
  ) => {
    if (!apiRef.current) throw new Error('API client not initialized');

    try {
      const updated = await apiRef.current.updateAudioSettings(profileId, settingsId, updates);
      
      setState(prev => ({
        ...prev,
        profiles: prev.profiles.map(p => {
          if (p.id !== profileId) return p;
          return {
            ...p,
            audioSettings: p.audioSettings.map(s => 
              s.id === settingsId ? updated : s
            )
          };
        }),
        currentProfile: prev.currentProfile?.id === profileId ? {
          ...prev.currentProfile,
          audioSettings: prev.currentProfile.audioSettings.map(s =>
            s.id === settingsId ? updated : s
          )
        } : prev.currentProfile
      }));

      return updated;
    } catch (error) {
      const err = error instanceof Error ? error : new Error('Audio settings update failed');
      showBoundary(err);
      throw err;
    }
  }, [showBoundary]);

  // Set current profile
  const setCurrentProfile = useCallback((profile: Profile) => {
    setState(prev => ({ ...prev, currentProfile: profile }));
  }, []);

  // Context value
  const value = useMemo(() => ({
    ...state,
    loadProfiles,
    createProfile,
    updateProfile,
    deleteProfile,
    setCurrentProfile,
    updateAudioSettings
  }), [
    state,
    loadProfiles,
    createProfile,
    updateProfile,
    deleteProfile,
    setCurrentProfile,
    updateAudioSettings
  ]);

  return (
    <ProfileContext.Provider value={value}>
      {children}
    </ProfileContext.Provider>
  );
};

/**
 * Custom hook for accessing profile context
 */
export const useProfile = (): ProfileContextType => {
  const context = useContext(ProfileContext);
  if (!context) {
    throw new Error(PROFILE_CONTEXT_ERROR);
  }
  return context;
};

export default ProfileContext;