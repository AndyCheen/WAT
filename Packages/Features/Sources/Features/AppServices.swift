import Foundation
import SwiftData
import Core
import Persistence
import Metrics
import Hydration
import Gamification
import Insights
import Notifications

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
    public let notifications: NotificationService
    /// Куди веде тап по сповіщенню — читають `RootView` і `HomeScreen`.
    public let router = AppRouter()

    /// Змінюється, коли дані застаріли не через дію на екрані: повернення з фону, нова доба,
    /// зміна поясу, дія зі сповіщення у фоні. Екрани слухають його й перечитують знімки —
    /// власні дії вони й так перечитують самі, з анімацією.
    public internal(set) var epoch: Int = 0

    /// Застосунок на екрані. Порція з дії сповіщення, поки його немає, — «поза застосунком»:
    /// розблокування від неї ніхто не побачить, тож потрібне відлуння (SPEC-NOTIFICATIONS §12.1).
    public private(set) var isForeground = false

    /// День останнього повного перерахунку гейміфікації — щоб не ганяти його на кожне
    /// повернення з фону, а лише коли настала нова доба.
    private var lastRefreshedDay: DayKey?

    /// `notificationCenter` за замовчуванням — у пам'яті: справжній `UNUserNotificationCenter`
    /// у процесі SPM-тестів падає, тож його передає лише застосунок.
    public init(
        container: ModelContainer,
        clock: Clock = SystemClock(),
        notificationCenter: NotificationCenterProtocol? = nil,
        bubbleSoundAvailable: Bool = false
    ) {
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
        self.notifications = NotificationService(
            store: NotificationStore(context: context), profiles: profiles, metrics: metrics,
            calendar: calendar, center: notificationCenter ?? InMemoryNotificationCenter(),
            bubbleSoundAvailable: bubbleSoundAvailable
        )
    }

    /// Перший запуск: профіль, норма, пресети, підписка гейміфікації й сповіщень.
    /// Системного запиту дозволу тут немає — запит без контексту найчастіше відхиляють (§16.5).
    public func bootstrap() {
        _ = profiles.profile()
        if profiles.goalRevisions().isEmpty {
            profiles.setGoal(2000, source: .onboarding, effectiveFrom: calendar.today, at: calendar.now)
        }
        _ = profiles.quickAddPresets()
        gamification.bootstrap()
        notifications.bootstrap()
        notifications.contextProvider = { [unowned self] in self.makeNotificationContext() }
        lastRefreshedDay = calendar.today
        metrics.record(MetricEvent(name: .appOpened, value: 1, occurredAt: calendar.now))
        touch()
    }

    /// Дія користувача завершена (порція, undo, норма, налаштування, приз) — один раз на дію,
    /// як і `metrics.commit()`. Перепланування сповіщень іде асинхронно, після дії (§16.3).
    public func touch() {
        if isForeground { notifications.recordInteraction(at: calendar.now) }
        notifications.setNeedsReschedule()
    }

    /// Застосунок повернувся з фону (`scenePhase == .active`).
    ///
    /// Без цього застосунок, лишений відкритим на ніч, показував учорашній день: доба
    /// перераховувалась лише після дії користувача. Відкриття застосунку ще й обнуляє
    /// лічильник проігнорованих нагадувань (SPEC-NOTIFICATIONS §6.2, «Скидання»).
    public func handleBecameActive() {
        isForeground = true
        refreshIfNewDay()
        notifications.recordInteraction(at: calendar.now)
        epoch &+= 1
        notifications.setNeedsReschedule()
    }

    /// Застосунок іде у фон — план має бути актуальним до того, як iOS його призупинить:
    /// відкладене перепланування після останньої порції інакше не встигло б.
    public func handleEnteredBackground() async {
        isForeground = false
        await notifications.rescheduleNow()
    }

    /// Північ, зміна поясу чи системного часу, поки застосунок відкритий.
    public func handleTimeChange() {
        refreshIfNewDay()
        epoch &+= 1
        notifications.setNeedsReschedule()
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

    public var profile: UserProfile { profiles.profile() }
}
