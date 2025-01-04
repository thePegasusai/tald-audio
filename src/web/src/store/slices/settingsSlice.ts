/**
 * @file Redux slice for TALD UNIA Audio System settings management
 * @version 1.0.0
 */

import { createSlice, PayloadAction, createSelector } from '@reduxjs/toolkit';
import { produce } from 'immer';
import { z } from 'zod';
import {
    SystemSettings,
    ProcessingQuality,
    HardwareConfig,
    ProcessingConfig,
    SpatialConfig
} from '../../types/settings.types';

// Validation schemas using zod
const hardwareSchema = z.object({
    sampleRate: z.union([z.literal(44100), z.literal(48000), z.literal(96000), z.literal(192000)]),
    bitDepth: z.union([z.literal(16), z.literal(24), z.literal(32)]),
    bufferSize: z.union([z.literal(64), z.literal(128), z.literal(256), z.literal(512), z.literal(1024)]),
    deviceId: z.string(),
    deviceName: z.string(),
    maxChannels: z.number().min(2).max(32)
});

const processingSchema = z.object({
    quality: z.nativeEnum(ProcessingQuality),
    localAIEnabled: z.boolean(),
    cloudProcessingEnabled: z.boolean(),
    roomCalibrationEnabled: z.boolean(),
    inferenceThreads: z.number().min(1).max(32),
    enhancementLevel: z.number().min(0).max(100)
});

const spatialSchema = z.object({
    headTrackingEnabled: z.boolean(),
    hrtfProfile: z.string(),
    roomSize: z.number().min(0).max(1000),
    reverbTime: z.number().min(0).max(10),
    wallAbsorption: z.number().min(0).max(1),
    listenerPosition: z.object({
        x: z.number(),
        y: z.number(),
        z: z.number()
    })
});

// Initial state with default values
const initialState: SystemSettings = {
    hardware: {
        sampleRate: 192000,
        bitDepth: 32,
        bufferSize: 256,
        deviceId: 'default',
        deviceName: 'TALD UNIA DAC',
        maxChannels: 2
    },
    processing: {
        quality: ProcessingQuality.BALANCED,
        localAIEnabled: true,
        cloudProcessingEnabled: false,
        roomCalibrationEnabled: false,
        inferenceThreads: 4,
        enhancementLevel: 50
    },
    spatial: {
        headTrackingEnabled: false,
        hrtfProfile: 'default',
        roomSize: 30,
        reverbTime: 0.3,
        wallAbsorption: 0.5,
        listenerPosition: { x: 0, y: 0, z: 0 }
    },
    version: '1.0.0',
    lastUpdated: new Date()
};

// Create the settings slice
const settingsSlice = createSlice({
    name: 'settings',
    initialState,
    reducers: {
        updateHardwareConfig: (state, action: PayloadAction<Partial<HardwareConfig>>) => {
            return produce(state, draft => {
                try {
                    const validatedConfig = hardwareSchema.partial().parse(action.payload);
                    Object.assign(draft.hardware, validatedConfig);
                    draft.lastUpdated = new Date();
                } catch (error) {
                    console.error('Hardware config validation failed:', error);
                    return state;
                }
            });
        },

        updateProcessingConfig: (state, action: PayloadAction<Partial<ProcessingConfig>>) => {
            return produce(state, draft => {
                try {
                    const validatedConfig = processingSchema.partial().parse(action.payload);
                    Object.assign(draft.processing, validatedConfig);
                    draft.lastUpdated = new Date();
                } catch (error) {
                    console.error('Processing config validation failed:', error);
                    return state;
                }
            });
        },

        updateSpatialConfig: (state, action: PayloadAction<Partial<SpatialConfig>>) => {
            return produce(state, draft => {
                try {
                    const validatedConfig = spatialSchema.partial().parse(action.payload);
                    Object.assign(draft.spatial, validatedConfig);
                    draft.lastUpdated = new Date();
                } catch (error) {
                    console.error('Spatial config validation failed:', error);
                    return state;
                }
            });
        },

        resetSettings: (state) => {
            return produce(state, draft => {
                Object.assign(draft, initialState);
                draft.lastUpdated = new Date();
            });
        }
    }
});

// Memoized selectors for optimized state access
export const selectSettings = createSelector(
    [(state: { settings: SystemSettings }) => state.settings],
    (settings) => settings
);

export const selectHardwareConfig = createSelector(
    [selectSettings],
    (settings) => settings.hardware
);

export const selectProcessingConfig = createSelector(
    [selectSettings],
    (settings) => settings.processing
);

export const selectSpatialConfig = createSelector(
    [selectSettings],
    (settings) => settings.spatial
);

// Export actions and reducer
export const { 
    updateHardwareConfig, 
    updateProcessingConfig, 
    updateSpatialConfig, 
    resetSettings 
} = settingsSlice.actions;

export default settingsSlice.reducer;