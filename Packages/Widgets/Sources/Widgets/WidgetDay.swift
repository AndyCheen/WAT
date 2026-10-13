import Foundation
import Core

/// Стан доби на конкретну хвилину — те, що малює запис таймлайну (SPEC-WIDGETS §9.3).
///
/// Рахується зі знімка через ті самі функції `Core`, що й капсула головного, чекпоінт і XP:
/// `PaceCurve`, `goalBlocks()`, `dayPartProgress`. Якщо доба вже інша, ніж у знімку (застосунок не
/// відкривали після півночі), — проєкція: 0 мл, та сама норма, розклад будні/вихідні.
public struct WidgetDay: Equatable, Sendable {
    public enum Phase: Equatable, Sendable {
        case beforeWake
        case active
        case afterSleep
    }

    /// Блок цілі частини доби з тим, що в ньому випито.
    public struct Block: Equatable, Sendable {
        public enum Position: Equatable, Sendable { case past, current, future }

        public let goal: GoalBlock
        public let drunkMl: Int
        public let position: Position
        /// Скільки блок мав би мати за темпом на цю хвилину: ціль — для минулого, 0 — для майбутнього.
        public let paceMl: Int

        public var isReached: Bool { drunkMl >= goal.targetMl }
        public var fraction: Double { goal.targetMl > 0 ? min(1, Double(drunkMl) / Double(goal.targetMl)) : 1 }
        public var paceFraction: Double { goal.targetMl > 0 ? min(1, Double(paceMl) / Double(goal.targetMl)) : 0 }
    }

    public let date: Date
    public let day: DayKey
    public let minute: Int
    /// Доба спроєктована зі знімка вчорашнього (чи давнішого) дня.
    public let isProjected: Bool
    public let goalMl: Int
    public let countedMl: Int
    public let schedule: DaySchedule
    public let phase: Phase
    public let blocks: [Block]
    /// Поточна частина доби — `nil` до підйому й після відбою.
    public let part: DayPartProgress?
    /// `E(t)` — скільки за темпом мало б бути випито зараз.
    public let expectedMl: Int
    public let dayRhythmEnabled: Bool
    public let reserve: HydrationReserve?
    /// Серія, яку чесно показати: на спроєктованій добі — лише якщо вчорашню норму закрито.
    public let streak: Int?
    /// Завдання — лише доби знімка: нові генерує застосунок.
    public let questsAreCurrent: Bool
    public let undo: WidgetSnapshot.LastAction?
    /// Календар доби — щоб перетворювати моменти на годинник у поясі пристрою.
    public let calendar: Calendar

    public var fraction: Double { goalMl > 0 ? min(1, Double(countedMl) / Double(goalMl)) : 0 }
    /// Як `DaySnapshot.completionPct` — понад 100 % до стелі 120 %.
    public var percent: Int { goalMl > 0 ? Int((Double(countedMl) / Double(goalMl) * 100).rounded()) : 0 }
    public var goalMet: Bool { countedMl >= goalMl }
    public var leftMl: Int { max(0, goalMl - countedMl) }
    /// Відрив від темпу: «+» — випереджаєш. `nil`, коли він нічого не каже: поза активними годинами,
    /// після закритої норми чи з вимкненим ритмом дня.
    public var paceDeltaMl: Int? {
        guard dayRhythmEnabled, phase == .active, !goalMet else { return nil }
        return countedMl - expectedMl
    }

    /// Хвилина доби для моменту — «Пий о 15:24».
    public func minute(of moment: Date) -> Int {
        let parts = calendar.dateComponents([.hour, .minute], from: moment)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }

    public var reserveLevelMl: Double { reserve?.level(at: date) ?? 0 }
    public var reserveFraction: Double { reserve?.fraction(at: date) ?? 0 }
    public var reserveIsEmpty: Bool { reserve?.isEmpty(at: date) ?? true }

    public static func resolve(_ snapshot: WidgetSnapshot, at date: Date, calendar: CalendarService) -> WidgetDay {
        let today = calendar.dayKey(for: date)
        let isProjected = today != snapshot.day
        let portions = isProjected ? [] : snapshot.portions.filter { $0.at <= date }
        let schedule: DaySchedule
        if isProjected {
            let week = calendar.isWeekend(today) ? (snapshot.weekend ?? snapshot.weekday) : snapshot.weekday
            schedule = week.daySchedule
        } else {
            schedule = snapshot.schedule.daySchedule
        }
        let curve = schedule.curve(goalMl: snapshot.goalMl)
        let minute = calendar.minuteOfDay(date)
        let timed = portions.map { TimedPortion(minute: calendar.minuteOfDay($0.at), ml: $0.ml) }
        let total = timed.reduce(0) { $0 + $1.ml }
        let counted = isProjected ? 0 : min(total, snapshot.countedMl)

        let phase: Phase = minute < schedule.wakeMinutes ? .beforeWake
            : minute >= schedule.sleepMinutes ? .afterSleep : .active

        let blocks = curve.goalBlocks().map { goal -> Block in
            let position: Block.Position = minute >= goal.toMinute ? .past
                : minute >= goal.fromMinute ? .current : .future
            let pace: Int
            switch position {
            case .past: pace = goal.targetMl
            case .future: pace = 0
            case .current:
                pace = Int((curve.expected(atMinute: Double(minute)) - curve.expected(atMinute: Double(goal.fromMinute))).rounded())
            }
            return Block(goal: goal, drunkMl: goal.drunkMl(of: timed), position: position, paceMl: pace)
        }

        let streak: Int?
        if !isProjected {
            streak = snapshot.streak.current > 0 ? snapshot.streak.current : nil
        } else if calendar.daysBetween(snapshot.day, today) == 1, snapshot.streak.countsToday {
            streak = snapshot.streak.current
        } else {
            streak = nil
        }

        return WidgetDay(
            date: date, day: today, minute: minute, isProjected: isProjected, goalMl: snapshot.goalMl,
            countedMl: counted, schedule: schedule, phase: phase, blocks: blocks,
            part: curve.dayPartProgress(atMinute: minute, portions: timed),
            expectedMl: Int(curve.expected(atMinute: Double(minute)).rounded()),
            dayRhythmEnabled: snapshot.dayRhythmEnabled,
            reserve: isProjected ? nil : snapshot.reserve,
            streak: streak, questsAreCurrent: !isProjected,
            undo: isProjected ? nil : snapshot.undoable(at: date), calendar: calendar.calendar
        )
    }
}
