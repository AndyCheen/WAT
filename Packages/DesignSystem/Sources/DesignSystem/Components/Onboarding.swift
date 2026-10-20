import SwiftUI

// Онбординг (WAT-56, SPEC-ONBOARDING, макет Design/Onboarding.html): контроли кроків і ілюстрації «Сцени».
// Компоненти не знають доменних моделей — лише прості значення. Ілюстрації сцени фарбуються «чорнилом»
// (`wtLearnInk`) за тлом розділу, як у «Знаннях»: той самий малюнок біліє на воді й на нічному небі.
// Чорновий вигляд: графіку доводить WAT-57.

public extension WTTheme {
    /// Тло вибраного варіанта — світлий відтінок акценту; у темній темі — глибокий синій, а не «світіння».
    var choiceSelectedFill: Color { isDark ? Color(hex: "#14263f") : Color(hex: "#eef7ff") }
}

// MARK: - Позначки

/// «ЗАРАЗ» / «ТИПОВО» — поточне значення в повторному проході (SPEC-ONBOARDING §7.2).
public struct WTMarkPill: View {
    @Environment(\.wtTheme) private var theme
    private let text: String
    private let onColor: Bool

    public init(_ text: String, onColor: Bool = false) {
        self.text = text
        self.onColor = onColor
    }

    public var body: some View {
        Text(text.uppercased())
            .font(WTFont.text(10.5, .black))
            .tracking(0.4)
            .foregroundStyle(onColor ? .white : theme.textButton)
            .padding(.horizontal, 8)
            .frame(height: 20)
            .background(onColor ? Color.white.opacity(0.25) : theme.chip, in: Capsule())
            .fixedSize()
    }
}

/// «Було 78 кг · ↺ Як було» під числом, «Зараз» — коли не змінено, або підказка першого запуску.
public struct WTWasLine: View {
    @Environment(\.wtTheme) private var theme
    public enum Content: Equatable {
        case none
        case pill(String)
        case hint(String)
        case was(String, revert: String)
    }

    private let content: Content
    private let onRevert: () -> Void
    private let identifier: String

    public init(_ content: Content, identifier: String, onRevert: @escaping () -> Void = {}) {
        self.content = content
        self.identifier = identifier
        self.onRevert = onRevert
    }

    public var body: some View {
        Group {
            switch content {
            case .none:
                Color.clear.frame(height: 1)
            case .pill(let text):
                WTMarkPill(text)
            case .hint(let text):
                Text(text)
            case let .was(text, revert):
                HStack(spacing: 6) {
                    Text(text)
                    Button {
                        withAnimation(WTAnimation.fade) { onRevert() }
                    } label: {
                        Label(revert, systemImage: "arrow.uturn.backward")
                            .foregroundStyle(theme.textButton)
                    }
                    .buttonStyle(WTPressStyle())
                    .accessibilityIdentifier("\(identifier).revert")
                }
            }
        }
        .font(WTFont.text(13, .heavy))
        .foregroundStyle(theme.textMuted)
        .frame(minHeight: 22)
        .accessibilityIdentifier(identifier)
    }
}

// MARK: - Вибір

/// Варіант-картка: емодзі, назва, підпис і «радіо». Вибраний — рамка акценту й світле тло.
public struct WTChoiceRow: View {
    @Environment(\.wtTheme) private var theme
    private let title: String
    private let subtitle: String?
    private let glyph: String?
    private let badge: String?
    private let isSelected: Bool
    private let action: () -> Void

    public init(_ title: String, subtitle: String? = nil, glyph: String? = nil, badge: String? = nil,
                isSelected: Bool, action: @escaping () -> Void) {
        self.title = title
        self.subtitle = subtitle
        self.glyph = glyph
        self.badge = badge
        self.isSelected = isSelected
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                if let glyph {
                    Text(glyph)
                        .font(.system(size: 21))
                        .frame(width: 42, height: 42)
                        // На вибраному тлі `chip` зливався б із карткою.
                        .background(isSelected ? theme.card : theme.chip, in: Circle())
                        .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(title)
                            .font(WTFont.text(17, .heavy))
                            .foregroundStyle(theme.textPrimary)
                        if let badge { WTMarkPill(badge) }
                    }
                    if let subtitle {
                        Text(subtitle)
                            .font(WTFont.text(13, .bold))
                            .foregroundStyle(theme.textMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .multilineTextAlignment(.leading)
                Spacer(minLength: 8)
                ZStack {
                    Circle()
                        .strokeBorder(isSelected ? theme.accent : theme.dotOff, lineWidth: 2)
                    if isSelected {
                        Circle().fill(theme.accent)
                        WTIcons.check(color: .white, size: 11)
                    }
                }
                .frame(width: 24, height: 24)
                .accessibilityHidden(true)
            }
            .padding(.vertical, 11)
            .padding(.horizontal, 16)
            .frame(minHeight: 60)
            .background(isSelected ? theme.choiceSelectedFill : theme.card,
                        in: RoundedRectangle(cornerRadius: WTRadius.button, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: WTRadius.button, style: .continuous)
                    .strokeBorder(isSelected ? theme.accent : .clear, lineWidth: 2)
            )
            .wtShadow(.card)
            .contentShape(Rectangle())
        }
        .buttonStyle(WTPressStyle(scale: 0.985))
        .animation(WTAnimation.fade, value: isSelected)
        .wtFeedback(.toggle, trigger: isSelected)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

/// Чіп вибору з позначкою поточного: помаранчева крапка — «зараз так» (SPEC-ONBOARDING §7.2).
public struct WTChoiceChip: View {
    @Environment(\.wtTheme) private var theme
    private let title: String
    private let isSelected: Bool
    private let isCurrent: Bool
    private let action: () -> Void

    public init(_ title: String, isSelected: Bool, isCurrent: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.isSelected = isSelected
        self.isCurrent = isCurrent
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Text(title)
                .font(WTFont.text(15, .heavy))
                .foregroundStyle(isSelected ? .white : theme.textButton)
                .padding(.horizontal, 16)
                .frame(height: 42)
                .background(isSelected ? theme.accent : theme.chip, in: Capsule())
                .overlay(alignment: .topTrailing) {
                    if isCurrent {
                        Circle().fill(WTColor.orange).frame(width: 8, height: 8).offset(x: -6, y: 5)
                    }
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(WTPressStyle())
        .animation(WTAnimation.fade, value: isSelected)
        .accessibilityValue(isCurrent ? "зараз так" : "")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

/// Рядок «назва + сегменти»: «Об'єм · Мілілітри | Унції». Поточне — помаранчева крапка на сегменті.
/// Ідентифікатори — на кожному сегменті (`<prefix>.<індекс>`), не на контейнері.
public struct WTSegmentRow: View {
    @Environment(\.wtTheme) private var theme
    private let title: String
    private let options: [String]
    private let selection: Int
    private let current: Int?
    private let identifierPrefix: String
    private let onSelect: (Int) -> Void

    public init(_ title: String, options: [String], selection: Int, current: Int? = nil, identifierPrefix: String,
                onSelect: @escaping (Int) -> Void) {
        self.title = title
        self.options = options
        self.selection = selection
        self.current = current
        self.identifierPrefix = identifierPrefix
        self.onSelect = onSelect
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(WTFont.text(12, .black))
                .tracking(0.4)
                .foregroundStyle(theme.textMuted)
            HStack(spacing: 4) {
                ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                    Button { onSelect(index) } label: {
                        Text(option)
                            .font(WTFont.text(15, .heavy))
                            .foregroundStyle(index == selection ? .white : theme.textButton)
                            .frame(maxWidth: .infinity, minHeight: 42)
                            .background(index == selection ? theme.accent : .clear,
                                        in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                            .overlay(alignment: .topTrailing) {
                                if index == current {
                                    Circle().fill(WTColor.orange).frame(width: 7, height: 7).offset(x: -6, y: 5)
                                }
                            }
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(WTPressStyle())
                    .accessibilityAddTraits(index == selection ? [.isButton, .isSelected] : .isButton)
                    .accessibilityIdentifier("\(identifierPrefix).\(index)")
                }
            }
            .padding(4)
            .background(theme.chip, in: RoundedRectangle(cornerRadius: WTRadius.control, style: .continuous))
        }
        .animation(WTAnimation.fade, value: selection)
        .wtFeedback(.toggle, trigger: selection)
    }
}

/// Колесо цілих чисел — вік. На iOS — системне колесо, у SPM-тестах на macOS його немає.
public struct WTWheelPicker: View {
    @Binding private var value: Int
    private let range: ClosedRange<Int>
    private let isDimmed: Bool
    private let accessibilityTitle: String

    public init(value: Binding<Int>, range: ClosedRange<Int>, isDimmed: Bool = false, accessibilityTitle: String) {
        _value = value
        self.range = range
        self.isDimmed = isDimmed
        self.accessibilityTitle = accessibilityTitle
    }

    public var body: some View {
        Picker(accessibilityTitle, selection: $value) {
            ForEach(Array(range), id: \.self) { number in
                Text("\(number)").font(WTFont.number(24, .semibold)).tag(number)
            }
        }
        #if os(iOS)
        .pickerStyle(.wheel)
        #endif
        .labelsHidden()
        .opacity(isDimmed ? 0.35 : 1)
        .animation(WTAnimation.fade, value: isDimmed)
    }
}

// MARK: - Лінійка

/// Лінійка ваги: прокрутка з прилипанням до поділок, стрілка посередині. `marked` — помаранчева крапка над
/// поточним значенням у повторному проході.
public struct WTRulerPicker: View {
    @Environment(\.wtTheme) private var theme
    @Binding private var value: Int
    private let range: ClosedRange<Int>
    private let marked: Int?
    private let accessibilityTitle: String
    private let accessibilityText: String
    private let identifier: String
    @State private var position: Int?

    private static let tick: CGFloat = 12

    public init(value: Binding<Int>, range: ClosedRange<Int>, marked: Int? = nil, accessibilityTitle: String,
                accessibilityValue: String, identifier: String) {
        _value = value
        self.range = range
        self.marked = marked
        self.accessibilityTitle = accessibilityTitle
        self.accessibilityText = accessibilityValue
        self.identifier = identifier
    }

    public var body: some View {
        GeometryReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 0) {
                    ForEach(Array(range), id: \.self) { number in
                        tick(number).frame(width: Self.tick).id(number)
                    }
                }
                .scrollTargetLayout()
            }
            .contentMargins(.horizontal, (proxy.size.width - Self.tick) / 2, for: .scrollContent)
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $position, anchor: .center)
            .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.28),
                                         .init(color: .black, location: 0.72), .init(color: .clear, location: 1)],
                                 startPoint: .leading, endPoint: .trailing))
            .overlay(alignment: .top) {
                Capsule().fill(theme.accent).frame(width: 4, height: 46).padding(.top, 4).allowsHitTesting(false)
            }
        }
        .frame(height: 76)
        .onAppear { position = value }
        .onChange(of: position) { _, newValue in
            if let newValue, newValue != value { value = newValue }
        }
        .onChange(of: value) { _, newValue in
            if position != newValue { withAnimation(WTAnimation.fade) { position = newValue } }
        }
        .wtFeedback(.toggle, trigger: value)
        .accessibilityElement()
        .accessibilityLabel(accessibilityTitle)
        .accessibilityValue(accessibilityText)
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: value = min(range.upperBound, value + 1)
            case .decrement: value = max(range.lowerBound, value - 1)
            @unknown default: break
            }
        }
        .accessibilityIdentifier(identifier)
    }

    private func tick(_ number: Int) -> some View {
        let major = number % 10 == 0, middle = number % 5 == 0
        return VStack(spacing: 6) {
            Circle()
                .fill(number == marked ? WTColor.orange : .clear)
                .frame(width: 7, height: 7)
            Capsule()
                .fill(major ? theme.textMuted : theme.dotOff)
                .frame(width: 2, height: major ? 34 : middle ? 26 : 16)
                .frame(height: 34, alignment: .top)
            Text(major ? "\(number)" : " ")
                .font(WTFont.number(12, .semibold))
                .foregroundStyle(theme.textMuted)
                .fixedSize()
        }
    }
}

// MARK: - Норма: розклад

/// Смуга складників норми й рядки «Вага 78 кг × 35 мл · 2 730 мл». `onColor` — для сцени на воді.
public struct WTGoalBreakdown: View {
    @Environment(\.wtTheme) private var theme
    public struct Row: Identifiable, Equatable {
        public enum Tone: Equatable { case primary, secondary, extra, outline }
        public let id: String
        public let tone: Tone
        public let title: String
        public let value: String
        /// Частка смуги; 0 — рядок без відрізка (вік зменшує частку ваги, а не додає свою).
        public let weight: Double

        public init(id: String, tone: Tone, title: String, value: String, weight: Double) {
            self.id = id
            self.tone = tone
            self.title = title
            self.value = value
            self.weight = weight
        }
    }

    private let rows: [Row]

    public init(rows: [Row]) { self.rows = rows }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            GeometryReader { proxy in
                let bar = rows.filter { $0.weight > 0 }
                let total = bar.reduce(0) { $0 + $1.weight }
                let gaps = CGFloat(max(0, bar.count - 1)) * 3
                HStack(spacing: 3) {
                    ForEach(bar) { row in
                        color(row.tone).frame(width: max(0, (proxy.size.width - gaps) * row.weight / max(total, 1)))
                    }
                }
            }
            .frame(height: 12)
            .clipShape(Capsule())
            .animation(WTAnimation.ring, value: rows)
            ForEach(rows) { row in
                HStack(spacing: 10) {
                    swatch(row.tone)
                    Text(row.title)
                        .font(WTFont.text(13, .heavy))
                        // `textTertiary` фіксовано світлий — у темній темі він зливався б із карткою.
                        .foregroundStyle(theme.isDark ? theme.textMuted : WTColor.textTertiary)
                    Spacer(minLength: 8)
                    Text(row.value)
                        .font(WTFont.number(14, .semibold))
                        .foregroundStyle(theme.textPrimary)
                        .monospacedDigit()
                }
                .accessibilityElement(children: .combine)
            }
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 16)
        .background(theme.card, in: RoundedRectangle(cornerRadius: WTRadius.button, style: .continuous))
        .wtShadow(.card)
    }

    private func color(_ tone: Row.Tone) -> Color {
        switch tone {
        case .primary: return theme.accent
        case .secondary: return theme.ringStart
        case .extra: return WTColor.orange
        case .outline: return .clear
        }
    }

    @ViewBuilder
    private func swatch(_ tone: Row.Tone) -> some View {
        if tone == .outline {
            RoundedRectangle(cornerRadius: 3).strokeBorder(theme.dotOff, lineWidth: 2).frame(width: 10, height: 10)
        } else {
            RoundedRectangle(cornerRadius: 3).fill(color(tone)).frame(width: 10, height: 10)
        }
    }
}

// MARK: - Підсумок і «Що зміниться»

/// Картка рядків «🎯 Норма · 2.55 л на день». Без змін ⇒ `old == nil`; зі змінами — «2.5 л → 2.95 л».
public struct WTSummaryCard: View {
    @Environment(\.wtTheme) private var theme
    public struct Row: Identifiable, Equatable {
        public let id: String
        public let glyph: String
        public let title: String
        public let value: String
        public let detail: String?
        public let old: String?

        public init(id: String, glyph: String, title: String, value: String, detail: String? = nil, old: String? = nil) {
            self.id = id
            self.glyph = glyph
            self.title = title
            self.value = value
            self.detail = detail
            self.old = old
        }
    }

    private let rows: [Row]
    private let identifierPrefix: String

    public init(rows: [Row], identifierPrefix: String) {
        self.rows = rows
        self.identifierPrefix = identifierPrefix
    }

    public var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                if index > 0 { WTDivider() }
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(row.glyph).font(.system(size: 17)).frame(width: 24).accessibilityHidden(true)
                    Text(row.title)
                        .font(WTFont.text(15, .heavy))
                        .foregroundStyle(theme.textMuted)
                    Spacer(minLength: 8)
                    VStack(alignment: .trailing, spacing: 2) {
                        HStack(spacing: 6) {
                            if let old = row.old {
                                Text(old)
                                    .strikethrough(color: theme.textMuted)
                                    .foregroundStyle(theme.textMuted)
                                // SF Symbol, а не «→»: у Nunito цього гліфа немає (як у `WTTimeChange`).
                                Image(systemName: "arrow.right")
                                    .font(.system(size: 11, weight: .heavy))
                                    .foregroundStyle(theme.textMuted)
                            }
                            Text(row.value).foregroundStyle(theme.textPrimary)
                        }
                        .font(WTFont.text(15, .heavy))
                        if let detail = row.detail {
                            Text(detail).font(WTFont.text(13, .bold)).foregroundStyle(theme.textMuted)
                        }
                    }
                    .multilineTextAlignment(.trailing)
                }
                .padding(.vertical, 12)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("\(identifierPrefix).\(row.id)")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 2)
        .background(theme.card, in: RoundedRectangle(cornerRadius: WTRadius.tile, style: .continuous))
        .wtShadow(.card)
    }
}

/// Дрібний текст-застереження з ⓘ: «не медична порада» (SPEC-ONBOARDING §3.1, тексти — WAT-57).
public struct WTDisclaimer: View {
    @Environment(\.wtTheme) private var theme
    private let text: String

    public init(_ text: String) { self.text = text }

    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "info.circle")
                .font(.system(size: 12, weight: .bold))
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(WTFont.text(12, .bold))
        .foregroundStyle(theme.textMuted)
        .multilineTextAlignment(.leading)
        // Один елемент: ідентифікатор викликача не розійдеться на іконку й текст.
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Прогрес

/// Смуга «Кроків»: сегмент на розділ, ширина — за кількістю його кроків.
public struct WTSegmentedProgress: View {
    @Environment(\.wtTheme) private var theme
    public struct Segment: Equatable {
        public let weight: Int
        public let fraction: Double

        public init(weight: Int, fraction: Double) {
            self.weight = weight
            self.fraction = fraction
        }
    }

    private let segments: [Segment]

    public init(segments: [Segment]) { self.segments = segments }

    public var body: some View {
        GeometryReader { proxy in
            let total = CGFloat(segments.reduce(0) { $0 + $1.weight })
            let gaps = CGFloat(max(0, segments.count - 1)) * 6
            HStack(spacing: 6) {
                ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                    let width = (proxy.size.width - gaps) * CGFloat(segment.weight) / max(total, 1)
                    ZStack(alignment: .leading) {
                        Capsule().fill(theme.track)
                        Capsule().fill(theme.accent).frame(width: width * CGFloat(min(1, max(0, segment.fraction))))
                    }
                    .frame(width: width)
                }
            }
        }
        .frame(height: 6)
        .animation(WTAnimation.ring, value: segments)
        .accessibilityHidden(true)
    }
}

/// Крапки «Сцени»: пройдені яскравіші, поточна — витягнута.
public struct WTPageDots: View {
    private let count: Int
    private let current: Int
    private let color: Color

    /// `current` — від 1; 0 — жодна не поточна.
    public init(count: Int, current: Int, color: Color = .white) {
        self.count = count
        self.current = current
        self.color = color
    }

    public var body: some View {
        HStack(spacing: 5) {
            ForEach(1...max(1, count), id: \.self) { index in
                Capsule()
                    .fill(color.opacity(index == current ? 1 : index < current ? 0.85 : 0.38))
                    .frame(width: index == current ? 20 : 7, height: 7)
            }
        }
        .animation(WTAnimation.sheet, value: current)
        .accessibilityHidden(true)
    }
}

// MARK: - Сцена

/// Каркас «Сцени»: угорі тло розділу з ілюстрацією, знизу — панель із питанням, що наїжджає на сцену.
/// Висота сцени — частка висоти екрана: на iPhone SE і Pro Max пропорції ті самі.
public struct WTSceneLayout<Top: View, Scene: View, Panel: View>: View {
    @Environment(\.wtTheme) private var theme
    private let style: WTStoryStyle
    private let sceneFraction: CGFloat
    private let top: Top
    private let scene: Scene
    private let panel: Panel

    private static var overlap: CGFloat { 30 }

    public init(style: WTStoryStyle, sceneFraction: CGFloat, @ViewBuilder top: () -> Top,
                @ViewBuilder scene: () -> Scene, @ViewBuilder panel: () -> Panel) {
        self.style = style
        self.sceneFraction = sceneFraction
        self.top = top()
        self.scene = scene()
        self.panel = panel()
    }

    public var body: some View {
        GeometryReader { proxy in
            let sceneHeight = proxy.size.height * sceneFraction
            ZStack(alignment: .top) {
                WTStoryBackground(style: style)
                    .animation(WTAnimation.fade, value: style)
                scene
                    .environment(\.wtLearnInk, WTLearnInk.of(style, theme: theme))
                    .frame(maxWidth: .infinity)
                    .frame(height: max(0, sceneHeight - 56 - Self.overlap))
                    .padding(.top, 56)
                top
                panel
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    // Під індикатор «додому» заходить лише тло панелі — кнопки лишаються в безпечній зоні.
                    .background {
                        UnevenRoundedRectangle(topLeadingRadius: WTRadius.sheet, topTrailingRadius: WTRadius.sheet,
                                               style: .continuous)
                            .fill(theme.screen)
                            .wtShadow(.sheet)
                            .ignoresSafeArea(edges: .bottom)
                    }
                    .padding(.top, sceneHeight - Self.overlap)
            }
            .animation(WTAnimation.sheet, value: sceneFraction)
        }
    }
}

/// Кругла кнопка верхньої панелі на кольоровому тлі чи на екрані: «‹» або ✕.
public struct WTBarButton: View {
    @Environment(\.wtTheme) private var theme
    public enum Kind { case back, close }
    private let kind: Kind
    private let onColor: Bool
    private let action: () -> Void

    public init(_ kind: Kind, onColor: Bool, action: @escaping () -> Void) {
        self.kind = kind
        self.onColor = onColor
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Group {
                switch kind {
                case .back: WTIcons.chevronLeft(color: onColor ? .white : theme.accent, size: 16)
                case .close: WTIcons.close(color: onColor ? .white : theme.accent, size: 13)
                }
            }
            .frame(width: 38, height: 38)
            .background(onColor ? Color.white.opacity(0.24) : theme.chip, in: Circle())
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(WTPressStyle())
        .accessibilityLabel(kind == .back ? "Назад" : "Закрити")
    }
}

/// Велике число сцени: «35 мл», «×0.95», «2.55 л». Число змінюється з рухом цифр.
public struct WTSceneNumber: View {
    @Environment(\.wtLearnInk) private var ink
    private let number: String
    private let unit: String?
    private let caption: String?
    private let size: CGFloat
    private let badge: String?

    public init(_ number: String, unit: String? = nil, caption: String? = nil, size: CGFloat = 72, badge: String? = nil) {
        self.number = number
        self.unit = unit
        self.caption = caption
        self.size = size
        self.badge = badge
    }

    public var body: some View {
        VStack(spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(number)
                    .font(WTFont.number(size, .semibold))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                if let unit {
                    Text(unit).font(WTFont.text(size * 0.33, .heavy))
                }
            }
            .animation(WTAnimation.sheet, value: number)
            if caption != nil || badge != nil {
                HStack(spacing: 8) {
                    if let caption { Text(caption).font(WTFont.text(15, .heavy)).opacity(0.92) }
                    if let badge { WTMarkPill(badge, onColor: true) }
                }
            }
        }
        .foregroundStyle(ink.text)
        .multilineTextAlignment(.center)
        .accessibilityElement(children: .combine)
    }
}

/// Плашка на сцені: «+300 мл · вагітність», «+350 мл до норми».
public struct WTSceneBadge: View {
    @Environment(\.wtLearnInk) private var ink
    private let text: String

    public init(_ text: String) { self.text = text }

    public var body: some View {
        Text(text)
            .font(WTFont.text(14, .black))
            .foregroundStyle(ink.text)
            .padding(.horizontal, 15)
            .frame(height: 34)
            .background(ink.badge, in: Capsule())
            .transition(.scale.combined(with: .opacity))
    }
}

/// Підлогові ваги зі стрілкою: `fraction` — місце ваги в діапазоні лінійки.
public struct WTScaleDial: View {
    @Environment(\.wtLearnInk) private var ink
    private let fraction: Double

    public init(fraction: Double) { self.fraction = fraction }

    public var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let center = CGPoint(x: size.width / 2, y: size.height * 0.68)
            let radius = size.width * 0.29
            ZStack {
                RoundedRectangle(cornerRadius: size.height * 0.26, style: .continuous)
                    .fill(ink.empty)
                    .overlay(RoundedRectangle(cornerRadius: size.height * 0.26, style: .continuous)
                        .strokeBorder(ink.soft, lineWidth: 3))
                Path { path in
                    path.addArc(center: center, radius: radius, startAngle: .degrees(200), endAngle: .degrees(340), clockwise: false)
                }
                .stroke(ink.soft, style: StrokeStyle(lineWidth: 6, lineCap: .round, dash: [2, 9]))
                Capsule()
                    .fill(ink.fill)
                    .frame(width: 5, height: radius * 0.92)
                    .offset(y: -radius * 0.46)
                    .rotationEffect(.degrees(-70 + 140 * min(1, max(0, fraction))))
                    .position(center)
                    .animation(.spring(response: 0.45, dampingFraction: 0.6), value: fraction)
                Circle().fill(ink.fill).frame(width: 14, height: 14).position(center)
            }
        }
        .aspectRatio(170 / 102, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

/// Шкала коефіцієнтів віку: відрізки з підписами, поточний — суцільний, трикутник над віком.
public struct WTAgeScale: View {
    @Environment(\.wtLearnInk) private var ink
    public struct Segment: Equatable {
        public let label: String
        public let span: Int
        public let isOn: Bool

        public init(label: String, span: Int, isOn: Bool) {
            self.label = label
            self.span = span
            self.isOn = isOn
        }
    }

    private let segments: [Segment]
    /// Місце віку на шкалі, 0…1; `nil` — вік не вказано.
    private let marker: Double?
    private let ticks: [(label: String, position: Double)]

    public init(segments: [Segment], marker: Double?, ticks: [(label: String, position: Double)]) {
        self.segments = segments
        self.marker = marker
        self.ticks = ticks
    }

    public var body: some View {
        VStack(spacing: 6) {
            GeometryReader { proxy in
                let total = CGFloat(segments.reduce(0) { $0 + $1.span })
                let gaps = CGFloat(max(0, segments.count - 1)) * 4
                ZStack(alignment: .topLeading) {
                    HStack(spacing: 4) {
                        ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                            Text(segment.label)
                                .font(WTFont.number(14, .semibold))
                                .foregroundStyle(segment.isOn ? ink.onFill : ink.text)
                                .frame(width: (proxy.size.width - gaps) * CGFloat(segment.span) / max(total, 1), height: 34)
                                .background(segment.isOn ? ink.fill : ink.empty,
                                            in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                    }
                    if let marker {
                        Triangle()
                            .fill(ink.fill)
                            .frame(width: 16, height: 9)
                            .offset(x: proxy.size.width * marker - 8, y: -13)
                    }
                }
                .animation(WTAnimation.sheet, value: marker)
                .animation(WTAnimation.fade, value: segments)
            }
            .frame(height: 34)
            GeometryReader { proxy in
                ForEach(Array(ticks.enumerated()), id: \.offset) { _, tick in
                    Text(tick.label)
                        .font(WTFont.number(12, .semibold))
                        .foregroundStyle(ink.text.opacity(0.85))
                        .fixedSize()
                        .position(x: proxy.size.width * tick.position, y: 8)
                }
            }
            .frame(height: 16)
        }
        .accessibilityHidden(true)
    }

    private struct Triangle: Shape {
        func path(in rect: CGRect) -> Path {
            Path { path in
                path.move(to: CGPoint(x: rect.minX, y: rect.minY))
                path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
                path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
                path.closeSubpath()
            }
        }
    }
}

/// Доба 00–24: активні години (підйом ☀️ — відбій 🌙) або три блоки цілей ранку, дня й вечора.
public struct WTSceneDayTrack: View {
    @Environment(\.wtLearnInk) private var ink
    public struct Block: Equatable {
        public let title: String
        public let start: Double
        public let end: Double

        public init(title: String, start: Double, end: Double) {
            self.title = title
            self.start = start
            self.end = end
        }
    }

    public struct Row: Equatable {
        public let label: String?
        /// Частки доби, 0…1.
        public let wake: Double
        public let sleep: Double
        /// Блоки цілей; порожньо — суцільне вікно «норма за день».
        public let blocks: [Block]
        public let windowTitle: String?

        public init(label: String?, wake: Double, sleep: Double, blocks: [Block] = [], windowTitle: String? = nil) {
            self.label = label
            self.wake = wake
            self.sleep = sleep
            self.blocks = blocks
            self.windowTitle = windowTitle
        }
    }

    private let rows: [Row]
    private let axis: [String]

    public init(rows: [Row], axis: [String]) {
        self.rows = rows
        self.axis = axis
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                VStack(alignment: .leading, spacing: 6) {
                    if let label = row.label {
                        Text(label.uppercased())
                            .font(WTFont.text(11, .black))
                            .tracking(0.4)
                            .foregroundStyle(ink.text.opacity(0.88))
                    }
                    track(row)
                }
            }
            HStack {
                ForEach(Array(axis.enumerated()), id: \.offset) { index, label in
                    if index > 0 { Spacer(minLength: 0) }
                    Text(label).font(WTFont.number(11, .semibold)).foregroundStyle(ink.text.opacity(0.88))
                }
            }
        }
        .animation(WTAnimation.sheet, value: rows)
        .accessibilityHidden(true)
    }

    private func track(_ row: Row) -> some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(ink.empty)
                if row.blocks.isEmpty {
                    let x = width * row.wake, w = width * max(0, row.sleep - row.wake)
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(ink.fill)
                        .frame(width: w)
                        .overlay {
                            if let title = row.windowTitle {
                                Text(title).font(WTFont.text(11, .black)).foregroundStyle(ink.onFill).lineLimit(1)
                            }
                        }
                        .offset(x: x)
                } else {
                    ForEach(Array(row.blocks.enumerated()), id: \.offset) { index, block in
                        let x = width * block.start, w = width * max(0, block.end - block.start)
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(ink.fill.opacity([0.55, 0.78, 1][min(index, 2)]))
                            .frame(width: max(0, w - 3))
                            .overlay {
                                if w > 58 {
                                    // Крайні блоки — з відступом: ☀️ і 🌙 стоять на їхніх краях.
                                    Text(block.title).font(WTFont.text(11, .black)).foregroundStyle(ink.onFill).lineLimit(1)
                                        .padding(.leading, index == 0 ? 12 : 0)
                                        .padding(.trailing, index == row.blocks.count - 1 ? 12 : 0)
                                }
                            }
                            .offset(x: x + 1.5)
                    }
                }
                marker("☀️", at: width * row.wake)
                marker("🌙", at: width * row.sleep)
            }
        }
        .frame(height: 30)
    }

    private func marker(_ glyph: String, at x: CGFloat) -> some View {
        Text(glyph)
            .font(.system(size: 12))
            .frame(width: 24, height: 24)
            .background(Color.white, in: Circle())
            .shadow(color: .black.opacity(0.16), radius: 4, y: 2)
            .offset(x: x - 12)
    }
}

/// Сцена кроку «Одиниці»: склянка, вага й підйом у вибраних одиницях — «так виглядатимуть числа».
public struct WTSceneSample: View {
    @Environment(\.wtLearnInk) private var ink
    private let rows: [(glyph: String, text: String)]
    private let caption: String

    public init(rows: [(glyph: String, text: String)], caption: String) {
        self.rows = rows
        self.caption = caption
    }

    public var body: some View {
        VStack(spacing: 10) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 12) {
                    Text(row.glyph).font(.system(size: 22))
                        .frame(width: 40, height: 40)
                        .background(ink.badge, in: Circle())
                    Text(row.text)
                        .font(WTFont.number(30, .semibold))
                        .contentTransition(.numericText())
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: 220)
            }
            Text(caption).font(WTFont.text(14, .heavy)).opacity(0.9)
        }
        .foregroundStyle(ink.text)
        .animation(WTAnimation.sheet, value: rows.map(\.text))
        .accessibilityElement(children: .combine)
    }
}

/// Екран блокування з нагадуванням: як виглядатиме сповіщення з кнопкою «+склянка».
public struct WTLockScreenPreview: View {
    @Environment(\.wtTheme) private var theme
    @Environment(\.wtLearnInk) private var ink
    private let time: String
    private let date: String
    private let appName: String
    private let title: String
    private let message: String
    private let actions: [String]
    private let stamp: String

    public init(time: String, date: String, appName: String, stamp: String, title: String, message: String, actions: [String]) {
        self.stamp = stamp
        self.time = time
        self.date = date
        self.appName = appName
        self.title = title
        self.message = message
        self.actions = actions
    }

    public var body: some View {
        VStack(spacing: 4) {
            Text(time).font(WTFont.number(52, .semibold)).foregroundStyle(ink.text)
            Text(date).font(WTFont.text(13, .heavy)).foregroundStyle(ink.text.opacity(0.88)).padding(.bottom, 12)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 7) {
                    WTDropShape().fill(theme.accent).frame(width: 14, height: 17)
                        .frame(width: 20, height: 20)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                    Text(appName)
                    Spacer()
                    Text(stamp)
                }
                .font(WTFont.text(12, .heavy))
                .foregroundStyle(theme.textPrimary.opacity(0.7))
                Text(title).font(WTFont.text(15, .black)).foregroundStyle(theme.textPrimary)
                Text(message).font(WTFont.text(14, .bold)).foregroundStyle(theme.textPrimary)
                HStack(spacing: 6) {
                    ForEach(Array(actions.enumerated()), id: \.offset) { index, action in
                        Text(action)
                            .font(WTFont.text(13, .heavy))
                            .foregroundStyle(index == 0 ? .white : theme.textButton)
                            .frame(maxWidth: .infinity, minHeight: 32)
                            .background(index == 0 ? theme.accent : theme.chip,
                                        in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                }
                .padding(.top, 7)
                .animation(WTAnimation.fade, value: actions)
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 11)
            .background(theme.card.opacity(0.92), in: RoundedRectangle(cornerRadius: WTRadius.tile, style: .continuous))
        }
        .accessibilityElement(children: .combine)
    }
}

/// Галочка поверх краплі на фініші.
public struct WTSceneCheck: View {
    @Environment(\.wtTheme) private var theme

    public init() {}

    public var body: some View {
        WTIcons.check(color: theme.accent, size: 22)
            .frame(width: 50, height: 50)
            .background(Color.white, in: Circle())
            .wtShadow(.modal)
            .wtStoryAppear(delay: 0.7, pop: true)
            .accessibilityHidden(true)
    }
}
