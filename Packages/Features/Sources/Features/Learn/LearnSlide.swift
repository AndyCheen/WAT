import Foundation
import DesignSystem

/// Куди веде кнопка «Що з цим робити» (SPEC-LEARN §4: кожна історія закінчується дією в застосунку).
enum LearnDestination: Equatable, Sendable {
    case home
    /// Шторка «Інше» на головному — пляшка, склянка нестандартного об'єму.
    case customAmount
    case stats
    case settings
    case portionButtons
    case notifications
    case levelRoad
    case prizes
    case story(String)
}

/// Що намальовано на слайді — шаблони ілюстрацій із `DesignSystem` (SPEC-LEARN §5.1).
enum LearnVisual: Equatable {
    case drop(level: Double)
    case emoji(String)
    case body(fraction: Double)
    case bodyMap([String])
    case columns(WTLearnColumns.Column, WTLearnColumns.Column)
    case question
    case ring(total: String, caption: String, segments: [WTLearnSegmentRing.Segment])
    case level(Int)
    case glasses(full: Int, bonus: Int, locked: Int, chip: String?, legend: [String])
    case ladder([WTLearnLadder.Node], progress: Double)
    case stack(unit: String, caption: String, segments: [WTLearnStackBar.Segment])
    case bars([WTLearnBars.Bar], legend: [String])
    case tiles([WTLearnTiles.Item])
    case chain(days: [WTLearnChain.Day], labels: [String], caption: String?)
    case tokens([WTLearnTokens.Token])
    case dayLine(drops: [Double], bells: [Double], start: String, end: String)
    case dots(Int)
    case homeRing(percent: Int)
    case dayPartPill(title: String, xp: String, timeLeft: String)
    // Інтерактивні
    case colorScale(verdicts: [String], prompt: String)
    case curve(modes: [String], captions: [String], start: String, end: String)
    case chips(options: [String], limit: Int, prompt: String)
    case miniHome(goal: Int, buttons: [Int])
    case factors(base: Int, baseLabel: String, factors: [WTLearnFactors.Factor])

    /// Інтерактивна ілюстрація забирає тапи собі — підказка «тапни» в ній, а не в тексті.
    var isInteractive: Bool {
        switch self {
        case .colorScale, .curve, .chips, .miniHome, .factors: return true
        default: return false
        }
    }
}

/// Один слайд історії. Тексти — готові, з живими значеннями (`LearnPresenter`); слайд лише малюється.
struct LearnSlide: Equatable {
    enum Kind: Equatable {
        case cover
        /// Думка: надзаголовок, (число), заголовок, текст, ілюстрація.
        case fact
        /// До 4 пунктів з іконками під ілюстрацією.
        case list
        /// «Правда чи міф?» — картка перевертається на відповідь (рішення від 19.10.2026).
        case quiz(isTrue: Bool, explanation: String)
        /// Підсумок вікторини «4 з 5» — рахує екран за відповідями; кнопка веде далі.
        case quizScore(title: String, destination: LearnDestination)
        /// «Що з цим робити»: кнопка на екран застосунку.
        case action(title: String, destination: LearnDestination)
    }

    struct Item: Equatable {
        let emoji: String
        let title: String
        var detail: String?
        var value: String?
    }

    struct Number: Equatable {
        let value: Double
        var decimals = 0
        var prefix = ""
        let unit: String
    }

    var kind: Kind
    var style: WTStoryStyle = .plain
    var kicker: String
    var title: String
    var text: String?
    var number: Number?
    var visual: LearnVisual?
    var items: [Item] = []
    var source: LearnSource?

    /// Усі тексти слайда — для перевірок довжини й мови (`LearnCopyTests`) і VoiceOver.
    var copy: [String] {
        var lines = [kicker, title] + [text].compactMap { $0 }
        lines += items.flatMap { [$0.title] + [$0.detail, $0.value].compactMap { $0 } }
        if case .quiz(_, let explanation) = kind { lines.append(explanation) }
        if case .action(let button, _) = kind { lines.append(button) }
        if case .quizScore(let button, _) = kind { lines.append(button) }
        return lines
    }
}
