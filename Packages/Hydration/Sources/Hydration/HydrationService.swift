import Foundation
import Core
import Persistence
import Metrics

/// Облік випитого: додавання й видалення порцій, перерахунок дня, публікація метрик.
///
/// Сервіс нічого не знає про XP, завдання чи досягнення — вони підписані на `MetricsService`.
@MainActor
public final class HydrationService {
    private let dayLogs: DayLogRepositoryProtocol
    private let profiles: ProfileRepositoryProtocol
    private let metrics: MetricsService
    private let calendar: CalendarService

    public init(
        dayLogs: DayLogRepositoryProtocol,
        profiles: ProfileRepositoryProtocol,
        metrics: MetricsService,
        calendar: CalendarService
    ) {
        self.dayLogs = dayLogs
        self.profiles = profiles
        self.metrics = metrics
        self.calendar = calendar
    }

    // MARK: - Читання

    public func snapshot(for day: DayKey) -> DaySnapshot {
        let goal = profiles.currentGoalMl(on: day)
        guard let log = dayLogs.existingDayLog(for: day) else {
            return .empty(dayKey: day, goalMl: goal)
        }
        return Self.snapshot(from: log)
    }

    public func todaySnapshot() -> DaySnapshot { snapshot(for: calendar.today) }

    public func intakes(for day: DayKey) -> [IntakeSnapshot] {
        dayLogs.activeIntakes(for: day).map { intake in
            IntakeSnapshot(
                id: intake.id,
                amountMl: intake.amountMl,
                createdAt: intake.createdAt,
                timeLabel: Self.timeFormatter(calendar).string(from: intake.createdAt)
            )
        }
    }

    // MARK: - Додавання

    /// Додає порцію в поточну добу. «Заднім числом» додавати не можна (ТЗ §4.1).
    @discardableResult
    public func addIntake(amountMl: Int, source: IntakeSource = .app, at date: Date? = nil) -> IntakeResult? {
        let now = date ?? calendar.now
        guard Intake.isValid(amountMl) else {
            AppLog.hydration.error("Недопустимий обʼєм порції: \(amountMl)")
            return nil
        }

        let day = calendar.dayKey(for: now)
        let goal = profiles.currentGoalMl(on: day)
        let log = dayLogs.dayLog(for: day, goalMl: goal, timeZoneId: calendar.calendar.timeZone.identifier)
        // Норму могли змінити протягом дня — поточний день підлаштовується (ТЗ §14).
        log.goalMlSnapshot = goal

        let wasGoalMet = log.goalMet
        let intake = Intake(amountMl: amountMl, createdAt: now, source: source)
        dayLogs.insert(intake, into: log)
        recompute(log)
        dayLogs.save()

        publishIntakeMetrics(intake: intake, at: now)
        let goalJustReached = !wasGoalMet && log.goalMet
        if goalJustReached {
            publishGoalMet(day: day, at: now, pct: log.completionPct)
        }
        metrics.commit()

        return IntakeResult(
            intakeId: intake.id,
            day: Self.snapshot(from: log),
            goalJustReached: goalJustReached,
            cappedAmountMl: log.isCapped ? log.totalMl - log.capMl : 0
        )
    }

    // MARK: - Видалення (undo)

    /// Мʼяке видалення порції з повним відкотом усіх похідних метрик.
    @discardableResult
    public func removeIntake(id: UUID, at date: Date? = nil) -> DaySnapshot? {
        let now = date ?? calendar.now
        guard let intake = dayLogs.intake(id: id), !intake.isDeleted, let log = intake.dayLog else { return nil }

        intake.deletedAt = now
        recompute(log)
        dayLogs.save()

        metrics.revert(sourceRef: intake.id, at: now)
        metrics.record(
            MetricEvent(name: .intakeRemoved, value: Double(intake.amountMl), occurredAt: now)
        )

        // Якщо після видалення норма дня більше не виконана — знімаємо і подію «ціль дня».
        let day = DayKey(rawValue: log.dayKey)
        if !log.goalMet {
            metrics.revert(sourceRef: Self.goalMetRef(day), at: now)
        }
        metrics.commit()

        return Self.snapshot(from: log)
    }

    // MARK: - Норма

    public func currentGoal(on day: DayKey? = nil) -> Int {
        profiles.currentGoalMl(on: day ?? calendar.today)
    }

    /// Встановлює нову норму з поточного дня і підлаштовує сьогоднішній день.
    @discardableResult
    public func setGoal(_ ml: Int, source: GoalSource = .manual, at date: Date? = nil) -> DaySnapshot {
        let now = date ?? calendar.now
        let day = calendar.dayKey(for: now)
        profiles.setGoal(ml, source: source, effectiveFrom: day, at: now)

        let goal = profiles.currentGoalMl(on: day)
        if let log = dayLogs.existingDayLog(for: day) {
            log.goalMlSnapshot = goal
            recompute(log)
            dayLogs.save()
            return Self.snapshot(from: log)
        }
        return .empty(dayKey: day, goalMl: goal)
    }

    public func calculateGoal(inputs: GoalInputs, formula: GoalFormula = GoalFormulaRegistry.current) -> Int {
        formula.dailyGoalMl(for: inputs, currentYear: calendar.calendar.component(.year, from: calendar.now))
    }

    // MARK: - Пресети

    public func quickAddAmounts() -> [Int] {
        profiles.quickAddPresets().filter(\.enabled).sorted { $0.order < $1.order }.map(\.amountMl)
    }

    // MARK: - Внутрішнє

    /// Перерахунок денного агрегату з активних порцій. Єдине місце, де живе стеля 120 %.
    private func recompute(_ log: DayLog) {
        let active = (log.intakes ?? []).filter { !$0.isDeleted }
        let total = active.reduce(0) { $0 + $1.amountMl }

        var parts = [0, 0, 0, 0, 0]
        for intake in active {
            let part = DayPart.from(hour: calendar.hour(of: intake.createdAt))
            parts[part.rawValue] += intake.amountMl
        }

        log.totalMl = total
        log.countedMl = min(total, log.capMl)
        log.entriesCount = active.count
        log.partTotals = parts
        log.firstIntakeAt = active.map(\.createdAt).min()
        log.lastIntakeAt = active.map(\.createdAt).max()
    }

    private func publishIntakeMetrics(intake: Intake, at date: Date) {
        let part = DayPart.from(hour: calendar.hour(of: date))
        metrics.record(MetricEvent(
            name: .intakeAdded, value: Double(intake.amountMl), occurredAt: date,
            sourceRef: intake.id, payload: ["source": String(intake.sourceRaw)]
        ))
        metrics.record(MetricEvent(
            name: .intakeCount, value: 1, occurredAt: date, sourceRef: intake.id
        ))
        metrics.record(MetricEvent(
            name: .part(part.rawValue), value: Double(intake.amountMl), occurredAt: date, sourceRef: intake.id
        ))
    }

    private func publishGoalMet(day: DayKey, at date: Date, pct: Int) {
        metrics.record(MetricEvent(
            name: .dayGoalMet, value: 1, occurredAt: date,
            sourceRef: Self.goalMetRef(day), payload: ["pct": String(pct)]
        ))
    }

    /// Детермінований ключ події «норма дня виконана» — одна на добу, з можливістю відкату.
    static func goalMetRef(_ day: DayKey) -> UUID {
        DeterministicID.uuid(from: "day.goalMet:\(day.rawValue)")
    }

    static func snapshot(from log: DayLog) -> DaySnapshot {
        DaySnapshot(
            dayKey: DayKey(rawValue: log.dayKey),
            goalMl: log.goalMlSnapshot,
            totalMl: log.totalMl,
            countedMl: log.countedMl,
            entriesCount: log.entriesCount,
            partTotals: log.partTotals,
            isCapped: log.isCapped
        )
    }

    private static func timeFormatter(_ calendar: CalendarService) -> DateFormatter {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        f.timeZone = calendar.calendar.timeZone
        f.locale = Locale(identifier: "uk_UA")
        return f
    }
}
