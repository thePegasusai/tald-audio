// UIKit v13.0+
import UIKit
import SwiftUI

// MARK: - Global Constants

private let kDefaultFontName = "SF Pro Display"
private let kFallbackFontName = "Helvetica Neue"
private let kMinFontScale: CGFloat = 1.0
private let kMaxFontScale: CGFloat = 2.0
private let kFontCacheSize = 50
private let kDefaultTextWeight = UIFont.Weight.regular

// MARK: - Font Cache

private var fontCache = NSCache<NSString, UIFont>()

// MARK: - Typography System

@available(iOS 13.0, *)
public struct Typography {
    // MARK: - Text Styles
    
    public static let title1 = scaledFont(
        UIFont.systemFont(ofSize: 28, weight: .bold),
        textStyle: .title1,
        traits: .current
    )
    
    public static let title2 = scaledFont(
        UIFont.systemFont(ofSize: 22, weight: .semibold),
        textStyle: .title2,
        traits: .current
    )
    
    public static let headline = scaledFont(
        UIFont.systemFont(ofSize: 17, weight: .semibold),
        textStyle: .headline,
        traits: .current
    )
    
    public static let body = scaledFont(
        UIFont.systemFont(ofSize: 17, weight: .regular),
        textStyle: .body,
        traits: .current
    )
    
    public static let caption = scaledFont(
        UIFont.systemFont(ofSize: 12, weight: .regular),
        textStyle: .caption1,
        traits: .current
    )
    
    // MARK: - SwiftUI Font Support
    
    public static func swiftUIFont(style: UIFont.TextStyle, weight: UIFont.Weight = kDefaultTextWeight) -> Font {
        let uiFont = adaptiveFont(
            style: style.rawValue,
            size: UIFont.preferredFont(forTextStyle: style).pointSize,
            weight: weight,
            isAccessibilityCategory: UIAccessibility.isBoldTextEnabled
        )
        return Font(uiFont as CTFont)
    }
}

// MARK: - Text Styles

public struct TextStyles {
    public static let regular = UIFont.Weight.regular
    public static let medium = UIFont.Weight.medium
    public static let semibold = UIFont.Weight.semibold
    public static let bold = UIFont.Weight.bold
    public static let heavy = UIFont.Weight.heavy
}

// MARK: - Font Scaling Functions

@available(iOS 13.0, *)
private func scaledFont(
    _ baseFont: UIFont,
    textStyle: UIFont.TextStyle,
    traits: UITraitCollection
) -> UIFont {
    // Generate cache key
    let cacheKey = "\(baseFont.fontName)_\(textStyle.rawValue)_\(traits.preferredContentSizeCategory.rawValue)" as NSString
    
    // Check cache first
    if let cachedFont = fontCache.object(forKey: cacheKey) {
        return cachedFont
    }
    
    // Create metrics for dynamic type
    let metrics = UIFontMetrics(forTextStyle: textStyle)
    
    // Scale font based on user's preferred content size
    let scaledFont = metrics.scaledFont(
        for: baseFont,
        compatibleWith: traits
    )
    
    // Handle right-to-left text direction
    let fontDescriptor = scaledFont.fontDescriptor.withSymbolicTraits(
        traits.layoutDirection == .rightToLeft ? .traitRightToLeft : []
    ) ?? scaledFont.fontDescriptor
    
    // Create final font with all attributes
    let finalFont = UIFont(descriptor: fontDescriptor, size: scaledFont.pointSize)
    
    // Cache the result
    fontCache.setObject(finalFont, forKey: cacheKey)
    
    return finalFont
}

@available(iOS 13.0, *)
private func adaptiveFont(
    style: String,
    size: CGFloat,
    weight: UIFont.Weight,
    isAccessibilityCategory: Bool
) -> UIFont {
    // Create base font with custom name or fallback to system font
    let baseFont: UIFont
    if let customFont = UIFont(name: kDefaultFontName, size: size) {
        baseFont = customFont
    } else {
        baseFont = UIFont.systemFont(ofSize: size, weight: weight)
    }
    
    // Apply weight variation
    let descriptor = baseFont.fontDescriptor.addingAttributes([
        .traits: [
            UIFontDescriptor.TraitKey.weight: weight
        ]
    ])
    
    // Scale for accessibility if needed
    let scaledSize = isAccessibilityCategory ? size * 1.5 : size
    
    // Create font with descriptor and handle potential failures
    if let font = UIFont(descriptor: descriptor, size: scaledSize) {
        return font
    }
    
    // Return system font as fallback
    return UIFont.systemFont(ofSize: scaledSize, weight: weight)
}