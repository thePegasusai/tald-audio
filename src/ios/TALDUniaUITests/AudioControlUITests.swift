import XCTest
@testable import TALDUnia

@available(iOS 14.0, *)
final class AudioControlUITests: XCTestCase {
    
    // MARK: - Properties
    
    private var app: XCUIApplication!
    private var metrics: XCTMetrics!
    private let defaultTimeout: TimeInterval = 5.0
    
    // MARK: - Setup & Teardown
    
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        
        // Initialize performance metrics
        metrics = XCTMetrics()
        metrics.activate()
        
        // Configure app for testing
        app.launchArguments = ["UI_TESTING"]
        app.launch()
        
        // Wait for audio control view to load
        let audioControlView = app.otherElements["AudioControlView"]
        XCTAssertTrue(audioControlView.waitForExistence(timeout: defaultTimeout))
    }
    
    override func tearDownWithError() throws {
        metrics.deactivate()
        app.terminate()
    }
    
    // MARK: - Volume Control Tests
    
    func testVolumeControl() throws {
        measure(metrics: metrics) {
            // Test volume slider existence and accessibility
            let volumeSlider = app.sliders["VolumeSlider"]
            XCTAssertTrue(volumeSlider.exists)
            XCTAssertTrue(volumeSlider.isEnabled)
            XCTAssertNotNil(volumeSlider.value)
            
            // Test precise volume adjustments
            let startValue = (volumeSlider.value as? String).flatMap(Double.init) ?? 0.0
            volumeSlider.adjust(toNormalizedSliderPosition: 0.75)
            
            // Verify VU meter updates
            let vuMeter = app.otherElements["VUMeter"]
            XCTAssertTrue(vuMeter.exists)
            
            // Test volume change latency
            let startTime = CACurrentMediaTime()
            volumeSlider.adjust(toNormalizedSliderPosition: 0.5)
            let endTime = CACurrentMediaTime()
            let latency = endTime - startTime
            XCTAssertLessThanOrEqual(latency, 0.010) // 10ms max latency
            
            // Test keyboard accessibility
            volumeSlider.typeText(.leftArrow)
            volumeSlider.typeText(.rightArrow)
            
            // Test audio quality metrics
            let processingIndicator = app.otherElements["ProcessingIndicator"]
            let thdValue = (processingIndicator.value as? String).flatMap { str -> Double? in
                let pattern = "THD: ([0-9.]+)%"
                let regex = try? NSRegularExpression(pattern: pattern)
                let range = NSRange(str.startIndex..., in: str)
                if let match = regex?.firstMatch(in: str, range: range),
                   let thdRange = Range(match.range(at: 1), in: str) {
                    return Double(str[thdRange])
                }
                return nil
            }
            XCTAssertNotNil(thdValue)
            XCTAssertLessThanOrEqual(thdValue ?? 1.0, 0.0005) // THD+N < 0.0005%
        }
    }
    
    // MARK: - Enhancement Toggle Tests
    
    func testEnhancementToggle() throws {
        measure(metrics: metrics) {
            // Test enhancement toggle existence and accessibility
            let enhancementToggle = app.switches["EnhancementToggle"]
            XCTAssertTrue(enhancementToggle.exists)
            XCTAssertTrue(enhancementToggle.isEnabled)
            
            // Test toggle state changes
            let initialState = enhancementToggle.isOn
            enhancementToggle.tap()
            XCTAssertNotEqual(enhancementToggle.isOn, initialState)
            
            // Test processing latency
            let startTime = CACurrentMediaTime()
            enhancementToggle.tap()
            let endTime = CACurrentMediaTime()
            let latency = endTime - startTime
            XCTAssertLessThanOrEqual(latency, 0.010) // 10ms max latency
            
            // Verify visual feedback
            let processingIndicator = app.otherElements["ProcessingIndicator"]
            XCTAssertTrue(processingIndicator.exists)
            
            // Test accessibility label updates
            XCTAssertNotNil(enhancementToggle.label)
            XCTAssertNotNil(enhancementToggle.value)
        }
    }
    
    // MARK: - Spatial Audio Tests
    
    func testSpatialAudioToggle() throws {
        measure(metrics: metrics) {
            // Test spatial toggle existence and accessibility
            let spatialToggle = app.switches["SpatialToggle"]
            XCTAssertTrue(spatialToggle.exists)
            XCTAssertTrue(spatialToggle.isEnabled)
            
            // Test toggle state changes
            let initialState = spatialToggle.isOn
            spatialToggle.tap()
            XCTAssertNotEqual(spatialToggle.isOn, initialState)
            
            // Test head tracking reset button
            if spatialToggle.isOn {
                let resetButton = app.buttons["ResetHeadPosition"]
                XCTAssertTrue(resetButton.exists)
                XCTAssertTrue(resetButton.isEnabled)
                resetButton.tap()
            }
            
            // Test processing latency
            let startTime = CACurrentMediaTime()
            spatialToggle.tap()
            let endTime = CACurrentMediaTime()
            let latency = endTime - startTime
            XCTAssertLessThanOrEqual(latency, 0.010) // 10ms max latency
        }
    }
    
    // MARK: - Processing State Tests
    
    func testProcessingStateIndicator() throws {
        measure(metrics: metrics) {
            // Test processing indicator existence
            let processingIndicator = app.otherElements["ProcessingIndicator"]
            XCTAssertTrue(processingIndicator.exists)
            
            // Test latency display
            let latencyText = processingIndicator.staticTexts.element(matching: NSPredicate(format: "label CONTAINS 'Latency'"))
            XCTAssertTrue(latencyText.exists)
            
            // Extract and verify latency value
            if let latencyString = latencyText.label,
               let latencyValue = Double(latencyString.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()) {
                XCTAssertLessThanOrEqual(latencyValue, 10.0) // 10ms max latency
            }
            
            // Test THD display
            let thdText = processingIndicator.staticTexts.element(matching: NSPredicate(format: "label CONTAINS 'THD'"))
            XCTAssertTrue(thdText.exists)
            
            // Verify contrast ratio for accessibility
            if let backgroundColor = processingIndicator.value(forKey: "backgroundColor") as? UIColor,
               let textColor = thdText.value(forKey: "textColor") as? UIColor {
                let contrast = calculateContrastRatio(backgroundColor, textColor)
                XCTAssertGreaterThanOrEqual(contrast, 4.5) // WCAG 2.1 AA requirement
            }
        }
    }
    
    // MARK: - Helper Methods
    
    private func calculateContrastRatio(_ color1: UIColor, _ color2: UIColor) -> CGFloat {
        func luminance(_ color: UIColor) -> CGFloat {
            var red: CGFloat = 0
            var green: CGFloat = 0
            var blue: CGFloat = 0
            color.getRed(&red, green: &green, blue: &blue, alpha: nil)
            
            let rLum = red <= 0.03928 ? red/12.92 : pow((red + 0.055)/1.055, 2.4)
            let gLum = green <= 0.03928 ? green/12.92 : pow((green + 0.055)/1.055, 2.4)
            let bLum = blue <= 0.03928 ? blue/12.92 : pow((blue + 0.055)/1.055, 2.4)
            
            return 0.2126 * rLum + 0.7152 * gLum + 0.0722 * bLum
        }
        
        let l1 = luminance(color1)
        let l2 = luminance(color2)
        let lighter = max(l1, l2)
        let darker = min(l1, l2)
        
        return (lighter + 0.05)/(darker + 0.05)
    }
}