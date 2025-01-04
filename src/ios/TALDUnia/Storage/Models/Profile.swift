// Foundation Latest
import Foundation

/// Custom error enum for Profile operations
public enum ProfileError: Error {
    case invalidUserId(String)
    case invalidPreferences(String)
    case audioSettingsConflict(String)
    case threadingError(String)
}

/// Thread-safe atomic property wrapper
@propertyWrapper
private struct AtomicProperty<T> {
    private let lock = NSLock()
    private var value: T
    
    init(wrappedValue: T) {
        self.value = wrappedValue
    }
    
    var wrappedValue: T {
        get {
            lock.lock()
            defer { lock.unlock() }
            return value
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            value = newValue
        }
    }
}

/// Thread-safe model class representing a user profile with comprehensive validation and error handling
@objc @objcMembers public class Profile: NSObject, Codable {
    // MARK: - Properties
    
    public private(set) var id: UUID
    public private(set) var userId: String
    public private(set) var name: String
    private let lock = NSLock()
    
    @AtomicProperty private var audioSettings: [AudioSettings]
    private var preferences: [String: Any]
    private let schemaVersion: Int = 1
    
    public private(set) var isActive: Bool
    public private(set) var createdAt: Date
    public private(set) var updatedAt: Date
    
    // MARK: - Initialization
    
    /// Creates a new Profile instance with validation
    public init(id: UUID = UUID(),
                userId: String,
                name: String,
                preferences: [String: Any]) throws {
        // Validate user ID
        guard !userId.isEmpty else {
            throw ProfileError.invalidUserId("User ID cannot be empty")
        }
        
        // Initialize properties
        self.id = id
        self.userId = userId
        self.name = name
        self._audioSettings = AtomicProperty(wrappedValue: [])
        self.preferences = preferences
        self.isActive = true
        self.createdAt = Date()
        self.updatedAt = Date()
        
        super.init()
        
        // Validate preferences
        try validatePreferences()
    }
    
    // MARK: - Codable Implementation
    
    private enum CodingKeys: String, CodingKey {
        case id, userId, name, audioSettings, preferences
        case isActive, createdAt, updatedAt, schemaVersion
    }
    
    public func encode(to encoder: Encoder) throws {
        lock.lock()
        defer { lock.unlock() }
        
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(id, forKey: .id)
        try container.encode(userId, forKey: .userId)
        try container.encode(name, forKey: .name)
        try container.encode(audioSettings, forKey: .audioSettings)
        try container.encode(preferences as? [String: String], forKey: .preferences)
        try container.encode(isActive, forKey: .isActive)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encode(schemaVersion, forKey: .schemaVersion)
    }
    
    public required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        // Version checking for future migrations
        let version = try container.decode(Int.self, forKey: .schemaVersion)
        guard version <= 1 else {
            throw ProfileError.invalidPreferences("Unsupported schema version: \(version)")
        }
        
        // Decode properties
        id = try container.decode(UUID.self, forKey: .id)
        userId = try container.decode(String.self, forKey: .userId)
        name = try container.decode(String.self, forKey: .name)
        let decodedSettings = try container.decode([AudioSettings].self, forKey: .audioSettings)
        _audioSettings = AtomicProperty(wrappedValue: decodedSettings)
        preferences = try container.decode([String: String].self, forKey: .preferences)
        isActive = try container.decode(Bool.self, forKey: .isActive)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        
        super.init()
    }
    
    // MARK: - Public Methods
    
    /// Thread-safe addition of audio settings
    public func addAudioSettings(_ settings: AudioSettings) -> Result<Void, ProfileError> {
        lock.lock()
        defer { lock.unlock() }
        
        do {
            // Validate settings
            guard settings.profileId == id else {
                throw ProfileError.audioSettingsConflict("Settings profile ID mismatch")
            }
            
            // Check for duplicate settings
            if audioSettings.contains(where: { $0.id == settings.id }) {
                throw ProfileError.audioSettingsConflict("Settings with ID \(settings.id) already exists")
            }
            
            // Add settings and update timestamp
            audioSettings.append(settings)
            updatedAt = Date()
            
            return .success(())
        } catch {
            return .failure(error as? ProfileError ?? ProfileError.threadingError(error.localizedDescription))
        }
    }
    
    /// Thread-safe removal of audio settings
    public func removeAudioSettings(withId settingsId: UUID) -> Result<Bool, ProfileError> {
        lock.lock()
        defer { lock.unlock() }
        
        do {
            guard let index = audioSettings.firstIndex(where: { $0.id == settingsId }) else {
                return .success(false)
            }
            
            audioSettings.remove(at: index)
            updatedAt = Date()
            
            return .success(true)
        } catch {
            return .failure(ProfileError.threadingError(error.localizedDescription))
        }
    }
    
    /// Thread-safe access to audio settings
    public func getAudioSettings() -> [AudioSettings] {
        return audioSettings
    }
    
    /// Updates profile preferences with validation
    public func updatePreferences(_ newPreferences: [String: Any]) -> Result<Void, ProfileError> {
        lock.lock()
        defer { lock.unlock() }
        
        do {
            self.preferences = newPreferences
            try validatePreferences()
            updatedAt = Date()
            return .success(())
        } catch {
            return .failure(error as? ProfileError ?? ProfileError.invalidPreferences(error.localizedDescription))
        }
    }
    
    // MARK: - Private Methods
    
    private func validatePreferences() throws {
        // Validate required preference keys
        let requiredKeys = ["defaultDevice", "outputFormat", "enhancementLevel"]
        for key in requiredKeys {
            guard preferences[key] != nil else {
                throw ProfileError.invalidPreferences("Missing required preference: \(key)")
            }
        }
        
        // Validate enhancement level if present
        if let enhancementLevel = preferences["enhancementLevel"] as? Float {
            guard enhancementLevel >= 0 && enhancementLevel <= 1 else {
                throw ProfileError.invalidPreferences("Enhancement level must be between 0 and 1")
            }
        }
        
        // Validate output format if present
        if let outputFormat = preferences["outputFormat"] as? String {
            let validFormats = ["PCM", "DSD", "MQA"]
            guard validFormats.contains(outputFormat) else {
                throw ProfileError.invalidPreferences("Invalid output format: \(outputFormat)")
            }
        }
    }
}