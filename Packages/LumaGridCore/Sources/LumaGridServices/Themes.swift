/// How a cosmetic theme is obtained.
public enum ThemeUnlock: Hashable, Codable, Sendable {
    case free
    case coins(Int)
    case purchase(productID: String)
}

/// A cosmetic look. Colors are hex strings ("#RRGGBB") so this stays UI-framework agnostic;
/// the app converts them to SwiftUI colors. Display names are localized in the app layer.
public struct ThemeDefinition: Hashable, Identifiable, Sendable {
    public let id: String
    public let unlock: ThemeUnlock
    /// Top and bottom of the background gradient.
    public let backgroundTop: String
    public let backgroundBottom: String
    /// Empty board cell color.
    public let boardCell: String
    /// Board frame/backing color.
    public let boardBacking: String
    /// Exactly `GameConfiguration.paletteSize` tile colors.
    public let tiles: [String]
    public let accent: String

    public init(id: String, unlock: ThemeUnlock, backgroundTop: String, backgroundBottom: String,
                boardCell: String, boardBacking: String, tiles: [String], accent: String) {
        self.id = id
        self.unlock = unlock
        self.backgroundTop = backgroundTop
        self.backgroundBottom = backgroundBottom
        self.boardCell = boardCell
        self.boardBacking = boardBacking
        self.tiles = tiles
        self.accent = accent
    }
}

public enum ThemeCatalog {
    public static let defaultThemeID = "lumen"

    public static func standard(products: ProductIdentifiers) -> [ThemeDefinition] {
        [
            // Default: deep ink with mint, cyan, lavender, coral, soft gold.
            ThemeDefinition(
                id: "lumen", unlock: .free,
                backgroundTop: "#1B1840", backgroundBottom: "#0B0A1F",
                boardCell: "#25224F", boardBacking: "#151334",
                tiles: ["#5FE3C0", "#4CC9F0", "#B69CFF", "#FF8A7A", "#F5CF6B"],
                accent: "#7FE7FF"
            ),
            ThemeDefinition(
                id: "tide", unlock: .coins(400),
                backgroundTop: "#0C2B3A", backgroundBottom: "#061520",
                boardCell: "#123A4C", boardBacking: "#0A2230",
                tiles: ["#3DD6D0", "#5AA9F5", "#9AE6B4", "#F6AD7B", "#E8E3A0"],
                accent: "#62F0E6"
            ),
            ThemeDefinition(
                id: "ember", unlock: .coins(600),
                backgroundTop: "#2A1424", backgroundBottom: "#120910",
                boardCell: "#3A1C30", boardBacking: "#1F0E1A",
                tiles: ["#FF9F6B", "#FF6F91", "#FFD36E", "#C59BFF", "#7CE0B5"],
                accent: "#FFB27A"
            ),
            ThemeDefinition(
                id: "nebula", unlock: .purchase(productID: products.themeNebula),
                backgroundTop: "#22104A", backgroundBottom: "#0A0620",
                boardCell: "#2E1A5E", boardBacking: "#170C36",
                tiles: ["#E07CFF", "#7C8CFF", "#55E6FF", "#FF7CC8", "#FFE08A"],
                accent: "#C9A2FF"
            ),
            ThemeDefinition(
                id: "sunrise", unlock: .purchase(productID: products.themeSunrise),
                backgroundTop: "#3A2340", backgroundBottom: "#1A1026",
                boardCell: "#4A2C4C", boardBacking: "#24152C",
                tiles: ["#FFB36B", "#FF7A7A", "#FFE27A", "#8FE3B0", "#87C6FF"],
                accent: "#FFC98A"
            ),
        ]
    }
}
