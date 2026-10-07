import Foundation
import DesignSystem
import Gamification

/// Рядок драбини — готові значення для `WTRoadRow` і карток.
struct LevelRoadRow: Identifiable, Equatable {
    enum Content: Equatable {
        case none
        case start(String)
        case card(icon: WTRoadIcon, title: String, subtitle: String, tone: WTRoadCardTone, isGrand: Bool)
        case choice(options: [WTRoadChoiceOption])
        case mystery(title: String, subtitle: String, isGrand: Bool)
    }

    let level: Int
    let style: WTRoadNodeStyle
    let hasReward: Bool
    let content: Content
    let isCurrent: Bool
    let accessibilityLabel: String?

    var id: Int { level }

    /// Центр кружка — на рівні іконки картки: падінг 12 + половина іконки (48 / 56).
    var nodeCenterY: CGFloat? {
        switch content {
        case .card: return 36
        case .choice: return 29
        case .mystery: return 42
        case .none, .start: return nil
        }
    }
}

/// Усі тексти вікна «Шлях рівнів» (SPEC-PRIZES §16.8): чиста функція «знімок → рядки».
/// На «ти», без роду (SPEC-NOTIFICATIONS §14.1).
enum LevelRoadPresenter {
    static let title = "Шлях рівнів"
    static let choiceTitle = "Обери один"
    static let choiceHint = "Можна взяти один із двох"
    static let takeTitle = "Забрати"
    static let openTitle = "Відкрити"
    static let doneTitle = "Чудово"
    static let endTitle = "Далі — ще більше призів"
    static let startTitle = "Старт"
    static let hereLabel = "Ти тут ·"

    static func rows(_ road: LevelRoadSnapshot) -> [LevelRoadRow] {
        let current = road.progress.level
        return road.nodes.map { node in
            let isCurrent = node.level == current
            let style: WTRoadNodeStyle
            if isCurrent {
                style = .current(fraction: road.progress.fraction)
            } else if node.level < current {
                style = .passed
            } else {
                style = node.status == .fogged ? .fogged : .ahead
            }
            return LevelRoadRow(
                level: node.level, style: style, hasReward: node.reward != nil,
                content: content(node, isFirst: node.level == road.nodes.first?.level),
                isCurrent: isCurrent, accessibilityLabel: accessibilityLabel(node)
            )
        }
    }

    private static func content(_ node: LevelRoadNode, isFirst: Bool) -> LevelRoadRow.Content {
        guard let reward = node.reward else { return isFirst ? .start(startTitle) : .none }
        switch node.status {
        case .claimed:
            return .card(icon: icon(node.claimed), title: title(node.claimed), subtitle: claimedSubtitle(node.claimKind),
                         tone: .claimed, isGrand: false)
        case .pending:
            switch reward {
            case .choice(let grants):
                return .choice(options: grants.compactMap(option))
            case .mystery(let pool):
                return .mystery(title: mysteryTitle(pool), subtitle: possibleText(pool), isGrand: pool.isGrand)
            case .prize:
                return .card(icon: icon(reward.plainGrants), title: title(reward.plainGrants),
                             subtitle: claimedSubtitle(.prize), tone: .claimed, isGrand: false)
            }
        case .upcoming:
            let ahead = upcoming(reward)
            return .card(icon: ahead.icon, title: ahead.title, subtitle: ahead.subtitle, tone: .upcoming,
                         isGrand: reward.isGrandMystery)
        case .fogged:
            return .card(icon: .unknown, title: "Ще не видно", subtitle: "Відкриється ближче", tone: .fogged, isGrand: false)
        case .passed, .ahead:
            return .none
        }
    }

    /// Що буде на рівні попереду — і для драбини, і для блоку «НАГОРОДА НА РІВНІ N» на 3f.
    static func upcoming(_ reward: LevelNode) -> (icon: WTRoadIcon, title: String, subtitle: String) {
        switch reward {
        case .prize(let grant):
            let definition = RewardCatalog.definition(grant.key)
            return (.single(definition?.emoji ?? "", count: grant.count), definition?.title ?? "", definition?.details ?? "")
        case .choice(let grants):
            return (.pair(grants.compactMap { RewardCatalog.definition($0.key)?.emoji }), "Приз на вибір", orNames(grants))
        case .mystery(let pool):
            return (.single("🎁"), mysteryTitle(pool), possibleText(pool))
        }
    }

    /// Заклик у блоці 3f, поки вибір чи 🎁 чекають.
    static func pendingCall(_ reward: LevelNode) -> (icon: WTRoadIcon, title: String, subtitle: String) {
        switch reward {
        case .choice(let grants):
            return (.pair(grants.compactMap { RewardCatalog.definition($0.key)?.emoji }), "Приз на вибір", "Обери один із двох")
        case .mystery(let pool):
            return (.single("🎁"), mysteryTitle(pool), "Відкрий — що всередині?")
        case .prize:
            return upcoming(reward)
        }
    }

    static func pendingLabel(level: Int) -> String { "РІВЕНЬ \(level) · ЧЕКАЄ НА ТЕБЕ" }
    static func nextLabel(level: Int) -> String { "НАГОРОДА НА РІВНІ \(level)" }

    static func choiceSubtitle(selected key: String?, done: Bool) -> String {
        guard let key, let definition = RewardCatalog.definition(key) else { return choiceHint }
        return done ? "✓ \(definition.emoji) у твоїх призах" : definition.details
    }

    // MARK: - Таємний

    static func mysteryTitle(_ pool: MysteryPool) -> String {
        pool.isGrand ? "Великий таємний приз" : "Таємний приз"
    }

    /// «Може випасти: ⚡ 🧊 🌟» — що в пулі, без шансів у відсотках (§16.2). Великий — лише набори
    /// й 🌟: «🌟 ⚡×2 🧊×2», бо одного простого призу в ньому немає.
    static func possibleText(_ pool: MysteryPool) -> String {
        var seen: [String] = []
        for entry in pool.entries {
            if pool.isGrand {
                guard entry.grants.count == 1, let grant = entry.grants.first,
                      let emoji = RewardCatalog.definition(grant.key)?.emoji else { continue }
                seen.append(grant.count > 1 ? "\(emoji)×\(grant.count)" : emoji)
            } else {
                for grant in entry.grants {
                    guard let emoji = RewardCatalog.definition(grant.key)?.emoji, !seen.contains(emoji) else { continue }
                    seen.append(emoji)
                }
            }
        }
        return "Може випасти: " + seen.joined(separator: " ")
    }

    static func revealKicker(level: Int, pool: MysteryPool) -> String {
        "\(mysteryTitle(pool)) · рівень \(level)"
    }

    static func revealOutcome(_ grants: [RewardGrant]) -> WTMysteryReveal.Outcome {
        let items = grants.reduce(0) { $0 + $1.count }
        let subtitle: String
        if grants.count > 1 {
            subtitle = "Обидва — уже у твоїх призах"
        } else if items > 1 {
            subtitle = "\(items) шт. — уже у твоїх призах"
        } else {
            subtitle = "Уже у твоїх призах"
        }
        let name = title(grants)
        let spoken = items > 1 && grants.count == 1 ? "\(name), \(items) штуки" : name
        return WTMysteryReveal.Outcome(
            emojis: grants.compactMap { RewardCatalog.definition($0.key)?.emoji },
            count: grants.count == 1 ? items : 1,
            title: name, subtitle: subtitle,
            announcement: "\(spoken) — у твоїх призах"
        )
    }

    // MARK: - Довідник «Звідки XP» (§16.14)

    static let guideTitle = "Звідки XP"
    static let guideFootnote = "Понад 120 % норми XP за воду не нараховується."

    /// Числа — з тих самих `XPRules`, що й нарахування, з урахуванням загального множника:
    /// після зміни балансу довідник не бреше.
    static func guideRows(rules: XPRules, dayRhythm: Bool) -> [WTXPGuideRow] {
        let scale = { (xp: Int) in Int((Double(xp) * rules.xpMultiplier).rounded()) }
        let dailyQuest = QuestCatalog.all.filter { $0.scope == .daily }.map(\.rewardXp).min() ?? 0
        let weeklyQuest = QuestCatalog.all.filter { $0.scope == .weekly }.map(\.rewardXp).min() ?? 0
        let achievement = AchievementCatalog.all.map(\.rewardXp).min() ?? 0
        let streakCap = String(format: "%.1f", rules.streakMultiplierCap).replacingOccurrences(of: ".", with: ",")

        var rows = [WTXPGuideRow(emoji: "💧", title: "Вода, кожні \(rules.volumeStepMl) мл",
                                 value: "+\(scale(rules.xpPerVolumeStep)) XP")]
        rows.append(WTXPGuideRow(emoji: "🎯", title: "Норма дня", value: "+\(scale(rules.perDailyGoal)) XP"))
        if dayRhythm {
            rows.append(WTXPGuideRow(emoji: "⏰", title: "Ціль частини доби", value: "+\(scale(rules.perDayPartGoal)) XP"))
        }
        rows += [
            WTXPGuideRow(emoji: "✅", title: "Щоденне завдання", value: "+\(scale(dailyQuest)) XP"),
            WTXPGuideRow(emoji: "📅", title: "Тижневе завдання", value: "+\(scale(weeklyQuest)) XP"),
            WTXPGuideRow(emoji: "🏅", title: "Досягнення", value: "від \(scale(achievement)) XP"),
            WTXPGuideRow(emoji: "🔥", title: "Серія множить XP за воду", value: "до ×\(streakCap)"),
            WTXPGuideRow(emoji: "⚡", title: "Буст до 00:00", value: "×2 чи ×3")
        ]
        return rows
    }

    // MARK: - Спільне

    static func title(_ grants: [RewardGrant]) -> String {
        grants.compactMap { RewardCatalog.definition($0.key)?.title }.joined(separator: " + ")
    }

    static func icon(_ grants: [RewardGrant]) -> WTRoadIcon {
        let emojis = grants.compactMap { RewardCatalog.definition($0.key)?.emoji }
        if emojis.count > 1 { return .combo(emojis) }
        return .single(emojis.first ?? "", count: grants.first?.count ?? 1)
    }

    static func claimedSubtitle(_ kind: LevelRoadClaim?) -> String {
        switch kind {
        case .choice: return "Обрано з двох"
        case .mystery: return "З таємного призу"
        case .prize, nil: return "Отримано"
        }
    }

    /// «Заморозка серії або подвійний XP»: друга назва посеред речення — з малої.
    static func orNames(_ grants: [RewardGrant]) -> String {
        grants.compactMap { RewardCatalog.definition($0.key)?.title }
            .enumerated()
            .map { $0.offset == 0 ? $0.element : $0.element.prefix(1).lowercased() + $0.element.dropFirst() }
            .joined(separator: " або ")
    }

    private static func option(_ grant: RewardGrant) -> WTRoadChoiceOption? {
        RewardCatalog.definition(grant.key).map { WTRoadChoiceOption(id: $0.key, emoji: $0.emoji, title: $0.title) }
    }

    private static func accessibilityLabel(_ node: LevelRoadNode) -> String? {
        guard let reward = node.reward else { return nil }
        let what: String
        switch node.status {
        case .claimed: what = "\(title(node.claimed)), \(claimedSubtitle(node.claimKind).lowercased())"
        case .pending: what = "\(upcoming(reward).title), чекає"
        case .upcoming: what = "\(upcoming(reward).title), попереду"
        case .fogged: what = "ще не видно"
        case .passed, .ahead: return nil
        }
        return "Рівень \(node.level): \(what)"
    }
}

extension LevelNode {
    var plainGrants: [RewardGrant] {
        if case .prize(let grant) = self { return [grant] }
        return []
    }

    var isGrandMystery: Bool {
        if case .mystery(let pool) = self { return pool.isGrand }
        return false
    }
}
