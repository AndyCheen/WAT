import Foundation
import Core

/// Тексти віджетів — чиста функція «стан доби → рядки» (SPEC-WIDGETS §8). На «ти», без родового минулого
/// часу; об'єм — у тих самих форматах, що на головному, щоб віджет і застосунок казали те саме.
public enum WidgetPresenter {
    // MARK: - Об'єм

    /// «1.25 / 2.0 л» — підпис кільця, як `HomeViewModel.volumeLabel`.
    public static func ringVolume(countedMl: Int, goalMl: Int) -> String {
        "\(Volume.litersLabel(countedMl)) / \(Volume.litersLabel(goalMl, fractionDigits: 1)) л"
    }

    /// «1.25» — велике число без одиниць; «1» замість «1.00».
    public static func liters(_ ml: Int) -> String {
        var text = Volume.litersLabel(ml)
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return text
    }

    /// Підпис кнопки порції — як `HomeScreen.amountTitle`: «250 мл», «1 л», «1.05 л».
    public static func amount(_ ml: Int) -> String { DayPartPresenter.volume(ml) }

    /// «+250 мл» — кнопка, що одразу додає порцію.
    public static func addTitle(_ ml: Int) -> String { "+\(amount(ml))" }

    /// «ще 750 мл» — вгору до 50, як у капсули й сповіщень: краще трохи більше, ніж недобрати.
    public static func left(_ ml: Int) -> String { "ще \(DayPartPresenter.volume(DayPartPresenter.roundedUp(ml)))" }

    // MARK: - Сьогодні

    public static func todayFootnote(_ day: WidgetDay) -> String {
        day.goalMet ? "Норму закрито" : left(day.leftMl)
    }

    /// Рядок над годинником на екрані блокування: «💧 1.25 з 2 л · ще 750 мл».
    public static func inline(_ day: WidgetDay) -> String {
        let head = "💧 \(liters(day.countedMl)) з \(liters(day.goalMl)) л"
        return day.goalMet ? "\(head) · ✓" : "\(head) · \(left(day.leftMl))"
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
        if day.goalMet {
            return Part(kind: .goalMet, caption: "Сьогодні", value: "", unit: nil, headline: "Норму закрито",
                        fraction: 1, footnote: "\(liters(day.countedMl)) л за день", xp: nil, deadlineMinute: nil)
        }
        switch day.phase {
        case .beforeWake:
            let first = day.blocks.first?.goal.targetMl ?? 0
            return Part(kind: .beforeWake, caption: "Ще рано", value: DayPartPresenter.clock(day.schedule.wakeMinutes),
                        unit: nil, headline: "підйом", fraction: 0,
                        footnote: "ціль ранку — \(DayPartPresenter.volume(first))", xp: nil, deadlineMinute: nil)
        case .afterSleep:
            return Part(kind: .afterSleep, caption: "Добраніч", value: "\(day.percent)%", unit: nil,
                        headline: "норми за день", fraction: day.fraction,
                        footnote: "завтра з \(DayPartPresenter.clock(day.schedule.wakeMinutes))", xp: nil, deadlineMinute: nil)
        case .active:
            break
        }
        let left = DayPartPresenter.roundedUp(day.leftMl)
        guard day.dayRhythmEnabled, let part = day.part else {
            // «Просто норма за день» (WAT-42): ціль — уся норма, дедлайн — відбій.
            return Part(kind: .wholeDay, caption: "До кінця дня", value: number(left), unit: unitWord(left),
                        headline: "ще до \(DayPartPresenter.clock(day.schedule.sleepMinutes))", fraction: day.fraction,
                        footnote: DayPartPresenter.duration(day.schedule.sleepMinutes - day.minute), xp: nil,
                        deadlineMinute: day.schedule.sleepMinutes)
        }
        let title = part.block.title
        if part.isReached {
            let next = day.blocks.first { $0.position == .future }
            return Part(kind: .closed, caption: title, value: "", unit: nil,
                        headline: "\(capitalized(title)) закрито", fraction: 1,
                        footnote: next.map { "далі \($0.goal.title) — \(DayPartPresenter.volume($0.goal.targetMl))" } ?? "на сьогодні все",
                        xp: nil, deadlineMinute: nil)
        }
        let partLeft = DayPartPresenter.roundedUp(part.leftMl)
        return Part(kind: .pending, caption: title, value: number(partLeft), unit: unitWord(partLeft),
                    headline: "ще до \(DayPartPresenter.clock(part.block.toMinute))", fraction: part.fraction,
                    footnote: DayPartPresenter.duration(part.minutesLeft), xp: "+\(xp) XP",
                    deadlineMinute: part.block.toMinute)
    }

    // MARK: - Ритм дня

    /// «+100 мл до темпу», «відстаєш на 350 мл», «йдеш за темпом» (у межах ±50 мл).
    public static func pace(_ day: WidgetDay) -> String? {
        if day.goalMet { return "✓ Норму закрито" }
        guard let delta = day.paceDeltaMl else { return nil }
        if abs(delta) < 50 { return "йдеш за темпом" }
        let rounded = DayPartPresenter.volume(DayPartPresenter.roundedUp(abs(delta)))
        return delta > 0 ? "+\(rounded) до темпу" : "відстаєш на \(rounded)"
    }

    /// «800 / 689» — випито й ціль блоку; з вимкненим ритмом — лише випито.
    public static func blockValue(_ block: WidgetDay.Block, rhythm: Bool) -> String {
        rhythm ? "\(block.drunkMl) / \(block.goal.targetMl)" : "\(block.drunkMl) мл"
    }

    /// «08–12».
    public static func blockHours(_ block: WidgetDay.Block) -> String {
        "\(hour(block.goal.fromMinute))–\(hour(block.goal.toMinute))"
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
        case .beforeWake:
            return Reserve(headline: "Сон", footnote: "підйом о \(DayPartPresenter.clock(day.schedule.wakeMinutes))", isUrgent: false)
        case .afterSleep:
            return Reserve(headline: "Добраніч", footnote: "завтра з \(DayPartPresenter.clock(day.schedule.wakeMinutes))", isUrgent: false)
        case .active:
            break
        }
        guard let reserve = day.reserve else {
            return Reserve(headline: "Почни зі склянки", footnote: "запас порожній", isUrgent: true)
        }
        switch reserve.mode {
        case .goalMet:
            return Reserve(headline: "Норму закрито", footnote: "запас до \(DayPartPresenter.clock(day.schedule.sleepMinutes))", isUrgent: false)
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

    static func number(_ ml: Int) -> String { ml >= 1000 ? liters(ml) : "\(ml)" }
    static func unitWord(_ ml: Int) -> String { ml >= 1000 ? "л" : "мл" }
    static func capitalized(_ text: String) -> String { text.prefix(1).uppercased() + text.dropFirst() }
    static func hour(_ minute: Int) -> String { String(format: "%02d", (minute / 60) % 24) }

    static func minutesLeft(_ reserve: HydrationReserve, _ day: WidgetDay) -> String {
        DayPartPresenter.duration(Int((reserve.zeroAt.timeIntervalSince(day.date) / 60).rounded(.up)))
    }

    static func clock(_ date: Date, _ day: WidgetDay) -> String { DayPartPresenter.clock(day.minute(of: date)) }
}
