import SwiftUI
import Persistence
import DesignSystem

/// Застосовує тему з налаштувань користувача до всього дерева.
public struct WTThemedContainer<Content: View>: View {
    @Environment(\.colorScheme) private var systemScheme
    private let mode: ThemeMode
    private let content: Content

    public init(mode: ThemeMode, @ViewBuilder content: () -> Content) {
        self.mode = mode
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
            .background(theme.screen.ignoresSafeArea())
            .preferredColorScheme(mode == .system ? nil : (mode == .dark ? .dark : .light))
            .wtTypeSizeLimit()
    }
}
