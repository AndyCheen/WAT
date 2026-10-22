import Foundation
import Core
import Gamification
import Widgets

/// Тексти завдань (SPEC-QUESTS §9.1) — чисті функції від знімка, системи об'єму й формату часу. Знімок несе
/// шаблон назви й параметри, а не рядок: «Половина до 2:00 пп» і «5 склянок від 5 унц.» складаються тут.
/// Вигляд рядків на головному — WAT-64 (QUESTS-PLAN §2.2).
enum QuestPresenter {
    static func title(_ quest: QuestSnapshot, unit: VolumeUnit = .milliliters, format: TimeFormat = .hours24) -> String {
        quest.title.parts.map { part -> String in
            switch part {
            case .text(let text): return text
            case .time: return quest.deadlineMinute.map(format.clock) ?? ""
            case .count(let noun): return count(quest.count ?? 0, noun)
            case .volume(let ml): return unit.label(ml)
            case .block: return blockName(index: quest.blockIndex ?? 0, count: quest.blockCount ?? 3)
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

    /// Блок цілі — за місцем у дні, а не за `DayPart`: блок «ранок і полудень» людині — просто ранок.
    static func blockName(index: Int, count: Int) -> String {
        if index <= 0 { return count > 1 ? "ранок" : "день" }
        return index >= count - 1 ? "вечір" : "день"
    }
}
