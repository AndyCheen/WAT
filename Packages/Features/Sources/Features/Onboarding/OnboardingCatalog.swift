import Foundation

/// Крок онбордингу (WAT-56, SPEC-ONBOARDING §3). `rawValue` — частина ідентифікаторів e2e.
public enum OnboardingStep: String, CaseIterable, Sendable {
    case hello, units, gender, age, weight, activity, goal, day, rhythm, glass, reminders, done

    /// Питання — усе між вітанням і фінішем: лише вони мають розділ, номер і «Далі».
    var isQuestion: Bool { self != .hello && self != .done }

    var chapter: OnboardingChapter? {
        switch self {
        case .hello, .done: return nil
        case .units: return .units
        case .gender, .age, .weight, .activity, .goal: return .norm
        case .day, .rhythm: return .day
        case .glass, .reminders: return .reminders
        }
    }
}

/// Розділ — підпис над питанням, сегмент смуги прогресу «Кроків» і тло сцени.
public enum OnboardingChapter: Int, CaseIterable, Sendable {
    case units, norm, day, reminders

    var title: String {
        switch self {
        case .units: return "Одиниці"
        case .norm: return "Норма"
        case .day: return "День"
        case .reminders: return "Нагадування"
        }
    }
}

/// Порядок кроків — лише тут. Онбординг чорновий (склад доводить WAT-57), тож новий крок — рядок у `steps`
/// і його вигляд у `OnboardingStepBody` / `OnboardingSceneArt`, а не правка рушія.
enum OnboardingCatalog {
    static let steps: [OnboardingStep] = [
        .hello, .units, .gender, .age, .weight, .activity, .goal, .day, .rhythm, .glass, .reminders, .done,
    ]

    static var questions: [OnboardingStep] { steps.filter(\.isQuestion) }

    static func steps(in chapter: OnboardingChapter) -> [OnboardingStep] {
        steps.filter { $0.chapter == chapter }
    }
}
