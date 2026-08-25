import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Шрифти макета.
///
/// **Важливо про кирилицю.** У самому макеті Fredoka підключена без кириличних підмножин —
/// увесь український текст там де-факто рендериться Nunito, а Fredoka дістається лише
/// цифрам і латиниці. Тому тут так само: Nunito несе весь текст, Fredoka — суто числові
/// акценти (відсоток на кільці, номер рівня, лічильники). Це відтворює макет точніше,
/// ніж «Fredoka скрізь», де кирилиця провалювалась би в системний шрифт посеред рядка.
public enum WTFont {
    public enum Family {
        /// Nunito — заголовки, кнопки, рядки, підписи (має кирилицю).
        case text
        /// Fredoka — тільки цифри й латиниця: великі показники та номери рівнів.
        case number

        var names: [(weight: Font.Weight, name: String)] {
            switch self {
            case .text:
                return [
                    (.light, "Nunito-Light"), (.regular, "Nunito-Regular"), (.medium, "Nunito-Medium"),
                    (.semibold, "Nunito-SemiBold"), (.bold, "Nunito-Bold"),
                    (.heavy, "Nunito-ExtraBold"), (.black, "Nunito-Black")
                ]
            case .number:
                return [
                    (.light, "Fredoka-Light"), (.regular, "Fredoka-Regular"), (.medium, "Fredoka-Medium"),
                    (.semibold, "Fredoka-SemiBold"), (.bold, "Fredoka-Bold")
                ]
            }
        }

        var fallbackDesign: Font.Design { .rounded }
    }

    public static func font(_ family: Family, size: CGFloat, weight: Font.Weight) -> Font {
        if let name = resolvedName(family, weight: weight) {
            return .custom(name, size: size)
        }
        return .system(size: size, weight: weight, design: family.fallbackDesign)
    }

    /// Заголовки, назви карток, кнопки, рядки списків.
    public static func display(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> Font {
        font(.text, size: size, weight: weight == .semibold ? .bold : weight)
    }

    /// Підписи, легенди, службові лейбли.
    public static func text(_ size: CGFloat, _ weight: Font.Weight = .bold) -> Font {
        font(.text, size: size, weight: weight)
    }

    /// Великі числові акценти — єдине місце, де працює Fredoka.
    public static func number(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> Font {
        font(.number, size: size, weight: weight)
    }

    /// Чи зареєстровані бандловані гарнітури (використовується в тестах і дизайн-QA).
    public static func isBundled(_ family: Family) -> Bool {
        resolvedName(family, weight: .bold) != nil
    }

    private static func resolvedName(_ family: Family, weight: Font.Weight) -> String? {
        #if canImport(UIKit)
        let candidates = family.names
        if let exact = candidates.first(where: { $0.weight == weight })?.name,
           UIFont(name: exact, size: 12) != nil {
            return exact
        }
        // Найближча доступна нарізка, якщо саме цієї ваги немає.
        for candidate in candidates.reversed() where UIFont(name: candidate.name, size: 12) != nil {
            return candidate.name
        }
        #endif
        return nil
    }
}

public extension View {
    /// Обмеження масштабування тексту: макет розрахований на фіксовану сітку 402 pt.
    /// Повна підтримка Dynamic Type — окрема задача після MVP (PLAN.md §6).
    func wtTypeSizeLimit() -> some View {
        self.dynamicTypeSize(...DynamicTypeSize.xLarge)
    }
}
