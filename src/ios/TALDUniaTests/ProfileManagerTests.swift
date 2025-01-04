// XCTest Latest
import XCTest
// TALDUnia Module
@testable import TALDUnia

/// Comprehensive test suite for ProfileManager class with emphasis on thread safety and performance
final class ProfileManagerTests: XCTestCase {
    
    // MARK: - Properties
    
    private var sut: ProfileManager!
    private var testProfileId: UUID!
    private var testUserId: String!
    private var testProfileName: String!
    private var testPreferences: [String: Any]!
    private var testQueue: DispatchQueue!
    private var concurrentExpectation: XCTestExpectation!
    
    // MARK: - Setup & Teardown
    
    override func setUp() {
        super.setUp()
        
        // Initialize ProfileManager instance
        sut = ProfileManager.shared
        
        // Set up test data
        testProfileId = UUID()
        testUserId = "test_user_\(UUID().uuidString)"
        testProfileName = "Test Profile"
        testPreferences = [
            "defaultDevice": "ESS ES9038PRO",
            "outputFormat": "PCM",
            "enhancementLevel": 0.8,
            "roomSize": 50.0,
            "reverbTime": 0.3
        ]
        
        // Initialize concurrent test queue
        testQueue = DispatchQueue(
            label: "com.taldunia.tests.concurrent",
            attributes: .concurrent
        )
        
        // Clear any existing profiles
        _ = sut.clearProfiles()
    }
    
    override func tearDown() {
        // Clean up test data
        _ = sut.clearProfiles()
        testQueue = nil
        testPreferences = nil
        testProfileId = nil
        testUserId = nil
        testProfileName = nil
        sut = nil
        
        super.tearDown()
    }
    
    // MARK: - Profile Creation Tests
    
    func testProfileCreation() {
        // Test profile creation with valid data
        let result = sut.createProfile(
            userId: testUserId,
            name: testProfileName,
            preferences: testPreferences
        )
        
        switch result {
        case .success(let profile):
            XCTAssertNotNil(profile)
            XCTAssertEqual(profile.userId, testUserId)
            XCTAssertEqual(profile.name, testProfileName)
            XCTAssertNotNil(profile.preferences["defaultDevice"])
            XCTAssertNotNil(profile.preferences["enhancementLevel"])
        case .failure(let error):
            XCTFail("Profile creation failed: \(error)")
        }
    }
    
    func testDuplicateProfileCreation() {
        // Create initial profile
        _ = sut.createProfile(
            userId: testUserId,
            name: testProfileName,
            preferences: testPreferences
        )
        
        // Attempt to create duplicate profile
        let result = sut.createProfile(
            userId: testUserId,
            name: testProfileName,
            preferences: testPreferences
        )
        
        switch result {
        case .success:
            XCTFail("Duplicate profile creation should fail")
        case .failure(let error):
            XCTAssertEqual(
                error.localizedDescription.contains("Profile already exists"),
                true
            )
        }
    }
    
    // MARK: - Profile Retrieval Tests
    
    func testProfileRetrieval() {
        // Create test profile
        let createResult = sut.createProfile(
            userId: testUserId,
            name: testProfileName,
            preferences: testPreferences
        )
        
        guard case .success(let createdProfile) = createResult else {
            XCTFail("Failed to create test profile")
            return
        }
        
        // Test profile retrieval
        let result = sut.getProfile(withId: createdProfile.id)
        
        switch result {
        case .success(let profile):
            XCTAssertNotNil(profile)
            XCTAssertEqual(profile?.id, createdProfile.id)
            XCTAssertEqual(profile?.userId, testUserId)
        case .failure(let error):
            XCTFail("Profile retrieval failed: \(error)")
        }
    }
    
    // MARK: - Profile Update Tests
    
    func testProfileUpdate() {
        // Create test profile
        let createResult = sut.createProfile(
            userId: testUserId,
            name: testProfileName,
            preferences: testPreferences
        )
        
        guard case .success(let profile) = createResult else {
            XCTFail("Failed to create test profile")
            return
        }
        
        // Update profile preferences
        var updatedPreferences = profile.preferences
        updatedPreferences["enhancementLevel"] = 0.9
        
        let updateResult = profile.updatePreferences(updatedPreferences)
        
        switch updateResult {
        case .success:
            let retrieveResult = sut.getProfile(withId: profile.id)
            guard case .success(let updatedProfile) = retrieveResult else {
                XCTFail("Failed to retrieve updated profile")
                return
            }
            XCTAssertEqual(
                updatedProfile?.preferences["enhancementLevel"] as? Float,
                0.9
            )
        case .failure(let error):
            XCTFail("Profile update failed: \(error)")
        }
    }
    
    // MARK: - Profile Deletion Tests
    
    func testProfileDeletion() {
        // Create test profile
        let createResult = sut.createProfile(
            userId: testUserId,
            name: testProfileName,
            preferences: testPreferences
        )
        
        guard case .success(let profile) = createResult else {
            XCTFail("Failed to create test profile")
            return
        }
        
        // Delete profile
        let deleteResult = sut.deleteProfile(withId: profile.id)
        
        switch deleteResult {
        case .success(let deleted):
            XCTAssertTrue(deleted)
            
            // Verify profile is deleted
            let retrieveResult = sut.getProfile(withId: profile.id)
            guard case .success(let retrievedProfile) = retrieveResult else {
                XCTFail("Profile retrieval should succeed with nil result")
                return
            }
            XCTAssertNil(retrievedProfile)
        case .failure(let error):
            XCTFail("Profile deletion failed: \(error)")
        }
    }
    
    // MARK: - Concurrent Operation Tests
    
    func testConcurrentProfileOperations() {
        let operationCount = 100
        let concurrentExpectation = expectation(description: "Concurrent operations")
        concurrentExpectation.expectedFulfillmentCount = operationCount
        
        for i in 0..<operationCount {
            testQueue.async {
                let userId = "concurrent_user_\(i)"
                let name = "Concurrent Profile \(i)"
                
                let result = self.sut.createProfile(
                    userId: userId,
                    name: name,
                    preferences: self.testPreferences
                )
                
                switch result {
                case .success(let profile):
                    // Verify profile creation
                    XCTAssertNotNil(profile)
                    XCTAssertEqual(profile.userId, userId)
                    
                    // Update profile
                    var updatedPreferences = profile.preferences
                    updatedPreferences["enhancementLevel"] = Float(i) / Float(operationCount)
                    _ = profile.updatePreferences(updatedPreferences)
                    
                case .failure(let error):
                    XCTFail("Concurrent operation failed: \(error)")
                }
                
                concurrentExpectation.fulfill()
            }
        }
        
        wait(for: [concurrentExpectation], timeout: 10.0)
    }
    
    // MARK: - Performance Tests
    
    func testProfileCreationPerformance() {
        measure {
            _ = sut.createProfile(
                userId: UUID().uuidString,
                name: "Performance Test Profile",
                preferences: testPreferences
            )
        }
    }
    
    func testProfileRetrievalPerformance() {
        // Create test profile
        let createResult = sut.createProfile(
            userId: testUserId,
            name: testProfileName,
            preferences: testPreferences
        )
        
        guard case .success(let profile) = createResult else {
            XCTFail("Failed to create test profile")
            return
        }
        
        measure {
            _ = sut.getProfile(withId: profile.id)
        }
    }
    
    // MARK: - Validation Tests
    
    func testProfileValidation() {
        // Test invalid preferences
        var invalidPreferences: [String: Any] = [
            "enhancementLevel": 2.0, // Invalid: should be between 0 and 1
            "outputFormat": "Invalid" // Invalid: not in supported formats
        ]
        
        let invalidResult = sut.createProfile(
            userId: testUserId,
            name: testProfileName,
            preferences: invalidPreferences
        )
        
        switch invalidResult {
        case .success:
            XCTFail("Profile creation should fail with invalid preferences")
        case .failure(let error):
            XCTAssertTrue(error.localizedDescription.contains("Invalid preferences"))
        }
        
        // Test empty user ID
        let emptyUserResult = sut.createProfile(
            userId: "",
            name: testProfileName,
            preferences: testPreferences
        )
        
        switch emptyUserResult {
        case .success:
            XCTFail("Profile creation should fail with empty user ID")
        case .failure(let error):
            XCTAssertTrue(error.localizedDescription.contains("Invalid profile"))
        }
    }
}