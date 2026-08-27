import SwiftUI

public extension Color {
    /// `Color(hex: "#5aa9f0")` — щоб значення з макета переносились без перерахунку.
    init(hex: String) {
        var string = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if string.hasPrefix("#") { string.removeFirst() }
        var value: UInt64 = 0
        Scanner(string: string).scanHexInt64(&value)
        let r, g, b, a: Double
        switch string.count {
        case 8:
            r = Double((value >> 24) & 0xFF) / 255
            g = Double((value >> 16) & 0xFF) / 255
            b = Double((value >> 8) & 0xFF) / 255
            a = Double(value & 0xFF) / 255
        default:
            r = Double((value >> 16) & 0xFF) / 255
            g = Double((value >> 8) & 0xFF) / 255
            b = Double(value & 0xFF) / 255
            a = 1
        }
        self.init(.sRGB, red: r, green: g, blue: b, opacity: a)
    }
}

/// Семантична палітра. Значення — точна витяжка з макетів (див. DESIGN-TOKENS.md §2.1).
public struct WTTheme: Equatable, Sendable {
    public let isDark: Bool
    public let screen: Color
    public let card: Color
    public let sheet: Color
    public let chip: Color
    public let button: Color
    public let textPrimary: Color
    public let textMuted: Color
    public let textButton: Color
    public let accent: Color
    public let line: Color
    public let track: Color
    public let dotOff: Color
    public let deleteBg: Color
    public let ringStart: Color
    public let ringEnd: Color

    public static let light = WTTheme(
        isDark: false,
        screen: Color(hex: "#f7fbff"),
        card: Color(hex: "#ffffff"),
        sheet: Color(hex: "#ffffff"),
        chip: Color(hex: "#eaf4ff"),
        button: Color(hex: "#eaf4ff"),
        textPrimary: Color(hex: "#1f4a72"),
        textMuted: Color(hex: "#8aa1bd"),
        textButton: Color(hex: "#3d8fd6"),
        accent: Color(hex: "#5aa9f0"),
        line: Color(hex: "#1f4a72").opacity(0.10),
        track: Color(hex: "#e4f0fb"),
        dotOff: Color(hex: "#dce8f3"),
        deleteBg: Color(hex: "#fdecec"),
        ringStart: Color(hex: "#bfe3ff"),
        ringEnd: Color(hex: "#6bb6f2")
    )

    public static let dark = WTTheme(
        isDark: true,
        screen: Color(hex: "#0c1524"),
        card: Color(hex: "#161f33"),
        sheet: Color(hex: "#131e30"),
        chip: Color(hex: "#17233a"),
        button: Color(hex: "#17233a"),
        textPrimary: Color(hex: "#eaf2ff"),
        textMuted: Color(hex: "#8ba0bd"),
        textButton: Color(hex: "#bcd8ff"),
        accent: Color(hex: "#7cc4ff"),
        line: Color.white.opacity(0.08),
        track: Color.white.opacity(0.08),
        dotOff: Color.white.opacity(0.14),
        deleteBg: Color(hex: "#e5484d").opacity(0.16),
        ringStart: Color(hex: "#8fd0ff"),
        ringEnd: Color(hex: "#3b6ef5")
    )
}

/// Кольори, які не залежать від теми (DESIGN-TOKENS.md §2.2).
public enum WTColor {
    public static let orange = Color(hex: "#ff8a3d")
    public static let success = Color(hex: "#3fb56f")
    public static let successText = Color(hex: "#3ea86b")
    public static let danger = Color(hex: "#e5484d")
    public static let warnBg = Color(hex: "#fdf1da")
    public static let warnText = Color(hex: "#a97a1f")
    public static let prizeBg = Color(hex: "#fff8ec")
    public static let prizeIconBg = Color(hex: "#ffe9c8")
    public static let goldIconBg = Color(hex: "#fff2e2")
    public static let textSecondary = Color(hex: "#3d4d66")
    public static let textTertiary = Color(hex: "#5c7291")
    public static let textQuaternary = Color(hex: "#b7c3d4")
    public static let neutralTrack = Color(hex: "#eef2f7")
    public static let neutralEmpty = Color(hex: "#e4e8ee")
    public static let neutralFuture = Color(hex: "#f2f4f7")
    public static let neutralLocked = Color(hex: "#e6e8eb")
    public static let neutralDisabled = Color(hex: "#d7dee8")
    public static let futureText = Color(hex: "#c3cddb")
    public static let scrim = Color(hex: "#081020").opacity(0.35)
    public static let modalScrim = Color(hex: "#0f2038").opacity(0.45)

    /// Заливка комірки календаря за відсотком норми (макет 4a).
    public static func calendarFill(pct: Int) -> Color {
        guard pct > 0 else { return neutralEmpty }
        let intensity = min(1, Double(pct) / 100)
        return Color(hex: "#5aa9f0").opacity(0.25 + intensity * 0.75)
    }

    /// 5 рівнів теплокарти «Коли ти пʼєш».
    public static func heatmapFill(level: Int) -> Color {
        switch level {
        case 1: return Color(hex: "#5aa9f0").opacity(0.28)
        case 2: return Color(hex: "#5aa9f0").opacity(0.52)
        case 3: return Color(hex: "#5aa9f0").opacity(0.76)
        case 4: return Color(hex: "#5aa9f0")
        default: return neutralTrack
        }
    }
}

/// Радіуси, відступи й тіні з макетів (DESIGN-TOKENS.md §3).
public enum WTRadius {
    public static let chip: CGFloat = 12
    public static let control: CGFloat = 14
    public static let button: CGFloat = 18
    public static let primaryButton: CGFloat = 20
    public static let tile: CGFloat = 20
    public static let panel: CGFloat = 22
    public static let card: CGFloat = 24
    public static let sheet: CGFloat = 32
    public static let pill: CGFloat = 999
}

public enum WTSpacing {
    public static let screenTop: CGFloat = 64
    public static let screenBottom: CGFloat = 44
    public static let screenSide: CGFloat = 24
    public static let screenSideHome: CGFloat = 26
    public static let cardPaddingV: CGFloat = 20
    public static let cardPaddingH: CGFloat = 18
    public static let cardGap: CGFloat = 18
}

public struct WTShadow {
    public let color: Color
    public let radius: CGFloat
    public let x: CGFloat
    public let y: CGFloat

    public static let card = WTShadow(color: Color(hex: "#1e3c78").opacity(0.06), radius: 12, x: 0, y: 8)
    public static let sheet = WTShadow(color: Color(hex: "#081020").opacity(0.15), radius: 20, x: 0, y: -12)
    public static let modal = WTShadow(color: Color(hex: "#142850").opacity(0.25), radius: 25, x: 0, y: 20)
    public static let knob = WTShadow(color: Color.black.opacity(0.25), radius: 1.5, x: 0, y: 1)
}

public extension View {
    func wtShadow(_ shadow: WTShadow) -> some View {
        self.shadow(color: shadow.color, radius: shadow.radius, x: shadow.x, y: shadow.y)
    }
}

public enum WTAnimation {
    /// `sheetUp .32s cubic-bezier(.22,1,.36,1)`
    public static let sheet = Animation.spring(response: 0.42, dampingFraction: 0.86)
    /// заповнення кільця, .75s
    public static let ring = Animation.spring(response: 0.75, dampingFraction: 0.9)
    public static let toggle = Animation.easeInOut(duration: 0.2)
    public static let fade = Animation.easeInOut(duration: 0.2)
    /// просідання кнопки під пальцем — коротке й пружне, інакше відчувається як лаг
    public static let press = Animation.spring(response: 0.22, dampingFraction: 0.7)
    /// поява й зникнення тоста
    public static let toast = Animation.spring(response: 0.38, dampingFraction: 0.82)
}

private struct WTThemeKey: EnvironmentKey {
    static let defaultValue = WTTheme.light
}

public extension EnvironmentValues {
    var wtTheme: WTTheme {
        get { self[WTThemeKey.self] }
        set { self[WTThemeKey.self] = newValue }
    }
}
