import SwiftUI

// Вікно «Шлях рівнів» — варіант A «Драбина» (SPEC-PRIZES §16.5, макет Design/LevelRoad.html).
// Компоненти приймають прості значення: що таке вибір чи таємний приз, знає лише Features.

// MARK: - Рейка

/// Вигляд кружка рівня на рейці.
public enum WTRoadNodeStyle: Equatable, Sendable {
    case passed
    /// `fraction` — частка XP до наступного рівня, кільцем навколо номера.
    case current(fraction: Double)
    case ahead
    case fogged
}

/// Кружок рівня. Розмір каже, чи є на рівні приз: порожній — 24, з призом — 32, поточний — 42.
public struct WTRoadNode: View {
    @Environment(\.wtTheme) private var theme
    private let level: Int
    private let style: WTRoadNodeStyle
    private let hasReward: Bool

    public init(level: Int, style: WTRoadNodeStyle, hasReward: Bool) {
        self.level = level
        self.style = style
        self.hasReward = hasReward
    }

    public static func diameter(style: WTRoadNodeStyle, hasReward: Bool) -> CGFloat {
        if case .current = style { return 42 }
        return hasReward ? 32 : 24
    }

    public var body: some View {
        let size = Self.diameter(style: style, hasReward: hasReward)
        ZStack {
            switch style {
            case .passed:
                Circle().fill(theme.accent)
                label(color: .white)
            case .current(let fraction):
                Circle().fill(theme.screen)
                Circle().stroke(theme.dotOff, lineWidth: 4).padding(2)
                Circle()
                    .trim(from: 0, to: max(0.001, min(1, fraction)))
                    .stroke(theme.accent, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .padding(2)
                label(color: theme.textPrimary)
            case .ahead, .fogged:
                Circle().fill(theme.screen)
                Circle().strokeBorder(theme.dotOff, lineWidth: 2)
                label(color: theme.textMuted)
            }
        }
        .frame(width: size, height: size)
        .opacity(style == .fogged ? 0.45 : 1)
        .accessibilityHidden(true)
    }

    private func label(color: Color) -> some View {
        let size: CGFloat = if case .current = style { 16 } else { hasReward ? 13 : 11 }
        return Text("\(level)")
            .font(WTFont.number(size, .semibold))
            .foregroundStyle(color)
    }
}

/// Центр кружка рівня — з нього рейка малює лінію.
public struct WTRoadAnchorKey: PreferenceKey {
    public static let defaultValue: [Int: Anchor<CGPoint>] = [:]
    public static func reduce(value: inout [Int: Anchor<CGPoint>], nextValue: () -> [Int: Anchor<CGPoint>]) {
        value.merge(nextValue()) { $1 }
    }
}

/// Рядок драбини: рейка з кружком зліва, вміст справа.
///
/// `nodeCenterY` — де по висоті вмісту центр кружка: на рівні іконки картки (36 = падінг 12 + іконка 48 / 2),
/// а в рядку без картки — центр самого кружка.
public struct WTRoadRow<Content: View>: View {
    private let level: Int
    private let style: WTRoadNodeStyle
    private let hasReward: Bool
    private let nodeCenterY: CGFloat?
    private let content: Content

    public init(
        level: Int, style: WTRoadNodeStyle, hasReward: Bool, nodeCenterY: CGFloat? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.level = level
        self.style = style
        self.hasReward = hasReward
        self.nodeCenterY = nodeCenterY
        self.content = content()
    }

    public var body: some View {
        let size = WTRoadNode.diameter(style: style, hasReward: hasReward)
        HStack(alignment: .top, spacing: 12) {
            WTRoadNode(level: level, style: style, hasReward: hasReward)
                .anchorPreference(key: WTRoadAnchorKey.self, value: .center) { [level: $0] }
                .padding(.top, max(0, (nodeCenterY ?? size / 2) - size / 2))
                .frame(width: 42)
            content
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.bottom, 14)
    }
}

/// Лінія рейки: суцільна до `position` (рівень + частка XP), далі пунктир.
/// `position` анімується — так «повтор прогресу» доростає лінією (§16.15).
public struct WTRoadRailShape: Shape {
    var points: [CGPoint]
    var position: Double

    public init(points: [CGPoint], position: Double) {
        self.points = points
        self.position = position
    }

    public var animatableData: Double {
        get { position }
        set { position = newValue }
    }

    public func path(in rect: CGRect) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)
        for index in points.indices.dropFirst() {
            let progress = position - Double(index - 1)
            guard progress > 0 else { break }
            let from = points[index - 1], to = points[index]
            let t = CGFloat(min(1, progress))
            path.addLine(to: CGPoint(x: from.x + (to.x - from.x) * t, y: from.y + (to.y - from.y) * t))
        }
        return path
    }
}

public extension View {
    /// Малює рейку під рядками `WTRoadRow`. `position` — у рівнях від першого рядка: 6,4 — сьомий рядок
    /// і ще 40 % до восьмого.
    func wtRoadRail(position: Double) -> some View {
        modifier(WTRoadRailModifier(position: position))
    }
}

private struct WTRoadRailModifier: ViewModifier {
    @Environment(\.wtTheme) private var theme
    let position: Double

    func body(content: Content) -> some View {
        content.backgroundPreferenceValue(WTRoadAnchorKey.self) { anchors in
            GeometryReader { proxy in
                let points = anchors.sorted { $0.key < $1.key }.map { proxy[$0.value] }
                ZStack {
                    WTRoadRailShape(points: points, position: Double(points.count))
                        .stroke(theme.dotOff, style: StrokeStyle(lineWidth: 4, lineCap: .round, dash: [6, 6]))
                    WTRoadRailShape(points: points, position: position)
                        .stroke(theme.accent, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                }
            }
        }
    }
}

// MARK: - Картки призів

/// Що намальовано в іконці картки.
public enum WTRoadIcon: Equatable, Sendable {
    /// Один приз; `count` ≥ 2 — бейдж «×N».
    case single(String, count: Int = 1)
    /// Кілька різних призів разом: «🧊 + ⚡».
    case combo([String])
    /// Вибір попереду: дві іконки з «або».
    case pair([String])
    /// 🎁, що чекає: похитується.
    case gift
    /// Туман: «?».
    case unknown
}

/// Тон картки на драбині.
public enum WTRoadCardTone: Equatable, Sendable {
    /// Отримано: без підкладки, з ✓, підпис зеленим.
    case claimed
    /// Попереду: на картці, іконка приглушена.
    case upcoming
    /// За горизонтом: розмита.
    case fogged
}

public struct WTRoadPrizeCard: View {
    @Environment(\.wtTheme) private var theme
    private let icon: WTRoadIcon
    private let title: String
    private let subtitle: String
    private let tone: WTRoadCardTone
    private let isGrand: Bool

    public init(icon: WTRoadIcon, title: String, subtitle: String, tone: WTRoadCardTone, isGrand: Bool = false) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.tone = tone
        self.isGrand = isGrand
    }

    public var body: some View {
        HStack(spacing: 14) {
            WTRoadIconView(icon: icon, background: tone == .claimed ? theme.unlockedIconBg : theme.lockedIconBg,
                           showsCheck: tone == .claimed)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(WTFont.display(15, .semibold))
                    .foregroundStyle(theme.textPrimary)
                Text(subtitle)
                    .font(WTFont.text(12, .bold))
                    .foregroundStyle(tone == .claimed ? WTColor.successText : theme.textMuted)
            }
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, tone == .claimed ? 4 : 14)
        .background {
            if tone != .claimed {
                RoundedRectangle(cornerRadius: WTRadius.panel, style: .continuous)
                    .fill(theme.card)
                    .wtShadow(.card)
            }
        }
        .overlay {
            if isGrand, tone == .upcoming {
                RoundedRectangle(cornerRadius: WTRadius.panel, style: .continuous)
                    .strokeBorder(WTColor.orange, lineWidth: 2)
            }
        }
        .blur(radius: tone == .fogged ? 3 : 0)
        .opacity(tone == .fogged ? 0.5 : 1)
        .accessibilityElement(children: .combine)
    }
}

/// Іконка картки: 48 × 48 у квадраті `WTRadius.control`, як у рядку призу.
struct WTRoadIconView: View {
    @Environment(\.wtTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let icon: WTRoadIcon
    let background: Color
    var size: CGFloat = 48
    var showsCheck = false

    var body: some View {
        switch icon {
        case .pair(let emojis):
            HStack(spacing: 5) {
                ForEach(Array(emojis.enumerated()), id: \.offset) { index, emoji in
                    if index > 0 {
                        Text("або")
                            .font(WTFont.text(11, .heavy))
                            .foregroundStyle(theme.textMuted)
                    }
                    tile(Text(emoji).font(.system(size: 19)), side: 38)
                }
            }
            .accessibilityHidden(true)
        default:
            tile(glyph, side: size)
                .overlay(alignment: .bottomTrailing) {
                    if case .single(_, let count) = icon, count > 1 {
                        Text("×\(count)")
                            .font(WTFont.text(11, .heavy))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .frame(height: 20)
                            .background(theme.accent, in: Capsule())
                            .overlay(Capsule().stroke(theme.card, lineWidth: 2))
                            .offset(x: 6, y: 6)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if showsCheck {
                        WTIcons.check(color: .white, size: 8)
                            .frame(width: 18, height: 18)
                            .background(WTColor.success, in: Circle())
                            .overlay(Circle().stroke(theme.screen, lineWidth: 2))
                            .offset(x: 5, y: -5)
                    }
                }
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private var glyph: some View {
        switch icon {
        case .single(let emoji, _):
            Text(emoji).font(.system(size: size * 0.5))
        case .combo(let emojis):
            Text(emojis.joined()).font(.system(size: size * 0.38)).tracking(-2)
        case .gift:
            // Похитування — від часу, а не `withAnimation(.repeatForever)` в `onAppear`: така транзакція
            // підхоплювала зсуви інших вʼюх, і шапка вікна починала «плавати».
            TimelineView(.animation(paused: reduceMotion)) { context in
                Text("🎁")
                    .font(.system(size: size * 0.54))
                    .rotationEffect(.degrees(reduceMotion ? 0 : Self.wiggle(at: context.date)))
            }
        case .unknown:
            Text("?").font(WTFont.display(size * 0.42, .bold)).foregroundStyle(theme.textMuted)
        case .pair:
            EmptyView()
        }
    }

    private func tile(_ content: some View, side: CGFloat) -> some View {
        content
            .frame(width: side, height: side)
            .background(background, in: RoundedRectangle(cornerRadius: side > 40 ? WTRadius.control : WTRadius.chip, style: .continuous))
    }

    /// Подарунок, що чекає, раз на 2,4 с коротко похитується (як у макеті) — щоб око знайшло його на довгій
    /// драбині, але не смикало його весь час. Кут — загасальна синусоїда в перші 0,5 с циклу.
    static func wiggle(at date: Date) -> Double {
        let cycle = 2.4, shake = 0.5
        let t = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: cycle)
        guard t < shake else { return 0 }
        return 12 * (1 - t / shake) * sin(t / shake * .pi * 4)
    }
}

// MARK: - Вибір «один з двох»

/// Варіант вибору — пігулка «іконка + назва».
public struct WTRoadChoiceOption: Identifiable, Equatable, Sendable {
    public let id: String
    public let emoji: String
    public let title: String

    public init(id: String, emoji: String, title: String) {
        self.id = id
        self.emoji = emoji
        self.title = title
    }
}

/// Компактна картка вибору (рішення від 06.10.2026: перша версія з великими плитками займала півекрана).
/// Заголовок і кнопка «Забрати» в один ряд, під ними дві пігулки. Опис обраного — у підписі.
public struct WTRoadChoiceCard: View {
    @Environment(\.wtTheme) private var theme
    private let title: String
    private let subtitle: String
    private let takeTitle: String
    private let options: [WTRoadChoiceOption]
    private let selectedId: String?
    private let isDone: Bool
    private let identifierPrefix: String
    private let onSelect: (String) -> Void
    private let onTake: () -> Void

    public init(
        title: String, subtitle: String, takeTitle: String, options: [WTRoadChoiceOption],
        selectedId: String?, isDone: Bool, identifierPrefix: String,
        onSelect: @escaping (String) -> Void, onTake: @escaping () -> Void
    ) {
        self.title = title
        self.subtitle = subtitle
        self.takeTitle = takeTitle
        self.options = options
        self.selectedId = selectedId
        self.isDone = isDone
        self.identifierPrefix = identifierPrefix
        self.onSelect = onSelect
        self.onTake = onTake
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(WTFont.display(15, .semibold))
                        .foregroundStyle(theme.textPrimary)
                    Text(subtitle)
                        .font(WTFont.text(12, .bold))
                        .foregroundStyle(isDone ? WTColor.successText : theme.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                        .contentTransition(.opacity)
                }
                Spacer(minLength: 0)
                Button(action: onTake) {
                    Text(takeTitle)
                        .font(WTFont.text(14, .heavy))
                        .foregroundStyle(selectedId == nil ? theme.textMuted : .white)
                        .padding(.horizontal, 16)
                        .frame(height: 34)
                        .background(selectedId == nil ? theme.chip : theme.accent, in: Capsule())
                }
                .buttonStyle(WTPressStyle())
                .disabled(selectedId == nil || isDone)
                .opacity(isDone ? 0 : 1)
                .accessibilityHint(selectedId == nil ? "Спочатку обери приз" : "")
                .accessibilityIdentifier("\(identifierPrefix).claim")
            }
            HStack(spacing: 8) {
                ForEach(options) { option in optionPill(option) }
            }
        }
        .padding(.top, 12)
        .padding(.bottom, 14)
        .padding(.horizontal, 14)
        .background(theme.card, in: RoundedRectangle(cornerRadius: WTRadius.panel, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: WTRadius.panel, style: .continuous)
                .strokeBorder(theme.accent, lineWidth: 2)
        )
        .wtShadow(.card)
    }

    private func optionPill(_ option: WTRoadChoiceOption) -> some View {
        let isSelected = option.id == selectedId
        let opacity: Double = isDone ? (isSelected ? 1 : 0.18) : (selectedId == nil || isSelected ? 1 : 0.5)
        return Button { onSelect(option.id) } label: {
            HStack(spacing: 7) {
                Text(option.emoji)
                    .font(.system(size: 17))
                    .frame(width: 32, height: 32)
                    .background(theme.prizeIconBg, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(alignment: .topTrailing) {
                        if isDone, isSelected {
                            WTIcons.check(color: .white, size: 8)
                                .frame(width: 18, height: 18)
                                .background(WTColor.success, in: Circle())
                                .overlay(Circle().stroke(theme.card, lineWidth: 2))
                                .offset(x: 5, y: -5)
                        }
                    }
                    .accessibilityHidden(true)
                Text(option.title)
                    .font(WTFont.text(12, .heavy))
                    .foregroundStyle(theme.textPrimary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 6)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(
                isSelected && !isDone ? theme.accent.opacity(0.1) : theme.screen,
                in: RoundedRectangle(cornerRadius: WTRadius.control, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: WTRadius.control, style: .continuous)
                    .strokeBorder(isSelected && !isDone ? theme.accent : theme.line, lineWidth: 2)
            )
            .opacity(opacity)
        }
        .buttonStyle(WTPressStyle(scale: 0.97))
        .disabled(isDone)
        .accessibilityLabel(option.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("\(identifierPrefix).\(option.id)")
    }
}

// MARK: - Таємний приз, що чекає

public struct WTRoadMysteryCard: View {
    @Environment(\.wtTheme) private var theme
    private let title: String
    private let subtitle: String
    private let buttonTitle: String
    private let isGrand: Bool
    private let buttonIdentifier: String
    private let onOpen: () -> Void

    public init(title: String, subtitle: String, buttonTitle: String, isGrand: Bool, buttonIdentifier: String,
                onOpen: @escaping () -> Void) {
        self.title = title
        self.subtitle = subtitle
        self.buttonTitle = buttonTitle
        self.isGrand = isGrand
        self.buttonIdentifier = buttonIdentifier
        self.onOpen = onOpen
    }

    public var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 14) {
                WTRoadIconView(icon: .gift, background: theme.prizeIconBg, size: 56)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(WTFont.display(15, .semibold))
                        .foregroundStyle(theme.textPrimary)
                    Text(subtitle)
                        .font(WTFont.text(12, .bold))
                        .foregroundStyle(theme.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
                Spacer(minLength: 0)
            }
            Button(action: onOpen) {
                Text(buttonTitle)
                    .font(WTFont.display(16, .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 46)
                    .background(isGrand ? WTColor.orange : theme.accent,
                                in: RoundedRectangle(cornerRadius: WTRadius.control, style: .continuous))
            }
            .buttonStyle(WTPressStyle())
            .accessibilityIdentifier(buttonIdentifier)
        }
        .padding(14)
        .background(theme.card, in: RoundedRectangle(cornerRadius: WTRadius.panel, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: WTRadius.panel, style: .continuous)
                .strokeBorder(isGrand ? WTColor.orange : theme.accent, lineWidth: 2)
        )
        .wtShadow(.card)
    }
}

/// «Ти тут · 300 / 500 XP» під поточним рівнем.
public struct WTRoadHerePill: View {
    @Environment(\.wtTheme) private var theme
    private let label: String
    private let value: String

    public init(label: String, value: String) {
        self.label = label
        self.value = value
    }

    public var body: some View {
        HStack(spacing: 4) {
            Text(label).font(WTFont.text(12, .heavy))
            Text(value).font(WTFont.number(12, .semibold))
            Text("XP").font(WTFont.text(12, .heavy))
        }
        .foregroundStyle(theme.textButton)
        .padding(.horizontal, 10)
        .frame(height: 26)
        .background(theme.chip, in: Capsule())
        .accessibilityElement(children: .combine)
    }
}

/// «Далі — ще більше призів» — кінець стежки за туманом.
public struct WTRoadEnd: View {
    @Environment(\.wtTheme) private var theme
    private let text: String

    public init(_ text: String) { self.text = text }

    public var body: some View {
        Text(text)
            .font(WTFont.text(13, .heavy))
            .foregroundStyle(theme.textMuted)
            .frame(maxWidth: .infinity)
            .padding(.top, 4)
    }
}

// MARK: - Блок «НАГОРОДА НА РІВНІ N» на 3f

/// Найближча нагорода або заклик, поки вибір чи 🎁 чекають (SPEC-PRIZES §16.6). Тап відкриває шлях рівнів.
public struct WTNextRewardRow: View {
    @Environment(\.wtTheme) private var theme
    private let icon: WTRoadIcon
    private let title: String
    private let subtitle: String
    private let isCallToAction: Bool
    private let action: () -> Void

    public init(icon: WTRoadIcon, title: String, subtitle: String, isCallToAction: Bool, action: @escaping () -> Void) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.isCallToAction = isCallToAction
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                WTRoadIconView(icon: icon, background: theme.prizeIconBg, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(WTFont.display(16, .semibold))
                        .foregroundStyle(theme.textPrimary)
                    Text(subtitle)
                        .font(WTFont.text(13, .bold))
                        .foregroundStyle(theme.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                WTIcons.chevronRight(color: isCallToAction ? WTColor.orange : theme.textMuted, size: 14)
            }
            .padding(.vertical, isCallToAction ? 12 : 10)
            .padding(.horizontal, isCallToAction ? 14 : 0)
            .background {
                if isCallToAction {
                    RoundedRectangle(cornerRadius: WTRadius.panel, style: .continuous)
                        .fill(theme.card)
                        .wtShadow(.card)
                }
            }
            .overlay {
                if isCallToAction {
                    RoundedRectangle(cornerRadius: WTRadius.panel, style: .continuous)
                        .strokeBorder(WTColor.orange, lineWidth: 2)
                }
            }
            .overlay(alignment: .bottom) {
                if !isCallToAction { Rectangle().fill(theme.line).frame(height: 1) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(WTPressStyle(scale: 0.98))
        .accessibilityElement(children: .combine)
    }
}
