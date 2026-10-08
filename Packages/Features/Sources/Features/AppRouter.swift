import Foundation
import Observation
import Core
import Gamification
import Insights
import Notifications

/// Перехід, який просить сповіщення, — тап, дія «Інший об'єм» чи прапорець `--notification-tap`.
///
/// Два «споживачі» з окремими полями: стек навігації читає `RootView`, шторку чи картку на
/// головному — `HomeScreen`. Одне спільне поле два екрани розбирали б навперегони.
@MainActor
@Observable
public final class AppRouter {
    public enum HomeIntent: Equatable {
        /// Шторка «Інше» з типовою порцією `P` (SPEC-NOTIFICATIONS §6.4).
        case customAmount(Int)
        /// Картка досягнення поверх головного — відлуння розблокування (§12.1).
        case achievement(String)
        /// Вікно «Склянка» — тап по ранковій склянці (§7, §16.4).
        case glass
        /// Вікно «Графік дня» повз правило частоти — `--start-screen schedule-suggestion` (WAT-41).
        case schedule(ScheduleSuggestion)
    }

    /// Новий стек навігації; порожній — повернутися на головний.
    public private(set) var pendingPath: [AppRoute]?
    public private(set) var pendingHomeIntent: HomeIntent?

    public init() {}

    public func open(_ route: NotificationTapRoute) {
        switch route {
        case .home:
            pendingPath = []
        case .customAmount(let ml):
            pendingPath = []
            pendingHomeIntent = .customAmount(ml)
        case .freezeCard:
            pendingPath = [.prizeCard(RewardCatalog.freezeKey)]
        case .boostCard:
            pendingPath = [.prizeCard(RewardCatalog.boostKey)]
        case .achievement(let key):
            pendingPath = []
            pendingHomeIntent = .achievement(key)
        case .progress:
            pendingPath = [.progress]
        case .glass:
            pendingPath = []
            pendingHomeIntent = .glass
        case .report(let periods):
            pendingPath = [.report(periods)]
        }
    }

    /// Екран без шторки — тап по віджету «Ритм дня» веде у статистику (WAT-30, SPEC-WIDGETS §9.4).
    public func open(path: [AppRoute]) {
        pendingPath = path
    }

    public func openScheduleSuggestion(_ suggestion: ScheduleSuggestion) {
        pendingPath = []
        pendingHomeIntent = .schedule(suggestion)
    }

    public func takePath() -> [AppRoute]? {
        defer { pendingPath = nil }
        return pendingPath
    }

    public func takeHomeIntent() -> HomeIntent? {
        defer { pendingHomeIntent = nil }
        return pendingHomeIntent
    }
}
