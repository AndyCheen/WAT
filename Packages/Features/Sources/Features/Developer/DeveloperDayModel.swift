import Foundation
import Observation
import Core
import Persistence
import Hydration

/// Редактор дня в режимі розробника (WAT-68): будь-який минулий день чи сьогодні — норма, порції з часом,
/// заповнення, заморозка.
@MainActor
@Observable
final class DeveloperDayModel {
    private let services: AppServices

    private(set) var selected: DayKey
    private(set) var day: DeveloperDay
    /// Порція, яку додамо: хвилина доби й об'єм.
    var minute: Int
    var amountMl = 250

    /// Відсотки норми для «Заповнити заново»: 90 — межа зарахування частини доби (`GoalBlock.reachedMl`), 120 — стеля.
    static let fillPercents = [0, 50, 90, 100, 120]
    /// Об'єми, які кнопками не набрати: 314 — «Пі», 50 — «Наперсток».
    static let amountPresets = [50, 250, 314, 500, 1000, 2000]

    init(services: AppServices) {
        self.services = services
        let today = services.calendar.today
        selected = today
        day = services.developerDay(today)
        minute = services.calendar.minuteOfDay(services.calendar.now)
    }

    var epoch: Int { services.epoch }

    func reload() {
        // Зсунули годинник назад — вибраний день міг опинитись у майбутньому.
        if selected > services.calendar.today { selected = services.calendar.today }
        day = services.developerDay(selected)
    }

    // MARK: - День

    var title: String { DeveloperPresenter.day(selected) }
    var distance: String { DeveloperPresenter.dayDistance(selected, today: services.calendar.today) }
    var canGoForward: Bool { selected < services.calendar.today }

    /// Дата для системного вибору дня — північ вибраного.
    var selectedDate: Date {
        get { services.calendar.date(from: selected) }
        set { select(min(services.calendar.dayKey(for: newValue), services.calendar.today)) }
    }

    var dateRange: ClosedRange<Date> {
        services.calendar.date(from: services.calendar.dayKey(offsetDays: -365, from: services.calendar.today))
            ... services.calendar.now
    }

    func step(_ days: Int) {
        select(min(services.calendar.dayKey(offsetDays: days, from: selected), services.calendar.today))
    }

    /// Від сьогодні за годинником застосунку — зі зсувом.
    func jump(daysAgo: Int) {
        select(services.calendar.dayKey(offsetDays: -daysAgo, from: services.calendar.today))
    }

    func select(_ day: DayKey) {
        selected = day
        reload()
    }

    // MARK: - Показники

    var volumeLabel: String {
        DeveloperPresenter.volume(total: day.snapshot.totalMl, counted: day.snapshot.countedMl, goal: day.snapshot.goalMl)
    }

    var goalLabel: String { DeveloperPresenter.ml(day.snapshot.goalMl) }

    func stepGoal(up: Bool) {
        let goal = GoalRevision.clamp(day.snapshot.goalMl + (up ? 100 : -100))
        services.developerSetGoal(goal, day: selected)
        reload()
    }

    func fill(_ percent: Int) {
        services.developerFill(day: selected, percent: percent)
        reload()
    }

    func setFrozen(_ frozen: Bool) {
        services.developerSetFrozen(frozen, day: selected)
        reload()
    }

    // MARK: - Порція

    /// Час як `Date` вибраного дня — для системного вибору часу.
    var time: Date {
        get { services.calendar.date(selected, minute: minute) }
        set { minute = services.calendar.minuteOfDay(newValue) }
    }

    var timeLabel: String { services.profile.timeFormat.clock(minute) }
    var amountLabel: String { DeveloperPresenter.ml(amountMl) }

    /// Сьогодні — не пізніше за зараз.
    var canAdd: Bool { !day.isToday || minute <= services.calendar.minuteOfDay(services.calendar.now) }

    func stepAmount(up: Bool) {
        amountMl = Intake.clamp(amountMl + (up ? 50 : -50))
    }

    func addIntake() {
        guard canAdd else { return }
        services.developerAddIntake(ml: amountMl, day: selected, minute: minute)
        reload()
    }

    func remove(_ intake: IntakeSnapshot) {
        services.developerRemoveIntake(id: intake.id, day: selected)
        reload()
    }

    func intakeLabel(_ intake: IntakeSnapshot) -> String {
        "\(intake.timeLabel) · \(DeveloperPresenter.ml(intake.amountMl))"
    }
}
