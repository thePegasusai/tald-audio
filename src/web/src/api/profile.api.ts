/**
 * @file API client implementation for TALD UNIA profile management
 * @version 1.0.0
 */

import axios, { AxiosInstance, AxiosError } from 'axios'; // ^1.5.0
import {
  Profile,
  AudioSettings,
  ProfileResponse,
  ProfileListResponse,
  CreateProfileRequest,
  UpdateProfileRequest,
  ProcessingQuality
} from '../types/profile.types';

// API Constants
const API_VERSION = '/api/v1';
const DEFAULT_PAGE_SIZE = 10;
const MAX_RETRIES = 3;
const REQUEST_TIMEOUT = 5000;

/**
 * Cache configuration for profile data
 */
interface ProfileCache {
  profiles: Map<string, Profile>;
  listCache: Map<string, ProfileListResponse>;
  ttl: number;
}

/**
 * API configuration options
 */
interface APIConfig {
  timeout?: number;
  retryCount?: number;
  cacheTimeout?: number;
  enableRateLimiting?: boolean;
}

/**
 * Profile API client for TALD UNIA audio system
 */
export class ProfileAPI {
  private readonly axiosInstance: AxiosInstance;
  private readonly cache: ProfileCache;
  private readonly retryDelay = 1000;
  private rateLimitRemaining = 100;

  constructor(
    private readonly baseURL: string,
    private readonly config: APIConfig = {}
  ) {
    this.axiosInstance = axios.create({
      baseURL: `${baseURL}${API_VERSION}`,
      timeout: config.timeout || REQUEST_TIMEOUT,
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json'
      }
    });

    this.cache = {
      profiles: new Map(),
      listCache: new Map(),
      ttl: config.cacheTimeout || 300000 // 5 minutes default
    };

    this.setupInterceptors();
  }

  /**
   * Creates a new user profile
   */
  public async createProfile(request: CreateProfileRequest): Promise<Profile> {
    try {
      const response = await this.axiosInstance.post<ProfileResponse>(
        '/profiles',
        request
      );

      if (response.data.success) {
        const profile = response.data.profile;
        this.cache.profiles.set(profile.id, profile);
        return profile;
      }

      throw new Error(response.data.errors?.join(', ') || 'Profile creation failed');
    } catch (error) {
      return this.handleError(error as AxiosError);
    }
  }

  /**
   * Retrieves paginated list of profiles
   */
  public async getProfiles(
    page = 1,
    limit = DEFAULT_PAGE_SIZE,
    filter?: Partial<Profile>
  ): Promise<ProfileListResponse> {
    const cacheKey = `${page}-${limit}-${JSON.stringify(filter)}`;
    const cached = this.cache.listCache.get(cacheKey);

    if (cached && this.isCacheValid(cached)) {
      return cached;
    }

    try {
      const response = await this.axiosInstance.get<ProfileListResponse>('/profiles', {
        params: {
          page,
          limit,
          ...filter
        }
      });

      if (response.data.success) {
        this.cache.listCache.set(cacheKey, response.data);
        return response.data;
      }

      throw new Error('Failed to fetch profiles');
    } catch (error) {
      return this.handleError(error as AxiosError);
    }
  }

  /**
   * Retrieves a single profile by ID
   */
  public async getProfileById(id: string): Promise<Profile> {
    const cached = this.cache.profiles.get(id);

    if (cached && this.isCacheValid(cached)) {
      return cached;
    }

    try {
      const response = await this.axiosInstance.get<ProfileResponse>(`/profiles/${id}`);

      if (response.data.success) {
        const profile = response.data.profile;
        this.cache.profiles.set(id, profile);
        return profile;
      }

      throw new Error('Profile not found');
    } catch (error) {
      return this.handleError(error as AxiosError);
    }
  }

  /**
   * Updates an existing profile
   */
  public async updateProfile(id: string, updates: UpdateProfileRequest): Promise<Profile> {
    try {
      const response = await this.axiosInstance.put<ProfileResponse>(
        `/profiles/${id}`,
        updates
      );

      if (response.data.success) {
        const profile = response.data.profile;
        this.cache.profiles.set(id, profile);
        this.invalidateListCache();
        return profile;
      }

      throw new Error(response.data.errors?.join(', ') || 'Profile update failed');
    } catch (error) {
      return this.handleError(error as AxiosError);
    }
  }

  /**
   * Deletes a profile by ID
   */
  public async deleteProfile(id: string): Promise<void> {
    try {
      const response = await this.axiosInstance.delete<{ success: boolean }>(`/profiles/${id}`);

      if (response.data.success) {
        this.cache.profiles.delete(id);
        this.invalidateListCache();
        return;
      }

      throw new Error('Profile deletion failed');
    } catch (error) {
      return this.handleError(error as AxiosError);
    }
  }

  /**
   * Updates audio settings for a profile
   */
  public async updateAudioSettings(
    profileId: string,
    settingsId: string,
    updates: Partial<AudioSettings>
  ): Promise<AudioSettings> {
    try {
      const response = await this.axiosInstance.put<{ success: boolean; settings: AudioSettings }>(
        `/profiles/${profileId}/settings/${settingsId}`,
        updates
      );

      if (response.data.success) {
        const profile = await this.getProfileById(profileId);
        const settingsIndex = profile.audioSettings.findIndex(s => s.id === settingsId);
        if (settingsIndex !== -1) {
          profile.audioSettings[settingsIndex] = response.data.settings;
          this.cache.profiles.set(profileId, profile);
        }
        return response.data.settings;
      }

      throw new Error('Audio settings update failed');
    } catch (error) {
      return this.handleError(error as AxiosError);
    }
  }

  private setupInterceptors(): void {
    // Request interceptor
    this.axiosInstance.interceptors.request.use(
      (config) => {
        if (this.rateLimitRemaining <= 0) {
          throw new Error('Rate limit exceeded');
        }
        return config;
      },
      (error) => Promise.reject(error)
    );

    // Response interceptor
    this.axiosInstance.interceptors.response.use(
      (response) => {
        this.rateLimitRemaining = parseInt(response.headers['x-rate-limit-remaining'] || '100', 10);
        return response;
      },
      async (error) => {
        if (error.response?.status === 429) {
          const retryAfter = parseInt(error.response.headers['retry-after'] || '5', 10);
          await this.delay(retryAfter * 1000);
          return this.axiosInstance.request(error.config);
        }
        return Promise.reject(error);
      }
    );
  }

  private async handleError(error: AxiosError): Promise<never> {
    const retryCount = (error.config as any)?.retryCount || 0;

    if (retryCount < (this.config.retryCount || MAX_RETRIES) && this.isRetryable(error)) {
      await this.delay(this.retryDelay * Math.pow(2, retryCount));
      return this.axiosInstance.request({
        ...error.config,
        retryCount: retryCount + 1
      });
    }

    throw new Error(
      error.response?.data?.message ||
      error.message ||
      'An unexpected error occurred'
    );
  }

  private isRetryable(error: AxiosError): boolean {
    return (
      !error.response ||
      error.response.status >= 500 ||
      error.response.status === 429
    );
  }

  private isCacheValid(data: any): boolean {
    const timestamp = (data as any)._timestamp;
    return timestamp && Date.now() - timestamp < this.cache.ttl;
  }

  private invalidateListCache(): void {
    this.cache.listCache.clear();
  }

  private delay(ms: number): Promise<void> {
    return new Promise(resolve => setTimeout(resolve, ms));
  }
}

export default ProfileAPI;