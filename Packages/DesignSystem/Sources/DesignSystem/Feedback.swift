import SwiftUI

/// Тактильний відгук застосунку.
///
/// Список навмисно короткий і **семантичний**: екран каже «сталося додавання порції»,
/// а не «дай medium impact». Якщо завтра підбір відчуттів зміниться — правиться одне
/// місце, `sensory`, а не тридцять точок виклику.
public enum WTFeedback: Equatable, Sendable {
    /// Звичайний тап по керуючому елементу.
    case tap
    /// Порцію додано — головна дія застосунку.
    case add
    /// Денна норма щойно виконана.
    case goalReached
    /// Новий рівень.
    case levelUp
    /// Порцію знято.
    case remove
    /// Перемикач, вибір у сегментованому контролі.
    case toggle

    var sensory: SensoryFeedback {
        switch self {
        case .tap: return .impact(weight: .light, intensity: 0.7)
        case .add: return .impact(weight: .medium)
        case .goalReached: return .success
        case .levelUp: return .success
        case .remove: return .impact(flexibility: .rigid, intensity: 0.8)
        case .toggle: return .selection
        }
    }
}

private struct WTHapticsEnabledKey: EnvironmentKey {
    static let defaultValue = true
}

public extension EnvironmentValues {
    /// Глобальний вимикач гаптики — живиться з `UserProfile.hapticsEnabled`.
    /// Інжектиться один раз на корені (`WTThemedContainer`), тож окремі екрани
    /// про налаштування не знають.
    var wtHapticsEnabled: Bool {
        get { self[WTHapticsEnabledKey.self] }
        set { self[WTHapticsEnabledKey.self] = newValue }
    }
}

private struct WTFeedbackModifier<Trigger: Equatable>: ViewModifier {
    @Environment(\.wtHapticsEnabled) private var isEnabled
    let trigger: Trigger
    let feedback: (Trigger) -> WTFeedback?

    func body(content: Content) -> some View {
        content.sensoryFeedback(trigger: trigger) { _, new in
            guard isEnabled, let value = feedback(new) else { return nil }
            return value.sensory
        }
    }
}

public extension View {
    /// Тактильний відгук на зміну `trigger`. Мовчить, якщо гаптику вимкнено в налаштуваннях.
    func wtFeedback<Trigger: Equatable>(
        trigger: Trigger,
        _ feedback: @escaping (Trigger) -> WTFeedback?
    ) -> some View {
        modifier(WTFeedbackModifier(trigger: trigger, feedback: feedback))
    }

    /// Коротка форма: одне й те саме відчуття на будь-яку зміну значення.
    func wtFeedback<Trigger: Equatable>(_ feedback: WTFeedback, trigger: Trigger) -> some View {
        modifier(WTFeedbackModifier(trigger: trigger, feedback: { _ in feedback }))
    }
}

/// Стиль натискання: кнопка «просідає» під пальцем.
///
/// До цього весь застосунок сидів на `.buttonStyle(.plain)`, тобто дотик не мав
/// жодної візуальної відповіді. Застосовується всередині компонентів `DesignSystem`,
/// щоб екрани лишалися без правок.
public struct WTPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let scale: CGFloat
    private let opacity: Double

    /// - Parameter scale: для дрібних кнопок 0.96, для великих рядків і карток — ближче до 1.
    public init(scale: CGFloat = 0.96, opacity: Double = 0.9) {
        self.scale = scale
        self.opacity = opacity
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            // При ввімкненому Reduce Motion лишається тільки зміна прозорості.
            .scaleEffect(configuration.isPressed && !reduceMotion ? scale : 1)
            .opacity(configuration.isPressed ? opacity : 1)
            .animation(WTAnimation.press, value: configuration.isPressed)
    }
}
