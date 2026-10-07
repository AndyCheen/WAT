import SwiftUI
import Core
import Persistence
import DesignSystem

public enum AppRoute: Hashable {
    case progress
    /// 3f з уже відкритим вікном «Шлях рівнів» — тост рівня з вибором чи 🎁 (SPEC-PRIZES §16.6).
    case levelRoad
    case achievements
    case prizes
    case stats
    /// Екран «Призи» з уже відкритою карткою — тап по порятунку серії веде в картку
    /// заморозки, бо заморожувати можна лише з неї (SPEC-NOTIFICATIONS §12.1).
    case prizeCard(String)
    /// Екран «Сповіщення» (§15.1).
    case notifications
    /// DEBUG: «План сповіщень» — заплановане з часами (§16.11).
    case notificationPlan
    /// Звіт-історія (§11.3). Кілька періодів — злите «Підсумки тижня й місяця» грає їх підряд.
    case report([ReportPeriod])
}

/// Кореневий екран: стек навігації 1a → 3f → 2e, 1a → 3f → «Призи», 1a → 4a (PLAN.md §8).
public struct RootView: View {
    @State private var services: AppServices
    @State private var path: [AppRoute] = []
    @State private var themeMode: ThemeMode
    @State private var hapticsEnabled: Bool

    public init(services: AppServices, initialRoute: AppRoute? = nil) {
        _services = State(initialValue: services)
        _themeMode = State(initialValue: services.profile.themeMode)
        _hapticsEnabled = State(initialValue: services.profile.hapticsEnabled)
        _path = State(initialValue: initialRoute.map { [$0] } ?? [])
    }

    public var body: some View {
        WTThemedContainer(mode: themeMode, hapticsEnabled: hapticsEnabled) {
            NavigationStack(path: $path) {
                HomeScreen(
                    services: services,
                    themeMode: $themeMode,
                    hapticsEnabled: $hapticsEnabled,
                    onOpenProgress: { path.append(.progress) },
                    onOpenLevelRoad: { path.append(.levelRoad) },
                    onOpenStats: { path.append(.stats) },
                    onOpenAchievements: { path.append(.achievements) },
                    onOpenPrize: { path.append(.prizeCard($0)) },
                    onOpenNotifications: { path.append(.notifications) },
                    isOnTop: { path.isEmpty }
                )
                .wtHideNavigationBar()
                .navigationDestination(for: AppRoute.self) { route in
                    destination(route).wtHideNavigationBar()
                }
            }
        }
        // Тап по сповіщенню, зокрема той, що запустив застосунок: `initial` — бо при холодному
        // старті маршрут з'являється раніше за перший кадр.
        .onChange(of: services.router.pendingPath, initial: true) {
            if let route = services.router.takePath() { path = route }
        }
    }

    @ViewBuilder
    private func destination(_ route: AppRoute) -> some View {
        switch route {
        case .progress, .levelRoad:
            ProgressScreen(
                services: services,
                opensLevelRoad: route == .levelRoad,
                onBack: { path.removeLast() },
                onOpenAllAchievements: { path.append(.achievements) },
                onOpenAllPrizes: { path.append(.prizes) }
            )
        case .achievements:
            AchievementsScreen(services: services, onBack: { path.removeLast() })
        case .prizes:
            PrizesScreen(services: services, onBack: { path.removeLast() })
        case .stats:
            StatsScreen(services: services, onBack: { path.removeLast() })
        case .prizeCard(let key):
            PrizesScreen(services: services, onBack: { path.removeLast() }, focusKey: key)
        case .notifications:
            NotificationsScreen(
                services: services,
                onBack: { path.removeLast() },
                onOpenPlan: { path.append(.notificationPlan) }
            )
        case .notificationPlan:
            NotificationPlanScreen(services: services, onBack: { path.removeLast() })
        case .report(let periods):
            ReportScreen(services: services, periods: periods, onClose: { path.removeLast() })
        }
    }
}
