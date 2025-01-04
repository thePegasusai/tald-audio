/**
 * Utility functions for formatting audio-related values, metrics, and timestamps
 * in the TALD UNIA web interface.
 * @version 1.0.0
 */

import { format } from 'date-fns';
import numeral from 'numeral';
import { memoize } from 'lodash';
import i18next from 'i18next';
import { createLogger } from 'winston';

import { AudioMetrics } from '../types/audio.types';
import { Profile } from '../types/profile.types';

// Constants for formatting configuration
const VALID_SAMPLE_RATES = [44100, 48000, 88200, 96000, 176400, 192000, 384000, 768000];
const FORMATTING_ERROR_INDICATOR = '--';
const DEFAULT_LOCALE = 'en-US';

// Configure logger for formatting errors
const logger = createLogger({
  level: 'warn',
  format: format.combine(
    format.timestamp(),
    format.json()
  ),
  transports: [
    // Add your transport configuration here
  ]
});

/**
 * Interface for formatted audio metrics
 */
interface FormattedAudioMetrics {
  thd: string;
  snr: string;
  rmsLevel: string;
  error?: string;
}

/**
 * Formats audio quality metrics for display with appropriate units and precision.
 * Includes error handling and memoization for performance.
 * 
 * @param metrics - AudioMetrics object containing raw values
 * @returns Formatted metrics object with string values or error indicators
 */
export const formatAudioMetrics = memoize((metrics: AudioMetrics): FormattedAudioMetrics => {
  try {
    // Validate input
    if (!metrics) {
      throw new Error('Invalid metrics object');
    }

    // Validate metric ranges
    if (metrics.thd < 0 || metrics.thd > 1 || 
        metrics.snr < 0 || metrics.snr > 200 ||
        metrics.rmsLevel < -120 || metrics.rmsLevel > 0) {
      throw new Error('Metrics values out of valid range');
    }

    return {
      // Format THD+N as percentage with 6 decimal places
      thd: `${numeral(metrics.thd * 100).format('0.000000')}%`,
      
      // Format SNR in dB with 1 decimal place
      snr: `${numeral(metrics.snr).format('0.0')} dB`,
      
      // Format RMS level in dB with 1 decimal place
      rmsLevel: `${numeral(metrics.rmsLevel).format('0.0')} dB`
    };
  } catch (error) {
    logger.warn('Error formatting audio metrics', {
      error: error.message,
      metrics
    });

    return {
      thd: FORMATTING_ERROR_INDICATOR,
      snr: FORMATTING_ERROR_INDICATOR,
      rmsLevel: FORMATTING_ERROR_INDICATOR,
      error: error.message
    };
  }
});

/**
 * Formats sample rate in kHz with appropriate suffix and locale support.
 * Includes input validation and error handling.
 * 
 * @param sampleRate - Sample rate in Hz
 * @param locale - Optional locale string for formatting
 * @returns Formatted sample rate string
 */
export const formatSampleRate = memoize((
  sampleRate: number,
  locale: string = DEFAULT_LOCALE
): string => {
  try {
    // Validate sample rate
    if (!VALID_SAMPLE_RATES.includes(sampleRate)) {
      throw new Error('Invalid sample rate');
    }

    // Convert to kHz and format with locale
    const kHz = sampleRate / 1000;
    const formatter = new Intl.NumberFormat(locale, {
      minimumFractionDigits: 0,
      maximumFractionDigits: 1
    });

    return `${formatter.format(kHz)} kHz`;
  } catch (error) {
    logger.warn('Error formatting sample rate', {
      error: error.message,
      sampleRate,
      locale
    });
    return FORMATTING_ERROR_INDICATOR;
  }
});

/**
 * Formats a timestamp with localization support.
 * 
 * @param timestamp - ISO timestamp string
 * @param locale - Optional locale string for formatting
 * @returns Formatted date/time string
 */
export const formatTimestamp = memoize((
  timestamp: string,
  locale: string = DEFAULT_LOCALE
): string => {
  try {
    const date = new Date(timestamp);
    if (isNaN(date.getTime())) {
      throw new Error('Invalid timestamp');
    }

    return format(date, 'PPpp', { locale });
  } catch (error) {
    logger.warn('Error formatting timestamp', {
      error: error.message,
      timestamp,
      locale
    });
    return FORMATTING_ERROR_INDICATOR;
  }
});

/**
 * Formats a decibel value with appropriate precision and unit.
 * 
 * @param db - Decibel value
 * @param precision - Number of decimal places (default: 1)
 * @returns Formatted decibel string
 */
export const formatDecibels = memoize((
  db: number,
  precision: number = 1
): string => {
  try {
    if (typeof db !== 'number' || isNaN(db)) {
      throw new Error('Invalid decibel value');
    }

    return `${numeral(db).format(`0.${'0'.repeat(precision)}`)} dB`;
  } catch (error) {
    logger.warn('Error formatting decibels', {
      error: error.message,
      db,
      precision
    });
    return FORMATTING_ERROR_INDICATOR;
  }
});

/**
 * Formats a frequency value in Hz or kHz as appropriate.
 * 
 * @param frequency - Frequency in Hz
 * @param locale - Optional locale string for formatting
 * @returns Formatted frequency string
 */
export const formatFrequency = memoize((
  frequency: number,
  locale: string = DEFAULT_LOCALE
): string => {
  try {
    if (frequency <= 0) {
      throw new Error('Invalid frequency value');
    }

    const formatter = new Intl.NumberFormat(locale, {
      minimumFractionDigits: 0,
      maximumFractionDigits: 2
    });

    if (frequency >= 1000) {
      return `${formatter.format(frequency / 1000)} kHz`;
    }
    return `${formatter.format(frequency)} Hz`;
  } catch (error) {
    logger.warn('Error formatting frequency', {
      error: error.message,
      frequency,
      locale
    });
    return FORMATTING_ERROR_INDICATOR;
  }
});

/**
 * Formats a percentage value with specified precision.
 * 
 * @param value - Decimal value (0-1)
 * @param precision - Number of decimal places
 * @returns Formatted percentage string
 */
export const formatPercentage = memoize((
  value: number,
  precision: number = 1
): string => {
  try {
    if (value < 0 || value > 1) {
      throw new Error('Percentage value out of range');
    }

    return `${numeral(value * 100).format(`0.${'0'.repeat(precision)}`)}%`;
  } catch (error) {
    logger.warn('Error formatting percentage', {
      error: error.message,
      value,
      precision
    });
    return FORMATTING_ERROR_INDICATOR;
  }
});

// Export all formatters
export {
  formatAudioMetrics,
  formatSampleRate,
  formatTimestamp,
  formatDecibels,
  formatFrequency,
  formatPercentage
};