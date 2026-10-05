import Foundation
import Core
import DesignSystem

/// Капсула частини доби під кільцем (WAT-40): готовий вміст і підпис для VoiceOver.
struct DayPartLine: Equatable {
    let content: WTDayPartPill.Content
    let accessibilityLabel: String
}

/// Тексти капсули частини доби — чиста функція «стан → тексти», як `PrizePresenter` і `ReportPresenter`.
///
/// Підказка для того, хто відкрив застосунок, коли чекпоінт навмисно мовчить: бракує менше ніж
/// ½ порції понад темп (SPEC-NOTIFICATIONS §9). Тому числа ті самі, що в чекпоінта: «ще N мл»
/// округлюється вгору до 50, як `NotificationFormat.left`, — 99 мл стають «ще 100 мл».
enum DayPartPresenter {
    /// `nil` — капсули немає: поза активними годинами або норму дня вже закрито.
    static func line(_ progress: DayPartProgress?, goalMet: Bool, xp: Int) -> DayPartLine? {
        guard let progress, !goalMet else { return nil }
        let block = progress.block

        if progress.isReached {
            // «закрито» — безособовий зворот без роду, як у тексті чекпоінта (§14.1).
            let title = "\(block.title.prefix(1).uppercased())\(block.title.dropFirst()) закрито"
            return DayPartLine(content: .closed(title: title), accessibilityLabel: title)
        }

        let deadline = clock(block.toMinute)
        let left = roundedUp(progress.leftMl)
        return DayPartLine(
            content: .pending(
                fraction: progress.fraction,
                title: "До \(deadline) — ще \(volume(left))",
                xp: "+\(xp) XP",
                timeLeft: duration(progress.minutesLeft)
            ),
            accessibilityLabel: "До \(deadline) бракує \(left) мл, лишилось \(spokenDuration(progress.minutesLeft))"
        )
    }

    /// Вгору до 50, щоб не недобрати.
    static func roundedUp(_ ml: Int) -> Int {
        Int((Double(max(0, ml)) / 50).rounded(.up)) * 50
    }

    /// «850 мл», «1.5 л» — літри з крапкою, як на кільці (`Volume.litersLabel`).
    static func volume(_ ml: Int) -> String {
        guard ml >= 1000 else { return "\(ml) мл" }
        var text = Volume.litersLabel(ml)
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return "\(text) л"
    }

    /// «35 хв», «2 год», «1 год 20 хв». Менше хвилини не буває: межа частини — вже наступна.
    static func duration(_ minutes: Int) -> String {
        let total = max(1, minutes)
        let (hours, rest) = (total / 60, total % 60)
        switch (hours, rest) {
        case (0, _): return "\(rest) хв"
        case (_, 0): return "\(hours) год"
        default: return "\(hours) год \(rest) хв"
        }
    }

    /// «35 хвилин», «1 година 20 хвилин» — VoiceOver повними словами.
    static func spokenDuration(_ minutes: Int) -> String {
        let total = max(1, minutes)
        let (hours, rest) = (total / 60, total % 60)
        var parts: [String] = []
        if hours > 0 { parts.append("\(hours) \(Plural.uk(hours, one: "година", few: "години", many: "годин"))") }
        if rest > 0 { parts.append("\(rest) \(Plural.uk(rest, one: "хвилина", few: "хвилини", many: "хвилин"))") }
        return parts.joined(separator: " ")
    }

    /// Відбій опівночі — «00:00», а не «24:00».
    private static func clock(_ minute: Int) -> String {
        let value = minute % (24 * 60)
        return String(format: "%02d:%02d", value / 60, value % 60)
    }
}
