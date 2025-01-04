//
// VisualizationUITests.swift
// TALD UNIA
//
// Comprehensive UI test suite for audio visualization components
// Version: 1.0.0
//

import XCTest // macOS 13.0+
import XCTMetrics // macOS 13.0+

// MARK: - Constants
private let kTestTimeout: TimeInterval = 5.0
private let kTestAudioDuration: TimeInterval = 10.0
private let kMaxLatencyThreshold: TimeInterval = 0.010 // 10ms requirement
private let kMinFrameRate: Double = 60.0
private let kTestFrequencies: [Double] = [20.0, 1000.0, 20000.0]
private let kReferenceLevel: Float = -18.0 // Professional reference level
private let kTHDNThreshold: Float = 0.0005 // THD+N requirement

@available(macOS 13.0, *)
@MainActor
final class VisualizationUITests: XCTestCase {
    
    // MARK: - Properties
    private var app: XCUIApplication!
    private var isVisualizationActive: Bool = false
    private let performanceMetrics = XCTMetrics.applicationLaunchMetric()
    
    // MARK: - Setup/Teardown
    override func setUp() async throws {
        try await super.setUp()
        continueAfterFailure = false
        
        // Initialize test application
        app = XCUIApplication()
        app.launchArguments = ["--uitesting"]
        
        // Configure performance metrics
        let metrics = XCTOSSignpostMetric.applicationMetric(
            name: "VisualizationPerformance",
            signpostName: "VisualizationUpdate"
        )
        XCTMetricConsumption.add(metrics)
        
        // Launch application and navigate to visualization view
        app.launch()
        
        // Wait for visualization view to appear
        let visualizationView = app.otherElements["VisualizationView"]
        XCTAssertTrue(visualizationView.waitForExistence(timeout: kTestTimeout))
    }
    
    override func tearDown() async throws {
        // Stop audio playback
        if isVisualizationActive {
            app.buttons["StopVisualization"].tap()
            isVisualizationActive = false
        }
        
        // Save performance metrics
        try await XCTMetricConsumption.save()
        
        // Clean up
        app.terminate()
        try await super.tearDown()
    }
    
    // MARK: - Test Cases
    func testSpectrumAnalyzerDisplay() async throws {
        // Configure test frequencies
        let spectrumAnalyzer = app.otherElements["SpectrumAnalyzer"]
        XCTAssertTrue(spectrumAnalyzer.exists)
        
        // Start performance measurement
        measure(metrics: [performanceMetrics]) {
            // Verify frequency bands
            for frequency in kTestFrequencies {
                let bandElement = spectrumAnalyzer.otherElements["FrequencyBand_\(Int(frequency))"]
                XCTAssertTrue(bandElement.exists)
                
                // Verify band visualization
                let bandFrame = bandElement.frame
                XCTAssertGreaterThan(bandFrame.height, 0)
                
                // Check color accuracy
                let colorAttribute = bandElement.value(forKey: "backgroundColor") as? String
                XCTAssertNotNil(colorAttribute)
            }
        }
        
        // Verify accessibility
        XCTAssertTrue(spectrumAnalyzer.isEnabled)
        XCTAssertEqual(spectrumAnalyzer.label, "Audio spectrum analyzer")
        
        // Validate update rate
        let updateMetric = XCTOSSignpostMetric.applicationMetric(name: "SpectrumUpdateRate")
        let result = updateMetric.didComplete()
        XCTAssertGreaterThanOrEqual(result.frameRate, kMinFrameRate)
    }
    
    func testWaveformVisualization() async throws {
        let waveformView = app.otherElements["WaveformView"]
        XCTAssertTrue(waveformView.exists)
        
        // Test waveform rendering
        measure(metrics: [performanceMetrics]) {
            // Start audio playback
            app.buttons["StartPlayback"].tap()
            isVisualizationActive = true
            
            // Verify waveform updates
            let waveformPath = waveformView.otherElements["WaveformPath"]
            XCTAssertTrue(waveformPath.exists)
            
            // Test zoom controls
            let zoomSlider = app.sliders["WaveformZoom"]
            XCTAssertTrue(zoomSlider.exists)
            zoomSlider.adjust(toNormalizedSliderPosition: 0.5)
            
            // Verify scroll behavior
            let scrollView = waveformView.scrollViews.firstMatch
            XCTAssertTrue(scrollView.exists)
            scrollView.swipeLeft()
            scrollView.swipeRight()
        }
        
        // Verify accessibility
        XCTAssertTrue(waveformView.isEnabled)
        XCTAssertEqual(waveformView.label, "Audio waveform display")
    }
    
    func testVUMeterPerformance() async throws {
        let vuMeter = app.otherElements["VUMeter"]
        XCTAssertTrue(vuMeter.exists)
        
        measure(metrics: [performanceMetrics]) {
            // Start calibrated playback
            app.buttons["StartCalibration"].tap()
            isVisualizationActive = true
            
            // Verify meter accuracy
            let levelIndicator = vuMeter.otherElements["LevelIndicator"]
            XCTAssertTrue(levelIndicator.exists)
            
            // Test peak detection
            let peakIndicator = vuMeter.otherElements["PeakIndicator"]
            XCTAssertTrue(peakIndicator.exists)
            
            // Verify reference level
            let referenceLevel = Float(vuMeter.value(forKey: "referenceLevel") as? String ?? "0") ?? 0
            XCTAssertEqual(referenceLevel, kReferenceLevel)
            
            // Check THD+N monitoring
            let thdnValue = Float(vuMeter.value(forKey: "thdnValue") as? String ?? "1") ?? 1
            XCTAssertLessThanOrEqual(thdnValue, kTHDNThreshold)
        }
        
        // Verify accessibility
        XCTAssertTrue(vuMeter.isEnabled)
        XCTAssertEqual(vuMeter.label, "Volume unit meter")
    }
    
    func testVisualizationLatency() async throws {
        // Configure high-precision timer
        let signpostMetric = XCTOSSignpostMetric.applicationMetric(
            name: "VisualizationLatency",
            signpostName: "RenderFrame"
        )
        
        measure(metrics: [signpostMetric]) {
            // Start visualization
            app.buttons["StartVisualization"].tap()
            isVisualizationActive = true
            
            // Measure display latency
            let visualizationView = app.otherElements["VisualizationView"]
            XCTAssertTrue(visualizationView.exists)
            
            // Verify timing requirements
            let latencyResult = signpostMetric.didComplete()
            XCTAssertLessThanOrEqual(
                latencyResult.averageLatency,
                kMaxLatencyThreshold,
                "Visualization latency exceeds 10ms requirement"
            )
        }
        
        // Verify resource usage
        let resourceMetrics = XCTCPUMetric()
        XCTAssertLessThanOrEqual(resourceMetrics.cpuUsage, 40.0)
    }
}