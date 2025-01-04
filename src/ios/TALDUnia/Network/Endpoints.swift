import Foundation

/// Defines all available API endpoints for the TALD UNIA audio system with comprehensive routing and security configuration
public enum APIEndpoint {
    // MARK: - Audio Processing Endpoints
    
    /// Real-time audio processing with format selection
    case processAudio(format: String, realtime: Bool)
    
    /// AI-driven audio enhancement with model selection and level control
    case enhanceAudio(modelId: String, enhancementLevel: Float)
    
    /// Spatial audio processing with room profile and parameters
    case spatialProcess(roomProfile: String, spatialParameters: [String: Float])
    
    // MARK: - Profile Management Endpoints
    
    /// User profile retrieval
    case getProfile(profileId: UUID)
    
    /// Profile settings update
    case updateProfile(profileId: UUID, settings: [String: Any])
    
    // MARK: - Model Management Endpoints
    
    /// AI model download and update
    case downloadModel(modelId: String, version: String, forceUpdate: Bool)
    
    /// Real-time audio streaming
    case streamAudio(streamId: String, configuration: [String: Any])
    
    // MARK: - Path Construction
    
    /// Returns the fully qualified endpoint path
    public var path: String {
        let base = NetworkConstants.baseURL
        
        switch self {
        case .processAudio(let format, _):
            return "\(base)/audio/process/\(format)"
            
        case .enhanceAudio(let modelId, _):
            return "\(base)/audio/enhance/\(modelId)"
            
        case .spatialProcess(let roomProfile, _):
            return "\(base)/audio/spatial/\(roomProfile)"
            
        case .getProfile(let profileId):
            return "\(base)/profiles/\(profileId)"
            
        case .updateProfile(let profileId, _):
            return "\(base)/profiles/\(profileId)"
            
        case .downloadModel(let modelId, let version, _):
            return "\(base)/models/\(modelId)/\(version)"
            
        case .streamAudio(let streamId, _):
            return "\(base)/stream/\(streamId)"
        }
    }
    
    // MARK: - HTTP Method
    
    /// Returns the appropriate HTTP method for each endpoint
    public var method: String {
        switch self {
        case .getProfile, .downloadModel:
            return "GET"
        case .processAudio, .enhanceAudio, .spatialProcess:
            return "POST"
        case .updateProfile:
            return "PUT"
        case .streamAudio:
            return "CONNECT"
        }
    }
    
    // MARK: - Security Configuration
    
    /// Indicates whether the endpoint requires authentication
    public var requiresAuth: Bool {
        switch self {
        case .processAudio(_, let realtime):
            return realtime
        case .getProfile, .updateProfile, .downloadModel:
            return true
        case .enhanceAudio, .spatialProcess, .streamAudio:
            return true
        }
    }
    
    // MARK: - Timeout Configuration
    
    /// Custom timeout interval for specific endpoints
    public var timeoutInterval: TimeInterval {
        switch self {
        case .processAudio(_, let realtime):
            return realtime ? NetworkConstants.timeoutInterval / 2 : NetworkConstants.timeoutInterval
        case .streamAudio:
            return NetworkConstants.timeoutInterval * 2
        case .downloadModel:
            return NetworkConstants.timeoutInterval * 4
        default:
            return NetworkConstants.timeoutInterval
        }
    }
    
    // MARK: - Cache Configuration
    
    /// Specific caching policy for each endpoint
    public var cachePolicy: URLRequest.CachePolicy {
        switch self {
        case .getProfile:
            return .returnCacheDataElseLoad
        case .downloadModel(_, _, let forceUpdate):
            return forceUpdate ? .reloadIgnoringLocalCacheData : .returnCacheDataElseLoad
        case .processAudio(_, let realtime):
            return realtime ? .reloadIgnoringLocalCacheData : .useProtocolCachePolicy
        default:
            return .reloadIgnoringLocalCacheData
        }
    }
    
    // MARK: - Request Parameters
    
    /// Constructs request parameters for the endpoint
    public var parameters: [String: Any] {
        switch self {
        case .processAudio(_, let realtime):
            return ["realtime": realtime]
            
        case .enhanceAudio(_, let enhancementLevel):
            return ["enhancementLevel": enhancementLevel]
            
        case .spatialProcess(_, let spatialParameters):
            return spatialParameters
            
        case .updateProfile(_, let settings):
            return settings
            
        case .downloadModel(_, _, let forceUpdate):
            return ["forceUpdate": forceUpdate]
            
        case .streamAudio(_, let configuration):
            return configuration
            
        default:
            return [:]
        }
    }
}