import Foundation
import Gamification
import DesignSystem

/// Вікно відкриття досягнень (WAT-60, SPEC-ACHIEVEMENTS §8): що показати й що зробити після закриття.
/// Показує `RootView` поверх усього, складає `CelebrationPresenter`.
public struct Celebration: Equatable, Identifiable {
    /// Звідки відкрите: дія на екрані чи порція поза ним — віджет, сповіщення, «Команди», завершений учорашній
    /// день, перерахунок після оновлення (§8.5).
    public enum Context: Equatable, Sendable {
        case action
        case whileAway
    }

    public let id = UUID()
    public let context: Context
    /// Що позначити відсвяткованим після закриття.
    public let keys: [String]
    public let pages: [WTCelebrationPage]
    public let level: WTCelebrationLevel?
    public let finishTitle: String
    public let laterTitle: String?
    /// Головна кнопка останньої сторінки веде на 3f з вікном «Шлях рівнів» — рівень дав вибір чи 🎁.
    public let opensLevelRoad: Bool
    /// Після дії на головному вікно чекає, поки догра кільце (§8.5).
    public let appearDelay: Double

    public static func == (lhs: Celebration, rhs: Celebration) -> Bool { lhs.id == rhs.id }
}

/// Тексти вікна відкриття — чиста функція «досягнення → сторінки» (SPEC-ACHIEVEMENTS §8.2–§8.4). Опис —
/// `details` знімка, тобто той самий текст, що в картці, уже в одиницях людини; «Далі» — з каталогу.
enum CelebrationPresenter {
    /// Більше — одна сторінка сіткою (§8.1).
    static let maxPages = 3
    /// Прогрес до наступної сходинки, з якого її варто показувати: «1 / 100» лякає, а не заохочує (§8.4).
    static let nextMinFraction = 0.1

    struct LevelUp: Equatable {
        let number: Int
        let fraction: Double
    }

    static func make(
        _ unlocked: [AchievementSnapshot], all: [AchievementSnapshot], context: Celebration.Context, level: LevelUp?
    ) -> Celebration? {
        guard !unlocked.isEmpty else { return nil }
        let node = level.flatMap { LevelRoadCatalog.node(forLevel: $0.number) }
        let pages = unlocked.count > maxPages
            ? [summaryPage(unlocked, context: context)]
            : unlocked.map { page($0, all: all, context: context) }
        let finish: String
        let opensRoad: Bool
        switch node {
        case .choice?: (finish, opensRoad) = ("Обрати приз", true)
        case .mystery?: (finish, opensRoad) = ("Відкрити 🎁", true)
        case .prize?, nil: (finish, opensRoad) = ("Чудово", false)
        }
        return Celebration(
            context: context,
            keys: unlocked.map(\.key),
            pages: pages,
            level: level.map { WTCelebrationLevel(number: $0.number, fraction: $0.fraction, caption: levelCaption(node)) },
            finishTitle: finish,
            laterTitle: opensRoad ? "Пізніше" : nil,
            opensLevelRoad: opensRoad,
            appearDelay: context == .action ? 0.6 : 0.4
        )
    }

    /// Підпис рівня — ті самі новини, що в тості рівня (SPEC-PRIZES §16.6). Вузла немає — підпису немає.
    static func levelCaption(_ node: LevelNode?) -> String? {
        switch node {
        case .prize(let grant)?:
            return RewardCatalog.definition(grant.key).map { "\($0.emoji) \($0.title) — у призах" }
        case .choice(let grants)?:
            let emojis = grants.compactMap { RewardCatalog.definition($0.key)?.emoji }.joined(separator: " або ")
            return "Обери приз: \(emojis)"
        case .mystery?:
            return "🎁 Таємний приз чекає"
        case nil:
            return nil
        }
    }

    static func label(_ item: AchievementSnapshot, context: Celebration.Context) -> String {
        let isHint = item.isSecret && !item.isEgg
        switch context {
        case .action:
            return item.isEgg ? "Пасхалка" : isHint ? "Таємне досягнення" : "Нове досягнення"
        case .whileAway:
            return "Поки тебе не було" + (item.isEgg ? " · пасхалка" : isHint ? " · таємне" : "")
        }
    }

    static func page(_ item: AchievementSnapshot, all: [AchievementSnapshot], context: Celebration.Context) -> WTCelebrationPage {
        let label = label(item, context: context)
        return WTCelebrationPage(
            emoji: item.emoji,
            label: label,
            title: item.title,
            details: item.details,
            xp: item.rewardXp,
            reveal: item.isEgg ? .egg : item.isSecret ? .secret : .none,
            // У першої пасхалки — «Тут їх більше» замість «Далі»: сходинок у пасхалок однаково немає.
            next: item.note == nil ? nextLine(after: item, all: all) : nil,
            note: item.note,
            accessibilityLabel: "\(label): \(item.title). \(item.details). Плюс \(item.rewardXp) XP"
        )
    }

    /// «Далі: ⭐ Тиждень поспіль · 3 / 7» — найменша ще не відкрита сходинка того самого правила, з відкритою
    /// функцією й прогресом від 10 % (§8.4). Немає — немає рядка.
    static func nextLine(after item: AchievementSnapshot, all: [AchievementSnapshot]) -> String? {
        let byKey = Dictionary(all.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
        let next = AchievementCatalog.higherSteps(after: item.key)
            .compactMap { byKey[$0.key] }
            .first { !$0.isUnlocked }
        guard let next, next.lockedCaption == nil, !next.isMasked, next.fraction >= nextMinFraction else { return nil }
        return "Далі: \(next.emoji) \(next.title) · \(next.valueLabel)"
    }

    /// Більше трьох за раз — заднім числом після оновлення чи за кілька днів поза застосунком (§8.1).
    static func summaryPage(_ unlocked: [AchievementSnapshot], context: Celebration.Context) -> WTCelebrationPage {
        let title = "Нові досягнення: \(unlocked.count)"
        let label = context == .whileAway ? "Поки тебе не було" : "Нове в колекції"
        let details = unlocked.map(\.title).joined(separator: " · ")
        let xp = unlocked.map(\.rewardXp).reduce(0, +)
        return WTCelebrationPage(
            emoji: "🏅", grid: unlocked.map(\.emoji), label: label, title: title, details: details, xp: xp,
            accessibilityLabel: "\(label): \(title). \(details). Плюс \(xp) XP"
        )
    }
}
