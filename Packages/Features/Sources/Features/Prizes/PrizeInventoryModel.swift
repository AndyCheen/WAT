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

    /// Дані застаріли не через дію на цьому екрані (нова доба, повернення з фону) — екран
    /// слухає це значення й викликає `reload()`.
    public var epoch: Int { services.epoch }

    public private(set) var inventory: PrizeInventory = .empty
    public private(set) var selected: PrizeSelection?
    public private(set) var feedback: PrizeFeedback?
    /// Дію виконано — картка показує підтвердження, а потім закривається сама.
    public private(set) var success: WTPrizeDetailSuccess?
    /// Інвентар на мить дії — з нього картка малює вміст, поки показує підтвердження.
    /// Свіжий інвентар змінив би прихований під підтвердженням текст (у буста з'являється
    /// «Уже діє до 00:00»), і картка змінила б висоту.
    public private(set) var inventoryAtAction: PrizeInventory?

    /// Скільки картка тримає підтвердження: досить, щоб прочитати плашку й побачити
    /// анімацію, але не стільки, щоб довелося закривати руками.
    var successHold: Duration = .milliseconds(1600)
    private var closeTask: Task<Void, Never>?

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

    /// Відкрити картку готового стосу — тап по порятунку серії чи подарунку за повернення
    /// (SPEC-NOTIFICATIONS §12.1, §12.5). Немає такого призу — лишається сам екран.
    public func focus(key: String) {
        guard let stack = inventory.ready.first(where: { $0.key == key }) else { return }
        select(.stack(stack))
    }

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
        if selection == nil {
            closeTask?.cancel()
            closeTask = nil
        }
        withAnimation(WTAnimation.fade) {
            selected = selection
            success = nil
        }
        inventoryAtAction = nil
        if selection == nil { reload() }
    }

    /// Дія з картки. Успіх — підтвердження прямо в картці й автозакриття: раніше картка
    /// зникала одразу, і не було видно, чи приз узагалі спрацював (рев'ю WAT-34).
    /// Невдача (північ змінила ціль заморозки) — картка закривається одразу: повторно
    /// відкрита, вона покаже новий текст (§6.2).
    public func performSelectedAction() {
        guard case .stack(let stack) = selected, success == nil else { return }
        let prizeId = stack.oldest.id
        // Текст підтвердження — за станом до дії: після заморозки «вчора» ціль уже «сьогодні».
        let confirmation = presenter.success(for: stack, at: now)
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
        guard done else {
            select(nil)
            return
        }
        feedback = PrizeFeedback(serial: (feedback?.serial ?? 0) + 1, feedback: haptic)
        services.touch()
        inventoryAtAction = inventory
        withAnimation(WTAnimation.toast) {
            success = confirmation
            reload()
        }
        closeTask?.cancel()
        closeTask = Task { [weak self, successHold] in
            try? await Task.sleep(for: successHold)
            guard !Task.isCancelled else { return }
            self?.select(nil)
        }
    }
}
