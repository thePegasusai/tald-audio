//
// ProfileManagerTests.swift
// TALD UNIA
//
// Comprehensive test suite for ProfileManager functionality validation
// XCTest version: macOS 13.0+
//

import XCTest
@testable import TALDUnia

class ProfileManagerTests: XCTestCase {
    
    // MARK: - Properties
    private var profileManager: ProfileManager!
    private var testProfile: Profile!
    private var testAudioSettings: AudioSettings!
    private let testTimeout: TimeInterval = 5.0
    
    // MARK: - Test Lifecycle
    override func setUp() {
        super.setUp()
        
        // Initialize profile manager
        profileManager = ProfileManager.shared()
        
        // Initialize test audio settings with required parameters
        testAudioSettings = AudioSettings(
            sampleRate: AudioConstants.SAMPLE_RATE,
            bitDepth: AudioConstants.BIT_DEPTH,
            bufferSize: AudioConstants.BUFFER_SIZE,
            channels: AudioConstants.MAX_CHANNELS,
            powerSettings: [
                "efficiencyTarget": Float(AudioConstants.AMPLIFIER_EFFICIENCY),
                "powerMode": 1.0,
                "processingThreshold": 0.7
            ]
        )
        
        // Clear any existing test data
        try? profileManager.clearCache()
    }
    
    override func tearDown() {
        // Clean up test profiles and cache
        if let profile = testProfile {
            try? profileManager.deleteProfile(profile.id)
        }
        try? profileManager.clearCache()
        
        testProfile = nil
        testAudioSettings = nil
        profileManager = nil
        
        super.tearDown()
    }
    
    // MARK: - Profile Creation Tests
    func testProfileCreation() throws {
        let expectation = XCTestExpectation(description: "Profile creation")
        
        let profileName = "Test Profile"
        let profileDescription = "Test Profile Description"
        
        do {
            testProfile = try profileManager.createProfile(
                name: profileName,
                description: profileDescription,
                settings: testAudioSettings
            )
            
            XCTAssertNotNil(testProfile)
            XCTAssertEqual(testProfile.name, profileName)
            XCTAssertEqual(testProfile.description, profileDescription)
            XCTAssertEqual(testProfile.audioSettings.sampleRate, AudioConstants.SAMPLE_RATE)
            XCTAssertEqual(testProfile.audioSettings.bitDepth, AudioConstants.BIT_DEPTH)
            XCTAssertFalse(testProfile.isDefault)
            
            expectation.fulfill()
        } catch {
            XCTFail("Profile creation failed: \(error)")
        }
        
        wait(for: [expectation], timeout: testTimeout)
    }
    
    func testProfileCreationValidation() {
        let expectation = XCTestExpectation(description: "Profile validation")
        
        // Test empty name validation
        XCTAssertThrowsError(try profileManager.createProfile(name: "", description: "Test")) { error in
            guard case TALDError.validationError(let code, _, _) = error else {
                XCTFail("Unexpected error type")
                return
            }
            XCTAssertEqual(code, "INVALID_PROFILE_NAME")
        }
        
        // Test invalid audio settings
        let invalidSettings = AudioSettings(sampleRate: 44100) // Invalid sample rate
        XCTAssertThrowsError(try profileManager.createProfile(
            name: "Test",
            description: "Test",
            settings: invalidSettings
        )) { error in
            guard case TALDError.configurationError(let code, _, _) = error else {
                XCTFail("Unexpected error type")
                return
            }
            XCTAssertEqual(code, "INVALID_SAMPLE_RATE")
        }
        
        expectation.fulfill()
        wait(for: [expectation], timeout: testTimeout)
    }
    
    // MARK: - Profile Retrieval Tests
    func testProfileRetrieval() throws {
        let expectation = XCTestExpectation(description: "Profile retrieval")
        
        // Create test profile
        testProfile = try profileManager.createProfile(
            name: "Test Profile",
            description: "Test Description",
            settings: testAudioSettings
        )
        
        // Test profile retrieval
        do {
            let retrievedProfile = try profileManager.getProfile(testProfile.id)
            XCTAssertEqual(retrievedProfile, testProfile)
            XCTAssertEqual(retrievedProfile.audioSettings, testProfile.audioSettings)
            expectation.fulfill()
        } catch {
            XCTFail("Profile retrieval failed: \(error)")
        }
        
        wait(for: [expectation], timeout: testTimeout)
    }
    
    // MARK: - Profile Update Tests
    func testProfileUpdate() throws {
        let expectation = XCTestExpectation(description: "Profile update")
        
        // Create initial profile
        testProfile = try profileManager.createProfile(
            name: "Initial Name",
            description: "Initial Description",
            settings: testAudioSettings
        )
        
        // Update profile
        let updatedName = "Updated Name"
        let updatedDescription = "Updated Description"
        
        do {
            try profileManager.updateProfile(
                testProfile.id,
                name: updatedName,
                description: updatedDescription
            )
            
            // Verify updates
            let updatedProfile = try profileManager.getProfile(testProfile.id)
            XCTAssertEqual(updatedProfile.name, updatedName)
            XCTAssertEqual(updatedProfile.description, updatedDescription)
            XCTAssertGreaterThan(updatedProfile.updatedAt, testProfile.updatedAt)
            
            expectation.fulfill()
        } catch {
            XCTFail("Profile update failed: \(error)")
        }
        
        wait(for: [expectation], timeout: testTimeout)
    }
    
    // MARK: - Profile Deletion Tests
    func testProfileDeletion() throws {
        let expectation = XCTestExpectation(description: "Profile deletion")
        
        // Create test profile
        testProfile = try profileManager.createProfile(
            name: "Test Profile",
            description: "Test Description",
            settings: testAudioSettings
        )
        
        // Delete profile
        do {
            try profileManager.deleteProfile(testProfile.id)
            
            // Verify deletion
            XCTAssertThrowsError(try profileManager.getProfile(testProfile.id)) { error in
                guard case TALDError.configurationError(let code, _, _) = error else {
                    XCTFail("Unexpected error type")
                    return
                }
                XCTAssertEqual(code, "PROFILE_NOT_FOUND")
            }
            
            expectation.fulfill()
        } catch {
            XCTFail("Profile deletion failed: \(error)")
        }
        
        wait(for: [expectation], timeout: testTimeout)
    }
    
    // MARK: - Concurrency Tests
    func testConcurrentAccess() {
        let expectation = XCTestExpectation(description: "Concurrent profile operations")
        expectation.expectedFulfillmentCount = 3
        
        let concurrentQueue = DispatchQueue(
            label: "com.tald.unia.test.concurrent",
            attributes: .concurrent
        )
        
        // Create multiple profiles concurrently
        for i in 0..<3 {
            concurrentQueue.async {
                do {
                    let profile = try self.profileManager.createProfile(
                        name: "Concurrent Profile \(i)",
                        description: "Concurrent Test",
                        settings: self.testAudioSettings
                    )
                    
                    // Verify profile creation
                    let retrieved = try self.profileManager.getProfile(profile.id)
                    XCTAssertEqual(retrieved, profile)
                    
                    expectation.fulfill()
                } catch {
                    XCTFail("Concurrent operation failed: \(error)")
                }
            }
        }
        
        wait(for: [expectation], timeout: testTimeout)
    }
    
    // MARK: - Performance Tests
    func testProfileCreationPerformance() {
        measure {
            do {
                let profile = try profileManager.createProfile(
                    name: "Performance Test",
                    description: "Performance Test Description",
                    settings: testAudioSettings
                )
                try profileManager.deleteProfile(profile.id)
            } catch {
                XCTFail("Performance test failed: \(error)")
            }
        }
    }
    
    func testProfileRetrievalPerformance() throws {
        // Create test profile for performance testing
        testProfile = try profileManager.createProfile(
            name: "Performance Test",
            description: "Performance Test Description",
            settings: testAudioSettings
        )
        
        measure {
            do {
                _ = try self.profileManager.getProfile(self.testProfile.id)
            } catch {
                XCTFail("Performance test failed: \(error)")
            }
        }
    }
    
    // MARK: - Cache Tests
    func testProfileCaching() throws {
        let expectation = XCTestExpectation(description: "Profile caching")
        
        // Create test profile
        testProfile = try profileManager.createProfile(
            name: "Cache Test",
            description: "Cache Test Description",
            settings: testAudioSettings
        )
        
        // First retrieval should cache the profile
        _ = try profileManager.getProfile(testProfile.id)
        
        // Subsequent retrieval should use cache
        let startTime = Date()
        _ = try profileManager.getProfile(testProfile.id)
        let retrievalTime = Date().timeIntervalSince(startTime)
        
        // Cached retrieval should be fast
        XCTAssertLessThan(retrievalTime, 0.01)
        
        expectation.fulfill()
        wait(for: [expectation], timeout: testTimeout)
    }
    
    // MARK: - Error Handling Tests
    func testErrorHandling() {
        let expectation = XCTestExpectation(description: "Error handling")
        
        // Test profile limit exceeded
        var profiles: [Profile] = []
        for i in 0..<11 { // Exceeds MAX_PROFILES (10)
            do {
                let profile = try profileManager.createProfile(
                    name: "Profile \(i)",
                    description: "Test",
                    settings: testAudioSettings
                )
                profiles.append(profile)
            } catch {
                guard case TALDError.configurationError(let code, _, _) = error else {
                    XCTFail("Unexpected error type")
                    return
                }
                XCTAssertEqual(code, "PROFILE_LIMIT_EXCEEDED")
                expectation.fulfill()
            }
        }
        
        // Cleanup test profiles
        profiles.forEach { profile in
            try? profileManager.deleteProfile(profile.id)
        }
        
        wait(for: [expectation], timeout: testTimeout)
    }
}