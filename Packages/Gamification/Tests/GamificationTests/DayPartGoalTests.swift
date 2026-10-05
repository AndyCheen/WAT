import XCTest
import Core
import Persistence
@testable import Gamification

/// XP `dayPartGoal` — SPEC-NOTIFICATIONS §9: +10 XP, коли порції всередині частини доби набрали
/// її ціль за кривою темпу. При 08:00–22:00 ціль «до 12:00» — 689 мл.
@MainActor
final class DayPartGoalTests: XCTestCase {
    private func activeAwards(_ env: GameEnv) -> [XPEntry] {
        env.store.xpEntries(reason: .dayPartGoal).filter { $0.revertedAt == nil }
    }

    func testAwardsOnceWhenBlockReachesTarget() {
        let env = GameEnv()
        env.addIntake(250, hour: 8, minute: 30)
        env.addIntake(250, hour: 10)
        XCTAssertTrue(activeAwards(env).isEmpty, "500 із 689 — ще ні")

        env.addIntake(200, hour: 11, minute: 30)
        XCTAssertEqual(activeAwards(env).map(\.amount), [XPRules.default.perDayPartGoal])

        env.addIntake(300, hour: 11, minute: 45)
        XCTAssertEqual(activeAwards(env).count, 1, "той самий блок удруге не нараховується")
    }

    /// Порції з різних частин доби одну ціль не закривають.
    func testPortionsOutsideBlockDoNotCount() {
        let env = GameEnv()
        env.addIntake(400, hour: 11)
        env.addIntake(500, hour: 12, minute: 30)  // уже наступний блок
        XCTAssertTrue(activeAwards(env).isEmpty)
    }

    /// Склянка о 06:30 при підйомі о 08:00 зараховується ранку (WAT-39): разом із порціями до
    /// 12:00 закриває «до 12:00».
    func testPortionBeforeWakeCountsToFirstBlock() {
        let env = GameEnv()
        env.addIntake(250, hour: 6, minute: 30)
        env.addIntake(200, hour: 9)
        XCTAssertTrue(activeAwards(env).isEmpty, "450 із 689 — ще ні")
        env.addIntake(250, hour: 11)
        XCTAssertEqual(activeAwards(env).count, 1)
    }

    /// Порція до підйому сама може закрити ранок — XP нараховується в її момент.
    func testEarlyPortionAloneClosesFirstBlock() {
        let env = GameEnv()
        env.addIntake(700, hour: 7)
        XCTAssertEqual(activeAwards(env).count, 1)
    }

    /// Пізня склянка після відбою добирає вечір.
    func testPortionAfterSleepCountsToLastBlock() {
        let env = GameEnv(hour: 23)
        env.addIntake(300, hour: 18)
        env.addIntake(300, hour: 22, minute: 30)
        XCTAssertEqual(activeAwards(env).count, 1, "600 ≥ 485 — вечір закрито")
    }

    /// Розклад дня — зі знімка в записі дня: підйом, змінений після, межі вже оціненого дня не
    /// пересуває. При 08:00 «до 12:00» — 689 мл; при 06:00 полудень 09–12 мав би ціль 484, і
    /// без знімка видалення порції 11:00 лишило б XP.
    func testScheduleSnapshotKeepsPastDayBlocks() {
        let env = GameEnv()
        env.addIntake(500, hour: 9, day: 17)
        let closing = env.addIntake(200, hour: 11, day: 17)
        XCTAssertEqual(activeAwards(env).count, 1)

        env.profiles.profile().wakeMinutes = 6 * 60
        env.profiles.save()

        env.removeIntake(closing)
        XCTAssertTrue(activeAwards(env).isEmpty, "500 < 689 за розкладом того дня")
    }

    func testUndoRevertsAndRestoreAwardsAgain() {
        let env = GameEnv()
        env.addIntake(400, hour: 9)
        let closing = env.addIntake(300, hour: 11)
        XCTAssertEqual(activeAwards(env).count, 1)

        env.removeIntake(closing)
        XCTAssertTrue(activeAwards(env).isEmpty, "без порції 11:00 блок нижче цілі")

        env.restoreIntake(closing)
        XCTAssertEqual(activeAwards(env).count, 1)
    }

    /// Видалення порції, без якої ціль усе одно закрита, XP не знімає.
    func testUndoKeepsAwardWhenTargetStillReached() {
        let env = GameEnv()
        env.addIntake(700, hour: 9)
        let extra = env.addIntake(250, hour: 10)
        env.removeIntake(extra)
        XCTAssertEqual(activeAwards(env).count, 1)
    }

    /// 18 липня 2026 — субота: з окремим розкладом вихідних (10:00–23:00) ціль «до 12:00» — 419 мл.
    func testWeekendScheduleChangesTarget() {
        let env = GameEnv()
        let profile = env.profiles.profile()
        profile.weekendScheduleEnabled = true
        profile.weekendWakeMinutes = 10 * 60
        profile.weekendSleepMinutes = 23 * 60
        env.profiles.save()

        env.addIntake(420, hour: 11)
        XCTAssertEqual(activeAwards(env).count, 1)
    }

    // MARK: - Режим «просто норма» (WAT-42, §28)

    private func setDayRhythm(_ enabled: Bool, _ env: GameEnv) {
        env.profiles.profile().dayRhythmEnabled = enabled
        env.profiles.save()
    }

    /// Без ритму дня закрита частина XP не дає, а порція й норма — як завжди.
    func testPlainModeAwardsNoDayPartXp() {
        let env = GameEnv()
        setDayRhythm(false, env)
        env.addIntake(700, hour: 9)
        env.addIntake(700, hour: 14)
        env.addIntake(700, hour: 19)
        XCTAssertTrue(env.store.xpEntries(reason: .dayPartGoal).isEmpty)
        XCTAssertEqual(env.store.xpEntries(reason: .intake).count, 3)
    }

    /// Вимкнення не забирає вже нараховане, а увімкнення назад нараховує з наступної порції —
    /// за весь блок, разом із порціями, випитими без ритму.
    func testTogglingKeepsEarnedAndResumesFromNextPortion() {
        let env = GameEnv()
        env.addIntake(700, hour: 9)
        XCTAssertEqual(activeAwards(env).count, 1)

        setDayRhythm(false, env)
        XCTAssertEqual(activeAwards(env).count, 1, "вимкнення XP не відкочує")
        env.addIntake(500, hour: 13)
        env.addIntake(350, hour: 15)
        XCTAssertEqual(activeAwards(env).count, 1, "850 ≥ 826, але режим вимкнено")

        setDayRhythm(true, env)
        env.addIntake(100, hour: 16)
        XCTAssertEqual(activeAwards(env).count, 2, "наступна порція в блоці 12–17 закриває його")
    }

    /// Завдання на частину доби — у пулі лише з ритмом дня.
    func testDayPartQuestsAreMarked() {
        XCTAssertEqual(QuestCatalog.all.filter(\.isDayPartQuest).map(\.key), ["daily.morning"])
        let env = GameEnv()
        setDayRhythm(false, env)
        env.addIntake(250, hour: 9)
        XCTAssertFalse(env.game.dailyQuests().contains { $0.key == "daily.morning" })
        XCTAssertEqual(env.game.dailyQuests().count, QuestCatalog.dailySlots)
    }
}
