import Foundation
import Core

/// Як людина впоралась із завданням раніше — параметр, з яким його видали, і результат (WAT-67).
public struct QuestOutcome: Sendable, Equatable {
    public let key: String
    public let day: DayKey
    public let succeeded: Bool
    public let deadlineMinute: Int?
    public let count: Int?
    public let targetMl: Int?

    public init(key: String, day: DayKey, succeeded: Bool, deadlineMinute: Int? = nil, count: Int? = nil,
                targetMl: Int? = nil) {
        self.key = key
        self.day = day
        self.succeeded = succeeded
        self.deadlineMinute = deadlineMinute
        self.count = count
        self.targetMl = targetMl
    }
}

/// Як людина зазвичай п'є — база адаптивних цілей (WAT-67). Рахується з історії до вчора (`QuestHistory.baseline`).
public struct QuestBaseline: Sendable, Equatable {
    /// Медіана хвилини, коли за день набралось 25 / 50 / 75 / 100 % норми, — з `minDays` днів, коли набралось.
    public var shareMinutes: [Int: Int]
    /// Медіана склянок від 150 мл за активний день і до половини кривої дня.
    public var glasses: Int?
    public var glassesBeforeHalf: Int?
    /// Медіана порції за 7 днів — «склянка» того, хто п'є склянками по 200 мл, а не по 250.
    public var portionMl: Int?
    /// Днів за 14, коли закрито всі три блоки, і днів за 7, коли норму закрито раніше за будь-яке нагадування.
    public var allBlocksDays14: Int
    public var goalAheadDays7: Int

    public init(shareMinutes: [Int: Int] = [:], glasses: Int? = nil, glassesBeforeHalf: Int? = nil, portionMl: Int? = nil,
                allBlocksDays14: Int = 0, goalAheadDays7: Int = 0) {
        self.shareMinutes = shareMinutes
        self.glasses = glasses
        self.glassesBeforeHalf = glassesBeforeHalf
        self.portionMl = portionMl
        self.allBlocksDays14 = allBlocksDays14
        self.goalAheadDays7 = goalAheadDays7
    }

    /// Без історії — цілі як у каталозі, і ніщо не відсіюється.
    public static let none = QuestBaseline(allBlocksDays14: 14, goalAheadDays7: 1)

    /// З кількох днів база — це вже звичка, а не випадок.
    public static let minDays = 3
}

/// Адаптивні завдання (рішення від 25.10.2026, WAT-67, SPEC-QUESTS §12). Ціль — на крок краща за те, як людина
/// зазвичай п'є, а не абсолютна: незмінна планка, яку людина щоразу не бере, лише демотивує. Аудит 60 днів: «5
/// склянок» у того, хто п'є 2–4 рази на день, — 0 з 17; «Норма до T» у того, хто закриває норму щодня, — 0 з 12.
///
/// Сходинки «два вгору — один униз»: перший раз — особиста база (медіана за 14 днів, угору до 30 хв); виконано двічі
/// поспіль на тій самій планці — на крок ближче до ідеалу кривої чи норми, не виконано — на крок легше, інакше планка
/// тримається. Таке правило сходиться до ~70 % успіху: завдання кличе вперед, але здебільшого вдається. «Крок після
/// кожного успіху» в симуляції 60 днів тримав людину біля 30 %: після вдалого дня одразу ставав недосяжним. Провалено
/// кілька разів поспіль — завдання відпочиває 14 днів.
public enum QuestAdaptation {
    /// Крок часу — той самий, що в назвах («до 14:00»).
    public static let stepMinutes = QuestRules.deadlineStepMinutes
    /// Скільки днів результати впливають на сходинку й паузу.
    public static let lookbackDays = 14
    /// Провалів поспіль до паузи: адаптивне має спершу полегшати, решта — одразу.
    public static let adaptiveFailStreak = 3
    public static let fixedFailStreak = 2

    /// Результати ключа за 14 днів, новіші спершу, — від них сходинка.
    public static func recent(_ key: String, in outcomes: [QuestOutcome], today: DayKey) -> [QuestOutcome] {
        outcomes
            .filter { $0.key == key && $0.day < today && today.ordinal - $0.day.ordinal <= lookbackDays }
            .sorted { $0.day > $1.day }
    }

    /// Пауза: останні `streak` результатів — провали. Результати старші за 14 днів не рахуються, тож пауза минає сама.
    public static func isPaused(_ key: String, outcomes: [QuestOutcome], today: DayKey, adaptive: Bool) -> Bool {
        let streak = adaptive ? adaptiveFailStreak : fixedFailStreak
        let list = recent(key, in: outcomes, today: today)
        return list.count >= streak && list.prefix(streak).allSatisfy { !$0.succeeded }
    }

    /// Дедлайн «до T»: від особистої бази до ідеалу `aim`, не пізніше `latest`.
    /// - Parameters:
    ///   - aim: ідеал — хвилина кривої темпу чи особистого дедлайну норми. Раніше за нього не вимагаємо.
    ///   - base: коли людина зазвичай досягає цієї частки; `nil` — історії замало.
    public static func deadline(aim: Int, base: Int?, latest: Int, history: [QuestOutcome]) -> Int {
        let upper = max(aim, latest)
        let start = min(max(aim, base.map(ceilToStep) ?? aim), upper)
        guard let previous = history.first?.deadlineMinute else { return start }
        let next = previous - stepMinutes * direction(history, sameAs: { $0.deadlineMinute == previous })
        return min(max(next, aim), upper)
    }

    /// N склянок чи днів: звичне + 1, далі — сходинкою.
    public static func count(base: Int?, fallback: Int, range: ClosedRange<Int>, history: [QuestOutcome]) -> Int {
        let start = base.map { $0 + 1 } ?? fallback
        guard let previous = history.first?.count else { return clamp(start, range) }
        return clamp(previous + direction(history, sameAs: { $0.count == previous }), range)
    }

    /// +1 — на крок важче (двічі поспіль виконано на тій самій планці), −1 — легше (останнє не виконано), 0 — тримати.
    static func direction(_ history: [QuestOutcome], sameAs: (QuestOutcome) -> Bool) -> Int {
        guard let last = history.first else { return 0 }
        guard last.succeeded else { return -1 }
        return history.count > 1 && history[1].succeeded && sameAs(history[1]) ? 1 : 0
    }

    /// Блок, у якому людина зазвичай п'є менше `personalBlockShare` цілі, стартує зі звичного плюс склянка; ближчий до
    /// цілі — зі звичного плюс пів склянки.
    public static let personalBlockShare = 0.6

    /// Особиста ціль «Закрий блок» — сходинка в пів склянки: виконано — вище, ні — нижче, але не нижче звичного
    /// (униз до 50 мл), тож завдання чергує «утримай» і «ще трохи». Угору до 50 мл; дійшла до межі зарахування —
    /// `nil`, повна ціль. Людина, що вже закриває блок у половині днів (медіана від 90 %), отримує повну ціль одразу.
    public static func blockTarget(median: Double?, block: GoalBlock, glassMl: Int, history: [QuestOutcome]) -> Int? {
        guard let median, median < GoalBlock.reachShare else { return nil }
        let usual = Int((median * Double(block.targetMl)).rounded())
        let step = glassMl / 2
        var target = median < personalBlockShare ? usual + glassMl : usual + step
        if let last = history.first {
            let previous = last.targetMl ?? block.reachedMl
            target = previous + step * direction(history, sameAs: { ($0.targetMl ?? block.reachedMl) == previous })
        }
        let rounded = Int((Double(max(target, usual / 50 * 50)) / 50).rounded(.up)) * 50
        return rounded < block.reachedMl ? rounded : nil
    }

    /// «Склянка після підйому» тому, хто п'є меншими склянками: звична порція, униз до 50 мл, але не менше 150 мл
    /// (поріг «склянки» в кількісних умовах). `nil` — звичайна ціль min(P, 250).
    public static func wakeGlassTarget(portionMl: Int?, glassMl: Int) -> Int? {
        let usual = min(glassMl, QuestRules.wakeGlassCapMl)
        guard let portionMl, portionMl < usual else { return nil }
        return max(QuestRules.glassMinMl, portionMl / 50 * 50)
    }

    static func ceilToStep(_ minute: Int) -> Int {
        (minute + stepMinutes - 1) / stepMinutes * stepMinutes
    }

    static func clamp(_ value: Int, _ range: ClosedRange<Int>) -> Int {
        min(max(value, range.lowerBound), range.upperBound)
    }
}
