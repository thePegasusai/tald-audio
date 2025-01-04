// CoreMotion v4.0+, simd v2.0+
import CoreMotion
import simd
import Foundation

/// Constants for head tracking configuration
private let kDefaultUpdateInterval: TimeInterval = 1.0 / 60.0  // 60Hz update rate
private let kMaxHeadRotationSpeed = Float.pi / 2.0  // Maximum rotation speed in radians/sec
private let kSmoothingFactor: Float = 0.85  // Default smoothing factor for motion
private let kCalibrationTimeout: TimeInterval = 5.0  // Calibration timeout in seconds

/// Converts quaternion rotation to Euler angles with enhanced gimbal lock handling
private func quaternionToEuler(_ quaternion: simd_quatf) -> SIMD3<Float> {
    // Normalize quaternion to ensure valid conversion
    let q = simd_normalize(quaternion)
    
    // Extract quaternion components
    let (x, y, z, w) = (q.imag.x, q.imag.y, q.imag.z, q.real)
    
    // Calculate Euler angles with gimbal lock protection
    var euler = SIMD3<Float>(0, 0, 0)
    
    // Yaw (y-axis rotation)
    euler.y = atan2(2.0 * (w * y + x * z), 1.0 - 2.0 * (y * y + x * x))
    
    // Pitch (x-axis rotation)
    let sinp = 2.0 * (w * x - z * y)
    if abs(sinp) >= 1 {
        euler.x = copysign(.pi / 2.0, sinp) // Handle gimbal lock
    } else {
        euler.x = asin(sinp)
    }
    
    // Roll (z-axis rotation)
    euler.z = atan2(2.0 * (w * z + y * x), 1.0 - 2.0 * (z * z + x * x))
    
    return euler
}

/// Advanced head tracking manager for spatial audio processing
public final class HeadTracker {
    // MARK: - Properties
    
    private let motionManager: CMMotionManager
    private let motionQueue: OperationQueue
    private var currentOrientation = SIMD3<Float>(0, 0, 0)
    private var previousOrientation = SIMD3<Float>(0, 0, 0)
    private var calibrationOffset = simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0))
    private let orientationLock = NSLock()
    
    public private(set) var isTracking = false
    public private(set) var isCalibrated = false
    
    private let updateInterval: TimeInterval
    private let smoothingFactor: Float
    
    // MARK: - Initialization
    
    /// Initializes the head tracker with configurable parameters
    public init(
        updateInterval: TimeInterval = kDefaultUpdateInterval,
        smoothingFactor: Float = kSmoothingFactor
    ) {
        self.updateInterval = updateInterval
        self.smoothingFactor = smoothingFactor
        
        // Initialize motion manager with optimal settings
        motionManager = CMMotionManager()
        motionManager.deviceMotionUpdateInterval = updateInterval
        
        // Create dedicated high-priority queue for motion processing
        motionQueue = OperationQueue()
        motionQueue.name = "com.taldunia.headtracker"
        motionQueue.maxConcurrentOperationCount = 1
        motionQueue.qualityOfService = .userInteractive
        
        Logger.shared.log("Head tracker initialized", subsystem: .spatial)
    }
    
    deinit {
        stopTracking()
    }
    
    // MARK: - Public Methods
    
    /// Starts head tracking with device capability verification
    public func startTracking() -> Result<Void, Error> {
        orientationLock.lock()
        defer { orientationLock.unlock() }
        
        guard !isTracking else {
            return .success(())
        }
        
        // Verify device motion capabilities
        guard motionManager.isDeviceMotionAvailable else {
            return .failure(AppError.spatialError(
                reason: "Device motion tracking not available",
                context: ErrorContext()
            ))
        }
        
        // Start motion updates
        motionManager.startDeviceMotionUpdates(
            using: .xArbitraryZVertical,
            to: motionQueue
        ) { [weak self] motion, error in
            guard let self = self, let motion = motion else {
                if let error = error {
                    Logger.shared.logError(error, subsystem: .spatial)
                }
                return
            }
            
            self.processMotionUpdate(motion)
        }
        
        isTracking = true
        Logger.shared.log("Head tracking started", subsystem: .spatial)
        
        return .success(())
    }
    
    /// Safely stops head tracking with resource cleanup
    public func stopTracking() {
        orientationLock.lock()
        defer { orientationLock.unlock() }
        
        guard isTracking else { return }
        
        motionManager.stopDeviceMotionUpdates()
        currentOrientation = SIMD3<Float>(0, 0, 0)
        previousOrientation = SIMD3<Float>(0, 0, 0)
        isTracking = false
        isCalibrated = false
        
        Logger.shared.log("Head tracking stopped", subsystem: .spatial)
    }
    
    /// Resets head orientation with calibration
    public func resetOrientation() {
        orientationLock.lock()
        defer { orientationLock.unlock() }
        
        guard let motion = motionManager.deviceMotion else {
            Logger.shared.log(
                "Failed to reset orientation - no motion data",
                level: .warning,
                subsystem: .spatial
            )
            return
        }
        
        // Store current orientation as calibration offset
        let currentQuat = simd_quatf(
            ix: Float(motion.attitude.quaternion.x),
            iy: Float(motion.attitude.quaternion.y),
            iz: Float(motion.attitude.quaternion.z),
            r: Float(motion.attitude.quaternion.w)
        )
        
        calibrationOffset = simd_inverse(currentQuat)
        currentOrientation = SIMD3<Float>(0, 0, 0)
        previousOrientation = SIMD3<Float>(0, 0, 0)
        isCalibrated = true
        
        Logger.shared.log("Head tracking orientation reset", subsystem: .spatial)
    }
    
    /// Returns current head orientation with prediction
    public func getCurrentOrientation() -> SIMD3<Float> {
        orientationLock.lock()
        defer { orientationLock.unlock() }
        
        return currentOrientation
    }
    
    // MARK: - Private Methods
    
    private func processMotionUpdate(_ motion: CMDeviceMotion) {
        orientationLock.lock()
        defer { orientationLock.unlock() }
        
        // Convert motion data to quaternion
        let motionQuat = simd_quatf(
            ix: Float(motion.attitude.quaternion.x),
            iy: Float(motion.attitude.quaternion.y),
            iz: Float(motion.attitude.quaternion.z),
            r: Float(motion.attitude.quaternion.w)
        )
        
        // Apply calibration offset
        let calibratedQuat = isCalibrated ? motionQuat * calibrationOffset : motionQuat
        
        // Convert to Euler angles
        let newOrientation = quaternionToEuler(calibratedQuat)
        
        // Apply smoothing
        currentOrientation = previousOrientation + (newOrientation - previousOrientation) * (1 - smoothingFactor)
        
        // Clamp rotation speed
        let deltaTime = Float(updateInterval)
        let maxDelta = kMaxHeadRotationSpeed * deltaTime
        let orientationDelta = currentOrientation - previousOrientation
        
        if any(abs(orientationDelta) .> maxDelta) {
            currentOrientation = previousOrientation + simd_clamp(
                orientationDelta,
                -maxDelta,
                maxDelta
            )
        }
        
        previousOrientation = currentOrientation
        
        // Log performance metrics
        Logger.shared.log(
            "Head tracking update",
            subsystem: .spatial,
            metadata: [
                "metrics": [
                    "latency": motion.timestamp - Date().timeIntervalSinceReferenceDate,
                    "yaw": currentOrientation.y,
                    "pitch": currentOrientation.x,
                    "roll": currentOrientation.z
                ]
            ]
        )
    }
}