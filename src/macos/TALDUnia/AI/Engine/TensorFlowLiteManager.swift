//
// TensorFlowLiteManager.swift
// TALD UNIA
//
// Manages TensorFlow Lite model loading, configuration, and optimization for audio processing
// Version: 1.0.0
//

import Foundation // macOS 13.0+
import TensorFlowLite // 2.13.0
import Metal // macOS 13.0+

// MARK: - Global Constants

private let kModelBasePath: String = "Models/"
private let kEnhancementModelName: String = "audio_enhancement.tflite"
private let kRoomCorrectionModelName: String = "room_correction.tflite"
private let kDefaultThreadCount: Int = 4
private let kMinimumMetalVersion: String = "2.4"
private let kModelVersionKey: String = "model_version"
private let kMaxGPUMemoryUsage: Int = 512 * 1024 * 1024 // 512MB
private let kModelCacheTimeout: TimeInterval = 300 // 5 minutes
private let kPerformanceMonitoringInterval: TimeInterval = 1.0

// MARK: - Performance Monitoring

private struct PerformanceMetrics {
    var averageLatency: Double = 0.0
    var peakLatency: Double = 0.0
    var processingLoad: Double = 0.0
    var gpuUtilization: Double = 0.0
    var lastUpdateTime: Date = Date()
    
    mutating func update(latency: TimeInterval, load: Double) {
        averageLatency = (averageLatency + latency) / 2.0
        peakLatency = max(peakLatency, latency)
        processingLoad = load
        lastUpdateTime = Date()
    }
}

// MARK: - Model Management

@objc
@available(macOS 13.0, *)
public class TensorFlowLiteManager {
    // MARK: - Properties
    
    private let metalAccelerator: MetalAccelerator
    private var activeInterpreters: [String: Interpreter]
    private let useGPUAcceleration: Bool
    private let threadCount: Int
    private let modelQueue: DispatchQueue
    private let modelCache: NSCache<NSString, Interpreter>
    private let performanceMonitor: PerformanceMonitor
    private let versionManager: ModelVersionManager
    private let activeOperations: AtomicCounter
    private let powerMonitor: PowerStateMonitor
    
    // MARK: - Initialization
    
    public init(useGPU: Bool = true, threads: Int = kDefaultThreadCount, config: ModelConfiguration) throws {
        self.useGPUAcceleration = useGPU
        self.threadCount = min(max(1, threads), ProcessInfo.processInfo.processorCount)
        self.activeInterpreters = [:]
        
        // Initialize Metal accelerator if GPU acceleration is enabled
        if useGPU {
            self.metalAccelerator = try MetalAccelerator(preferredGPU: true, config: ProcessingConfiguration())
        } else {
            self.metalAccelerator = try MetalAccelerator(preferredGPU: false, config: ProcessingConfiguration())
        }
        
        // Initialize processing queue
        self.modelQueue = DispatchQueue(
            label: "com.tald.unia.tflite.manager",
            qos: .userInteractive,
            attributes: .concurrent
        )
        
        // Initialize model cache
        self.modelCache = NSCache<NSString, Interpreter>()
        modelCache.countLimit = 10
        modelCache.totalCostLimit = kMaxGPUMemoryUsage
        
        // Initialize monitoring and management components
        self.performanceMonitor = PerformanceMonitor(updateInterval: kPerformanceMonitoringInterval)
        self.versionManager = ModelVersionManager()
        self.activeOperations = AtomicCounter()
        self.powerMonitor = PowerStateMonitor()
        
        // Load default models
        try loadDefaultModels()
    }
    
    // MARK: - Model Loading
    
    public func loadModel(modelUrl: URL, modelId: String, options: ModelLoadOptions) -> Result<LoadedModel, TALDError> {
        let startTime = Date()
        let operationCount = activeOperations.increment()
        defer { activeOperations.decrement() }
        
        // Check cache first
        if let cachedInterpreter = modelCache.object(forKey: NSString(string: modelId)) {
            return .success(LoadedModel(interpreter: cachedInterpreter, id: modelId))
        }
        
        do {
            // Validate model compatibility
            let validationResult = try validateModelCompatibility(modelUrl: modelUrl, requirements: options.requirements)
            guard case .success = validationResult else {
                return .failure(TALDError.configurationError(
                    code: "MODEL_INCOMPATIBLE",
                    message: "Model validation failed",
                    metadata: ErrorMetadata(
                        timestamp: Date(),
                        component: "TensorFlowLiteManager",
                        additionalInfo: ["modelId": modelId]
                    )
                ))
            }
            
            // Configure interpreter options
            var interpreterOptions = Interpreter.Options()
            interpreterOptions.threadCount = threadCount
            
            if useGPUAcceleration {
                let delegate = try metalAccelerator.createDelegate()
                interpreterOptions.delegates = [delegate]
            }
            
            // Create and configure interpreter
            let interpreter = try Interpreter(modelPath: modelUrl.path, options: interpreterOptions)
            try interpreter.allocateTensors()
            
            // Cache interpreter
            modelCache.setObject(interpreter, forKey: NSString(string: modelId))
            activeInterpreters[modelId] = interpreter
            
            // Update performance metrics
            let loadTime = Date().timeIntervalSince(startTime)
            performanceMonitor.updateMetrics(
                latency: loadTime,
                operationCount: operationCount
            )
            
            return .success(LoadedModel(interpreter: interpreter, id: modelId))
            
        } catch {
            return .failure(TALDError.configurationError(
                code: "MODEL_LOAD_FAILED",
                message: "Failed to load model: \(error.localizedDescription)",
                metadata: ErrorMetadata(
                    timestamp: Date(),
                    component: "TensorFlowLiteManager",
                    additionalInfo: [
                        "modelId": modelId,
                        "error": error.localizedDescription
                    ]
                )
            ))
        }
    }
    
    public func unloadModel(modelId: String, options: UnloadOptions = UnloadOptions()) -> Result<Void, TALDError> {
        return modelQueue.sync {
            guard activeInterpreters[modelId] != nil else {
                return .failure(TALDError.configurationError(
                    code: "MODEL_NOT_FOUND",
                    message: "Model not found for unloading",
                    metadata: ErrorMetadata(
                        timestamp: Date(),
                        component: "TensorFlowLiteManager",
                        additionalInfo: ["modelId": modelId]
                    )
                ))
            }
            
            // Remove from cache and active interpreters
            modelCache.removeObject(forKey: NSString(string: modelId))
            activeInterpreters.removeValue(forKey: modelId)
            
            // Release GPU resources if using acceleration
            if useGPUAcceleration {
                metalAccelerator.releaseResources(for: modelId)
            }
            
            return .success(())
        }
    }
    
    // MARK: - Performance Optimization
    
    public func optimizePerformance(config: PerformanceConfig) -> Result<PerformanceMetrics, TALDError> {
        let startTime = Date()
        
        return modelQueue.sync {
            // Analyze current system state
            let systemLoad = powerMonitor.currentSystemLoad
            let gpuUtilization = metalAccelerator.currentUtilization
            
            // Adjust thread count based on system load
            let optimalThreadCount = calculateOptimalThreadCount(systemLoad: systemLoad)
            
            // Update interpreter configurations
            for (_, interpreter) in activeInterpreters {
                var options = interpreter.options
                options.threadCount = optimalThreadCount
                
                if useGPUAcceleration {
                    try? metalAccelerator.optimizeDelegate(for: interpreter)
                }
            }
            
            // Update performance metrics
            let optimizationTime = Date().timeIntervalSince(startTime)
            let metrics = PerformanceMetrics(
                averageLatency: performanceMonitor.averageLatency,
                peakLatency: performanceMonitor.peakLatency,
                processingLoad: systemLoad,
                gpuUtilization: gpuUtilization,
                lastUpdateTime: Date()
            )
            
            return .success(metrics)
        }
    }
    
    // MARK: - Private Helpers
    
    private func loadDefaultModels() throws {
        let defaultModels = [
            (kEnhancementModelName, "enhancement"),
            (kRoomCorrectionModelName, "room_correction")
        ]
        
        for (modelName, modelId) in defaultModels {
            let modelUrl = URL(fileURLWithPath: kModelBasePath).appendingPathComponent(modelName)
            let options = ModelLoadOptions(requirements: [:])
            
            let result = loadModel(modelUrl: modelUrl, modelId: modelId, options: options)
            if case .failure(let error) = result {
                throw error
            }
        }
    }
    
    private func calculateOptimalThreadCount(systemLoad: Double) -> Int {
        let availableThreads = ProcessInfo.processInfo.activeProcessorCount
        let optimalThreads = Int(Double(availableThreads) * (1.0 - systemLoad))
        return max(1, min(optimalThreads, threadCount))
    }
    
    @discardableResult
    private func validateModelCompatibility(modelUrl: URL, requirements: [String: Any]) -> Result<ModelValidationResult, TALDError> {
        // Verify model file exists
        guard FileManager.default.fileExists(atPath: modelUrl.path) else {
            return .failure(TALDError.configurationError(
                code: "MODEL_NOT_FOUND",
                message: "Model file not found",
                metadata: ErrorMetadata(
                    timestamp: Date(),
                    component: "TensorFlowLiteManager",
                    additionalInfo: ["path": modelUrl.path]
                )
            ))
        }
        
        // Verify model version if specified
        if let requiredVersion = requirements[kModelVersionKey] as? String {
            guard versionManager.isVersionCompatible(requiredVersion) else {
                return .failure(TALDError.configurationError(
                    code: "INCOMPATIBLE_VERSION",
                    message: "Model version not compatible",
                    metadata: ErrorMetadata(
                        timestamp: Date(),
                        component: "TensorFlowLiteManager",
                        additionalInfo: ["requiredVersion": requiredVersion]
                    )
                ))
            }
        }
        
        // Verify GPU compatibility if using acceleration
        if useGPUAcceleration {
            guard metalAccelerator.isCompatible(with: requirements) else {
                return .failure(TALDError.configurationError(
                    code: "GPU_INCOMPATIBLE",
                    message: "GPU acceleration not compatible with model",
                    metadata: ErrorMetadata(
                        timestamp: Date(),
                        component: "TensorFlowLiteManager",
                        additionalInfo: ["gpuAcceleration": "true"]
                    )
                ))
            }
        }
        
        return .success(ModelValidationResult(isValid: true))
    }
}

// MARK: - Supporting Types

private struct ModelLoadOptions {
    let requirements: [String: Any]
}

private struct UnloadOptions {
    let force: Bool = false
}

private struct LoadedModel {
    let interpreter: Interpreter
    let id: String
}

private struct ModelValidationResult {
    let isValid: Bool
}

private class AtomicCounter {
    private var value: Int = 0
    private let lock = NSLock()
    
    func increment() -> Int {
        lock.lock()
        defer { lock.unlock() }
        value += 1
        return value
    }
    
    func decrement() -> Int {
        lock.lock()
        defer { lock.unlock() }
        value -= 1
        return value
    }
}