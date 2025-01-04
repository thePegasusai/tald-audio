/**
 * TALD UNIA Audio System - HRTF Interface Definitions
 * Version: 1.0.0
 * 
 * Defines comprehensive TypeScript interfaces for Head-Related Transfer Function (HRTF)
 * data structures and spatial audio processing. Supports high-precision 3D audio rendering
 * with multiple interpolation methods and extensive dataset management.
 */

/**
 * Defines the structure of HRTF impulse response data with high-precision audio samples.
 * Supports multiple standard sample rates and variable-length impulse responses.
 */
export interface HRTFData {
    /**
     * Sampling rate of the HRTF measurements in Hz.
     * Supported values: 44100, 48000, 96000, 192000
     */
    sampleRate: number;

    /**
     * Left ear impulse response data with 32-bit floating-point precision.
     * Values normalized between -1.0 and 1.0
     */
    leftImpulseResponse: Float32Array;

    /**
     * Right ear impulse response data with 32-bit floating-point precision.
     * Values normalized between -1.0 and 1.0
     */
    rightImpulseResponse: Float32Array;

    /**
     * Length of the impulse response in samples.
     * Typical ranges: 512-2048 samples for optimal performance
     */
    length: number;
}

/**
 * Defines precise spatial position coordinates with validation for angle ranges.
 * Uses standard spherical coordinate system with right-hand rule.
 */
export interface HRTFPosition {
    /**
     * Horizontal angle in degrees from front center.
     * Range: -180 (left) to +180 (right)
     */
    azimuth: number;

    /**
     * Vertical angle in degrees from horizontal plane.
     * Range: -90 (down) to +90 (up)
     */
    elevation: number;

    /**
     * Distance from listener in meters.
     * Must be positive, typical range: 0.1 to 10.0
     */
    distance: number;
}

/**
 * Defines a complete HRTF measurement dataset with comprehensive metadata.
 * Supports multiple measurement positions and dataset versioning.
 */
export interface HRTFDataset {
    /**
     * Unique identifier name of the HRTF dataset.
     * Format: [source]_[subject]_[version]
     */
    name: string;

    /**
     * Detailed description including measurement conditions,
     * equipment specifications, and methodology details.
     */
    description: string;

    /**
     * Sample rate of all measurements in the dataset.
     * Must match system audio configuration.
     */
    sampleRate: number;

    /**
     * Map of HRTF measurements indexed by position.
     * Key format: "${azimuth}_${elevation}_${distance}"
     */
    measurements: Map<string, HRTFData>;
}

/**
 * Defines supported HRTF interpolation methods for optimal spatial rendering.
 * Methods offer different quality/performance tradeoffs.
 */
export enum HRTFInterpolationMethod {
    /**
     * Nearest neighbor interpolation - fastest, lowest quality
     */
    NEAREST = 'NEAREST',

    /**
     * Bilinear interpolation - balanced performance/quality
     */
    BILINEAR = 'BILINEAR',

    /**
     * Spherical harmonic interpolation - highest quality, most computationally intensive
     */
    SPHERICAL_HARMONIC = 'SPHERICAL_HARMONIC'
}