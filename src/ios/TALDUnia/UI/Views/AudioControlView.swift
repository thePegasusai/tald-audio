// SwiftUI Latest
import SwiftUI
// Combine Latest
import Combine

/// Professional-grade audio control interface with real-time visualization and WCAG 2.1 AA compliance
@available(iOS 14.0, *)
public struct AudioControlView: View {
    // MARK: - Constants
    
    private let kVolumeSliderHeight: CGFloat = 44.0
    private let kControlSpacing: CGFloat = 16.0
    private let kVUMeterHeight: CGFloat = 120.0
    private let kMinimumTouchTarget: CGFloat = 44.0
    private let kUpdateInterval: TimeInterval = 0.01
    private let kHapticFeedbackInterval: TimeInterval = 0.05
    
    // MARK: - View Model
    
    @StateObject private var viewModel: AudioControlViewModel
    
    // MARK: - State
    
    @State private var isVolumeSliderEditing = false
    @State private var displayLink: CADisplayLink?
    @State private var updateTask: Task<Void, Never>?
    @State private var memoryWarning = false
    
    // MARK: - Initialization
    
    public init(viewModel: AudioControlViewModel = AudioControlViewModel()) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }
    
    // MARK: - Body
    
    public var body: some View {
        VStack(spacing: kControlSpacing) {
            makeVolumeSection()
            makeEnhancementSection()
            makeSpatialSection()
        }
        .containerLayout()
        .onAppear {
            setupDisplayLink()
        }
        .onDisappear {
            cleanupDisplayLink()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)) { _ in
            handleMemoryWarning()
        }
    }
    
    // MARK: - Section Builders
    
    @ViewBuilder
    private func makeVolumeSection() -> some View {
        VStack(alignment: .leading, spacing: Layout.spacing2) {
            Text("Volume")
                .font(.headline)
                .foregroundColor(Colors.primary)
                .accessibilityAddTraits(.isHeader)
            
            CustomSliderRepresentable(
                value: Binding(
                    get: { Double(viewModel.currentVolume) },
                    set: { viewModel.updateVolume(Float($0)) }
                ),
                minimumValue: 0.0,
                maximumValue: 1.0
            )
            .frame(height: kVolumeSliderHeight)
            .accessibilityLabel("Volume Control")
            .accessibilityValue("\(Int(viewModel.currentVolume * 100))%")
            
            VUMeter(standard: .ppm, referenceLevel: -18.0)
                .frame(height: kVUMeterHeight)
                .accessibilityLabel("Volume Meter")
                .accessibilityHint("Shows current audio levels")
        }
        .padding(EdgeInsets.control)
        .background(Colors.surface)
        .cornerRadius(8)
    }
    
    @ViewBuilder
    private func makeEnhancementSection() -> some View {
        VStack(alignment: .leading, spacing: Layout.spacing2) {
            Text("AI Enhancement")
                .font(.headline)
                .foregroundColor(Colors.primary)
                .accessibilityAddTraits(.isHeader)
            
            Toggle("Enable Enhancement", isOn: Binding(
                get: { viewModel.isEnhancementEnabled },
                set: { _ in viewModel.toggleEnhancement() }
            ))
            .tint(Colors.primary)
            .accessibilityHint("Toggles AI-powered audio enhancement")
            
            if viewModel.isProcessing {
                ProgressView("Processing...")
                    .progressViewStyle(.linear)
                    .tint(Colors.primary)
                    .accessibilityLabel("Processing audio enhancement")
            }
        }
        .padding(EdgeInsets.control)
        .background(Colors.surface)
        .cornerRadius(8)
    }
    
    @ViewBuilder
    private func makeSpatialSection() -> some View {
        VStack(alignment: .leading, spacing: Layout.spacing2) {
            Text("Spatial Audio")
                .font(.headline)
                .foregroundColor(Colors.primary)
                .accessibilityAddTraits(.isHeader)
            
            Toggle("Enable Spatial Audio", isOn: Binding(
                get: { viewModel.isSpatialEnabled },
                set: { _ in viewModel.toggleSpatialAudio() }
            ))
            .tint(Colors.primary)
            .accessibilityHint("Toggles spatial audio processing")
            
            if viewModel.isSpatialEnabled {
                Button(action: viewModel.resetHeadPosition) {
                    Label("Reset Head Position", systemImage: "arrow.counterclockwise")
                        .foregroundColor(Colors.primary)
                }
                .accessibilityLabel("Reset Head Position")
                .accessibilityHint("Resets spatial audio head tracking position")
            }
        }
        .padding(EdgeInsets.control)
        .background(Colors.surface)
        .cornerRadius(8)
    }
    
    // MARK: - Display Link Management
    
    private func setupDisplayLink() {
        displayLink = CADisplayLink(target: DisplayLinkTarget { [weak viewModel] in
            guard let viewModel = viewModel else { return }
            updateTask = Task {
                // Update VU meter and visualizations
                await viewModel.updateMeters()
            }
        }, selector: #selector(DisplayLinkTarget.update))
        
        displayLink?.preferredFramesPerSecond = Int(1.0 / kUpdateInterval)
        displayLink?.add(to: .main, forMode: .common)
    }
    
    private func cleanupDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
        updateTask?.cancel()
        updateTask = nil
    }
    
    private func handleMemoryWarning() {
        memoryWarning = true
        cleanupDisplayLink()
        
        // Restart display link with reduced refresh rate
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            memoryWarning = false
            setupDisplayLink()
        }
    }
}

// MARK: - Display Link Target

private class DisplayLinkTarget {
    private let action: () -> Void
    
    init(action: @escaping () -> Void) {
        self.action = action
    }
    
    @objc func update() {
        action()
    }
}

// MARK: - Preview

@available(iOS 14.0, *)
struct AudioControlView_Previews: PreviewProvider {
    static var previews: some View {
        AudioControlView()
            .previewLayout(.sizeThatFits)
            .padding()
    }
}