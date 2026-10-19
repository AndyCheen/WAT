import SwiftUI

// Інтерактивні слайди «Знань» (SPEC-LEARN §4, §5.1: `quiz`, `scale`, `appDemo`). Стан — лише в самій
// в'юсі: історію перегорнули — стан скинувся, у профіль нічого не пишеться. Тапи забирають кнопки, тож
// програвач їх не перехоплює й слайд не гортається.

// MARK: - Картка, що перевертається

/// Вікторина (рішення від 19.10.2026: переворот узято з варіанту B): твердження — на лицьовому боці,
/// відповідь — на звороті. Під Reduce Motion — без обертання, просто зміна боку.
public struct WTLearnFlipCard<Front: View, Back: View>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let flipped: Bool
    private let front: Front
    private let back: Back

    public init(flipped: Bool, @ViewBuilder front: () -> Front, @ViewBuilder back: () -> Back) {
        self.flipped = flipped
        self.front = front()
        self.back = back()
    }

    public var body: some View {
        let angle = flipped ? 180.0 : 0
        ZStack {
            front.modifier(WTFlipSide(angle: reduceMotion ? (flipped ? 180 : 0) : angle, isBack: false, rotates: !reduceMotion))
            back.modifier(WTFlipSide(angle: reduceMotion ? (flipped ? 180 : 0) : angle, isBack: true, rotates: !reduceMotion))
        }
        .animation(reduceMotion ? WTAnimation.fade : .spring(response: 0.65, dampingFraction: 0.82), value: flipped)
    }
}

/// Бік картки видно лише свою половину оберту — інакше крізь лицьовий проступав би зворот.
private struct WTFlipSide: ViewModifier, Animatable {
    var angle: Double
    let isBack: Bool
    let rotates: Bool

    var animatableData: Double {
        get { angle }
        set { angle = newValue }
    }

    func body(content: Content) -> some View {
        let showing = isBack ? angle >= 90 : angle < 90
        // `hidden()`, а не прозорість: прозорий бік лишався б у дереві доступності, і VoiceOver читав би
        // кнопки «Правда / Міф» уже після відповіді.
        Group {
            if showing { content } else { content.hidden() }
        }
            .rotation3DEffect(.degrees(rotates ? (isBack ? angle - 180 : angle) : 0), axis: (x: 0, y: 1, z: 0),
                              perspective: 0.45)
    }
}

// MARK: - Шкала кольору

/// Вісім відтінків від світлого до темного (шкала Armstrong, SPEC-LEARN §10): тап — оцінка під шкалою.
public struct WTLearnColorScale: View {
    @Environment(\.wtLearnInk) private var ink
    @Environment(\.wtTheme) private var theme
    private let verdicts: [String]
    private let prompt: String
    @State private var selected: Int?

    /// Відтінки з шкали — сталі, не залежать від теми: це колір у житті, а не в інтерфейсі.
    public static let swatches: [Color] = ["#fbf8d6", "#f8f1a8", "#f4e77a", "#efd84f", "#e6c335", "#d7aa2a", "#c18e25",
                                           "#9f6f1f"].map { Color(hex: $0) }

    /// - Parameter verdicts: по одному на відтінок, від світлого до темного.
    public init(verdicts: [String], prompt: String) {
        self.verdicts = verdicts
        self.prompt = prompt
    }

    public var body: some View {
        VStack(spacing: 18) {
            HStack(spacing: 6) {
                ForEach(Self.swatches.indices, id: \.self) { index in
                    Button {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) { selected = index }
                    } label: {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Self.swatches[index])
                            .frame(width: 34, height: 72)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(selected == index ? ink.text : Color.black.opacity(0.06), lineWidth: selected == index ? 3 : 1)
                            )
                            .scaleEffect(selected == index ? 1.12 : 1)
                    }
                    .buttonStyle(WTPressStyle(scale: 0.94))
                    .accessibilityLabel("Відтінок \(index + 1) з \(Self.swatches.count)")
                    .accessibilityIdentifier("learn.scale.\(index)")
                    .wtStoryAppear(delay: 0.1 + Double(index) * 0.06, pop: true)
                }
            }
            Text(selected.map { verdicts.indices.contains($0) ? verdicts[$0] : "" } ?? prompt)
                .font(WTFont.text(18, .heavy))
                .foregroundStyle(ink.text)
                .multilineTextAlignment(.center)
                .frame(minHeight: 50)
                .id(selected ?? -1)
                .transition(.opacity)
                .accessibilityIdentifier("learn.scale.verdict")
        }
        .wtFeedback(.toggle, trigger: selected)
    }
}

// MARK: - Крива дня

/// «Усе разом» проти «потроху»: скільки води в запасі протягом дня. Перемикач — дві пігулки над графіком.
public struct WTLearnCurve: View {
    @Environment(\.wtLearnInk) private var ink
    @Environment(\.wtTheme) private var theme
    private let modes: [String]
    private let captions: [String]
    private let start: String
    private let end: String
    @State private var mode = 0

    public init(modes: [String], captions: [String], start: String, end: String) {
        self.modes = modes
        self.captions = captions
        self.start = start
        self.end = end
    }

    public var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 6) {
                ForEach(modes.indices, id: \.self) { index in
                    Button { withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.8)) { mode = index } } label: {
                        Text(modes[index])
                            .font(WTFont.text(14, .heavy))
                            .foregroundStyle(mode == index ? ink.onFill : ink.text)
                            .padding(.horizontal, 16)
                            .frame(height: 38)
                            .background(mode == index ? ink.fill : ink.empty, in: Capsule())
                    }
                    .buttonStyle(WTPressStyle())
                    .accessibilityIdentifier("learn.curve.\(index)")
                }
            }
            ZStack(alignment: .bottomLeading) {
                WTDayCurveShape(blend: Double(mode)).fill(ink.soft.opacity(0.6))
                WTDayCurveShape(blend: Double(mode), isLine: true).stroke(ink.fill, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                GeometryReader { proxy in
                    ForEach(drops.indices, id: \.self) { index in
                        WTDropShape().fill(ink.fill)
                            .frame(width: 16, height: 20)
                            .position(x: proxy.size.width * drops[index], y: proxy.size.height + 18)
                    }
                }
            }
            .frame(height: 150)
            .padding(.bottom, 26)
            HStack {
                Text(start)
                Spacer()
                Text(end)
            }
            .font(WTFont.text(12, .black))
            .foregroundStyle(ink.text.opacity(0.7))
            Text(captions.indices.contains(mode) ? captions[mode] : "")
                .font(WTFont.text(16, .heavy))
                .foregroundStyle(ink.text)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .id(mode)
                .transition(.opacity)
        }
        .wtFeedback(.toggle, trigger: mode)
        .accessibilityElement(children: .contain)
    }

    /// Порції: усе ввечері — дві великі, потроху — вісім рівно.
    private var drops: [Double] {
        mode == 0 ? [0.78, 0.84] : (0..<8).map { 0.06 + Double($0) * 0.125 }
    }
}

/// Запас води в тілі за день. `blend` 0 — «усе разом» (спад до вечора, сплеск і швидкий спад),
/// 1 — «потроху» (рівне плато).
struct WTDayCurveShape: Shape {
    var blend: Double
    var isLine = false

    var animatableData: Double {
        get { blend }
        set { blend = newValue }
    }

    func path(in rect: CGRect) -> Path {
        func spike(_ x: Double) -> Double {
            if x < 0.76 { return 0.42 - 0.22 * x / 0.76 }
            if x < 0.84 { return 0.2 + 0.72 * (x - 0.76) / 0.08 }
            return max(0.32, 0.92 - 0.6 * (x - 0.84) / 0.12)
        }
        func steady(_ x: Double) -> Double {
            0.42 + 0.14 * min(1, x / 0.1) + 0.035 * sin(x * 2 * .pi * 8 - 2.95)
        }
        var path = Path()
        let steps = 80
        for step in 0...steps {
            let x = Double(step) / Double(steps)
            let y = spike(x) * (1 - blend) + steady(x) * blend
            let point = CGPoint(x: rect.minX + rect.width * x, y: rect.maxY - rect.height * y)
            if step == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        if !isLine {
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.closeSubpath()
        }
        return path
    }
}

// MARK: - Чипи-якорі

/// Обери кілька варіантів: щойно вибрано `limit`, під чипами — підсумок.
public struct WTLearnChips: View {
    @Environment(\.wtLearnInk) private var ink
    private let options: [String]
    private let limit: Int
    private let prompt: String
    private let summary: ([String]) -> String
    @State private var selected: [Int] = []

    public init(options: [String], limit: Int, prompt: String, summary: @escaping ([String]) -> String) {
        self.options = options
        self.limit = limit
        self.prompt = prompt
        self.summary = summary
    }

    public var body: some View {
        VStack(spacing: 18) {
            WTFlowLayout(spacing: 10) {
                ForEach(options.indices, id: \.self) { index in
                    let isOn = selected.contains(index)
                    Button { toggle(index) } label: {
                        Text(options[index])
                            .font(WTFont.text(15, .heavy))
                            .foregroundStyle(isOn ? ink.onFill : ink.text)
                            .padding(.horizontal, 16)
                            .frame(height: 44)
                            .background(isOn ? ink.fill : ink.empty, in: Capsule())
                    }
                    .buttonStyle(WTPressStyle())
                    .accessibilityAddTraits(isOn ? .isSelected : [])
                    .accessibilityIdentifier("learn.chip.\(index)")
                    .wtStoryAppear(delay: 0.1 + Double(index) * 0.08, pop: true)
                }
            }
            Text(selected.count == limit ? summary(selected.map { options[$0] }) : prompt)
                .font(WTFont.text(16, .heavy))
                .foregroundStyle(ink.text)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .id(selected.count == limit)
                .transition(.opacity)
                .accessibilityIdentifier("learn.chips.summary")
        }
        .wtFeedback(.toggle, trigger: selected)
    }

    private func toggle(_ index: Int) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
            if let position = selected.firstIndex(of: index) {
                selected.remove(at: position)
            } else {
                // Понад ліміт — найстаріший вибір поступається новому: «обери два», а не «зніми зайве».
                if selected.count == limit { selected.removeFirst() }
                selected.append(index)
            }
        }
    }
}

// MARK: - Міні-головний

/// Кільце й кнопки порцій: тап — кільце росте, як на головному. Нічого не записується.
public struct WTLearnMiniHome: View {
    @Environment(\.wtLearnInk) private var ink
    @Environment(\.wtTheme) private var theme
    private let goal: Int
    private let buttons: [(title: String, ml: Int)]
    private let volume: (Int) -> String
    @State private var total = 0

    public init(goal: Int, buttons: [(title: String, ml: Int)], volume: @escaping (Int) -> String) {
        self.goal = goal
        self.buttons = buttons
        self.volume = volume
    }

    public var body: some View {
        VStack(spacing: 22) {
            ZStack {
                WTProgressRing(progress: Double(total) / Double(max(goal, 1)), diameter: 190, lineWidth: 16)
                VStack(spacing: 2) {
                    Text("\(Int((Double(total) / Double(max(goal, 1)) * 100).rounded()))%")
                        .font(WTFont.number(44, .semibold))
                        .contentTransition(.numericText(value: Double(total)))
                        .accessibilityIdentifier("learn.demo.percent")
                    Text(volume(total)).font(WTFont.text(14, .bold)).foregroundStyle(theme.textMuted)
                }
                .foregroundStyle(theme.textPrimary)
            }
            .padding(18)
            .background(theme.card, in: Circle())
            HStack(spacing: 10) {
                ForEach(buttons.indices, id: \.self) { index in
                    WTQuickButton(buttons[index].title) {
                        withAnimation(WTAnimation.ring) { total += buttons[index].ml }
                    }
                    .accessibilityIdentifier("learn.demo.add.\(index)")
                }
            }
        }
        .wtFeedback(.add, trigger: total)
    }
}

// MARK: - Що додає до норми

/// Стовпець потреби з базою й перемикачами чинників: увімкнений чинник надбудовує стовпець.
public struct WTLearnFactors: View {
    public struct Factor: Equatable, Sendable {
        public let emoji: String
        public let title: String
        public let add: Double
        public init(emoji: String, title: String, add: Double) {
            self.emoji = emoji
            self.title = title
            self.add = add
        }
    }

    @Environment(\.wtLearnInk) private var ink
    private let base: Double
    private let baseLabel: String
    private let factors: [Factor]
    private let format: (Double) -> String
    @State private var on: Set<Int> = []

    public init(base: Double, baseLabel: String, factors: [Factor], format: @escaping (Double) -> String) {
        self.base = base
        self.baseLabel = baseLabel
        self.factors = factors
        self.format = format
    }

    private var shape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(topLeadingRadius: 18, bottomLeadingRadius: 10, bottomTrailingRadius: 10,
                               topTrailingRadius: 18, style: .continuous)
    }

    public var body: some View {
        let added = on.reduce(0) { $0 + factors[$1].add }
        let maximum = base + factors.reduce(0) { $0 + $1.add }
        let height: CGFloat = 190
        VStack(spacing: 16) {
            VStack(spacing: 8) {
                Text(format(base + added))
                    .font(WTFont.text(22, .black))
                    .foregroundStyle(ink.text)
                    .contentTransition(.numericText(value: base + added))
                    .accessibilityIdentifier("learn.factors.total")
                // Привид повного стовпця — видно, куди ще може вирости потреба.
                ZStack(alignment: .bottom) {
                    shape.fill(ink.empty)
                    VStack(spacing: 0) {
                        Rectangle().fill(WTColor.orange).frame(height: height * added / maximum)
                        Rectangle().fill(ink.fill).frame(height: height * base / maximum)
                            .overlay(alignment: .bottom) {
                                Text(baseLabel).font(WTFont.text(12, .black)).foregroundStyle(ink.onFill).padding(.bottom, 8)
                            }
                    }
                    .clipShape(shape)
                }
                .frame(width: 96, height: height)
            }
            WTFlowLayout(spacing: 8) {
                ForEach(factors.indices, id: \.self) { index in
                    let isOn = on.contains(index)
                    Button {
                        withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
                            if isOn { on.remove(index) } else { on.insert(index) }
                        }
                    } label: {
                        Text("\(factors[index].emoji) \(factors[index].title)")
                            .font(WTFont.text(14, .heavy))
                            .foregroundStyle(isOn ? .white : ink.text)
                            .padding(.horizontal, 14)
                            .frame(height: 40)
                            .background(isOn ? WTColor.orange : ink.empty, in: Capsule())
                    }
                    .buttonStyle(WTPressStyle())
                    .accessibilityAddTraits(isOn ? .isSelected : [])
                    .accessibilityIdentifier("learn.factor.\(index)")
                }
            }
        }
        .wtFeedback(.toggle, trigger: on)
    }
}
