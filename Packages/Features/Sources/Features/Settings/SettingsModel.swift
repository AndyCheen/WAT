import Foundation
import Observation
import SwiftUI
import Core
import Persistence
import Hydration

/// Екран «Налаштування» (WAT-15): денна мета, ритм дня, вхід у «Сповіщення», вібрація, тема.
///
/// Головний про зміни не чує напряму — він перечитує себе в `onAppear`, коли до нього повертаються.
@MainActor
@Observable
public final class SettingsModel {
    private let services: AppServices
    public private(set) var goalMl: Int
    /// Кнопки головного — підписом рядка «Кнопки порцій» (WAT-45).
    public private(set) var quickAmounts: [Int]

    /// Пропозиція «Рівні інтервали» — лише щойно після вимикання ритму: нагадування «за темпом»
    /// теж спираються на частини доби, але змінювати їх мовчки не можна, а питати щоразу — набридливо.
    public private(set) var offersIntervalReminders = false

    public init(services: AppServices) {
        self.services = services
        goalMl = services.hydration.currentGoal()
        quickAmounts = services.hydration.quickAddAmounts()
    }

    public func refresh() {
        goalMl = services.hydration.currentGoal()
        quickAmounts = services.hydration.quickAddAmounts()
        Task { await services.notifications.refreshAuthorization() }
    }

    // MARK: - Денна мета

    public var goalLabel: String {
        volumeUnit.format(goalMl) { "\(Volume.litersLabel($0, fractionDigits: 1)) л" }
    }

    /// Підпис кроку мети: «Крок — 100 мл» / «Крок — 4 унц.».
    public var goalStepLabel: String {
        "Крок — " + volumeUnit.portion(volumeUnit.milliliters(units: VolumeSteps.goal(volumeUnit).fine))
    }

    /// ±100 мл або ±4 унц. (`VolumeSteps.goal`, WAT-46).
    public func stepGoal(up: Bool) {
        goalMl = services.hydration.stepGoal(up: up).goalMl
        services.touch()
    }

    // MARK: - Система об'єму (WAT-46)

    public var volumeUnit: VolumeUnit { services.profile.volumeUnit }

    /// Як виглядатимуть числа: «250 мл · 2 л» / «8 унц. · 64 унц.» (64 — звична в США денна норма).
    public var volumeUnitExample: String {
        volumeUnit.isMetric ? "250 мл · 2 л" : [8, 64].map { volumeUnit.portion(volumeUnit.milliliters(units: $0)) }.joined(separator: " · ")
    }

    /// Перемикає систему й переводить кнопки порцій; `touch()` — тексти сповіщень перескладаються одразу.
    public func setVolumeUnit(_ unit: VolumeUnit) {
        services.hydration.setVolumeUnit(unit)
        quickAmounts = services.hydration.quickAddAmounts()
        services.touch()
    }

    public var quickAmountsSummary: String {
        // В унціях позначення одне на всіх: «8 унц. · 16 унц. · 32 унц.» не вміщалось у рядок.
        guard volumeUnit.isMetric else {
            return quickAmounts.map(volumeUnit.number).joined(separator: " · ") + " " + VolumeUnit.ounceSymbol
        }
        return quickAmounts.map { HomeScreen.amountTitle($0, volumeUnit) }.joined(separator: " · ")
    }

    // MARK: - Сповіщення

    public var notificationsSummary: String {
        // Читання `revision` — щоб підпис перечитався, щойно з'ясується статус дозволу.
        _ = services.notifications.revision
        guard services.profile.notificationsEnabled else { return "Вимк." }
        return services.notifications.authorization == .denied ? "Без дозволу" : "Увімк."
    }

    // MARK: - Ритм дня (WAT-42, SPEC-NOTIFICATIONS §28)

    public var dayRhythmEnabled: Bool { services.profile.dayRhythmEnabled }

    /// Вимкнено — режим «просто норма за день»: без чекпоінтів, XP і завдань частин доби, капсули
    /// й частин у звітах. Нарахований XP лишається; увімкнення повертає все з наступної порції.
    public func setDayRhythm(_ enabled: Bool) {
        services.profile.dayRhythmEnabled = enabled
        services.profiles.save()
        let settings = services.notifications.settings
        offersIntervalReminders = !enabled && services.profile.notificationsEnabled
            && settings.remindersEnabled && settings.reminderMode == .pace
        // Перепланування — чекпоінти зникають чи повертаються одразу, а не з наступною порцією.
        services.touch()
    }

    public func switchRemindersToInterval() {
        services.notifications.settings.reminderMode = .interval
        services.profiles.save()
        offersIntervalReminders = false
        services.touch()
    }

    /// Плашка разова: пішли з екрана — пропозиція згоріла.
    public func dismissOffers() {
        offersIntervalReminders = false
    }

    // MARK: - Застосунок

    public func setHaptics(_ enabled: Bool) {
        services.profile.hapticsEnabled = enabled
        services.profiles.save()
    }

    public func setThemeMode(_ mode: ThemeMode) {
        services.profile.themeMode = mode
        services.profiles.save()
    }
}
