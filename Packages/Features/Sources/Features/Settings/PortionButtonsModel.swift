import Foundation
import Observation
import Core
import Persistence
import Hydration

/// Екран «Кнопки порцій» (WAT-45): три кнопки головного й чотири підказки шторки «Інше».
///
/// Головний перечитує себе в `onAppear`, тож зміни видно, щойно до нього повернуться.
@MainActor
@Observable
public final class PortionButtonsModel {
    private let services: AppServices
    public private(set) var homeAmounts: [Int] = []
    public private(set) var sheetAmounts: [Int] = []

    public init(services: AppServices) {
        self.services = services
        reload()
    }

    public func reload() {
        homeAmounts = services.hydration.quickAddAmounts(.home)
        sheetAmounts = services.hydration.quickAddAmounts(.customSheet)
    }

    public func amounts(_ place: PresetPlace) -> [Int] {
        place == .home ? homeAmounts : sheetAmounts
    }

    public func step(_ place: PresetPlace, at index: Int, up: Bool) {
        services.hydration.stepPreset(place, at: index, by: up ? PresetRules.stepMl : -PresetRules.stepMl)
        reload()
    }

    /// «Повернути типові» — лише коли є що повертати.
    public func isDefault(_ place: PresetPlace) -> Bool {
        amounts(place) == place.defaults
    }

    public func reset(_ place: PresetPlace) {
        services.hydration.resetPresets(place)
        reload()
    }
}
