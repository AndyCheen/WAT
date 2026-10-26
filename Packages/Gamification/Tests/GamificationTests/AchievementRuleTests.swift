import XCTest
import Core
import Metrics
import Persistence
@testable import Gamification

/// Правила каталогу досягнень (SPEC-ACHIEVEMENTS-CATALOG §4, §6). Дні — справжні записи дня з порціями,
/// як у `HydrationService`: правила рахуються з історії, а не з подій.
@MainActor
final class AchievementRuleTests: XCTestCase {

    // MARK: - Вода (§4.1)

    /// Обʼєм — лише зарахований: понад 120 % норми драбина не росте (принцип 1).
    func testVolumeCountsOnlyCappedWater() {
        let env = GameEnv()
        env.drink(2000, on: "2026-07-18", hour: 9)
        env.drink(1000, on: "2026-07-18", hour: 10)
        XCTAssertEqual(env.progressValue("volume.10l"), 2400, "3000 мл випито, 2400 — зараховано")
    }

    // MARK: - Регулярність (§4.3)

    /// «Ніколи двічі»: одиночні пропуски рахунку не обнуляють.
    func testNeverTwiceForgivesSingleMisses() {
        let env = GameEnv()
        env.clock.set(GameEnv.date("2026-08-01", hour: 20))
        for (index, day) in env.days(from: "2026-06-17", to: "2026-07-31").enumerated() where index % 3 != 2 {
            env.goalDay(day)
        }
        XCTAssertTrue(env.isUnlocked("days.neverTwice"), "45 днів (WAT-67), пропуски — по одному")
    }

    /// Два пропуски поспіль — рахунок з нуля; сьогодні без норми ще не пропуск.
    func testNeverTwiceRestartsAfterTwoMissesInARow() {
        let env = GameEnv()
        env.clock.set(GameEnv.date("2026-08-01", hour: 20))
        for day in env.days(from: "2026-07-02", to: "2026-07-31") where !["2026-07-15", "2026-07-16"].contains(day) {
            env.goalDay(day)
        }
        XCTAssertFalse(env.isUnlocked("days.neverTwice"))
        XCTAssertEqual(env.progressValue("days.neverTwice"), 15, "02–15 — 14 днів, із 16-го з нуля: 17–31 — 15")
    }

    /// Заморожений день — не пропуск: два «пропуски» поспіль, з яких один заморожений, ланцюг не рвуть.
    func testNeverTwiceTreatsFrozenDayAsNotMissed() {
        let env = GameEnv()
        env.clock.set(GameEnv.date("2026-08-01", hour: 20))
        env.store.streakState().frozenDayKeys = ["2026-07-16"]
        for day in env.days(from: "2026-06-17", to: "2026-07-31") where !["2026-07-15", "2026-07-16"].contains(day) {
            env.goalDay(day)
        }
        XCTAssertTrue(env.isUnlocked("days.neverTwice"))
    }

    /// «Без провалів»: 28 днів поспіль від 80 % норми.
    func testNoDipsNeedsEightyPercentEveryDay() {
        let env = GameEnv()
        env.clock.set(GameEnv.date("2026-08-01", hour: 20))
        for day in env.days(from: "2026-07-03", to: "2026-07-30") { env.drink(1600, on: day) }
        XCTAssertTrue(env.isUnlocked("days.noDips"))
    }

    /// 79 % рве ланцюг; заморожений день тримає його, але не додає — як у серії.
    func testNoDipsBreaksBelowEightyAndFreezeOnlyHolds() {
        let env = GameEnv()
        env.clock.set(GameEnv.date("2026-08-01", hour: 20))
        for day in env.days(from: "2026-07-03", to: "2026-07-30") {
            env.drink(day == "2026-07-16" ? 1580 : 1600, on: day)
        }
        XCTAssertFalse(env.isUnlocked("days.noDips"))
        XCTAssertEqual(env.progressValue("days.noDips"), 14, "після провалу 16-го: 17–30")

        env.store.streakState().frozenDayKeys = ["2026-07-16"]
        env.game.refresh(at: env.clock.now)
        XCTAssertEqual(env.progressValue("days.noDips"), 27, "заморожений день тримає, але не додає")
        XCTAssertFalse(env.isUnlocked("days.noDips"))
    }

    func testNoZerosNeedsAPortionEveryDay() {
        let env = GameEnv()
        env.clock.set(GameEnv.date("2026-08-01", hour: 20))
        for day in env.days(from: "2026-07-02", to: "2026-07-31") { env.drink(200, on: day) }
        XCTAssertTrue(env.isUnlocked("days.noZero"))
        XCTAssertFalse(env.isUnlocked("goal.days5"), "порція — не норма")
    }

    /// «Стабільний місяць» — чотири тижні з понеділка, у кожному 5+ днів із нормою. Поточний тиждень,
    /// що ще не набрав п'яти, ланцюг не рве.
    func testStableMonthCountsCalendarWeeks() {
        let env = GameEnv()
        env.clock.set(GameEnv.date("2026-08-04", hour: 9))
        for day in env.days(from: "2026-07-06", to: "2026-08-02")
        where DayKey.weekdayIndex(ordinal: DayKey(rawValue: day).ordinal) < 5 {
            env.goalDay(day)
        }
        XCTAssertTrue(env.isUnlocked("weeks.stable4"))
        XCTAssertEqual(env.progressValue("weeks.stable13"), 4)
    }

    // MARK: - Серії й повернення (§4.2)

    /// «Знову в ритмі» — норма наступного дня після обриву серії ≥ 3; утретє — таємне «Вода камінь точить».
    func testBounceBackAndItsThirdTime() {
        let env = GameEnv()
        env.clock.set(GameEnv.date("2026-08-01", hour: 20))
        // Тричі: три дні норми, пропуск, норма.
        for start in [1, 6, 11] {
            for offset in [0, 1, 2, 4] {
                env.goalDay(String(format: "2026-07-%02d", start + offset))
            }
            if start == 1 { XCTAssertTrue(env.isUnlocked("comeback.bounce")) }
        }
        XCTAssertTrue(env.isUnlocked("comeback.third"))
    }

    /// Пропуск двох днів — уже не «наступного дня».
    func testBounceBackNeedsTheVeryNextDay() {
        let env = GameEnv()
        env.clock.set(GameEnv.date("2026-08-01", hour: 20))
        for day in ["2026-07-01", "2026-07-02", "2026-07-03", "2026-07-06"] { env.goalDay(day) }
        XCTAssertFalse(env.isUnlocked("comeback.bounce"))
    }

    func testSecondWaveNeedsANewSevenAfterABrokenSeven() {
        let env = GameEnv()
        env.clock.set(GameEnv.date("2026-08-01", hour: 20))
        for day in env.days(from: "2026-07-01", to: "2026-07-07") { env.goalDay(day) }
        for day in env.days(from: "2026-07-09", to: "2026-07-14") { env.goalDay(day) }
        XCTAssertEqual(env.progressValue("comeback.wave"), 6)
        env.goalDay("2026-07-15")
        XCTAssertTrue(env.isUnlocked("comeback.wave"))
        XCTAssertTrue(env.isUnlocked("record.streak") == false, "сім не довше за сім")
    }

    func testRecordBeatenNeedsALongerSeriesThanBefore() {
        let env = GameEnv()
        env.clock.set(GameEnv.date("2026-08-01", hour: 20))
        for day in env.days(from: "2026-07-01", to: "2026-07-03") { env.goalDay(day) }
        for day in env.days(from: "2026-07-05", to: "2026-07-10") { env.goalDay(day) }
        XCTAssertFalse(env.isUnlocked("record.streak"), "6 довше за 3, але менше за 7")
        env.goalDay("2026-07-11")
        XCTAssertTrue(env.isUnlocked("record.streak"))
    }

    /// «Знову тут» — 3 дні норми після перерви 7+ днів без порцій.
    func testBackAfterABreak() {
        let env = GameEnv()
        env.clock.set(GameEnv.date("2026-08-01", hour: 20))
        env.goalDay("2026-07-01")
        for day in ["2026-07-10", "2026-07-11"] { env.goalDay(day) }
        XCTAssertFalse(env.isUnlocked("comeback.again"))
        env.goalDay("2026-07-12")
        XCTAssertTrue(env.isUnlocked("comeback.again"))
    }

    /// Пасхалка «Багато води утекло» — перша порція після 30+ днів без води.
    func testLongBreakEggAppearsOnlyWhenFound() {
        let env = GameEnv()
        env.clock.set(GameEnv.date("2026-08-03", hour: 20))
        env.drink(200, on: "2026-07-01")
        env.drink(200, on: "2026-07-31")
        XCTAssertNil(env.achievement("egg.longTime"), "29 днів перерви — ще не знайдено, і в знімку її немає")
        env.drink(200, on: "2026-08-02")
        XCTAssertNil(env.achievement("egg.longTime"))

        let other = GameEnv()
        other.clock.set(GameEnv.date("2026-08-03", hour: 20))
        other.drink(200, on: "2026-07-01")
        other.drink(200, on: "2026-08-01")
        XCTAssertEqual(other.achievement("egg.longTime")?.isUnlocked, true, "30 днів без порцій між ними")
    }

    // MARK: - Ритм дня (§4.4)

    /// Один ранок випадає випадково — потрібно 12 (WAT-60, WAT-67); «Ранок, день і вечір» — 10: з допуском блоку такі
    /// дні в того, хто п'є рівно, звичайні (WAT-67).
    func testMorningGoalAndAllThreeBlocks() {
        let env = GameEnv()
        env.clock.set(GameEnv.date("2026-08-01", hour: 23))
        let days = env.days(from: "2026-07-18", to: "2026-07-29")
        for day in days.dropLast() { env.drink(1000, on: day, hour: 9) }
        XCTAssertFalse(env.isUnlocked("rhythm.morning"))
        XCTAssertEqual(env.achievement("rhythm.morning")?.value, 11)
        env.drink(1000, on: days[11], hour: 9)
        XCTAssertTrue(env.isUnlocked("rhythm.morning"))

        for (index, day) in days.prefix(10).enumerated() {
            XCTAssertFalse(env.isUnlocked("rhythm.allThree"), "\(index) з 10")
            env.drink(1000, on: day, hour: 14)
            env.drink(1000, on: day, hour: 19)
        }
        XCTAssertTrue(env.isUnlocked("rhythm.allThree"))
    }

    /// Вимкнений «Ритм дня»: замкнене з підписом, не рахується; відкрите раніше не забирається (§4.4).
    func testDayRhythmGateLocksWithCaptionAndKeepsUnlocked() {
        let env = GameEnv()
        env.clock.set(GameEnv.date("2026-08-01", hour: 23))
        env.profiles.profile().dayRhythmEnabled = false
        for day in env.days(from: "2026-07-18", to: "2026-07-29") { env.drink(1000, on: day, hour: 9) }
        XCTAssertFalse(env.isUnlocked("rhythm.morning"))
        let locked = env.achievement("rhythm.morning")
        XCTAssertEqual(locked?.lockedCaption, "Увімкни «Ритм дня» в налаштуваннях")
        XCTAssertEqual(locked?.value, 0, "підпис замість прогресу")
        XCTAssertNil(env.achievement("rhythm.even90")?.lockedCaption, "«Рівномірність» від перемикача не залежить")

        env.profiles.profile().dayRhythmEnabled = true
        env.drink(200, on: "2026-07-30", hour: 10)
        XCTAssertTrue(env.isUnlocked("rhythm.morning"), "увімкнули — рахується з наступної дії")

        env.profiles.profile().dayRhythmEnabled = false
        XCTAssertTrue(env.isUnlocked("rhythm.morning"))
        XCTAssertNil(env.achievement("rhythm.morning")?.lockedCaption)
    }

    /// Вимкнені сповіщення: «Чуйність» і «Вчасно» не рахуються, підпис «Увімкни сповіщення».
    func testNotificationsGate() {
        let env = GameEnv()
        env.game.notificationsAuthorized = { false }
        env.metrics.record(MetricEvent(name: .streakRescued, value: 1, occurredAt: env.clock.now, sourceRef: UUID()))
        XCTAssertFalse(env.isUnlocked("comeback.rescue"))
        XCTAssertEqual(env.achievement("comeback.rescue")?.lockedCaption, "Увімкни сповіщення")

        env.game.notificationsAuthorized = { true }
        env.drink(200, on: "2026-07-18", hour: 10)
        XCTAssertTrue(env.isUnlocked("comeback.rescue"))
    }

    func testResponsiveCountsQuickResponses() {
        let env = GameEnv()
        for _ in 0..<29 {
            env.metrics.record(MetricEvent(name: .reminderQuick, value: 1, occurredAt: env.clock.now, sourceRef: UUID()))
        }
        XCTAssertFalse(env.isUnlocked("rhythm.responsive"))
        env.metrics.record(MetricEvent(name: .reminderQuick, value: 1, occurredAt: env.clock.now, sourceRef: UUID()))
        XCTAssertTrue(env.isUnlocked("rhythm.responsive"))
    }

    func testWakeGlassAndQuietEvening() {
        let env = GameEnv()
        env.clock.set(GameEnv.date("2026-08-01", hour: 23))
        // Пороги — 15 і 25 днів (WAT-67).
        for day in env.days(from: "2026-07-05", to: "2026-07-29") {
            env.drink(250, on: day, hour: 8, minute: 20)
            env.drink(1750, on: day, hour: 19, minute: 30)
        }
        XCTAssertTrue(env.isUnlocked("rhythm.wakeGlass"), "перша склянка за 20 хв після підйому о 08:00")
        XCTAssertTrue(env.isUnlocked("rhythm.quietEvening"), "норма о 19:30 — за 2,5 год до відбою о 22:00")
    }

    /// «Рівна крива» — 18 завершених днів від 90 (WAT-60, WAT-67), «Ідеальна» — найкращий день; сьогоднішній ще може
    /// змінитись. Лише будні: у вихідні інший розклад, і та сама крива вже не ідеальна.
    func testEvennessCountsFinishedDays() {
        let env = GameEnv()
        env.clock.set(GameEnv.date("2026-07-21", hour: 23))
        let shares = DaySchedule.weekdayDefault.curve(goalMl: 2000).partShares()
        let hours: [DayPart: Int] = [.morning: 8, .noon: 10, .afternoon: 14, .evening: 19]
        let weekdays = Array(env.days(from: "2026-06-01", to: "2026-07-21")
            .filter { DayKey(rawValue: $0).weekdayIndex < 5 }.suffix(18))
        for day in weekdays {
            for (part, hour) in hours where shares[part.rawValue] > 0 {
                env.drink(Int((2000 * shares[part.rawValue]).rounded()), on: day, hour: hour, minute: 30)
            }
        }
        XCTAssertFalse(env.isUnlocked("rhythm.even90"), "17 завершених — сьогоднішній ще триває")
        XCTAssertTrue(env.isUnlocked("rhythm.even97"))

        env.clock.set(GameEnv.date("2026-07-22", hour: 9))
        env.drink(200, on: "2026-07-22", hour: 9)
        XCTAssertTrue(env.isUnlocked("rhythm.even90"))
    }

    // MARK: - Статистика (§4.5)

    func testAccuracyAndBullseyeLookAtFinishedDays() {
        let env = GameEnv()
        env.clock.set(GameEnv.date("2026-07-25", hour: 23))
        let accurate = env.days(from: "2026-06-25", to: "2026-07-19")
        for day in accurate.dropLast() { env.drink(2050, on: day) }
        XCTAssertFalse(env.isUnlocked("stats.accuracy"), "24 дні з 25 (WAT-67)")
        env.drink(2050, on: accurate[24])
        XCTAssertTrue(env.isUnlocked("stats.accuracy"))

        env.drink(2000, on: "2026-07-22")
        env.drink(2000, on: "2026-07-23")
        env.drink(2000, on: "2026-07-25")
        XCTAssertFalse(env.isUnlocked("stats.bullseye"), "рівно норма сьогодні — день ще не закінчився")
        XCTAssertEqual(env.achievement("stats.bullseye")?.title, "???")

        env.clock.set(GameEnv.date("2026-07-26", hour: 9))
        env.drink(100, on: "2026-07-26", hour: 9)
        XCTAssertTrue(env.isUnlocked("stats.bullseye"))
        XCTAssertEqual(env.achievement("stats.bullseye")?.title, "В яблучко")
    }

    func testMonthsCountCalendarMonths() {
        let env = GameEnv()
        env.clock.set(GameEnv.date("2026-08-01", hour: 9))
        for day in env.days(from: "2026-07-01", to: "2026-07-30") { env.goalDay(day) }
        XCTAssertTrue(env.isUnlocked("stats.greenMonth"))
        XCTAssertFalse(env.isUnlocked("stats.perfectMonth"))
        env.goalDay("2026-07-31")
        XCTAssertTrue(env.isUnlocked("stats.perfectMonth"))
    }

    // MARK: - Календар і фанові (§4.8)

    func testWeekendsAndSeasons() {
        let env = GameEnv()
        env.clock.set(GameEnv.date("2026-09-01", hour: 9))
        // 11–12 липня 2026 — субота й неділя; далі ще три вихідні поспіль.
        for saturday in ["2026-07-11", "2026-07-18", "2026-07-25", "2026-08-01"] {
            let ordinal = DayKey(rawValue: saturday).ordinal
            XCTAssertEqual(DayKey.weekdayIndex(ordinal: ordinal), 5, saturday)
            env.goalDay(saturday)
            env.goalDay(DayKey(ordinal: ordinal + 1).rawValue)
            if saturday == "2026-07-11" { XCTAssertTrue(env.isUnlocked("special.weekend")) }
        }
        XCTAssertTrue(env.isUnlocked("special.weekendMonth"))

        for day in env.days(from: "2026-06-01", to: "2026-06-22") { env.goalDay(day) }
        XCTAssertTrue(env.isUnlocked("special.summer"), "червень–серпень: 22 + 8")
    }

    /// Зима — грудень одного року й січень–лютий наступного: один сезон.
    func testWinterSpansTheNewYear() {
        let env = GameEnv()
        env.clock.set(GameEnv.date("2026-03-01", hour: 9))
        for day in env.days(from: "2025-12-17", to: "2026-01-15") { env.goalDay(day) }
        XCTAssertTrue(env.isUnlocked("special.winter"))
    }

    func testDatesAndSkyEvents() {
        let env = GameEnv()
        env.clock.set(GameEnv.date("2028-12-31", hour: 9))
        env.goalDay("2026-07-20")
        XCTAssertFalse(env.isUnlocked("special.fullMoon"), "20 липня 2026 — не повня")
        env.drink(200, on: "2026-07-29")
        XCTAssertFalse(env.isUnlocked("special.fullMoon"), "порція в повню — ще не норма (WAT-60)")
        env.goalDay("2026-07-29")
        XCTAssertTrue(env.isUnlocked("special.fullMoon"), "повня 29 липня 2026, 17:37 за Києвом")

        env.goalDay("2026-06-21")
        XCTAssertTrue(env.isUnlocked("special.longestDay"))
        env.goalDay("2026-12-21")
        XCTAssertTrue(env.isUnlocked("special.shortestDay"))

        env.drink(200, on: "2027-01-01")
        XCTAssertTrue(env.isUnlocked("special.newYear"))
        env.goalDay("2027-03-22")
        XCTAssertTrue(env.isUnlocked("special.waterDay"))
        env.drink(200, on: "2028-02-29")
        XCTAssertTrue(env.isUnlocked("special.leap"))

        env.drink(200, on: "2026-11-13")
        XCTAssertEqual(env.achievement("egg.friday13")?.isUnlocked, true, "13 листопада 2026 — п'ятниця")
        env.drink(200, on: "2027-04-01")
        XCTAssertEqual(env.achievement("egg.aprilFools")?.isUnlocked, true)
        XCTAssertFalse(env.isUnlocked("special.anniversary"), "перша порція — 21 червня, а 2027-06-21 порції немає")
    }

    func testAnniversaryNeedsAPortionOnTheSameDate() {
        let env = GameEnv()
        env.clock.set(GameEnv.date("2027-08-01", hour: 9))
        env.drink(200, on: "2026-07-20")
        env.drink(200, on: "2027-07-19")
        XCTAssertFalse(env.isUnlocked("special.anniversary"))
        env.drink(200, on: "2027-07-20")
        XCTAssertTrue(env.isUnlocked("special.anniversary"))
    }

    func testPortionsOfTheDay() {
        let env = GameEnv()
        env.clock.set(GameEnv.date("2026-07-20", hour: 23))
        env.drink(50, on: "2026-07-20", hour: 7)
        XCTAssertTrue(env.isUnlocked("special.thimble"))
        env.drink(300, on: "2026-07-20", hour: 11, minute: 11)
        XCTAssertEqual(env.achievement("egg.wish")?.isUnlocked, true)
        env.drink(300, on: "2026-07-20", hour: 12)
        XCTAssertTrue(env.isUnlocked("special.noon"))
        env.drink(314, on: "2026-07-20", hour: 13)
        XCTAssertEqual(env.achievement("egg.pi")?.isUnlocked, true)
        XCTAssertFalse(env.isUnlocked("special.halfFull"), "до 12:00 — 350 мл")
        for hour in 14...17 { env.drink(250, on: "2026-07-20", hour: hour) }
        XCTAssertEqual(env.progressValue("special.eightGlasses"), 1, "8 порцій — перший день із восьми")
    }

    /// «Вісім на вісім» — 8 днів по 8 порцій (WAT-60): один такий день дрібнить воду випадково.
    func testEightByEight() {
        let env = GameEnv()
        env.clock.set(GameEnv.date("2026-08-01", hour: 23))
        let days = env.days(from: "2026-07-20", to: "2026-07-27")
        for day in days {
            XCTAssertFalse(env.isUnlocked("special.eightGlasses"), day)
            for hour in 9...16 { env.drink(250, on: day, hour: hour) }
        }
        XCTAssertTrue(env.isUnlocked("special.eightGlasses"))

        let seven = GameEnv()
        seven.clock.set(GameEnv.date("2026-08-01", hour: 23))
        for day in days { for hour in 9...15 { seven.drink(250, on: day, hour: hour) } }
        XCTAssertEqual(seven.progressValue("special.eightGlasses"), 0, "по 7 порцій — жодного дня")
    }

    func testHalfGoalBeforeNoon() {
        let env = GameEnv()
        env.clock.set(GameEnv.date("2026-08-01", hour: 23))
        let days = env.days(from: "2026-07-20", to: "2026-07-24")
        for day in days {
            XCTAssertFalse(env.isUnlocked("special.halfFull"), day)
            env.drink(600, on: day, hour: 8)
            env.drink(400, on: day, hour: 11, minute: 59)
        }
        XCTAssertTrue(env.isUnlocked("special.halfFull"), "5 днів")
    }

    /// Паліндром і «Як дві краплі води» — лише завершені дні: доливання не має їх зіпсувати.
    func testMirrorAndTwinsUseFinishedDays() {
        let env = GameEnv()
        env.clock.set(GameEnv.date("2026-07-21", hour: 23))
        env.drink(2112, on: "2026-07-20")
        env.drink(2112, on: "2026-07-21")
        XCTAssertTrue(env.isUnlocked("special.mirror"), "20-те завершене: 2112")
        XCTAssertFalse(env.isUnlocked("special.twins"), "21-ше ще триває")

        env.clock.set(GameEnv.date("2026-07-22", hour: 9))
        env.drink(200, on: "2026-07-22", hour: 9)
        XCTAssertTrue(env.isUnlocked("special.twins"))
    }

    /// «Нерішучість»: тричі додати й скасувати за хвилину.
    func testIndecisionNeedsThreeCancelsWithinAMinute() {
        let env = GameEnv()
        let start = GameEnv.date("2026-07-18", hour: 10)
        for index in 0..<3 {
            let id = env.drink(250, on: "2026-07-18", hour: 10, minute: 0)
            env.undo(id, at: start.addingTimeInterval(Double(index) * 15 + 5))
        }
        XCTAssertTrue(env.isUnlocked("special.indecision"))

        let slow = GameEnv()
        for minute in [0, 1, 2] {
            let id = slow.drink(250, on: "2026-07-18", hour: 10, minute: minute)
            slow.undo(id, at: GameEnv.date("2026-07-18", hour: 10, minute: minute).addingTimeInterval(10))
        }
        XCTAssertFalse(slow.isUnlocked("special.indecision"))
        XCTAssertNil(slow.achievement("discover.undo"), "«Друга думка» знято (WAT-60): виправлену помилку не святкуємо")
    }

    func testOtherTimeZoneComparesOffsetsNotNames() {
        let env = GameEnv()
        env.drink(200, on: "2026-07-17", timeZoneId: "Europe/Kyiv")
        env.drink(200, on: "2026-07-18", timeZoneId: "Europe/Kiev")
        XCTAssertFalse(env.isUnlocked("special.borderless"), "Kiev і Kyiv — один пояс")
        env.drink(200, on: "2026-07-19", timeZoneId: "America/New_York")
        XCTAssertTrue(env.isUnlocked("special.borderless"))
    }

    // MARK: - Відкриття (§4.7)

    func testIntakeSourcesOpenTheirDiscoveries() {
        let env = GameEnv()
        env.drink(200, on: "2026-07-18", hour: 9, source: .app)
        env.drink(200, on: "2026-07-18", hour: 10, source: .widget)
        XCTAssertTrue(env.isUnlocked("discover.widget"))
        env.drink(200, on: "2026-07-18", hour: 11, source: .siri)
        XCTAssertTrue(env.isUnlocked("discover.voice"))
        XCTAssertEqual(env.progressValue("discover.allPaths"), 3)
        env.drink(200, on: "2026-07-18", hour: 12, source: .notification)
        XCTAssertTrue(env.isUnlocked("discover.notificationGlass"))
        XCTAssertTrue(env.isUnlocked("discover.allPaths"))
    }

    // MARK: - Гра (§4.6)

    func testLevelMilestonesAndQuests() {
        let env = GameEnv(quests: nil)
        env.reachLevel(5)
        env.game.refresh(at: env.clock.now)
        XCTAssertNil(env.achievement("level.5"), "«Струмок» знято (WAT-60): у рівня своє свято")
        env.reachLevel(10)
        env.game.refresh(at: env.clock.now)
        XCTAssertTrue(env.isUnlocked("level.10"))

        for hour in [9, 11, 13, 15] { env.drink(500, on: "2026-07-18", hour: hour) }
        XCTAssertFalse(env.isUnlocked("quest.first"), "щоденні завдання «Тижневої мети» не дають (WAT-60)")
        XCTAssertEqual(env.progressValue("quest.allDaily"), 1, "«Перша склянка» й «Половина норми» — обидві стартові, день 1 з 10")
    }

    /// «Тижнева мета» — перше тижневе завдання. У перший тиждень людини воно одне — «Норма 3 дні» (SPEC-QUESTS §5.2).
    func testWeeklyGoalOpensWithTheFirstWeeklyQuest() {
        let env = GameEnv(quests: nil)
        let week = env.days(from: "2026-07-13", to: "2026-07-15")
        for day in week.dropLast() { env.goalDay(day) }
        XCTAssertFalse(env.isUnlocked("quest.first"))
        XCTAssertEqual(env.metrics.events(.weeklyQuestCompleted).count, 0)
        XCTAssertEqual(env.store.quests(scope: .weekly, periodKey: "2026-W29").map(\.defKey), ["weekly.goalDays"])

        env.goalDay(week[2])
        XCTAssertTrue(env.isUnlocked("quest.first"))
        XCTAssertEqual(env.achievement("quest.first")?.title, "Тижнева мета")
        XCTAssertEqual(env.metrics.events(.weeklyQuestCompleted).count, 1)
    }

    /// «Без хвостів» — 15 днів, коли виконано всі щоденні завдання (WAT-60, WAT-67).
    func testNoTailsNeedsFifteenDays() {
        // Те саме щоденне щодня: тест про лік днів, а не про вибір пікера.
        let env = GameEnv(quests: QuestForcing(daily: ["starter.firstGoal"]))
        env.clock.set(GameEnv.date("2026-07-30", hour: 23))
        let days = env.days(from: "2026-07-15", to: "2026-07-29")
        for day in days {
            XCTAssertFalse(env.isUnlocked("quest.allDaily"), day)
            env.clock.set(GameEnv.date(day, hour: 16))
            for hour in [9, 11, 13, 15] { env.drink(500, on: day, hour: hour) }
        }
        XCTAssertTrue(env.isUnlocked("quest.allDaily"))
        XCTAssertEqual(env.achievement("quest.allDaily")?.title, "Без хвостів")
    }

    func testBoostAndGoalOnTheSameDay() {
        let env = GameEnv()
        let boost = env.game.grantPrize(key: RewardCatalog.boostKey, source: .seed)!
        XCTAssertTrue(env.game.activateBoost(prizeId: boost.id))
        XCTAssertFalse(env.isUnlocked("boost.goal"))
        env.goalDay("2026-07-18", hour: 15)
        XCTAssertTrue(env.isUnlocked("boost.goal"))
    }

    /// «Порятунок»: заморозка вчорашнього пропуску врятувала серію 7.
    func testFreezeThatSavedASevenDaySeries() {
        let env = GameEnv()
        for day in env.days(from: "2026-07-10", to: "2026-07-16") { env.goalDay(day) }
        let freeze = env.game.grantPrize(key: RewardCatalog.freezeKey, source: .seed)!
        XCTAssertTrue(env.game.useFreeze(prizeId: freeze.id))
        XCTAssertTrue(env.isUnlocked("freeze.saved"))
    }

    func testMysteryAndChoiceOnTheLevelRoad() {
        let env = GameEnv()
        let mystery = (2...80).first { if case .mystery? = LevelRoadCatalog.node(forLevel: $0) { return true }; return false }!
        let choice = (2...80).first { if case .choice? = LevelRoadCatalog.node(forLevel: $0) { return true }; return false }!
        env.reachLevel(max(mystery, choice))

        let grants = env.game.openMystery(level: mystery)!
        XCTAssertEqual(env.progressValue("mystery.5"), 1, "«Перша скриня» знято (WAT-60), рахує «Пошук скарбів»")
        XCTAssertEqual(env.progressValue("mystery.triple") == 1, grants.contains { $0.key == RewardCatalog.tripleKey })

        guard case .choice(let options)? = LevelRoadCatalog.node(forLevel: choice) else { return XCTFail() }
        XCTAssertTrue(env.game.claimChoice(level: choice, key: options[0].key))
        XCTAssertNil(env.achievement("discover.levelChoice"), "«Перехрестя» знято (WAT-60)")
    }

    /// Колекції бачать відкрите в тому самому проході; «Усе зібрано» знімається разом з останнім.
    func testCollectionsFollowTheRestInOnePass() {
        let env = GameEnv()
        let core = AchievementCatalog.all.filter { $0.isCore && $0.key != "collection.all" && $0.key != "first.drop" }
        for definition in core where !definition.rule.isCollection {
            env.store.achievementProgress(defKey: definition.key)?.unlockedAt = env.clock.now
        }
        let id = env.drink(200, on: "2026-07-18", hour: 9)
        XCTAssertTrue(env.isUnlocked("first.drop"))
        XCTAssertTrue(env.isUnlocked("collection.50"))
        XCTAssertTrue(env.isUnlocked("collection.all"), "увесь основний каталог")

        env.undo(id, at: env.clock.now)
        XCTAssertFalse(env.isUnlocked("first.drop"))
        XCTAssertFalse(env.isUnlocked("collection.all"), "без «Першої краплі» каталог не зібрано")
    }

    /// «Дискотека»: п'ять змін теми за хвилину.
    func testDiscoNeedsFiveThemeChangesInAMinute() {
        let env = GameEnv()
        for second in stride(from: 0, to: 150, by: 30) {
            env.metrics.record(MetricEvent(name: .themeChanged, occurredAt: env.clock.now.addingTimeInterval(Double(second))))
        }
        XCTAssertNil(env.achievement("egg.disco"), "п'ять змін за дві хвилини")
        for second in 0..<5 {
            env.metrics.record(MetricEvent(name: .themeChanged, occurredAt: env.clock.now.addingTimeInterval(300 + Double(second))))
        }
        XCTAssertEqual(env.achievement("egg.disco")?.isUnlocked, true)
    }

    // MARK: - Таємні й пасхалки (§4.9, §4.10)

    /// Закрите таємне — «???», підказка й 🤫, без прогресу й останнім у списку; відкрите — звичайне.
    func testHintSecretIsMaskedUntilUnlocked() {
        let env = GameEnv()
        let masked = env.achievement("special.thimble")!
        XCTAssertEqual(masked.title, "???")
        XCTAssertEqual(masked.details, "«Іноді досить і ковточка»")
        XCTAssertEqual(masked.emoji, "🤫")
        XCTAssertTrue(masked.isMasked)
        XCTAssertEqual(masked.state, .locked)
        XCTAssertEqual(env.game.achievementSnapshots().sortedForDisplay.last?.isMasked, true, "закриті таємні — останні")

        env.drink(50, on: "2026-07-18", hour: 9)
        let open = env.achievement("special.thimble")!
        XCTAssertEqual(open.title, "Наперсток")
        XCTAssertEqual(open.details, "Порція 50 мл")
        XCTAssertFalse(open.isMasked)
    }

    /// Пасхалки до знахідки немає ні в знімку, ні в лічильнику; після — «🥚 N» окремо від «N / 102».
    func testEggsAreInvisibleUntilFoundAndCountedApart() {
        let env = GameEnv()
        let before = env.game.achievementSnapshots()
        XCTAssertFalse(before.contains { $0.key.hasPrefix("egg.") })
        XCTAssertEqual(before.tally.total, 102)
        XCTAssertEqual(before.tally.eggs, 0)

        env.drink(314, on: "2026-07-18", hour: 9)
        env.clock.advance(by: 60)
        env.drink(200, on: "2026-07-18", hour: 11, minute: 11)
        let after = env.game.achievementSnapshots()
        XCTAssertEqual(after.tally.total, 102, "знайдена пасхалка лічильник не роздуває")
        XCTAssertEqual(after.tally.eggs, 2)
        XCTAssertEqual(after.first { $0.key == "egg.pi" }?.note, "Пасхалка! Тут їх більше", "лише в першої знайденої")
        XCTAssertNil(after.first { $0.key == "egg.wish" }?.note)
        XCTAssertEqual(after.first { $0.key == "egg.pi" }?.category, .water, "знайдена — у своїй категорії")
    }

    // MARK: - Відкат і історія (§6)

    func testUndoRelocksAndMasksAgain() {
        let env = GameEnv()
        env.drink(200, on: "2026-07-18", hour: 9)
        let id = env.drink(50, on: "2026-07-18", hour: 10)
        XCTAssertTrue(env.isUnlocked("special.thimble"))
        env.undo(id, at: env.clock.now)
        XCTAssertFalse(env.isUnlocked("special.thimble"))
        XCTAssertEqual(env.achievement("special.thimble")?.title, "???")
    }

    /// Після оновлення досягнення відкриваються заднім числом з історії — без тоста (§6).
    func testHistoryBackfillsOnRefreshWithoutAToast() {
        let env = GameEnv()
        env.clock.set(GameEnv.date("2026-08-01", hour: 9))
        for day in env.days(from: "2026-07-01", to: "2026-07-10") {
            let log = env.dayLogs.dayLog(for: DayKey(rawValue: day), goalMl: 2000, timeZoneId: "Europe/Kyiv")
            log.totalMl = 2000
            log.countedMl = 2000
            log.entriesCount = 4
        }
        env.dayLogs.save()
        _ = env.game.takeRecentUnlocks()

        env.game.refresh(at: env.clock.now)
        XCTAssertTrue(env.isUnlocked("goal.days5"))
        XCTAssertTrue(env.isUnlocked("volume.10l"))
        XCTAssertTrue(env.game.takeRecentUnlocks().achievements.isEmpty, "заднім числом — не заслуга жодної дії")
    }
}
