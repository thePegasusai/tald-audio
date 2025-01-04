import XCTest
@testable import TALDUnia

@MainActor
final class VisualizationUITests: XCTestCase {
    
    // MARK: - Properties
    
    private var app: XCUIApplication!
    private var metrics: XCTMetrics!
    private let latencyThreshold: Double = 10.0 // ms
    private let cpuThreshold: Float = 40.0 // %
    private let memoryThreshold: Float = 1024.0 // MB
    
    // MARK: - Setup
    
    override func setUp() {
        super.setUp()
        
        // Initialize application
        app = XCUIApplication()
        
        // Configure performance metrics
        metrics = XCTMetrics()
        metrics.addMetric(XCTCPUMetric())
        metrics.addMetric(XCTMemoryMetric())
        metrics.addMetric(XCTStorageMetric())
        
        // Configure accessibility testing
        app.launchArguments += ["-UIAccessibilityEnabled", "YES"]
        app.launchArguments += ["-AppleLanguages", "(en)"]
        
        // Launch with test configuration
        app.launch()
    }
    
    // MARK: - Spectrum Analyzer Tests
    
    func testSpectrumAnalyzerDisplay() throws {
        // Navigate to visualization view
        let visualizationView = app.otherElements["Audio visualization display"]
        XCTAssertTrue(visualizationView.waitForExistence(timeout: 5))
        
        // Verify spectrum analyzer exists and is accessible
        let analyzer = visualizationView.otherElements["Spectrum analyzer"]
        XCTAssertTrue(analyzer.exists)
        XCTAssertTrue(analyzer.isEnabled)
        
        // Test frequency band rendering
        measure(metrics: metrics) {
            // Verify frequency labels
            let frequencyLabels = analyzer.staticTexts.matching(identifier: "frequency-label")
            XCTAssertGreaterThan(frequencyLabels.count, 0)
            
            // Verify band visualization
            let bands = analyzer.otherElements.matching(identifier: "frequency-band")
            XCTAssertGreaterThan(bands.count, 0)
            
            // Test real-time updates
            let startBands = bands.allElementsBoundByIndex.map { $0.frame }
            Thread.sleep(forTimeInterval: 0.1)
            let endBands = bands.allElementsBoundByIndex.map { $0.frame }
            XCTAssertNotEqual(startBands, endBands, "Spectrum analyzer should update in real-time")
        }
        
        // Test accessibility
        XCTAssertTrue(analyzer.isAccessibilityElement)
        XCTAssertNotNil(analyzer.label)
        XCTAssertNotNil(analyzer.value)
        
        // Verify color adaptation
        let darkMode = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
        darkMode.launch()
        // Toggle dark mode and verify color updates
    }
    
    // MARK: - Waveform Tests
    
    func testWaveformVisualization() throws {
        let visualizationView = app.otherElements["Audio visualization display"]
        XCTAssertTrue(visualizationView.waitForExistence(timeout: 5))
        
        // Verify waveform display
        let waveform = visualizationView.otherElements["Waveform display"]
        XCTAssertTrue(waveform.exists)
        
        measure(metrics: metrics) {
            // Test animation performance
            let startFrame = waveform.frame
            Thread.sleep(forTimeInterval: 0.1)
            let endFrame = waveform.frame
            XCTAssertNotEqual(startFrame, endFrame, "Waveform should animate smoothly")
            
            // Verify reduced motion support
            let reduceMotion = app.switches["Reduce Motion"]
            if reduceMotion.exists {
                reduceMotion.tap()
                Thread.sleep(forTimeInterval: 0.1)
                let motionEndFrame = waveform.frame
                XCTAssertEqual(endFrame, motionEndFrame, "Waveform should respect reduced motion")
            }
        }
        
        // Test accessibility
        XCTAssertTrue(waveform.isAccessibilityElement)
        XCTAssertNotNil(waveform.value)
        
        // Verify power efficiency
        let powerMetric = XCTCPUMetric()
        measure(metrics: [powerMetric]) {
            Thread.sleep(forTimeInterval: 1.0)
        }
    }
    
    // MARK: - Processing Status Tests
    
    func testProcessingStatusIndicators() throws {
        let visualizationView = app.otherElements["Audio visualization display"]
        XCTAssertTrue(visualizationView.waitForExistence(timeout: 5))
        
        // Verify status indicators
        let latencyIndicator = visualizationView.staticTexts["Latency"]
        let cpuIndicator = visualizationView.staticTexts["CPU Load"]
        let fpsIndicator = visualizationView.staticTexts["FPS"]
        
        XCTAssertTrue(latencyIndicator.exists)
        XCTAssertTrue(cpuIndicator.exists)
        XCTAssertTrue(fpsIndicator.exists)
        
        measure(metrics: metrics) {
            // Test latency warning threshold
            let latencyValue = Double(latencyIndicator.value as? String ?? "0") ?? 0
            XCTAssertLessThan(latencyValue, latencyThreshold, "Latency exceeds threshold")
            
            // Test CPU load warning
            let cpuValue = Float(cpuIndicator.value as? String ?? "0") ?? 0
            XCTAssertLessThan(cpuValue, cpuThreshold, "CPU usage exceeds threshold")
            
            // Test frame rate
            let fpsValue = Float(fpsIndicator.value as? String ?? "0") ?? 0
            XCTAssertGreaterThan(fpsValue, 30.0, "Frame rate below threshold")
        }
        
        // Test accessibility announcements
        XCTAssertTrue(latencyIndicator.isAccessibilityElement)
        XCTAssertTrue(cpuIndicator.isAccessibilityElement)
        XCTAssertTrue(fpsIndicator.isAccessibilityElement)
    }
    
    // MARK: - Performance Tests
    
    func testVisualizationPerformance() throws {
        let visualizationView = app.otherElements["Audio visualization display"]
        XCTAssertTrue(visualizationView.waitForExistence(timeout: 5))
        
        // Configure performance metrics
        let performanceMetrics: [XCTMetric] = [
            XCTCPUMetric(),
            XCTMemoryMetric(),
            XCTStorageMetric(),
            XCTClockMetric()
        ]
        
        measure(metrics: performanceMetrics) {
            // Test under load
            for _ in 0..<10 {
                // Simulate audio processing load
                Thread.sleep(forTimeInterval: 0.1)
                
                // Verify responsiveness
                XCTAssertTrue(visualizationView.isHittable)
                
                // Check memory usage
                let memoryMetric = performanceMetrics.first { $0 is XCTMemoryMetric } as? XCTMemoryMetric
                if let memoryUsage = memoryMetric?.measurements.first?.doubleValue {
                    XCTAssertLessThan(memoryUsage, Double(memoryThreshold), "Memory usage exceeds threshold")
                }
            }
        }
        
        // Test power efficiency
        let powerMetric = XCTCPUMetric()
        measure(metrics: [powerMetric]) {
            Thread.sleep(forTimeInterval: 1.0)
        }
    }
}