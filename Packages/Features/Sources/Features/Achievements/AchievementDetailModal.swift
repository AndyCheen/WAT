import SwiftUI
import Gamification
import DesignSystem

/// Картка деталей для будь-якої поверхні модуля: блок 3f, екран 2e, тост головного.
/// Одне перетворення знімка на `WTAchievementDetail` — щоб три точки входу показували
/// буквально ту саму картку (SPEC-ACHIEVEMENTS §13, п. 10).
struct AchievementDetailModal: View {
    let item: AchievementSnapshot
    let onClose: () -> Void

    var body: some View {
        WTAchievementDetail(
            emoji: item.emoji,
            title: item.title,
            details: item.details,
            isUnlocked: item.isUnlocked,
            rewardLabel: item.rewardLabel,
            fraction: item.fraction,
            valueLabel: item.valueLabel,
            accessibilityValue: item.detailAccessibilityValue,
            onClose: onClose
        )
        .zIndex(10)
    }
}

extension AchievementSnapshot {
    var rewardLabel: String { "+\(rewardXp) XP за виконання" }

    /// «Відкрито» / «Прогрес 5 із 7» — VoiceOver читає «5/7» як «5 слеш 7».
    var progressAccessibilityValue: String {
        isUnlocked ? "Відкрито" : "Прогрес \(Int(min(value, target))) із \(Int(target))"
    }

    /// Опис, стан і нагорода одним рядком — картка для VoiceOver один елемент.
    var detailAccessibilityValue: String {
        isUnlocked
            ? "\(details). Відкрито"
            : "\(details). \(progressAccessibilityValue). \(rewardLabel)"
    }
}
