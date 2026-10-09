import Foundation
import Core

/// Усе, що бачать віджети, — одним значенням (SPEC-WIDGETS §9.1).
///
/// Розширення віджетів не відкриває SwiftData: два процеси, що пишуть в одне сховище, дають застарілі
/// дані в застосунку й розбіжні кеші метрик і гейміфікації. Тож пише лише застосунок — наприкінці кожного
/// проходу перепланування сповіщень, — а віджет читає цей знімок і решту рахує сам через `Core`.
///
/// Знімок описує **добу, коли його зроблено**. Нову добу без запуску застосунку віджет проєктує сам
/// (`WidgetDay.resolve`): 0 мл, та сама норма, розклад будні/вихідні.
public struct WidgetSnapshot: Codable, Equatable, Sendable {
    /// Змінюється разом із форматом; старий знімок віджет не читає — показує «відкрий застосунок».
    public static let currentVersion = 1

    public var version: Int
    public var generatedAt: Date
    public var day: DayKey
    /// `VolumeUnit.rawValue` — тексти в системі людини (WAT-46).
    public var unitRaw: Int
    public var goalMl: Int
    public var totalMl: Int
    public var countedMl: Int
    /// Порції цієї доби за часом.
    public var portions: [Portion]
    /// Розклад цієї доби — знімок `DayLog`, як у капсули головного: зміна підйому не переписує минулі дні.
    public var schedule: Schedule
    /// Розклад для доби, яку віджет проєктує сам.
    public var weekday: Schedule
    /// `nil` — вихідні як будні.
    public var weekend: Schedule?
    public var dayRhythmEnabled: Bool
    /// Кнопки головного (`QuickAddPreset.place == .home`) у тому ж порядку.
    public var homeButtons: [Int]
    /// «Моя склянка».
    public var glassMl: Int
    /// Підказки шторки «Інше» (`QuickAddPreset.place == .customSheet`) — вибір «Інше» у віджеті. Необов'язкове:
    /// знімок старішої збірки його не має, і віджет тоді бере типові.
    public var customHints: [Int]?
    public var streak: Streak
    public var level: Level
    public var dailyQuests: [Quest]
    public var weeklyQuests: [Quest]
    /// XP за закриту частину доби — з бустом, як нарахує гейміфікація.
    public var dayPartXp: Int
    public var reserve: HydrationReserve?
    /// Остання порція з віджета, елемента керування чи «Команд» — для «Скасувати» (SPEC-WIDGETS §4.1).
    public var lastAction: LastAction?

    public init(
        generatedAt: Date, day: DayKey, unitRaw: Int = 0, goalMl: Int, totalMl: Int, countedMl: Int,
        portions: [Portion], schedule: Schedule, weekday: Schedule, weekend: Schedule? = nil,
        dayRhythmEnabled: Bool = true, homeButtons: [Int], glassMl: Int, customHints: [Int]? = nil,
        streak: Streak, level: Level,
        dailyQuests: [Quest] = [], weeklyQuests: [Quest] = [], dayPartXp: Int = 10,
        reserve: HydrationReserve? = nil, lastAction: LastAction? = nil
    ) {
        self.version = Self.currentVersion
        self.generatedAt = generatedAt
        self.day = day
        self.unitRaw = unitRaw
        self.goalMl = goalMl
        self.totalMl = totalMl
        self.countedMl = countedMl
        self.portions = portions
        self.schedule = schedule
        self.weekday = weekday
        self.weekend = weekend
        self.dayRhythmEnabled = dayRhythmEnabled
        self.homeButtons = homeButtons
        self.glassMl = glassMl
        self.customHints = customHints
        self.streak = streak
        self.level = level
        self.dailyQuests = dailyQuests
        self.weeklyQuests = weeklyQuests
        self.dayPartXp = dayPartXp
        self.reserve = reserve
        self.lastAction = lastAction
    }

    public struct Portion: Codable, Equatable, Sendable {
        public var id: UUID
        public var at: Date
        public var ml: Int

        public init(id: UUID, at: Date, ml: Int) {
            self.id = id
            self.at = at
            self.ml = ml
        }
    }

    public struct Schedule: Codable, Equatable, Sendable {
        public var wakeMinutes: Int
        public var sleepMinutes: Int

        public init(wakeMinutes: Int, sleepMinutes: Int) {
            self.wakeMinutes = wakeMinutes
            self.sleepMinutes = sleepMinutes
        }

        public init(_ schedule: DaySchedule) {
            self.init(wakeMinutes: schedule.wakeMinutes, sleepMinutes: schedule.sleepMinutes)
        }

        public var daySchedule: DaySchedule { DaySchedule(wakeMinutes: wakeMinutes, sleepMinutes: sleepMinutes) }
    }

    public struct Streak: Codable, Equatable, Sendable {
        /// Довжина серії на момент знімка.
        public var current: Int
        /// Чи зараховано вже сам день знімка (норма або заморозка).
        public var countsToday: Bool

        public init(current: Int, countsToday: Bool) {
            self.current = current
            self.countsToday = countsToday
        }
    }

    public struct Level: Codable, Equatable, Sendable {
        public var level: Int
        public var xpIntoLevel: Int
        public var xpForNextLevel: Int

        public init(level: Int, xpIntoLevel: Int, xpForNextLevel: Int) {
            self.level = level
            self.xpIntoLevel = xpIntoLevel
            self.xpForNextLevel = xpForNextLevel
        }

        public var fraction: Double { xpForNextLevel > 0 ? min(1, Double(xpIntoLevel) / Double(xpForNextLevel)) : 0 }
        public var xpLeft: Int { max(0, xpForNextLevel - xpIntoLevel) }
    }

    public struct Quest: Codable, Equatable, Sendable {
        public var title: String
        /// «Готово», «3/4», «50 %» — `QuestSnapshot.progressLabel`.
        public var progressLabel: String
        public var fraction: Double
        public var isDone: Bool

        public init(title: String, progressLabel: String, fraction: Double, isDone: Bool) {
            self.title = title
            self.progressLabel = progressLabel
            self.fraction = fraction
            self.isDone = isDone
        }
    }

    public struct LastAction: Codable, Equatable, Sendable {
        public var intakeId: UUID
        public var ml: Int
        public var at: Date

        public init(intakeId: UUID, ml: Int, at: Date) {
            self.intakeId = intakeId
            self.ml = ml
            self.at = at
        }
    }
}

extension WidgetSnapshot {
    /// Типові підказки шторки «Інше» — як у `QuickAddPreset` (WAT-45).
    public static let defaultCustomHints = [150, 250, 350, 500]

    public var hints: [Int] { (customHints?.isEmpty == false ? customHints : nil) ?? Self.defaultCustomHints }

    /// Скільки «Скасувати» лишається на віджетах після тапу (SPEC-WIDGETS §4.1).
    public static let undoWindow: TimeInterval = 60

    /// Порція, яку ще можна скасувати з віджета о `date`.
    public func undoable(at date: Date) -> LastAction? {
        guard let lastAction, date >= lastAction.at, date < lastAction.at.addingTimeInterval(Self.undoWindow),
              portions.contains(where: { $0.id == lastAction.intakeId }) else { return nil }
        return lastAction
    }

    /// Той самий зміст, інший час знімка. Такий знімок таймлайнів не перезавантажує: бюджет оновлень у фоні
    /// обмежений, а перепланування сповіщень іде й без змін для віджетів (повернення з фону, фонове оновлення).
    public func sameContent(as other: WidgetSnapshot) -> Bool {
        var a = self, b = other
        a.generatedAt = .distantPast
        b.generatedAt = .distantPast
        return a == b
    }
}
