//
// ErrorTypes.swift
// TALD UNIA
//
// Core error types and error handling mechanisms for the TALD UNIA audio system
// Foundation version: macOS 13.0+
//

import Foundation

/// Metadata structure for additional error context
public struct ErrorMetadata: Codable {
    let timestamp: Date
    let component: String
    let additionalInfo: [String: String]
}

/// Defines severity levels for error classification
public enum ErrorSeverity: Int, Codable {
    case critical = 0
    case error = 1
    case warning = 2
    case info = 3
    
    var description: String {
        switch self {
        case .critical: return "Critical"
        case .error: return "Error"
        case .warning: return "Warning"
        case .info: return "Information"
        }
    }
    
    var level: Int {
        return self.rawValue
    }
}

/// Classification system for error categories
public enum ErrorCategory: String, Codable {
    case configuration
    case audio
    case ai
    case spatial
    case network
    case hardware
    
    var categoryCode: String {
        return "TALD_\(self.rawValue.uppercased())"
    }
    
    var description: String {
        switch self {
        case .configuration: return "Configuration Error"
        case .audio: return "Audio Processing Error"
        case .ai: return "AI Processing Error"
        case .spatial: return "Spatial Processing Error"
        case .network: return "Network Error"
        case .hardware: return "Hardware Error"
        }
    }
    
    func isUserFacing() -> Bool {
        switch self {
        case .configuration, .hardware:
            return true
        case .audio, .spatial:
            return true
        case .ai, .network:
            return false
        }
    }
}

/// Main error type for TALD UNIA system
public enum TALDError: Error {
    case configurationError(code: String, message: String, metadata: ErrorMetadata)
    case audioProcessingError(code: String, message: String, metadata: ErrorMetadata)
    case aiProcessingError(code: String, message: String, metadata: ErrorMetadata)
    case spatialProcessingError(code: String, message: String, metadata: ErrorMetadata)
    case networkError(code: String, message: String, metadata: ErrorMetadata)
    case hardwareError(code: String, message: String, metadata: ErrorMetadata)
    
    public var errorCode: String {
        switch self {
        case .configurationError(let code, _, _): return "\(ErrorCategory.configuration.categoryCode)_\(code)"
        case .audioProcessingError(let code, _, _): return "\(ErrorCategory.audio.categoryCode)_\(code)"
        case .aiProcessingError(let code, _, _): return "\(ErrorCategory.ai.categoryCode)_\(code)"
        case .spatialProcessingError(let code, _, _): return "\(ErrorCategory.spatial.categoryCode)_\(code)"
        case .networkError(let code, _, _): return "\(ErrorCategory.network.categoryCode)_\(code)"
        case .hardwareError(let code, _, _): return "\(ErrorCategory.hardware.categoryCode)_\(code)"
        }
    }
    
    public var severity: ErrorSeverity {
        switch self {
        case .hardwareError: return .critical
        case .configurationError: return .error
        case .audioProcessingError: return .error
        case .aiProcessingError: return .warning
        case .spatialProcessingError: return .warning
        case .networkError: return .warning
        }
    }
    
    public var metadata: ErrorMetadata {
        switch self {
        case .configurationError(_, _, let metadata): return metadata
        case .audioProcessingError(_, _, let metadata): return metadata
        case .aiProcessingError(_, _, let metadata): return metadata
        case .spatialProcessingError(_, _, let metadata): return metadata
        case .networkError(_, _, let metadata): return metadata
        case .hardwareError(_, _, let metadata): return metadata
        }
    }
    
    public var debugDescription: String {
        return "[\(severity.description)] \(errorCode): \(localizedDescription)"
    }
    
    public var localizedDescription: String {
        let bundle = Bundle.main
        let tableName = "TALDErrors"
        
        switch self {
        case .configurationError(_, let message, _),
             .audioProcessingError(_, let message, _),
             .aiProcessingError(_, let message, _),
             .spatialProcessingError(_, let message, _),
             .networkError(_, let message, _),
             .hardwareError(_, let message, _):
            
            let localizedMessage = bundle.localizedString(
                forKey: errorCode,
                value: message,
                table: tableName
            )
            return localizedMessage
        }
    }
    
    public var recoverySuggestion: String {
        let bundle = Bundle.main
        let tableName = "TALDErrorRecovery"
        let suggestionKey = "\(errorCode)_RECOVERY"
        
        let defaultSuggestion: String
        switch severity {
        case .critical:
            defaultSuggestion = "Please contact support immediately."
        case .error:
            defaultSuggestion = "Try restarting the application."
        case .warning:
            defaultSuggestion = "You may continue using the application."
        case .info:
            defaultSuggestion = "No action required."
        }
        
        return bundle.localizedString(
            forKey: suggestionKey,
            value: defaultSuggestion,
            table: tableName
        )
    }
}