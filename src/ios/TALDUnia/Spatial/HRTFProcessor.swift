// Foundation v17.0+
import AVFoundation
import Accelerate
import simd

/// High-performance HRTF processor optimized for ESS ES9038PRO DAC integration
@objc public class HRTFProcessor: NSObject {
    
    // MARK: - Constants
    
    private enum Constants {
        static let kDefaultSampleRate: Double = 48000
        static let kDefaultHRTFResolution: Float = 5.0
        static let kMaxProcessingLatency: TimeInterval = 0.010
        static let kHRTFCacheSize: Int = 1024
        static let kMinProcessingResolution: Float = 2.0
        static let kMaxProcessingResolution: Float = 10.0
    }
    
    // MARK: - Types
    
    /// Quality level for HRTF processing
    @objc public enum ProcessingQuality: Int {
        case maximum = 0
        case balanced = 1
        case powerEfficient = 2
    }
    
    /// Key for HRTF coefficient cache
    private struct HRTFKey: Hashable {
        let azimuth: Float
        let elevation: Float
        let distance: Float
    }
    
    // MARK: - Properties
    
    /// Audio format configuration
    private let audioFormat: AVAudioFormat
    
    /// Current listener position in 3D space
    @objc public private(set) var listenerPosition: simd_float3
    
    /// Current listener orientation
    @objc public private(set) var listenerOrientation: simd_float3
    
    /// HRTF database containing impulse responses
    private let hrtfDatabase: HRTFDatabase
    
    /// High-priority queue for audio processing
    private let processingQueue: DispatchQueue
    
    /// Cache for frequently used HRTF coefficients
    private var coefficientCache: LRUCache<HRTFKey, HRTFCoefficients>
    
    /// Room acoustics simulator
    private let roomSimulator: RoomSimulator
    
    /// Performance monitoring
    private let performanceMonitor: PerformanceMonitor
    
    /// Current processing quality setting
    @objc public private(set) var processingQuality: ProcessingQuality
    
    // MARK: - Initialization
    
    /// Initializes the HRTF processor with optimized configuration
    /// - Parameters:
    ///   - format: Audio format configuration
    ///   - roomParams: Room acoustics parameters
    ///   - quality: Processing quality setting
    @objc public init(format: AVAudioFormat,
                     roomParams: RoomParameters = RoomParameters(),
                     quality: ProcessingQuality = .balanced) throws {
        
        self.audioFormat = format
        self.listenerPosition = simd_float3(0, 0, 0)
        self.listenerOrientation = simd_float3(0, 0, 1)
        self.processingQuality = quality
        
        // Initialize high-priority processing queue
        self.processingQueue = DispatchQueue(
            label: "com.taldunia.spatial.hrtf",
            qos: .userInteractive,
            attributes: []
        )
        
        // Initialize HRTF database
        do {
            self.hrtfDatabase = try HRTFDatabase()
        } catch {
            throw AppError.hrtfLoadingFailed(
                reason: "Failed to initialize HRTF database",
                context: ErrorContext(additionalInfo: ["error": error])
            )
        }
        
        // Initialize coefficient cache
        self.coefficientCache = LRUCache<HRTFKey, HRTFCoefficients>(
            capacity: Constants.kHRTFCacheSize
        )
        
        // Initialize room simulator with default parameters
        self.roomSimulator = RoomSimulator(
            size: SpatialConstants.defaultRoomSize,
            reverbTime: SpatialConstants.defaultReverbTime
        )
        
        // Initialize performance monitoring
        self.performanceMonitor = PerformanceMonitor()
        
        super.init()
        
        // Validate hardware capabilities
        try validateHardwareCapabilities()
    }
    
    // MARK: - Public Methods
    
    /// Processes audio buffer with HRTF spatialization
    /// - Parameter inputBuffer: Input audio buffer to process
    /// - Returns: Processed audio buffer with spatial effects
    @objc public func processAudio(_ inputBuffer: AudioBuffer) -> Result<AudioBuffer, Error> {
        let startTime = CACurrentMediaTime()
        
        return processingQueue.sync {
            do {
                // Check processing load and adjust quality if needed
                let currentLoad = performanceMonitor.currentCPULoad
                adjustProcessingQuality(for: currentLoad)
                
                // Calculate current HRTF coefficients
                let coefficients = try calculateHRTF(
                    azimuth: calculateAzimuth(),
                    elevation: calculateElevation(),
                    distance: calculateDistance()
                )
                
                // Apply HRTF filtering
                let processedBuffer = try applyHRTFFiltering(
                    inputBuffer: inputBuffer,
                    coefficients: coefficients
                )
                
                // Apply room acoustics
                let spatializedBuffer = try roomSimulator.process(processedBuffer)
                
                // Update performance metrics
                let processingTime = CACurrentMediaTime() - startTime
                performanceMonitor.updateMetrics(processingTime: processingTime)
                
                return .success(spatializedBuffer)
            } catch {
                return .failure(AppError.spatialProcessingFailed(
                    reason: "HRTF processing failed",
                    context: ErrorContext(additionalInfo: ["error": error])
                ))
            }
        }
    }
    
    /// Updates listener position and orientation
    /// - Parameters:
    ///   - position: New listener position
    ///   - orientation: New listener orientation
    ///   - timestamp: Update timestamp for motion prediction
    @objc public func updateListenerPosition(_ position: simd_float3,
                                           orientation: simd_float3,
                                           timestamp: Double) {
        processingQueue.async {
            // Apply motion prediction
            let predictedPosition = self.predictPosition(
                position,
                timestamp: timestamp
            )
            
            // Update position and orientation
            self.listenerPosition = predictedPosition
            self.listenerOrientation = normalize(orientation)
            
            // Update room simulation parameters
            self.roomSimulator.updateListenerPosition(predictedPosition)
            
            // Clear cached coefficients that are no longer relevant
            self.cleanupCache()
        }
    }
    
    // MARK: - Private Methods
    
    /// Calculates HRTF coefficients for given position
    private func calculateHRTF(azimuth: Float,
                             elevation: Float,
                             distance: Float) throws -> HRTFCoefficients {
        // Check cache first
        let key = HRTFKey(
            azimuth: azimuth,
            elevation: elevation,
            distance: distance
        )
        
        if let cached = coefficientCache.get(key) {
            return cached
        }
        
        // Calculate new coefficients using cubic spline interpolation
        let coefficients = try hrtfDatabase.interpolateCoefficients(
            azimuth: azimuth,
            elevation: elevation,
            distance: distance,
            quality: processingQuality
        )
        
        // Cache the result
        coefficientCache.set(key, value: coefficients)
        
        return coefficients
    }
    
    /// Applies HRTF filtering to audio buffer
    private func applyHRTFFiltering(inputBuffer: AudioBuffer,
                                  coefficients: HRTFCoefficients) throws -> AudioBuffer {
        guard let input = inputBuffer.pcmBuffer else {
            throw AppError.audioError(
                reason: "Invalid input buffer",
                severity: .error,
                context: ErrorContext()
            )
        }
        
        // Create output buffer
        let outputBuffer = AudioBuffer(
            format: audioFormat,
            bufferSize: input.frameLength
        )
        
        // Apply HRTF convolution using vDSP
        vDSP_conv(
            input.floatChannelData?[0] ?? [],
            1,
            coefficients.leftEar,
            1,
            outputBuffer.pcmBuffer?.floatChannelData?[0] ?? [],
            1,
            vDSP_Length(input.frameLength),
            vDSP_Length(coefficients.length)
        )
        
        vDSP_conv(
            input.floatChannelData?[0] ?? [],
            1,
            coefficients.rightEar,
            1,
            outputBuffer.pcmBuffer?.floatChannelData?[1] ?? [],
            1,
            vDSP_Length(input.frameLength),
            vDSP_Length(coefficients.length)
        )
        
        return outputBuffer
    }
    
    /// Validates hardware capabilities for HRTF processing
    private func validateHardwareCapabilities() throws {
        // Verify sample rate
        guard audioFormat.sampleRate <= Constants.kDefaultSampleRate else {
            throw AppError.hardwareError(
                reason: "Sample rate exceeds HRTF processing capabilities",
                severity: .error,
                context: ErrorContext(additionalInfo: [
                    "currentRate": audioFormat.sampleRate,
                    "maxRate": Constants.kDefaultSampleRate
                ])
            )
        }
        
        // Verify processing latency
        let estimatedLatency = performanceMonitor.estimateProcessingLatency()
        guard estimatedLatency <= Constants.kMaxProcessingLatency else {
            throw AppError.hardwareError(
                reason: "Processing latency exceeds requirements",
                severity: .error,
                context: ErrorContext(additionalInfo: [
                    "estimatedLatency": estimatedLatency,
                    "maxLatency": Constants.kMaxProcessingLatency
                ])
            )
        }
    }
    
    /// Adjusts processing quality based on CPU load
    private func adjustProcessingQuality(for cpuLoad: Double) {
        if cpuLoad > 0.8 && processingQuality != .powerEfficient {
            processingQuality = .powerEfficient
        } else if cpuLoad < 0.4 && processingQuality != .maximum {
            processingQuality = .maximum
        }
    }
    
    /// Predicts future position based on current motion
    private func predictPosition(_ position: simd_float3,
                               timestamp: Double) -> simd_float3 {
        // Implement motion prediction algorithm
        // For now, return current position
        return position
    }
    
    /// Removes outdated entries from coefficient cache
    private func cleanupCache() {
        coefficientCache.removeAll { key, _ in
            let distance = simd_distance(
                simd_float3(key.azimuth, key.elevation, key.distance),
                listenerPosition
            )
            return distance > 10.0 // Clear coefficients for distances > 10m
        }
    }
    
    /// Calculates current azimuth angle
    private func calculateAzimuth() -> Float {
        // Calculate azimuth based on listener position and orientation
        return atan2(listenerOrientation.x, listenerOrientation.z)
    }
    
    /// Calculates current elevation angle
    private func calculateElevation() -> Float {
        // Calculate elevation based on listener position and orientation
        let length = simd_length(listenerOrientation)
        return asin(listenerOrientation.y / length)
    }
    
    /// Calculates current distance
    private func calculateDistance() -> Float {
        return simd_length(listenerPosition)
    }
}