import { Module } from '@nestjs/common'; // ^10.0.0
import { TerminusModule } from '@nestjs/terminus'; // ^10.0.1
import { HttpModule } from '@nestjs/axios'; // ^3.0.0
import { HealthController } from './health.controller';

/**
 * HealthModule configures comprehensive system monitoring capabilities for the TALD UNIA audio system
 * 
 * Provides health checks for:
 * - Audio processing metrics (THD+N, SNR, CPU usage, power efficiency)
 * - Infrastructure components (database, cache, message broker, storage)
 * - Memory utilization
 * - External service dependencies (AI service, audio processor)
 * 
 * Implements monitoring requirements from Technical Specifications section 2.4.1 and 8.5
 */
@Module({
  imports: [
    // Terminus provides core health check functionality
    TerminusModule,
    // HttpModule enables health checks of external services
    HttpModule.register({
      timeout: 5000,
      maxRedirects: 3,
    }),
  ],
  controllers: [HealthController],
  providers: [],
})
export class HealthModule {}