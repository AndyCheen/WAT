import SwiftUI

// Інфографіка історій «Знань» (SPEC-LEARN §4, §5.5): усі числа й підписи готує екран, компоненти лише
// малюють і програють появу. Кольори — з `WTLearnInk`, тож одна діаграма працює на будь-якій полиці.

private let wtEaseOut = Animation.timingCurve(0.22, 1, 0.36, 1, duration: 0.8)

// MARK: - Два стовпці «надходить = виходить»

public struct WTLearnColumns: View {
    public struct Column: Equatable, Sendable {
        public let title: String
        public let total: String
        /// Знизу вгору: найбільша частина — першою.
        public let parts: [(label: String, value: String, share: Double)]
        public init(title: String, total: String, parts: [(label: String, value: String, share: Double)]) {
            self.title = title
            self.total = total
            self.parts = parts
        }
        public static func == (lhs: Column, rhs: Column) -> Bool {
            lhs.title == rhs.title && lhs.total == rhs.total && lhs.parts.map(\.label) == rhs.parts.map(\.label)
        }
    }

    @Environment(\.wtLearnInk) private var ink
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let left: Column
    private let right: Column
    private let height: CGFloat
    @State private var grown = false

    public init(left: Column, right: Column, height: CGFloat = 230) {
        self.left = left
        self.right = right
        self.height = height
    }

    public var body: some View {
        HStack(alignment: .bottom, spacing: 12) {
            column(left, offset: 0)
            Text("=")
                .font(WTFont.number(36, .semibold))
                .foregroundStyle(ink.fill)
                .padding(.bottom, 52 + height * 0.4)
                .wtStoryAppear(delay: 1.1, pop: true)
            column(right, offset: 0.1)
        }
        .frame(maxWidth: .infinity)
        .onAppear { grown = true }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(left.title) \(left.total), \(right.title) \(right.total)")
    }

    private func column(_ column: Column, offset: Double) -> some View {
        VStack(spacing: 10) {
            VStack(spacing: 3) {
                ForEach(Array(column.parts.enumerated().reversed()), id: \.offset) { index, part in
                    let strength = max(0.25, 1 - Double(index) * 0.25)
                    HStack(spacing: 4) {
                        Text(part.label).font(WTFont.text(12, .heavy)).lineLimit(1).minimumScaleFactor(0.8)
                        Spacer(minLength: 2)
                        Text(part.value).font(WTFont.number(13, .semibold))
                    }
                    .foregroundStyle(strength > 0.55 ? ink.onFill : ink.text)
                    .padding(.horizontal, 10)
                    .frame(height: max(20, height * part.share - 3))
                    .background(ink.fill.opacity(strength), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .background(ink.empty, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .scaleEffect(y: grown || reduceMotion ? 1 : 0.001, anchor: .bottom)
                    .animation(wtEaseOut.delay(0.25 + offset + Double(index) * 0.16), value: grown)
                }
            }
            .frame(height: height, alignment: .bottom)
            VStack(spacing: 1) {
                Text(column.title).font(WTFont.text(14, .heavy))
                Text(column.total).font(WTFont.text(14, .bold)).opacity(0.7)
            }
            .foregroundStyle(ink.text)
        }
        .frame(width: 138)
    }
}

// MARK: - Кільце норми, поділене на частини

public struct WTLearnSegmentRing: View {
    public struct Segment: Equatable, Sendable {
        public let label: String
        public let value: String
        public let share: Double
        public init(label: String, value: String, share: Double) {
            self.label = label
            self.value = value
            self.share = share
        }
    }

    @Environment(\.wtLearnInk) private var ink
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let total: String
    private let caption: String
    private let segments: [Segment]
    private let diameter: CGFloat
    @State private var drawn = false

    public init(total: String, caption: String, segments: [Segment], diameter: CGFloat = 196) {
        self.total = total
        self.caption = caption
        self.segments = segments
        self.diameter = diameter
    }

    public var body: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle().stroke(ink.empty, lineWidth: 18)
                ForEach(segments.indices, id: \.self) { index in
                    let start = segments[..<index].reduce(0) { $0 + $1.share }
                    let gap = segments.count > 1 ? 0.025 : 0
                    Circle()
                        .trim(from: start + gap / 2, to: drawn || reduceMotion ? start + segments[index].share - gap / 2 : start + gap / 2)
                        .stroke(ink.fill.opacity(1 - Double(index) * 0.28), style: StrokeStyle(lineWidth: 18, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(wtEaseOut.delay(0.2 + Double(index) * 0.3), value: drawn)
                }
                VStack(spacing: 2) {
                    Text(total).font(WTFont.number(diameter * 0.2, .semibold))
                    Text(caption).font(WTFont.text(13, .heavy)).opacity(0.75)
                }
                .foregroundStyle(ink.text)
            }
            .frame(width: diameter, height: diameter)
            if segments.count > 1 {
                VStack(spacing: 6) {
                    ForEach(segments.indices, id: \.self) { index in
                        HStack(spacing: 8) {
                            Circle().fill(ink.fill.opacity(1 - Double(index) * 0.28)).frame(width: 12, height: 12)
                            Text(segments[index].label).font(WTFont.text(14, .heavy))
                            Spacer(minLength: 12)
                            Text(segments[index].value).font(WTFont.text(15, .black))
                        }
                        .wtStoryAppear(delay: 0.4 + Double(index) * 0.3)
                    }
                }
                .foregroundStyle(ink.text)
                .frame(width: 240)
            }
        }
        .onAppear { drawn = true }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(([total + " " + caption] + segments.map { "\($0.label) \($0.value)" }).joined(separator: ", "))
    }
}

// MARK: - Склянки XP

/// Ряд склянок по кроку об'єму: повні — до норми, м'які — понад норму до стелі, з замком — понад стелю.
public struct WTLearnGlasses: View {
    @Environment(\.wtLearnInk) private var ink
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let full: Int
    private let bonus: Int
    private let locked: Int
    private let chip: String?
    private let legend: [String]
    @State private var filled = false

    public init(full: Int, bonus: Int, locked: Int, chip: String?, legend: [String]) {
        self.full = full
        self.bonus = bonus
        self.locked = locked
        self.chip = chip
        self.legend = legend
    }

    public var body: some View {
        let total = full + bonus + locked
        VStack(spacing: 16) {
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(52), spacing: 12), count: min(5, max(1, total))), spacing: 26) {
                ForEach(0..<total, id: \.self) { index in
                    glass(index)
                }
            }
            .padding(.top, 14)
            if !legend.isEmpty {
                HStack(spacing: 14) {
                    ForEach(legend.indices, id: \.self) { index in
                        Text(legend[index]).font(WTFont.text(12, .heavy)).opacity(0.75)
                    }
                }
                .foregroundStyle(ink.text)
                .wtStoryAppear(delay: 1.6)
            }
        }
        .onAppear { filled = true }
        .accessibilityHidden(true)
    }

    private func glass(_ index: Int) -> some View {
        let isLocked = index >= full + bonus
        let delay = 0.15 + Double(index) * 0.11
        return ZStack {
            WTGlassShape().fill(ink.empty)
            if !isLocked {
                Rectangle()
                    .fill(index < full ? ink.fill : ink.soft)
                    .scaleEffect(y: filled || reduceMotion ? 0.88 : 0.001, anchor: .bottom)
                    .animation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.5).delay(delay), value: filled)
                    .mask(WTGlassShape())
            }
        }
        .frame(width: 48, height: 62)
        .overlay(alignment: .top) {
            if let chip {
                Text(isLocked ? "🔒" : chip)
                    .font(isLocked ? .system(size: 11) : WTFont.number(12, .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 1)
                    .background(isLocked ? Color.gray.opacity(0.6) : WTColor.orange, in: Capsule())
                    .offset(y: -16)
                    .wtStoryAppear(delay: delay + 0.35, pop: true)
            }
        }
    }
}

// MARK: - Драбина рівнів

/// Вертикальна «Драбина», як у вікні «Шлях рівнів» (WAT-44): що вже взято, що наступне, що далі.
public struct WTLearnLadder: View {
    public enum State: Equatable, Sendable { case done, next, later }
    public struct Node: Equatable, Sendable {
        public let emoji: String
        public let caption: String
        public let title: String
        public let state: State
        public init(emoji: String, caption: String, title: String, state: State) {
            self.emoji = emoji
            self.caption = caption
            self.title = title
            self.state = state
        }
    }

    @Environment(\.wtLearnInk) private var ink
    @Environment(\.wtTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let nodes: [Node]
    /// Скільки рейки залито — від першого вузла до останнього.
    private let progress: Double
    private let spacing: CGFloat
    @SwiftUI.State private var grown = false

    public init(nodes: [Node], progress: Double, spacing: CGFloat = 16) {
        self.nodes = nodes
        self.progress = progress
        self.spacing = spacing
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            ForEach(nodes.indices, id: \.self) { index in
                row(nodes[index]).wtStoryAppear(delay: 0.1 + Double(index) * 0.1)
            }
        }
        .background(alignment: .topLeading) {
            GeometryReader { proxy in
                let rail = proxy.size.height - 46
                ZStack(alignment: .top) {
                    Capsule().fill(ink.empty).frame(width: 4, height: rail)
                    Capsule().fill(ink.fill).frame(width: 4, height: rail * (grown || reduceMotion ? progress : 0))
                        .frame(height: rail, alignment: .top)
                        .animation(.timingCurve(0.22, 1, 0.36, 1, duration: 1.2).delay(0.3), value: grown)
                }
                .offset(x: 21, y: 23)
            }
        }
        .frame(maxWidth: 320, alignment: .leading)
        .onAppear { grown = true }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(nodes.map { "\($0.caption): \($0.title)" }.joined(separator: ", "))
    }

    private func row(_ node: Node) -> some View {
        HStack(spacing: 14) {
            // «⚡🧊» вибору — дві іконки в одному колі: менший кегль, інакше друга обрізається.
            Text(node.emoji)
                .font(.system(size: node.emoji.count > 1 ? 12 : 18))
                .lineLimit(1)
                .fixedSize()
                .frame(width: 40, height: 40)
                .background(theme.card, in: Circle())
                .overlay(Circle().stroke(border(node.state), lineWidth: 3))
                .background(node.state == .next ? WTColor.orange.opacity(0.18) : .clear, in: Circle().inset(by: -6))
                .overlay(alignment: .topTrailing) {
                    if node.state == .done {
                        WTIcons.check(color: ink.onFill, size: 8)
                            .frame(width: 18, height: 18)
                            .background(ink.fill, in: Circle())
                            .offset(x: 5, y: -5)
                    }
                }
                .frame(width: 46, height: 46)
            VStack(alignment: .leading, spacing: 1) {
                Text(node.caption)
                    .font(WTFont.text(12, .heavy))
                    .foregroundStyle(node.state == .next ? WTColor.orange : ink.text.opacity(0.6))
                Text(node.title).font(WTFont.text(16, .heavy)).foregroundStyle(ink.text)
            }
        }
        .opacity(node.state == .later ? 0.55 : 1)
    }

    private func border(_ state: State) -> Color {
        switch state {
        case .done: return ink.fill
        case .next: return WTColor.orange
        case .later: return ink.empty
        }
    }
}

// MARK: - Складений стовпчик

/// «145 XP за рівний день»: число, горизонтальна смуга з частин і легенда під нею.
public struct WTLearnStackBar: View {
    public struct Segment: Equatable, Sendable {
        public let emoji: String
        public let value: Int
        public let label: String
        public init(emoji: String, value: Int, label: String) {
            self.emoji = emoji
            self.value = value
            self.label = label
        }
    }

    @Environment(\.wtLearnInk) private var ink
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let unit: String
    private let caption: String
    private let segments: [Segment]
    @State private var grown = false

    public init(unit: String, caption: String, segments: [Segment]) {
        self.unit = unit
        self.caption = caption
        self.segments = segments
    }

    public var body: some View {
        let total = segments.reduce(0) { $0 + $1.value }
        VStack(spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                WTCountUpText(Double(total)).font(WTFont.number(60, .semibold))
                Text(unit).font(WTFont.number(24, .semibold)).opacity(0.75)
            }
            Text(caption).font(WTFont.text(13, .heavy)).opacity(0.7)
            GeometryReader { proxy in
                let width = proxy.size.width - CGFloat(max(0, segments.count - 1)) * 3
                HStack(spacing: 3) {
                    ForEach(segments.indices, id: \.self) { index in
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(ink.fill.opacity(1 - Double(index) * 0.2))
                            .frame(width: width * Double(segments[index].value) / Double(max(total, 1)))
                            .scaleEffect(x: grown || reduceMotion ? 1 : 0.001, anchor: .leading)
                            .animation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.7).delay(0.2 + Double(index) * 0.18),
                                       value: grown)
                    }
                }
            }
            .frame(height: 24)
            .padding(.top, 10)
            HStack(alignment: .top, spacing: 4) {
                ForEach(segments.indices, id: \.self) { index in
                    VStack(spacing: 1) {
                        Text("\(segments[index].emoji) \(segments[index].value)").font(WTFont.text(14, .black))
                        Text(segments[index].label).font(WTFont.text(11, .heavy)).opacity(0.75)
                    }
                    .frame(maxWidth: .infinity)
                    .wtStoryAppear(delay: 0.45 + Double(index) * 0.15)
                }
            }
            .padding(.top, 8)
        }
        .foregroundStyle(ink.text)
        .frame(maxWidth: 330)
        .onAppear { grown = true }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(total) \(unit) \(caption): " + segments.map { "\($0.label) \($0.value)" }.joined(separator: ", "))
    }
}

// MARK: - Вертикальні стовпці

/// Стовпці, що виростають: «2,0 л · 2,5 л», «до · після», «×1 … ×1,5». Нижня частка `lower` — інший тон
/// (з напоїв проти з їжею).
public struct WTLearnBars: View {
    public struct Bar: Equatable, Sendable {
        public let label: String
        public let value: String
        public let fraction: Double
        public let lower: Double?
        public let isAccent: Bool
        public init(label: String, value: String, fraction: Double, lower: Double? = nil, isAccent: Bool = false) {
            self.label = label
            self.value = value
            self.fraction = fraction
            self.lower = lower
            self.isAccent = isAccent
        }
    }

    @Environment(\.wtLearnInk) private var ink
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let bars: [Bar]
    private let height: CGFloat
    private let legend: [String]
    @State private var grown = false

    public init(bars: [Bar], height: CGFloat = 200, legend: [String] = []) {
        self.bars = bars
        self.height = height
        self.legend = legend
    }

    public var body: some View {
        VStack(spacing: 14) {
            HStack(alignment: .bottom, spacing: bars.count > 3 ? 12 : 26) {
                ForEach(bars.indices, id: \.self) { index in
                    let bar = bars[index]
                    VStack(spacing: 8) {
                        Text(bar.value).font(WTFont.text(bars.count > 3 ? 14 : 20, .black))
                            .wtStoryAppear(delay: 0.6 + Double(index) * 0.15)
                        VStack(spacing: 0) {
                            Rectangle().fill(bar.isAccent ? WTColor.orange : ink.soft)
                            if let lower = bar.lower {
                                Rectangle().fill(ink.fill).frame(height: height * min(1, bar.fraction) * lower)
                            }
                        }
                        .frame(width: bars.count > 3 ? 44 : 84, height: height * min(1, bar.fraction))
                        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 16, bottomLeadingRadius: 8,
                                                          bottomTrailingRadius: 8, topTrailingRadius: 16, style: .continuous))
                        .scaleEffect(y: grown || reduceMotion ? 1 : 0.001, anchor: .bottom)
                        .animation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.9).delay(0.2 + Double(index) * 0.15), value: grown)
                        Text(bar.label).font(WTFont.text(13, .heavy)).opacity(0.75).multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            if !legend.isEmpty {
                HStack(spacing: 16) {
                    ForEach(legend.indices, id: \.self) { index in
                        HStack(spacing: 6) {
                            RoundedRectangle(cornerRadius: 3).fill(index == 0 ? ink.fill : ink.soft).frame(width: 12, height: 12)
                            Text(legend[index]).font(WTFont.text(12, .heavy)).opacity(0.8)
                        }
                    }
                }
                .wtStoryAppear(delay: 1.2)
            }
        }
        .foregroundStyle(ink.text)
        .frame(maxWidth: .infinity)
        .onAppear { grown = true }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(bars.map { "\($0.label) \($0.value)" }.joined(separator: ", "))
    }
}

// MARK: - Ланцюг серії

public struct WTLearnChain: View {
    public enum Day: Equatable, Sendable { case met, frozen, missed, today }

    @Environment(\.wtLearnInk) private var ink
    @Environment(\.wtTheme) private var theme
    private let days: [Day]
    private let labels: [String]
    private let caption: String?

    public init(days: [Day], labels: [String], caption: String? = nil) {
        self.days = days
        self.labels = labels
        self.caption = caption
    }

    public var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 0) {
                ForEach(days.indices, id: \.self) { index in
                    if index > 0 {
                        Rectangle()
                            .fill(days[index] == .missed || days[index - 1] == .missed ? ink.empty : ink.fill.opacity(0.7))
                            .frame(width: 8, height: 3)
                            .wtStoryAppear(delay: 0.3 + Double(index) * 0.1, pop: true)
                    }
                    VStack(spacing: 6) {
                        cell(days[index])
                        Text(index < labels.count ? labels[index] : "")
                            .font(WTFont.text(11, .black))
                            .foregroundStyle(ink.text.opacity(0.7))
                    }
                    .wtStoryAppear(delay: 0.3 + Double(index) * 0.1, pop: true)
                }
            }
            if let caption {
                Text(caption).font(WTFont.text(14, .heavy)).foregroundStyle(ink.text).wtStoryAppear(delay: 1.2)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(caption ?? "")
    }

    @ViewBuilder
    private func cell(_ day: Day) -> some View {
        switch day {
        case .met:
            WTIcons.check(color: ink.onFill, size: 12)
                .frame(width: 34, height: 34)
                .background(ink.fill, in: Circle())
        case .frozen:
            Text("🧊").font(.system(size: 17))
                .frame(width: 34, height: 34)
                .background(Color(hex: "#d8efff"), in: Circle())
        case .missed:
            Circle().stroke(ink.empty, style: StrokeStyle(lineWidth: 2.5, dash: [4, 3])).frame(width: 34, height: 34)
        case .today:
            Text("🔥").font(.system(size: 17))
                .frame(width: 34, height: 34)
                .background(WTColor.orange.opacity(0.2), in: Circle())
                .overlay(Circle().stroke(WTColor.orange, lineWidth: 2.5))
        }
    }
}

// MARK: - Жетони призів

public struct WTLearnTokens: View {
    public struct Token: Equatable, Sendable {
        public let emoji: String
        public let title: String
        public let caption: String
        public init(emoji: String, title: String, caption: String) {
            self.emoji = emoji
            self.title = title
            self.caption = caption
        }
    }

    @Environment(\.wtLearnInk) private var ink
    @Environment(\.wtTheme) private var theme
    private let tokens: [Token]

    public init(tokens: [Token]) { self.tokens = tokens }

    public var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ForEach(tokens.indices, id: \.self) { index in
                VStack(spacing: 8) {
                    Text(tokens[index].emoji)
                        .font(.system(size: 34))
                        .frame(width: 72, height: 72)
                        .background(theme.prizeIconBg, in: Circle())
                    Text(tokens[index].title).font(WTFont.text(15, .black)).foregroundStyle(theme.textPrimary)
                    Text(tokens[index].caption).font(WTFont.text(12, .bold)).foregroundStyle(theme.textMuted)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 16)
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity)
                .background(theme.card, in: RoundedRectangle(cornerRadius: WTRadius.panel, style: .continuous))
                .wtStoryAppear(delay: 0.15 + Double(index) * 0.15, pop: true)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(tokens.map { "\($0.title): \($0.caption)" }.joined(separator: ", "))
    }
}

// MARK: - День із нагадуваннями

/// Вісь дня: краплі — порції, дзвіночки — нагадування там, де настала пауза.
public struct WTLearnDayLine: View {
    @Environment(\.wtLearnInk) private var ink
    private let drops: [Double]
    private let bells: [Double]
    private let start: String
    private let end: String

    /// Позиції — частки від підйому (0) до відбою (1).
    public init(drops: [Double], bells: [Double], start: String, end: String) {
        self.drops = drops
        self.bells = bells
        self.start = start
        self.end = end
    }

    public var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack(alignment: .topLeading) {
                Capsule().fill(ink.empty).frame(width: width, height: 6).offset(y: 70)
                ForEach(drops.indices, id: \.self) { index in
                    WTDropShape().fill(ink.fill)
                        .frame(width: 26, height: 32)
                        .offset(x: width * drops[index] - 13, y: 34)
                        .wtStoryAppear(delay: 0.2 + Double(index) * 0.15, pop: true)
                }
                ForEach(bells.indices, id: \.self) { index in
                    Text("🔔").font(.system(size: 24))
                        .offset(x: width * bells[index] - 14, y: 0)
                        .wtStoryAppear(delay: 1 + Double(index) * 0.3, pop: true)
                }
                Text(start).font(WTFont.text(12, .black)).foregroundStyle(ink.text.opacity(0.7)).offset(y: 86)
                Text(end).font(WTFont.text(12, .black)).foregroundStyle(ink.text.opacity(0.7))
                    .frame(width: width, alignment: .trailing).offset(y: 86)
            }
        }
        .frame(height: 110)
        .accessibilityHidden(true)
    }
}
