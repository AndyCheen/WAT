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
            status: item.detailStatus,
            rewardLabel: item.rewardLabel,
            note: item.note,
            accessibilityValue: item.detailAccessibilityValue,
            onClose: onClose
        )
        .zIndex(10)
    }
}

extension AchievementSnapshot {
    var rewardLabel: String { "+\(rewardXp) XP за виконання" }

    /// Під назвою плитки: прогрес, підпис вимкненої функції чи нічого — у відкритого, таємного й разового.
    var tileStatus: WTAchievementStatus {
        if isUnlocked { return .unlocked }
        if isMasked { return .hidden }
        if let lockedCaption { return .caption(lockedCaption) }
        if isOneStep { return .locked }
        return .progress(fraction: fraction, label: progressLabel)
    }

    /// Нижній слот картки — той самий розклад, лише з «5 / 7» замість «5/7».
    var detailStatus: WTAchievementStatus {
        if case .progress = tileStatus { return .progress(fraction: fraction, label: valueLabel) }
        return tileStatus
    }

    /// «Відкрито» / «Прогрес 5 із 7» — VoiceOver читає «5/7» як «5 слеш 7». Таємне — «Таємне досягнення»,
    /// разове — «Ще не відкрито»: «прогрес 0 із 1» про досягнення, що або є, або ні, нічого не каже.
    var progressAccessibilityValue: String {
        if isUnlocked { return "Відкрито" }
        if isMasked { return "Таємне досягнення" }
        if let lockedCaption { return lockedCaption }
        if isOneStep { return "Ще не відкрито" }
        return "Прогрес \(Int(min(value, target))) із \(Int(target))"
    }

    /// Опис, стан і нагорода одним рядком — картка для VoiceOver один елемент.
    var detailAccessibilityValue: String {
        if isUnlocked { return [details, note, "Відкрито"].compactMap { $0 }.joined(separator: ". ") }
        if isMasked { return "\(details). \(progressAccessibilityValue)" }
        return "\(details). \(progressAccessibilityValue). \(rewardLabel)"
    }
}
