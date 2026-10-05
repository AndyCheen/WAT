import SwiftUI

// Вікно «Графік дня» (WAT-41, макет Design/Schedule.html, погоджено варіант A «Час»): іконка частини доби,
// «08:00 → 06:30» і великий крок часу для «Налаштувати». Без дуги, позначок і легенди — перша версія
// макета мала їх забагато.

/// Емодзі в колі — головна картинка вікна.
public struct WTGlyphBadge: View {
    @Environment(\.wtTheme) private var theme
    private let glyph: String

    public init(_ glyph: String) {
        self.glyph = glyph
    }

    public var body: some View {
        Text(glyph)
            .font(.system(size: 46))
            .frame(width: 92, height: 92)
            .background(theme.chip, in: Circle())
            .accessibilityHidden(true)
    }
}

/// Капсула над заголовком — «Лише вихідні».
public struct WTScopePill: View {
    @Environment(\.wtTheme) private var theme
    private let title: String

    public init(_ title: String) {
        self.title = title
    }

    public var body: some View {
        Text(title)
            .font(WTFont.text(13, .black))
            .foregroundStyle(theme.textButton)
            .padding(.horizontal, 12)
            .frame(height: 28)
            .background(theme.chip, in: Capsule())
    }
}

/// «08:00 → 06:30»: старий час блідий і закреслений, новий — великий. Знак частини доби — лише коли
/// рядків два, інакше його вже показує іконка вікна. Ширини колонок фіксовані: цифри Fredoka різної ширини,
/// і два рядки, центровані кожен окремо, «їхали» один відносно одного.
public struct WTTimeChange: View {
    @Environment(\.wtTheme) private var theme
    private let glyph: String?
    private let old: String
    private let new: String
    private let accessibilityText: String

    public init(glyph: String? = nil, old: String, new: String, accessibilityLabel: String) {
        self.glyph = glyph
        self.old = old
        self.new = new
        self.accessibilityText = accessibilityLabel
    }

    public var body: some View {
        HStack(spacing: 14) {
            if let glyph {
                Text(glyph).font(.system(size: 22)).frame(width: 28)
            }
            Text(old)
                .font(WTFont.number(30, .medium))
                .foregroundStyle(theme.textMuted)
                .strikethrough(color: theme.textMuted)
                .frame(width: 82, alignment: .trailing)
            // SF Symbol, а не «→»: у Nunito цього гліфа немає, і система підставляла тонку стрілку.
            Image(systemName: "arrow.right")
                .font(.system(size: 20, weight: .heavy))
                .foregroundStyle(theme.textMuted)
            Text(new)
                .font(WTFont.number(58, .semibold))
                .foregroundStyle(theme.textPrimary)
                .monospacedDigit()
                .frame(width: 152, alignment: .leading)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }
}

/// Великий крок часу «– 06:30 +» — той самий крок 15 хв, що на екрані «Сповіщення», але на весь рядок:
/// у вікні це головний контрол, а не рядок налаштувань.
public struct WTTimeStepper: View {
    @Environment(\.wtTheme) private var theme
    private let glyph: String?
    private let value: String
    private let title: String
    private let identifier: String
    private let onDecrement: () -> Void
    private let onIncrement: () -> Void

    /// `identifier` — для e2e: значення отримує його сам, кнопки — `.minus` / `.plus`
    /// (ідентифікатор на контейнері перекрив би дочірні).
    public init(glyph: String? = nil, value: String, title: String, identifier: String,
                onDecrement: @escaping () -> Void, onIncrement: @escaping () -> Void) {
        self.glyph = glyph
        self.value = value
        self.title = title
        self.identifier = identifier
        self.onDecrement = onDecrement
        self.onIncrement = onIncrement
    }

    public var body: some View {
        HStack(spacing: 14) {
            if let glyph {
                Text(glyph).font(.system(size: 22)).frame(width: 28).accessibilityHidden(true)
            }
            WTStepperButton("–", size: 44, action: onDecrement)
                .accessibilityLabel("\(title) раніше")
                .accessibilityIdentifier("\(identifier).minus")
            Text(value)
                .font(WTFont.number(50, .semibold))
                .foregroundStyle(theme.textPrimary)
                .monospacedDigit()
                .contentTransition(.numericText())
                .frame(minWidth: 150)
                .accessibilityLabel(title)
                .accessibilityValue(value)
                .accessibilityIdentifier(identifier)
            WTStepperButton("+", size: 44, action: onIncrement)
                .accessibilityLabel("\(title) пізніше")
                .accessibilityIdentifier("\(identifier).plus")
        }
    }
}
