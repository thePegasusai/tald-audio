//
// APIClient.swift
// TALD UNIA
//
// Core API client for network communication with TALD UNIA backend services
// Version: 1.0.0
//

import Foundation // macOS 13.0+
import Combine // macOS 13.0+

/// Request timeout interval (10ms as per requirements)
private let API_TIMEOUT: TimeInterval = 0.010

/// Maximum number of retry attempts for failed requests
private let MAX_RETRY_ATTEMPTS: Int = 3

/// Dedicated dispatch queue for API operations
private let REQUEST_QUEUE = DispatchQueue(label: "com.tald.unia.apiclient", qos: .userInitiated)

/// Core API client implementing secure, monitored network communication
public final class APIClient {
    // MARK: - Singleton
    
    public static let shared = APIClient()
    
    // MARK: - Properties
    
    private let session: URLSession
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let networkMonitor: NetworkMonitor
    
    // MARK: - Initialization
    
    private init() {
        // Configure secure session
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = API_TIMEOUT
        configuration.timeoutIntervalForResource = API_TIMEOUT
        configuration.waitsForConnectivity = true
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.networkServiceType = .responsiveAV
        
        // Configure TLS
        configuration.tlsMinimumSupportedProtocolVersion = .TLSv13
        configuration.tlsMaximumSupportedProtocolVersion = .TLSv13
        
        self.session = URLSession(configuration: configuration)
        
        // Initialize JSON coding
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
        
        // Initialize network monitoring
        self.networkMonitor = NetworkMonitor.shared
        self.networkMonitor.startMonitoring()
    }
    
    // MARK: - Audio Processing API
    
    /// Processes audio data with network quality adaptation
    /// - Parameters:
    ///   - audioData: Raw audio data for processing
    ///   - options: Audio processing options
    /// - Returns: Publisher emitting processed audio or error
    public func processAudio(audioData: Data, options: ProcessingOptions) -> AnyPublisher<ProcessedAudio, Error> {
        guard networkMonitor.isConnected else {
            return Fail(error: TALDError.networkError(
                code: "NETWORK_UNAVAILABLE",
                message: "Network connection unavailable",
                metadata: ErrorMetadata(
                    timestamp: Date(),
                    component: "APIClient",
                    additionalInfo: ["operation": "processAudio"]
                )
            )).eraseToAnyPublisher()
        }
        
        // Build request URL
        let endpoint = APIEndpoints.audioProcessing
        guard let url = URL(string: APIEndpoints.baseURL + endpoint) else {
            return Fail(error: TALDError.networkError(
                code: "INVALID_URL",
                message: "Invalid audio processing URL",
                metadata: ErrorMetadata(
                    timestamp: Date(),
                    component: "APIClient",
                    additionalInfo: ["endpoint": endpoint]
                )
            )).eraseToAnyPublisher()
        }
        
        // Build request with audio data
        let request = buildRequest(url: url, method: "POST", body: audioData)
        
        // Perform request with monitoring
        return performRequest(request, retryCount: 0)
            .tryMap { data -> ProcessedAudio in
                do {
                    let processed = try self.decoder.decode(ProcessedAudio.self, from: data)
                    return processed
                } catch {
                    throw TALDError.audioProcessingError(
                        code: "DECODE_ERROR",
                        message: "Failed to decode processed audio",
                        metadata: ErrorMetadata(
                            timestamp: Date(),
                            component: "APIClient",
                            additionalInfo: ["error": error.localizedDescription]
                        )
                    )
                }
            }
            .eraseToAnyPublisher()
    }
    
    /// Enhances audio using AI processing
    /// - Parameters:
    ///   - audioData: Audio data for enhancement
    ///   - options: AI enhancement options
    /// - Returns: Publisher emitting enhanced audio or error
    public func enhanceAudio(audioData: Data, options: EnhancementOptions) -> AnyPublisher<EnhancedAudio, Error> {
        guard networkMonitor.isConnected else {
            return Fail(error: TALDError.networkError(
                code: "NETWORK_UNAVAILABLE",
                message: "Network connection unavailable",
                metadata: ErrorMetadata(
                    timestamp: Date(),
                    component: "APIClient",
                    additionalInfo: ["operation": "enhanceAudio"]
                )
            )).eraseToAnyPublisher()
        }
        
        // Build request URL
        let endpoint = APIEndpoints.aiEnhancement
        guard let url = URL(string: APIEndpoints.baseURL + endpoint) else {
            return Fail(error: TALDError.networkError(
                code: "INVALID_URL",
                message: "Invalid AI enhancement URL",
                metadata: ErrorMetadata(
                    timestamp: Date(),
                    component: "APIClient",
                    additionalInfo: ["endpoint": endpoint]
                )
            )).eraseToAnyPublisher()
        }
        
        // Build request with enhancement options
        var requestData = audioData
        do {
            let optionsData = try encoder.encode(options)
            requestData.append(optionsData)
        } catch {
            return Fail(error: TALDError.aiProcessingError(
                code: "ENCODE_ERROR",
                message: "Failed to encode enhancement options",
                metadata: ErrorMetadata(
                    timestamp: Date(),
                    component: "APIClient",
                    additionalInfo: ["error": error.localizedDescription]
                )
            )).eraseToAnyPublisher()
        }
        
        let request = buildRequest(url: url, method: "POST", body: requestData)
        
        // Perform request with monitoring
        return performRequest(request, retryCount: 0)
            .tryMap { data -> EnhancedAudio in
                do {
                    let enhanced = try self.decoder.decode(EnhancedAudio.self, from: data)
                    return enhanced
                } catch {
                    throw TALDError.aiProcessingError(
                        code: "DECODE_ERROR",
                        message: "Failed to decode enhanced audio",
                        metadata: ErrorMetadata(
                            timestamp: Date(),
                            component: "APIClient",
                            additionalInfo: ["error": error.localizedDescription]
                        )
                    )
                }
            }
            .eraseToAnyPublisher()
    }
    
    /// Processes spatial audio with position data
    /// - Parameters:
    ///   - audioData: Audio data for spatial processing
    ///   - options: Spatial processing options
    /// - Returns: Publisher emitting spatial audio or error
    public func processSpatialAudio(audioData: Data, options: SpatialOptions) -> AnyPublisher<SpatialAudio, Error> {
        guard networkMonitor.isConnected else {
            return Fail(error: TALDError.networkError(
                code: "NETWORK_UNAVAILABLE",
                message: "Network connection unavailable",
                metadata: ErrorMetadata(
                    timestamp: Date(),
                    component: "APIClient",
                    additionalInfo: ["operation": "processSpatialAudio"]
                )
            )).eraseToAnyPublisher()
        }
        
        // Build request URL
        let endpoint = APIEndpoints.spatialProcessing
        guard let url = URL(string: APIEndpoints.baseURL + endpoint) else {
            return Fail(error: TALDError.networkError(
                code: "INVALID_URL",
                message: "Invalid spatial processing URL",
                metadata: ErrorMetadata(
                    timestamp: Date(),
                    component: "APIClient",
                    additionalInfo: ["endpoint": endpoint]
                )
            )).eraseToAnyPublisher()
        }
        
        // Build request with spatial options
        var requestData = audioData
        do {
            let optionsData = try encoder.encode(options)
            requestData.append(optionsData)
        } catch {
            return Fail(error: TALDError.spatialProcessingError(
                code: "ENCODE_ERROR",
                message: "Failed to encode spatial options",
                metadata: ErrorMetadata(
                    timestamp: Date(),
                    component: "APIClient",
                    additionalInfo: ["error": error.localizedDescription]
                )
            )).eraseToAnyPublisher()
        }
        
        let request = buildRequest(url: url, method: "POST", body: requestData)
        
        // Perform request with monitoring
        return performRequest(request, retryCount: 0)
            .tryMap { data -> SpatialAudio in
                do {
                    let spatial = try self.decoder.decode(SpatialAudio.self, from: data)
                    return spatial
                } catch {
                    throw TALDError.spatialProcessingError(
                        code: "DECODE_ERROR",
                        message: "Failed to decode spatial audio",
                        metadata: ErrorMetadata(
                            timestamp: Date(),
                            component: "APIClient",
                            additionalInfo: ["error": error.localizedDescription]
                        )
                    )
                }
            }
            .eraseToAnyPublisher()
    }
    
    // MARK: - Private Methods
    
    /// Performs network request with automatic retry and monitoring
    private func performRequest(_ request: URLRequest, retryCount: Int) -> AnyPublisher<Data, Error> {
        // Adapt timeout based on network quality
        var adaptedRequest = request
        adaptedRequest.timeoutInterval = networkMonitor.currentQuality.latencyThreshold
        
        return session.dataTaskPublisher(for: adaptedRequest)
            .tryMap { data, response -> Data in
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw TALDError.networkError(
                        code: "INVALID_RESPONSE",
                        message: "Invalid response type",
                        metadata: ErrorMetadata(
                            timestamp: Date(),
                            component: "APIClient",
                            additionalInfo: ["responseType": String(describing: type(of: response))]
                        )
                    )
                }
                
                guard (200...299).contains(httpResponse.statusCode) else {
                    throw TALDError.networkError(
                        code: "HTTP_ERROR",
                        message: "HTTP error \(httpResponse.statusCode)",
                        metadata: ErrorMetadata(
                            timestamp: Date(),
                            component: "APIClient",
                            additionalInfo: [
                                "statusCode": String(httpResponse.statusCode),
                                "url": request.url?.absoluteString ?? "unknown"
                            ]
                        )
                    )
                }
                
                return data
            }
            .tryCatch { error -> AnyPublisher<Data, Error> in
                // Implement retry logic for recoverable errors
                if retryCount < MAX_RETRY_ATTEMPTS,
                   let urlError = error as? URLError,
                   [.timedOut, .networkConnectionLost].contains(urlError.code) {
                    return self.performRequest(request, retryCount: retryCount + 1)
                        .delay(for: .seconds(pow(2.0, Double(retryCount))), scheduler: REQUEST_QUEUE)
                        .eraseToAnyPublisher()
                }
                throw error
            }
            .eraseToAnyPublisher()
    }
    
    /// Builds URLRequest with security headers and monitoring configuration
    private func buildRequest(url: URL, method: String, body: Data? = nil) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = API_TIMEOUT
        
        // Set security headers
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(Bundle.main.bundleIdentifier, forHTTPHeaderField: "X-Client-ID")
        request.setValue(APP_VERSION, forHTTPHeaderField: "X-Client-Version")
        
        // Set network quality headers
        request.setValue(networkMonitor.currentQuality.rawValue, forHTTPHeaderField: "X-Network-Quality")
        
        if let body = body {
            request.httpBody = body
        }
        
        return request
    }
}