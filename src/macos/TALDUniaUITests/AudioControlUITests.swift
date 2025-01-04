//
// AudioControlUITests.swift
// TALD UNIA
//
// UI test suite for audio control interface with comprehensive test coverage
// Version: 1.0.0
//

import XCTest // macOS 13.0+
@testable import TALDUnia // Version 1.0.0

// MARK: - Test Constants
private let TEST_TIMEOUT: TimeInterval = 5.0
private let VOLUME_TEST_VALUES: [Double] = [-60.0, -48.0, -36.0, -24.0, -12.0, 0.0, 6.0, 12.0]
private let PERFORMANCE_THRESHOLD: TimeInterval = 0.010 // 10ms requirement
private let THD_N_THRESHOLD: Double = 0.0005 // Burmester-level quality requirement

class AudioControlUITests: XCTestCase {
    // MARK: - Properties
    private var app: XCUIApplication!
    private var volumeSlider: XCUIElement!
    private var playButton: XCUIElement!
    private var enhancementToggle: XCUIElement!
    private var spatialControls: XCUIElement!
    private var performanceMonitor: XCUIElement!
    
    // MARK: - Setup
    override func setUp() {
        super.setUp()
        
        // Initialize application with performance monitoring
        app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--enable-performance-monitoring"]
        app.launchEnvironment = [
            "TALD_TEST_MODE": "1",
            "TALD_PERFORMANCE_LOGGING": "1"
        ]
        
        // Configure test metrics collection
        continueAfterFailure = false
        XCTMetric.applicationLaunchMetric.map { app.measure(metrics: [$0]) }
        
        // Initialize UI elements
        volumeSlider = app.sliders["Volume Control"]
        playButton = app.buttons["Play"]
        enhancementToggle = app.switches["AI Enhancement"]
        spatialControls = app.groups["Spatial Audio Controls"]
        performanceMonitor = app.groups["Performance Monitor"]
        
        app.launch()
    }
    
    // MARK: - Audio Control Tests
    func testVolumeControl() throws {
        // Verify volume slider accessibility
        XCTAssertTrue(volumeSlider.exists, "Volume slider not found")
        XCTAssertTrue(volumeSlider.isEnabled, "Volume slider not enabled")
        XCTAssertTrue(volumeSlider.isHittable, "Volume slider not hittable")
        
        // Test volume adjustments with audio quality verification
        for volume in VOLUME_TEST_VALUES {
            // Set volume
            volumeSlider.adjust(toNormalizedSliderPosition: normalizeVolume(volume))
            
            // Verify volume update
            let currentVolume = try XCTUnwrap(volumeSlider.value as? Double)
            XCTAssertEqual(currentVolume, volume, accuracy: 0.1, "Volume not set correctly")
            
            // Measure THD+N at current volume
            let metrics = try XCTUnwrap(performanceMonitor.staticTexts["THD+N"].label)
            let thdnValue = try XCTUnwrap(Double(metrics.replacingOccurrences(of: "%", with: "")))
            XCTAssertLessThanOrEqual(thdnValue, THD_N_THRESHOLD * 100, "THD+N exceeds quality threshold")
            
            // Verify processing latency
            let latencyText = try XCTUnwrap(performanceMonitor.staticTexts["Latency"].label)
            let latencyValue = try XCTUnwrap(Double(latencyText.replacingOccurrences(of: " ms", with: "")))
            XCTAssertLessThanOrEqual(latencyValue, PERFORMANCE_THRESHOLD * 1000, "Processing latency exceeds threshold")
        }
    }
    
    func testPlaybackControls() throws {
        // Verify play button state
        XCTAssertTrue(playButton.exists, "Play button not found")
        XCTAssertTrue(playButton.isEnabled, "Play button not enabled")
        
        // Test play/pause toggle
        playButton.tap()
        XCTAssertEqual(playButton.label, "Pause", "Button not updated to pause state")
        
        // Verify audio processing
        let processingLoad = try XCTUnwrap(performanceMonitor.staticTexts["Processing Load"].label)
        XCTAssertTrue(processingLoad.contains("%"), "Processing load not displayed")
        
        // Test pause
        playButton.tap()
        XCTAssertEqual(playButton.label, "Play", "Button not updated to play state")
    }
    
    func testEnhancementControls() throws {
        // Verify enhancement toggle
        XCTAssertTrue(enhancementToggle.exists, "Enhancement toggle not found")
        XCTAssertTrue(enhancementToggle.isEnabled, "Enhancement toggle not enabled")
        
        // Test AI enhancement
        enhancementToggle.tap()
        XCTAssertTrue(enhancementToggle.isSelected, "Enhancement not enabled")
        
        // Verify processing impact
        let processingTime = try XCTUnwrap(performanceMonitor.staticTexts["Latency"].label)
        let latencyValue = try XCTUnwrap(Double(processingTime.replacingOccurrences(of: " ms", with: "")))
        XCTAssertLessThanOrEqual(latencyValue, PERFORMANCE_THRESHOLD * 1000, "Enhancement processing exceeds latency threshold")
    }
    
    func testSpatialAudioControls() throws {
        // Verify spatial controls
        XCTAssertTrue(spatialControls.exists, "Spatial controls not found")
        
        // Test spatial audio toggle
        let spatialToggle = spatialControls.switches["Spatial Audio"]
        XCTAssertTrue(spatialToggle.exists, "Spatial toggle not found")
        
        spatialToggle.tap()
        XCTAssertTrue(spatialToggle.isSelected, "Spatial audio not enabled")
        
        // Verify head tracking
        let headTrackingToggle = spatialControls.switches["Head Tracking"]
        XCTAssertTrue(headTrackingToggle.exists, "Head tracking toggle not found")
        
        headTrackingToggle.tap()
        XCTAssertTrue(headTrackingToggle.isSelected, "Head tracking not enabled")
    }
    
    func testPerformanceMetrics() throws {
        // Enable performance monitoring
        performanceMonitor.tap()
        
        // Verify metrics display
        XCTAssertTrue(performanceMonitor.exists, "Performance monitor not displayed")
        
        // Test audio processing performance
        measure(metrics: [XCTCPUMetric(), XCTMemoryMetric(), XCTStorageMetric()]) {
            // Generate audio load
            playButton.tap()
            volumeSlider.adjust(toNormalizedSliderPosition: 0.75)
            enhancementToggle.tap()
            
            // Verify performance under load
            let latencyText = try! XCTUnwrap(performanceMonitor.staticTexts["Latency"].label)
            let latencyValue = try! XCTUnwrap(Double(latencyText.replacingOccurrences(of: " ms", with: "")))
            XCTAssertLessThanOrEqual(latencyValue, PERFORMANCE_THRESHOLD * 1000, "Performance degraded under load")
        }
    }
    
    func testAccessibility() throws {
        // Verify accessibility labels
        XCTAssertEqual(volumeSlider.label, "Volume Control", "Invalid volume slider accessibility label")
        XCTAssertEqual(playButton.label, "Play", "Invalid play button accessibility label")
        XCTAssertEqual(enhancementToggle.label, "AI Enhancement", "Invalid enhancement toggle accessibility label")
        
        // Test keyboard navigation
        XCUIElement.perform(withKeyModifiers: .command) {
            XCUIElement.typeKey(XCUIKeyboardKey.tab, modifierFlags: [])
        }
        XCTAssertTrue(playButton.hasKeyboardFocus, "Keyboard navigation failed")
        
        // Verify color contrast
        let colorContrast = try XCTUnwrap(app.staticTexts["Volume (dB)"].value as? String)
        XCTAssertFalse(colorContrast.isEmpty, "Color contrast text not accessible")
    }
    
    // MARK: - Helper Methods
    private func normalizeVolume(_ value: Double) -> Double {
        return (value + 60.0) / 72.0 // Scale -60dB to +12dB to 0-1 range
    }
}