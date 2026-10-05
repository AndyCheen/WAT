import Foundation
import Observation
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif
import Core
import Persistence
import Notifications

/// Екран «Сповіщення» — рядки етапів A і B (SPEC-NOTIFICATIONS §15.1).
///
/// Профіль і налаштування — моделі SwiftData, тож екран спостерігає їх напряму; модель лише
/// пише зміни, зберігає й просить перепланування (`touch()` — одна дія, одне перепланування).
@MainActor
@Observable
public final class NotificationsSettingsModel {
    private let services: AppServices
    public private(set) var quietPeriods: [QuietPeriod] = []

    public init(services: AppServices) {
        self.services = services
        quietPeriods = services.notifications.quietPeriods()
    }

    var profile: UserProfile { services.profile }
    var settings: NotificationSettings { services.notifications.settings }

    public var authorization: NotificationAuthorization? { services.notifications.authorization }
    /// Змінюється після кожного перепланування — пауза й статус дозволу перечитуються.
    public var revision: Int { services.notifications.revision }
    public var isPaused: Bool { services.notifications.isPaused(at: services.calendar.now) }

    public func refresh() {
        quietPeriods = services.notifications.quietPeriods()
        Task { await services.notifications.refreshAuthorization() }
    }

    // MARK: - Вимикачі

    var master: Binding<Bool> {
        Binding(get: { self.profile.notificationsEnabled },
                set: { self.profile.notificationsEnabled = $0; self.changed(enabling: $0) })
    }

    func toggle(_ keyPath: ReferenceWritableKeyPath<NotificationSettings, Bool>) -> Binding<Bool> {
        Binding(get: { self.settings[keyPath: keyPath] },
                set: { self.settings[keyPath: keyPath] = $0; self.changed(enabling: $0) })
    }

    var weekendSchedule: Binding<Bool> {
        Binding(get: { self.profile.weekendScheduleEnabled },
                set: { self.profile.weekendScheduleEnabled = $0; self.scheduleChanged() })
    }

    /// Збереження + перепланування. Увімкнення будь-якого перемикача, поки системний запит
    /// ще не робили, — привід його зробити: людина сама просить сповіщення (§16.5).
    private func changed(enabling: Bool = false) {
        services.profiles.save()
        services.touch()
        if enabling, services.notifications.authorization == .notDetermined {
            Task { await services.notifications.requestAuthorization() }
        }
    }

    /// Розклад сьогодні — у запис дня, щоб цілі частин доби, XP і звіт бачили нові межі;
    /// минулі дні лишаються зі своїми (WAT-39).
    private func scheduleChanged() {
        services.profiles.save()
        services.hydration.scheduleDidChange()
        changed()
    }

    // MARK: - Режим дня (межі — `DaySchedule`, ті самі, що у вікні «Графік дня»)

    static let timeStep = DaySchedule.stepMinutes

    func stepWake(_ direction: Int, weekend: Bool = false) {
        updateSchedule(weekend: weekend) { $0.steppingWake(direction) }
    }

    func stepSleep(_ direction: Int, weekend: Bool = false) {
        updateSchedule(weekend: weekend) { $0.steppingSleep(direction) }
    }

    private func updateSchedule(weekend: Bool, _ change: (DaySchedule) -> DaySchedule) {
        var week = profile.weekSchedule
        if weekend { week.weekend = change(week.weekend) } else { week.weekday = change(week.weekday) }
        profile.weekSchedule = week
        scheduleChanged()
    }

    func stepGlass(_ direction: Int) {
        profile.glassMl = clamp(profile.glassMl + direction * UserProfile.glassStep,
                                UserProfile.glassRange.lowerBound, UserProfile.glassRange.upperBound)
        // Склянку задали тут — вікно «Склянка» вже не питатиме «скільки в твоїй склянці?» (§7.1).
        profile.glassConfirmed = true
        changed()
    }

    // MARK: - Нагадування

    var reminderModeIndex: Int { settings.reminderMode == .pace ? 0 : 1 }
    func selectReminderMode(_ index: Int) {
        settings.reminderMode = index == 0 ? .pace : .interval
        changed()
    }

    var frequencyIndex: Int { ReminderFrequency.allCases.firstIndex(of: settings.reminderFrequency) ?? 1 }
    func selectFrequency(_ index: Int) {
        settings.reminderFrequency = ReminderFrequency.allCases[index]
        changed()
    }

    var intervalIndex: Int { NotificationSettings.intervalChoices.firstIndex(of: settings.reminderIntervalMinutes) ?? 1 }
    func selectInterval(_ index: Int) {
        settings.reminderIntervalMinutes = NotificationSettings.intervalChoices[index]
        changed()
    }

    // MARK: - Ранок і вечір: «о підйомі / за 2 год до відбою» або свій час

    var morningCustomIndex: Int { settings.morningCustomMinutes == nil ? 0 : 1 }
    func selectMorningCustom(_ index: Int) {
        settings.morningCustomMinutes = index == 0 ? nil : profile.wakeMinutes
        changed()
    }
    func stepMorning(_ direction: Int) {
        let current = settings.morningCustomMinutes ?? profile.wakeMinutes
        settings.morningCustomMinutes = clamp(current + direction * Self.timeStep, profile.wakeMinutes, profile.sleepMinutes - 60)
        changed()
    }

    /// Свій час вечірнього підсумку — 18:00–23:00, але не пізніше відбою (§8).
    var eveningCustomIndex: Int { settings.eveningCustomMinutes == nil ? 0 : 1 }
    func selectEveningCustom(_ index: Int) {
        settings.eveningCustomMinutes = index == 0 ? nil : clamp(profile.sleepMinutes - 120, 18 * 60, 23 * 60)
        changed()
    }
    func stepEvening(_ direction: Int) {
        let current = settings.eveningCustomMinutes ?? profile.sleepMinutes - 120
        settings.eveningCustomMinutes = clamp(current + direction * Self.timeStep, 18 * 60, min(23 * 60, profile.sleepMinutes))
        changed()
    }

    var soundIndex: Int { NotificationSound.allCases.firstIndex(of: settings.sound) ?? 0 }
    func selectSound(_ index: Int) {
        settings.sound = NotificationSound.allCases[index]
        changed()
    }

    // MARK: - Звіти (§11.1): один день тижня, час — крок 15 хв у межах доби

    func selectReportWeekday(_ index: Int) {
        settings.weeklyReportWeekday = index
        changed()
    }

    func stepReportTime(weekly: Bool, _ direction: Int) {
        let current = weekly ? settings.weeklyReportMinutes : settings.monthlyReportMinutes
        let value = clamp(current + direction * Self.timeStep, 0, 24 * 60 - Self.timeStep)
        if weekly { settings.weeklyReportMinutes = value } else { settings.monthlyReportMinutes = value }
        changed()
    }

    // MARK: - Тихі періоди

    func addQuietPeriod() {
        // Пн–Пт 10:00–12:00 — найчастіший випадок «нарада», далі людина підлаштує.
        services.notifications.addQuietPeriod(fromMinutes: 10 * 60, toMinutes: 12 * 60, weekdayMask: 0b0011111)
        quietPeriods = services.notifications.quietPeriods()
        changed()
    }

    func delete(_ period: QuietPeriod) {
        services.notifications.deleteQuietPeriod(period)
        quietPeriods = services.notifications.quietPeriods()
        changed()
    }

    func toggleDay(_ index: Int, of period: QuietPeriod) {
        period.weekdayMask ^= 1 << index
        changed()
    }

    func stepQuiet(_ period: QuietPeriod, from: Bool, _ direction: Int) {
        if from {
            period.fromMinutes = clamp(period.fromMinutes + direction * Self.timeStep, 0, period.toMinutes - Self.timeStep)
        } else {
            period.toMinutes = clamp(period.toMinutes + direction * Self.timeStep, period.fromMinutes + Self.timeStep, 24 * 60)
        }
        changed()
    }

    // MARK: - Пауза й дозвіл

    func resume() {
        services.notifications.resume()
        services.touch()
    }

    /// Плашка «вимкнені в налаштуваннях iOS» веде просто в налаштування сповіщень застосунку.
    func openSystemSettings() {
        #if canImport(UIKit)
        if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
            UIApplication.shared.open(url)
        }
        #endif
    }

    // MARK: - Формат

    static func time(_ minutes: Int) -> String {
        String(format: "%02d:%02d", minutes / 60, minutes % 60)
    }

    private func clamp(_ value: Int, _ low: Int, _ high: Int) -> Int {
        min(max(value, low), max(low, high))
    }
}
