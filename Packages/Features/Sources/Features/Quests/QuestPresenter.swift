import Foundation
import Core
import Gamification
import Widgets

/// Тексти завдань (SPEC-QUESTS §9.1) — чисті функції від знімка, системи об'єму й формату часу. Знімок несе
/// шаблон назви й параметри, а не рядок: «Половина до 2:00 пп» і «5 склянок від 5 унц.» складаються тут.
/// Що з цього видно на головному — `QuestBlock`.
enum QuestPresenter {
    static let blockLabel = "ЗАВДАННЯ"
    static let todayLabel = "СЬОГОДНІ"
    static let weekLabel = "ЦЬОГО ТИЖНЯ"
    static let allDailyDone = "Усе на сьогодні 🎉"
    static let weekClosed = "Тиждень закрито 🎉"
    static let weeklyFromMonday = "Тижневі завдання — з понеділка"

    /// «· ЩЕ 5 ДН.» — продовження підпису «ЦЬОГО ТИЖНЯ», приглушене. Разом із сьогоднішнім: у неділю — «ще 1 дн.».
    static func weekDaysLeft(_ days: Int) -> String { "· ЩЕ \(days) ДН." }

    /// «Виконані · 2» / «Сховати».
    static func completedToggle(count: Int, showing: Bool) -> String { showing ? "Сховати" : "Виконані · \(count)" }

    /// VoiceOver рядка: «Половина до 14:00, ще 500 мл, 25 XP». «2/4» вголос читалося б як дріб — тут «2 з 4».
    static func accessibilityLabel(_ quest: QuestSnapshot, xp: Int, unit: VolumeUnit = .milliliters,
                                   format: TimeFormat = .hours24) -> String {
        let progress: String
        if quest.isDone {
            progress = "виконано"
        } else {
            let done = Int(min(quest.progress, quest.target))
            let target = Int(quest.target)
            switch quest.kind {
            case .volume: progress = progressLabel(quest, unit: unit)
            case .count: progress = "\(done) з \(target)"
            // Після «з N» — родовий множини для будь-якого N ≥ 2: «з 4 днів», «з 5 днів».
            case .days: progress = "\(done) з \(target) днів"
            }
        }
        return "\(title(quest, unit: unit, format: format)), \(progress), \(xp) XP"
    }

    static func title(_ quest: QuestSnapshot, unit: VolumeUnit = .milliliters, format: TimeFormat = .hours24) -> String {
        quest.title.parts.map { part -> String in
            switch part {
            case .text(let text): return text
            case .time: return quest.deadlineMinute.map(format.clock) ?? ""
            case .count(let noun): return count(quest.count ?? 0, noun)
            case .volume(let ml): return unit.label(ml)
            case .block: return blockName(index: quest.blockIndex ?? 0, count: quest.blockCount ?? 3)
            case .weekday: return quest.weekdayIndex.map { CalendarService.weekdayNames[min(max($0, 0), 6)] } ?? ""
            }
        }.joined()
    }

    /// «ще 500 мл» (вгору до 50, як у капсули частини доби), «ще 9 унц.», «2/4», «2/5 дн.», «Готово».
    static func progressLabel(_ quest: QuestSnapshot, unit: VolumeUnit = .milliliters) -> String {
        if quest.isDone { return "Готово" }
        let done = Int(min(quest.progress, quest.target))
        let target = Int(quest.target)
        switch quest.kind {
        case .volume: return WidgetPresenter.left(target - done, unit: unit)
        case .count: return "\(done)/\(target)"
        case .days: return "\(done)/\(target) дн."
        }
    }

    /// N з узгодженим іменником: «3 склянки», «5 днів», «2 ідеальні дні».
    static func count(_ n: Int, _ noun: QuestNoun) -> String {
        let word: String
        switch noun {
        case .glasses: word = Plural.uk(n, one: "склянка", few: "склянки", many: "склянок")
        case .days: word = Plural.uk(n, one: "день", few: "дні", many: "днів")
        case .mornings: word = Plural.uk(n, one: "ранок", few: "ранки", many: "ранків")
        case .perfectDays: word = Plural.uk(n, one: "ідеальний день", few: "ідеальні дні", many: "ідеальних днів")
        }
        return "\(n) \(word)"
    }

    // MARK: - Несподіване (§9.1)

    static let surpriseDone = "Готово · ⚡ у призах"

    /// Позначка виду над назвою — «Блискавка» окремо: це азарт, а не латка прогалини.
    static func surpriseKind(_ quest: QuestSnapshot) -> String { quest.isFlash ? "БЛИСКАВКА" : "НЕСПОДІВАНЕ" }

    /// «250 мл до 14:30 · ще 250 мл»; виконане — «Готово · ⚡ у призах».
    static func surpriseDetail(_ quest: QuestSnapshot, unit: VolumeUnit = .milliliters,
                               format: TimeFormat = .hours24) -> String {
        if quest.isDone { return surpriseDone }
        let deadline = quest.deadlineMinute.map(format.clock) ?? ""
        return "\(unit.label(Int(quest.target))) до \(deadline) · \(progressLabel(quest, unit: unit))"
    }

    /// «+25 XP · ⚡» — XP з бустом і загальним множником, як у рядків.
    static func surpriseReward(xp: Int) -> String { "+\(xp) XP · ⚡" }

    /// VoiceOver картки: таймер читається окремо, тож тут — що зробити й що за це.
    static func surpriseAccessibilityLabel(_ quest: QuestSnapshot, xp: Int, unit: VolumeUnit = .milliliters,
                                           format: TimeFormat = .hours24) -> String {
        let kind = quest.isFlash ? "Блискавка" : "Несподіване завдання"
        return "\(kind): \(title(quest, unit: unit, format: format)), \(surpriseDetail(quest, unit: unit, format: format)), "
            + "\(xp) XP і приз «Подвійний XP»"
    }

    /// Блок цілі — за місцем у дні, а не за `DayPart`: блок «ранок і полудень» людині — просто ранок.
    static func blockName(index: Int, count: Int) -> String {
        if index <= 0 { return count > 1 ? "ранок" : "день" }
        return index >= count - 1 ? "вечір" : "день"
    }
}
