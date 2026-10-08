import SwiftUI
import WidgetKit
import DesignSystem

// Спільне для всіх віджетів: кнопки дій, тло, тема, кільце, вода.

/// Як намалювати кнопку дії. У розширенні — `Button(intent:)` (інтенти живуть у цілях, а не в пакеті:
/// Xcode 16 не індексує App Intents у SPM-пакетах, SPEC-WIDGETS §9.2); у DEBUG-галереї застосунку —
/// проста мітка.
public struct WidgetActionButtonFactory: Sendable {
    let make: @MainActor @Sendable (WidgetAction, AnyView) -> AnyView

    public init(_ make: @escaping @MainActor @Sendable (WidgetAction, AnyView) -> AnyView) {
        self.make = make
    }

    public static let label = WidgetActionButtonFactory { _, label in label }
}

private struct WidgetActionButtonKey: EnvironmentKey {
    static let defaultValue = WidgetActionButtonFactory.label
}

private struct WidgetGalleryKey: EnvironmentKey {
    static let defaultValue = false
}

public extension EnvironmentValues {
    var widgetActionButton: WidgetActionButtonFactory {
        get { self[WidgetActionButtonKey.self] }
        set { self[WidgetActionButtonKey.self] = newValue }
    }

    /// В'юшка малюється в DEBUG-галереї застосунку, а не системою: тло й поля — вручну.
    var isWidgetGallery: Bool {
        get { self[WidgetGalleryKey.self] }
        set { self[WidgetGalleryKey.self] = newValue }
    }
}

/// Кнопка, що виконує дію з віджета.
struct WidgetActionButton<Label: View>: View {
    @Environment(\.widgetActionButton) private var factory
    let action: WidgetAction
    @ViewBuilder let label: () -> Label

    init(_ action: WidgetAction, @ViewBuilder label: @escaping () -> Label) {
        self.action = action
        self.label = label
    }

    var body: some View { factory.make(action, AnyView(label())) }
}

public extension View {
    /// Тло віджета. Система кладе його й під поля (`containerBackground`), тож вода «на все тло» доходить до
    /// країв без вимкнення полів. У галереї — те саме вручну: поля 16 pt і заокруглення, як на iPhone.
    func wtWidgetContainer<Background: View>(@ViewBuilder background: () -> Background) -> some View {
        modifier(WidgetContainer(background: background()))
    }

    /// Тема з `colorScheme`: у віджеті немає `WTThemedContainer`, а кольори в'юшок — із `\.wtTheme`.
    func wtWidgetTheme() -> some View { modifier(WidgetTheme()) }
}

private struct WidgetContainer<Background: View>: ViewModifier {
    @Environment(\.isWidgetGallery) private var isGallery
    let background: Background

    func body(content: Content) -> some View {
        if isGallery {
            content
                .padding(WidgetMetrics.margin)
                .background { background }
                .clipShape(RoundedRectangle(cornerRadius: WidgetMetrics.cornerRadius, style: .continuous))
        } else {
            content.containerBackground(for: .widget) { background }
        }
    }
}

private struct WidgetTheme: ViewModifier {
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        content.environment(\.wtTheme, scheme == .dark ? .dark : .light)
    }
}

/// Розміри віджетів iPhone 6.3″ (402 pt) і внутрішні пропорції — щоб числа не розсипались по в'юшках.
public enum WidgetMetrics {
    public static let small = CGSize(width: 170, height: 170)
    public static let medium = CGSize(width: 364, height: 170)
    public static let large = CGSize(width: 364, height: 382)
    public static let margin: CGFloat = 16
    public static let cornerRadius: CGFloat = 22
    static let buttonHeight: CGFloat = 38
    static let gap: CGFloat = 8
}

/// Кільце дня: доріжка звичайна, дуга — акцентна (у тонованому режимі iOS 18 вона береться кольором відтінку).
struct WidgetRing: View {
    @Environment(\.wtTheme) private var theme
    let fraction: Double
    let lineWidth: CGFloat

    var body: some View {
        ZStack {
            Circle().stroke(theme.track, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.001, min(1, fraction)))
                .stroke(LinearGradient(colors: [theme.ringStart, theme.ringEnd], startPoint: .top,
                                       endPoint: UnitPoint(x: 0.4, y: 1)),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .widgetAccentable()
        }
        .padding(lineWidth / 2)
    }
}

/// Тонка смужка прогресу з акцентною заливкою.
struct WidgetBar: View {
    @Environment(\.wtTheme) private var theme
    let fraction: Double
    var isDone = false
    var height: CGFloat = 8
    var highlighted = false

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(theme.track)
                Capsule()
                    .fill(isDone ? AnyShapeStyle(WTColor.success)
                                 : AnyShapeStyle(LinearGradient(colors: [theme.ringStart, theme.ringEnd],
                                                                startPoint: .leading, endPoint: .trailing)))
                    .frame(width: max(height, proxy.size.width * max(0, min(1, fraction))))
                    .opacity(fraction > 0 ? 1 : 0)
                    .widgetAccentable()
            }
        }
        .frame(height: height)
        .overlay {
            if highlighted { Capsule().stroke(theme.accent, lineWidth: 1.5).padding(-2) }
        }
    }
}

/// Поверхня води з хвилею: заповнює прямокутник знизу до частки `fraction`. Хвиля нерухома — новий
/// запис таймлайну раз на 5 хв, і рухома тут лише марнувала б бюджет рендеру.
struct WidgetWaterShape: Shape {
    var fraction: Double
    var amplitude: CGFloat = 4
    var phase: Double = 0.6

    func path(in rect: CGRect) -> Path {
        let level = rect.maxY - rect.height * max(0, min(1, fraction))
        let wavelength = rect.width / 6
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        var x = rect.minX
        while x <= rect.maxX + 2 {
            path.addLine(to: CGPoint(x: x, y: level + sin(x / wavelength + phase) * amplitude))
            x += 3
        }
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// Мітка кнопки порції у віджеті.
struct PortionLabel: View {
    @Environment(\.wtTheme) private var theme
    let title: String
    var prominent = false
    var height: CGFloat = WidgetMetrics.buttonHeight
    var fontSize: CGFloat = 15

    var body: some View {
        Text(title)
            .font(WTFont.text(fontSize, .heavy))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .foregroundStyle(prominent ? Color.white : theme.textButton)
            .frame(maxWidth: .infinity, minHeight: height, maxHeight: height)
            .background(prominent ? theme.accent : theme.button,
                        in: RoundedRectangle(cornerRadius: WTRadius.control, style: .continuous))
            .widgetAccentable(prominent)
    }
}

/// Помаранчева крапля серії з числом — як у шапці головного (WAT-10).
struct StreakBadge: View {
    @Environment(\.wtTheme) private var theme
    let count: Int
    var size: CGFloat = 14

    var body: some View {
        HStack(spacing: 3) {
            WTDropShape().fill(WTColor.orange).frame(width: size, height: size).widgetAccentable()
            Text("\(count)").font(WTFont.number(size + 1, .semibold)).foregroundStyle(WTColor.orange)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Серія \(count)")
    }
}

/// Мала шапка віджета великими літерами.
struct WidgetCaption: View {
    @Environment(\.wtTheme) private var theme
    let text: String
    var color: Color?

    var body: some View {
        Text(text.uppercased())
            .font(WTFont.text(11, .black))
            .kerning(0.3)
            .foregroundStyle(color ?? theme.textMuted)
            .lineLimit(1)
            .truncationMode(.tail)
    }
}

/// «✓ +250 мл · Скасувати» — після тапу по кнопці, ~1 хв (SPEC-WIDGETS §4.1).
struct UndoPanel: View {
    @Environment(\.wtTheme) private var theme
    let undo: WidgetSnapshot.LastAction
    var compact = false
    var onDeep = false

    var body: some View {
        VStack(spacing: compact ? 6 : 8) {
            ZStack {
                Circle().fill(WTColor.success)
                WTIcons.check(color: .white, size: compact ? 14 : 17)
            }
            .frame(width: compact ? 30 : 36, height: compact ? 30 : 36)
            .widgetAccentable()
            Text(WidgetPresenter.addTitle(undo.ml))
                .font(WTFont.number(compact ? 18 : 21, .semibold))
                .foregroundStyle(onDeep ? Color.white : theme.textPrimary)
            WidgetActionButton(.undo(intakeId: undo.intakeId)) {
                Text("Скасувати")
                    .font(WTFont.text(13, .heavy))
                    .foregroundStyle(onDeep ? Color.white : theme.textButton)
                    .padding(.horizontal, 14)
                    .frame(height: 28)
                    .background(onDeep ? Color.white.opacity(0.2) : theme.button, in: Capsule())
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
