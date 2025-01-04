//
// AudioControlView.swift
// TALD UNIA
//
// Professional-grade audio control interface with industry-standard metering
// Version: 1.0.0
//

import SwiftUI // macOS 13.0+
import Combine // macOS 13.0+

// MARK: - Constants

private let VOLUME_RANGE: ClosedRange<Double> = -60.0...12.0
private let CONTROL_SPACING: CGFloat = 16.0
private let BUTTON_SIZE: CGFloat = 44.0
private let CALIBRATION_POINTS: [Double] = [-60.0, -48.0, -36.0, -24.0, -12.0, 0.0, 6.0, 12.0]
private let THDN_THRESHOLD: Double = 0.0005

// MARK: - Audio Control View

@available(macOS 13.0, *)
public struct AudioControlView: View {
    @ObservedObject private var viewModel: AudioControlViewModel
    @State private var isCalibrating: Bool = false
    @State private var showingPerformanceMonitor: Bool = false
    
    // MARK: - Initialization
    
    public init(viewModel: AudioControlViewModel) {
        self.viewModel = viewModel
    }
    
    // MARK: - Body
    
    public var body: some View {
        VStack(spacing: CONTROL_SPACING) {
            // Transport Controls
            transportControlsView
            
            // Volume Control
            volumeControlView
            
            // Performance Monitoring
            if showingPerformanceMonitor {
                monitoringView
            }
            
            // Enhancement Controls
            enhancementControlsView
            
            // Spatial Audio Controls
            spatialAudioControlsView
            
            // Calibration Controls
            if isCalibrating {
                calibrationView
            }
        }
        .padding()
        .background(Colors.background)
        .accessibilityElement(children: .contain)
    }
    
    // MARK: - Transport Controls
    
    private var transportControlsView: some View {
        HStack(spacing: CONTROL_SPACING) {
            Button(action: {
                _ = viewModel.togglePlayback()
            }) {
                Image(systemName: viewModel.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .resizable()
                    .frame(width: BUTTON_SIZE, height: BUTTON_SIZE)
                    .foregroundColor(Colors.primary)
            }
            .accessibilityLabel(viewModel.isPlaying ? "Pause" : "Play")
            
            Spacer()
            
            Button(action: { showingPerformanceMonitor.toggle() }) {
                Image(systemName: "waveform.circle")
                    .resizable()
                    .frame(width: BUTTON_SIZE, height: BUTTON_SIZE)
                    .foregroundColor(Colors.secondary)
            }
            .accessibilityLabel("Performance Monitor")
        }
    }
    
    // MARK: - Volume Control
    
    private var volumeControlView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Volume (dB)")
                .foregroundColor(Colors.onBackground)
            
            HStack {
                Text("\(Int(VOLUME_RANGE.lowerBound))")
                    .foregroundColor(Colors.onBackground.opacity(0.6))
                
                Slider(
                    value: Binding(
                        get: { viewModel.volume },
                        set: { _ = viewModel.updateVolume($0) }
                    ),
                    in: VOLUME_RANGE
                )
                .accentColor(Colors.primary)
                
                Text("+\(Int(VOLUME_RANGE.upperBound))")
                    .foregroundColor(Colors.onBackground.opacity(0.6))
            }
            
            // Calibration markers
            HStack(spacing: 0) {
                ForEach(CALIBRATION_POINTS, id: \.self) { point in
                    Rectangle()
                        .frame(width: 1, height: 8)
                        .foregroundColor(Colors.onBackground.opacity(0.3))
                    
                    Spacer()
                }
            }
        }
    }
    
    // MARK: - Monitoring View
    
    private var monitoringView: some View {
        VStack(alignment: .leading, spacing: 8) {
            // THD+N Monitoring
            HStack {
                Text("THD+N:")
                    .foregroundColor(Colors.onBackground)
                
                Text(String(format: "%.5f%%", viewModel.thdnLevel * 100))
                    .foregroundColor(viewModel.thdnLevel <= THDN_THRESHOLD ? Colors.primary : Colors.error)
            }
            
            // Latency Monitoring
            HStack {
                Text("Latency:")
                    .foregroundColor(Colors.onBackground)
                
                Text(String(format: "%.1f ms", viewModel.processingLatency * 1000))
                    .foregroundColor(viewModel.processingLatency <= 0.010 ? Colors.primary : Colors.error)
            }
        }
        .padding()
        .background(Colors.surface)
        .cornerRadius(8)
    }
    
    // MARK: - Enhancement Controls
    
    private var enhancementControlsView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: Binding(
                get: { viewModel.isEnhancementEnabled },
                set: { _ = viewModel.toggleEnhancement() }
            )) {
                Text("AI Enhancement")
                    .foregroundColor(Colors.onBackground)
            }
            .toggleStyle(SwitchToggleStyle(tint: Colors.primary))
        }
    }
    
    // MARK: - Spatial Audio Controls
    
    private var spatialAudioControlsView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: Binding(
                get: { viewModel.isSpatialEnabled },
                set: { _ = viewModel.toggleSpatialAudio() }
            )) {
                Text("Spatial Audio")
                    .foregroundColor(Colors.onBackground)
            }
            .toggleStyle(SwitchToggleStyle(tint: Colors.primary))
        }
    }
    
    // MARK: - Calibration View
    
    private var calibrationView: some View {
        VStack(alignment: .leading, spacing: CONTROL_SPACING) {
            Text("Audio Calibration")
                .font(.headline)
                .foregroundColor(Colors.onBackground)
            
            Button(action: {
                _ = viewModel.calibrateAudio()
            }) {
                Text("Start Calibration")
                    .foregroundColor(Colors.onPrimary)
                    .padding()
                    .background(Colors.primary)
                    .cornerRadius(8)
            }
            .accessibilityLabel("Start Audio Calibration")
        }
        .padding()
        .background(Colors.surface)
        .cornerRadius(8)
    }
}

// MARK: - Preview Provider

#if DEBUG
struct AudioControlView_Previews: PreviewProvider {
    static var previews: some View {
        AudioControlView(viewModel: try! AudioControlViewModel())
            .frame(width: 400, height: 600)
            .preferredColorScheme(.light)
        
        AudioControlView(viewModel: try! AudioControlViewModel())
            .frame(width: 400, height: 600)
            .preferredColorScheme(.dark)
    }
}
#endif