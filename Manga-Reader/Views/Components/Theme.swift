//
//  Theme.swift
//  Manga-Reader
//
//  The "Ink & Seal" design language. Print-inspired: warm paper in light,
//  near-black ink in dark, a single vermilion seal accent, serif titles,
//  and monospaced metadata stamps. Every color is a dynamic light/dark pair,
//  so a `.preferredColorScheme` override (from Settings) repaints everything.
//

import SwiftUI
import UIKit

// MARK: - Dynamic color helper

private func dynamicColor(light: UInt, dark: UInt) -> Color {
    Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(hex: dark)
            : UIColor(hex: light)
    })
}

private extension UIColor {
    convenience init(hex: UInt, alpha: CGFloat = 1) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}

// MARK: - Palette

/// Semantic color tokens. Reference these, never raw hex, so light/dark and
/// future palette tweaks stay in one place.
enum Ink {
    /// App background — warm paper / near-black ink.
    static let background = dynamicColor(light: 0xFBFAF8, dark: 0x141318)
    /// Raised surface (cards, sheets, bars).
    static let surface = dynamicColor(light: 0xFFFFFF, dark: 0x1D1C22)
    /// A slightly recessed fill, used for placeholders and chips.
    static let surfaceAlt = dynamicColor(light: 0xF1EEE9, dark: 0x26242C)

    /// Primary text — the ink itself.
    static let primary = dynamicColor(light: 0x17140F, dark: 0xF3F1EC)
    /// Secondary text — authors, captions.
    static let secondary = dynamicColor(light: 0x6B655C, dark: 0xA6A199)
    /// Tertiary text — faint metadata.
    static let tertiary = dynamicColor(light: 0x756E64, dark: 0xAAA49B)

    /// Hairline dividers and card frames.
    static let hairline = dynamicColor(light: 0xE5E0D7, dark: 0x2E2C34)

    /// The seal — vermilion (朱). The one accent. Use with restraint.
    static let seal = dynamicColor(light: 0xB93624, dark: 0xFF6B55)
    /// Seal at low opacity, for tint fills behind the accent.
    static let sealSoft = dynamicColor(light: 0xFBE7E2, dark: 0x3A1F1B)
}

// MARK: - Typography

extension Font {
    /// Serif display face (New York, ships with iOS). Titles and section heads.
    static func inkDisplay(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        let style: Font.TextStyle = switch size {
        case ..<21: .title3
        case ..<25: .title2
        case ..<30: .title
        default: .largeTitle
        }
        return .system(style, design: .serif).weight(weight)
    }

    /// Monospaced metadata stamp — "CH·012", page counts, spine labels.
    static func inkMono(_ size: CGFloat, weight: Font.Weight = .medium) -> Font {
        let style: Font.TextStyle = switch size {
        case ..<11: .caption
        case ..<12: .footnote
        case ..<13: .subheadline
        default: .body
        }
        return .system(style, design: .monospaced).weight(weight)
    }
}

// MARK: - Spacing & shape

/// Layout constants. Manga grammar leans on generous gutters (negative space).
enum Gutter {
    static let page: CGFloat = 20   // screen side margins
    static let rail: CGFloat = 14   // gap between cover cards
    static let section: CGFloat = 30 // vertical gap between sections
    static let cardRadius: CGFloat = 8
    static let coverWidth: CGFloat = 128
    static let coverHeight: CGFloat = 182 // ~ manga cover ratio
}

// MARK: - Appearance preference

/// User-facing appearance choice, persisted and applied at the app root.
enum AppearanceMode: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return "System"
        case .light:  return "Light"
        case .dark:   return "Dark"
        }
    }

    var symbol: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light:  return "sun.max"
        case .dark:   return "moon.stars"
        }
    }

    /// nil lets iOS follow the system setting.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light:  return .light
        case .dark:   return .dark
        }
    }
}

/// Shared key so any view can read/write the appearance preference.
let appearanceStorageKey = "appearanceMode"
