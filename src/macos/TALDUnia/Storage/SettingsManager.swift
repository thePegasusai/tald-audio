//
// SettingsManager.swift
// TALD UNIA
//
// Thread-safe settings manager with secure storage and performance optimization
// Foundation version: macOS 13.0+
// Security version: macOS 13.0+
// os.log version: macOS 13.0+
//

import Foundation
import Security
import os.log

// MARK: - Global Constants
private let SETTINGS_FILE_NAME: String = "audio_settings.json"
private let SETTINGS_DIRECTORY: String = "~/Library/Application Support/TALDUnia/"
private let BACKUP_DIRECTORY: String = "~/Library/Application Support/TALDUnia/Backups/"
private let SETTINGS_CACHE_SIZE: Int = 1024

// MARK: - SettingsManager
public class SettingsManager {
    // MARK: - Singleton
    public static let shared = SettingsManager()
    
    // MARK: - Properties
    private let settingsURL: URL
    private let backupURL: URL
    private var currentSettings: AudioSettings?
    private let settingsCache: NSCache<NSString, AudioSettings>
    private let settingsQueue: DispatchQueue
    private let logger = Logger(subsystem: "com.tald.unia", category: "SettingsManager")
    
    // MARK: - Initialization
    private init() {
        // Initialize paths
        let fileManager = FileManager.default
        let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        
        settingsURL = appSupportURL.appendingPathComponent("TALDUnia").appendingPathComponent(SETTINGS_FILE_NAME)
        backupURL = appSupportURL.appendingPathComponent("TALDUnia/Backups")
        
        // Initialize cache with size limit
        settingsCache = NSCache<NSString, AudioSettings>()
        settingsCache.countLimit = SETTINGS_CACHE_SIZE
        
        // Create serial queue for thread safety
        settingsQueue = DispatchQueue(label: "com.tald.unia.settings", qos: .userInitiated)
        
        // Validate settings directory
        if !validateSettingsPath() {
            logger.error("Failed to validate settings directory")
        }
        
        // Initial settings load
        do {
            currentSettings = try loadSettings()
        } catch {
            logger.error("Failed to load initial settings: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Path Validation
    private func validateSettingsPath() -> Bool {
        let fileManager = FileManager.default
        
        do {
            // Create settings directory if needed
            if !fileManager.fileExists(atPath: settingsURL.deletingLastPathComponent().path) {
                try fileManager.createDirectory(
                    at: settingsURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true,
                    attributes: [
                        FileAttributeKey.posixPermissions: 0o700
                    ]
                )
            }
            
            // Create backup directory if needed
            if !fileManager.fileExists(atPath: backupURL.path) {
                try fileManager.createDirectory(
                    at: backupURL,
                    withIntermediateDirectories: true,
                    attributes: [
                        FileAttributeKey.posixPermissions: 0o700
                    ]
                )
            }
            
            return true
        } catch {
            logger.error("Path validation failed: \(error.localizedDescription)")
            return false
        }
    }
    
    // MARK: - Settings Loading
    public func loadSettings() throws -> AudioSettings? {
        return try settingsQueue.sync {
            // Check cache first
            if let cachedSettings = settingsCache.object(forKey: SETTINGS_FILE_NAME as NSString) {
                logger.debug("Retrieved settings from cache")
                return cachedSettings
            }
            
            // Load from file if not cached
            guard FileManager.default.fileExists(atPath: settingsURL.path) else {
                logger.info("No settings file found, creating default settings")
                let defaultSettings = AudioSettings()
                try saveSettings(defaultSettings)
                return defaultSettings
            }
            
            let startTime = DispatchTime.now()
            
            // Read and decrypt settings
            let encryptedData = try Data(contentsOf: settingsURL)
            let decryptedData = try decryptSettings(encryptedData)
            
            // Decode settings
            let decoder = JSONDecoder()
            let settings = try decoder.decode(AudioSettings.self, from: decryptedData)
            
            // Validate settings
            try settings.validateSettings()
            
            // Cache valid settings
            settingsCache.setObject(settings, forKey: SETTINGS_FILE_NAME as NSString)
            
            let endTime = DispatchTime.now()
            let loadTime = Double(endTime.uptimeNanoseconds - startTime.uptimeNanoseconds) / 1_000_000_000
            logger.debug("Settings loaded in \(loadTime) seconds")
            
            return settings
        }
    }
    
    // MARK: - Settings Saving
    public func saveSettings(_ settings: AudioSettings) throws -> Bool {
        return try settingsQueue.sync {
            let startTime = DispatchTime.now()
            
            // Validate settings
            try settings.validateSettings()
            
            // Create backup of existing settings
            if FileManager.default.fileExists(atPath: settingsURL.path) {
                let backupFileName = "settings_backup_\(Date().timeIntervalSince1970).json"
                let backupFileURL = backupURL.appendingPathComponent(backupFileName)
                try FileManager.default.copyItem(at: settingsURL, to: backupFileURL)
            }
            
            // Encode settings
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let settingsData = try encoder.encode(settings)
            
            // Encrypt settings
            let encryptedData = try encryptSettings(settingsData)
            
            // Write to file atomically
            try encryptedData.write(to: settingsURL, options: .atomicWrite)
            
            // Update cache
            settingsCache.setObject(settings, forKey: SETTINGS_FILE_NAME as NSString)
            currentSettings = settings
            
            let endTime = DispatchTime.now()
            let saveTime = Double(endTime.uptimeNanoseconds - startTime.uptimeNanoseconds) / 1_000_000_000
            logger.debug("Settings saved in \(saveTime) seconds")
            
            return true
        }
    }
    
    // MARK: - Settings Update
    public func updateSettings(_ parameters: [String: Any]) throws -> Bool {
        return try settingsQueue.sync {
            let startTime = DispatchTime.now()
            
            // Load current settings
            guard var settings = try loadSettings() else {
                throw TALDError.configurationError(
                    code: "SETTINGS_NOT_FOUND",
                    message: "No settings found to update",
                    metadata: ErrorMetadata(
                        timestamp: Date(),
                        component: "SettingsManager",
                        additionalInfo: ["operation": "update"]
                    )
                )
            }
            
            // Update settings
            try settings.update(
                sampleRate: parameters["sampleRate"] as? Int,
                bitDepth: parameters["bitDepth"] as? Int,
                bufferSize: parameters["bufferSize"] as? Int,
                channels: parameters["channels"] as? Int,
                eqSettings: parameters["eqSettings"] as? [String: Float],
                dspParameters: parameters["dspParameters"] as? [String: Any],
                powerSettings: parameters["powerSettings"] as? [String: Float]
            )
            
            // Save updated settings
            let saved = try saveSettings(settings)
            
            let endTime = DispatchTime.now()
            let updateTime = Double(endTime.uptimeNanoseconds - startTime.uptimeNanoseconds) / 1_000_000_000
            logger.debug("Settings updated in \(updateTime) seconds")
            
            return saved
        }
    }
    
    // MARK: - Encryption
    private func encryptSettings(_ data: Data) throws -> Data {
        // Create encryption key
        let key = try createEncryptionKey()
        
        // Generate random IV
        var iv = Data(count: 16)
        let result = iv.withUnsafeMutableBytes { bytes in
            SecRandomCopyBytes(kSecRandomDefault, 16, bytes.baseAddress!)
        }
        guard result == errSecSuccess else {
            throw TALDError.configurationError(
                code: "ENCRYPTION_FAILED",
                message: "Failed to generate IV",
                metadata: ErrorMetadata(
                    timestamp: Date(),
                    component: "SettingsManager",
                    additionalInfo: ["operation": "encrypt"]
                )
            )
        }
        
        // Encrypt data
        let algorithm = SecKeyAlgorithm.rsaEncryptionOAEPSHA256
        var error: Unmanaged<CFError>?
        guard let encryptedData = SecKeyCreateEncryptedData(
            key,
            algorithm,
            data as CFData,
            &error
        ) as Data? else {
            throw TALDError.configurationError(
                code: "ENCRYPTION_FAILED",
                message: "Failed to encrypt settings",
                metadata: ErrorMetadata(
                    timestamp: Date(),
                    component: "SettingsManager",
                    additionalInfo: ["operation": "encrypt"]
                )
            )
        }
        
        // Combine IV and encrypted data
        return iv + encryptedData
    }
    
    private func decryptSettings(_ data: Data) throws -> Data {
        // Extract IV and encrypted data
        let iv = data.prefix(16)
        let encryptedData = data.dropFirst(16)
        
        // Get decryption key
        let key = try createEncryptionKey()
        
        // Decrypt data
        let algorithm = SecKeyAlgorithm.rsaEncryptionOAEPSHA256
        var error: Unmanaged<CFError>?
        guard let decryptedData = SecKeyCreateDecryptedData(
            key,
            algorithm,
            encryptedData as CFData,
            &error
        ) as Data? else {
            throw TALDError.configurationError(
                code: "DECRYPTION_FAILED",
                message: "Failed to decrypt settings",
                metadata: ErrorMetadata(
                    timestamp: Date(),
                    component: "SettingsManager",
                    additionalInfo: ["operation": "decrypt"]
                )
            )
        }
        
        return decryptedData
    }
    
    private func createEncryptionKey() throws -> SecKey {
        let tag = "com.tald.unia.settings.key".data(using: .utf8)!
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeySizeInBits as String: 2048,
            kSecPrivateKeyAttrs as String: [
                kSecAttrIsPermanent as String: true,
                kSecAttrApplicationTag as String: tag
            ]
        ]
        
        var error: Unmanaged<CFError>?
        guard let key = SecKeyCreateRandomKey(attributes as CFDictionary, &error) else {
            throw TALDError.configurationError(
                code: "KEY_GENERATION_FAILED",
                message: "Failed to generate encryption key",
                metadata: ErrorMetadata(
                    timestamp: Date(),
                    component: "SettingsManager",
                    additionalInfo: ["operation": "createKey"]
                )
            )
        }
        
        return key
    }
}