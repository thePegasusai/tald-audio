import XCTest

class ProfileUITests: XCTestCase {
    // MARK: - Properties
    
    /// Main application reference
    var app: XCUIApplication!
    
    /// Standard timeout for UI interactions
    let timeout: TimeInterval = 10
    
    /// Test profile data for validation
    var testProfiles: [String: [String: Any]] = [
        "Studio": [
            "name": "Studio",
            "enhancement": "High",
            "spatialAudio": true,
            "roomSize": "Medium"
        ],
        "Gaming": [
            "name": "Gaming",
            "enhancement": "Maximum",
            "spatialAudio": true,
            "roomSize": "Large"
        ]
    ]
    
    // MARK: - Setup & Teardown
    
    override func setUp() {
        super.setUp()
        
        // Initialize application
        app = XCUIApplication()
        
        // Configure launch arguments for testing mode
        app.launchArguments.append("--uitesting")
        app.launchArguments.append("--reset-state")
        
        // Enable performance metrics collection
        app.launchArguments.append("--enable-performance-monitoring")
        
        // Launch the app
        app.launch()
        
        // Wait for initial load
        XCTAssert(app.wait(for: .runningForeground, timeout: timeout))
    }
    
    override func tearDown() {
        // Clean up test data
        app.terminate()
        
        // Log test completion metrics
        XCTContext.runActivity(named: "Cleanup") { _ in
            // Clear any cached test data
            UserDefaults.standard.removePersistentDomain(forName: app.bundleIdentifier)
        }
        
        super.tearDown()
    }
    
    // MARK: - Test Cases
    
    func testProfileCreation() {
        // Navigate to profile management
        let profileButton = app.buttons["profileManagementButton"]
        XCTAssert(profileButton.waitForExistence(timeout: timeout))
        profileButton.tap()
        
        // Verify add profile button accessibility
        let addButton = app.buttons["addProfileButton"]
        XCTAssert(addButton.isEnabled)
        XCTAssert(addButton.isAccessibilityElement)
        XCTAssertNotNil(addButton.accessibilityLabel)
        
        // Create new profile
        addButton.tap()
        
        // Enter profile name
        let nameField = app.textFields["profileNameField"]
        XCTAssert(nameField.waitForExistence(timeout: timeout))
        nameField.tap()
        nameField.typeText("Studio")
        
        // Configure audio settings
        let enhancementSlider = app.sliders["enhancementLevelSlider"]
        XCTAssert(enhancementSlider.exists)
        enhancementSlider.adjust(toNormalizedSliderPosition: 0.8)
        
        let spatialToggle = app.switches["spatialAudioToggle"]
        XCTAssert(spatialToggle.exists)
        spatialToggle.tap()
        
        let roomSizeSegment = app.segmentedControls["roomSizeControl"]
        XCTAssert(roomSizeSegment.exists)
        roomSizeSegment.buttons["Medium"].tap()
        
        // Save profile
        let saveButton = app.buttons["saveProfileButton"]
        XCTAssert(saveButton.isEnabled)
        saveButton.tap()
        
        // Verify profile creation
        let profileCell = app.cells["profileCell_Studio"]
        XCTAssert(profileCell.waitForExistence(timeout: timeout))
        XCTAssert(profileCell.isAccessibilityElement)
        
        // Verify settings persistence
        profileCell.tap()
        XCTAssertEqual(enhancementSlider.value as? String, "80%")
        XCTAssertTrue(spatialToggle.isOn)
        XCTAssertEqual(roomSizeSegment.selectedSegmentIndex, 1)
    }
    
    func testProfileEditing() {
        // Select existing profile
        let profileCell = app.cells["profileCell_Studio"]
        XCTAssert(profileCell.waitForExistence(timeout: timeout))
        
        // Enter edit mode
        let editButton = profileCell.buttons["editButton"]
        XCTAssert(editButton.exists)
        editButton.tap()
        
        // Modify settings
        let nameField = app.textFields["profileNameField"]
        nameField.tap()
        nameField.clearText()
        nameField.typeText("Studio Pro")
        
        let enhancementSlider = app.sliders["enhancementLevelSlider"]
        enhancementSlider.adjust(toNormalizedSliderPosition: 1.0)
        
        let roomSizeSegment = app.segmentedControls["roomSizeControl"]
        roomSizeSegment.buttons["Large"].tap()
        
        // Save changes
        let saveButton = app.buttons["saveProfileButton"]
        saveButton.tap()
        
        // Verify updates
        let updatedCell = app.cells["profileCell_Studio Pro"]
        XCTAssert(updatedCell.waitForExistence(timeout: timeout))
        
        // Verify settings persistence
        updatedCell.tap()
        XCTAssertEqual(enhancementSlider.value as? String, "100%")
        XCTAssertEqual(roomSizeSegment.selectedSegmentIndex, 2)
    }
    
    func testProfileDeletion() {
        // Select profile for deletion
        let profileCell = app.cells["profileCell_Studio Pro"]
        XCTAssert(profileCell.waitForExistence(timeout: timeout))
        
        // Initiate deletion
        profileCell.swipeLeft()
        let deleteButton = app.buttons["deleteProfileButton"]
        XCTAssert(deleteButton.exists)
        deleteButton.tap()
        
        // Verify confirmation dialog
        let confirmButton = app.alerts.buttons["Delete"]
        XCTAssert(confirmButton.waitForExistence(timeout: timeout))
        confirmButton.tap()
        
        // Verify deletion
        XCTAssertFalse(profileCell.exists)
        
        // Verify default profile activation
        let defaultProfileIndicator = app.staticTexts["defaultProfileIndicator"]
        XCTAssert(defaultProfileIndicator.exists)
    }
    
    func testProfileSwitching() {
        // Create test profiles if needed
        for (name, settings) in testProfiles {
            createTestProfile(name: name, settings: settings)
        }
        
        // Verify profile list
        let profileList = app.collectionViews["profileListView"]
        XCTAssert(profileList.exists)
        
        // Test switching between profiles
        let firstProfile = app.cells["profileCell_Studio"]
        let secondProfile = app.cells["profileCell_Gaming"]
        
        XCTAssert(firstProfile.waitForExistence(timeout: timeout))
        XCTAssert(secondProfile.waitForExistence(timeout: timeout))
        
        // Switch to second profile
        secondProfile.tap()
        
        // Verify transition animation
        let transitionComplete = app.staticTexts["profileActiveIndicator"].waitForExistence(timeout: timeout)
        XCTAssertTrue(transitionComplete)
        
        // Verify settings application
        let enhancementLabel = app.staticTexts["enhancementLevelLabel"]
        XCTAssertEqual(enhancementLabel.label, "Maximum")
    }
    
    func testAccessibility() {
        // Enable VoiceOver for testing
        XCUIDevice.shared.press(XCUIDevice.Button.home, forDuration: 1.0)
        
        // Verify element labeling
        for (name, _) in testProfiles {
            let cell = app.cells["profileCell_\(name)"]
            XCTAssert(cell.isAccessibilityElement)
            XCTAssertNotNil(cell.accessibilityLabel)
            XCTAssertNotNil(cell.accessibilityHint)
        }
        
        // Test navigation
        let profileList = app.collectionViews["profileListView"]
        XCTAssert(profileList.isAccessibilityElement)
        
        // Verify touch targets
        let addButton = app.buttons["addProfileButton"]
        let buttonFrame = addButton.frame
        XCTAssertGreaterThanOrEqual(buttonFrame.width, 44)
        XCTAssertGreaterThanOrEqual(buttonFrame.height, 44)
        
        // Test dynamic type
        XCUIDevice.shared.press(XCUIDevice.Button.home, forDuration: 1.0)
        
        // Verify reduced motion handling
        let preferences = app.buttons["settingsButton"]
        preferences.tap()
        let reduceMotionSwitch = app.switches["reduceMotionSwitch"]
        reduceMotionSwitch.tap()
        
        // Verify UI adapts to reduced motion
        let transitionStyle = app.windows.firstMatch.value(forKey: "layer.speed") as? Float
        XCTAssertEqual(transitionStyle, 0.0)
    }
    
    // MARK: - Helper Methods
    
    private func createTestProfile(name: String, settings: [String: Any]) {
        let addButton = app.buttons["addProfileButton"]
        guard addButton.waitForExistence(timeout: timeout) else {
            XCTFail("Add profile button not found")
            return
        }
        
        addButton.tap()
        
        let nameField = app.textFields["profileNameField"]
        nameField.tap()
        nameField.typeText(name)
        
        if let enhancement = settings["enhancement"] as? String {
            let enhancementControl = app.segmentedControls["enhancementControl"]
            enhancementControl.buttons[enhancement].tap()
        }
        
        if let spatialAudio = settings["spatialAudio"] as? Bool, spatialAudio {
            app.switches["spatialAudioToggle"].tap()
        }
        
        if let roomSize = settings["roomSize"] as? String {
            app.segmentedControls["roomSizeControl"].buttons[roomSize].tap()
        }
        
        app.buttons["saveProfileButton"].tap()
    }
}

// MARK: - XCUIElement Extensions

extension XCUIElement {
    func clearText() {
        guard let stringValue = self.value as? String else {
            return
        }
        
        var deleteString = String()
        stringValue.forEach { _ in deleteString += XCUIKeyboardKey.delete.rawValue }
        typeText(deleteString)
    }
}