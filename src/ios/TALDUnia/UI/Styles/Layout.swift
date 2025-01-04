import UIKit
import SwiftUI

// MARK: - Global Constants

/// Base unit for the 8px grid system
private let kBaseUnit: CGFloat = 8.0

/// Minimum touch target size (44x44 points) per iOS HIG
private let kMinTouchTarget: CGFloat = 44.0

/// Maximum container width for optimal readability
private let kMaxContainerWidth: CGFloat = 428.0

/// Default animation duration for layout transitions
private let kDefaultAnimationDuration: TimeInterval = 0.3

// MARK: - Layout System

/// Core layout system providing spacing, sizing and layout guidelines
public struct Layout {
    // MARK: - Spacing Scale
    
    /// Zero spacing (0px) for edge-to-edge layouts
    public static let spacing0: CGFloat = 0
    
    /// Extra small spacing (4px) for tight layouts
    public static let spacing1: CGFloat = scaledSpacing(0.5)
    
    /// Small spacing (8px) for default spacing
    public static let spacing2: CGFloat = scaledSpacing(1.0)
    
    /// Medium spacing (16px) for content separation
    public static let spacing3: CGFloat = scaledSpacing(2.0)
    
    /// Large spacing (24px) for section separation
    public static let spacing4: CGFloat = scaledSpacing(3.0)
    
    /// Extra large spacing (32px) for major section separation
    public static let spacing5: CGFloat = scaledSpacing(4.0)
    
    /// Maximum spacing (48px) for significant visual breaks
    public static let spacing6: CGFloat = scaledSpacing(6.0)
    
    // MARK: - Private Helpers
    
    /// Calculates scaled spacing values with dynamic type support
    private static func scaledSpacing(_ multiplier: CGFloat, shouldScaleWithDynamicType: Bool = true) -> CGFloat {
        var spacing = kBaseUnit * multiplier
        
        if shouldScaleWithDynamicType {
            let contentSize = UIApplication.shared.preferredContentSizeCategory
            let sizeMultiplier = UIFontMetrics.default.scaledValue(for: 1.0)
            spacing *= sizeMultiplier
        }
        
        // Round to nearest pixel for crisp rendering
        return round(spacing * UIScreen.main.scale) / UIScreen.main.scale
    }
}

// MARK: - Container Sizes

/// Defines fluid responsive container widths
public struct ContainerSizes {
    /// Small container width (320pt)
    public static let small: CGFloat = 320.0
    
    /// Medium container width (375pt)
    public static let medium: CGFloat = 375.0
    
    /// Large container width (428pt)
    public static let large: CGFloat = kMaxContainerWidth
    
    /// Full width container that respects safe areas
    public static let full: CGFloat = UIScreen.main.bounds.width
    
    /// Adaptive container that adjusts based on size class
    public static var adaptive: CGFloat {
        let window = UIApplication.shared.windows.first
        let sizeClass = window?.traitCollection.horizontalSizeClass
        
        switch sizeClass {
        case .compact:
            return small
        case .regular:
            return large
        default:
            return medium
        }
    }
}

// MARK: - Touch Targets

/// Defines accessibility-focused touch target sizes
public struct TouchTargets {
    /// Minimum touch target size (44x44)
    public static let minimum = CGSize(width: kMinTouchTarget, height: kMinTouchTarget)
    
    /// Standard touch target size (48x48)
    public static let standard = CGSize(width: scaledTouchTarget(1.0), height: scaledTouchTarget(1.0))
    
    /// Large touch target size (56x56)
    public static let large = CGSize(width: scaledTouchTarget(1.2), height: scaledTouchTarget(1.2))
    
    /// Expanded touch target size (64x64)
    public static let expanded = CGSize(width: scaledTouchTarget(1.5), height: scaledTouchTarget(1.5))
    
    /// Calculates scaled touch target sizes
    private static func scaledTouchTarget(_ multiplier: CGFloat) -> CGFloat {
        return max(kMinTouchTarget * multiplier, kMinTouchTarget)
    }
}

// MARK: - Edge Insets

/// Provides context-aware edge insets for different UI scenarios
public struct EdgeInsets {
    /// Screen edge insets that respect safe areas
    public static var screen: UIEdgeInsets {
        return adaptiveInsets(edges: .all, baseInset: Layout.spacing3)
    }
    
    /// Container edge insets for content areas
    public static var container: UIEdgeInsets {
        return adaptiveInsets(edges: .horizontal, baseInset: Layout.spacing2)
    }
    
    /// Control edge insets for interactive elements
    public static var control: UIEdgeInsets {
        return UIEdgeInsets(top: Layout.spacing1,
                           left: Layout.spacing2,
                           bottom: Layout.spacing1,
                           right: Layout.spacing2)
    }
    
    /// Creates adaptive edge insets based on context
    public static func adaptiveInsets(edges: UIRectEdge,
                                    baseInset: CGFloat,
                                    sizeClass: UIUserInterfaceSizeClass? = nil) -> UIEdgeInsets {
        let window = UIApplication.shared.windows.first
        let currentSizeClass = sizeClass ?? window?.traitCollection.horizontalSizeClass
        let safeAreaInsets = window?.safeAreaInsets ?? .zero
        
        var insets = UIEdgeInsets.zero
        let scaledInset = baseInset * (currentSizeClass == .regular ? 1.5 : 1.0)
        
        if edges.contains(.top) {
            insets.top = max(scaledInset, safeAreaInsets.top)
        }
        if edges.contains(.left) {
            insets.left = max(scaledInset, safeAreaInsets.left)
        }
        if edges.contains(.bottom) {
            insets.bottom = max(scaledInset, safeAreaInsets.bottom)
        }
        if edges.contains(.right) {
            insets.right = max(scaledInset, safeAreaInsets.right)
        }
        
        return insets
    }
}

// MARK: - SwiftUI Support

@available(iOS 13.0, *)
extension Layout {
    /// SwiftUI view modifier for applying standard spacing
    public struct StandardSpacing: ViewModifier {
        public func body(content: Content) -> some View {
            content
                .padding(.horizontal, Layout.spacing2)
                .padding(.vertical, Layout.spacing3)
        }
    }
    
    /// SwiftUI view modifier for container layouts
    public struct ContainerLayout: ViewModifier {
        let maxWidth: CGFloat
        
        public func body(content: Content) -> some View {
            content
                .frame(maxWidth: maxWidth)
                .padding(EdgeInsets.container)
        }
    }
}

@available(iOS 13.0, *)
public extension View {
    /// Applies standard spacing to a SwiftUI view
    func standardSpacing() -> some View {
        modifier(Layout.StandardSpacing())
    }
    
    /// Applies container layout to a SwiftUI view
    func containerLayout(maxWidth: CGFloat = ContainerSizes.adaptive) -> some View {
        modifier(Layout.ContainerLayout(maxWidth: maxWidth))
    }
}