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

    /// Змінюється, коли дані застаріли не через дію на екрані: повернення з фону, нова доба,
    /// зміна поясу. Екрани слухають його й перечитують знімки — власні дії вони й так
    /// перечитують самі, з анімацією.
    public private(set) var epoch: Int = 0

    /// День останнього повного перерахунку гейміфікації — щоб не ганяти його на кожне
    /// повернення з фону, а лише коли настала нова доба.
    private var lastRefreshedDay: DayKey?

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
        lastRefreshedDay = calendar.today
        metrics.record(MetricEvent(name: .appOpened, value: 1, occurredAt: calendar.now))
        touch()
    }

    /// Застосунок повернувся з фону (`scenePhase == .active`).
    ///
    /// Без цього застосунок, лишений відкритим на ніч, показував учорашній день: доба
    /// перераховувалась лише після дії користувача (CLAUDE.md, «Відомі прогалини», п. 1).
    public func handleBecameActive() {
        refreshIfNewDay()
        epoch &+= 1
    }

    /// Північ, зміна поясу чи системного часу, поки застосунок відкритий.
    public func handleTimeChange() {
        refreshIfNewDay()
        epoch &+= 1
    }

    /// Нова доба — нові щоденні завдання й перерахована серія. Свій `commit()`: це окрема
    /// подія, не частина дії користувача.
    private func refreshIfNewDay() {
        let today = calendar.today
        guard today != lastRefreshedDay else { return }
        lastRefreshedDay = today
        gamification.refresh(at: calendar.now)
        metrics.commit()
    }

    /// Сигнал екранам, що дані змінилися.
    public func touch() {
        revision &+= 1
    }

    public var profile: UserProfile { profiles.profile() }
}
