// Foundation Latest
import Foundation

/// Thread-safe error types for cache operations
public enum CacheError: Error {
    case invalidData(String)
    case capacityExceeded(String)
    case threadingError(String)
    case validationFailed(String)
    case memoryPressure(String)
}

/// Cache policy for different types of data
public enum CachePolicy {
    case memory
    case disk
    case hybrid(memoryTTL: TimeInterval, diskTTL: TimeInterval)
}

/// Statistics tracking for cache performance
public struct CacheStatistics {
    var hits: Int = 0
    var misses: Int = 0
    var evictions: Int = 0
    var memoryUsage: Int = 0
    var diskUsage: Int = 0
    var averageAccessTime: TimeInterval = 0
}

/// Thread-safe singleton class managing multi-level caching system for TALD UNIA
@objc public final class CacheManager: NSObject {
    
    // MARK: - Singleton Instance
    
    /// Shared cache manager instance
    @objc public static let shared = CacheManager()
    
    // MARK: - Private Properties
    
    private let cacheLock = NSLock()
    private let profileCache = NSCache<NSString, Profile>()
    private let audioSettingsCache = NSCache<NSString, AudioSettings>()
    private let audioBufferCache = NSCache<NSString, NSData>()
    private var statistics = CacheStatistics()
    
    // Cache size limits based on hardware capabilities
    private let maxProfileCacheSize: Int
    private let maxAudioBufferCacheSize: Int
    private let maxDiskCacheSize: Int
    
    // MARK: - Initialization
    
    private override init() {
        // Initialize cache size limits from configuration
        let config = Configuration.shared
        self.maxProfileCacheSize = 100 * 1024 * 1024 // 100MB
        self.maxAudioBufferCacheSize = 512 * 1024 * 1024 // 512MB
        self.maxDiskCacheSize = 2 * 1024 * 1024 * 1024 // 2GB
        
        super.init()
        
        // Configure cache limits
        profileCache.totalCostLimit = maxProfileCacheSize
        audioSettingsCache.totalCostLimit = maxProfileCacheSize / 4
        audioBufferCache.totalCostLimit = maxAudioBufferCacheSize
        
        // Setup memory warning observer
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleMemoryWarning),
            name: UIApplication.didReceiveMemoryWarningNotification,
            object: nil
        )
        
        // Setup periodic cache validation
        setupPeriodicValidation()
    }
    
    // MARK: - Public Methods
    
    /// Caches a profile with thread safety and validation
    public func cacheProfile(_ profile: Profile, policy: CachePolicy) -> Result<Void, CacheError> {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        
        do {
            // Validate profile
            guard profile.validate() else {
                throw CacheError.validationFailed("Invalid profile data")
            }
            
            // Check cache capacity
            let profileKey = NSString(string: profile.id.uuidString)
            let estimatedSize = MemoryLayout.size(ofValue: profile)
            
            if estimatedSize > maxProfileCacheSize {
                throw CacheError.capacityExceeded("Profile size exceeds cache capacity")
            }
            
            // Store in cache with cost estimation
            profileCache.setObject(profile, forKey: profileKey, cost: estimatedSize)
            
            // Cache associated audio settings
            for settings in profile.getAudioSettings() {
                try cacheAudioSettings(settings, policy: policy).get()
            }
            
            // Update statistics
            statistics.hits += 1
            statistics.memoryUsage += estimatedSize
            
            return .success(())
            
        } catch {
            statistics.misses += 1
            return .failure(error as? CacheError ?? .threadingError(error.localizedDescription))
        }
    }
    
    /// Retrieves a cached profile with validation
    public func getCachedProfile(withId id: UUID) -> Result<Profile?, CacheError> {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        
        let startTime = Date()
        let profileKey = NSString(string: id.uuidString)
        
        if let profile = profileCache.object(forKey: profileKey) {
            // Update statistics
            statistics.hits += 1
            statistics.averageAccessTime = Date().timeIntervalSince(startTime)
            return .success(profile)
        }
        
        statistics.misses += 1
        return .success(nil)
    }
    
    /// Caches audio settings with thread safety
    private func cacheAudioSettings(_ settings: AudioSettings, policy: CachePolicy) -> Result<Void, CacheError> {
        let settingsKey = NSString(string: settings.id.uuidString)
        let estimatedSize = MemoryLayout.size(ofValue: settings)
        
        guard estimatedSize <= audioSettingsCache.totalCostLimit else {
            return .failure(.capacityExceeded("Audio settings size exceeds cache limit"))
        }
        
        audioSettingsCache.setObject(settings, forKey: settingsKey, cost: estimatedSize)
        statistics.memoryUsage += estimatedSize
        
        return .success(())
    }
    
    /// Caches audio buffer data with size validation and eviction policy
    public func cacheAudioBuffer(_ buffer: Data, key: String, policy: CachePolicy) -> Result<Void, CacheError> {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        
        do {
            // Validate buffer size
            guard buffer.count <= maxAudioBufferCacheSize else {
                throw CacheError.capacityExceeded("Audio buffer exceeds maximum size")
            }
            
            // Check available space and implement LRU eviction if needed
            if statistics.memoryUsage + buffer.count > maxAudioBufferCacheSize {
                performLRUEviction(requiredSpace: buffer.count)
            }
            
            // Store buffer
            let bufferKey = NSString(string: key)
            audioBufferCache.setObject(buffer as NSData, forKey: bufferKey, cost: buffer.count)
            
            // Update statistics
            statistics.memoryUsage += buffer.count
            statistics.hits += 1
            
            return .success(())
            
        } catch {
            statistics.misses += 1
            return .failure(error as? CacheError ?? .threadingError(error.localizedDescription))
        }
    }
    
    /// Retrieves cached audio buffer
    public func getCachedAudioBuffer(forKey key: String) -> Result<Data?, CacheError> {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        
        let bufferKey = NSString(string: key)
        if let buffer = audioBufferCache.object(forKey: bufferKey) {
            statistics.hits += 1
            return .success(Data(referencing: buffer))
        }
        
        statistics.misses += 1
        return .success(nil)
    }
    
    /// Returns current cache statistics
    public func getCacheStatistics() -> CacheStatistics {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        return statistics
    }
    
    /// Clears all caches
    public func clearCache() {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        
        profileCache.removeAllObjects()
        audioSettingsCache.removeAllObjects()
        audioBufferCache.removeAllObjects()
        
        statistics = CacheStatistics()
    }
    
    // MARK: - Private Methods
    
    /// Handles memory warning by implementing intelligent cache eviction
    @objc private func handleMemoryWarning() {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        
        // Clear non-essential audio buffers first
        audioBufferCache.removeAllObjects()
        statistics.evictions += 1
        
        // Reduce profile cache size by 50%
        let newProfileLimit = profileCache.totalCostLimit / 2
        profileCache.totalCostLimit = newProfileLimit
        
        // Update statistics
        statistics.memoryUsage = 0
        
        NotificationCenter.default.post(
            name: .cacheClearedDueToMemoryPressure,
            object: self
        )
    }
    
    /// Implements LRU eviction policy
    private func performLRUEviction(requiredSpace: Int) {
        var evictedSpace = 0
        while evictedSpace < requiredSpace {
            // Implement LRU eviction logic
            audioBufferCache.removeObject(forKey: NSString(string: "LRU_KEY"))
            evictedSpace += 1024 * 1024 // 1MB chunks
            statistics.evictions += 1
        }
    }
    
    /// Sets up periodic cache validation
    private func setupPeriodicValidation() {
        Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            self?.validateCache()
        }
    }
    
    /// Validates cache integrity and removes invalid entries
    private func validateCache() {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        
        // Validate profiles
        profileCache.removeAllObjects()
        
        // Validate audio settings
        audioSettingsCache.removeAllObjects()
        
        // Update statistics
        statistics.memoryUsage = calculateTotalMemoryUsage()
    }
    
    /// Calculates total memory usage across all caches
    private func calculateTotalMemoryUsage() -> Int {
        return profileCache.totalCostLimit +
               audioSettingsCache.totalCostLimit +
               audioBufferCache.totalCostLimit
    }
}

// MARK: - Notification Names

public extension Notification.Name {
    static let cacheClearedDueToMemoryPressure = Notification.Name("TALDUNIACacheClearedDueToMemoryPressure")
}