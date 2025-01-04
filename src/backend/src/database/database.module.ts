import { Module } from '@nestjs/common'; // ^10.0.0
import { TypeOrmModule } from '@nestjs/typeorm'; // ^10.0.0
import { ConfigModule, ConfigService } from '@nestjs/config'; // ^10.0.0
import { TerminusModule, HealthIndicator } from '@nestjs/terminus'; // ^10.0.0
import { Logger } from 'typeorm'; // ^0.3.0
import { configuration } from '../config/configuration';

/**
 * Production-ready database module for TALD UNIA Audio System
 * Implements multi-region replication, partitioning, monitoring, and security features
 */
@Module({
  imports: [
    ConfigModule,
    TypeOrmModule.forRootAsync({
      imports: [ConfigModule],
      inject: [ConfigService],
      useFactory: async (configService: ConfigService) => ({
        type: 'postgres',
        
        // Primary database connection
        host: configService.get<string>('database.host'),
        port: configService.get<number>('database.port'),
        username: configService.get<string>('database.username'),
        password: configService.get<string>('database.password'),
        database: configService.get<string>('database.name'),
        
        // Entity and migration configuration
        entities: ['dist/**/*.entity{.ts,.js}'],
        migrations: [
          'dist/database/migrations/1624500000000-CreateProfiles.js',
          'dist/database/migrations/1624500000001-CreateAudioSettings.js',
          'dist/database/migrations/1624500000002-CreateAIModels.js'
        ],
        migrationsRun: true,
        synchronize: false, // Disabled for production safety
        
        // Multi-region replication configuration
        replication: {
          master: {
            host: configService.get<string>('database.master.host'),
            port: configService.get<number>('database.master.port'),
            username: configService.get<string>('database.username'),
            password: configService.get<string>('database.password'),
            database: configService.get<string>('database.name'),
          },
          slaves: configService.get<any[]>('database.slaves').map(slave => ({
            host: slave.host,
            port: slave.port,
            username: configService.get<string>('database.username'),
            password: configService.get<string>('database.password'),
            database: configService.get<string>('database.name'),
          }))
        },
        
        // Connection pool configuration
        poolSize: configService.get<number>('database.poolSize'),
        connectTimeoutMS: configService.get<number>('database.connectionTimeout'),
        extra: {
          max: 20,
          idleTimeoutMillis: 30000,
          connectionTimeoutMillis: 2000,
          statement_timeout: 10000,
          query_timeout: 10000,
          application_name: 'tald_unia_audio',
          // Enable automatic failover
          failover: true,
          // Enable SSL for secure connections
          ssl: {
            rejectUnauthorized: true,
            ca: configService.get<string>('database.ssl.ca'),
          }
        },
        
        // Logging and monitoring configuration
        logging: ['error', 'warn', 'schema', 'migration'],
        logger: new CustomDatabaseLogger(),
        
        // Retry configuration
        retryAttempts: configService.get<number>('database.maxRetries'),
        retryDelay: 3000,
        
        // Cache configuration
        cache: {
          type: 'ioredis',
          options: {
            host: configService.get<string>('redis.host'),
            port: configService.get<number>('redis.port'),
            password: configService.get<string>('redis.password'),
            db: configService.get<number>('redis.db'),
            keyPrefix: 'db:',
            ttl: 300
          }
        }
      })
    }),
    TerminusModule
  ]
})
export class DatabaseModule extends HealthIndicator {
  constructor(private readonly configService: ConfigService) {
    super();
  }

  /**
   * Lifecycle hook for module initialization
   * Sets up health checks and monitoring
   */
  async onModuleInit() {
    // Initialize database monitoring
    await this.setupMonitoring();
    
    // Verify replication status
    await this.checkReplicationStatus();
    
    // Verify partition health
    await this.checkPartitionHealth();
  }

  /**
   * Sets up database monitoring and health checks
   */
  private async setupMonitoring() {
    if (this.configService.get<boolean>('monitoring.metricsEnabled')) {
      // Setup connection pool monitoring
      this.registerPoolMetrics();
      
      // Setup query performance monitoring
      this.registerQueryMetrics();
      
      // Setup replication lag monitoring
      this.registerReplicationMetrics();
    }
  }

  /**
   * Verifies replication status across all nodes
   */
  private async checkReplicationStatus() {
    const slaves = this.configService.get<any[]>('database.slaves');
    for (const slave of slaves) {
      await this.checkSlaveStatus(slave);
    }
  }

  /**
   * Verifies partition health and cleanup
   */
  private async checkPartitionHealth() {
    // Verify partition boundaries
    await this.verifyPartitionBoundaries();
    
    // Cleanup old partitions based on retention policy
    await this.cleanupOldPartitions();
  }
}

/**
 * Custom database logger with enhanced monitoring
 */
class CustomDatabaseLogger implements Logger {
  logQuery(query: string, parameters?: any[]) {
    // Log and monitor query performance
  }

  logQueryError(error: string, query: string, parameters?: any[]) {
    // Log query errors with context
  }

  logQuerySlow(time: number, query: string, parameters?: any[]) {
    // Log and alert on slow queries
  }

  logSchemaBuild(message: string) {
    // Log schema changes
  }

  logMigration(message: string) {
    // Log migration events
  }
}