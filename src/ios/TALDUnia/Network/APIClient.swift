// Foundation v6.0+, Combine v2.0+, Security v2.0+, Network v2.0+
import Foundation
import Combine
import Security
import Network

/// Enhanced API client for TALD UNIA audio system with comprehensive security, monitoring and streaming capabilities
@available(iOS 13.0, *)
public final class APIClient {
    
    // MARK: - Shared Instance
    
    /// Shared API client instance
    public static let shared = APIClient()
    
    // MARK: - Properties
    
    private let session: URLSession
    private let baseURL: URL
    private let networkMonitor = NetworkMonitor.shared
    private var cancellables = Set<AnyCancellable>()
    
    /// Security configuration for API communications
    private let securityConfiguration: SecurityConfiguration
    
    /// Connection pool for request management
    private let connectionPool: ConnectionPool
    
    /// Priority-based request queue
    private let requestQueue: PriorityQueue<URLRequest>
    
    /// API metrics collection
    public private(set) var metrics: APIMetrics
    
    /// Retry policy for failed requests
    private let retryPolicy: RetryPolicy
    
    // MARK: - Initialization
    
    private init() {
        // Initialize base URL from configuration
        guard let url = URL(string: NetworkConstants.baseURL) else {
            fatalError("Invalid base URL configuration")
        }
        self.baseURL = url
        
        // Configure security
        self.securityConfiguration = SecurityConfiguration(
            minimumTLSVersion: .TLSv13,
            certificatePinningEnabled: true,
            certificateHashes: Configuration.shared.networkSettings.certificateHashes
        )
        
        // Configure session
        let configuration = URLSessionConfiguration.ephemeral
        configuration.tlsMinimumSupportedProtocolVersion = .TLSv13
        configuration.tlsMaximumSupportedProtocolVersion = .TLSv13
        configuration.httpAdditionalHeaders = defaultHeaders
        configuration.timeoutIntervalForRequest = NetworkConstants.timeoutInterval
        configuration.waitsForConnectivity = true
        
        self.session = URLSession(
            configuration: configuration,
            delegate: SecurityDelegate(securityConfiguration),
            delegateQueue: nil
        )
        
        // Initialize connection management
        self.connectionPool = ConnectionPool(
            maxConnections: NetworkConstants.connectionPoolSize
        )
        
        // Initialize request queue
        self.requestQueue = PriorityQueue<URLRequest>()
        
        // Initialize metrics collection
        self.metrics = APIMetrics()
        
        // Configure retry policy
        self.retryPolicy = RetryPolicy(
            maxRetries: NetworkConstants.maxRetryCount,
            backoffStrategy: .exponential(initial: 0.5)
        )
        
        // Setup network monitoring
        setupNetworkMonitoring()
    }
    
    // MARK: - Public Methods
    
    /// Performs a type-safe API request with comprehensive error handling and monitoring
    public func request<T: Decodable>(
        _ endpoint: APIEndpoint,
        body: Encodable? = nil,
        priority: RequestPriority = .normal
    ) -> AnyPublisher<T, RequestError> {
        guard networkMonitor.status.value != .disconnected else {
            return Fail(error: RequestError.networkError(NetworkError.noConnection))
                .eraseToAnyPublisher()
        }
        
        return Future { [weak self] promise in
            guard let self = self else { return }
            
            // Prepare request
            let request = try self.prepareRequest(
                endpoint: endpoint,
                body: body,
                priority: priority
            )
            
            // Add to connection pool
            self.connectionPool.acquire { connection in
                // Execute request with retry policy
                self.executeRequest(
                    request,
                    connection: connection,
                    priority: priority
                ) { result in
                    switch result {
                    case .success(let data):
                        do {
                            let decoder = JSONDecoder()
                            let response = try decoder.decode(T.self, from: data)
                            promise(.success(response))
                        } catch {
                            promise(.failure(.decodingError(error)))
                        }
                    case .failure(let error):
                        promise(.failure(error))
                    }
                    
                    // Release connection
                    self.connectionPool.release(connection)
                }
            }
        }
        .handleEvents(
            receiveSubscription: { [weak self] _ in
                self?.metrics.incrementRequestCount()
            },
            receiveCompletion: { [weak self] completion in
                if case .failure(let error) = completion {
                    self?.metrics.recordError(error)
                }
            }
        )
        .eraseToAnyPublisher()
    }
    
    /// Establishes secure audio streaming session with quality monitoring
    public func streamAudio(
        config: AudioStreamConfig,
        priority: StreamPriority = .realtime
    ) -> AnyPublisher<AudioStreamSession, StreamError> {
        return Future { [weak self] promise in
            guard let self = self else { return }
            
            // Validate network capacity
            guard self.networkMonitor.quality.value != .critical else {
                promise(.failure(.insufficientBandwidth))
                return
            }
            
            // Setup secure WebSocket connection
            let streamSession = AudioStreamSession(
                config: config,
                security: self.securityConfiguration,
                priority: priority
            )
            
            // Configure stream monitoring
            streamSession.metricsPublisher
                .sink { [weak self] metrics in
                    self?.metrics.recordStreamMetrics(metrics)
                }
                .store(in: &self.cancellables)
            
            // Start streaming
            streamSession.start { result in
                switch result {
                case .success:
                    promise(.success(streamSession))
                case .failure(let error):
                    promise(.failure(error))
                }
            }
        }
        .eraseToAnyPublisher()
    }
    
    // MARK: - Private Methods
    
    private func prepareRequest(
        endpoint: APIEndpoint,
        body: Encodable?,
        priority: RequestPriority
    ) throws -> URLRequest {
        var components = URLComponents()
        components.path = endpoint.path
        
        guard let url = components.url(relativeTo: baseURL) else {
            throw RequestError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = endpoint.method
        request.setValue(priority.rawValue, forHTTPHeaderField: "X-Request-Priority")
        
        if let body = body {
            let encoder = JSONEncoder()
            request.httpBody = try encoder.encode(body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        
        if endpoint.requiresAuth {
            request.setValue(
                "Bearer \(AuthManager.shared.currentToken)",
                forHTTPHeaderField: "Authorization"
            )
        }
        
        return request
    }
    
    private func executeRequest(
        _ request: URLRequest,
        connection: Connection,
        priority: RequestPriority,
        completion: @escaping (Result<Data, RequestError>) -> Void
    ) {
        let startTime = Date()
        
        let task = session.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }
            
            let duration = Date().timeIntervalSince(startTime)
            self.metrics.recordRequestDuration(duration)
            
            if let error = error {
                if self.retryPolicy.shouldRetry(error: error) {
                    self.retryRequest(
                        request,
                        connection: connection,
                        priority: priority,
                        completion: completion
                    )
                    return
                }
                completion(.failure(.networkError(error)))
                return
            }
            
            guard let httpResponse = response as? HTTPURLResponse else {
                completion(.failure(.invalidResponse(-1)))
                return
            }
            
            switch httpResponse.statusCode {
            case 200...299:
                guard let data = data else {
                    completion(.failure(.invalidResponse(httpResponse.statusCode)))
                    return
                }
                completion(.success(data))
                
            case 401:
                completion(.failure(.unauthorized))
                
            case 429:
                completion(.failure(.rateLimited))
                
            default:
                completion(.failure(.invalidResponse(httpResponse.statusCode)))
            }
        }
        
        requestQueue.enqueue(task, priority: priority)
    }
    
    private func retryRequest(
        _ request: URLRequest,
        connection: Connection,
        priority: RequestPriority,
        completion: @escaping (Result<Data, RequestError>) -> Void
    ) {
        retryPolicy.executeWithRetry { [weak self] in
            self?.executeRequest(
                request,
                connection: connection,
                priority: priority,
                completion: completion
            )
        }
    }
    
    private func setupNetworkMonitoring() {
        networkMonitor.status
            .sink { [weak self] status in
                self?.metrics.recordNetworkStatus(status)
            }
            .store(in: &cancellables)
        
        networkMonitor.quality
            .sink { [weak self] quality in
                self?.metrics.recordNetworkQuality(quality)
            }
            .store(in: &cancellables)
    }
    
    private var defaultHeaders: [String: String] {
        [
            "User-Agent": "TALD-UNIA/\(Configuration.shared.configVersion)",
            "Accept": "application/json",
            "X-Client-Version": Configuration.shared.configVersion,
            "X-Device-Model": UIDevice.current.model,
            "X-OS-Version": UIDevice.current.systemVersion
        ]
    }
}

// MARK: - Supporting Types

private struct SecurityConfiguration {
    let minimumTLSVersion: SSLProtocol
    let certificatePinningEnabled: Bool
    let certificateHashes: [String]
}

private class SecurityDelegate: NSObject, URLSessionDelegate {
    private let configuration: SecurityConfiguration
    
    init(_ configuration: SecurityConfiguration) {
        self.configuration = configuration
        super.init()
    }
    
    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard let serverTrust = challenge.protectionSpace.serverTrust,
              let certificate = SecTrustGetCertificateAtIndex(serverTrust, 0) else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }
        
        if configuration.certificatePinningEnabled {
            let certificateHash = calculateCertificateHash(certificate)
            guard configuration.certificateHashes.contains(certificateHash) else {
                completionHandler(.cancelAuthenticationChallenge, nil)
                return
            }
        }
        
        let credential = URLCredential(trust: serverTrust)
        completionHandler(.useCredential, credential)
    }
    
    private func calculateCertificateHash(_ certificate: SecCertificate) -> String {
        // Implementation of certificate hash calculation
        return ""
    }
}

private class Connection {
    let identifier: UUID
    var isInUse: Bool
    
    init(identifier: UUID = UUID()) {
        self.identifier = identifier
        self.isInUse = false
    }
}

private class ConnectionPool {
    private let maxConnections: Int
    private var connections: [Connection]
    private let queue = DispatchQueue(label: "com.taldunia.connectionpool")
    
    init(maxConnections: Int) {
        self.maxConnections = maxConnections
        self.connections = []
    }
    
    func acquire(completion: @escaping (Connection) -> Void) {
        queue.async { [weak self] in
            guard let self = self else { return }
            
            if let availableConnection = self.connections.first(where: { !$0.isInUse }) {
                availableConnection.isInUse = true
                completion(availableConnection)
                return
            }
            
            if self.connections.count < self.maxConnections {
                let newConnection = Connection()
                newConnection.isInUse = true
                self.connections.append(newConnection)
                completion(newConnection)
                return
            }
            
            // Wait for available connection
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.1) {
                self.acquire(completion: completion)
            }
        }
    }
    
    func release(_ connection: Connection) {
        queue.async {
            connection.isInUse = false
        }
    }
}

private class RetryPolicy {
    enum BackoffStrategy {
        case constant(TimeInterval)
        case exponential(initial: TimeInterval)
    }
    
    private let maxRetries: Int
    private let backoffStrategy: BackoffStrategy
    private var currentRetry: Int = 0
    
    init(maxRetries: Int, backoffStrategy: BackoffStrategy) {
        self.maxRetries = maxRetries
        self.backoffStrategy = backoffStrategy
    }
    
    func shouldRetry(error: Error) -> Bool {
        return currentRetry < maxRetries
    }
    
    func executeWithRetry(_ operation: @escaping () -> Void) {
        currentRetry += 1
        
        let delay: TimeInterval = {
            switch backoffStrategy {
            case .constant(let interval):
                return interval
            case .exponential(let initial):
                return initial * pow(2.0, Double(currentRetry - 1))
            }
        }()
        
        DispatchQueue.global().asyncAfter(deadline: .now() + delay) {
            operation()
        }
    }
}

public class APIMetrics {
    private var requestCount: Int = 0
    private var errorCount: Int = 0
    private var averageRequestDuration: TimeInterval = 0
    private var networkStatusHistory: [NetworkStatus] = []
    private var networkQualityHistory: [NetworkQuality] = []
    private let metricsQueue = DispatchQueue(label: "com.taldunia.metrics")
    
    func incrementRequestCount() {
        metricsQueue.async {
            self.requestCount += 1
        }
    }
    
    func recordError(_ error: RequestError) {
        metricsQueue.async {
            self.errorCount += 1
        }
    }
    
    func recordRequestDuration(_ duration: TimeInterval) {
        metricsQueue.async {
            self.averageRequestDuration = (self.averageRequestDuration * Double(self.requestCount) + duration) / Double(self.requestCount + 1)
        }
    }
    
    func recordNetworkStatus(_ status: NetworkStatus) {
        metricsQueue.async {
            self.networkStatusHistory.append(status)
            if self.networkStatusHistory.count > 100 {
                self.networkStatusHistory.removeFirst()
            }
        }
    }
    
    func recordNetworkQuality(_ quality: NetworkQuality) {
        metricsQueue.async {
            self.networkQualityHistory.append(quality)
            if self.networkQualityHistory.count > 100 {
                self.networkQualityHistory.removeFirst()
            }
        }
    }
    
    func recordStreamMetrics(_ metrics: StreamMetrics) {
        metricsQueue.async {
            // Record streaming-specific metrics
        }
    }
}