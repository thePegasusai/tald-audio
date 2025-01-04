//
// Logger.swift
// TALD UNIA
//
// Core logging system for the TALD UNIA audio system
// Foundation version: macOS 13.0+
//

import Foundation // macOS 13.0+
import os.log // macOS 13.0+

// MARK: - Constants
private let LOG_DATE_FORMAT: String = "yyyy-MM-dd HH:mm:ss.SSS"
private let DEFAULT_LOG_DIRECTORY: String = "~/Library/Logs/TALDUnia/"
private let LOG_SUBSYSTEM: String = "com.tald.unia.logger"
private let MAX_LOG_SIZE: Int = 10_485_760 // 10MB

// MARK: - Log Severity
public enum LogSeverity: String {
    case debug = "DEBUG"
    case info = "INFO"
    case warning = "WARNING"
    case error = "ERROR"
    case critical = "CRITICAL"
    
    var osLogType: OSLogType {
        switch self {
        case .debug: return .debug
        case .info: return .info
        case .warning: return .default
        case .error: return .error
        case .critical: return .fault
        }
    }
    
    var emoji: String {
        switch self {
        case .debug: return "🔍"
        case .info: return "ℹ️"
        case .warning: return "⚠️"
        case .error: return "❌"
        case .critical: return "🚨"
        }
    }
}

// MARK: - Logger
public final class Logger {
    // MARK: - Singleton
    public static let shared = Logger()
    
    // MARK: - Properties
    private let fileHandle: FileHandle
    private let osLog: OSLog
    private let loggingQueue: DispatchQueue
    private let config: LogConfig
    private var logBuffer: Data
    private let isDebugMode: Bool
    private let dateFormatter: DateFormatter
    
    // MARK: - Initialization
    private init() {
        self.loggingQueue = DispatchQueue(label: "com.tald.unia.logger", qos: .utility)
        self.logBuffer = Data(capacity: 1024)
        self.config = Configuration.shared.logConfig
        self.isDebugMode = DEBUG_MODE
        
        // Configure date formatter
        self.dateFormatter = DateFormatter()
        dateFormatter.dateFormat = LOG_DATE_FORMAT
        
        // Setup log directory
        let logPath = (DEFAULT_LOG_DIRECTORY as NSString).expandingTildeInPath
        try? FileManager.default.createDirectory(
            atPath: logPath,
            withIntermediateDirectories: true,
            attributes: nil
        )
        
        // Initialize file handle
        let logFile = URL(fileURLWithPath: logPath).appendingPathComponent("tald_unia.log")
        if !FileManager.default.fileExists(atPath: logFile.path) {
            FileManager.default.createFile(atPath: logFile.path, contents: nil)
        }
        
        // Open file handle
        guard let handle = try? FileHandle(forWritingTo: logFile) else {
            fatalError("Failed to create log file handle")
        }
        self.fileHandle = handle
        
        // Initialize OS Log
        self.osLog = OSLog(subsystem: LOG_SUBSYSTEM, category: "default")
        
        // Setup log rotation monitoring
        setupLogRotation()
    }
    
    deinit {
        try? fileHandle.close()
    }
    
    // MARK: - Public Methods
    public func log(
        _ message: String,
        severity: LogSeverity = .info,
        context: String = "",
        metadata: [String: Any]? = nil
    ) {
        guard config.enabled else { return }
        
        loggingQueue.async { [weak self] in
            guard let self = self else { return }
            
            let formattedMessage = self.formatLogMessage(
                message: message,
                severity: severity,
                context: context,
                metadata: metadata
            )
            
            // Write to file
            if let data = formattedMessage.data(using: .utf8) {
                self.writeToFile(data)
            }
            
            // Send to system log
            os_log(
                "%{public}@",
                log: self.osLog,
                type: severity.osLogType,
                formattedMessage
            )
            
            // Print to console in debug mode
            if self.isDebugMode {
                print(formattedMessage)
            }
            
            // Check log rotation
            self.checkLogRotation()
        }
    }
    
    public func error(
        _ error: Error,
        context: String,
        metadata: [String: Any]? = nil
    ) {
        var errorMetadata = metadata ?? [:]
        
        if let taldError = error as? TALDError {
            errorMetadata["errorCode"] = taldError.errorCode
            errorMetadata["severity"] = taldError.severity.description
            errorMetadata["stackTrace"] = Thread.callStackSymbols.joined(separator: "\n")
        }
        
        log(
            error.localizedDescription,
            severity: .error,
            context: context,
            metadata: errorMetadata
        )
    }
    
    // MARK: - Private Methods
    private func formatLogMessage(
        message: String,
        severity: LogSeverity,
        context: String,
        metadata: [String: Any]?
    ) -> String {
        let timestamp = dateFormatter.string(from: Date())
        let processInfo = "[\(ProcessInfo.processInfo.processIdentifier)]"
        let threadInfo = "[Thread: \(Thread.current.description)]"
        
        var formattedMessage = "\(timestamp) \(severity.emoji) \(severity.rawValue) \(processInfo) \(threadInfo)"
        
        if !context.isEmpty {
            formattedMessage += " [\(context)]"
        }
        
        formattedMessage += ": \(message)"
        
        if let metadata = metadata {
            let metadataString = try? JSONSerialization.data(
                withJSONObject: metadata,
                options: [.prettyPrinted]
            )
            if let metadataString = metadataString {
                formattedMessage += "\nMetadata: \(String(data: metadataString, encoding: .utf8) ?? "")"
            }
        }
        
        return formattedMessage + "\n"
    }
    
    private func writeToFile(_ data: Data) {
        do {
            try fileHandle.seekToEnd()
            try fileHandle.write(contentsOf: data)
        } catch {
            os_log(
                "Failed to write to log file: %{public}@",
                log: osLog,
                type: .error,
                error.localizedDescription
            )
        }
    }
    
    private func setupLogRotation() {
        loggingQueue.async { [weak self] in
            guard let self = self else { return }
            
            let logPath = (DEFAULT_LOG_DIRECTORY as NSString).expandingTildeInPath
            let logFile = URL(fileURLWithPath: logPath).appendingPathComponent("tald_unia.log")
            
            do {
                let attributes = try FileManager.default.attributesOfItem(atPath: logFile.path)
                let fileSize = attributes[.size] as? Int ?? 0
                
                if fileSize > MAX_LOG_SIZE {
                    try self.rotateLog()
                }
            } catch {
                os_log(
                    "Failed to check log file size: %{public}@",
                    log: self.osLog,
                    type: .error,
                    error.localizedDescription
                )
            }
        }
    }
    
    private func checkLogRotation() {
        do {
            let currentOffset = try fileHandle.offset()
            if currentOffset > MAX_LOG_SIZE {
                try rotateLog()
            }
        } catch {
            os_log(
                "Failed to check log rotation: %{public}@",
                log: osLog,
                type: .error,
                error.localizedDescription
            )
        }
    }
    
    private func rotateLog() throws {
        let logPath = (DEFAULT_LOG_DIRECTORY as NSString).expandingTildeInPath
        let logFile = URL(fileURLWithPath: logPath).appendingPathComponent("tald_unia.log")
        let backupFile = URL(fileURLWithPath: logPath).appendingPathComponent("tald_unia.log.\(Date().timeIntervalSince1970)")
        
        try fileHandle.close()
        try FileManager.default.moveItem(at: logFile, to: backupFile)
        FileManager.default.createFile(atPath: logFile.path, contents: nil)
        
        guard let newHandle = try? FileHandle(forWritingTo: logFile) else {
            throw TALDError.configurationError(
                code: "LOG_ROTATION_FAILED",
                message: "Failed to create new log file handle",
                metadata: ErrorMetadata(
                    timestamp: Date(),
                    component: "Logger",
                    additionalInfo: ["path": logFile.path]
                )
            )
        }
        
        self.fileHandle = newHandle
        
        // Clean up old log files
        cleanupOldLogs()
    }
    
    private func cleanupOldLogs() {
        let logPath = (DEFAULT_LOG_DIRECTORY as NSString).expandingTildeInPath
        let fileManager = FileManager.default
        
        do {
            let files = try fileManager.contentsOfDirectory(atPath: logPath)
            let logFiles = files.filter { $0.hasPrefix("tald_unia.log.") }
                .sorted(by: >)
            
            if logFiles.count > config.maxFileCount {
                let filesToDelete = logFiles[config.maxFileCount...]
                for file in filesToDelete {
                    try? fileManager.removeItem(atPath: logPath + file)
                }
            }
        } catch {
            os_log(
                "Failed to cleanup old logs: %{public}@",
                log: osLog,
                type: .error,
                error.localizedDescription
            )
        }
    }
}