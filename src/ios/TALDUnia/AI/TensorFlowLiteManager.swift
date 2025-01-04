// Foundation v6.0+, TensorFlowLite v2.13.0
import Foundation
import TensorFlowLite
import os.log

/// Constants for TensorFlow Lite operations
private enum TFLiteConstants {
    static let kModelCacheDirectory = "ai_models"
    static let kMaxConcurrentInterpreters = 4
    static let kDefaultThreadCount = 2
    static let kInterpreterQueueLabel = "com.tald.unia.tflite.queue"
    static let kMaxCacheSize = 512 * 1024 * 1024 // 512MB
    static let kPerformanceLogCategory = "TFLitePerformance"
    static let kMinimumModelVersion = "1.0.0"
}

/// Represents potential TensorFlow Lite errors
enum TFLiteError: LocalizedError {
    case modelNotFound(String)
    case interpreterInitFailed(String)
    case invalidModelVersion(String, String)
    case resourceExhausted
    case gpuDelegateError(String)
    
    var errorDescription: String? {
        switch self {
        case .modelNotFound(let name):
            return "Model not found: \(name)"
        case .interpreterInitFailed(let reason):
            return "Interpreter initialization failed: \(reason)"
        case .invalidModelVersion(let current, let required):
            return "Invalid model version: \(current) (required: \(required))"
        case .resourceExhausted:
            return "Maximum interpreter limit reached"
        case .gpuDelegateError(let reason):
            return "GPU delegate error: \(reason)"
        }
    }
}

/// Cached interpreter wrapper with metadata
private struct CachedInterpreter {
    let interpreter: Interpreter
    let modelVersion: String
    let lastUsed: Date
    let memorySize: Int
    var isGPUEnabled: Bool
}

/// Thread-safe singleton manager for TensorFlow Lite operations
final class TensorFlowLiteManager {
    
    // MARK: - Singleton Instance
    
    static let shared = TensorFlowLiteManager()
    
    // MARK: - Private Properties
    
    private var interpreterCache: [String: CachedInterpreter]
    private let interpreterQueue: DispatchQueue
    private let configuration: Configuration
    private let performanceLogger: OSLog
    private let memoryMonitor: DispatchSource.MemoryPressure
    
    // MARK: - Initialization
    
    private init() {
        self.interpreterCache = [:]
        self.interpreterQueue = DispatchQueue(
            label: TFLiteConstants.kInterpreterQueueLabel,
            qos: .userInitiated
        )
        self.configuration = Configuration.shared
        self.performanceLogger = OSLog(
            subsystem: Bundle.main.bundleIdentifier ?? "com.tald.unia",
            category: TFLiteConstants.kPerformanceLogCategory
        )
        
        // Initialize memory pressure monitor
        self.memoryMonitor = DispatchSource.makeMemoryPressureSource(
            eventMask: [.warning, .critical],
            queue: interpreterQueue
        )
        
        setupMemoryMonitoring()
        createModelCacheDirectory()
    }
    
    // MARK: - Public Methods
    
    /// Loads and initializes a TensorFlow Lite model
    @discardableResult
    func loadModel(
        modelName: String,
        modelVersion: String,
        enableGPU: Bool = false
    ) -> Result<Interpreter, TFLiteError> {
        
        os_signpost(.begin, log: performanceLogger, name: "LoadModel")
        defer { os_signpost(.end, log: performanceLogger, name: "LoadModel") }
        
        return interpreterQueue.sync {
            // Check version compatibility
            guard modelVersion >= TFLiteConstants.kMinimumModelVersion else {
                return .failure(.invalidModelVersion(
                    modelVersion,
                    TFLiteConstants.kMinimumModelVersion
                ))
            }
            
            // Check cache first
            if let cached = interpreterCache[modelName] {
                os_log("Using cached interpreter for model: %{public}s", log: performanceLogger, type: .info, modelName)
                return .success(cached.interpreter)
            }
            
            // Check resource limits
            if interpreterCache.count >= TFLiteConstants.kMaxConcurrentInterpreters {
                cleanupCache()
            }
            
            // Load model file
            guard let modelPath = Bundle.main.path(
                forResource: modelName,
                ofType: "tflite"
            ) else {
                return .failure(.modelNotFound(modelName))
            }
            
            do {
                // Initialize interpreter
                let interpreter = try Interpreter(modelPath: modelPath)
                
                // Configure interpreter
                try configureInterpreter(interpreter, enableGPU: enableGPU)
                
                // Cache the interpreter
                interpreterCache[modelName] = CachedInterpreter(
                    interpreter: interpreter,
                    modelVersion: modelVersion,
                    lastUsed: Date(),
                    memorySize: calculateModelSize(at: modelPath),
                    isGPUEnabled: enableGPU
                )
                
                os_log("Successfully loaded model: %{public}s", log: performanceLogger, type: .info, modelName)
                return .success(interpreter)
                
            } catch {
                os_log("Failed to load model: %{public}s - %{public}s", log: performanceLogger, type: .error, modelName, error.localizedDescription)
                return .failure(.interpreterInitFailed(error.localizedDescription))
            }
        }
    }
    
    /// Retrieves a cached interpreter instance
    func getInterpreter(modelName: String) -> Result<Interpreter, TFLiteError> {
        return interpreterQueue.sync {
            guard let cached = interpreterCache[modelName] else {
                return .failure(.modelNotFound(modelName))
            }
            
            // Update last used timestamp
            interpreterCache[modelName] = CachedInterpreter(
                interpreter: cached.interpreter,
                modelVersion: cached.modelVersion,
                lastUsed: Date(),
                memorySize: cached.memorySize,
                isGPUEnabled: cached.isGPUEnabled
            )
            
            return .success(cached.interpreter)
        }
    }
    
    // MARK: - Private Methods
    
    private func configureInterpreter(
        _ interpreter: Interpreter,
        enableGPU: Bool
    ) throws {
        // Set number of threads based on device capabilities
        interpreter.numberOfThreads = TFLiteConstants.kDefaultThreadCount
        
        // Configure GPU acceleration if requested
        if enableGPU {
            let options = MetalDelegate.Options()
            options.allowPrecisionLoss = false
            options.waitType = .active
            
            do {
                let delegate = try MetalDelegate(options: options)
                try interpreter.addDelegate(delegate)
            } catch {
                throw TFLiteError.gpuDelegateError(error.localizedDescription)
            }
        }
        
        // Allocate tensors
        try interpreter.allocateTensors()
    }
    
    private func cleanupCache() {
        // Remove least recently used interpreters if cache is full
        while interpreterCache.count >= TFLiteConstants.kMaxConcurrentInterpreters {
            let oldest = interpreterCache.min { $0.value.lastUsed < $1.value.lastUsed }
            if let oldestKey = oldest?.key {
                interpreterCache.removeValue(forKey: oldestKey)
            }
        }
    }
    
    private func setupMemoryMonitoring() {
        memoryMonitor.setEventHandler { [weak self] in
            self?.handleMemoryPressure()
        }
        memoryMonitor.resume()
    }
    
    private func handleMemoryPressure() {
        // Clear cache under memory pressure
        interpreterCache.removeAll()
        
        os_log("Cleared interpreter cache due to memory pressure", log: performanceLogger, type: .info)
    }
    
    private func createModelCacheDirectory() {
        let fileManager = FileManager.default
        guard let cachePath = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return
        }
        
        let modelCachePath = cachePath.appendingPathComponent(TFLiteConstants.kModelCacheDirectory)
        
        do {
            try fileManager.createDirectory(
                at: modelCachePath,
                withIntermediateDirectories: true
            )
        } catch {
            os_log("Failed to create model cache directory: %{public}s", log: performanceLogger, type: .error, error.localizedDescription)
        }
    }
    
    private func calculateModelSize(at path: String) -> Int {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path) else {
            return 0
        }
        return attributes[.size] as? Int ?? 0
    }
}