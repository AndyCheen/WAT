import Foundation
import Core
import Persistence
import Hydration
import Gamification
import Notifications

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
        SaveBatch.run(container.mainContext) { refill(day, percent: percent) }
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
    public func developerCloseDays(_ count: Int, progress: (Double) -> Void = { _ in }) async {
        let today = calendar.today
        let days = stride(from: count, through: 1, by: -1).map { calendar.dayKey(offsetDays: -$0, from: today) }
        await runSteps(days.map { day in
            { [unowned self] in if !hydration.snapshot(for: day).goalMet { refill(day, percent: 100) } }
        }, progress: progress)
        finishDeveloperAction(changedPast: true)
    }

    /// Демо-історія 60 днів (`FixtureSeeder`) — та сама, що в `--seed-demo`.
    public func developerSeedDemo(progress: (Double) -> Void = { _ in }) async {
        await runSteps(FixtureSeeder.steps(into: self, days: 60), progress: progress)
        epoch &+= 1
    }

    /// Масова дія кроками: крок — один пакет збережень (`SaveBatch`), між кроками — кадр. Одним шматком 60 днів
    /// трималися б на головному потоці кілька секунд, і застосунок виглядав завислим.
    private func runSteps(_ steps: [() -> Void], progress: (Double) -> Void) async {
        for (index, step) in steps.enumerated() {
            SaveBatch.run(container.mainContext, step)
            progress(Double(index + 1) / Double(steps.count))
            // Саме пауза, а не `Task.yield()`: кадр малюється між проходами циклу подій, а не між задачами актора.
            try? await Task.sleep(for: .milliseconds(10))
        }
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

    /// Рівень з режиму розробника не святкується, а відсвятковане — від нього: наступне справжнє підняття, хоч би й на
    /// вже бачений рівень, отримає тост чи рядок у вікні.
    public func developerSetLevel(_ level: Int) {
        gamification.developerSetLevel(level)
        settleCelebratedLevel()
        finishDeveloperAction()
    }

    public func developerAlmostNextLevel() {
        gamification.developerAlmostNextLevel()
        settleCelebratedLevel()
        finishDeveloperAction()
    }

    private func settleCelebratedLevel() {
        profile.highestCelebratedLevel = gamification.levelProgress().level
        profiles.save()
    }

    public func developerStopBoost() {
        gamification.developerStopBoost()
        finishDeveloperAction()
    }

    // MARK: - Сповіщення

    /// Справжнє сповіщення-зразок за `seconds` (`NotificationService.scheduleSample`). `nil` — без дозволу iOS сповіщення
    /// не прийде, і планувати нічого.
    @discardableResult
    public func developerSendNotification(_ sample: NotificationSample, after seconds: TimeInterval) async -> String? {
        await notifications.refreshAuthorization()
        guard notifications.authorization == .authorized else { return nil }
        return await notifications.scheduleSample(sample, after: seconds)
    }

    /// Відлуння — одразу, як після порції поза застосунком (§12.1): про останнє відкрите досягнення, а без нього — про
    /// «Першу краплю».
    @discardableResult
    public func developerSendEcho() async -> String? {
        await notifications.refreshAuthorization()
        guard notifications.authorization == .authorized else { return nil }
        let unlocked = gamification.achievementSnapshots().filter(\.isUnlocked)
            .max { ($0.unlockedAt ?? .distantPast) < ($1.unlockedAt ?? .distantPast) }
        let text = EchoText.achievement(unlocked?.title ?? "Перша крапля")
        await notifications.sendEcho(title: text.title, body: text.body,
                                     route: unlocked.map { .achievement(key: $0.key) } ?? .progress,
                                     intakeId: UUID(), at: calendar.now)
        return text.title
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
