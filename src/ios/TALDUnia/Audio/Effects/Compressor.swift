// Foundation v17.0+
import AVFoundation
import Accelerate

/// High-performance dynamic range compressor with SIMD optimization and real-time quality monitoring
@objc public class Compressor: NSObject {
    
    // MARK: - Constants
    
    private let kDefaultThreshold: Float = -20.0
    private let kDefaultRatio: Float = 4.0
    private let kDefaultAttackTime: Float = 0.005
    private let kDefaultReleaseTime: Float = 0.050
    private let kDefaultKneeWidth: Float = 6.0
    private let kMinGainReduction: Float = -60.0
    private let kMaxTHDN: Float = 0.0005
    private let kMaxLatency: Float = 0.010
    private let kMinPowerEfficiency: Float = 0.90
    
    // MARK: - Properties
    
    /// Threshold level in dB where compression begins
    @objc public var threshold: Float {
        get { return _threshold.value }
        set { _threshold.value = newValue }
    }
    private let _threshold = Atomic<Float>(-20.0)
    
    /// Compression ratio (input:output)
    @objc public var ratio: Float {
        get { return _ratio.value }
        set { _ratio.value = max(1.0, newValue) }
    }
    private let _ratio = Atomic<Float>(4.0)
    
    /// Attack time in seconds
    @objc public var attackTime: Float {
        get { return _attackTime.value }
        set { _attackTime.value = max(0.0, min(newValue, kMaxLatency)) }
    }
    private let _attackTime = Atomic<Float>(0.005)
    
    /// Release time in seconds
    @objc public var releaseTime: Float {
        get { return _releaseTime.value }
        set { _releaseTime.value = max(0.0, newValue) }
    }
    private let _releaseTime = Atomic<Float>(0.050)
    
    /// Knee width in dB for smooth compression onset
    @objc public var kneeWidth: Float {
        get { return _kneeWidth.value }
        set { _kneeWidth.value = max(0.0, newValue) }
    }
    private let _kneeWidth = Atomic<Float>(6.0)
    
    /// Makeup gain in dB applied after compression
    @objc public var makeupGain: Float {
        get { return _makeupGain.value }
        set { _makeupGain.value = newValue }
    }
    private let _makeupGain = Atomic<Float>(0.0)
    
    /// Indicates if compression is enabled
    @objc public var isEnabled: Bool {
        get { return _isEnabled.value }
        set { _isEnabled.value = newValue }
    }
    private let _isEnabled = Atomic<Bool>(true)
    
    // MARK: - Private Properties
    
    private let dspProcessor: DSPProcessor
    private let inputBuffer: AudioBuffer
    private let outputBuffer: AudioBuffer
    private var currentGainReduction: Float = 0.0
    private var envelopeFollower: Float = 0.0
    private let performanceMonitor: PerformanceMonitor
    private let powerTracker: PowerEfficiencyTracker
    private let thdnAnalyzer: THDNAnalyzer
    
    // MARK: - Initialization
    
    /// Initialize compressor with specified parameters
    /// - Parameters:
    ///   - threshold: Compression threshold in dB
    ///   - ratio: Compression ratio
    ///   - attackTime: Attack time in seconds
    ///   - releaseTime: Release time in seconds
    ///   - kneeWidth: Knee width in dB
    public init(threshold: Float? = nil,
               ratio: Float? = nil,
               attackTime: Float? = nil,
               releaseTime: Float? = nil,
               kneeWidth: Float? = nil) throws {
        
        // Initialize DSP processor
        self.dspProcessor = try DSPProcessor(
            sampleRate: AudioConstants.sampleRate,
            bufferSize: AudioConstants.bufferSize,
            channelCount: AudioConstants.channelCount
        )
        
        // Initialize audio buffers
        self.inputBuffer = try AudioBuffer(
            format: AudioFormat(),
            bufferSize: AudioConstants.bufferSize,
            enableMonitoring: true
        )
        
        self.outputBuffer = try AudioBuffer(
            format: AudioFormat(),
            bufferSize: AudioConstants.bufferSize,
            enableMonitoring: true
        )
        
        // Initialize performance monitoring
        self.performanceMonitor = PerformanceMonitor()
        self.powerTracker = PowerEfficiencyTracker(targetEfficiency: kMinPowerEfficiency)
        self.thdnAnalyzer = THDNAnalyzer(maxTHDN: kMaxTHDN)
        
        super.init()
        
        // Set initial parameters
        self.threshold = threshold ?? kDefaultThreshold
        self.ratio = ratio ?? kDefaultRatio
        self.attackTime = attackTime ?? kDefaultAttackTime
        self.releaseTime = releaseTime ?? kDefaultReleaseTime
        self.kneeWidth = kneeWidth ?? kDefaultKneeWidth
    }
    
    // MARK: - Processing
    
    /// Process audio through compressor with SIMD optimization
    /// - Parameters:
    ///   - inputBuffer: Input audio buffer pointer
    ///   - outputBuffer: Output audio buffer pointer
    ///   - frameCount: Number of frames to process
    /// - Returns: Processing metrics or error
    public func process(_ inputBuffer: UnsafeMutablePointer<Float>,
                       _ outputBuffer: UnsafeMutablePointer<Float>,
                       frameCount: Int) -> Result<ProcessingMetrics, Error> {
        
        guard isEnabled else {
            // Pass through when disabled
            memcpy(outputBuffer, inputBuffer, frameCount * MemoryLayout<Float>.size)
            return .success(ProcessingMetrics())
        }
        
        performanceMonitor.startProcessing()
        
        do {
            // Process in SIMD-optimized chunks
            var offset = 0
            while offset < frameCount {
                let chunkSize = min(AudioConstants.bufferSize, frameCount - offset)
                
                // Calculate input level using vDSP
                var inputLevel: Float = 0
                vDSP_maxmgv(inputBuffer + offset, 1, &inputLevel, vDSP_Length(chunkSize))
                
                // Calculate gain reduction
                let gainReduction = try calculateGainReduction(
                    inputLevel: inputLevel,
                    currentTHDN: thdnAnalyzer.currentTHDN,
                    currentLatency: performanceMonitor.currentLatency
                ).get()
                
                // Apply envelope following
                let attackCoeff = Float(exp(-1.0 / (Float(AudioConstants.sampleRate) * attackTime)))
                let releaseCoeff = Float(exp(-1.0 / (Float(AudioConstants.sampleRate) * releaseTime)))
                
                if gainReduction < envelopeFollower {
                    envelopeFollower = attackCoeff * (envelopeFollower - gainReduction) + gainReduction
                } else {
                    envelopeFollower = releaseCoeff * (envelopeFollower - gainReduction) + gainReduction
                }
                
                // Apply gain reduction and makeup gain using vDSP
                var gainFactors = [Float](repeating: pow(10, (envelopeFollower + makeupGain) / 20), count: chunkSize)
                vDSP_vmul(inputBuffer + offset, 1, &gainFactors, 1, outputBuffer + offset, 1, vDSP_Length(chunkSize))
                
                offset += chunkSize
            }
            
            // Update performance metrics
            let metrics = ProcessingMetrics(
                latency: performanceMonitor.currentLatency,
                thdnLevel: thdnAnalyzer.currentTHDN,
                powerEfficiency: powerTracker.currentEfficiency,
                gainReduction: envelopeFollower
            )
            
            performanceMonitor.endProcessing()
            return .success(metrics)
            
        } catch {
            return .failure(error)
        }
    }
    
    /// Reset compressor state
    public func reset() -> Result<Void, Error> {
        currentGainReduction = 0.0
        envelopeFollower = 0.0
        performanceMonitor.reset()
        powerTracker.reset()
        thdnAnalyzer.reset()
        return .success(())
    }
    
    // MARK: - Private Methods
    
    /// Calculate gain reduction with quality monitoring
    @inline(__always)
    private func calculateGainReduction(inputLevel: Float,
                                      currentTHDN: Float,
                                      currentLatency: TimeInterval) -> Result<Float, Error> {
        // Validate quality metrics
        guard currentTHDN <= kMaxTHDN else {
            return .failure(AppError.audioError(
                reason: "THD+N exceeds maximum threshold",
                severity: .error,
                context: ErrorContext(additionalInfo: [
                    "currentTHDN": currentTHDN,
                    "maxTHDN": kMaxTHDN
                ])
            ))
        }
        
        guard currentLatency <= TimeInterval(kMaxLatency) else {
            return .failure(AppError.audioError(
                reason: "Processing latency exceeds maximum",
                severity: .error,
                context: ErrorContext(additionalInfo: [
                    "currentLatency": currentLatency,
                    "maxLatency": kMaxLatency
                ])
            ))
        }
        
        // Calculate level above threshold
        let levelAboveThreshold = inputLevel - threshold
        
        // Apply knee smoothing
        var gainReduction: Float = 0.0
        if levelAboveThreshold < -kneeWidth/2 {
            gainReduction = 0.0
        } else if levelAboveThreshold > kneeWidth/2 {
            gainReduction = (levelAboveThreshold - threshold) * (ratio - 1) / ratio
        } else {
            let kneeScale = (levelAboveThreshold + kneeWidth/2) / kneeWidth
            gainReduction = levelAboveThreshold * kneeScale * (ratio - 1) / ratio
        }
        
        // Apply gain reduction limits
        gainReduction = max(gainReduction, kMinGainReduction)
        
        return .success(-gainReduction)
    }
}

// MARK: - Supporting Types

private struct ProcessingMetrics {
    let latency: TimeInterval
    let thdnLevel: Float
    let powerEfficiency: Float
    let gainReduction: Float
}

private class Atomic<T> {
    private let queue = DispatchQueue(
        label: "com.taldunia.audio.atomic",
        qos: .userInteractive
    )
    private var _value: T
    
    init(_ value: T) {
        self._value = value
    }
    
    var value: T {
        get { return queue.sync { _value } }
        set { queue.sync { _value = newValue } }
    }
}