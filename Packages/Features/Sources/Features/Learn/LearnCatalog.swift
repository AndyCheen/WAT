import Foundation
import Metrics
import DesignSystem

/// Полиця «Знань» (SPEC-LEARN §4): наука, звички, механіки застосунку.
public enum LearnShelf: String, CaseIterable, Sendable {
    case body, habits, app

    var title: String {
        switch self {
        case .body: return "Вода й тіло"
        case .habits: return "Звички"
        case .app: return "Застосунок"
        }
    }

    /// Колір обкладинок і кольорових слайдів полиці (SPEC-LEARN §5.1).
    var style: WTStoryStyle {
        switch self {
        case .body: return .learnWater
        case .habits: return .learnDeep
        case .app: return .learnWarm
        }
    }

    /// Подія «дочитано історію полиці» — досягнення за всю полицю (§7). За «Звички» досягнення немає.
    var completionMetric: MetricKey? {
        switch self {
        case .body: return .learnBodyCompleted
        case .habits: return nil
        case .app: return .learnAppCompleted
        }
    }
}

/// Першоджерела фактів (SPEC-LEARN §10). Коротка назва — у рядку «Звідки цифра?», повна — на фініші.
enum LearnSource: String, CaseIterable, Sendable {
    case popkin, efsa, jequier, valtin, armstrong, ganio, killer, dennis, lally, acsm, who, rosinger

    var short: String {
        switch self {
        case .popkin: return "Popkin et al., 2010"
        case .efsa: return "EFSA, 2010"
        case .jequier: return "Jéquier, Constant, 2010"
        case .valtin: return "Valtin, 2002"
        case .armstrong: return "Armstrong et al., 1994"
        case .ganio: return "Ganio et al., 2011"
        case .killer: return "Killer et al., 2014"
        case .dennis: return "Dennis et al., 2010"
        case .lally: return "Lally et al., 2010"
        case .acsm: return "ACSM, 2007"
        case .who: return "ВООЗ"
        case .rosinger: return "Rosinger et al., 2019"
        }
    }

    var full: String {
        switch self {
        case .popkin:
            return "Popkin B. M., DʼAnci K. E., Rosenberg I. H. Water, hydration, and health. Nutrition Reviews, 2010; 68(8): 439–458."
        case .efsa:
            return "EFSA NDA Panel. Scientific Opinion on Dietary Reference Values for water. EFSA Journal, 2010; 8(3): 1459."
        case .jequier:
            return "Jéquier E., Constant F. Water as an essential nutrient: the physiological basis of hydration. Eur J Clin Nutr, 2010; 64: 115–123."
        case .valtin:
            return "Valtin H. «Drink at least eight glasses of water a day.» Really? Am J Physiol Regul Integr Comp Physiol, 2002; 283: R993–R1004."
        case .armstrong:
            return "Armstrong L. E. et al. Urinary indices of hydration status. Int J Sport Nutr, 1994; 4(3): 265–279."
        case .ganio:
            return "Ganio M. S. et al. Mild dehydration impairs cognitive performance and mood of men. Br J Nutr, 2011; 106: 1535–1543."
        case .killer:
            return "Killer S. C., Blannin A. K., Jeukendrup A. E. No evidence of dehydration with moderate daily coffee intake. PLoS One, 2014; 9(1): e84154."
        case .dennis:
            return "Dennis E. A. et al. Water consumption increases weight loss during a hypocaloric diet intervention. Obesity, 2010; 18(2): 300–307."
        case .lally:
            return "Lally P. et al. How are habits formed: modelling habit formation in the real world. Eur J Soc Psychol, 2010; 40(6): 998–1009."
        case .acsm:
            return "American College of Sports Medicine. Exercise and fluid replacement. Med Sci Sports Exerc, 2007; 39(2): 377–390."
        case .who:
            return "WHO. Oral rehydration salts: production of the new ORS. 2006."
        case .rosinger:
            return "Rosinger A. Y. et al. Short sleep duration is associated with inadequate hydration. SLEEP, 2019; 42(2)."
        }
    }
}

/// Історія — метадані; слайди з текстами й живими значеннями складає `LearnPresenter`.
struct LearnStory: Identifiable, Equatable, Sendable {
    let id: String
    let shelf: LearnShelf
    let emoji: String
    let title: String
    let minutes: Int
    let sources: [LearnSource]
    /// Версія 1 — чернетка (SPEC-LEARN §5.3): у DEBUG на обкладинці мітка «чернетка».
    var isDraft = true
}

/// Каталог «Знань» — версія 1 (SPEC-LEARN §4, рішення від 19.10.2026: 12 історій як є).
/// Порядок — порядок полиць і обкладинок у бібліотеці. Ідентифікатор — ключ прогресу й `sourceRef`
/// метрики, тож він не змінюється, навіть коли змінюється назва.
enum LearnCatalog {
    static let stories: [LearnStory] = [
        LearnStory(id: "body.why", shelf: .body, emoji: "💧", title: "Навіщо тілу вода", minutes: 2,
                   sources: [.popkin, .jequier, .efsa]),
        LearnStory(id: "body.howMuch", shelf: .body, emoji: "📏", title: "Скільки треба саме тобі", minutes: 2,
                   sources: [.valtin, .efsa, .killer]),
        LearnStory(id: "body.signs", shelf: .body, emoji: "🔎", title: "Коли води бракує", minutes: 2,
                   sources: [.ganio, .armstrong, .popkin, .who]),
        LearnStory(id: "body.myths", shelf: .body, emoji: "🤔", title: "Пʼять міфів про воду", minutes: 3,
                   sources: [.killer, .efsa, .popkin, .dennis]),
        LearnStory(id: "habits.rhythm", shelf: .habits, emoji: "🕒", title: "Рівно протягом дня", minutes: 2,
                   sources: [.jequier, .rosinger]),
        LearnStory(id: "habits.anchors", shelf: .habits, emoji: "⚓", title: "Звички, що тримаються", minutes: 2,
                   sources: [.lally]),
        LearnStory(id: "habits.special", shelf: .habits, emoji: "☀️", title: "Спека, спорт і хвороба", minutes: 2,
                   sources: [.acsm, .who]),
        LearnStory(id: "app.start", shelf: .app, emoji: "👋", title: "Перші кроки", minutes: 2, sources: []),
        LearnStory(id: "app.xp", shelf: .app, emoji: "⭐", title: "XP і рівні", minutes: 1, sources: []),
        LearnStory(id: "app.streak", shelf: .app, emoji: "🔥", title: "Серія й заморозка", minutes: 2, sources: []),
        LearnStory(id: "app.prizes", shelf: .app, emoji: "🎁", title: "Призи й шлях рівнів", minutes: 2, sources: []),
        LearnStory(id: "app.reminders", shelf: .app, emoji: "🔔", title: "Нагадування без спаму", minutes: 2, sources: [])
    ]

    static func story(_ id: String) -> LearnStory? {
        stories.first { $0.id == id }
    }

    static func stories(in shelf: LearnShelf) -> [LearnStory] {
        stories.filter { $0.shelf == shelf }
    }

    /// Наступна на фініші: далі по полиці, після останньої — перша наступної полиці.
    static func next(after story: LearnStory) -> LearnStory {
        let index = stories.firstIndex(of: story) ?? 0
        return stories[(index + 1) % stories.count]
    }
}
