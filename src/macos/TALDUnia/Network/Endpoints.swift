//
// Endpoints.swift
// TALD UNIA
//
// Network endpoint definitions for TALD UNIA audio system
// Version: 1.0.0
//

import Foundation // macOS 13.0+

/// API endpoint paths for TALD UNIA audio system
@frozen public struct APIEndpoints {
    // MARK: - Base URL Configuration
    
    /// Base URL for API endpoints
    public static let baseURL: String = "https://api.tald.unia"
    
    // MARK: - API Endpoints
    
    /// Audio processing endpoint path
    public static let audioProcessing: String = "/audio/process"
    
    /// AI enhancement endpoint path
    public static let aiEnhancement: String = "/ai/enhance"
    
    /// Spatial audio processing endpoint path
    public static let spatialProcessing: String = "/spatial/process"
    
    /// Profile management endpoint path
    public static let profileManagement: String = "/profile"
    
    /// AI model download endpoint path
    public static let modelDownload: String = "/model/download"
    
    /// WebSocket endpoint for real-time audio streaming
    public static var websocketEndpoint: String {
        return "\(NetworkConstants.WEBSOCKET_PROTOCOL)://\(baseURL)/\(NetworkConstants.API_VERSION)/stream"
    }
}

/// Type-safe endpoint path enumeration
@frozen public enum EndpointPath: String {
    case audio = "audio"
    case ai = "ai"
    case spatial = "spatial"
    case profile = "profile"
    case model = "model"
    case websocket = "stream"
    
    /// Full path including API version
    public var fullPath: String {
        return "/\(NetworkConstants.API_VERSION)/\(self.rawValue)"
    }
}

/// URL construction utility for API endpoints
@frozen final class URLBuilder {
    // MARK: - Properties
    
    private let urlCache: NSCache<NSString, NSURL>
    private let buildQueue: DispatchQueue
    
    // MARK: - Constants
    
    private let requestTimeout: TimeInterval = 0.010 // 10ms as per requirements
    
    // MARK: - Initialization
    
    init() {
        urlCache = NSCache<NSString, NSURL>()
        urlCache.countLimit = 100 // Cache up to 100 URLs
        buildQueue = DispatchQueue(label: "com.tald.unia.urlbuilder", qos: .userInitiated)
    }
    
    // MARK: - URL Construction
    
    /// Builds and caches URL for the given endpoint path
    /// - Parameters:
    ///   - path: Endpoint path
    ///   - params: Optional query parameters
    /// - Returns: Result containing constructed URL or error
    @inlinable
    func buildAndCacheURL(path: String, params: [String: String]? = nil) -> Result<URL, URLError> {
        let cacheKey = NSString(string: path + (params?.description ?? ""))
        
        if let cachedURL = urlCache.object(forKey: cacheKey) as URL? {
            return .success(cachedURL)
        }
        
        return buildQueue.sync {
            do {
                var components = URLComponents()
                components.scheme = "https"
                components.host = APIEndpoints.baseURL.replacingOccurrences(of: "https://", with: "")
                components.path = path
                
                if let params = params {
                    components.queryItems = params.map { 
                        URLQueryItem(name: $0.key, value: $0.value)
                    }
                }
                
                guard let url = components.url else {
                    return .failure(URLError(.badURL))
                }
                
                urlCache.setObject(url as NSURL, forKey: cacheKey)
                return .success(url)
            } catch {
                return .failure(URLError(.badURL))
            }
        }
    }
    
    /// Builds WebSocket URL for real-time streaming
    /// - Returns: Result containing WebSocket URL or error
    @inlinable
    func buildWebSocketURL() -> Result<URL, URLError> {
        let wsConfig = Configuration.shared.networkConfig
        
        guard let url = URL(string: APIEndpoints.websocketEndpoint) else {
            return .failure(URLError(.badURL))
        }
        
        return .success(url)
    }
}

// MARK: - Request Configuration

extension URLRequest {
    /// Creates a configured URLRequest for TALD UNIA API
    /// - Parameters:
    ///   - url: Target URL
    ///   - method: HTTP method
    /// - Returns: Configured URLRequest
    static func configuredRequest(url: URL, method: String = "GET") -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 0.010 // 10ms timeout as per requirements
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(Bundle.main.bundleIdentifier, forHTTPHeaderField: "X-Client-ID")
        return request
    }
}