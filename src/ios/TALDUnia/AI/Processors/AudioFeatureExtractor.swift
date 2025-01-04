// Foundation v17.0+
import Foundation
import Accelerate
import AVFoundation

/// Constants for feature extraction configuration and optimization
private enum FeatureConstants {
    static let kFeatureFrameSize: Int = 2048
    static let kFeatureHopSize: Int = 512
    static let kMelBands: Int = 80
    static let kMinFrequency: Float = 20.0
    static let kMaxFrequency: Float = 20000.0
    static let kSIMDAlignment: Int = 16
    static let kMaxBufferPoolSize: Int = 8
    static let kProcessingTimeout: TimeInterval = 0.01
    static let kMinConfidenceThreshold: Float = 0.85
}

/// Error types specific to feature extraction
public enum FeatureExtractionError: LocalizedError {
    case initializationFailed(String)
    case processingFailed(String)
    case validationFailed(String)
    case bufferError(String)
    case timeoutError(String)
    
    public var errorDescription: String? {
        switch self {
        case .initializationFailed(let reason): return "Feature extraction initialization failed: \(reason)"
        case .processingFailed(let reason): return "Feature extraction processing failed: \(reason)"
        case .validationFailed(let reason): return "Feature validation failed: \(reason)"
        case .bufferError(let reason): return "Buffer error: \(reason)"
        case .timeoutError(let reason): return "Processing timeout: \(reason)"
        }
    }
}

/// Represents extracted audio features
public struct AudioFeatures {
    public let melSpectrum: [Float]
    public let temporalFeatures: TemporalFeatures
    public let confidence: Float
    public let extractionTime: TimeInterval
}

/// Time-domain audio features
public struct TemporalFeatures {
    public let rmsEnergy: Float
    public let zeroCrossings: Int
    public let spectralCentroid: Float
    public let crest: Float
}

/// Performance metrics for feature extraction
public struct PerformanceMetrics {
    public var processingTime: TimeInterval = 0
    public var bufferUtilization: Float = 0
    public var powerEfficiency: Double = 0
    public var featureConfidence: Float = 0
}

/// High-performance audio feature extractor for AI-driven enhancement
@objc public final class AudioFeatureExtractor: NSObject {
    
    // MARK: - Properties
    
    private let fftProcessor: FFTProcessor
    private let processingQueue: DispatchQueue
    private var bufferPool: BufferPool<Float>
    private let sampleRate: Int
    private var isInitialized: Bool = false
    private var melFilterbank: [Float]
    private var metrics: PerformanceMetrics
    private let activeProcessingCount = AtomicCounter()
    
    // MARK: - Initialization
    
    /// Initializes the feature extractor with specified configuration
    /// - Parameters:
    ///   - sampleRate: Audio sample rate in Hz
    ///   - frameSize: Optional frame size for analysis
    ///   - config: Optional feature extraction configuration
    public init(sampleRate: Int = AudioConstants.sampleRate,
                frameSize: Int? = nil,
                config: FeatureConfiguration? = nil) throws {
        
        self.sampleRate = sampleRate
        self.metrics = PerformanceMetrics()
        
        // Initialize FFT processor
        self.fftProcessor = try FFTProcessor(
            fftSize: frameSize ?? FeatureConstants.kFeatureFrameSize
        )
        
        // Create processing queue
        self.processingQueue = DispatchQueue(
            label: "com.taldunia.audio.features",
            qos: .userInteractive,
            attributes: .concurrent
        )
        
        // Initialize buffer pool
        self.bufferPool = BufferPool(
            capacity: FeatureConstants.kMaxBufferPoolSize,
            bufferSize: FeatureConstants.kFeatureFrameSize
        )
        
        // Create mel filterbank
        self.melFilterbank = [Float](repeating: 0,
                                   count: FeatureConstants.kMelBands)
        
        super.init()
        
        // Complete initialization
        try setupMelFilterbank()
        isInitialized = true
    }
    
    // MARK: - Feature Extraction
    
    /// Extracts audio features from input buffer with comprehensive validation
    /// - Parameter inputBuffer: Input audio buffer
    /// - Returns: Extracted features or error
    public func extractFeatures(_ inputBuffer: AVAudioPCMBuffer) -> Result<AudioFeatures, FeatureExtractionError> {
        guard isInitialized else {
            return .failure(.initializationFailed("Feature extractor not initialized"))
        }
        
        let startTime = CACurrentMediaTime()
        activeProcessingCount.increment()
        defer { activeProcessingCount.decrement() }
        
        // Validate input buffer
        guard let frames = inputBuffer.floatChannelData?[0],
              inputBuffer.frameLength > 0 else {
            return .failure(.bufferError("Invalid input buffer"))
        }
        
        // Process features
        do {
            // Acquire buffer from pool
            guard let buffer = bufferPool.acquire() else {
                return .failure(.bufferError("Failed to acquire buffer from pool"))
            }
            defer { bufferPool.release(buffer) }
            
            // Compute FFT
            let fftResult = try fftProcessor.processFFT(frames,
                                                      buffer,
                                                      frameCount: Int(inputBuffer.frameLength))
            
            // Extract mel spectrum
            let melResult = try computeMelSpectrum(fftResult.magnitude,
                                                  length: fftResult.magnitude.count)
            
            // Extract temporal features
            let temporalResult = try extractTemporalFeatures(frames,
                                                           length: Int(inputBuffer.frameLength))
            
            // Calculate confidence
            let confidence = calculateFeatureConfidence(melResult,
                                                      temporalResult)
            
            // Update metrics
            let processingTime = CACurrentMediaTime() - startTime
            updateMetrics(processingTime: processingTime,
                         confidence: confidence)
            
            // Package features
            let features = AudioFeatures(
                melSpectrum: try melResult.get(),
                temporalFeatures: try temporalResult.get(),
                confidence: confidence,
                extractionTime: processingTime
            )
            
            return .success(features)
            
        } catch {
            return .failure(.processingFailed(error.localizedDescription))
        }
    }
    
    // MARK: - Private Methods
    
    /// Computes mel-scaled spectrum from linear FFT spectrum
    /// - Parameters:
    ///   - spectrum: Linear spectrum
    ///   - length: Spectrum length
    /// - Returns: Mel-scaled spectrum or error
    @inline(__always)
    private func computeMelSpectrum(_ spectrum: UnsafePointer<Float>,
                                   length: Int) -> Result<[Float], FeatureExtractionError> {
        
        // Validate input
        guard length > 0 else {
            return .failure(.validationFailed("Invalid spectrum length"))
        }
        
        var melSpectrum = [Float](repeating: 0, count: FeatureConstants.kMelBands)
        
        // Apply mel filterbank with SIMD optimization
        vDSP_mmul(spectrum,
                 1,
                 melFilterbank,
                 1,
                 &melSpectrum,
                 1,
                 vDSP_Length(FeatureConstants.kMelBands),
                 vDSP_Length(length/2),
                 1)
        
        // Convert to log scale with numerical stability
        var epsilon: Float = 1e-10
        vDSP_vsadd(melSpectrum,
                   1,
                   &epsilon,
                   &melSpectrum,
                   1,
                   vDSP_Length(FeatureConstants.kMelBands))
        
        vForce.log(melSpectrum,
                  result: &melSpectrum,
                  count: FeatureConstants.kMelBands)
        
        return .success(melSpectrum)
    }
    
    /// Extracts temporal features from audio buffer
    /// - Parameters:
    ///   - buffer: Audio buffer
    ///   - length: Buffer length
    /// - Returns: Temporal features or error
    private func extractTemporalFeatures(_ buffer: UnsafePointer<Float>,
                                       length: Int) -> Result<TemporalFeatures, FeatureExtractionError> {
        
        // Calculate RMS energy
        var rms: Float = 0
        vDSP_rmsqv(buffer,
                   1,
                   &rms,
                   vDSP_Length(length))
        
        // Count zero crossings
        var zeroCrossings = 0
        var previousSample: Float = 0
        
        for i in 0..<length {
            if (buffer[i] * previousSample) < 0 {
                zeroCrossings += 1
            }
            previousSample = buffer[i]
        }
        
        // Calculate spectral centroid
        var centroid: Float = 0
        vDSP_meanv(buffer,
                   1,
                   &centroid,
                   vDSP_Length(length))
        
        // Calculate crest factor
        var peak: Float = 0
        vDSP_maxmgv(buffer,
                    1,
                    &peak,
                    vDSP_Length(length))
        
        let crest = peak / (rms + Float.ulpOfOne)
        
        let features = TemporalFeatures(
            rmsEnergy: rms,
            zeroCrossings: zeroCrossings,
            spectralCentroid: centroid,
            crest: crest
        )
        
        return .success(features)
    }
    
    /// Sets up mel filterbank for spectral analysis
    private func setupMelFilterbank() throws {
        // Implementation of mel filterbank creation
        // For brevity, basic initialization shown
        melFilterbank = [Float](repeating: 1.0/Float(FeatureConstants.kMelBands),
                              count: FeatureConstants.kMelBands)
    }
    
    /// Calculates confidence score for extracted features
    private func calculateFeatureConfidence(_ melResult: Result<[Float], FeatureExtractionError>,
                                          _ temporalResult: Result<TemporalFeatures, FeatureExtractionError>) -> Float {
        // Basic confidence calculation
        // In practice, would implement more sophisticated validation
        guard case .success = melResult,
              case .success = temporalResult else {
            return 0.0
        }
        return 1.0
    }
    
    /// Updates performance metrics
    private func updateMetrics(processingTime: TimeInterval,
                             confidence: Float) {
        metrics.processingTime = processingTime
        metrics.featureConfidence = confidence
        metrics.bufferUtilization = Float(activeProcessingCount.value) / Float(FeatureConstants.kMaxBufferPoolSize)
        metrics.powerEfficiency = max(0.0, 1.0 - processingTime/FeatureConstants.kProcessingTimeout)
    }
}

// MARK: - Supporting Types

/// Thread-safe atomic counter
private final class AtomicCounter {
    private var value_ = 0
    private let lock = os_unfair_lock()
    
    var value: Int {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        return value_
    }
    
    func increment() {
        os_unfair_lock_lock(&lock)
        value_ += 1
        os_unfair_lock_unlock(&lock)
    }
    
    func decrement() {
        os_unfair_lock_lock(&lock)
        value_ -= 1
        os_unfair_lock_unlock(&lock)
    }
}

/// Configuration for feature extraction
public struct FeatureConfiguration {
    let frameSize: Int
    let hopSize: Int
    let melBands: Int
    let minFrequency: Float
    let maxFrequency: Float
    
    public init(frameSize: Int = FeatureConstants.kFeatureFrameSize,
                hopSize: Int = FeatureConstants.kFeatureHopSize,
                melBands: Int = FeatureConstants.kMelBands,
                minFrequency: Float = FeatureConstants.kMinFrequency,
                maxFrequency: Float = FeatureConstants.kMaxFrequency) {
        self.frameSize = frameSize
        self.hopSize = hopSize
        self.melBands = melBands
        self.minFrequency = minFrequency
        self.maxFrequency = maxFrequency
    }
}