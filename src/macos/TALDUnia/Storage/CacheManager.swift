//
// CacheManager.swift
// TALD UNIA
//
// High-performance hybrid caching system with monitoring and cleanup mechanisms
// Foundation version: macOS 13.0+
//

import Foundation // macOS 13.0+

// MARK: - Cache Constants
private let DEFAULT_TTL: TimeInterval = 3600
private let AUDIO_CACHE_PREFIX = "audio:"
private let PROFILE_CACHE_PREFIX = "profile:"
private let SETTINGS_CACHE_PREFIX = "settings:"
private let MAX_CACHE_SIZE: Int64 = 1024 * 1024 * 512 // 512MB
private let CLEANUP_INTERVAL: TimeInterval = 300 // 5 minutes
private let MAX_MEMORY_CACHE_COUNT = 1000
private let CHECKSUM_KEY_SUFFIX = ":checksum"

// MARK: - Cache Statistics
private struct CacheStatistics {
    var hits: Int64 = 0
    var misses: Int64 = 0
    var evictions: Int64 = 0
    var totalBytesWritten: Int64 = 0
    var lastCleanupTime: Date = Date()
}

// MARK: - Cache Entry
private class CacheEntry: NSObject {
    let data: Data
    let checksum: String
    let expirationDate: Date
    let metadata: [String: Any]
    
    init(data: Data, checksum: String, ttl: TimeInterval, metadata: [String: Any] = [:]) {
        self.data = data
        self.checksum = checksum
        self.expirationDate = Date().addingTimeInterval(ttl)
        self.metadata = metadata
        super.init()
    }
}

// MARK: - Cache Manager Implementation
@objc public class CacheManager: NSObject {
    
    // MARK: - Properties
    private static let shared = CacheManager()
    private let memoryCache: NSCache<NSString, AnyObject>
    private let fileManager: FileManager
    private let cacheDirectory: URL
    private let queue: DispatchQueue
    private var cacheStats: CacheStatistics
    private var cleanupTimer: DispatchSourceTimer
    private var totalCacheSize: Int64
    
    // MARK: - Initialization
    private override init() {
        // Initialize memory cache with limits
        memoryCache = NSCache<NSString, AnyObject>()
        memoryCache.countLimit = MAX_MEMORY_CACHE_COUNT
        
        // Setup file manager and cache directory
        fileManager = FileManager.default
        cacheDirectory = try! fileManager.url(
            for: .cachesDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ).appendingPathComponent("TALDUnia/Cache", isDirectory: true)
        
        // Initialize other properties
        queue = DispatchQueue(label: "com.tald.unia.cache", qos: .userInitiated)
        cacheStats = CacheStatistics()
        totalCacheSize = 0
        
        // Create cleanup timer
        cleanupTimer = DispatchSource.makeTimerSource(queue: queue)
        
        super.init()
        
        // Setup cache directory
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        
        // Configure cleanup timer
        cleanupTimer.schedule(deadline: .now(), repeating: CLEANUP_INTERVAL)
        cleanupTimer.setEventHandler { [weak self] in
            self?.performCleanup()
        }
        cleanupTimer.resume()
        
        // Setup power efficiency monitoring
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handlePowerStateChange(_:)),
            name: NSProcessInfo.powerStateDidChangeNotification,
            object: nil
        )
    }
    
    // MARK: - Public Interface
    public static func shared() -> CacheManager {
        return CacheManager.shared
    }
    
    public func setAudioBuffer(_ buffer: [Float32], key: String, ttl: TimeInterval? = nil) throws {
        let cacheKey = AUDIO_CACHE_PREFIX + key
        let data = Data(bytes: buffer, count: buffer.count * MemoryLayout<Float32>.stride)
        let checksum = calculateChecksum(data)
        
        // Compress data for storage efficiency
        let compressedData = try compressData(data)
        let entry = CacheEntry(
            data: compressedData,
            checksum: checksum,
            ttl: ttl ?? DEFAULT_TTL
        )
        
        queue.async { [weak self] in
            guard let self = self else { return }
            
            // Update memory cache
            self.memoryCache.setObject(entry, forKey: cacheKey as NSString)
            
            // Write to disk cache
            let fileURL = self.cacheDirectory.appendingPathComponent(cacheKey)
            do {
                try self.atomicWrite(entry: entry, to: fileURL)
                self.updateCacheSize(delta: Int64(compressedData.count))
            } catch {
                print("Failed to write cache entry: \(error)")
            }
        }
    }
    
    public func getAudioBuffer(_ key: String) throws -> [Float32]? {
        let cacheKey = AUDIO_CACHE_PREFIX + key
        
        // Check memory cache first
        if let entry = memoryCache.object(forKey: cacheKey as NSString) as? CacheEntry {
            if !isExpired(entry) {
                queue.async { [weak self] in
                    self?.cacheStats.hits += 1
                }
                return try decompressAndValidate(entry)
            }
        }
        
        // Check disk cache
        let fileURL = cacheDirectory.appendingPathComponent(cacheKey)
        guard let entry = try? loadFromDisk(fileURL: fileURL),
              !isExpired(entry) else {
            queue.async { [weak self] in
                self?.cacheStats.misses += 1
            }
            return nil
        }
        
        // Update memory cache
        memoryCache.setObject(entry, forKey: cacheKey as NSString)
        
        queue.async { [weak self] in
            self?.cacheStats.hits += 1
        }
        
        return try decompressAndValidate(entry)
    }
    
    // MARK: - Private Helper Methods
    private func calculateChecksum(_ data: Data) -> String {
        var hasher = SHA256()
        hasher.update(data: data)
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
    
    private func compressData(_ data: Data) throws -> Data {
        return try (data as NSData).compressed(using: .lzfse) as Data
    }
    
    private func decompressData(_ data: Data) throws -> Data {
        return try (data as NSData).decompressed(using: .lzfse) as Data
    }
    
    private func atomicWrite(entry: CacheEntry, to url: URL) throws {
        let tempURL = url.appendingPathExtension("tmp")
        try entry.data.write(to: tempURL, options: .atomic)
        try fileManager.moveItem(at: tempURL, to: url)
    }
    
    private func loadFromDisk(fileURL: URL) throws -> CacheEntry? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        let checksumURL = fileURL.appendingPathExtension("checksum")
        guard let checksum = try? String(contentsOf: checksumURL, encoding: .utf8) else { return nil }
        
        return CacheEntry(
            data: data,
            checksum: checksum,
            ttl: DEFAULT_TTL
        )
    }
    
    private func isExpired(_ entry: CacheEntry) -> Bool {
        return entry.expirationDate.timeIntervalSinceNow < 0
    }
    
    private func decompressAndValidate(_ entry: CacheEntry) throws -> [Float32] {
        let decompressedData = try decompressData(entry.data)
        let checksum = calculateChecksum(decompressedData)
        
        guard checksum == entry.checksum else {
            throw TALDError.cacheError(
                code: "CHECKSUM_MISMATCH",
                message: "Cache entry validation failed",
                metadata: ErrorMetadata(
                    timestamp: Date(),
                    component: "CacheManager",
                    additionalInfo: ["key": "checksum_validation"]
                )
            )
        }
        
        return decompressedData.withUnsafeBytes { buffer in
            Array(buffer.bindMemory(to: Float32.self))
        }
    }
    
    private func updateCacheSize(delta: Int64) {
        totalCacheSize += delta
        if totalCacheSize > MAX_CACHE_SIZE {
            performCleanup()
        }
    }
    
    private func performCleanup() {
        queue.async { [weak self] in
            guard let self = self else { return }
            
            // Clear expired memory cache entries
            let now = Date()
            self.memoryCache.removeAllObjects()
            
            // Clear expired disk cache entries
            let cacheContents = try? self.fileManager.contentsOfDirectory(
                at: self.cacheDirectory,
                includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey]
            )
            
            var freedSpace: Int64 = 0
            cacheContents?.forEach { url in
                guard let entry = try? self.loadFromDisk(fileURL: url),
                      self.isExpired(entry) else { return }
                
                if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                    freedSpace += Int64(size)
                }
                
                try? self.fileManager.removeItem(at: url)
                self.cacheStats.evictions += 1
            }
            
            self.totalCacheSize -= freedSpace
            self.cacheStats.lastCleanupTime = now
        }
    }
    
    @objc private func handlePowerStateChange(_ notification: Notification) {
        let powerState = ProcessInfo.processInfo.isLowPowerModeEnabled
        if powerState {
            memoryCache.countLimit = MAX_MEMORY_CACHE_COUNT / 2
            performCleanup()
        } else {
            memoryCache.countLimit = MAX_MEMORY_CACHE_COUNT
        }
    }
}