import Foundation
import Core
import Persistence
import Gamification
import Notifications

/// Тексти режиму розробника (WAT-68). Об'єм — завжди в мілілітрах, хоч яка система в профілі: так він зберігається, і
/// розробник бачить те саме число, що в базі й тестах.
enum DeveloperPresenter {
    /// «+1 д 3 год», «−45 хв», «без зсуву».
    static func clockOffset(_ seconds: TimeInterval) -> String {
        let minutes = Int((abs(seconds) / 60).rounded())
        guard minutes > 0 else { return "без зсуву" }
        let days = minutes / (24 * 60), hours = minutes / 60 % 24, rest = minutes % 60
        let parts = [days > 0 ? "\(days) д" : nil, hours > 0 ? "\(hours) год" : nil, rest > 0 ? "\(rest) хв" : nil]
        return (seconds < 0 ? "−" : "+") + parts.compactMap { $0 }.joined(separator: " ")
    }

    /// «Пн, 26 жовтня · 08:30».
    static func moment(_ date: Date, calendar: CalendarService, format: TimeFormat) -> String {
        "\(day(calendar.dayKey(for: date))) · \(format.clock(calendar.minuteOfDay(date)))"
    }

    /// «Пн, 26 жовтня».
    static func day(_ day: DayKey) -> String {
        "\(ReportFormat.weekdayShort(day.weekdayIndex)), \(day.day) \(ReportFormat.monthGenitive(day.month))"
    }

    /// «сьогодні», «учора», «5 днів тому».
    static func dayDistance(_ day: DayKey, today: DayKey) -> String {
        let days = today.ordinal - day.ordinal
        switch days {
        case 0: return "сьогодні"
        case 1: return "учора"
        default: return "\(ReportFormat.daysWord(days, withNumber: true)) тому"
        }
    }

    static func ml(_ ml: Int) -> String { "\(ml) мл" }

    /// «1250 / 2000 мл · 63 %» — зараховане проти норми; понад стелю — ще й фактичне.
    static func volume(total: Int, counted: Int, goal: Int) -> String {
        let pct = goal > 0 ? Int((Double(counted) / Double(goal) * 100).rounded()) : 0
        let base = "\(counted) / \(goal) мл · \(pct) %"
        return total > counted ? base + " (випито \(total))" : base
    }

    static func level(_ progress: LevelProgress) -> String {
        "\(progress.level) · \(progress.xpIntoLevel) / \(progress.xpForNextLevel) XP"
    }

    static func questState(_ state: QuestState) -> String {
        switch state {
        case .active: return "активне"
        case .completed, .claimed: return "виконане"
        case .expired: return "прострочене"
        case .cancelled: return "скасоване"
        }
    }

    static func scope(_ scope: QuestScope) -> String {
        switch scope {
        case .daily: return "Щоденні"
        case .weekly: return "Тижневі"
        case .adhoc: return "Несподівані"
        }
    }

    /// Назва з каталогу ще без параметрів видачі: «Половина до T», «N склянок».
    static func questTemplate(_ title: QuestTitle) -> String {
        title.parts.map { part -> String in
            switch part {
            case .text(let text): return text
            case .time: return "T"
            case .count: return "N"
            case .volume(let ml): return "\(ml) мл"
            case .block, .blockAim: return "блок"
            case .weekday: return "день тижня"
            }
        }.joined()
    }

    static func achievementState(_ achievement: DeveloperAchievement) -> String {
        var marks = [achievement.isUnlocked ? "відкрито" : "\(Int(achievement.value)) / \(Int(achievement.target))"]
        if achievement.isEgg { marks.append("🥚") } else if achievement.isSecret { marks.append("🤫") }
        if achievement.isRetired { marks.append("зняте") }
        marks.append("+\(achievement.rewardXp) XP")
        return marks.joined(separator: " · ")
    }

    static let scheduleDemos: [(ScheduleSuggestionDemo, String)] = [
        (.wakeEarly, "Ранній підйом"), (.wakeLate, "Пізній підйом"), (.sleepLate, "Пізній відбій"),
        (.sleepEarly, "Ранній відбій"), (.both, "Підйом і відбій"), (.weekend, "Вихідні"), (.weekdays, "Будні")
    ]

    static let notificationSamples: [(NotificationSample, String)] = [
        (.reminder, "Нагадування"), (.reminderFollowUp, "Повторне"), (.checkpoint, "Чекпоінт"),
        (.challenge, "Несподіване"), (.morning, "Ранкова склянка"), (.eveningClosable, "Вечір: майже ціль"),
        (.eveningStreak, "Вечір: серія"), (.eveningClose, "Закрити норму"), (.eveningSoothing, "Вечір: без норми"),
        (.rescueMorning, "Порятунок зранку"), (.rescueEvening, "Порятунок увечері"), (.comebackFirst, "Повернення"),
        (.comebackLast, "Повернення: пауза"), (.reportDay, "Звіт дня"), (.reportWeek, "Звіт тижня"),
        (.reportMonth, "Звіт місяця")
    ]

    /// Через скільки прийде зразок: 5 с — побачити банер у застосунку, 30 с — встигнути заблокувати телефон.
    static let notificationDelays = [5, 30]

    static func notificationSent(_ title: String, seconds: Int) -> String {
        seconds == 0 ? "«\(title)» — уже" : "«\(title)» — за \(seconds) с"
    }

    static let notificationDenied = "Немає дозволу на сповіщення — увімкни його в Параметрах iOS"

    static let notificationTaps: [(NotificationType, String)] = [
        (.reminder, "Нагадування"), (.morning, "Ранкова склянка"), (.evening, "Вечірній підсумок"),
        (.rescue, "Порятунок серії"), (.comeback, "Повернення"), (.echo, "Відлуння"), (.report, "Звіт"),
        (.challenge, "Несподіване")
    ]
}
