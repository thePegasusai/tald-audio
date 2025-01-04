//
// HeadTracker.swift
// TALD UNIA
//
// High-performance head tracking system for spatial audio processing
// Version: 1.0.0
//

import CoreMotion // macOS 13.0+
import simd // macOS 13.0+
import Foundation // macOS 13.0+

// MARK: - Queue Labels
private let HEAD_TRACKER_QUEUE_LABEL = "com.tald.unia.headtracker.processing"
private let HEAD_TRACKER_CALIBRATION_QUEUE_LABEL = "com.tald.unia.headtracker.calibration"

// MARK: - Head Tracker
@objc public final class HeadTracker {
    // MARK: - Properties
    private let motionManager: CMMotionManager
    private let trackingQueue: DispatchQueue
    private let calibrationQueue: DispatchQueue
    private var currentOrientation: simd_float4x4
    private var calibrationMatrix: simd_float4x4
    private var updateRate: Double
    private var isTracking: Bool
    private var isCalibrating: Bool
    private let orientationLock: NSLock
    private var lastUpdateTimestamp: Double
    private var sampleCount: Int
    private var driftCompensation: Double
    
    // MARK: - Initialization
    public init() {
        // Initialize motion manager with optimal settings
        motionManager = CMMotionManager()
        motionManager.deviceMotionUpdateInterval = SpatialConstants.HEAD_TRACKING_UPDATE_RATE
        
        // Create high-priority queues
        trackingQueue = DispatchQueue(
            label: HEAD_TRACKER_QUEUE_LABEL,
            qos: .userInteractive
        )
        calibrationQueue = DispatchQueue(
            label: HEAD_TRACKER_CALIBRATION_QUEUE_LABEL,
            qos: .userInitiated
        )
        
        // Initialize matrices and state
        currentOrientation = matrix_identity_float4x4
        calibrationMatrix = matrix_identity_float4x4
        updateRate = SpatialConstants.HEAD_TRACKING_UPDATE_RATE
        isTracking = false
        isCalibrating = false
        orientationLock = NSLock()
        lastUpdateTimestamp = 0
        sampleCount = 0
        driftCompensation = 0
        
        // Configure motion sensors
        motionManager.showsDeviceMovementDisplay = true
        motionManager.deviceMotionUpdateInterval = updateRate
    }
    
    // MARK: - Public Methods
    public func startTracking() -> Bool {
        guard motionManager.isDeviceMotionAvailable else {
            Logger.shared.log(
                "Device motion not available",
                severity: .error,
                context: "HeadTracker"
            )
            return false
        }
        
        // Prevent multiple tracking sessions
        guard !isTracking else { return true }
        
        // Reset state
        orientationLock.lock()
        currentOrientation = matrix_identity_float4x4
        calibrationMatrix = matrix_identity_float4x4
        lastUpdateTimestamp = CACurrentMediaTime()
        sampleCount = 0
        driftCompensation = 0
        orientationLock.unlock()
        
        // Start motion updates
        motionManager.startDeviceMotionUpdates(
            to: trackingQueue
        ) { [weak self] motion, error in
            guard let self = self,
                  let motion = motion else {
                if let error = error {
                    Logger.shared.error(
                        error,
                        context: "HeadTracker",
                        metadata: ["operation": "motionUpdate"]
                    )
                }
                return
            }
            
            self.processMotionData(motion)
        }
        
        isTracking = true
        
        Logger.shared.log(
            "Head tracking started",
            severity: .info,
            context: "HeadTracker",
            metadata: [
                "updateRate": String(updateRate),
                "timestamp": String(lastUpdateTimestamp)
            ]
        )
        
        return true
    }
    
    public func stopTracking() {
        guard isTracking else { return }
        
        motionManager.stopDeviceMotionUpdates()
        
        orientationLock.lock()
        currentOrientation = matrix_identity_float4x4
        isTracking = false
        orientationLock.unlock()
        
        Logger.shared.log(
            "Head tracking stopped",
            severity: .info,
            context: "HeadTracker",
            metadata: [
                "sampleCount": String(sampleCount),
                "totalTime": String(CACurrentMediaTime() - lastUpdateTimestamp)
            ]
        )
    }
    
    public func getCurrentOrientation() -> simd_float4x4 {
        orientationLock.lock()
        defer { orientationLock.unlock() }
        
        // Apply drift compensation
        var compensatedOrientation = currentOrientation
        if driftCompensation != 0 {
            let compensation = simd_float4x4(rotationAbout: SIMD3<Float>(0, 1, 0), by: Float(driftCompensation))
            compensatedOrientation = matrix_multiply(compensatedOrientation, compensation)
        }
        
        return matrix_multiply(compensatedOrientation, calibrationMatrix)
    }
    
    // MARK: - Private Methods
    private func processMotionData(_ motionData: CMDeviceMotion) {
        let currentTime = CACurrentMediaTime()
        let deltaTime = currentTime - lastUpdateTimestamp
        
        // Convert quaternion to rotation matrix using SIMD
        let quat = motionData.attitude.quaternion
        let q = simd_quatf(
            ix: Float(quat.x),
            iy: Float(quat.y),
            iz: Float(quat.z),
            r: Float(quat.w)
        )
        
        // Create rotation matrix
        var newOrientation = matrix_float4x4(q)
        
        // Apply calibration and update orientation
        orientationLock.lock()
        currentOrientation = newOrientation
        
        // Update drift compensation
        if deltaTime > 0 {
            let rotationRate = motionData.rotationRate
            driftCompensation += rotationRate.y * deltaTime * 0.1 // Damping factor
        }
        
        sampleCount += 1
        lastUpdateTimestamp = currentTime
        orientationLock.unlock()
        
        // Performance monitoring
        if sampleCount % 100 == 0 {
            Logger.shared.log(
                "Head tracking performance",
                severity: .debug,
                context: "HeadTracker",
                metadata: [
                    "updateInterval": String(deltaTime),
                    "sampleCount": String(sampleCount),
                    "driftCompensation": String(driftCompensation)
                ]
            )
        }
    }
}

// MARK: - SIMD Extensions
private extension simd_float4x4 {
    init(rotationAbout axis: SIMD3<Float>, by angle: Float) {
        let c = cos(angle)
        let s = sin(angle)
        let t = 1 - c
        
        let x = axis.x
        let y = axis.y
        let z = axis.z
        
        self.init(
            SIMD4<Float>(t*x*x + c, t*x*y - s*z, t*x*z + s*y, 0),
            SIMD4<Float>(t*x*y + s*z, t*y*y + c, t*y*z - s*x, 0),
            SIMD4<Float>(t*x*z - s*y, t*y*z + s*x, t*z*z + c, 0),
            SIMD4<Float>(0, 0, 0, 1)
        )
    }
}