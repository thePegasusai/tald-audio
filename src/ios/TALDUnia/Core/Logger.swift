// Foundation v6.0+, os.log v2.0+
import Foundation
import os.log

/// Log severity levels for the TALD UNIA system
@objc public enum LogLevel: Int {
    case debug = 0
    case info = 1
    case warning = 2
    case error = 3
    case fatal = 4
    
    var osLogType: OSLogType {
        switch self {
        case .debug: return .debug
        case .info: return .info
        case .warning: return .default
        case .error: return .error
        case .fatal: return .fault
        }
    }
}

/// System components for log categorization
@objc public enum Subsystem: Int {
    case audio
    case ai
    case spatial
    case network
    case hardware
    
    var identifier: String {
        switch self {
        case .audio: return "audio"
        case .ai: return "ai"
        case .spatial: return "spatial"
        case .network: return "network"
        case .hardware: return "hardware"
        }
    }
}

/// Performance metrics tracking for system monitoring
private struct PerformanceMetrics {
    var audioQuality: Double = 0.0
    var processingLoad: Double = 0.0
    var powerEfficiency: Double = 0.0
    var latency: TimeInterval = 0.0
    
    mutating func update(metric: String, value: Double) {
        switch metric {
        case "audioQuality": audioQuality = value
        case "processingLoad": processingLoad = value
        case "powerEfficiency": powerEfficiency = value
        case "latency": latency = value
        default: break
        }
    }
}

/// Thread-safe logging manager for the TALD UNIA system
@objc public final class Logger {
    
    // MARK: - Shared Instance
    
    public static let shared = Logger()
    
    // MARK: - Properties
    
    private let logQueue = DispatchQueue(label: "com.taldunia.logger", qos: .utility)
    private let dateFormatter = ISO8601DateFormatter()
    private let osLog: OSLog
    private var logFileHandle: FileHandle?
    private let maxLogFileSize: Int64 = 10 * 1024 * 1024 // 10MB
    private let logDirectory: URL
    private var performanceMetrics = PerformanceMetrics()
    
    // MARK: - Initialization
    
    private init() {
        // Configure OS logging
        osLog = OSLog(subsystem: "com.taldunia.audio", category: "TALD_UNIA")
        
        // Setup log directory
        logDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs")
        
        // Create log directory if needed
        try? FileManager.default.createDirectory(at: logDirectory, withIntermediateDirectories: true)
        
        // Initialize log file
        let logFile = logDirectory.appendingPathComponent("taldunia.log")
        if !FileManager.default.fileExists(atPath: logFile.path) {
            FileManager.default.createFile(atPath: logFile.path, contents: nil)
        }
        logFileHandle = try? FileHandle(forWritingTo: logFile)
        
        // Set initial log level based on environment
        configureLogLevel(for: Configuration.shared.environment)
    }
    
    deinit {
        logFileHandle?.closeFile()
    }
    
    // MARK: - Public Methods
    
    /// Logs a message with specified level and subsystem
    @discardableResult
    public func log(
        _ message: String,
        level: LogLevel = .info,
        subsystem: Subsystem = .audio,
        metadata: [String: Any]? = nil
    ) -> Bool {
        logQueue.sync {
            let timestamp = dateFormatter.string(from: Date())
            let formattedMessage = "[\(timestamp)][\(subsystem.identifier.uppercased())][\(level)] \(message)"
            
            // Log to OS system
            os_log("%{public}@", log: osLog, type: level.osLogType, formattedMessage)
            
            // Log to file
            if let data = (formattedMessage + "\n").data(using: .utf8) {
                logFileHandle?.write(data)
            }
            
            // Check for log rotation
            if let size = try? logFileHandle?.seekToEnd(), size > maxLogFileSize {
                rotateLogFiles()
            }
            
            // Update metrics if provided
            if let metrics = metadata?["metrics"] as? [String: Double] {
                metrics.forEach { performanceMetrics.update(metric: $0.key, value: $0.value) }
            }
            
            return true
        }
    }
    
    /// Enhanced error logging with full context
    public func logError(_ error: Error, subsystem: Subsystem = .audio, isFatal: Bool = false) {
        let level: LogLevel = isFatal ? .fatal : .error
        
        if let appError = error as? AppError {
            let context = appError.errorContext
            let metadata: [String: Any] = [
                "file": context.file,
                "function": context.function,
                "line": context.line,
                "additionalInfo": context.additionalInfo ?? [:]
            ]
            
            log(appError.localizedDescription, level: level, subsystem: subsystem, metadata: metadata)
        } else {
            log(error.localizedDescription, level: level, subsystem: subsystem)
        }
    }
    
    /// Configures logging level based on environment
    public func configureLogLevel(for environment: Environment) {
        logQueue.sync {
            switch environment {
            case .development:
                os_log_debug_enabled(osLog)
            case .staging:
                os_log_debug_enabled(osLog)
            case .production:
                os_log_debug_enabled(false)
            }
        }
    }
    
    // MARK: - Private Methods
    
    /// Manages log file rotation with compression
    private func rotateLogFiles() -> Bool {
        guard let currentLog = logFileHandle else { return false }
        
        do {
            // Close current log file
            currentLog.closeFile()
            
            // Create archive name with timestamp
            let timestamp = dateFormatter.string(from: Date())
            let archiveName = "taldunia_\(timestamp).log"
            let archivePath = logDirectory.appendingPathComponent(archiveName)
            
            // Move current log to archive
            let currentLogPath = logDirectory.appendingPathComponent("taldunia.log")
            try FileManager.default.moveItem(at: currentLogPath, to: archivePath)
            
            // Create new log file
            FileManager.default.createFile(atPath: currentLogPath.path, contents: nil)
            logFileHandle = try FileHandle(forWritingTo: currentLogPath)
            
            // Clean up old archives (keep last 5)
            let archives = try FileManager.default.contentsOfDirectory(at: logDirectory,
                                                                     includingPropertiesForKeys: [.creationDateKey])
            let oldArchives = archives.filter { $0.lastPathComponent.hasPrefix("taldunia_") }
                .sorted { (url1, url2) -> Bool in
                    let date1 = try? url1.resourceValues(forKeys: [.creationDateKey]).creationDate
                    let date2 = try? url2.resourceValues(forKeys: [.creationDateKey]).creationDate
                    return date1 ?? Date() > date2 ?? Date()
                }
                .dropFirst(5)
            
            try oldArchives.forEach { try FileManager.default.removeItem(at: $0) }
            
            return true
        } catch {
            os_log("Failed to rotate log files: %{public}@",
                  log: osLog,
                  type: .error,
                  error.localizedDescription)
            return false
        }
    }
}