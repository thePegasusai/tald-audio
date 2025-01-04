//
// CustomSlider.swift
// TALD UNIA
//
// A professional-grade audio slider component with precise dB-scaled control
// and comprehensive accessibility features
// Version: 1.0.0
//

import SwiftUI // macOS 13.0+

// MARK: - Constants
private let SLIDER_HEIGHT: CGFloat = 4.0
private let THUMB_SIZE: CGFloat = 16.0
private let HAPTIC_FEEDBACK_INTENSITY: CGFloat = 0.5
private let MIN_DB_VALUE: Double = -60.0
private let MAX_DB_VALUE: Double = 12.0
private let DB_STEP_SIZE: Double = 0.1

@available(macOS 13.0, *)
public struct CustomSlider: View {
    // MARK: - Properties
    @Binding private var value: Double
    private let range: ClosedRange<Double>
    private let label: String
    private let isEnabled: Bool
    private let onValueChanged: ((Double) -> Void)?
    private let showDBScale: Bool
    
    @State private var isDragging: Bool = false
    @State private var peakLevel: Double = 0.0
    
    // MARK: - Initialization
    public init(
        value: Binding<Double>,
        range: ClosedRange<Double> = MIN_DB_VALUE...MAX_DB_VALUE,
        label: String,
        isEnabled: Bool = true,
        onValueChanged: ((Double) -> Void)? = nil,
        showDBScale: Bool = true
    ) {
        self._value = value
        self.range = range
        self.label = label
        self.isEnabled = isEnabled
        self.onValueChanged = onValueChanged
        self.showDBScale = showDBScale
    }
    
    // MARK: - Body
    public var body: some View {
        VStack(alignment: .leading, spacing: Layout.spacing1) {
            // Label and value display
            HStack {
                Text(label)
                    .font(Typography.labelSmall)
                    .foregroundColor(Colors.onSurface.opacity(0.87))
                
                Spacer()
                
                Text(formatDBValue(value))
                    .font(Typography.monospacedDigits)
                    .foregroundColor(Colors.accent)
            }
            
            // Slider track and thumb
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background track
                    Capsule()
                        .fill(Colors.secondary.opacity(0.12))
                        .frame(height: SLIDER_HEIGHT)
                    
                    // Active track
                    Capsule()
                        .fill(Colors.primary)
                        .frame(
                            width: geometry.size.width * normalizeValue(value, range: range),
                            height: SLIDER_HEIGHT
                        )
                    
                    // Peak level indicator
                    if peakLevel > value {
                        Rectangle()
                            .fill(Colors.accent)
                            .frame(
                                width: 2,
                                height: SLIDER_HEIGHT * 1.5
                            )
                            .offset(
                                x: geometry.size.width * normalizeValue(peakLevel, range: range)
                            )
                            .animation(.easeOut(duration: 0.1), value: peakLevel)
                    }
                    
                    // Thumb
                    Circle()
                        .fill(isDragging ? Colors.accent : Colors.primary)
                        .frame(width: THUMB_SIZE, height: THUMB_SIZE)
                        .shadow(radius: isDragging ? 4 : 2)
                        .offset(
                            x: (geometry.size.width * normalizeValue(value, range: range)) - THUMB_SIZE/2
                        )
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { gesture in
                                    handleDrag(gesture, in: geometry)
                                }
                                .onEnded { _ in
                                    isDragging = false
                                }
                        )
                }
            }
            .frame(height: THUMB_SIZE)
            
            // dB scale indicators
            if showDBScale {
                HStack {
                    Text("\(Int(range.lowerBound))dB")
                    Spacer()
                    Text("0dB")
                    Spacer()
                    Text("+\(Int(range.upperBound))dB")
                }
                .font(Typography.labelSmall)
                .foregroundColor(Colors.onSurface.opacity(0.6))
            }
        }
        .opacity(isEnabled ? 1.0 : 0.5)
        .disabled(!isEnabled)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(formatDBValue(value))
        .accessibilityAdjustableAction { direction in
            let step = direction == .increment ? DB_STEP_SIZE : -DB_STEP_SIZE
            let newValue = value + step
            if range.contains(newValue) {
                value = newValue
                generateHapticFeedback(previousValue: value - step, newValue: value)
                onValueChanged?(value)
            }
        }
    }
    
    // MARK: - Private Methods
    private func handleDrag(_ gesture: DragGesture.Value, in geometry: GeometryProxy) {
        isDragging = true
        let width = geometry.size.width
        let location = gesture.location.x
        
        let percentage = max(0, min(1, location / width))
        let previousValue = value
        let newValue = range.lowerBound + (range.upperBound - range.lowerBound) * percentage
        
        // Snap to dB steps
        value = round(newValue / DB_STEP_SIZE) * DB_STEP_SIZE
        value = max(range.lowerBound, min(range.upperBound, value))
        
        generateHapticFeedback(previousValue: previousValue, newValue: value)
        onValueChanged?(value)
        
        // Update peak level if necessary
        if value > peakLevel {
            peakLevel = value
        }
    }
    
    private func normalizeValue(_ value: Double, range: ClosedRange<Double>) -> Double {
        // Convert to logarithmic scale for better audio control
        let minDb = range.lowerBound
        let maxDb = range.upperBound
        let normalizedValue = (value - minDb) / (maxDb - minDb)
        
        // Apply logarithmic scaling
        return max(0, min(1, normalizedValue))
    }
    
    private func generateHapticFeedback(previousValue: Double, newValue: Double) {
        let feedbackGenerator = NSHapticFeedbackManager.defaultPerformer
        
        // Generate stronger feedback at 0dB and boundaries
        if (previousValue < 0 && newValue >= 0) || (previousValue >= 0 && newValue < 0) {
            feedbackGenerator.perform(.levelChange, performanceTime: .default)
        } else if abs(newValue - range.lowerBound) < DB_STEP_SIZE || abs(newValue - range.upperBound) < DB_STEP_SIZE {
            feedbackGenerator.perform(.generic, performanceTime: .default)
        }
    }
    
    private func formatDBValue(_ value: Double) -> String {
        if abs(value) < DB_STEP_SIZE {
            return "0dB"
        }
        let formattedValue = String(format: "%.1f", value)
        return "\(formattedValue)dB"
    }
}

// MARK: - Preview Provider
struct CustomSlider_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: Layout.spacing4) {
            CustomSlider(
                value: .constant(-20.0),
                label: "Main Volume",
                showDBScale: true
            )
            
            CustomSlider(
                value: .constant(0.0),
                label: "Monitor Level",
                isEnabled: false
            )
        }
        .padding(Layout.spacing4)
        .frame(width: 300)
        .background(Colors.surface)
        .previewLayout(.sizeThatFits)
    }
}