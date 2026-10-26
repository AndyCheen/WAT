import Foundation
import Core
import Persistence
import Hydration
import Gamification

/// День у режимі розробника: показники запису дня й порції.
public struct DeveloperDay: Equatable {
    public let day: DayKey
    public let snapshot: DaySnapshot
    public let intakes: [IntakeSnapshot]
    public let isFrozen: Bool
    public let isToday: Bool
}

/// Режим розробника (WAT-68): дії з даними для тестування. Кожна йде тим самим шляхом, що й дія людини — порція через
/// `HydrationService`, приз через `GamificationService`, — і закінчується так само: `touch()` (сповіщення й віджети),
/// `epoch` (екрани перечитують себе) і вікно відкриття, якщо щось відкрилось.
extension AppServices {
    // MARK: - Дні

    public func developerDay(_ day: DayKey) -> DeveloperDay {
        DeveloperDay(day: day, snapshot: hydration.snapshot(for: day), intakes: hydration.intakes(for: day),
                     isFrozen: gamification.isFrozen(day), isToday: day == calendar.today)
    }

    /// Порція в будь-яку хвилину минулого дня чи сьогодні — не пізніше, ніж зараз: порцій з майбутнього не буває.
    @discardableResult
    public func developerAddIntake(ml: Int, day: DayKey, minute: Int) -> Bool {
        let date = calendar.date(day, minute: minute)
        guard date <= calendar.now, hydration.addIntake(amountMl: ml, source: .app, at: date) != nil else { return false }
        finishDeveloperAction(changedPast: day != calendar.today)
        return true
    }

    public func developerRemoveIntake(id: UUID, day: DayKey) {
        hydration.removeIntake(id: id)
        finishDeveloperAction(changedPast: day != calendar.today)
    }

    /// Порції дня заново — `percent` від норми дня, рівно по активних годинах (`DayFill`). 0 — очистити день.
    public func developerFill(day: DayKey, percent: Int) {
        refill(day, percent: percent)
        finishDeveloperAction(changedPast: day != calendar.today)
    }

    public func developerSetGoal(_ ml: Int, day: DayKey) {
        hydration.setGoal(ml, on: day)
        finishDeveloperAction(changedPast: day != calendar.today)
    }

    public func developerSetFrozen(_ frozen: Bool, day: DayKey) {
        gamification.developerSetFrozen(frozen, day: day)
        finishDeveloperAction()
    }

    /// Серія: `count` днів до сьогодні з закритою нормою. Уже закриті не чіпаються.
    public func developerCloseDays(_ count: Int) {
        for offset in stride(from: count, through: 1, by: -1) {
            let day = calendar.dayKey(offsetDays: -offset, from: calendar.today)
            if !hydration.snapshot(for: day).goalMet { refill(day, percent: 100) }
        }
        finishDeveloperAction(changedPast: true)
    }

    /// Демо-історія 60 днів (`FixtureSeeder`) — та сама, що в `--seed-demo`.
    public func developerSeedDemo() {
        FixtureSeeder.seed(into: self)
        epoch &+= 1
    }

    private func refill(_ day: DayKey, percent: Int) {
        for intake in hydration.intakes(for: day) { hydration.removeIntake(id: intake.id) }
        let goal = hydration.snapshot(for: day).goalMl
        let until = day == calendar.today ? calendar.minuteOfDay(calendar.now) : nil
        for portion in DayFill.portions(totalMl: goal * percent / 100, schedule: hydration.schedule(for: day),
                                        untilMinute: until) {
            hydration.addIntake(amountMl: portion.ml, source: .app, at: calendar.date(day, minute: portion.minute))
        }
    }

    // MARK: - Гра

    public func developerUnlock(achievement key: String) {
        gamification.developerUnlock(achievement: key)
        finishDeveloperAction()
    }

    public func developerRelock(achievement key: String) {
        gamification.developerRelock(achievement: key)
        finishDeveloperAction()
    }

    @discardableResult
    public func developerIssueQuest(key: String, delayMinutes: Int = 0) -> Bool {
        let issued = gamification.developerIssueQuest(key: key, delayMinutes: delayMinutes)
        finishDeveloperAction()
        return issued
    }

    public func developerComplete(quest id: UUID) {
        gamification.developerComplete(quest: id)
        finishDeveloperAction()
    }

    public func developerCancel(quest id: UUID) {
        gamification.developerCancel(quest: id)
        finishDeveloperAction()
    }

    public func developerGrantPrize(key: String) {
        gamification.grantPrize(key: key, source: .seed)
        finishDeveloperAction()
    }

    public func developerAwardXp(_ amount: Int) {
        gamification.developerAwardXp(amount)
        finishDeveloperAction()
    }

    public func developerLevelUp() {
        gamification.developerLevelUp()
        finishDeveloperAction()
    }

    public func developerStopBoost() {
        gamification.developerStopBoost()
        finishDeveloperAction()
    }

    // MARK: - Годинник

    /// `nil` — годинник не зсувається: фіксований (`--uitest-now`) чи збірка без режиму розробника.
    public var developerClock: OffsetClock? { clock as? OffsetClock }

    /// Як переведений системний час: нова доба, перепланування, екрани перечитують себе (`handleTimeChange`).
    public func developerShiftClock(by seconds: TimeInterval) {
        guard let clock = developerClock else { return }
        clock.offset += seconds
        DeveloperSettings.clockOffset = clock.offset
        handleTimeChange()
    }

    public func developerResetClock() {
        guard let clock = developerClock, clock.offset != 0 else { return }
        clock.offset = 0
        DeveloperSettings.clockOffset = 0
        handleTimeChange()
    }

    // MARK: - Внутрішнє

    /// Порції минулого дня оцінено кожна у свою мить, а серія, «завершені дні» й завдання сьогодні — від них: повний
    /// перерахунок, як після демо-історії (`FixtureSeeder`).
    private func finishDeveloperAction(changedPast: Bool = false) {
        if changedPast {
            gamification.refresh(at: calendar.now)
            metrics.commit()
        }
        touch()
        epoch &+= 1
        presentCelebrations(context: .action)
    }
}
