import { Module } from '@nestjs/common'; // ^10.0.0
import { ConfigModule } from '@nestjs/config'; // ^10.0.0
import { CacheService } from './cache.service';

/**
 * NestJS module that provides Redis-based caching functionality for the TALD UNIA audio system.
 * Implements a memory/disk hybrid caching strategy optimized for low-latency audio processing
 * with comprehensive monitoring and security features.
 */
@Module({
  imports: [
    ConfigModule.forFeature(() => ({
      redis: {
        host: process.env.REDIS_HOST,
        port: process.env.REDIS_PORT,
        password: process.env.REDIS_PASSWORD,
        // Enable TLS in production for security
        tls: process.env.NODE_ENV === 'production',
        // Additional Redis configuration from environment
        db: parseInt(process.env.REDIS_DB || '0', 10),
        keyPrefix: process.env.REDIS_KEY_PREFIX || 'tald:',
        connectionTimeout: parseInt(process.env.REDIS_CONNECTION_TIMEOUT || '5000', 10),
        // Enable client-side caching for improved performance
        enableOfflineQueue: true,
        enableReadyCheck: true,
        maxRetriesPerRequest: 3,
        // Optimize connection pool for audio processing
        maxReconnectAttempts: 10,
        reconnectOnError: (err) => {
          const targetError = 'READONLY';
          if (err.message.includes(targetError)) {
            // Reconnect on failover-related errors
            return true;
          }
          return false;
        }
      }
    }))
  ],
  providers: [CacheService],
  exports: [CacheService]
})
export class CacheModule {}