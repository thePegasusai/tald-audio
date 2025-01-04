// Foundation v17.0+
import Foundation

/// Represents the severity level of an error in the TALD UNIA system
public enum ErrorSeverity: Int {
    case critical = 0
    case error = 1
    case warning = 2
    case info = 3
}

/// Represents the category of an error for better classification
public enum ErrorCategory: String {
    case audio = "audio"
    case configuration = "configuration"
    case ai = "ai"
    case spatial = "spatial"
    case network = "network"
    case hardware = "hardware"
}

/// Holds contextual information about an error
public struct ErrorContext {
    let file: String
    let function: String
    let line: Int
    let timestamp: Date
    let additionalInfo: [String: Any]?
    
    public init(file: String = #file,
                function: String = #function,
                line: Int = #line,
                timestamp: Date = Date(),
                additionalInfo: [String: Any]? = nil) {
        self.file = file
        self.function = function
        self.line = line
        self.timestamp = timestamp
        self.additionalInfo = additionalInfo
    }
}

/// Main error type for the TALD UNIA application
public enum AppError: LocalizedError, CustomDebugStringConvertible {
    // MARK: - Audio Errors
    case audioError(reason: String, severity: ErrorSeverity = .error, context: ErrorContext)
    case audioInitializationFailed(reason: String, context: ErrorContext)
    case audioProcessingFailed(reason: String, context: ErrorContext)
    
    // MARK: - Configuration Errors
    case configurationError(reason: String, severity: ErrorSeverity = .error, context: ErrorContext)
    case invalidConfiguration(key: String, context: ErrorContext)
    case missingConfiguration(key: String, context: ErrorContext)
    
    // MARK: - AI Errors
    case aiError(reason: String, severity: ErrorSeverity = .error, context: ErrorContext)
    case modelLoadingFailed(modelName: String, context: ErrorContext)
    case inferenceError(reason: String, context: ErrorContext)
    
    // MARK: - Spatial Audio Errors
    case spatialError(reason: String, severity: ErrorSeverity = .error, context: ErrorContext)
    case hrtfLoadingFailed(reason: String, context: ErrorContext)
    case spatialProcessingFailed(reason: String, context: ErrorContext)
    
    // MARK: - Network Errors
    case networkError(reason: String, severity: ErrorSeverity = .error, context: ErrorContext)
    case connectionFailed(url: URL, context: ErrorContext)
    case invalidResponse(statusCode: Int, context: ErrorContext)
    
    // MARK: - Hardware Errors
    case hardwareError(reason: String, severity: ErrorSeverity = .error, context: ErrorContext)
    case deviceNotFound(deviceType: String, context: ErrorContext)
    case deviceInitializationFailed(deviceType: String, context: ErrorContext)
    
    // MARK: - Public Properties
    
    /// Returns the severity level of the error
    public var errorSeverity: ErrorSeverity {
        switch self {
        case .audioError(_, let severity, _),
             .configurationError(_, let severity, _),
             .aiError(_, let severity, _),
             .spatialError(_, let severity, _),
             .networkError(_, let severity, _),
             .hardwareError(_, let severity, _):
            return severity
        case .audioInitializationFailed,
             .modelLoadingFailed,
             .deviceInitializationFailed:
            return .critical
        default:
            return .error
        }
    }
    
    /// Returns the category of the error
    public var errorCategory: ErrorCategory {
        switch self {
        case .audioError, .audioInitializationFailed, .audioProcessingFailed:
            return .audio
        case .configurationError, .invalidConfiguration, .missingConfiguration:
            return .configuration
        case .aiError, .modelLoadingFailed, .inferenceError:
            return .ai
        case .spatialError, .hrtfLoadingFailed, .spatialProcessingFailed:
            return .spatial
        case .networkError, .connectionFailed, .invalidResponse:
            return .network
        case .hardwareError, .deviceNotFound, .deviceInitializationFailed:
            return .hardware
        }
    }
    
    /// Returns the context of the error
    public var errorContext: ErrorContext {
        switch self {
        case .audioError(_, _, let context),
             .audioInitializationFailed(_, let context),
             .audioProcessingFailed(_, let context),
             .configurationError(_, _, let context),
             .invalidConfiguration(_, let context),
             .missingConfiguration(_, let context),
             .aiError(_, _, let context),
             .modelLoadingFailed(_, let context),
             .inferenceError(_, let context),
             .spatialError(_, _, let context),
             .hrtfLoadingFailed(_, let context),
             .spatialProcessingFailed(_, let context),
             .networkError(_, _, let context),
             .connectionFailed(_, let context),
             .invalidResponse(_, let context),
             .hardwareError(_, _, let context),
             .deviceNotFound(_, let context),
             .deviceInitializationFailed(_, let context):
            return context
        }
    }
    
    // MARK: - LocalizedError Implementation
    
    public var errorDescription: String? {
        return localizedDescription
    }
    
    public var localizedDescription: String {
        let errorPrefix = "TALD_UNIA_ERROR"
        let severityString = errorSeverity == .critical ? "CRITICAL: " : ""
        
        switch self {
        case .audioError(let reason, _, _):
            return "\(errorPrefix).\(severityString)AUDIO: \(reason)"
        case .audioInitializationFailed(let reason, _):
            return "\(errorPrefix).CRITICAL: Audio initialization failed - \(reason)"
        case .audioProcessingFailed(let reason, _):
            return "\(errorPrefix).AUDIO_PROCESSING: \(reason)"
        case .configurationError(let reason, _, _):
            return "\(errorPrefix).\(severityString)CONFIG: \(reason)"
        case .invalidConfiguration(let key, _):
            return "\(errorPrefix).CONFIG: Invalid configuration for key '\(key)'"
        case .missingConfiguration(let key, _):
            return "\(errorPrefix).CONFIG: Missing configuration for key '\(key)'"
        case .aiError(let reason, _, _):
            return "\(errorPrefix).\(severityString)AI: \(reason)"
        case .modelLoadingFailed(let modelName, _):
            return "\(errorPrefix).CRITICAL: Failed to load AI model '\(modelName)'"
        case .inferenceError(let reason, _):
            return "\(errorPrefix).AI_INFERENCE: \(reason)"
        case .spatialError(let reason, _, _):
            return "\(errorPrefix).\(severityString)SPATIAL: \(reason)"
        case .hrtfLoadingFailed(let reason, _):
            return "\(errorPrefix).SPATIAL: HRTF loading failed - \(reason)"
        case .spatialProcessingFailed(let reason, _):
            return "\(errorPrefix).SPATIAL: Processing failed - \(reason)"
        case .networkError(let reason, _, _):
            return "\(errorPrefix).\(severityString)NETWORK: \(reason)"
        case .connectionFailed(let url, _):
            return "\(errorPrefix).NETWORK: Connection failed to \(url.absoluteString)"
        case .invalidResponse(let statusCode, _):
            return "\(errorPrefix).NETWORK: Invalid response (Status: \(statusCode))"
        case .hardwareError(let reason, _, _):
            return "\(errorPrefix).\(severityString)HARDWARE: \(reason)"
        case .deviceNotFound(let deviceType, _):
            return "\(errorPrefix).HARDWARE: Device not found - \(deviceType)"
        case .deviceInitializationFailed(let deviceType, _):
            return "\(errorPrefix).CRITICAL: Device initialization failed - \(deviceType)"
        }
    }
    
    // MARK: - CustomDebugStringConvertible Implementation
    
    public var debugDescription: String {
        let context = errorContext
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        
        var debug = """
        TALD UNIA Error Debug Information
        --------------------------------
        Timestamp: \(dateFormatter.string(from: context.timestamp))
        Category: \(errorCategory.rawValue)
        Severity: \(errorSeverity)
        Location: \(context.file):\(context.line)
        Function: \(context.function)
        Description: \(localizedDescription)
        """
        
        if let additionalInfo = context.additionalInfo {
            debug += "\nAdditional Context:"
            additionalInfo.forEach { key, value in
                debug += "\n  \(key): \(value)"
            }
        }
        
        return debug
    }
}