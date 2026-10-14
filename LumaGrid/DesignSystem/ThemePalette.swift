import SwiftUI
import LumaGridServices

extension Color {
    /// Creates a color from "#RRGGBB". Invalid strings fall back to magenta so mistakes are visible in development.
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard cleaned.count == 6, let value = UInt32(cleaned, radix: 16) else {
            self = .pink
            return
        }
        self.init(
            .sRGB,
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255,
            opacity: 1
        )
    }
}

/// Fixed interface colors shared by every theme.
enum LumaColors {
    /// Warm off-white for primary text.
    static let text = Color(hex: "#F6F1E7")
    static let secondaryText = Color(hex: "#F6F1E7").opacity(0.68)
    static let panel = Color.white.opacity(0.07)
    static let panelStroke = Color.white.opacity(0.12)
    static let coin = Color(hex: "#F5CF6B")
    static let valid = Color(hex: "#7FE7FF")
    static let invalid = Color(hex: "#FF8A7A")
}

/// A theme resolved into SwiftUI colors.
struct ThemePalette: Equatable {
    let id: String
    let backgroundTop: Color
    let backgroundBottom: Color
    let boardCell: Color
    let boardBacking: Color
    let tiles: [Color]
    let accent: Color

    init(_ theme: ThemeDefinition) {
        id = theme.id
        backgroundTop = Color(hex: theme.backgroundTop)
        backgroundBottom = Color(hex: theme.backgroundBottom)
        boardCell = Color(hex: theme.boardCell)
        boardBacking = Color(hex: theme.boardBacking)
        tiles = theme.tiles.map(Color.init(hex:))
        accent = Color(hex: theme.accent)
    }

    func tile(_ index: Int) -> Color {
        guard !tiles.isEmpty else { return accent }
        return tiles[((index % tiles.count) + tiles.count) % tiles.count]
    }

    var background: LinearGradient {
        LinearGradient(colors: [backgroundTop, backgroundBottom], startPoint: .top, endPoint: .bottom)
    }

    static let `default` = ThemePalette(AppConfiguration.themes[0])
}

private struct PaletteKey: EnvironmentKey {
    static let defaultValue = ThemePalette.default
}

private struct ReduceMotionPreferenceKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var palette: ThemePalette {
        get { self[PaletteKey.self] }
        set { self[PaletteKey.self] = newValue }
    }

    /// True when either the system Reduce Motion setting or the in-game preference is on.
    var lumaReduceMotion: Bool {
        get { self[ReduceMotionPreferenceKey.self] }
        set { self[ReduceMotionPreferenceKey.self] = newValue }
    }
}

/// Localized display text for theme IDs (kept out of the services layer).
enum ThemeText {
    static func name(for id: String) -> String {
        switch id {
        case "lumen": return String(localized: "Lumen")
        case "tide": return String(localized: "Tide")
        case "ember": return String(localized: "Ember")
        case "nebula": return String(localized: "Nebula")
        case "sunrise": return String(localized: "Sunrise")
        default: return id.capitalized
        }
    }
}
