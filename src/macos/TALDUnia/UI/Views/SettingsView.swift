//
// SettingsView.swift
// TALD UNIA
//
// A SwiftUI view that provides the settings interface for the TALD UNIA macOS application
// with comprehensive audio configuration, power efficiency monitoring, and quality metrics
// Version: 1.0.0
//

import SwiftUI // macOS 13.0+

// MARK: - Constants
private let SECTION_SPACING: CGFloat = 24.0
private let CONTROL_SPACING: CGFloat = 16.0

// MARK: - Audio Quality Metrics
private struct AudioQualityMetrics {
    var thdPlusNoise: Double
    var latency: TimeInterval
    var powerEfficiency: Double
}

@available(macOS 13.0, *)
public struct SettingsView: View {
    // MARK: - Properties
    @State private var selectedTab: Int = 0
    @State private var audioQuality: Double = 1.0
    @State private var aiEnhancement: Bool = true
    @State private var spatialAudio: Bool = true
    @State private var showingResetAlert: Bool = false
    @State private var powerEfficiency: Double = 0.0
    @State private var qualityMetrics = AudioQualityMetrics(
        thdPlusNoise: 0.0,
        latency: 0.0,
        powerEfficiency: 0.0
    )
    @State private var processingLatency: TimeInterval = 0.0
    
    // MARK: - Body
    public var body: some View {
        VStack(spacing: SECTION_SPACING) {
            // Audio Processing Settings
            GroupBox("Audio Processing") {
                VStack(alignment: .leading, spacing: CONTROL_SPACING) {
                    CustomSlider(
                        value: $audioQuality,
                        range: 0...1,
                        label: "Audio Quality"
                    ) { value in
                        updateAudioSettings(["quality": value])
                    }
                    
                    Toggle("AI Enhancement", isOn: $aiEnhancement)
                        .onChange(of: aiEnhancement) { newValue in
                            updateAudioSettings(["aiEnhancement": newValue])
                        }
                    
                    Toggle("Spatial Audio", isOn: $spatialAudio)
                        .onChange(of: spatialAudio) { newValue in
                            updateAudioSettings(["spatialAudio": newValue])
                        }
                }
                .padding()
            }
            
            // Power Efficiency Section
            powerEfficiencySection
            
            // Quality Metrics Section
            qualityMetricsSection
            
            // Reset Button
            Button("Reset to Defaults") {
                showingResetAlert = true
            }
            .alert("Reset Settings", isPresented: $showingResetAlert) {
                Button("Cancel", role: .cancel) {}
                Button("Reset", role: .destructive) {
                    resetSettings()
                }
            } message: {
                Text("This will reset all settings to their default values.")
            }
        }
        .padding()
        .frame(minWidth: 500, minHeight: 600)
        .background(Colors.background)
        .onAppear {
            initializeSettings()
            startMonitoring()
        }
    }
    
    // MARK: - Power Efficiency Section
    private var powerEfficiencySection: some View {
        GroupBox("Power Efficiency") {
            VStack(alignment: .leading, spacing: CONTROL_SPACING) {
                HStack {
                    Text("Current Efficiency:")
                        .font(Typography.bodyMedium)
                    Text(String(format: "%.1f%%", powerEfficiency * 100))
                        .font(Typography.bodyMedium)
                        .foregroundColor(
                            powerEfficiency >= AudioConstants.AMPLIFIER_EFFICIENCY ?
                            Colors.primary : Colors.error
                        )
                }
                
                ProgressView(
                    value: powerEfficiency,
                    total: 1.0
                )
                .tint(
                    powerEfficiency >= AudioConstants.AMPLIFIER_EFFICIENCY ?
                    Colors.primary : Colors.error
                )
                
                if powerEfficiency < AudioConstants.AMPLIFIER_EFFICIENCY {
                    Text("Power efficiency below target")
                        .font(Typography.bodyMedium)
                        .foregroundColor(Colors.error)
                }
            }
            .padding()
        }
    }
    
    // MARK: - Quality Metrics Section
    private var qualityMetricsSection: some View {
        GroupBox("Quality Metrics") {
            VStack(alignment: .leading, spacing: CONTROL_SPACING) {
                HStack {
                    Text("THD+N:")
                        .font(Typography.bodyMedium)
                    Text(String(format: "%.4f%%", qualityMetrics.thdPlusNoise * 100))
                        .font(Typography.bodyMedium)
                        .foregroundColor(
                            qualityMetrics.thdPlusNoise <= AudioConstants.THD_N_THRESHOLD ?
                            Colors.primary : Colors.error
                        )
                }
                
                HStack {
                    Text("Processing Latency:")
                        .font(Typography.bodyMedium)
                    Text(String(format: "%.1fms", qualityMetrics.latency * 1000))
                        .font(Typography.bodyMedium)
                        .foregroundColor(
                            qualityMetrics.latency <= AudioConstants.TARGET_LATENCY ?
                            Colors.primary : Colors.error
                        )
                }
            }
            .padding()
        }
    }
    
    // MARK: - Private Methods
    private func initializeSettings() {
        do {
            if let settings = try SettingsManager.shared.loadSettings() {
                audioQuality = Double(settings.masterVolume)
                aiEnhancement = settings.enhancementEnabled
                spatialAudio = settings.spatialEnabled
                powerEfficiency = Double(
                    settings.powerOptimizationSettings["efficiencyTarget"] ?? 
                    Float(AudioConstants.AMPLIFIER_EFFICIENCY)
                )
            }
        } catch {
            print("Failed to load settings: \(error)")
        }
    }
    
    private func startMonitoring() {
        // Start power efficiency monitoring
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            powerEfficiency = SettingsManager.shared.monitorPowerEfficiency()
        }
        
        // Start quality metrics monitoring
        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            let metrics = SettingsManager.shared.trackQualityMetrics()
            qualityMetrics = AudioQualityMetrics(
                thdPlusNoise: metrics["thdPlusNoise"] as? Double ?? 0.0,
                latency: metrics["latency"] as? TimeInterval ?? 0.0,
                powerEfficiency: metrics["powerEfficiency"] as? Double ?? 0.0
            )
        }
    }
    
    private func updateAudioSettings(_ parameters: [String: Any]) {
        do {
            try SettingsManager.shared.updateSettings(parameters)
        } catch {
            print("Failed to update settings: \(error)")
        }
    }
    
    private func resetSettings() {
        do {
            let defaultSettings = AudioSettings()
            try SettingsManager.shared.saveSettings(defaultSettings)
            initializeSettings()
        } catch {
            print("Failed to reset settings: \(error)")
        }
    }
}

// MARK: - Preview Provider
struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView()
            .frame(width: 600, height: 800)
            .preferredColorScheme(.dark)
    }
}