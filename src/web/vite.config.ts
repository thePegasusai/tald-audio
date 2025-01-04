import { defineConfig } from 'vite'; // ^4.4.0
import react from '@vitejs/plugin-react'; // ^4.0.0
import legacy from '@vitejs/plugin-legacy'; // ^4.0.0
import { VitePWA } from 'vite-plugin-pwa'; // ^0.16.0
import { resolve } from 'path';
import { compilerOptions } from './tsconfig.json';

// Custom plugin for audio worker optimization
const audioWorkerPlugin = () => ({
  name: 'audio-worker-plugin',
  enforce: 'post' as const,
  config: () => ({
    worker: {
      format: 'es',
      plugins: []
    }
  })
});

// Worker thread plugins configuration
const workerPlugins = () => ({
  name: 'worker-plugins',
  enforce: 'pre' as const
});

export default defineConfig({
  plugins: [
    react({
      babel: {
        plugins: [
          ['@babel/plugin-proposal-decorators', { legacy: true }]
        ]
      },
      fastRefresh: true
    }),
    legacy({
      modernPolyfills: ['web-audio-api'],
      additionalLegacyPolyfills: ['regenerator-runtime/runtime']
    }),
    VitePWA({
      strategies: 'injectManifest',
      filename: 'audio-worker.ts',
      manifest: {
        name: 'TALD UNIA Audio System',
        short_name: 'TALD UNIA',
        description: 'Advanced Audio Processing System',
        theme_color: '#ffffff',
        icons: [
          {
            src: '/icons/icon-192x192.png',
            sizes: '192x192',
            type: 'image/png'
          },
          {
            src: '/icons/icon-512x512.png',
            sizes: '512x512',
            type: 'image/png'
          }
        ]
      },
      workbox: {
        globPatterns: ['**/*.{js,css,html,ico,png,svg,wav,mp3}'],
        runtimeCaching: [
          {
            urlPattern: /^https:\/\/api\.tald-unia\.com/,
            handler: 'NetworkFirst',
            options: {
              cacheName: 'api-cache',
              expiration: {
                maxEntries: 100,
                maxAgeSeconds: 60 * 60 * 24
              }
            }
          }
        ]
      }
    })
  ],

  resolve: {
    alias: {
      '@': resolve(__dirname, './src'),
      '@audio': resolve(__dirname, './src/audio'),
      '@workers': resolve(__dirname, './src/workers'),
      ...Object.fromEntries(
        Object.entries(compilerOptions.paths || {}).map(([key, [value]]) => [
          key.replace('/*', ''),
          resolve(__dirname, value.replace('/*', ''))
        ])
      )
    }
  },

  build: {
    target: 'es2015',
    outDir: 'dist',
    assetsDir: 'assets',
    sourcemap: true,
    minify: 'terser',
    terserOptions: {
      compress: {
        drop_console: true,
        passes: 3,
        pure_funcs: ['console.log']
      }
    },
    rollupOptions: {
      output: {
        manualChunks: {
          vendor: ['react', 'react-dom', '@reduxjs/toolkit'],
          audio: ['@tensorflow/tfjs', 'web-audio-api'],
          websocket: ['socket.io-client'],
          workers: ['@audio/processor', '@audio/analyzer']
        }
      }
    },
    commonjsOptions: {
      include: [/node_modules/],
      extensions: ['.js', '.cjs']
    }
  },

  server: {
    port: 3000,
    strictPort: true,
    cors: true,
    proxy: {
      '/api': {
        target: process.env.VITE_API_URL,
        changeOrigin: true,
        secure: false,
        rewrite: (path) => path.replace(/^\/api/, '')
      },
      '/ws': {
        target: process.env.VITE_WS_URL,
        ws: true,
        changeOrigin: true
      }
    }
  },

  preview: {
    port: 3000,
    strictPort: true
  },

  optimizeDeps: {
    include: [
      'react',
      'react-dom',
      '@reduxjs/toolkit',
      '@tensorflow/tfjs',
      'socket.io-client',
      'web-audio-api'
    ],
    exclude: ['@audio/processor', '@audio/analyzer']
  },

  worker: {
    plugins: [workerPlugins(), audioWorkerPlugin()],
    format: 'es',
    rollupOptions: {
      output: {
        format: 'es',
        sourcemap: true
      }
    }
  },

  define: {
    'process.env.VITE_API_URL': JSON.stringify(process.env.VITE_API_URL),
    'process.env.VITE_WS_URL': JSON.stringify(process.env.VITE_WS_URL)
  }
});