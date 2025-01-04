//
// Layout.swift
// TALD UNIA
//
// Implements a comprehensive layout system with an 8px baseline grid,
// responsive spacing, and accessibility-compliant sizing
// Version: 1.0.0
//

import SwiftUI // macOS 13.0+

// MARK: - Global Constants
private let GRID_UNIT: CGFloat = 8.0
private let MIN_TOUCH_TARGET: CGFloat = 44.0
private let CONTENT_MAX_WIDTH: CGFloat = 1440.0
private let MIN_SCALE_FACTOR: CGFloat = 0.75
private let MAX_SCALE_FACTOR: CGFloat = 1.5

// MARK: - Layout System
public struct Layout {
    // MARK: - Spacing Scale
    public static let spacing0: CGFloat = gridSpacing(0)     // 0px
    public static let spacing1: CGFloat = gridSpacing(0.5)   // 4px
    public static let spacing2: CGFloat = gridSpacing(1)     // 8px
    public static let spacing3: CGFloat = gridSpacing(2)     // 16px
    public static let spacing4: CGFloat = gridSpacing(3)     // 24px
    public static let spacing5: CGFloat = gridSpacing(4)     // 32px
    public static let spacing6: CGFloat = gridSpacing(6)     // 48px
    
    // MARK: - Layout Constraints
    public static let minTouchTarget = CGSize(
        width: MIN_TOUCH_TARGET,
        height: MIN_TOUCH_TARGET
    )
    
    public static let contentMaxWidth = CONTENT_MAX_WIDTH
    
    // MARK: - Responsive Spacing
    public static func adaptiveSpacing(
        _ baseSpacing: CGFloat,
        minScale: CGFloat = MIN_SCALE_FACTOR,
        maxScale: CGFloat = MAX_SCALE_FACTOR
    ) -> CGFloat {
        let windowSize = NSScreen.main?.visibleFrame.size ?? CGSize(width: 1024, height: 768)
        let baseWidth: CGFloat = 1024.0
        
        // Calculate scale factor based on window width
        let scaleFactor = max(
            minScale,
            min(maxScale, windowSize.width / baseWidth)
        )
        
        // Ensure result maintains grid alignment
        return gridSpacing(baseSpacing * scaleFactor / GRID_UNIT)
    }
    
    // MARK: - Edge Insets
    public static func padding(
        _ edges: Edge.Set = .all,
        _ spacing: CGFloat
    ) -> EdgeInsets {
        EdgeInsets(
            top: edges.contains(.top) ? spacing : 0,
            leading: edges.contains(.leading) ? spacing : 0,
            bottom: edges.contains(.bottom) ? spacing : 0,
            trailing: edges.contains(.trailing) ? spacing : 0
        )
    }
}

// MARK: - Layout Modifier
public struct LayoutModifier: ViewModifier {
    let padding: EdgeInsets
    let margin: EdgeInsets
    let maxWidth: CGFloat?
    let minTouchTarget: CGSize?
    let adaptiveScale: CGFloat
    
    public init(
        padding: EdgeInsets = EdgeInsets(),
        margin: EdgeInsets = EdgeInsets(),
        maxWidth: CGFloat? = nil,
        minTouchTarget: CGSize? = nil,
        adaptiveScale: CGFloat = 1.0
    ) {
        self.padding = padding
        self.margin = margin
        self.maxWidth = maxWidth
        self.minTouchTarget = minTouchTarget
        self.adaptiveScale = adaptiveScale
    }
    
    public func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(
                minWidth: minTouchTarget?.width,
                minHeight: minTouchTarget?.height,
                maxWidth: maxWidth
            )
            .padding(margin)
            .scaleEffect(adaptiveScale)
    }
}

// MARK: - Helper Functions
private func gridSpacing(_ multiplier: CGFloat) -> CGFloat {
    guard multiplier >= 0 else { return 0 }
    
    // Round to nearest 0.5 to maintain grid alignment
    let roundedMultiplier = round(multiplier * 2) / 2
    return GRID_UNIT * roundedMultiplier
}

// MARK: - View Extensions
public extension View {
    func layoutModifier(
        padding: EdgeInsets = EdgeInsets(),
        margin: EdgeInsets = EdgeInsets(),
        maxWidth: CGFloat? = nil,
        minTouchTarget: CGSize? = nil,
        adaptiveScale: CGFloat = 1.0
    ) -> some View {
        modifier(LayoutModifier(
            padding: padding,
            margin: margin,
            maxWidth: maxWidth,
            minTouchTarget: minTouchTarget,
            adaptiveScale: adaptiveScale
        ))
    }
    
    func gridPadding(
        _ edges: Edge.Set = .all,
        _ spacing: CGFloat
    ) -> some View {
        padding(Layout.padding(edges, Layout.adaptiveSpacing(spacing)))
    }
    
    func minTouchTarget() -> some View {
        layoutModifier(minTouchTarget: Layout.minTouchTarget)
    }
    
    func maxContentWidth() -> some View {
        layoutModifier(maxWidth: Layout.contentMaxWidth)
    }
}

// MARK: - Preview Provider
struct Layout_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: Layout.spacing3) {
            Text("Layout System Preview")
                .gridPadding(.all, Layout.spacing4)
                .background(Colors.surface)
                .minTouchTarget()
            
            HStack(spacing: Layout.spacing2) {
                ForEach(0..<3) { _ in
                    Rectangle()
                        .fill(Colors.primary)
                        .frame(width: Layout.spacing4, height: Layout.spacing4)
                }
            }
            .maxContentWidth()
        }
        .background(Colors.background)
    }
}