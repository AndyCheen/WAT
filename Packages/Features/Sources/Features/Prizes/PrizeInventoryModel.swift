import Foundation
import SwiftUI
import Observation
import DesignSystem
import Gamification

/// Що відкрито в картці призу: готовий стос чи діючий буст.
public enum PrizeSelection: Equatable, Identifiable {
    case stack(PrizeStack)
    case active(RewardSnapshot)

    public var id: String {
        switch self {
        case .stack(let stack): return "stack.\(stack.key)"
        case .active(let prize): return "active.\(prize.id)"
        }
    }

    var emoji: String {
        switch self {
        case .stack(let stack): return stack.oldest.emoji
        case .active(let prize): return prize.emoji
        }
    }
}

/// Тактильний відгук на дію з призом. Лічильник — щоб дві однакові дії поспіль
/// теж змінювали тригер `wtFeedback`.
public struct PrizeFeedback: Equatable {
    let serial: Int
    let feedback: WTFeedback
}

/// Інвентар призів, картка й дія — спільні для блоку 3f і екрана «Призи».
///
/// Одна модель на дві поверхні, а не дві копії: SPEC-PRIZES §9.3 вимагає, щоб A і B
/// не розходились у правилі, а тут, крім розрізу інвентаря, ще й вибір, «нове» і дія.
@MainActor
@Observable
public final class PrizeInventoryModel {
    private let services: AppServices

    public private(set) var inventory: PrizeInventory = .empty
    public private(set) var selected: PrizeSelection?
    public private(set) var feedback: PrizeFeedback?

    public init(services: AppServices) {
        self.services = services
        inventory = services.gamification.prizeInventory()
    }

    public func reload() {
        inventory = services.gamification.prizeInventory()
    }

    /// Для екрана «Призи»: знімок береться до позначення, тож крапки «нове» видно весь
    /// цей візит (та сама схема, що в досягнень, WAT-23).
    public func reloadMarkingSeen() {
        reload()
        services.gamification.markPrizesSeen()
    }

    public var now: Date { services.calendar.now }

    var presenter: PrizePresenter {
        PrizePresenter(calendar: services.calendar, boostExpiry: services.gamification.boostExpiry(activatedAt:))
    }

    // MARK: - Картка

    /// Відкриття картки стосу гасить його крапку «нове». Інвентар перечитується вже
    /// після закриття — під модалкою рядок не має змінюватись.
    public func select(_ selection: PrizeSelection?) {
        if case .stack(let stack) = selection, stack.isNew {
            services.gamification.markPrizesSeen(key: stack.key)
        }
        withAnimation(WTAnimation.fade) { selected = selection }
        if selection == nil { reload() }
    }

    /// Дія з картки. Картка після дії закривається завжди — навіть якщо північ змінила
    /// ціль заморозки: повторно відкрита, вона покаже новий текст (§6.2).
    public func performSelectedAction() {
        guard case .stack(let stack) = selected else { return }
        let prizeId = stack.oldest.id
        let done: Bool
        let haptic: WTFeedback
        switch stack.key {
        case RewardCatalog.freezeKey:
            done = services.gamification.useFreeze(prizeId: prizeId)
            // Серію врятовано — це успіх.
            haptic = .goalReached
        case RewardCatalog.boostKey:
            done = services.gamification.activateBoost(prizeId: prizeId)
            // Увімкнено режим, а не досягнуто мети.
            haptic = .toggle
        default:
            return
        }
        if done {
            feedback = PrizeFeedback(serial: (feedback?.serial ?? 0) + 1, feedback: haptic)
            services.touch()
        }
        withAnimation(WTAnimation.fade) { selected = nil }
        withAnimation(WTAnimation.fade) { reload() }
    }
}
