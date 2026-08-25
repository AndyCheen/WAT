import SwiftUI
import Persistence
import DesignSystem

public enum AppRoute: Hashable {
    case progress
    case achievements
    case stats
}

/// Кореневий екран: стек навігації 1a → 3f → 2e, 1a → 4a (PLAN.md §8).
public struct RootView: View {
    @State private var services: AppServices
    @State private var path: [AppRoute] = []
    @State private var themeMode: ThemeMode

    public init(services: AppServices, initialRoute: AppRoute? = nil) {
        _services = State(initialValue: services)
        _themeMode = State(initialValue: services.profile.themeMode)
        _path = State(initialValue: initialRoute.map { [$0] } ?? [])
    }

    public var body: some View {
        WTThemedContainer(mode: themeMode) {
            NavigationStack(path: $path) {
                HomeScreen(
                    services: services,
                    themeMode: $themeMode,
                    onOpenProgress: { path.append(.progress) },
                    onOpenStats: { path.append(.stats) }
                )
                .wtHideNavigationBar()
                .navigationDestination(for: AppRoute.self) { route in
                    destination(route).wtHideNavigationBar()
                }
            }
        }
    }

    @ViewBuilder
    private func destination(_ route: AppRoute) -> some View {
        switch route {
        case .progress:
            ProgressScreen(
                services: services,
                onBack: { path.removeLast() },
                onOpenAllAchievements: { path.append(.achievements) }
            )
        case .achievements:
            AchievementsScreen(services: services, onBack: { path.removeLast() })
        case .stats:
            StatsScreen(services: services, onBack: { path.removeLast() })
        }
    }
}
