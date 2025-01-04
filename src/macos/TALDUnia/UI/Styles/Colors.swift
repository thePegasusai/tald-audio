//
// Colors.swift
// TALD UNIA
//
// Implements a comprehensive color system using P3 color space with dynamic adaptation
// and WCAG 2.1 AA compliance for the TALD UNIA audio system
// Version: 1.0.0
//

import SwiftUI // macOS 13.0+
import Core.Constants

// MARK: - Global Constants
private let COLOR_OPACITY_HIGH: Double = 0.87
private let COLOR_OPACITY_MEDIUM: Double = 0.60
private let COLOR_OPACITY_LOW: Double = 0.38
private let MIN_CONTRAST_RATIO: Double = 4.5
private let P3_COLOR_SPACE: String = "displayP3"

// MARK: - Color System
public struct Colors {
    // MARK: - Primary Colors
    public static let primary = adaptiveColor(
        light: Color(P3_COLOR_SPACE, red: 0.141, green: 0.349, blue: 0.827, opacity: 1.0),
        dark: Color(P3_COLOR_SPACE, red: 0.267, green: 0.478, blue: 0.949, opacity: 1.0)
    )
    
    public static let secondary = adaptiveColor(
        light: Color(P3_COLOR_SPACE, red: 0.173, green: 0.173, blue: 0.180, opacity: 1.0),
        dark: Color(P3_COLOR_SPACE, red: 0.827, green: 0.827, blue: 0.847, opacity: 1.0)
    )
    
    public static let accent = adaptiveColor(
        light: Color(P3_COLOR_SPACE, red: 0.937, green: 0.365, blue: 0.157, opacity: 1.0),
        dark: Color(P3_COLOR_SPACE, red: 1.000, green: 0.459, blue: 0.259, opacity: 1.0)
    )
    
    // MARK: - Background Colors
    public static let background = adaptiveColor(
        light: Color(P3_COLOR_SPACE, red: 0.969, green: 0.969, blue: 0.969, opacity: 1.0),
        dark: Color(P3_COLOR_SPACE, red: 0.118, green: 0.118, blue: 0.118, opacity: 1.0)
    )
    
    public static let surface = adaptiveColor(
        light: Color(P3_COLOR_SPACE, red: 1.000, green: 1.000, blue: 1.000, opacity: 1.0),
        dark: Color(P3_COLOR_SPACE, red: 0.173, green: 0.173, blue: 0.173, opacity: 1.0)
    )
    
    // MARK: - Semantic Colors
    public static let error = adaptiveColor(
        light: Color(P3_COLOR_SPACE, red: 0.898, green: 0.184, blue: 0.153, opacity: 1.0),
        dark: Color(P3_COLOR_SPACE, red: 0.984, green: 0.286, blue: 0.255, opacity: 1.0)
    )
    
    // MARK: - On Colors (Contrast Colors)
    public static let onPrimary = adaptiveColor(
        light: Color(P3_COLOR_SPACE, red: 1.000, green: 1.000, blue: 1.000, opacity: 1.0),
        dark: Color(P3_COLOR_SPACE, red: 0.000, green: 0.000, blue: 0.000, opacity: 1.0)
    )
    
    public static let onSecondary = adaptiveColor(
        light: Color(P3_COLOR_SPACE, red: 1.000, green: 1.000, blue: 1.000, opacity: 1.0),
        dark: Color(P3_COLOR_SPACE, red: 0.000, green: 0.000, blue: 0.000, opacity: 1.0)
    )
    
    public static let onBackground = adaptiveColor(
        light: Color(P3_COLOR_SPACE, red: 0.000, green: 0.000, blue: 0.000, opacity: 1.0),
        dark: Color(P3_COLOR_SPACE, red: 1.000, green: 1.000, blue: 1.000, opacity: 1.0)
    )
    
    public static let onSurface = adaptiveColor(
        light: Color(P3_COLOR_SPACE, red: 0.000, green: 0.000, blue: 0.000, opacity: 1.0),
        dark: Color(P3_COLOR_SPACE, red: 1.000, green: 1.000, blue: 1.000, opacity: 1.0)
    )
    
    public static let onError = adaptiveColor(
        light: Color(P3_COLOR_SPACE, red: 1.000, green: 1.000, blue: 1.000, opacity: 1.0),
        dark: Color(P3_COLOR_SPACE, red: 0.000, green: 0.000, blue: 0.000, opacity: 1.0)
    )
}

// MARK: - Color Modifier
public struct ColorModifier {
    public let opacity: Double
    public let blend: Color?
    public let adjustContrast: Double
    public let ensureAccessibility: Bool
    
    public init(
        opacity: Double = 1.0,
        blend: Color? = nil,
        adjustContrast: Double = 0.0,
        ensureAccessibility: Bool = true
    ) {
        self.opacity = opacity
        self.blend = blend
        self.adjustContrast = adjustContrast
        self.ensureAccessibility = ensureAccessibility
    }
}

// MARK: - Helper Functions
private func adaptiveColor(light: Color, dark: Color, minimumContrast: Double = MIN_CONTRAST_RATIO) -> Color {
    let colorScheme = SystemDefaults.DEFAULT_COLOR_SCHEME
    
    // Ensure colors meet contrast requirements
    if minimumContrast > 0 {
        let backgroundContrast = calculateContrastRatio(
            colorScheme == .light ? light : dark,
            colorScheme == .light ? Colors.background : Colors.background
        )
        
        if backgroundContrast < minimumContrast {
            // Adjust color to meet contrast requirements
            return adjustColorForContrast(
                colorScheme == .light ? light : dark,
                against: Colors.background,
                targetContrast: minimumContrast
            )
        }
    }
    
    return colorScheme == .light ? light : dark
}

private func calculateContrastRatio(_ color1: Color, _ color2: Color) -> Double {
    let luminance1 = calculateRelativeLuminance(color1)
    let luminance2 = calculateRelativeLuminance(color2)
    
    let lighter = max(luminance1, luminance2)
    let darker = min(luminance1, luminance2)
    
    return (lighter + 0.05) / (darker + 0.05)
}

private func calculateRelativeLuminance(_ color: Color) -> Double {
    var red: CGFloat = 0
    var green: CGFloat = 0
    var blue: CGFloat = 0
    
    let uiColor = NSColor(color)
    uiColor.getRed(&red, green: &green, blue: &blue, alpha: nil)
    
    let r = adjustColorComponent(red)
    let g = adjustColorComponent(green)
    let b = adjustColorComponent(blue)
    
    return 0.2126 * r + 0.7152 * g + 0.0722 * b
}

private func adjustColorComponent(_ component: CGFloat) -> Double {
    let c = Double(component)
    return c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
}

private func adjustColorForContrast(_ color: Color, against background: Color, targetContrast: Double) -> Color {
    var adjustedColor = color
    var currentContrast = calculateContrastRatio(adjustedColor, background)
    let step: CGFloat = 0.01
    
    while currentContrast < targetContrast {
        // Adjust color components to increase contrast
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        
        NSColor(adjustedColor).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        
        // Adjust towards white or black depending on background
        let backgroundLuminance = calculateRelativeLuminance(background)
        if backgroundLuminance > 0.5 {
            // Darken the color
            red = max(0, red - step)
            green = max(0, green - step)
            blue = max(0, blue - step)
        } else {
            // Lighten the color
            red = min(1, red + step)
            green = min(1, green + step)
            blue = min(1, blue + step)
        }
        
        adjustedColor = Color(P3_COLOR_SPACE, red: Double(red), green: Double(green), blue: Double(blue), opacity: Double(alpha))
        currentContrast = calculateContrastRatio(adjustedColor, background)
    }
    
    return adjustedColor
}