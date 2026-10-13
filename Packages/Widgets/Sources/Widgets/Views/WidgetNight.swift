import SwiftUI
import WidgetKit
import DesignSystem

// Ніч у віджетах (рішення від 13.10.2026, SPEC-WIDGETS §7, варіант A «Нічне небо» в Design/Widgets.html §8).
//
// Після відбою й до підйому запас не ведеться, а «0%» і «Добраніч» читалися як «води немає, пий». Тож уночі «Запас
// води» й «Частина доби» переходять у нічне небо: місяць, зорі, жодних відсотків запасу. Небо — тло віджета: у
// тонованому режимі iOS 18 його прибирає система, лишаються місяць (акцентний) і текст.

/// Тло нічного віджета: глибоке небо й кілька зір.
struct NightSky: View {
    let isMedium: Bool

    var body: some View {
        LinearGradient(colors: [WTColor.nightSkyTop, WTColor.nightSkyBottom], startPoint: .topLeading, endPoint: .bottomTrailing)
            .overlay {
                Canvas { context, size in
                    for star in stars {
                        let radius = star.radius * 1.5
                        let rect = CGRect(x: star.x * size.width - radius, y: star.y * size.height - radius,
                                          width: radius * 2, height: radius * 2)
                        context.fill(Path(ellipseIn: rect), with: .color(.white.opacity(0.6)))
                    }
                }
            }
    }

    /// Зорі — поза підписом і текстом: у середньому — між текстом і кнопками, у малому — справа й згори.
    private var stars: [(x: Double, y: Double, radius: Double)] {
        isMedium
            ? [(0.38, 0.1, 1), (0.52, 0.26, 0.8), (0.3, 0.36, 0.7), (0.6, 0.08, 1.2), (0.47, 0.47, 0.6), (0.62, 0.52, 0.7)]
            : [(0.62, 0.07, 0.8), (0.9, 0.42, 1), (0.75, 0.3, 0.6), (0.93, 0.9, 0.6)]
    }
}

/// Місяць — SF Symbol: той самий знак, що в кільці «Запасу» на екрані блокування.
struct NightMoon: View {
    @Environment(\.wtTheme) private var theme
    let size: CGFloat

    var body: some View {
        Image(systemName: "moon.fill")
            .font(.system(size: size, weight: .regular))
            .foregroundStyle(theme.isTinted ? theme.accent : WTColor.moon)
            .widgetAccentable()
    }
}

extension WTTheme {
    /// Палітра поверх нічного неба — світлий текст у будь-якій темі; тонований режим лишає свою.
    var night: WTTheme { isTinted ? self : .dark }
}
