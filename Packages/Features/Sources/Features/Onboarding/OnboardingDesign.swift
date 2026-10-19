import Foundation

/// Дизайн онбордингу — **тимчасовий** перемикач (рішення від 19.10.2026, SPEC-ONBOARDING §10): обидва варіанти
/// подобаються, остаточний вибір — у WAT-57. Тоді перемикач, цей файл і другий каркас прибираються.
///
/// `UserDefaults`, а не поле `UserProfile`: тимчасове налаштування не має лишити по собі колонку в схемі SwiftData.
public enum OnboardingDesign: String, CaseIterable, Sendable {
    /// Угорі жива ілюстрація кроку, унизу — питання на панелі.
    case scene
    /// Світлий екран, картки варіантів, смуга прогресу з розділів.
    case steps

    var title: String {
        switch self {
        case .scene: return "Сцена"
        case .steps: return "Кроки"
        }
    }

    private static let key = "onboarding.design"

    public static var current: OnboardingDesign {
        get { UserDefaults.standard.string(forKey: key).flatMap(OnboardingDesign.init(rawValue:)) ?? .scene }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: key) }
    }
}
