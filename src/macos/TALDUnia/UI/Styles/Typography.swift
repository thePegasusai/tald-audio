//
// Typography.swift
// TALD UNIA
//
// Implements a comprehensive typography system using SF Pro Display font family
// with dynamic type support and WCAG 2.1 AA compliance
// Version: 1.0.0
//

import SwiftUI // macOS 13.0+

// MARK: - Global Constants
private let BASE_FONT_SIZE: CGFloat = 16.0
private let LINE_HEIGHT_MULTIPLIER: CGFloat = 1.5
private let LETTER_SPACING_MULTIPLIER: CGFloat = 0.02
private let MAX_SCALE_FACTOR: CGFloat = 2.0

// MARK: - Text Style Configuration
public struct TextStyle {
    let weight: Font.Weight
    let size: CGFloat
    let lineHeight: CGFloat
    let letterSpacing: CGFloat
    let isAccessibilityOptimized: Bool
    
    init(
        weight: Font.Weight,
        size: CGFloat,
        lineHeight: CGFloat? = nil,
        letterSpacing: CGFloat? = nil,
        isAccessibilityOptimized: Bool = true
    ) {
        self.weight = weight
        self.size = size
        self.lineHeight = lineHeight ?? (size * LINE_HEIGHT_MULTIPLIER)
        self.letterSpacing = letterSpacing ?? (size * LETTER_SPACING_MULTIPLIER)
        self.isAccessibilityOptimized = isAccessibilityOptimized
    }
}

// MARK: - Typography System
public struct Typography {
    // MARK: - Display Styles
    public static let displayLarge = adaptiveFont(
        style: TextStyle(
            weight: .bold,
            size: 57.0,
            lineHeight: 64.0,
            letterSpacing: -0.25
        )
    )
    
    public static let displayMedium = adaptiveFont(
        style: TextStyle(
            weight: .semibold,
            size: 45.0,
            lineHeight: 52.0,
            letterSpacing: 0
        )
    )
    
    public static let displaySmall = adaptiveFont(
        style: TextStyle(
            weight: .semibold,
            size: 36.0,
            lineHeight: 44.0,
            letterSpacing: 0
        )
    )
    
    // MARK: - Headline Styles
    public static let headlineLarge = adaptiveFont(
        style: TextStyle(
            weight: .semibold,
            size: 32.0,
            lineHeight: 40.0,
            letterSpacing: 0
        )
    )
    
    public static let headlineMedium = adaptiveFont(
        style: TextStyle(
            weight: .semibold,
            size: 28.0,
            lineHeight: 36.0,
            letterSpacing: 0
        )
    )
    
    public static let headlineSmall = adaptiveFont(
        style: TextStyle(
            weight: .semibold,
            size: 24.0,
            lineHeight: 32.0,
            letterSpacing: 0
        )
    )
    
    // MARK: - Body Styles
    public static let bodyLarge = adaptiveFont(
        style: TextStyle(
            weight: .regular,
            size: 16.0,
            lineHeight: 24.0,
            letterSpacing: 0.5
        )
    )
    
    public static let bodyMedium = adaptiveFont(
        style: TextStyle(
            weight: .regular,
            size: 14.0,
            lineHeight: 20.0,
            letterSpacing: 0.25
        )
    )
    
    public static let bodySmall = adaptiveFont(
        style: TextStyle(
            weight: .regular,
            size: 12.0,
            lineHeight: 16.0,
            letterSpacing: 0.4
        )
    )
    
    // MARK: - Label Styles
    public static let labelLarge = adaptiveFont(
        style: TextStyle(
            weight: .medium,
            size: 14.0,
            lineHeight: 20.0,
            letterSpacing: 0.1
        )
    )
    
    public static let labelMedium = adaptiveFont(
        style: TextStyle(
            weight: .medium,
            size: 12.0,
            lineHeight: 16.0,
            letterSpacing: 0.5
        )
    )
    
    public static let labelSmall = adaptiveFont(
        style: TextStyle(
            weight: .medium,
            size: 11.0,
            lineHeight: 16.0,
            letterSpacing: 0.5
        )
    )
}

// MARK: - Helper Functions
private func scaledSize(baseSize: CGFloat, scale: CGFloat = 1.0, isAccessibilitySize: Bool = false) -> CGFloat {
    var scaledSize = baseSize * scale
    
    if isAccessibilitySize {
        scaledSize *= min(MAX_SCALE_FACTOR, UIFontMetrics.default.scaledValue(for: 1.0))
    }
    
    return max(baseSize * 0.75, min(scaledSize, baseSize * MAX_SCALE_FACTOR))
}

private func adaptiveFont(style: TextStyle) -> Font {
    let scaledTextSize = scaledSize(
        baseSize: style.size,
        isAccessibilitySize: style.isAccessibilityOptimized
    )
    
    let font = Font.custom(
        "SFProDisplay-\(style.weight.rawValue.capitalized)",
        size: scaledTextSize,
        relativeTo: .body
    )
    .weight(style.weight)
    .leading(style.lineHeight / style.size)
    .tracking(style.letterSpacing)
    
    return font
}

// MARK: - Font Weight Extension
private extension Font.Weight {
    var rawValue: String {
        switch self {
        case .regular: return "regular"
        case .medium: return "medium"
        case .semibold: return "semibold"
        case .bold: return "bold"
        default: return "regular"
        }
    }
}

// MARK: - View Extension for Typography
public extension View {
    func typographyStyle(_ style: Font) -> some View {
        self.font(style)
    }
}