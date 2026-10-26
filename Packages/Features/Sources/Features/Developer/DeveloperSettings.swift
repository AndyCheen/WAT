import Foundation
import SwiftData
import Core
import Persistence

/// Стан режиму розробника між запусками (WAT-68) — у `UserDefaults`, а не в базі: стирання бази його не чіпає, а
/// зсув годинника потрібен раніше, ніж відкриється сховище.
public enum DeveloperSettings {
    /// e2e підміняють сховище на тимчасове: зсув годинника з ручної перевірки не має протікати в сценарії.
    public static var defaults: UserDefaults = .standard

    static let clockOffsetKey = "wt.developer.clockOffset"
    static let pendingResetKey = "wt.developer.pendingReset"

    /// Зсув годинника в секундах — застосунок збирає з ним `OffsetClock` на старті.
    public static var clockOffset: TimeInterval {
        get { defaults.double(forKey: clockOffsetKey) }
        set { defaults.set(newValue, forKey: clockOffsetKey) }
    }

    /// Стирання, яке попросили з режиму розробника, — виконується на наступному запуску (`applyPendingReset`).
    public static var pendingReset: EraseScope? {
        get { defaults.string(forKey: pendingResetKey).flatMap(EraseScope.init(rawValue:)) }
        set { defaults.set(newValue?.rawValue, forKey: pendingResetKey) }
    }

    /// Стерти, поки сховище ще ніхто не читав (`Database.erase`). Повне стирання повертає й справжній час: зсунутий
    /// годинник у «новій установці» лише заплутав би.
    @MainActor
    public static func applyPendingReset(to container: ModelContainer) {
        guard let scope = pendingReset else { return }
        pendingReset = nil
        if scope == .everything { clockOffset = 0 }
        do {
            try Database.erase(scope, in: container.mainContext)
        } catch {
            AppLog.persistence.error("developer reset: \(error)")
        }
    }
}
