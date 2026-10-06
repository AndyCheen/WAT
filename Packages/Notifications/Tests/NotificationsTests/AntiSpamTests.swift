import XCTest
import Core
import Persistence
@testable import Notifications

/// Анти-спам — §13: проміжок 30 хв, пріоритети, ліміт 8, бюджет 64, деградація при неактивності.
final class AntiSpamTests: XCTestCase {
    private func plan(_ context: NotificationContext, _ preferences: NotificationPreferences = .default,
                      journal: NotificationJournal = .empty, rules: NotificationRules = .default) -> NotificationPlan {
        NotificationPlanner.plan(context: context, preferences: preferences, journal: journal, rules: rules)
    }

    /// Між будь-якими двома — ≥ 30 хв, повторне — рівно +30 (критерій §19.5). Перевіряється
    /// на всьому доставленому за день у кількох сценаріях, разом із ранком і вечором.
    func testAnyTwoDeliveredAreAtLeastThirtyMinutesApart() {
        let scenarios: [[(date: Date, ml: Int)]] = [
            [],
            intakes([(8, 30, 250), (13, 0, 250), (15, 0, 300), (18, 30, 250)]),
            intakes([(9, 50, 200), (19, 10, 300)]),
            intakes([(7, 10, 300), (10, 0, 250), (11, 50, 250), (16, 40, 250)])
        ]
        var simulator = DaySimulator()
        for quiet in [[], [QuietWindow(fromMinutes: 10 * 60, toMinutes: 10 * 60 + 40)]] {
            simulator.preferences.quietWindows = quiet
            for scenario in scenarios {
                let delivered = simulator.run(intakes: scenario, from: Fixture.date(7), until: Fixture.date(23, 59))
                for (a, b) in zip(delivered, delivered.dropFirst()) {
                    XCTAssertGreaterThanOrEqual(b.fireAt.timeIntervalSince(a.fireAt), 30 * 60,
                                                "\(Fixture.clock(a.fireAt)) → \(Fixture.clock(b.fireAt))")
                }
                // «Ніколи раніше» за +30; тихий період може відсунути повторне пізніше. Основним
                // блоку може бути й чекпоінт, що забрав собі нагадування (§9).
                for follow in delivered where follow.slot == "followUp" {
                    let primary = delivered.last {
                        ($0.slot == "primary" || $0.type == .checkpoint) && $0.fireAt < follow.fireAt
                    }!
                    let gap = follow.fireAt.timeIntervalSince(primary.fireAt)
                    if quiet.isEmpty { XCTAssertEqual(gap, 30 * 60) } else { XCTAssertGreaterThanOrEqual(gap, 30 * 60) }
                }
            }
        }
    }

    /// Нагадування, що впало ближче ніж за 30 хв до сильнішого, зсувається на +30 від нього;
    /// повторне — скасовується (§13.3).
    func testWeakerPrimaryMovesBehindStronger() {
        var preferences = NotificationPreferences.default
        preferences.morningMinutes = 9 * 60 + 30  // ранкова склянка поряд із 09:37
        let result = plan(Fixture.context(at: Fixture.date(7)), preferences).items.filter { $0.dayKey.day == 1 }
        XCTAssertEqual(result.prefix(3).map { "\($0.type.key) \(Fixture.clock($0.fireAt))" },
                       ["morning 09:30", "reminder 10:00", "reminder 12:07"],
                       "основне 09:37 → 10:00, повторне 10:07 скасовано")
    }

    /// Уже показане сповіщення — теж перешкода: план не поставить нове ближче ніж за 30 хв.
    func testDeliveredNotificationsAreObstacles() {
        let journal = NotificationJournal(entries: [
            JournalEntry(identifier: "wt.morning.2026-10-01", type: .morning, slot: "morning",
                         dayKey: DayKey(rawValue: "2026-10-01"), fireAt: Fixture.date(9, 30))
        ])
        let first = plan(Fixture.context(at: Fixture.date(9, 31)), journal: journal).items.first { $0.type == .reminder }
        XCTAssertEqual(first.map { Fixture.clock($0.fireAt) }, "10:00")
    }

    /// ≤ 8 активних на день (критерій §19.13). Порятунок рахується в ліміт, але не скасовується
    /// ніколи: коли ліміт вичерпано, проходить лише він (§13.1).
    func testDailyCapCountsDeliveredAndLetsOnlyRescueThrough() {
        let day = DayKey(rawValue: "2026-10-01")
        func delivered(_ count: Int) -> NotificationJournal {
            NotificationJournal(entries: (0..<count).map { index in
                JournalEntry(identifier: "wt.reminder.2026-10-01.\(index)", type: .reminder, slot: "primary",
                             dayKey: day, fireAt: Fixture.date(7 + index))
            })
        }
        var context = Fixture.context(at: Fixture.date(14, 59), countedMl: 500, intakes: [Fixture.date(14, 58)])
        context.streak = StreakInput(countedYesterday: true, lengthEndingYesterday: 4)
        context.readyFreezes = 1

        let six = plan(context, journal: delivered(6)).items.filter { $0.dayKey == day }
        XCTAssertEqual(six.map(\.type), [.reminder, .rescue], "6 показано + основне + порятунок = 8")

        let eight = plan(context, journal: delivered(8)).items.filter { $0.dayKey == day }
        XCTAssertEqual(eight.map(\.type), [.rescue], "ліміт вичерпано — проходить лише порятунок")
    }

    /// iOS тримає ≤ 64 запланованих (§16.2): план не виходить за бюджет із запасом під відлуння.
    func testPlanNeverExceedsPendingBudget() {
        var rules = NotificationRules.default
        XCTAssertLessThanOrEqual(plan(Fixture.context(at: Fixture.date(0, 5))).items.count, rules.maxPending - rules.echoReserve)
        rules.maxPending = 7
        XCTAssertEqual(plan(Fixture.context(at: Fixture.date(0, 5)), rules: rules).items.count, 3)
        let times = plan(Fixture.context(at: Fixture.date(0, 5)), rules: rules).items.map(\.fireAt)
        XCTAssertEqual(times, times.sorted(), "лишаються найближчі")
    }

    func testNothingOutsideActiveHours() {
        var preferences = NotificationPreferences.default
        preferences.weekday = DaySchedule(wakeMinutes: 7 * 60, sleepMinutes: 21 * 60)
        for item in plan(Fixture.context(at: Fixture.date(0, 5)), preferences).items {
            let hour = Calendar.kyiv.component(.hour, from: item.fireAt)
            XCTAssertTrue((7..<21).contains(hour), "\(item.id) о \(Fixture.clock(item.fireAt))")
        }
    }

    // MARK: - Деградація при неактивності (§13.5, критерій §19.15)

    private func summary(_ plan: NotificationPlan) -> [String] {
        plan.items.map { "\($0.dayKey.day): \($0.type.key)" }.reduce(into: [String]()) { result, line in
            if result.last != line { result.append(line) }
        }
    }

    func testInactivityShrinksThePlan() {
        let last = Fixture.date(10)
        var context = Fixture.context(at: last, countedMl: 250, intakes: [last])
        context.lastInteractionAt = last
        let lines = summary(plan(context))
        XCTAssertEqual(lines, [
            "1: reminder",                                   // сьогодні — повний набір
            "1: evening",
            "2: morning", "2: reminder",                     // +1 — повний набір (вечора без порцій немає, §8 п. 5)
            "3: morning",                                    // +2 — лише ранкова склянка
            "4: comeback",                                   // +3 — повернення №1
            "8: comeback"                                    // +7 — останнє; далі тиша
        ])
    }

    /// Фонове оновлення на 2-й день без дій: план рахується від дня останньої дії, а не від сьогодні.
    func testPlanCountsFromLastActionDay() {
        var context = Fixture.context(at: Fixture.date(day: 3, 6))
        context.lastIntakeAt = Fixture.date(day: 1, 10)
        let lines = summary(plan(context))
        XCTAssertEqual(lines, ["3: morning", "4: comeback", "8: comeback"])
    }

    func testComebackComesAtUsualFirstIntakeTime() {
        var context = Fixture.context(at: Fixture.date(day: 3, 6))
        context.lastIntakeAt = Fixture.date(day: 1, 10)
        context.firstIntakeMinutes = [600, 610, 650]
        let comeback = plan(context).items.first { $0.type == .comeback }!
        XCTAssertEqual(Fixture.clock(comeback.fireAt), "10:10")
        XCTAssertEqual(comeback.category, .glass, "дія «+склянка»")
    }

    /// Текст 7-го дня згадує подарунок, лише коли той доступний (критерій §19.16).
    func testLastComebackMentionsGiftOnlyWhenAvailable() {
        var context = Fixture.context(at: Fixture.date(day: 3, 6))
        context.lastIntakeAt = Fixture.date(day: 1, 10)
        let last = { (context: NotificationContext) in
            self.plan(context).items.first { $0.id == "wt.comeback.2026-10-08.2" }!.body
        }
        XCTAssertTrue(last(context).contains("подвійний XP"))

        context.lastComebackGiftAt = Fixture.date(day: 20, 10, month: 9)
        XCTAssertFalse(last(context).contains("подвійний XP"), "подарунок був 18 днів тому — частота §12.5")
    }

    func testComebackCanBeTurnedOff() {
        var preferences = NotificationPreferences.default
        preferences.comebackEnabled = false
        var context = Fixture.context(at: Fixture.date(day: 3, 6))
        context.lastIntakeAt = Fixture.date(day: 1, 10)
        XCTAssertTrue(plan(context, preferences).items.allSatisfy { $0.type != .comeback })
    }
}

extension Calendar {
    static var kyiv: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = Fixture.kyiv
        return calendar
    }
}
