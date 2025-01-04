import { Injectable, Logger } from '@nestjs/common'; // ^10.0.0
import { ConfigService } from '@nestjs/config'; // ^10.0.0
import Redis from 'ioredis'; // ^5.3.0
import { RedisConfig } from '../config/configuration';

// Cache configuration constants
const DEFAULT_TTL = 3600; // 1 hour default TTL
const AUDIO_CACHE_PREFIX = 'audio:';
const PROFILE_CACHE_PREFIX = 'profile:';
const MODEL_CACHE_PREFIX = 'model:';
const MAX_RETRY_ATTEMPTS = 3;
const CIRCUIT_BREAKER_THRESHOLD = 5;
const BUFFER_CHUNK_SIZE = 16384; // 16KB chunks for audio buffers
const MONITORING_INTERVAL = 5000; // 5 seconds

// Cache metrics interface for monitoring
interface CacheMetrics {
  hits: number;
  misses: number;
  errors: number;
  latency: number[];
  memoryUsage: number;
  lastError?: Error;
}

// Circuit breaker for fault tolerance
interface CircuitBreaker {
  failures: number;
  lastFailure: Date;
  state: 'CLOSED' | 'OPEN' | 'HALF_OPEN';
}

@Injectable()
export class CacheService {
  private readonly redisClient: Redis;
  private readonly logger: Logger;
  private readonly metrics: CacheMetrics;
  private readonly circuitBreaker: CircuitBreaker;

  constructor(private readonly configService: ConfigService) {
    this.logger = new Logger('CacheService');
    this.metrics = {
      hits: 0,
      misses: 0,
      errors: 0,
      latency: [],
      memoryUsage: 0
    };

    this.circuitBreaker = {
      failures: 0,
      lastFailure: new Date(),
      state: 'CLOSED'
    };

    // Initialize Redis client with configuration
    const redisConfig = this.configService.get<RedisConfig>('redis');
    this.redisClient = new Redis({
      host: redisConfig.host,
      port: redisConfig.port,
      password: redisConfig.password,
      db: redisConfig.db,
      keyPrefix: redisConfig.keyPrefix,
      connectTimeout: redisConfig.connectionTimeout,
      retryStrategy: (times: number) => {
        if (times > MAX_RETRY_ATTEMPTS) {
          this.handleConnectionFailure();
          return null;
        }
        return Math.min(times * 100, 3000);
      },
      enableReadyCheck: true,
      maxRetriesPerRequest: 3,
      lazyConnect: false
    });

    // Set up Redis event handlers
    this.setupRedisEventHandlers();
    
    // Initialize monitoring
    this.startMonitoring();
  }

  /**
   * Stores audio buffer in Redis with optimized chunking
   * @param key Cache key for the audio buffer
   * @param buffer Float32Array audio data
   */
  async setAudioBuffer(key: string, buffer: Float32Array): Promise<void> {
    try {
      const startTime = Date.now();
      const fullKey = `${AUDIO_CACHE_PREFIX}${key}`;

      // Convert Float32Array to Buffer for efficient storage
      const rawBuffer = Buffer.from(buffer.buffer);
      
      // Split into chunks for better memory management
      const chunks = Math.ceil(rawBuffer.length / BUFFER_CHUNK_SIZE);
      const pipeline = this.redisClient.pipeline();

      // Store metadata
      pipeline.hset(`${fullKey}:meta`, {
        size: buffer.length,
        chunks,
        format: 'float32',
        timestamp: Date.now()
      });

      // Store chunks
      for (let i = 0; i < chunks; i++) {
        const chunk = rawBuffer.slice(
          i * BUFFER_CHUNK_SIZE,
          (i + 1) * BUFFER_CHUNK_SIZE
        );
        pipeline.setex(
          `${fullKey}:chunk:${i}`,
          DEFAULT_TTL,
          chunk
        );
      }

      await pipeline.exec();
      
      // Update metrics
      this.updateLatencyMetric(Date.now() - startTime);
      
    } catch (error) {
      this.handleError('setAudioBuffer', error);
      throw error;
    }
  }

  /**
   * Retrieves and reconstructs audio buffer from Redis
   * @param key Cache key for the audio buffer
   * @returns Reconstructed Float32Array
   */
  async getAudioBuffer(key: string): Promise<Float32Array> {
    try {
      if (this.isCircuitBreakerOpen()) {
        throw new Error('Circuit breaker is open');
      }

      const startTime = Date.now();
      const fullKey = `${AUDIO_CACHE_PREFIX}${key}`;

      // Get metadata
      const meta = await this.redisClient.hgetall(`${fullKey}:meta`);
      if (!meta || !meta.size) {
        this.metrics.misses++;
        return null;
      }

      // Retrieve all chunks
      const pipeline = this.redisClient.pipeline();
      for (let i = 0; i < parseInt(meta.chunks); i++) {
        pipeline.get(`${fullKey}:chunk:${i}`);
      }

      const results = await pipeline.exec();
      if (!results) {
        this.metrics.misses++;
        return null;
      }

      // Reconstruct buffer
      const chunks = results.map(([err, chunk]) => {
        if (err) throw err;
        return chunk;
      });

      const combinedBuffer = Buffer.concat(chunks);
      const float32Array = new Float32Array(
        combinedBuffer.buffer,
        combinedBuffer.byteOffset,
        combinedBuffer.byteLength / Float32Array.BYTES_PER_ELEMENT
      );

      // Update metrics
      this.metrics.hits++;
      this.updateLatencyMetric(Date.now() - startTime);

      return float32Array;

    } catch (error) {
      this.handleError('getAudioBuffer', error);
      throw error;
    }
  }

  private setupRedisEventHandlers(): void {
    this.redisClient.on('error', (error) => {
      this.logger.error('Redis client error:', error);
      this.metrics.errors++;
      this.metrics.lastError = error;
    });

    this.redisClient.on('connect', () => {
      this.logger.log('Connected to Redis');
      this.resetCircuitBreaker();
    });

    this.redisClient.on('ready', () => {
      this.logger.log('Redis client ready');
    });
  }

  private startMonitoring(): void {
    setInterval(async () => {
      try {
        const info = await this.redisClient.info('memory');
        const memoryMatch = info.match(/used_memory:(\d+)/);
        if (memoryMatch) {
          this.metrics.memoryUsage = parseInt(memoryMatch[1]);
        }

        // Log metrics
        this.logger.debug('Cache metrics:', {
          hits: this.metrics.hits,
          misses: this.metrics.misses,
          errors: this.metrics.errors,
          avgLatency: this.calculateAverageLatency(),
          memoryUsage: this.metrics.memoryUsage
        });
      } catch (error) {
        this.logger.error('Monitoring error:', error);
      }
    }, MONITORING_INTERVAL);
  }

  private handleError(operation: string, error: Error): void {
    this.metrics.errors++;
    this.metrics.lastError = error;
    this.circuitBreaker.failures++;
    this.circuitBreaker.lastFailure = new Date();
    
    if (this.circuitBreaker.failures >= CIRCUIT_BREAKER_THRESHOLD) {
      this.circuitBreaker.state = 'OPEN';
      this.logger.error(`Circuit breaker opened after ${this.circuitBreaker.failures} failures`);
    }

    this.logger.error(`Cache operation ${operation} failed:`, error);
  }

  private handleConnectionFailure(): void {
    this.logger.error('Redis connection failed after maximum retries');
    this.circuitBreaker.state = 'OPEN';
  }

  private resetCircuitBreaker(): void {
    this.circuitBreaker.failures = 0;
    this.circuitBreaker.state = 'CLOSED';
  }

  private isCircuitBreakerOpen(): boolean {
    if (this.circuitBreaker.state === 'OPEN') {
      const now = new Date();
      const timeSinceLastFailure = now.getTime() - this.circuitBreaker.lastFailure.getTime();
      
      if (timeSinceLastFailure > 30000) { // 30 seconds cool-down
        this.circuitBreaker.state = 'HALF_OPEN';
        return false;
      }
      return true;
    }
    return false;
  }

  private updateLatencyMetric(latency: number): void {
    this.metrics.latency.push(latency);
    if (this.metrics.latency.length > 100) {
      this.metrics.latency.shift();
    }
  }

  private calculateAverageLatency(): number {
    if (this.metrics.latency.length === 0) return 0;
    const sum = this.metrics.latency.reduce((a, b) => a + b, 0);
    return sum / this.metrics.latency.length;
  }
}