//
// ProfileView.swift
// TALD UNIA
//
// A SwiftUI view that provides the user interface for managing audio profiles
// with real-time monitoring and power-aware validation
// Version: 1.0.0
//

import SwiftUI // macOS 13.0+

// MARK: - Constants
private let PROFILE_LIST_MAX_HEIGHT: CGFloat = 400
private let PROFILE_FORM_SPACING: CGFloat = 16
private let AUDIO_QUALITY_UPDATE_INTERVAL: TimeInterval = 0.1
private let POWER_EFFICIENCY_THRESHOLD: Double = 0.9

// MARK: - Audio Quality Metrics
private struct AudioQualityMetrics {
    var thdPlusNoise: Double = 0.0
    var signalToNoise: Double = 120.0
    var processingLatency: Double = 0.0
    var powerEfficiency: Double = 0.0
}

@available(macOS 13.0, *)
@MainActor
public struct ProfileView: View {
    // MARK: - Properties
    @StateObject private var viewModel = ProfileViewModel()
    @State private var isCreatingProfile = false
    @State private var isEditingProfile = false
    @State private var selectedProfileId: UUID?
    @State private var audioQualityMetrics = AudioQualityMetrics()
    @State private var errorState: TALDError?
    
    // MARK: - Timer for Quality Monitoring
    @State private var qualityMonitorTimer: Timer?
    
    // MARK: - Body
    public var body: some View {
        NavigationStack {
            HStack(spacing: Layout.spacing4) {
                // MARK: - Profile List Section
                VStack(alignment: .leading, spacing: Layout.spacing3) {
                    Text("Audio Profiles")
                        .font(Typography.headlineSmall)
                        .foregroundColor(Colors.onSurface)
                    
                    ScrollView {
                        LazyVStack(spacing: Layout.spacing2) {
                            ForEach(viewModel.profiles, id: \.id) { profile in
                                ProfileListItem(
                                    profile: profile,
                                    isActive: viewModel.activeProfile?.id == profile.id,
                                    onSelect: { handleProfileSelection(profile) }
                                )
                            }
                        }
                    }
                    .frame(maxHeight: PROFILE_LIST_MAX_HEIGHT)
                    
                    Button(action: { isCreatingProfile = true }) {
                        Label("Create Profile", systemImage: "plus.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Colors.primary)
                }
                .frame(width: 300)
                .padding(Layout.spacing3)
                .background(Colors.surface)
                .cornerRadius(8)
                
                // MARK: - Profile Detail Section
                if let selectedProfile = viewModel.profiles.first(where: { $0.id == selectedProfileId }) {
                    VStack(alignment: .leading, spacing: Layout.spacing4) {
                        // Profile Header
                        HStack {
                            Text(selectedProfile.name)
                                .font(Typography.headlineMedium)
                                .foregroundColor(Colors.onSurface)
                            
                            Spacer()
                            
                            Button(action: { isEditingProfile = true }) {
                                Label("Edit", systemImage: "pencil.circle")
                            }
                            .disabled(selectedProfile.isDefault)
                        }
                        
                        // Audio Quality Metrics
                        VStack(alignment: .leading, spacing: Layout.spacing3) {
                            Text("Audio Quality Metrics")
                                .font(Typography.labelLarge)
                                .foregroundColor(Colors.onSurface)
                            
                            MetricsGrid(metrics: audioQualityMetrics)
                        }
                        
                        // Audio Settings
                        VStack(alignment: .leading, spacing: Layout.spacing3) {
                            Text("Audio Settings")
                                .font(Typography.labelLarge)
                                .foregroundColor(Colors.onSurface)
                            
                            // Volume Control
                            CustomSlider(
                                value: Binding(
                                    get: { Double(selectedProfile.audioSettings.masterVolume) },
                                    set: { updateMasterVolume(selectedProfile, value: Float($0)) }
                                ),
                                label: "Master Volume",
                                isEnabled: !selectedProfile.isDefault
                            )
                            
                            // Enhancement Controls
                            Toggle("AI Enhancement", isOn: Binding(
                                get: { selectedProfile.aiEnhancementEnabled },
                                set: { updateEnhancement(selectedProfile, enabled: $0) }
                            ))
                            .disabled(selectedProfile.isDefault)
                            
                            Toggle("Spatial Audio", isOn: Binding(
                                get: { selectedProfile.spatialAudioEnabled },
                                set: { updateSpatialAudio(selectedProfile, enabled: $0) }
                            ))
                            .disabled(selectedProfile.isDefault)
                            
                            Toggle("Power Optimization", isOn: Binding(
                                get: { selectedProfile.powerOptimizationEnabled },
                                set: { updatePowerOptimization(selectedProfile, enabled: $0) }
                            ))
                            .disabled(selectedProfile.isDefault)
                        }
                        
                        Spacer()
                        
                        // Action Buttons
                        HStack {
                            Button(action: { handleProfileActivation(selectedProfile) }) {
                                Label(
                                    viewModel.activeProfile?.id == selectedProfile.id ? "Active" : "Activate",
                                    systemImage: "checkmark.circle.fill"
                                )
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(Colors.primary)
                            .disabled(viewModel.activeProfile?.id == selectedProfile.id)
                            
                            Spacer()
                            
                            if !selectedProfile.isDefault {
                                Button(role: .destructive, action: { handleProfileDeletion(selectedProfile) }) {
                                    Label("Delete", systemImage: "trash.fill")
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                    }
                    .padding(Layout.spacing4)
                    .background(Colors.surface)
                    .cornerRadius(8)
                } else {
                    // Empty State
                    VStack {
                        Text("Select a profile to view details")
                            .font(Typography.bodyLarge)
                            .foregroundColor(Colors.onSurface.opacity(0.6))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Colors.surface)
                    .cornerRadius(8)
                }
            }
            .padding(Layout.spacing4)
            .alert("Error", isPresented: Binding(
                get: { errorState != nil },
                set: { if !$0 { errorState = nil } }
            )) {
                Text(errorState?.localizedDescription ?? "")
            }
        }
        .sheet(isPresented: $isCreatingProfile) {
            ProfileFormView(
                mode: .create,
                onSave: handleProfileCreation
            )
        }
        .sheet(isPresented: $isEditingProfile) {
            if let profile = viewModel.profiles.first(where: { $0.id == selectedProfileId }) {
                ProfileFormView(
                    mode: .edit(profile),
                    onSave: handleProfileUpdate
                )
            }
        }
        .onAppear {
            setupQualityMonitoring()
        }
        .onDisappear {
            qualityMonitorTimer?.invalidate()
        }
    }
    
    // MARK: - Private Methods
    private func setupQualityMonitoring() {
        qualityMonitorTimer = Timer.scheduledTimer(withTimeInterval: AUDIO_QUALITY_UPDATE_INTERVAL, repeats: true) { _ in
            Task {
                await monitorAudioQuality()
            }
        }
    }
    
    private func monitorAudioQuality() async {
        guard let activeProfile = viewModel.activeProfile else { return }
        
        do {
            let metrics = try await viewModel.validateAudioQuality(activeProfile)
            audioQualityMetrics = AudioQualityMetrics(
                thdPlusNoise: metrics.thdPlusNoise,
                signalToNoise: metrics.signalToNoise,
                processingLatency: metrics.latency,
                powerEfficiency: metrics.powerEfficiency
            )
        } catch {
            errorState = error as? TALDError
        }
    }
    
    private func handleProfileSelection(_ profile: Profile) {
        selectedProfileId = profile.id
    }
    
    private func handleProfileCreation(_ name: String, _ settings: AudioSettings) {
        Task {
            do {
                try await viewModel.createProfile(
                    name: name,
                    description: "Custom audio profile",
                    settings: settings
                )
            } catch {
                errorState = error as? TALDError
            }
        }
    }
    
    private func handleProfileUpdate(_ profile: Profile, _ settings: AudioSettings) {
        Task {
            do {
                try await viewModel.updateProfile(
                    profile,
                    settings: settings
                )
            } catch {
                errorState = error as? TALDError
            }
        }
    }
    
    private func handleProfileActivation(_ profile: Profile) {
        Task {
            do {
                try await viewModel.setActiveProfile(profile)
            } catch {
                errorState = error as? TALDError
            }
        }
    }
    
    private func handleProfileDeletion(_ profile: Profile) {
        Task {
            do {
                try await viewModel.deleteProfile(profile)
                selectedProfileId = nil
            } catch {
                errorState = error as? TALDError
            }
        }
    }
    
    private func updateMasterVolume(_ profile: Profile, value: Float) {
        Task {
            var settings = profile.audioSettings
            settings.masterVolume = value
            try? await viewModel.updateProfile(profile, settings: settings)
        }
    }
    
    private func updateEnhancement(_ profile: Profile, enabled: Bool) {
        Task {
            try? await viewModel.updateProfile(
                profile,
                aiEnhancementEnabled: enabled
            )
        }
    }
    
    private func updateSpatialAudio(_ profile: Profile, enabled: Bool) {
        Task {
            try? await viewModel.updateProfile(
                profile,
                spatialAudioEnabled: enabled
            )
        }
    }
    
    private func updatePowerOptimization(_ profile: Profile, enabled: Bool) {
        Task {
            try? await viewModel.updateProfile(
                profile,
                powerOptimizationEnabled: enabled
            )
            
            // Monitor power efficiency if enabled
            if enabled {
                try? await viewModel.monitorPowerEfficiency(profile)
            }
        }
    }
}

// MARK: - Supporting Views
private struct ProfileListItem: View {
    let profile: Profile
    let isActive: Bool
    let onSelect: () -> Void
    
    var body: some View {
        Button(action: onSelect) {
            HStack {
                VStack(alignment: .leading) {
                    Text(profile.name)
                        .font(Typography.labelLarge)
                        .foregroundColor(Colors.onSurface)
                    
                    Text(profile.description)
                        .font(Typography.labelSmall)
                        .foregroundColor(Colors.onSurface.opacity(0.6))
                        .lineLimit(1)
                }
                
                Spacer()
                
                if isActive {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(Colors.primary)
                }
            }
            .padding(Layout.spacing2)
            .background(isActive ? Colors.primary.opacity(0.1) : Colors.surface)
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }
}

private struct MetricsGrid: View {
    let metrics: AudioQualityMetrics
    
    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: Layout.spacing4, verticalSpacing: Layout.spacing2) {
            GridRow {
                MetricItem(
                    label: "THD+N",
                    value: String(format: "%.4f%%", metrics.thdPlusNoise * 100),
                    threshold: metrics.thdPlusNoise <= AudioConstants.THD_N_THRESHOLD
                )
                
                MetricItem(
                    label: "SNR",
                    value: String(format: "%.1f dB", metrics.signalToNoise),
                    threshold: metrics.signalToNoise >= 120.0
                )
            }
            
            GridRow {
                MetricItem(
                    label: "Latency",
                    value: String(format: "%.1f ms", metrics.processingLatency * 1000),
                    threshold: metrics.processingLatency <= AudioConstants.TARGET_LATENCY
                )
                
                MetricItem(
                    label: "Efficiency",
                    value: String(format: "%.1f%%", metrics.powerEfficiency * 100),
                    threshold: metrics.powerEfficiency >= POWER_EFFICIENCY_THRESHOLD
                )
            }
        }
    }
}

private struct MetricItem: View {
    let label: String
    let value: String
    let threshold: Bool
    
    var body: some View {
        VStack(alignment: .leading) {
            Text(label)
                .font(Typography.labelSmall)
                .foregroundColor(Colors.onSurface.opacity(0.6))
            
            Text(value)
                .font(Typography.monospacedDigits)
                .foregroundColor(threshold ? Colors.primary : Colors.error)
        }
    }
}