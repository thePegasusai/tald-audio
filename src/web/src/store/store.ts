/**
 * TALD UNIA Audio System - Redux Store Configuration
 * Version: 1.0.0
 */

import { configureStore, createSerializableStateInvariantMiddleware } from '@reduxjs/toolkit'; // v2.0.0
import thunk from 'redux-thunk'; // v2.4.2
import { persistStore } from 'redux-persist'; // v6.0.0

// Import reducers
import audioReducer from './slices/audioSlice';
import profileReducer from './slices/profileSlice';
import settingsReducer from './slices/settingsSlice';
import visualizationReducer from './slices/visualizationSlice';

// Configure serializable check middleware with custom options
const serializableMiddleware = createSerializableStateInvariantMiddleware({
  ignoredActions: ['persist/PERSIST', 'persist/REHYDRATE'],
  ignoredPaths: ['audio.processingState.errorState'],
  warnAfter: 100
});

// Configure store with all reducers and middleware
const store = configureStore({
  reducer: {
    audio: audioReducer,
    profile: profileReducer,
    settings: settingsReducer,
    visualization: visualizationReducer
  },
  middleware: (getDefaultMiddleware) => getDefaultMiddleware({
    serializableCheck: false,
    thunk: true
  }).concat(serializableMiddleware),
  devTools: process.env.NODE_ENV === 'development' ? {
    trace: true,
    traceLimit: 25,
    maxAge: 50
  } : false,
  preloadedState: undefined,
  enhancers: []
});

// Configure Redux persist
export const persistor = persistStore(store, {
  manualPersist: false,
  serialize: true,
  throttle: 1000,
  blacklist: ['visualization']
});

// Set up hot module replacement for reducers
if (process.env.NODE_ENV === 'development' && module.hot) {
  module.hot.accept('./slices/audioSlice', () => {
    store.replaceReducer(audioReducer);
  });
  module.hot.accept('./slices/profileSlice', () => {
    store.replaceReducer(profileReducer);
  });
  module.hot.accept('./slices/settingsSlice', () => {
    store.replaceReducer(settingsReducer);
  });
  module.hot.accept('./slices/visualizationSlice', () => {
    store.replaceReducer(visualizationReducer);
  });
}

// Set up performance monitoring
if (process.env.NODE_ENV === 'development') {
  const PERFORMANCE_SAMPLE_RATE = 0.1;
  store.subscribe(() => {
    if (Math.random() < PERFORMANCE_SAMPLE_RATE) {
      const state = store.getState();
      console.debug('Store Performance Metrics:', {
        audioLatency: state.audio.processingState.latency,
        cpuLoad: state.visualization.processingStatus.cpuLoad,
        bufferHealth: state.audio.processingState.bufferHealth
      });
    }
  });
}

// Export types and store
export type RootState = ReturnType<typeof store.getState>;
export type AppDispatch = typeof store.dispatch;
export default store;