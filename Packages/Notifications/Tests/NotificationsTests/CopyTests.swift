import XCTest
import Core
import Persistence
@testable import Notifications

/// Тексти — SPEC-NOTIFICATIONS §14 (критерій §19.14).
final class CopyCatalogTests: XCTestCase {
    /// Минулий час із родом про самого користувача — «пив / пила», «забув / забула». Рід
    /// іменника («організм не отримав», «пауза затяглася») — не про людину й дозволений.
    private let genderedPast = [
        "пив", "пила", "випив", "випила", "забув", "забула", "зробив", "зробила", "закрив", "закрила",
        "почав", "почала", "був", "була", "записав", "записала", "пропустив", "пропустила", "зірвав", "зірвала"
    ]

    /// Найгірші значення плейсхолдерів — найдовші рядки, які реально можуть з'явитися.
    private func worstCase(_ text: String) -> String {
        text.replacingOccurrences(of: "{left}", with: "1,95 л")
            .replacingOccurrences(of: "{glass}", with: "500 мл")
            .replacingOccurrences(of: "{streak}", with: Plural.days(365))
            .replacingOccurrences(of: "{since}", with: "11 год 55 хв")
            .replacingOccurrences(of: "{total}", with: "1,95 л")
    }

    private func words(_ text: String) -> [String] {
        text.lowercased().components(separatedBy: CharacterSet.letters.inverted).filter { !$0.isEmpty }
    }

    func testEveryVariantFitsTheLockScreen() {
        for variant in NotificationCopy.all {
            XCTAssertLessThanOrEqual(worstCase(variant.title).count, 30, variant.title)
            XCTAssertLessThanOrEqual(worstCase(variant.body).count, 100, variant.body)
        }
    }

    func testNoGenderedPastTenseAndNoFormalYou() {
        let inserts = [
            NotificationCopy.streakInsert(365), NotificationCopy.boostInsert(remaining: "11 год 55 хв"),
            NotificationCopy.questInsert(title: "Додати 4 записи"), NotificationCopy.weeklyInsert(xp: 100),
            NotificationCopy.bounceBackInsert(xp: 25), NotificationCopy.echoBody,
            NotificationCopy.echoComebackGift.title, NotificationCopy.echoComebackGift.body
        ]
        for text in NotificationCopy.all.flatMap({ [$0.title, $0.body] }) + inserts {
            let found = words(text)
            for word in genderedPast { XCTAssertFalse(found.contains(word), "«\(word)» у «\(text)»") }
            XCTAssertFalse(found.contains("ви") || found.contains("вам") || found.contains("ваш"), "«ви» у «\(text)»")
        }
    }

    /// Емодзі — щонайбільше одне, на початку заголовка (§14.1).
    func testTitleEmojiOnlyAtStart() {
        for variant in NotificationCopy.all {
            let emoji = variant.title.filter { $0.unicodeScalars.contains { $0.properties.isEmojiPresentation || $0.properties.generalCategory == .otherSymbol } }
            XCTAssertLessThanOrEqual(emoji.count, 1, variant.title)
            if let first = emoji.first { XCTAssertEqual(variant.title.first, first, variant.title) }
        }
    }

    func testVariantIdsAreUniquePerType() {
        let groups: [[CopyVariant]] = [
            NotificationCopy.reminderPrimary + NotificationCopy.reminderFollowUp,
            NotificationCopy.morning,
            NotificationCopy.eveningClosable + NotificationCopy.eveningStreak + NotificationCopy.eveningSoothing,
            NotificationCopy.rescueEvening + NotificationCopy.rescueMorning,
            NotificationCopy.comebackFirst + [NotificationCopy.comebackLastWithGift, NotificationCopy.comebackLast]
        ]
        for group in groups { XCTAssertEqual(Set(group.map(\.id)).count, group.count) }
    }

    /// Кожна вставка вміщується в будь-який текст, який вона може замінити (§14.3).
    func testInsertsKeepBodiesShort() {
        let inserts = [
            NotificationCopy.streakInsert(365), NotificationCopy.boostInsert(remaining: "11 год 55 хв"),
            NotificationCopy.questInsert(title: "Додати 4 записи"), NotificationCopy.weeklyInsert(xp: 100),
            NotificationCopy.bounceBackInsert(xp: 25)
        ]
        for insert in inserts { XCTAssertLessThanOrEqual(insert.count, 100, insert) }
    }

    func testFormats() {
        XCTAssertEqual(NotificationFormat.left(260), "300 мл", "вгору до 50 — щоб не недобрати")
        XCTAssertEqual(NotificationFormat.left(1010), "1,05 л")
        XCTAssertEqual(NotificationFormat.volume(1200), "1,2 л")
        XCTAssertEqual(NotificationFormat.volume(2000), "2 л")
        XCTAssertEqual(NotificationFormat.duration(minutes: 100), "1 год 40 хв")
        XCTAssertEqual(NotificationFormat.duration(minutes: 120), "2 год")
        XCTAssertEqual(NotificationFormat.duration(minutes: 45), "45 хв")
    }
}

/// Вибір варіанта, плейсхолдери й вставки контексту в готовому плані.
final class TextComposerTests: XCTestCase {
    private func plan(_ context: NotificationContext, _ preferences: NotificationPreferences = .default,
                      journal: NotificationJournal = .empty) -> NotificationPlan {
        NotificationPlanner.plan(context: context, preferences: preferences, journal: journal)
    }

    func testCompositionIsDeterministic() {
        let context = Fixture.context(at: Fixture.date(7))
        XCTAssertEqual(plan(context), plan(context))
    }

    /// Два останні використані варіанти типу підряд не повторюються (§14.1).
    func testRecentVariantsAreNotRepeated() {
        let day = DayKey(rawValue: "2026-10-01")
        for used in [[0, 1], [2, 3], [1, 3]] {
            let journal = NotificationJournal(entries: used.enumerated().map { index, variant in
                JournalEntry(identifier: "wt.reminder.2026-10-01.0\(index)", type: .reminder, slot: "primary",
                             dayKey: day, fireAt: Fixture.date(7, index), variant: variant)
            })
            let first = plan(Fixture.context(at: Fixture.date(7, 30)), journal: journal).items.first { $0.type == .reminder }!
            XCTAssertFalse(used.contains(first.variant), "використані \(used), вибрано \(first.variant)")
        }
    }

    /// `{since}` без порцій сьогодні не має сенсу — такий варіант не вибирається (рішення від 04.10.2026).
    func testSinceVariantNeedsAnIntake() {
        let travel = plan(Fixture.context(at: Fixture.date(7))).items.filter { $0.type == .reminder }
        XCTAssertTrue(travel.allSatisfy { !$0.body.contains("Від останньої порції") && !$0.body.contains("{") })
    }

    func testPlaceholdersAreFilled() {
        for item in plan(Fixture.context(at: Fixture.date(7))).items {
            XCTAssertFalse(item.title.contains("{") || item.body.contains("{"), "\(item.title) / \(item.body)")
        }
    }

    /// Серія ≥ 3 на кону — вставка в нагадування (§12.2).
    func testStreakAtStakeInsert() {
        var context = Fixture.context(at: Fixture.date(7))
        context.streak = StreakInput(countedYesterday: true, lengthEndingYesterday: 12)
        let reminder = plan(context).items.first { $0.type == .reminder }!
        XCTAssertTrue(reminder.body.contains("Серія 12 днів тримається на сьогоднішній нормі"), reminder.body)
        XCTAssertLessThanOrEqual(reminder.body.count, 100)
    }

    func testBoostInsert() {
        var context = Fixture.context(at: Fixture.date(7))
        context.boostExpiresAt = Fixture.date(day: 2, 0)
        let reminder = plan(context).items.first { $0.type == .reminder }!
        XCTAssertTrue(reminder.body.contains("⚡ Ще 14 год 18 хв подвійного XP"), reminder.body)
    }

    func testQuestInsertOnlyToday() {
        var context = Fixture.context(at: Fixture.date(7))
        context.quests.oneEntryLeftTitle = "Додати 4 записи"
        let reminders = plan(context).items.filter { $0.type == .reminder }
        XCTAssertTrue(reminders.filter { $0.dayKey.day == 1 }.allSatisfy { $0.body.contains("«Додати 4 записи»") })
        XCTAssertTrue(reminders.filter { $0.dayKey.day == 2 }.allSatisfy { !$0.body.contains("«Додати 4 записи»") })
    }

    /// «Знову в ритмі» — у ранковій склянці того дня, якщо немає ранкового порятунку (§12.5 Б).
    func testBounceBackInsertYieldsToRescue() {
        var context = Fixture.context(at: Fixture.date(7))
        context.streak = StreakInput(countedYesterday: false, countedDayBefore: true, lengthEndingDayBefore: 5)
        let morning = plan(context).items.first { $0.type == .morning && $0.dayKey.day == 1 }!
        XCTAssertTrue(morning.body.contains("+25 XP «Знову в ритмі»"), morning.body)
        XCTAssertFalse(morning.body.lowercased().contains("сері"), "обрив серії не згадується")

        context.readyFreezes = 1
        XCTAssertNil(plan(context).items.first { $0.type == .morning && $0.dayKey.day == 1 }, "замість неї — порятунок")

        context.readyFreezes = 0
        context.lastBounceBackDay = DayKey(rawValue: "2026-09-28")
        let cooled = plan(context).items.first { $0.type == .morning && $0.dayKey.day == 1 }!
        XCTAssertFalse(cooled.body.contains("Знову в ритмі"), "раз на 7 днів")
    }

    func testMorningQuestVariantOnlyWithActiveQuest() {
        for day in 1...28 {
            let context = Fixture.context(at: Fixture.date(day: day, 6))
            let morning = plan(context).items.first { $0.type == .morning }!
            XCTAssertNotEqual(morning.title, "Почнімо з води")
        }
    }
}

final class TypicalPortionTests: XCTestCase {
    func testMedianClampedAndRounded() {
        XCTAssertEqual(TypicalPortion.compute([], glassMl: 300), 300, "без історії — моя склянка")
        XCTAssertEqual(TypicalPortion.compute([250, 250, 1000], glassMl: 250), 250, "пляшка 1 л не зсуває медіану")
        XCTAssertEqual(TypicalPortion.compute([330, 340, 360], glassMl: 250), 350)
        XCTAssertEqual(TypicalPortion.compute([100, 120], glassMl: 250), 150)
        XCTAssertEqual(TypicalPortion.compute([800, 900], glassMl: 250), 500)
    }
}

final class PlannerPerformanceTests: XCTestCase {
    /// Планувальник має вкладатися в ≈ 2 мс (§16.3) — він іде після кожної дії.
    func testPlanIsFast() {
        var context = Fixture.context(at: Fixture.date(9), countedMl: 750,
                                      intakes: [Fixture.date(7), Fixture.date(8), Fixture.date(8, 50)])
        context.portionHistoryMl = Array(repeating: 250, count: 120)
        context.firstIntakeMinutes = Array(repeating: 450, count: 14)
        context.streak = StreakInput(countedYesterday: true, lengthEndingYesterday: 20)
        context.readyFreezes = 2
        let runs = 200
        let start = ProcessInfo.processInfo.systemUptime
        for _ in 0..<runs { _ = NotificationPlanner.plan(context: context, preferences: .default) }
        let average = (ProcessInfo.processInfo.systemUptime - start) / Double(runs)
        // У debug-збірці тестів ≈ 0,7 мс — межа ТЗ з потрійним запасом.
        XCTAssertLessThan(average, 0.002, "середнє \(average * 1000) мс")
    }
}
