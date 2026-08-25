import Foundation
import SwiftData
import Core
import Persistence
import Metrics
import Hydration
import Gamification
import Insights

/// Композиційний корінь: збирає репозиторії та сервіси й тримає їх разом.
/// Застосунок-таргет лишається тонким — уся збірка тут.
@MainActor
@Observable
public final class AppServices {
    public let container: ModelContainer
    public let clock: Clock
    public let calendar: CalendarService

    public let profiles: ProfileRepository
    public let dayLogs: DayLogRepository
    public let metrics: MetricsService
    public let hydration: HydrationService
    public let gamification: GamificationService
    public let insights: InsightsService

    /// Змінюється при кожній дії — екрани перечитують знімки.
    public private(set) var revision: Int = 0

    public init(container: ModelContainer, clock: Clock = SystemClock()) {
        self.container = container
        self.clock = clock
        let context = container.mainContext
        let calendar = CalendarService(clock: clock)
        self.calendar = calendar

        let profiles = ProfileRepository(context: context)
        let dayLogs = DayLogRepository(context: context)
        let metrics = MetricsService(store: MetricStore(context: context), calendar: calendar)

        self.profiles = profiles
        self.dayLogs = dayLogs
        self.metrics = metrics
        self.hydration = HydrationService(
            dayLogs: dayLogs, profiles: profiles, metrics: metrics, calendar: calendar
        )
        self.gamification = GamificationService(
            store: GamificationStore(context: context), dayLogs: dayLogs,
            profiles: profiles, metrics: metrics, calendar: calendar
        )
        self.insights = InsightsService(
            dayLogs: dayLogs, profiles: profiles, metrics: metrics, calendar: calendar
        )
    }

    /// Перший запуск: профіль, норма, пресети, підписка гейміфікації.
    public func bootstrap() {
        _ = profiles.profile()
        if profiles.goalRevisions().isEmpty {
            profiles.setGoal(2000, source: .onboarding, effectiveFrom: calendar.today, at: calendar.now)
        }
        _ = profiles.quickAddPresets()
        gamification.bootstrap()
        metrics.record(MetricEvent(name: .appOpened, value: 1, occurredAt: calendar.now))
        touch()
    }

    /// Сигнал екранам, що дані змінилися.
    public func touch() {
        revision &+= 1
    }

    public var profile: UserProfile { profiles.profile() }
}
