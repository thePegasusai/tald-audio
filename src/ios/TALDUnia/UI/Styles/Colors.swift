import UIKit
import SwiftUI

// MARK: - Global Constants

private let kMinContrastRatio: CGFloat = 4.5
private let kDefaultColorSpace = "displayP3"
private let kDefaultOpacity: CGFloat = 0.87
private let kSurfaceElevationLevels: [Int] = [0, 1, 2, 3, 4, 8, 12, 16, 24]

// MARK: - Color System Functions

@available(iOS 13.0, *)
func adaptiveColor(light: UIColor, dark: UIColor, opacity: CGFloat = kDefaultOpacity) -> UIColor {
    let lightColor = light.usingColorSpace(named: kDefaultColorSpace) ?? light
    let darkColor = dark.usingColorSpace(named: kDefaultColorSpace) ?? dark
    
    return UIColor { traitCollection in
        let baseColor = traitCollection.userInterfaceStyle == .dark ? darkColor : lightColor
        return baseColor.withAlphaComponent(opacity)
    }
}

func contrastingColor(backgroundColor: UIColor, targetContrast: CGFloat = kMinContrastRatio) -> UIColor {
    let p3Background = backgroundColor.usingColorSpace(named: kDefaultColorSpace) ?? backgroundColor
    var components = p3Background.cgColor.components ?? [0, 0, 0, 1]
    
    // Calculate luminance and adjust for contrast
    let luminance = (0.299 * components[0] + 0.587 * components[1] + 0.114 * components[2])
    let targetColor = luminance > 0.5 ? UIColor.black : UIColor.white
    
    return targetColor.withAlphaComponent(kDefaultOpacity)
}

func elevatedSurfaceColor(baseColor: UIColor, elevationLevel: Int) -> UIColor {
    guard kSurfaceElevationLevels.contains(elevationLevel) else { return baseColor }
    
    let opacity = min(1.0, kDefaultOpacity + (CGFloat(elevationLevel) * 0.01))
    let brightness = 1.0 + (CGFloat(elevationLevel) * 0.005)
    
    var hue: CGFloat = 0
    var saturation: CGFloat = 0
    var brightness_: CGFloat = 0
    var alpha: CGFloat = 0
    
    baseColor.getHue(&hue, saturation: &saturation, brightness: &brightness_, alpha: &alpha)
    
    return UIColor(hue: hue,
                  saturation: saturation,
                  brightness: brightness_ * brightness,
                  alpha: opacity)
}

// MARK: - Core Color System

public struct Colors {
    public static let primary = adaptiveColor(
        light: UIColor(displayP3Red: 0.141, green: 0.278, blue: 0.941, alpha: 1.0),
        dark: UIColor(displayP3Red: 0.278, green: 0.392, blue: 1.0, alpha: 1.0)
    )
    
    public static let primaryVariant = adaptiveColor(
        light: UIColor(displayP3Red: 0.071, green: 0.141, blue: 0.812, alpha: 1.0),
        dark: UIColor(displayP3Red: 0.392, green: 0.482, blue: 1.0, alpha: 1.0)
    )
    
    public static let secondary = adaptiveColor(
        light: UIColor(displayP3Red: 0.941, green: 0.278, blue: 0.278, alpha: 1.0),
        dark: UIColor(displayP3Red: 1.0, green: 0.392, blue: 0.392, alpha: 1.0)
    )
    
    public static let secondaryVariant = adaptiveColor(
        light: UIColor(displayP3Red: 0.812, green: 0.141, blue: 0.141, alpha: 1.0),
        dark: UIColor(displayP3Red: 1.0, green: 0.482, blue: 0.482, alpha: 1.0)
    )
    
    public static let background = adaptiveColor(
        light: UIColor(displayP3Red: 0.969, green: 0.969, blue: 0.969, alpha: 1.0),
        dark: UIColor(displayP3Red: 0.059, green: 0.059, blue: 0.059, alpha: 1.0)
    )
    
    public static let surface = adaptiveColor(
        light: UIColor(displayP3Red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0),
        dark: UIColor(displayP3Red: 0.118, green: 0.118, blue: 0.118, alpha: 1.0)
    )
    
    public static let error = adaptiveColor(
        light: UIColor(displayP3Red: 0.898, green: 0.184, blue: 0.184, alpha: 1.0),
        dark: UIColor(displayP3Red: 1.0, green: 0.321, blue: 0.321, alpha: 1.0)
    )
}

// MARK: - Control Colors

public struct ControlColors {
    public static let buttonBackground = adaptiveColor(
        light: Colors.primary,
        dark: Colors.primary,
        opacity: 0.95
    )
    
    public static let buttonBackgroundPressed = adaptiveColor(
        light: Colors.primaryVariant,
        dark: Colors.primaryVariant,
        opacity: 0.95
    )
    
    public static let buttonBackgroundDisabled = adaptiveColor(
        light: Colors.primary,
        dark: Colors.primary,
        opacity: 0.38
    )
    
    public static let sliderTrack = adaptiveColor(
        light: Colors.primary,
        dark: Colors.primary,
        opacity: 0.24
    )
    
    public static let sliderThumb = adaptiveColor(
        light: Colors.primary,
        dark: Colors.primary,
        opacity: 1.0
    )
    
    public static let sliderThumbPressed = adaptiveColor(
        light: Colors.primaryVariant,
        dark: Colors.primaryVariant,
        opacity: 1.0
    )
}

// MARK: - Visualization Colors

public struct VisualizationColors {
    public static let waveformGradient = adaptiveColor(
        light: UIColor(displayP3Red: 0.278, green: 0.392, blue: 1.0, alpha: 1.0),
        dark: UIColor(displayP3Red: 0.392, green: 0.482, blue: 1.0, alpha: 1.0)
    )
    
    public static let spectrumGradient = adaptiveColor(
        light: UIColor(displayP3Red: 0.941, green: 0.278, blue: 0.278, alpha: 1.0),
        dark: UIColor(displayP3Red: 1.0, green: 0.392, blue: 0.392, alpha: 1.0)
    )
    
    public static let vuMeterLow = adaptiveColor(
        light: UIColor(displayP3Red: 0.278, green: 0.941, blue: 0.278, alpha: 1.0),
        dark: UIColor(displayP3Red: 0.392, green: 1.0, blue: 0.392, alpha: 1.0)
    )
    
    public static let vuMeterMid = adaptiveColor(
        light: UIColor(displayP3Red: 0.941, green: 0.941, blue: 0.278, alpha: 1.0),
        dark: UIColor(displayP3Red: 1.0, green: 1.0, blue: 0.392, alpha: 1.0)
    )
    
    public static let vuMeterHigh = adaptiveColor(
        light: UIColor(displayP3Red: 0.941, green: 0.278, blue: 0.278, alpha: 1.0),
        dark: UIColor(displayP3Red: 1.0, green: 0.392, blue: 0.392, alpha: 1.0)
    )
}

// MARK: - Status Colors

public struct StatusColors {
    public static let success = adaptiveColor(
        light: UIColor(displayP3Red: 0.278, green: 0.941, blue: 0.278, alpha: 1.0),
        dark: UIColor(displayP3Red: 0.392, green: 1.0, blue: 0.392, alpha: 1.0)
    )
    
    public static let warning = adaptiveColor(
        light: UIColor(displayP3Red: 0.941, green: 0.941, blue: 0.278, alpha: 1.0),
        dark: UIColor(displayP3Red: 1.0, green: 1.0, blue: 0.392, alpha: 1.0)
    )
    
    public static let error = Colors.error
    
    public static let info = adaptiveColor(
        light: UIColor(displayP3Red: 0.278, green: 0.278, blue: 0.941, alpha: 1.0),
        dark: UIColor(displayP3Red: 0.392, green: 0.392, blue: 1.0, alpha: 1.0)
    )
    
    public static let progress = adaptiveColor(
        light: Colors.primary,
        dark: Colors.primary,
        opacity: 0.87
    )
}