import SwiftUI
import Persistence
import DesignSystem

/// Застосовує тему й налаштування відгуку з профілю до всього дерева.
public struct WTThemedContainer<Content: View>: View {
    @Environment(\.colorScheme) private var systemScheme
    private let mode: ThemeMode
    private let hapticsEnabled: Bool
    private let content: Content

    public init(mode: ThemeMode, hapticsEnabled: Bool = true, @ViewBuilder content: () -> Content) {
        self.mode = mode
        self.hapticsEnabled = hapticsEnabled
        self.content = content()
    }

    private var theme: WTTheme {
        switch mode {
        case .light: return .light
        case .dark: return .dark
        case .system: return systemScheme == .dark ? .dark : .light
        }
    }

    public var body: some View {
        content
            .environment(\.wtTheme, theme)
            // Вимикач гаптики живе тут, тож окремі екрани про налаштування не знають.
            .environment(\.wtHapticsEnabled, hapticsEnabled)
            .background(theme.screen.ignoresSafeArea())
            .preferredColorScheme(mode == .system ? nil : (mode == .dark ? .dark : .light))
            .wtTypeSizeLimit()
    }
}
