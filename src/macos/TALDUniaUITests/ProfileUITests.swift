//
// ProfileUITests.swift
// TALD UNIA
//
// UI test suite for profile management functionality with comprehensive testing
// of audio settings, performance metrics, and error handling
// XCTest version: macOS 13.0+
//

import XCTest

// MARK: - Test Constants
private let TEST_PROFILE_NAME = "Test Profile"
private let TEST_PROFILE_DESCRIPTION = "Test Profile Description"
private let TEST_TIMEOUT: TimeInterval = 5.0
private let PERFORMANCE_THRESHOLD: TimeInterval = 0.010 // 10ms latency requirement
private let THD_THRESHOLD: Double = 0.0005 // THD+N threshold

@available(macOS 13.0, *)
class ProfileUITests: XCTestCase {
    // MARK: - Properties
    private var app: XCUIApplication!
    
    // Accessibility Identifiers
    private let profileListIdentifier = "profileListTable"
    private let createProfileButtonIdentifier = "createProfileButton"
    private let editProfileButtonIdentifier = "editProfileButton"
    private let deleteProfileButtonIdentifier = "deleteProfileButton"
    private let audioSettingsIdentifier = "audioSettingsView"
    private let performanceMetricsIdentifier = "performanceMetricsView"
    private let errorMessageIdentifier = "errorMessageLabel"
    
    // MARK: - Setup and Teardown
    override func setUpWithError() throws {
        try super.setUpWithError()
        continueAfterFailure = false
        
        // Initialize application
        app = XCUIApplication()
        app.launchArguments = ["--uitesting"]
        app.launch()
        
        // Wait for initial UI load
        let profileList = app.tables[profileListIdentifier]
        XCTAssertTrue(profileList.waitForExistence(timeout: TEST_TIMEOUT))
    }
    
    // MARK: - Test Cases
    
    /// Tests creation of a new profile with comprehensive audio settings
    func testCreateProfileWithAudioSettings() throws {
        // Tap create profile button
        let createButton = app.buttons[createProfileButtonIdentifier]
        XCTAssertTrue(createButton.exists)
        createButton.tap()
        
        // Enter profile details
        let nameField = app.textFields["profileNameField"]
        let descriptionField = app.textFields["profileDescriptionField"]
        
        nameField.tap()
        nameField.typeText(TEST_PROFILE_NAME)
        descriptionField.tap()
        descriptionField.typeText(TEST_PROFILE_DESCRIPTION)
        
        // Configure audio settings
        let audioSettings = app.groups[audioSettingsIdentifier]
        XCTAssertTrue(audioSettings.exists)
        
        // Set sample rate
        let sampleRateButton = audioSettings.popUpButtons["sampleRateSelector"]
        sampleRateButton.click()
        sampleRateButton.menuItems["\(AudioConstants.SAMPLE_RATE)"].click()
        
        // Set bit depth
        let bitDepthButton = audioSettings.popUpButtons["bitDepthSelector"]
        bitDepthButton.click()
        bitDepthButton.menuItems["\(AudioConstants.BIT_DEPTH)"].click()
        
        // Enable AI enhancement
        let aiSwitch = audioSettings.switches["aiEnhancementSwitch"]
        if !aiSwitch.isSelected {
            aiSwitch.click()
        }
        
        // Configure spatial audio
        let spatialSwitch = audioSettings.switches["spatialAudioSwitch"]
        if !spatialSwitch.isSelected {
            spatialSwitch.click()
        }
        
        // Set power optimization
        let powerSwitch = audioSettings.switches["powerOptimizationSwitch"]
        if !powerSwitch.isSelected {
            powerSwitch.click()
        }
        
        // Save profile
        app.buttons["saveProfileButton"].tap()
        
        // Verify profile creation
        let profileList = app.tables[profileListIdentifier]
        let createdProfile = profileList.cells.containing(NSPredicate(format: "label CONTAINS %@", TEST_PROFILE_NAME)).element
        XCTAssertTrue(createdProfile.exists)
    }
    
    /// Tests audio quality metrics and performance validation
    func testAudioQualityValidation() throws {
        // Select test profile
        let profileList = app.tables[profileListIdentifier]
        let testProfile = profileList.cells.containing(NSPredicate(format: "label CONTAINS %@", TEST_PROFILE_NAME)).element
        testProfile.tap()
        
        // Access performance metrics view
        let metricsView = app.groups[performanceMetricsIdentifier]
        XCTAssertTrue(metricsView.exists)
        
        // Validate THD+N
        let thdValue = Double(metricsView.staticTexts["thdValueLabel"].label) ?? 1.0
        XCTAssertLessThanOrEqual(thdValue, THD_THRESHOLD)
        
        // Validate processing latency
        let latencyValue = TimeInterval(metricsView.staticTexts["latencyValueLabel"].label) ?? 1.0
        XCTAssertLessThanOrEqual(latencyValue, PERFORMANCE_THRESHOLD)
        
        // Validate power efficiency
        let efficiencyValue = Double(metricsView.staticTexts["efficiencyValueLabel"].label) ?? 0.0
        XCTAssertGreaterThanOrEqual(efficiencyValue, AudioConstants.AMPLIFIER_EFFICIENCY)
    }
    
    /// Tests error handling and recovery procedures
    func testErrorHandling() throws {
        // Create profile with invalid settings
        let createButton = app.buttons[createProfileButtonIdentifier]
        createButton.tap()
        
        // Set invalid sample rate
        let audioSettings = app.groups[audioSettingsIdentifier]
        let sampleRateField = audioSettings.textFields["sampleRateField"]
        sampleRateField.tap()
        sampleRateField.typeText("48000") // Invalid sample rate
        
        // Attempt to save
        app.buttons["saveProfileButton"].tap()
        
        // Verify error message
        let errorMessage = app.staticTexts[errorMessageIdentifier]
        XCTAssertTrue(errorMessage.exists)
        XCTAssertTrue(errorMessage.label.contains("INVALID_SAMPLE_RATE"))
        
        // Test recovery
        sampleRateField.tap()
        sampleRateField.typeText("\(AudioConstants.SAMPLE_RATE)")
        app.buttons["saveProfileButton"].tap()
        
        // Verify error cleared
        XCTAssertFalse(errorMessage.exists)
    }
    
    /// Tests profile update functionality
    func testUpdateProfile() throws {
        // Select existing profile
        let profileList = app.tables[profileListIdentifier]
        let testProfile = profileList.cells.containing(NSPredicate(format: "label CONTAINS %@", TEST_PROFILE_NAME)).element
        testProfile.tap()
        
        // Enter edit mode
        let editButton = app.buttons[editProfileButtonIdentifier]
        editButton.tap()
        
        // Update description
        let descriptionField = app.textFields["profileDescriptionField"]
        descriptionField.tap()
        descriptionField.typeText(" Updated")
        
        // Update audio settings
        let audioSettings = app.groups[audioSettingsIdentifier]
        let enhancementSlider = audioSettings.sliders["enhancementQualitySlider"]
        enhancementSlider.adjust(toNormalizedSliderPosition: 0.8)
        
        // Save changes
        app.buttons["saveProfileButton"].tap()
        
        // Verify updates
        let updatedProfile = profileList.cells.containing(NSPredicate(format: "label CONTAINS %@", TEST_PROFILE_NAME)).element
        XCTAssertTrue(updatedProfile.exists)
        XCTAssertTrue(updatedProfile.staticTexts["profileDescriptionLabel"].label.contains("Updated"))
    }
}