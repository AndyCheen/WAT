import SwiftUI

// Будівельні блоки екрана налаштувань (екран «Сповіщення», SPEC-NOTIFICATIONS §15.1).
// Макету екрана ще немає (окрема дизайн-задача) — блоки зібрані з токенів шторки
// налаштувань на 1a, щоб екран виглядав її продовженням.

/// Рядок налаштування: назва (і підпис) ліворуч, контрол праворуч.
public struct WTSettingRow<Control: View>: View {
    @Environment(\.wtTheme) private var theme
    private let title: String
    private let subtitle: String?
    private let control: Control

    public init(_ title: String, subtitle: String? = nil, @ViewBuilder control: () -> Control) {
        self.title = title
        self.subtitle = subtitle
        self.control = control()
    }

    public var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(WTFont.text(16, .bold))
                    .foregroundStyle(theme.textPrimary)
                if let subtitle {
                    Text(subtitle)
                        .font(WTFont.text(13, .semibold))
                        .foregroundStyle(theme.textMuted)
                }
            }
            Spacer(minLength: 8)
            control
        }
        .padding(.vertical, 8)
    }
}

/// Рядок-перехід: назва, значення праворуч і шеврон. Увесь рядок — одна кнопка.
public struct WTNavigationRow: View {
    @Environment(\.wtTheme) private var theme
    private let title: String
    private let value: String?
    private let action: () -> Void

    public init(_ title: String, value: String? = nil, action: @escaping () -> Void) {
        self.title = title
        self.value = value
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(title)
                    .font(WTFont.text(17, .bold))
                    .foregroundStyle(theme.textPrimary)
                Spacer(minLength: 8)
                if let value {
                    Text(value)
                        .font(WTFont.text(15, .bold))
                        .foregroundStyle(theme.textMuted)
                }
                WTIcons.chevronRight(color: theme.textMuted, size: 13)
            }
            .padding(.vertical, 6)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(WTPressStyle(scale: 0.98))
    }
}

/// «–  08:00  +» — компактний степер значення для часу й об'єму.
public struct WTValueStepper: View {
    @Environment(\.wtTheme) private var theme
    private let value: String
    private let identifier: String
    private let onDecrement: () -> Void
    private let onIncrement: () -> Void

    /// `identifier` — для e2e: значення отримує його сам, кнопки — `.minus` / `.plus`
    /// (ідентифікатор на контейнері перекрив би дочірні).
    public init(_ value: String, identifier: String, onDecrement: @escaping () -> Void, onIncrement: @escaping () -> Void) {
        self.value = value
        self.identifier = identifier
        self.onDecrement = onDecrement
        self.onIncrement = onIncrement
    }

    public var body: some View {
        HStack(spacing: 10) {
            WTStepperButton("–", size: 34, action: onDecrement)
                .accessibilityIdentifier("\(identifier).minus")
            Text(value)
                .font(WTFont.number(18, .semibold))
                .foregroundStyle(theme.textPrimary)
                .monospacedDigit()
                .frame(minWidth: 62)
                .accessibilityIdentifier(identifier)
            WTStepperButton("+", size: 34, action: onIncrement)
                .accessibilityIdentifier("\(identifier).plus")
        }
    }
}

/// Тонка лінія між рядками картки.
public struct WTDivider: View {
    @Environment(\.wtTheme) private var theme
    public init() {}
    public var body: some View {
        Rectangle().fill(theme.line).frame(height: 1)
    }
}

/// Дні тижня для тихого періоду: сім круглих перемикачів «Пн…Нд».
/// Чипи `WTChip` у ряд із семи не вміщуються в ширину картки.
public struct WTWeekdayPicker: View {
    @Environment(\.wtTheme) private var theme
    private let titles: [String]
    private let isSelected: (Int) -> Bool
    private let onToggle: (Int) -> Void
    private let identifierPrefix: String

    public init(titles: [String], isSelected: @escaping (Int) -> Bool, identifierPrefix: String = "weekday",
                onToggle: @escaping (Int) -> Void) {
        self.titles = titles
        self.isSelected = isSelected
        self.identifierPrefix = identifierPrefix
        self.onToggle = onToggle
    }

    public var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(titles.enumerated()), id: \.offset) { index, title in
                let selected = isSelected(index)
                Button { onToggle(index) } label: {
                    Text(title)
                        .font(WTFont.text(13, .heavy))
                        .foregroundStyle(selected ? .white : theme.textPrimary)
                        .frame(width: 36, height: 36)
                        .background(selected ? theme.accent : theme.chip, in: Circle())
                        .frame(minWidth: 40, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(WTPressStyle())
                .accessibilityIdentifier("\(identifierPrefix).\(index)")
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .wtFeedback(.toggle, trigger: titles.indices.map(isSelected))
    }
}

/// Плашка-попередження зі стану, який користувач може виправити: «Сповіщення вимкнені
/// в налаштуваннях iOS · Відкрити», «На паузі до завтра · Відновити».
public struct WTNoticeBanner: View {
    @Environment(\.wtTheme) private var theme
    private let message: String
    private let actionTitle: String
    private let identifier: String
    private let action: () -> Void

    /// `identifier` — на тексті, кнопка — `.action`: на контейнері він перекрив би дочірні.
    public init(_ message: String, actionTitle: String, identifier: String, action: @escaping () -> Void) {
        self.message = message
        self.actionTitle = actionTitle
        self.identifier = identifier
        self.action = action
    }

    public var body: some View {
        HStack(spacing: 12) {
            Text(message)
                .font(WTFont.text(14, .bold))
                .foregroundStyle(theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier(identifier)
            Spacer(minLength: 8)
            WTSectionAction(actionTitle, action: action)
                .accessibilityIdentifier("\(identifier).action")
        }
        .padding(.vertical, 14)
        .padding(.horizontal, WTSpacing.cardPaddingH)
        .background(theme.chip, in: RoundedRectangle(cornerRadius: WTRadius.panel, style: .continuous))
    }
}
