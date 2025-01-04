//
// WebSocketClient.swift
// TALD UNIA
//
// Advanced WebSocket client for real-time audio streaming with network quality monitoring
// Foundation version: macOS 13.0+
//

import Foundation // macOS 13.0+

// MARK: - Constants
private let WEBSOCKET_QUEUE = DispatchQueue(label: "com.tald.unia.websocket", qos: .userInteractive)
private let MAX_RECONNECT_ATTEMPTS: Int = 5
private let RECONNECT_DELAY: TimeInterval = 2.0
private let MAX_MESSAGE_SIZE: Int = 32768
private let MIN_BUFFER_SIZE: Int = 1024
private let MAX_BUFFER_SIZE: Int = 8192
private let LATENCY_THRESHOLD: TimeInterval = 0.010 // 10ms max latency

// MARK: - Audio Stream Delegate Protocol
@objc public protocol AudioStreamDelegate: AnyObject {
    func didReceiveAudioData(_ data: Data, config: AudioConfig, metrics: QualityMetrics)
    func didUpdateStreamStatus(_ status: AudioStreamStatus, quality: NetworkQualityStatus)
    func didEncounterError(_ error: Error)
}

// MARK: - Quality Metrics
public struct QualityMetrics {
    let latency: TimeInterval
    let jitter: TimeInterval
    let bandwidth: Double
    let packetLoss: Double
    let bufferHealth: Double
    let timestamp: Date
}

// MARK: - Audio Stream Status
public enum AudioStreamStatus {
    case connecting
    case connected
    case streaming
    case disconnected
    case error
}

// MARK: - WebSocket Client
@objc public final class WebSocketClient {
    // MARK: - Properties
    private var webSocketTask: URLSessionWebSocketTask?
    private let serverURL: URL
    private var isConnected: Bool = false
    private var reconnectAttempts: Int = 0
    private weak var delegate: AudioStreamDelegate?
    private let networkMonitor = NetworkMonitor.shared
    private let processingQueue = WEBSOCKET_QUEUE
    private var currentBufferSize: Int = MIN_BUFFER_SIZE
    private var lastMessageTimestamp: Date = Date()
    
    // MARK: - Initialization
    public init(url: URL, delegate: AudioStreamDelegate) {
        self.serverURL = url
        self.delegate = delegate
        setupNetworkMonitoring()
    }
    
    // MARK: - Private Methods
    private func setupNetworkMonitoring() {
        networkMonitor.startMonitoring()
        networkMonitor.setQualityDelegate(self)
    }
    
    private func createURLRequest() -> URLRequest {
        var request = URLRequest(url: serverURL)
        request.timeoutInterval = NetworkConstants.TIMEOUT_INTERVAL
        request.setValue("audio/raw", forHTTPHeaderField: "Content-Type")
        request.setValue("v1", forHTTPHeaderField: "X-Protocol-Version")
        request.setValue("gzip", forHTTPHeaderField: "Accept-Encoding")
        return request
    }
    
    private func setupWebSocketTask() {
        let session = URLSession(configuration: .default)
        webSocketTask = session.webSocketTask(with: createURLRequest())
        webSocketTask?.maximumMessageSize = MAX_MESSAGE_SIZE
    }
    
    private func startReceiveMessageLoop() {
        webSocketTask?.receive { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .success(let message):
                self.handleReceivedMessage(message)
                self.startReceiveMessageLoop()
                
            case .failure(let error):
                self.handleWebSocketError(error)
            }
        }
    }
    
    private func handleReceivedMessage(_ message: URLSessionWebSocketTask.Message) {
        switch message {
        case .data(let data):
            processAudioData(data)
            
        case .string(let string):
            processControlMessage(string)
            
        @unknown default:
            Logger.shared.error(
                TALDError.networkError(
                    code: "UNKNOWN_MESSAGE_TYPE",
                    message: "Received unknown WebSocket message type",
                    metadata: ErrorMetadata(
                        timestamp: Date(),
                        component: "WebSocketClient",
                        additionalInfo: ["messageType": String(describing: message)]
                    )
                ),
                context: "WebSocketClient"
            )
        }
    }
    
    private func processAudioData(_ data: Data) {
        let currentTime = Date()
        let latency = currentTime.timeIntervalSince(lastMessageTimestamp)
        lastMessageTimestamp = currentTime
        
        let metrics = QualityMetrics(
            latency: latency,
            jitter: calculateJitter(),
            bandwidth: calculateBandwidth(dataSize: data.count),
            packetLoss: calculatePacketLoss(),
            bufferHealth: Double(currentBufferSize) / Double(MAX_BUFFER_SIZE),
            timestamp: currentTime
        )
        
        processingQueue.async { [weak self] in
            guard let self = self else { return }
            self.delegate?.didReceiveAudioData(data, config: AudioConfig(), metrics: metrics)
        }
    }
    
    private func processControlMessage(_ message: String) {
        guard let data = message.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }
        
        // Handle control messages (e.g., buffer size adjustments, quality updates)
        if let bufferSize = json["bufferSize"] as? Int {
            adjustBufferSize(bufferSize)
        }
    }
    
    private func adjustBufferSize(_ newSize: Int) {
        let clampedSize = min(max(newSize, MIN_BUFFER_SIZE), MAX_BUFFER_SIZE)
        currentBufferSize = clampedSize
    }
    
    private func calculateJitter() -> TimeInterval {
        // Implement jitter calculation based on message timing
        return 0.001 // Placeholder
    }
    
    private func calculateBandwidth(dataSize: Int) -> Double {
        // Implement bandwidth calculation
        return Double(dataSize * 8) // bits per second
    }
    
    private func calculatePacketLoss() -> Double {
        // Implement packet loss calculation
        return 0.001 // Placeholder
    }
    
    private func handleWebSocketError(_ error: Error) {
        Logger.shared.error(
            TALDError.networkError(
                code: "WEBSOCKET_ERROR",
                message: error.localizedDescription,
                metadata: ErrorMetadata(
                    timestamp: Date(),
                    component: "WebSocketClient",
                    additionalInfo: ["url": serverURL.absoluteString]
                )
            ),
            context: "WebSocketClient"
        )
        
        delegate?.didEncounterError(error)
        attemptReconnection()
    }
    
    private func attemptReconnection() {
        guard reconnectAttempts < MAX_RECONNECT_ATTEMPTS else {
            delegate?.didUpdateStreamStatus(.error, quality: networkMonitor.currentQuality)
            return
        }
        
        reconnectAttempts += 1
        DispatchQueue.global().asyncAfter(deadline: .now() + RECONNECT_DELAY) { [weak self] in
            self?.connect()
        }
    }
    
    // MARK: - Public Methods
    public func connect() {
        delegate?.didUpdateStreamStatus(.connecting, quality: networkMonitor.currentQuality)
        
        setupWebSocketTask()
        webSocketTask?.resume()
        startReceiveMessageLoop()
        
        isConnected = true
        reconnectAttempts = 0
        delegate?.didUpdateStreamStatus(.connected, quality: networkMonitor.currentQuality)
    }
    
    public func disconnect() {
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        isConnected = false
        delegate?.didUpdateStreamStatus(.disconnected, quality: networkMonitor.currentQuality)
    }
    
    public func sendAudioData(_ data: Data, config: AudioConfig) {
        guard isConnected else { return }
        
        let message = URLSessionWebSocketTask.Message.data(data)
        webSocketTask?.send(message) { [weak self] error in
            if let error = error {
                self?.handleWebSocketError(error)
            }
        }
    }
}

// MARK: - NetworkQualityDelegate Extension
extension WebSocketClient: NetworkQualityDelegate {
    public func networkQualityDidChange(_ quality: NetworkQualityStatus) {
        delegate?.didUpdateStreamStatus(isConnected ? .streaming : .disconnected, quality: quality)
        
        // Adjust buffer size based on network quality
        switch quality {
        case .excellent:
            adjustBufferSize(MIN_BUFFER_SIZE)
        case .good:
            adjustBufferSize(MIN_BUFFER_SIZE * 2)
        case .fair:
            adjustBufferSize(MIN_BUFFER_SIZE * 4)
        case .poor:
            adjustBufferSize(MAX_BUFFER_SIZE)
        }
    }
    
    public func audioStreamingMetricsDidUpdate(_ metrics: AudioStreamingMetrics) {
        // Update streaming metrics if needed
    }
}