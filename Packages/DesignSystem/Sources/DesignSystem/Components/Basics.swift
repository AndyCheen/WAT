import SwiftUI

/// Біла картка з радіусом 24 і мʼякою тінню — основа екрана 4a.
public struct WTCard<Content: View>: View {
    @Environment(\.wtTheme) private var theme
    private let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        content
            .padding(.vertical, WTSpacing.cardPaddingV)
            .padding(.horizontal, WTSpacing.cardPaddingH)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.card, in: RoundedRectangle(cornerRadius: WTRadius.card, style: .continuous))
            .wtShadow(.card)
    }
}

/// Службовий заголовок секції: «ЗАВДАННЯ НА СЬОГОДНІ», «ПРИЗИ».
public struct WTSectionLabel: View {
    @Environment(\.wtTheme) private var theme
    private let title: String
    private let size: CGFloat
    private let color: Color?

    public init(_ title: String, size: CGFloat = 13, color: Color? = nil) {
        self.title = title
        self.size = size
        self.color = color
    }

    public var body: some View {
        Text(title)
            .font(WTFont.text(size, .heavy))
            .tracking(0.3)
            .foregroundStyle(color ?? theme.textMuted)
    }
}

/// Текстова дія праворуч у заголовку секції: «Всі», «Виконані · 2», «Сховати».
///
/// Окремий компонент, бо той самий вигляд потрібен уже в трьох секціях, а у
/// Feature-шарі шрифтам і масштабу натискання не місце.
public struct WTSectionAction: View {
    @Environment(\.wtTheme) private var theme
    private let title: String
    private let action: () -> Void

    public init(_ title: String, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Text(title)
                .font(WTFont.text(14, .heavy))
                .foregroundStyle(theme.accent)
        }
        .buttonStyle(WTPressStyle(scale: 0.97))
    }
}

/// Кругла кнопка-іконка (38 / 42 / 26 pt у макетах).
public struct WTCircleButton: View {
    @Environment(\.wtTheme) private var theme
    private let size: CGFloat
    private let background: Color?
    private let action: () -> Void
    private let icon: AnyView

    public init<Icon: View>(
        size: CGFloat = 38,
        background: Color? = nil,
        action: @escaping () -> Void,
        @ViewBuilder icon: () -> Icon
    ) {
        self.size = size
        self.background = background
        self.action = action
        self.icon = AnyView(icon())
    }

    public var body: some View {
        Button(action: action) {
            icon
                .frame(width: size, height: size)
                .background(background ?? theme.chip, in: Circle())
        }
        .buttonStyle(WTPressStyle())
    }
}

/// Головна кнопка: акцентний фон, радіус 20, шрифт Fredoka 18.
public struct WTPrimaryButton: View {
    @Environment(\.wtTheme) private var theme
    private let title: String
    private let background: Color?
    private let action: () -> Void

    public init(_ title: String, background: Color? = nil, action: @escaping () -> Void) {
        self.title = title
        self.background = background
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Text(title)
                .font(WTFont.display(18, .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 17)
                .background(background ?? theme.accent, in: RoundedRectangle(cornerRadius: WTRadius.primaryButton, style: .continuous))
        }
        .buttonStyle(WTPressStyle())
    }
}

/// Кнопка швидкого додавання («200 мл», «Інше»).
public struct WTQuickButton: View {
    @Environment(\.wtTheme) private var theme
    private let title: String
    private let isAccent: Bool
    private let action: () -> Void

    public init(_ title: String, isAccent: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.isAccent = isAccent
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Text(title)
                .font(WTFont.display(16, .semibold))
                .foregroundStyle(isAccent ? .white : theme.textButton)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(
                    isAccent ? theme.accent : theme.button,
                    in: RoundedRectangle(cornerRadius: WTRadius.button, style: .continuous)
                )
        }
        .buttonStyle(WTPressStyle())
    }
}

/// Маленький чіп-пресет («150», «250»).
public struct WTChip: View {
    @Environment(\.wtTheme) private var theme
    private let title: String
    private let isSelected: Bool
    private let action: () -> Void

    public init(_ title: String, isSelected: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.isSelected = isSelected
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Text(title)
                .font(WTFont.text(14, .bold))
                .foregroundStyle(isSelected ? .white : theme.textPrimary)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(isSelected ? theme.accent : theme.chip, in: Capsule())
                // Видима капсула лишається 32 pt, як у макеті, але зона дотику
                // добирається до рекомендованих 44 pt прозорим полем.
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(WTPressStyle())
    }
}

/// Круглий степер «–» / «+».
public struct WTStepperButton: View {
    @Environment(\.wtTheme) private var theme
    private let symbol: String
    private let size: CGFloat
    private let action: () -> Void

    public init(_ symbol: String, size: CGFloat = 52, action: @escaping () -> Void) {
        self.symbol = symbol
        self.size = size
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Text(symbol)
                .font(.system(size: size * 0.55, weight: .semibold))
                .foregroundStyle(theme.textButton)
                .frame(width: size, height: size)
                .background(theme.button, in: Circle())
        }
        .buttonStyle(WTPressStyle())
    }
}

/// iOS-подібний перемикач у кольорах макета.
public struct WTToggle: View {
    @Environment(\.wtTheme) private var theme
    @Binding private var isOn: Bool

    public init(isOn: Binding<Bool>) {
        self._isOn = isOn
    }

    public var body: some View {
        Button {
            withAnimation(WTAnimation.toggle) { isOn.toggle() }
        } label: {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule()
                    .fill(isOn ? theme.accent : theme.dotOff)
                    .frame(width: 52, height: 31)
                Circle()
                    .fill(.white)
                    .frame(width: 25, height: 25)
                    .wtShadow(.knob)
                    .padding(.horizontal, 3)
            }
        }
        // Перемикач і так рухається сам — масштабування додаємо ледь помітне.
        .buttonStyle(WTPressStyle(scale: 0.98, opacity: 0.95))
        .wtFeedback(.toggle, trigger: isOn)
    }
}

/// Pill-таби: перемикач періодів і категорій.
public struct WTSegmentedTabs: View {
    @Environment(\.wtTheme) private var theme
    private let titles: [String]
    private let selection: Int
    private let filled: Bool
    private let onSelect: (Int) -> Void

    public init(titles: [String], selection: Int, filled: Bool = false, onSelect: @escaping (Int) -> Void) {
        self.titles = titles
        self.selection = selection
        self.filled = filled
        self.onSelect = onSelect
    }

    public var body: some View {
        HStack(spacing: filled ? 8 : 6) {
            ForEach(Array(titles.enumerated()), id: \.offset) { index, title in
                Button { onSelect(index) } label: {
                    Text(title)
                        .font(WTFont.display(filled ? 14 : 13, .semibold))
                        .foregroundStyle(index == selection ? .white : theme.textPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, filled ? 10 : 10)
                        .background(
                            index == selection ? theme.accent : (filled ? theme.chip : .clear),
                            in: RoundedRectangle(cornerRadius: filled ? WTRadius.control : 11, style: .continuous)
                        )
                }
                .buttonStyle(WTPressStyle())
            }
        }
        .padding(filled ? 0 : 4)
        .background(
            filled ? Color.clear : theme.chip,
            in: RoundedRectangle(cornerRadius: WTRadius.control, style: .continuous)
        )
        .animation(WTAnimation.fade, value: selection)
        .wtFeedback(.toggle, trigger: selection)
    }
}

/// Шапка екрана: кнопка «назад», заголовок по центру, симетричний відступ справа.
public struct WTNavBar: View {
    @Environment(\.wtTheme) private var theme
    private let title: String?
    private let onBack: (() -> Void)?

    public init(title: String? = nil, onBack: (() -> Void)? = nil) {
        self.title = title
        self.onBack = onBack
    }

    public var body: some View {
        HStack {
            if let onBack {
                WTCircleButton(size: 38, action: onBack) {
                    WTIcons.chevronLeft(color: theme.accent, size: 16)
                }
            } else {
                Color.clear.frame(width: 38, height: 38)
            }
            Spacer()
            if let title {
                Text(title)
                    .font(WTFont.display(20, .semibold))
                    .foregroundStyle(theme.textPrimary)
            }
            Spacer()
            Color.clear.frame(width: 38, height: 38)
        }
    }
}
