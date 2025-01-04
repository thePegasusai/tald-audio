import UIKit
import SwiftUI

// MARK: - CustomSliderDelegate Protocol

@objc public protocol CustomSliderDelegate: AnyObject {
    func slider(_ slider: CustomSlider, didChangeValue value: CGFloat)
    @objc optional func sliderDidBeginTracking(_ slider: CustomSlider)
    @objc optional func sliderDidEndTracking(_ slider: CustomSlider)
}

// MARK: - CustomSlider Class

@IBDesignable public class CustomSlider: UIControl {
    
    // MARK: - Constants
    
    private let kDefaultThumbSize: CGFloat = TouchTargets.minimum.width
    private let kMinTrackHeight: CGFloat = 4.0
    private let kMaxTrackHeight: CGFloat = 8.0
    private let kDefaultValue: CGFloat = 0.0
    private let kMaxValue: CGFloat = 1.0
    private let kHapticThreshold: CGFloat = 0.05
    private let kValuePrecision: CGFloat = 0.001
    private let kAnimationDuration: TimeInterval = 0.2
    
    // MARK: - Public Properties
    
    @IBInspectable public var value: CGFloat = 0.0 {
        didSet {
            if value != oldValue {
                updateValue(value, animated: false, generateHaptic: false)
            }
        }
    }
    
    @IBInspectable public var minimumValue: CGFloat = 0.0
    @IBInspectable public var maximumValue: CGFloat = 1.0
    @IBInspectable public var isContinuous: Bool = true
    @IBInspectable public var isHapticEnabled: Bool = true
    
    public weak var delegate: CustomSliderDelegate?
    
    // MARK: - Private Properties
    
    private let trackLayer = CAGradientLayer()
    private let thumbView = UIView()
    private var previousValue: CGFloat = 0.0
    private var feedbackGenerator: UIImpactFeedbackGenerator?
    private var isTracking: Bool = false
    
    // MARK: - Initialization
    
    override public init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }
    
    required public init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
    }
    
    // MARK: - UI Setup
    
    private func setupUI() {
        // Configure track layer
        trackLayer.colors = [ControlColors.sliderTrack.cgColor, ControlColors.sliderTrack.cgColor]
        trackLayer.startPoint = CGPoint(x: 0, y: 0.5)
        trackLayer.endPoint = CGPoint(x: 1, y: 0.5)
        trackLayer.cornerRadius = kMinTrackHeight / 2
        layer.addSublayer(trackLayer)
        
        // Configure thumb view
        thumbView.backgroundColor = ControlColors.sliderThumb
        thumbView.layer.cornerRadius = kDefaultThumbSize / 2
        thumbView.layer.shadowColor = UIColor.black.cgColor
        thumbView.layer.shadowOffset = CGSize(width: 0, height: 2)
        thumbView.layer.shadowRadius = 4
        thumbView.layer.shadowOpacity = 0.15
        addSubview(thumbView)
        
        // Setup gesture recognizer
        let panGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        thumbView.addGestureRecognizer(panGesture)
        thumbView.isUserInteractionEnabled = true
        
        // Setup haptic feedback
        feedbackGenerator = UIImpactFeedbackGenerator(style: .light)
        feedbackGenerator?.prepare()
        
        // Configure accessibility
        isAccessibilityElement = true
        accessibilityTraits = .adjustable
        accessibilityLabel = "Audio Control"
        
        // Set initial value
        value = kDefaultValue
    }
    
    // MARK: - Layout
    
    override public func layoutSubviews() {
        super.layoutSubviews()
        
        let trackHeight = bounds.height >= kMaxTrackHeight * 2 ? kMaxTrackHeight : kMinTrackHeight
        let trackRect = CGRect(x: 0,
                             y: (bounds.height - trackHeight) / 2,
                             width: bounds.width,
                             height: trackHeight)
        trackLayer.frame = trackRect
        
        let thumbSize = CGSize(width: kDefaultThumbSize, height: kDefaultThumbSize)
        let thumbX = (bounds.width - thumbSize.width) * (value - minimumValue) / (maximumValue - minimumValue)
        thumbView.frame = CGRect(origin: CGPoint(x: thumbX,
                                               y: (bounds.height - thumbSize.height) / 2),
                               size: thumbSize)
    }
    
    // MARK: - Value Updates
    
    @objc private func updateValue(_ newValue: CGFloat, animated: Bool = true, generateHaptic: Bool = true) {
        let clampedValue = min(maximumValue, max(minimumValue, newValue))
        let roundedValue = round(clampedValue / kValuePrecision) * kValuePrecision
        
        if roundedValue != value {
            value = roundedValue
            
            if generateHaptic && isHapticEnabled && abs(roundedValue - previousValue) >= kHapticThreshold {
                feedbackGenerator?.impactOccurred()
                previousValue = roundedValue
            }
            
            let thumbX = (bounds.width - thumbView.bounds.width) * (value - minimumValue) / (maximumValue - minimumValue)
            
            if animated {
                UIView.animate(withDuration: kAnimationDuration,
                             delay: 0,
                             options: [.beginFromCurrentState, .allowUserInteraction],
                             animations: {
                    self.thumbView.frame.origin.x = thumbX
                })
            } else {
                thumbView.frame.origin.x = thumbX
            }
            
            if isContinuous {
                delegate?.slider(self, didChangeValue: value)
            }
            
            accessibilityValue = String(format: "%.1f", value * 100)
            UIAccessibility.post(notification: .layoutChanged, argument: self)
        }
    }
    
    // MARK: - Gesture Handling
    
    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        switch gesture.state {
        case .began:
            isTracking = true
            delegate?.sliderDidBeginTracking?(self)
            feedbackGenerator?.prepare()
            
        case .changed:
            let translation = gesture.translation(in: self)
            let delta = translation.x / bounds.width * (maximumValue - minimumValue)
            let newValue = previousValue + delta
            updateValue(newValue, animated: false, generateHaptic: true)
            
        case .ended, .cancelled:
            isTracking = false
            previousValue = value
            delegate?.sliderDidEndTracking?(self)
            
        default:
            break
        }
    }
    
    // MARK: - Accessibility
    
    override public func accessibilityIncrement() {
        let increment = (maximumValue - minimumValue) * kValuePrecision
        updateValue(value + increment)
    }
    
    override public func accessibilityDecrement() {
        let decrement = (maximumValue - minimumValue) * kValuePrecision
        updateValue(value - decrement)
    }
}

// MARK: - SwiftUI Support

@available(iOS 13.0, *)
struct CustomSliderRepresentable: UIViewRepresentable {
    @Binding var value: Double
    var minimumValue: Double = 0.0
    var maximumValue: Double = 1.0
    var onValueChanged: ((Double) -> Void)?
    
    func makeUIView(context: Context) -> CustomSlider {
        let slider = CustomSlider()
        slider.minimumValue = CGFloat(minimumValue)
        slider.maximumValue = CGFloat(maximumValue)
        slider.delegate = context.coordinator
        return slider
    }
    
    func updateUIView(_ uiView: CustomSlider, context: Context) {
        uiView.value = CGFloat(value)
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, CustomSliderDelegate {
        var parent: CustomSliderRepresentable
        
        init(_ parent: CustomSliderRepresentable) {
            self.parent = parent
        }
        
        func slider(_ slider: CustomSlider, didChangeValue value: CGFloat) {
            parent.value = Double(value)
            parent.onValueChanged?(Double(value))
        }
    }
}