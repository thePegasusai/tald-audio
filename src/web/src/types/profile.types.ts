/**
 * @file Type definitions for TALD UNIA user profiles and audio settings
 * @version 1.0.0
 */

/**
 * Available audio processing quality levels
 */
export enum ProcessingQuality {
  Maximum = 'MAXIMUM',
  Balanced = 'BALANCED',
  PowerSaver = 'POWER_SAVER'
}

/**
 * Global constants for audio configuration
 */
export const DEFAULT_SAMPLE_RATE = 192000;
export const DEFAULT_BIT_DEPTH = 32;
export const DEFAULT_CHANNELS = 2;
export const DEFAULT_BUFFER_SIZE = 256;
export const MAX_EQ_BANDS = 31;

/**
 * User profile preferences
 */
export interface ProfilePreferences {
  theme: 'light' | 'dark';
  language: string;
  notifications: boolean;
  autoSave: boolean;
}

/**
 * EQ band configuration
 */
export interface EQBand {
  id: string;
  frequency: number;
  gain: number;
  q: number;
  type: 'peak' | 'lowshelf' | 'highshelf' | 'lowpass' | 'highpass';
  enabled: boolean;
}

/**
 * Compressor settings configuration
 */
export interface CompressorSettings {
  threshold: number;
  ratio: number;
  attack: number;
  release: number;
  knee: number;
  makeupGain: number;
  enabled: boolean;
}

/**
 * Room correction configuration
 */
export interface RoomCorrectionConfig {
  enabled: boolean;
  roomSize: 'small' | 'medium' | 'large';
  calibrationData?: Float32Array;
  targetCurve?: Float32Array;
  correctionStrength: number;
}

/**
 * DSP processing configuration
 */
export interface DSPConfig {
  enableEQ: boolean;
  eqBands: EQBand[];
  enableCompression: boolean;
  compressorSettings: CompressorSettings;
  enableRoomCorrection: boolean;
  roomConfig: RoomCorrectionConfig;
}

/**
 * AI enhancement configuration
 */
export interface AIConfig {
  enabled: boolean;
  enhancementLevel: number;
  noiseReduction: boolean;
  spatialUpsampling: boolean;
  modelVersion: string;
  processingMode: 'realtime' | 'quality';
}

/**
 * Spatial audio configuration
 */
export interface SpatialConfig {
  enabled: boolean;
  roomProfile: string;
  hrtfProfile: string;
  headTracking: boolean;
  binauralRendering: boolean;
  objectBasedAudio: boolean;
  speakerLayout: string;
}

/**
 * Complete audio settings configuration
 */
export interface AudioSettings {
  id: string;
  profileId: string;
  sampleRate: number;
  bitDepth: number;
  channels: number;
  bufferSize: number;
  processingQuality: ProcessingQuality;
  dspConfig: DSPConfig;
  aiConfig: AIConfig;
  spatialConfig: SpatialConfig;
  isActive: boolean;
}

/**
 * User profile with complete configuration
 */
export interface Profile {
  id: string;
  userId: string;
  name: string;
  preferences: ProfilePreferences;
  isDefault: boolean;
  audioSettings: AudioSettings[];
  createdAt: string;
  updatedAt: string;
}

/**
 * Profile creation request
 */
export interface CreateProfileRequest {
  name: string;
  preferences: ProfilePreferences;
  audioSettings: Omit<AudioSettings, 'id' | 'profileId'>[];
}

/**
 * Profile update request
 */
export interface UpdateProfileRequest {
  name?: string;
  preferences?: Partial<ProfilePreferences>;
  audioSettings?: Partial<AudioSettings>[];
}

/**
 * Profile response with validation
 */
export interface ProfileResponse {
  success: boolean;
  profile: Profile;
  errors?: string[];
}

/**
 * Profile list response
 */
export interface ProfileListResponse {
  success: boolean;
  profiles: Profile[];
  total: number;
  page: number;
  pageSize: number;
}