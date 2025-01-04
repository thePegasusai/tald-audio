/**
 * @file Redux Toolkit slice for TALD UNIA profile management
 * @version 1.0.0
 */

import { createSlice, createAsyncThunk, createSelector, PayloadAction } from '@reduxjs/toolkit';
import { Profile, ProfilePreferences, AudioSettings } from '../../types/profile.types';
import ProfileAPI from '../../api/profile.api';

// Cache duration in milliseconds (5 minutes)
const CACHE_DURATION = 5 * 60 * 1000;
const MAX_RETRIES = 3;

interface ProfileState {
  profiles: Profile[];
  currentProfile: Profile | null;
  loading: boolean;
  error: string | null;
  total: number;
  cache: {
    [key: string]: {
      data: Profile[];
      timestamp: number;
    };
  };
  optimisticUpdates: {
    id: string;
    tempId: string;
    type: 'create' | 'update' | 'delete';
    data: Partial<Profile>;
  }[];
  lastSync: number | null;
}

const initialState: ProfileState = {
  profiles: [],
  currentProfile: null,
  loading: false,
  error: null,
  total: 0,
  cache: {},
  optimisticUpdates: [],
  lastSync: null,
};

/**
 * Fetch profiles with pagination and caching
 */
export const fetchProfiles = createAsyncThunk(
  'profiles/fetchProfiles',
  async ({ page, limit, forceRefresh = false }: { 
    page: number; 
    limit: number; 
    forceRefresh?: boolean;
  }, { getState, rejectWithValue }) => {
    const state = getState() as { profile: ProfileState };
    const cacheKey = `${page}-${limit}`;
    const cached = state.profile.cache[cacheKey];

    if (!forceRefresh && cached && Date.now() - cached.timestamp < CACHE_DURATION) {
      return { data: cached.data, total: state.profile.total };
    }

    try {
      const api = new ProfileAPI(process.env.REACT_APP_API_URL || '');
      const response = await api.getProfiles(page, limit);
      return { data: response.profiles, total: response.total };
    } catch (error) {
      return rejectWithValue((error as Error).message);
    }
  }
);

/**
 * Create new profile with optimistic update
 */
export const createProfile = createAsyncThunk(
  'profiles/createProfile',
  async (profile: Omit<Profile, 'id'>, { dispatch, rejectWithValue }) => {
    const tempId = `temp-${Date.now()}`;
    const optimisticProfile = { ...profile, id: tempId } as Profile;

    try {
      const api = new ProfileAPI(process.env.REACT_APP_API_URL || '');
      dispatch(profileSlice.actions.addOptimisticUpdate({
        id: tempId,
        tempId,
        type: 'create',
        data: optimisticProfile
      }));

      const createdProfile = await api.createProfile(profile);
      return createdProfile;
    } catch (error) {
      return rejectWithValue((error as Error).message);
    }
  }
);

/**
 * Update profile with optimistic updates
 */
export const updateProfile = createAsyncThunk(
  'profiles/updateProfile',
  async ({ id, updates }: { 
    id: string; 
    updates: Partial<Profile>;
  }, { dispatch, rejectWithValue }) => {
    const tempId = `temp-${Date.now()}`;

    try {
      const api = new ProfileAPI(process.env.REACT_APP_API_URL || '');
      dispatch(profileSlice.actions.addOptimisticUpdate({
        id,
        tempId,
        type: 'update',
        data: updates
      }));

      const updatedProfile = await api.updateProfile(id, updates);
      return updatedProfile;
    } catch (error) {
      return rejectWithValue((error as Error).message);
    }
  }
);

/**
 * Delete profile with optimistic update
 */
export const deleteProfile = createAsyncThunk(
  'profiles/deleteProfile',
  async (id: string, { dispatch, rejectWithValue }) => {
    const tempId = `temp-${Date.now()}`;

    try {
      const api = new ProfileAPI(process.env.REACT_APP_API_URL || '');
      dispatch(profileSlice.actions.addOptimisticUpdate({
        id,
        tempId,
        type: 'delete',
        data: { id }
      }));

      await api.deleteProfile(id);
      return id;
    } catch (error) {
      return rejectWithValue((error as Error).message);
    }
  }
);

const profileSlice = createSlice({
  name: 'profile',
  initialState,
  reducers: {
    setCurrentProfile: (state, action: PayloadAction<Profile>) => {
      state.currentProfile = action.payload;
    },
    addOptimisticUpdate: (state, action: PayloadAction<{
      id: string;
      tempId: string;
      type: 'create' | 'update' | 'delete';
      data: Partial<Profile>;
    }>) => {
      state.optimisticUpdates.push(action.payload);
      
      switch (action.payload.type) {
        case 'create':
          state.profiles.push(action.payload.data as Profile);
          break;
        case 'update':
          const updateIndex = state.profiles.findIndex(p => p.id === action.payload.id);
          if (updateIndex !== -1) {
            state.profiles[updateIndex] = {
              ...state.profiles[updateIndex],
              ...action.payload.data
            };
          }
          break;
        case 'delete':
          state.profiles = state.profiles.filter(p => p.id !== action.payload.id);
          break;
      }
    },
    removeOptimisticUpdate: (state, action: PayloadAction<string>) => {
      state.optimisticUpdates = state.optimisticUpdates.filter(
        update => update.tempId !== action.payload
      );
    },
    clearCache: (state) => {
      state.cache = {};
      state.lastSync = null;
    }
  },
  extraReducers: (builder) => {
    builder
      .addCase(fetchProfiles.pending, (state) => {
        state.loading = true;
        state.error = null;
      })
      .addCase(fetchProfiles.fulfilled, (state, action) => {
        state.loading = false;
        state.profiles = action.payload.data;
        state.total = action.payload.total;
        state.lastSync = Date.now();
        state.cache[`${action.meta.arg.page}-${action.meta.arg.limit}`] = {
          data: action.payload.data,
          timestamp: Date.now()
        };
      })
      .addCase(fetchProfiles.rejected, (state, action) => {
        state.loading = false;
        state.error = action.payload as string;
      })
      .addCase(createProfile.fulfilled, (state, action) => {
        const tempUpdate = state.optimisticUpdates.find(
          update => update.type === 'create'
        );
        if (tempUpdate) {
          const index = state.profiles.findIndex(p => p.id === tempUpdate.tempId);
          if (index !== -1) {
            state.profiles[index] = action.payload;
          }
          state.optimisticUpdates = state.optimisticUpdates.filter(
            update => update.tempId !== tempUpdate.tempId
          );
        }
      })
      .addCase(updateProfile.fulfilled, (state, action) => {
        const tempUpdate = state.optimisticUpdates.find(
          update => update.id === action.payload.id
        );
        if (tempUpdate) {
          const index = state.profiles.findIndex(p => p.id === action.payload.id);
          if (index !== -1) {
            state.profiles[index] = action.payload;
          }
          state.optimisticUpdates = state.optimisticUpdates.filter(
            update => update.tempId !== tempUpdate.tempId
          );
        }
      })
      .addCase(deleteProfile.fulfilled, (state, action) => {
        const tempUpdate = state.optimisticUpdates.find(
          update => update.id === action.payload
        );
        if (tempUpdate) {
          state.optimisticUpdates = state.optimisticUpdates.filter(
            update => update.tempId !== tempUpdate.tempId
          );
        }
      });
  }
});

// Selectors
export const selectProfiles = createSelector(
  [(state: { profile: ProfileState }) => state.profile],
  (profile) => profile.profiles
);

export const selectProfileById = createSelector(
  [
    (state: { profile: ProfileState }) => state.profile.profiles,
    (_: any, id: string) => id
  ],
  (profiles, id) => profiles.find(profile => profile.id === id)
);

export const selectCurrentProfile = createSelector(
  [(state: { profile: ProfileState }) => state.profile],
  (profile) => profile.currentProfile
);

export const { setCurrentProfile, clearCache } = profileSlice.actions;
export default profileSlice.reducer;