import Foundation
import Core

/// Тексти віджетів — чиста функція «стан доби → рядки» (SPEC-WIDGETS §8). На «ти», без родового минулого
/// часу; об'єм — у тих самих форматах, що на головному, щоб віджет і застосунок казали те саме.
///
/// Система людини (WAT-46, WAT-58) — зі знімка: функції з `WidgetDay` беруть її з доби, решта — параметром.
/// У мілілітрах і 24 годинах тексти — байт-у-байт як до WAT-58.
public enum WidgetPresenter {
    // MARK: - Об'єм

    /// «1.25 / 2.0 л» — підпис кільця, як `HomeViewModel.volumeLabel`; в унціях — «42 / 68 унц.».
    public static func ringVolume(countedMl: Int, goalMl: Int, unit: VolumeUnit = .milliliters) -> String {
        guard unit.isMetric else { return "\(unit.units(countedMl)) / \(unit.units(goalMl)) \(VolumeUnit.ounceSymbol)" }
        return "\(Volume.litersLabel(countedMl)) / \(Volume.litersLabel(goalMl, fractionDigits: 1)) л"
    }

    /// «1.25» — велике число без одиниць; «1» замість «1.00». В унціях — ціле число унцій.
    public static func liters(_ ml: Int, unit: VolumeUnit = .milliliters) -> String {
        guard unit.isMetric else { return "\(unit.units(ml))" }
        var text = Volume.litersLabel(ml)
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return text
    }

    /// Позначення поруч із великим числом з `liters`: «л» / «унц.».
    public static func bigUnit(_ unit: VolumeUnit) -> String { unit.isMetric ? "л" : VolumeUnit.ounceSymbol }

    /// Підпис кнопки порції — як `HomeScreen.amountTitle`: «250 мл», «1 л», «1.05 л», «8 унц.».
    public static func amount(_ ml: Int, unit: VolumeUnit = .milliliters) -> String { unit.label(ml) }

    /// «+250 мл» — кнопка, що одразу додає порцію.
    public static func addTitle(_ ml: Int, unit: VolumeUnit = .milliliters) -> String { "+\(amount(ml, unit: unit))" }

    /// «ще 750 мл» — вгору до 50, як у капсули й сповіщень: краще трохи більше, ніж недобрати. В унціях —
    /// вгору до цілої, як `DayPartPresenter`.
    public static func left(_ ml: Int, unit: VolumeUnit = .milliliters) -> String { "ще \(roundedUp(ml, unit))" }

    // MARK: - Завдання (віджет «Прогрес», SPEC-QUESTS §9.3)

    /// Права половина «Прогресу»: до двох невиконаних щоденних і одне тижневе. Виконані тут не показуються —
    /// місця три рядки, а підсумок дня й так на головному.
    public struct Quests: Equatable, Sendable {
        public enum Today: Equatable, Sendable {
            case rows([WidgetSnapshot.Quest])
            /// «✓ Усе на сьогодні».
            case allDone
            /// Щоденних немає або вони зникли за дедлайном — без рядка й без підпису, як на головному.
            case hidden
        }

        public enum Week: Equatable, Sendable {
            case row(WidgetSnapshot.Quest)
            /// «✓ Тиждень закрито».
            case closed
            /// «З понеділка».
            case fromMonday
            case hidden
        }

        /// Несподіване з живим таймером — першим рядком; тоді щоденних лише один.
        public let surprise: WidgetSnapshot.Surprise?
        public let today: Today
        public let week: Week
    }

    public static let questsTodayCaption = "Сьогодні"
    public static let questsWeekCaption = "Цього тижня"
    public static let questsAllDone = "✓ Усе на сьогодні"
    public static let questsWeekClosed = "✓ Тиждень закрито"
    public static let questsFromMonday = "З понеділка"
    public static let dailyQuestRows = 2

    /// Стан на хвилину запису: дедлайн міг минути вже після знімка.
    public static func quests(_ snapshot: WidgetSnapshot, at date: Date) -> Quests {
        let daily = snapshot.dailyQuests.filter { $0.isVisible(at: date) }
        let expired = (snapshot.expiredDailyQuests ?? 0) + snapshot.dailyQuests.count - daily.count
        let open = daily.filter { !$0.isDone }
        let surprise = snapshot.surprise.flatMap { $0.isOpen(at: date) ? $0 : nil }
        let today: Quests.Today
        if !open.isEmpty {
            today = .rows(Array(open.prefix(surprise == nil ? dailyQuestRows : dailyQuestRows - 1)))
        } else if !daily.isEmpty, expired == 0 {
            today = .allDone
        } else {
            today = .hidden
        }

        let week: Quests.Week
        if let weekly = snapshot.weeklyQuests.first(where: { !$0.isDone }) {
            week = .row(weekly)
        } else if !snapshot.weeklyQuests.isEmpty {
            week = .closed
        } else {
            week = snapshot.weeklyStartsMonday == true ? .fromMonday : .hidden
        }
        return Quests(surprise: surprise, today: today, week: week)
    }

    // MARK: - Сьогодні

    public static func todayFootnote(_ day: WidgetDay) -> String {
        day.goalMet ? "Норму закрито" : left(day.leftMl, unit: day.unit)
    }

    /// Рядок над годинником на екрані блокування: «💧 1.25 з 2 л · ще 750 мл».
    public static func inline(_ day: WidgetDay) -> String {
        let head = "💧 \(liters(day.countedMl, unit: day.unit)) з \(liters(day.goalMl, unit: day.unit)) \(bigUnit(day.unit))"
        return day.goalMet ? "\(head) · ✓" : "\(head) · \(left(day.leftMl, unit: day.unit))"
    }

    // MARK: - Частина доби

    /// Що показує віджет «Частина доби» — один рядок на кожен стан (SPEC-WIDGETS §7).
    public struct Part: Equatable, Sendable {
        public enum Kind: Equatable, Sendable { case pending, closed, goalMet, beforeWake, afterSleep, wholeDay }
        public let kind: Kind
        /// Мала шапка великими: «РАНОК І ПОЛУДЕНЬ», «ДО КІНЦЯ ДНЯ».
        public let caption: String
        /// Велике число: «650» (мл / л — окремо в `unit`), «08:00».
        public let value: String
        public let unit: String?
        public let headline: String
        public let fraction: Double
        public let footnote: String
        /// «+10 XP» — лише поки ціль частини ще можна закрити.
        public let xp: String?
        /// Дедлайн — для відліку без секунд на iOS 18.
        public let deadlineMinute: Int?
    }

    public static func part(_ day: WidgetDay, xp: Int) -> Part {
        // Ніч — раніше за «норму закрито»: уночі віджет — нічне небо з підсумком дня (рішення від 13.10.2026, §7).
        switch day.phase {
        case .beforeWake:
            let first = day.blocks.first?.goal.targetMl ?? 0
            return Part(kind: .beforeWake, caption: "Ще рано", value: clock(day.schedule.wakeMinutes, day),
                        unit: nil, headline: "підйом", fraction: 0,
                        footnote: "ціль ранку — \(day.unit.label(first))", xp: nil, deadlineMinute: nil)
        case .afterSleep:
            return Part(kind: .afterSleep, caption: "Ніч", value: "\(day.percent)%", unit: nil,
                        headline: day.goalMet ? "норму закрито" : "норми за день", fraction: day.fraction,
                        footnote: "завтра з \(clock(day.schedule.wakeMinutes, day))", xp: nil, deadlineMinute: nil)
        case .active:
            break
        }
        if day.goalMet {
            return Part(kind: .goalMet, caption: "Сьогодні", value: "", unit: nil, headline: "Норму закрито",
                        fraction: 1, footnote: "\(liters(day.countedMl, unit: day.unit)) \(bigUnit(day.unit)) за день",
                        xp: nil, deadlineMinute: nil)
        }
        let left = shownLeft(day.leftMl, day.unit)
        guard day.dayRhythmEnabled, let part = day.part else {
            // «Просто норма за день» (WAT-42): ціль — уся норма, дедлайн — відбій.
            return Part(kind: .wholeDay, caption: "До кінця дня", value: left.value, unit: left.unit,
                        headline: "ще до \(clock(day.schedule.sleepMinutes, day))", fraction: day.fraction,
                        footnote: DayPartPresenter.duration(day.schedule.sleepMinutes - day.minute), xp: nil,
                        deadlineMinute: day.schedule.sleepMinutes)
        }
        let title = part.block.title
        if part.isReached {
            let next = day.blocks.first { $0.position == .future }
            return Part(kind: .closed, caption: title, value: "", unit: nil,
                        headline: "\(capitalized(title)) закрито", fraction: 1,
                        footnote: next.map { "далі \($0.goal.title) — \(day.unit.label($0.goal.targetMl))" } ?? "на сьогодні все",
                        xp: nil, deadlineMinute: nil)
        }
        let partLeft = shownLeft(part.leftMl, day.unit)
        return Part(kind: .pending, caption: title, value: partLeft.value, unit: partLeft.unit,
                    headline: "ще до \(clock(part.block.toMinute, day))", fraction: part.fraction,
                    footnote: DayPartPresenter.duration(part.minutesLeft), xp: "+\(xp) XP",
                    deadlineMinute: part.block.toMinute)
    }

    // MARK: - Ритм дня

    /// «+100 мл до темпу», «відстаєш на 350 мл», «йдеш за темпом» (у межах ±50 мл).
    public static func pace(_ day: WidgetDay) -> String? {
        if day.goalMet { return "✓ Норму закрито" }
        guard let delta = day.paceDeltaMl else { return nil }
        if abs(delta) < 50 { return "йдеш за темпом" }
        let rounded = roundedUp(abs(delta), day.unit)
        return delta > 0 ? "+\(rounded) до темпу" : "відстаєш на \(rounded)"
    }

    /// «800 / 689» — випито й ціль блоку; з вимкненим ритмом — лише випито.
    public static func blockValue(_ block: WidgetDay.Block, rhythm: Bool, unit: VolumeUnit = .milliliters) -> String {
        rhythm ? "\(unit.units(block.drunkMl)) / \(unit.units(block.goal.targetMl))" : unit.format(block.drunkMl) { "\($0) мл" }
    }

    /// «08–12» / «8–11 дп».
    public static func blockHours(_ block: WidgetDay.Block, format: TimeFormat = .hours24) -> String {
        format.hourRange(block.goal.fromMinute, block.goal.toMinute)
    }

    // MARK: - Запас води

    public struct Reserve: Equatable, Sendable {
        public let headline: String
        public let footnote: String
        /// «Час пити», «Почни зі склянки» — віджет виділяє.
        public let isUrgent: Bool
    }

    public static func reserve(_ day: WidgetDay) -> Reserve {
        switch day.phase {
        // Уночі запас не ведеться — так і кажемо, а не «0%» (рішення від 13.10.2026, §7).
        case .beforeWake:
            return Reserve(headline: "Сон", footnote: "запас рахую з \(clock(day.schedule.wakeMinutes, day))", isUrgent: false)
        case .afterSleep:
            return Reserve(headline: "Добраніч", footnote: "запас рахую з \(clock(day.schedule.wakeMinutes, day))", isUrgent: false)
        case .active:
            break
        }
        guard let reserve = day.reserve else {
            return Reserve(headline: "Почни зі склянки", footnote: "запас порожній", isUrgent: true)
        }
        switch reserve.mode {
        case .goalMet:
            return Reserve(headline: "Норму закрито", footnote: "запас до \(clock(day.schedule.sleepMinutes, day))", isUrgent: false)
        case .evening:
            return Reserve(headline: "Запас до вечора", footnote: "~\(minutesLeft(reserve, day))", isUrgent: false)
        case .flowing:
            if day.reserveIsEmpty {
                let planned = reserve.reminderIsPlanned ? reserve.reminderAt.flatMap { $0 > day.date ? $0 : nil } : nil
                return Reserve(headline: "Час пити", footnote: planned.map { "нагадаю о \(clock($0, day))" } ?? "запас порожній",
                               isUrgent: true)
            }
            guard let reminder = reserve.reminderAt else {
                return Reserve(headline: "Запасу ~\(minutesLeft(reserve, day))", footnote: "далі — час пити", isUrgent: false)
            }
            return Reserve(headline: "Пий о \(clock(reminder, day))", footnote: "запасу ~\(minutesLeft(reserve, day))", isUrgent: false)
        }
    }

    // MARK: - Прогрес

    /// «80 XP до 8».
    public static func xpLeft(_ level: WidgetSnapshot.Level) -> String { "\(level.xpLeft) XP до \(level.level + 1)" }

    /// «днів поспіль» — під числом серії.
    public static func streakWord(_ count: Int) -> String {
        "\(Plural.uk(count, one: "день", few: "дні", many: "днів")) поспіль"
    }

    // MARK: - Допоміжне

    /// Число кнопки без позначення: «250», «1.5», «8».
    static func number(_ ml: Int, unit: VolumeUnit = .milliliters) -> String {
        guard unit.isMetric else { return "\(unit.units(ml))" }
        return ml >= 1000 ? liters(ml) : "\(ml)"
    }
    static func unitWord(_ ml: Int, unit: VolumeUnit = .milliliters) -> String {
        guard unit.isMetric else { return VolumeUnit.ounceSymbol }
        return ml >= 1000 ? "л" : "мл"
    }
    static func capitalized(_ text: String) -> String { text.prefix(1).uppercased() + text.dropFirst() }

    /// «750 мл» — вгору до 50; «26 унц.» — вгору до цілої.
    static func roundedUp(_ ml: Int, _ unit: VolumeUnit) -> String {
        guard unit.isMetric else { return "\(unit.unitsRoundedUp(ml)) \(VolumeUnit.ounceSymbol)" }
        return DayPartPresenter.volume(DayPartPresenter.roundedUp(ml))
    }

    /// Скільки лишилось великим числом і позначенням окремо — «650» + «мл», «26» + «унц.».
    static func shownLeft(_ ml: Int, _ unit: VolumeUnit) -> (value: String, unit: String) {
        guard unit.isMetric else { return ("\(unit.unitsRoundedUp(ml))", VolumeUnit.ounceSymbol) }
        let left = DayPartPresenter.roundedUp(ml)
        return (number(left), unitWord(left))
    }

    static func clock(_ minute: Int, _ day: WidgetDay) -> String { DayPartPresenter.clock(minute, day.timeFormat) }

    static func minutesLeft(_ reserve: HydrationReserve, _ day: WidgetDay) -> String {
        DayPartPresenter.duration(Int((reserve.zeroAt.timeIntervalSince(day.date) / 60).rounded(.up)))
    }

    static func clock(_ date: Date, _ day: WidgetDay) -> String { clock(day.minute(of: date), day) }
}
