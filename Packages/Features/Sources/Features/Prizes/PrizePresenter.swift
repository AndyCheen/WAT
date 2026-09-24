import Foundation
import SwiftUI
import Core
import DesignSystem
import Gamification

/// Вміст картки призу — готові значення для `WTPrizeDetail`.
struct PrizeDetailContent: Equatable {
    let emoji: String
    let title: String
    let count: Int
    let details: String
    let status: WTPrizeDetailStatus
    let action: WTPrizeDetailAction?
    let accessibilityValue: String
}

/// Усі тексти модуля «Призи» (SPEC-PRIZES §4.1, §5.2, §8.2, §10) в одному місці: блок 3f,
/// екран «Призи» і картка мають говорити однаково, а VoiceOver — повними словами.
struct PrizePresenter {
    let calendar: CalendarService
    /// Кінець буста, увімкненого в цю мить, — `GamificationService.boostExpiry(activatedAt:)`.
    let boostExpiry: (Date) -> Date

    static let freezeDetails = "Пропущений день не обірве серію. Серія збережеться, але не зросте"
    static let boostDetails = "Увесь XP до кінця дня — удвічі. Множиться разом із бонусом серії"

    // MARK: - Рядок стосу

    /// Підпис пояснює, *що буде*, а не повторює назву. `isWarning` — є що рятувати.
    func rowSubtitle(_ stack: PrizeStack) -> (text: String, isWarning: Bool) {
        switch stack.key {
        case RewardCatalog.freezeKey:
            if case .yesterday(let streak) = stack.freezeTarget {
                return ("Можна врятувати серію \(Self.days(streak))", true)
            }
            return ("Збереже серію, якщо пропустиш день", false)
        default:
            return ("×2 XP до кінця дня", false)
        }
    }

    func rowAccessibilityValue(_ stack: PrizeStack) -> String {
        stack.isNew ? "\(stack.count) шт., нове" : "\(stack.count) шт."
    }

    // MARK: - Діючий буст

    /// «⚡ ×2 XP · » — пігулка в заголовку 3f; залишок іде окремим шрифтом.
    func pillLabel(_ prize: RewardSnapshot) -> String { "\(prize.emoji) ×2 XP · " }

    /// «×2 XP · діє до 00:00» — підпис hero-картки.
    func activeSubtitle(_ prize: RewardSnapshot) -> String {
        "×2 XP · діє до \(clockTime(prize.expiresAt))"
    }

    func activeAccessibilityLabel(_ prize: RewardSnapshot) -> String { "Діє: \(prize.title)" }

    func activeAccessibilityValue(_ prize: RewardSnapshot, at now: Date) -> String {
        "ще \(Self.longDuration(prize.remaining(at: now)))"
    }

    // MARK: - Картка

    func detail(for selection: PrizeSelection, inventory: PrizeInventory, at now: Date) -> PrizeDetailContent {
        switch selection {
        case .active(let prize):
            let details = "Діє до \(clockTime(prize.expiresAt))"
            let remaining = prize.remaining(at: now)
            return PrizeDetailContent(
                emoji: prize.emoji, title: prize.title, count: 1, details: details,
                status: .timer(Self.shortDuration(remaining)), action: nil,
                accessibilityValue: "\(details). Залишилось \(Self.longDuration(remaining))"
            )
        case .stack(let stack) where stack.key == RewardCatalog.freezeKey:
            return freezeDetail(stack)
        case .stack(let stack):
            return boostDetail(stack, inventory: inventory, at: now)
        }
    }

    private func freezeDetail(_ stack: PrizeStack) -> PrizeDetailContent {
        let status: WTPrizeDetailStatus
        let action: WTPrizeDetailAction
        let statusText: String?
        switch stack.freezeTarget ?? .today {
        case .yesterday(let streak):
            statusText = "Серія \(Self.days(streak)) збережеться"
            status = .warning(statusText!)
            action = WTPrizeDetailAction(title: "Заморозити вчора")
        case .today:
            statusText = "Якщо все ж закриєш норму — заморозка повернеться"
            status = .note(statusText!)
            action = WTPrizeDetailAction(title: "Заморозити сьогодні")
        case .todayAlreadyCounted:
            statusText = nil
            status = .none
            action = WTPrizeDetailAction(
                title: "Сьогодні вже зараховано", isEnabled: false,
                disabledHint: "Сьогоднішній день уже в серії — заморожувати нічого"
            )
        }
        return PrizeDetailContent(
            emoji: stack.oldest.emoji, title: stack.oldest.title, count: stack.count,
            details: Self.freezeDetails, status: status, action: action,
            accessibilityValue: Self.join(["\(stack.count) шт.", Self.freezeDetails, statusText])
        )
    }

    private func boostDetail(_ stack: PrizeStack, inventory: PrizeInventory, at now: Date) -> PrizeDetailContent {
        let title = "Увімкнути на \(Self.compactDuration(boostExpiry(now).timeIntervalSince(now)))"
        let running = inventory.active.first
        let statusText = running.map { "Уже діє до \(clockTime($0.expiresAt))" }
        return PrizeDetailContent(
            emoji: stack.oldest.emoji, title: stack.oldest.title, count: stack.count,
            details: Self.boostDetails,
            status: statusText.map(WTPrizeDetailStatus.info) ?? .none,
            action: WTPrizeDetailAction(
                title: title, isEnabled: running == nil,
                disabledHint: running == nil ? nil : "Одночасно діє лише один буст"
            ),
            accessibilityValue: Self.join(["\(stack.count) шт.", Self.boostDetails, statusText])
        )
    }

    // MARK: - Формат часу

    /// «00:00» у локальному часовому поясі застосунку.
    func clockTime(_ date: Date?) -> String {
        guard let date else { return "00:00" }
        let parts = calendar.calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
    }

    /// Хвилини округлюються вгору: за 30 с до кінця показуємо «0:01», а не «0:00», яке
    /// читалось би як «вже скінчився».
    static func minutes(_ interval: TimeInterval) -> Int {
        max(0, Int((interval / 60).rounded(.up)))
    }

    /// «3:20» — таймер.
    static func shortDuration(_ interval: TimeInterval) -> String {
        let total = minutes(interval)
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    /// «3 год 20 хв» — у кнопці, де місця на повні слова немає.
    static func compactDuration(_ interval: TimeInterval) -> String {
        let total = minutes(interval)
        let (hours, mins) = (total / 60, total % 60)
        if hours == 0 { return "\(mins) хв" }
        return mins == 0 ? "\(hours) год" : "\(hours) год \(mins) хв"
    }

    /// «3 години 20 хвилин» — для VoiceOver, який «3:20» читає як час доби.
    static func longDuration(_ interval: TimeInterval) -> String {
        let total = minutes(interval)
        let (hours, mins) = (total / 60, total % 60)
        let h = "\(hours) \(plural(hours, "година", "години", "годин"))"
        let m = "\(mins) \(plural(mins, "хвилина", "хвилини", "хвилин"))"
        if hours == 0 { return m }
        return mins == 0 ? h : "\(h) \(m)"
    }

    static func days(_ count: Int) -> String {
        "\(count) \(plural(count, "день", "дні", "днів"))"
    }

    static func plural(_ n: Int, _ one: String, _ few: String, _ many: String) -> String {
        let (mod10, mod100) = (n % 10, n % 100)
        if mod10 == 1 && mod100 != 11 { return one }
        if (2...4).contains(mod10) && !(12...14).contains(mod100) { return few }
        return many
    }

    private static func join(_ parts: [String?]) -> String {
        parts.compactMap { $0 }.joined(separator: ". ")
    }
}

/// Картка призу поверх екрана — з таймером, що тікає раз на хвилину.
///
/// Час для таймера береться з `Clock` (через модель), а не з `context.date`
/// `TimelineView` — інакше `FixedClock` у тестах і демо розходився б із картинкою.
struct PrizeDetailModal: View {
    let model: PrizeInventoryModel
    let selection: PrizeSelection

    var body: some View {
        TimelineView(.periodic(from: model.now, by: 60)) { _ in
            let content = model.presenter.detail(for: selection, inventory: model.inventory, at: model.now)
            WTPrizeDetail(
                emoji: content.emoji, title: content.title, count: content.count,
                details: content.details, status: content.status, action: content.action,
                accessibilityValue: content.accessibilityValue,
                onAction: { model.performSelectedAction() },
                onClose: { model.select(nil) }
            )
        }
        .zIndex(10)
    }
}
