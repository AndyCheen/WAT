import SwiftUI

// Звіт-історія (SPEC-NOTIFICATIONS §11, макет Design/Notifications.html, кадри 4–6): слайди-інфографіка,
// гортання тапом без автоперемикання. Компоненти не знають доменних моделей — лише прості значення.
// Кожен візуал програє свою появу в `onAppear`: програвач перестворює слайд на кожен перехід.
// Під Reduce Motion — одразу кінцевий стан.

public enum WTStoryStyle: Equatable, Sendable {
    /// Градієнт «вода», білий текст — обкладинки й «гра».
    case water
    /// Колір екрана — слайди з графіками.
    case plain
}

/// Програвач історії: смуги прогресу, заголовок періоду, ✕ і тап ліворуч / праворуч.
public struct WTStoryPlayer<Slide: View>: View {
    @Environment(\.wtTheme) private var theme
    private let count: Int
    @Binding private var index: Int
    private let header: String
    private let style: (Int) -> WTStoryStyle
    private let onClose: () -> Void
    private let slide: (Int) -> Slide

    public init(count: Int, index: Binding<Int>, header: String, style: @escaping (Int) -> WTStoryStyle,
                onClose: @escaping () -> Void, @ViewBuilder slide: @escaping (Int) -> Slide) {
        self.count = count
        _index = index
        self.header = header
        self.style = style
        self.onClose = onClose
        self.slide = slide
    }

    public var body: some View {
        let current = style(index)
        let ink: Color = current == .water ? .white : theme.textPrimary
        GeometryReader { proxy in
            ZStack(alignment: .top) {
                WTStoryBackground(style: current)
                slide(index)
                    .id(index)
                    .transition(.opacity)
                    .padding(.top, 76)
                    .padding(.horizontal, 28)
                    .padding(.bottom, WTSpacing.screenBottom)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

                VStack(spacing: 14) {
                    HStack(spacing: 4) {
                        ForEach(0..<count, id: \.self) { bar in
                            Capsule()
                                .fill(ink.opacity(bar <= index ? 1 : 0.25))
                                .frame(height: 3)
                        }
                    }
                    .accessibilityHidden(true)
                    HStack {
                        Text(header)
                            .font(WTFont.text(12, .black))
                            .tracking(0.5)
                            .foregroundStyle(current == .water ? Color.white.opacity(0.85) : theme.textMuted)
                        Spacer()
                        Button(action: onClose) {
                            WTIcons.close(color: current == .water ? .white : theme.accent, size: 12)
                                .frame(width: 34, height: 34)
                                .background(current == .water ? Color.white.opacity(0.25) : theme.chip, in: Circle())
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(WTPressStyle())
                        .accessibilityLabel("Закрити")
                        .accessibilityIdentifier("report.close")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }
            .contentShape(Rectangle())
            // Кнопки слайда забирають свій тап самі — сюди доходить лише тап по «полотну».
            .onTapGesture(coordinateSpace: .local) { location in
                withAnimation(WTAnimation.fade) {
                    if location.x < proxy.size.width / 3 { index = max(0, index - 1) }
                    else { index = min(count - 1, index + 1) }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: "Далі") { withAnimation(WTAnimation.fade) { index = min(count - 1, index + 1) } }
        .accessibilityAction(named: "Назад") { withAnimation(WTAnimation.fade) { index = max(0, index - 1) } }
    }
}

/// Тло слайда. «Вода» — градієнт кільця прогресу до глибшого синього внизу.
public struct WTStoryBackground: View {
    @Environment(\.wtTheme) private var theme
    private let style: WTStoryStyle

    public init(style: WTStoryStyle) { self.style = style }

    public var body: some View {
        Group {
            switch style {
            case .water:
                LinearGradient(stops: [.init(color: theme.ringStart, location: 0), .init(color: theme.ringEnd, location: 0.7),
                                       .init(color: theme.waterDeep, location: 1)],
                               startPoint: .top, endPoint: .bottom)
            case .plain:
                theme.screen
            }
        }
        .ignoresSafeArea()
    }
}

/// Дві хвилі, що наливаються знизу до `level` (частка висоти) і погойдуються.
public struct WTStoryWaves: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let level: Double
    @State private var filled = false

    public init(level: Double) { self.level = level }

    public var body: some View {
        GeometryReader { proxy in
            TimelineView(.animation(paused: reduceMotion)) { context in
                let t = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate
                ZStack(alignment: .bottom) {
                    wave(proxy, level: level, sway: sin(t / 1.0) * 0.06, opacity: 0.16)
                    wave(proxy, level: level * 0.88, sway: -sin(t / 1.2) * 0.06, opacity: 0.10)
                }
            }
            .offset(y: filled || reduceMotion ? 0 : proxy.size.height * level)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear { withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 1.6)) { filled = true } }
    }

    private func wave(_ proxy: GeometryProxy, level: Double, sway: Double, opacity: Double) -> some View {
        Ellipse()
            .fill(Color.white.opacity(opacity))
            .frame(width: proxy.size.width * 2, height: proxy.size.height * level * 2)
            .offset(x: proxy.size.width * sway, y: proxy.size.height * level)
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .bottom)
    }
}

/// Поява елемента слайда: знизу вгору з затримкою. Без Reduce Motion.
public struct WTStoryAppear: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let delay: Double
    let pop: Bool
    @State private var visible = false

    public func body(content: Content) -> some View {
        content
            .opacity(visible || reduceMotion ? 1 : 0)
            .offset(y: visible || reduceMotion || pop ? 0 : 14)
            .scaleEffect(pop && !(visible || reduceMotion) ? 0.3 : 1)
            .onAppear {
                guard !reduceMotion else { return }
                let animation: Animation = pop
                    ? .spring(response: 0.5, dampingFraction: 0.55)
                    : .timingCurve(0.22, 1, 0.36, 1, duration: 0.55)
                withAnimation(animation.delay(delay)) { visible = true }
            }
    }
}

public extension View {
    /// `pop` — «вистрибує» з масштабу, для емодзі й бейджів.
    func wtStoryAppear(delay: Double = 0, pop: Bool = false) -> some View {
        modifier(WTStoryAppear(delay: delay, pop: pop))
    }
}

/// Число, що наростає від нуля: «13,3», «1 140». Кома десяткова, пробіл між тисячами.
public struct WTCountUpText: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let value: Double
    private let decimals: Int
    private let delay: Double
    @State private var shown: Double = 0

    public init(_ value: Double, decimals: Int = 0, delay: Double = 0.2) {
        self.value = value
        self.decimals = decimals
        self.delay = delay
    }

    public var body: some View {
        WTCountingText(value: reduceMotion ? value : shown, decimals: decimals)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 1.1).delay(delay)) { shown = value }
            }
            .accessibilityLabel(WTCountingText.format(value, decimals: decimals))
    }
}

struct WTCountingText: View, Animatable {
    var value: Double
    let decimals: Int

    var animatableData: Double {
        get { value }
        set { value = newValue }
    }

    var body: some View { Text(Self.format(value, decimals: decimals)).monospacedDigit() }

    static func format(_ value: Double, decimals: Int) -> String {
        let text = String(format: "%.\(decimals)f", value).replacingOccurrences(of: ".", with: ",")
        let parts = text.split(separator: ",", maxSplits: 1)
        var integer = String(parts[0])
        var grouped = ""
        while integer.count > 3 {
            grouped = "\u{00a0}" + integer.suffix(3) + grouped
            integer = String(integer.dropLast(3))
        }
        return integer + grouped + (parts.count > 1 ? "," + parts[1] : "")
    }
}

/// Пігулка під графіком: «▲ 8 % проти минулого тижня».
public struct WTStoryPill: View {
    public enum Tone: Sendable { case positive, negative, onWater }
    @Environment(\.wtTheme) private var theme
    private let text: String
    private let tone: Tone

    public init(_ text: String, tone: Tone) {
        self.text = text
        self.tone = tone
    }

    public var body: some View {
        let (fill, ink): (Color, Color) = switch tone {
        case .positive: (WTColor.successText.opacity(0.14), WTColor.successText)
        case .negative: (WTColor.orange.opacity(0.14), WTColor.orange)
        case .onWater: (Color.white.opacity(0.22), .white)
        }
        Text(text)
            .font(WTFont.text(14, .black))
            .foregroundStyle(ink)
            .padding(.horizontal, 14)
            .frame(minHeight: 34)
            .background(fill, in: Capsule())
    }
}

/// Сітка крапель — «53 склянки»; краплі вистрибують по черзі.
public struct WTDropGrid: View {
    private let count: Int
    private let columns: Int
    private let color: Color

    public init(count: Int, columns: Int = 9, color: Color = .white.opacity(0.95)) {
        self.count = count
        self.columns = columns
        self.color = color
    }

    public var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 7), count: columns), spacing: 7) {
            ForEach(0..<count, id: \.self) { index in
                WTDropShape().fill(color)
                    .frame(width: 22, height: 28)
                    .wtStoryAppear(delay: 0.5 + Double(index) * min(0.025, 1.3 / Double(max(count, 1))), pop: true)
            }
        }
        .accessibilityHidden(true)
    }
}

/// Склянка дня, що наливається до частки норми; пунктир — норма.
public struct WTStoryGlass: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let fraction: Double
    @State private var shown: Double = 0

    public init(fraction: Double) { self.fraction = fraction }

    public var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .top) {
                WTWaterShape(fraction: reduceMotion ? min(1, fraction) : shown, phase: 0, amplitude: 0)
                    .fill(Color.white.opacity(0.9))
                    .clipShape(WTGlassShape())
                WTGlassShape().stroke(Color.white.opacity(0.7), lineWidth: 6)
                Rectangle()
                    .stroke(style: StrokeStyle(lineWidth: 3, dash: [8, 7]))
                    .foregroundStyle(.white)
                    .frame(height: 0.5)
                    .padding(.horizontal, proxy.size.width * 0.09)
                    .offset(y: WTGlassShape.levelY(1, height: proxy.size.height))
            }
        }
        .aspectRatio(220 / 290, contentMode: .fit)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 1.6).delay(0.2)) { shown = min(1, fraction) }
        }
        .accessibilityHidden(true)
    }
}

/// Таймлайн дня: від підйому до відбою, блоки цілей (✓ — суцільна рамка, ні — пунктир), краплі
/// падають у час своїх порцій, над блоками — підписи.
public struct WTDayTimeline: View {
    public struct Block: Equatable, Sendable {
        public let from: Double
        public let to: Double
        public let reached: Bool
        public let label: String
        public init(from: Double, to: Double, reached: Bool, label: String) {
            self.from = from
            self.to = to
            self.reached = reached
            self.label = label
        }
    }

    @Environment(\.wtTheme) private var theme
    private let blocks: [Block]
    private let drops: [Double]
    private let ticks: [(position: Double, label: String)]

    /// Позиції — частки від підйому (0) до відбою (1).
    public init(blocks: [Block], drops: [Double], ticks: [(position: Double, label: String)]) {
        self.blocks = blocks
        self.drops = drops
        self.ticks = ticks
    }

    public var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack(alignment: .topLeading) {
                Capsule().fill(theme.track).frame(width: width, height: 4).offset(y: 92)
                ForEach(blocks.indices, id: \.self) { index in
                    let block = blocks[index]
                    let x = width * block.from + 3, w = width * (block.to - block.from) - 6
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(block.reached ? WTColor.successText.opacity(0.16) : .clear)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(block.reached ? WTColor.successText.opacity(0.55) : theme.dotOff,
                                        style: StrokeStyle(lineWidth: 2, dash: block.reached ? [] : [5, 4]))
                        )
                        .frame(width: max(0, w), height: 20)
                        .offset(x: x, y: 84)
                    Text(block.label)
                        .font(WTFont.text(12, .black))
                        .foregroundStyle(block.reached ? WTColor.successText : theme.textMuted)
                        .fixedSize()
                        .frame(width: max(0, w))
                        .offset(x: x, y: 44)
                        .wtStoryAppear(delay: 1.6)
                }
                ForEach(drops.indices, id: \.self) { index in
                    WTDropShape().fill(theme.accent)
                        .frame(width: 22, height: 28)
                        .modifier(WTFall(delay: 0.2 + Double(index) * 0.15))
                        .offset(x: width * drops[index] - 11)
                }
                ForEach(ticks.indices, id: \.self) { index in
                    Text(ticks[index].label)
                        .font(WTFont.text(11, .black))
                        .foregroundStyle(theme.textMuted)
                        .fixedSize()
                        .frame(width: 44)
                        .offset(x: min(max(0, width * ticks[index].position - 22), width - 44), y: 116)
                }
            }
        }
        .frame(height: 140)
        .accessibilityHidden(true)
    }
}

/// Крапля падає згори на вісь таймлайну.
struct WTFall: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let delay: Double
    @State private var landed = false

    func body(content: Content) -> some View {
        content
            .opacity(landed || reduceMotion ? 1 : 0)
            .offset(y: landed || reduceMotion ? 58 : -40)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.spring(response: 0.5, dampingFraction: 0.6).delay(delay)) { landed = true }
            }
    }
}

/// Сім крапель тижня: закрита норма — наповнена акцентом, ні — блідий рівень.
public struct WTWeekDrops: View {
    @Environment(\.wtTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let items: [(label: String, met: Bool)]
    @State private var filled = false

    public init(items: [(label: String, met: Bool)]) { self.items = items }

    public var body: some View {
        HStack {
            ForEach(items.indices, id: \.self) { index in
                let item = items[index]
                VStack(spacing: 8) {
                    ZStack(alignment: .bottom) {
                        WTDropShape().fill(theme.track)
                        GeometryReader { proxy in
                            Rectangle()
                                .fill(item.met ? theme.accent : theme.dotOff)
                                .frame(height: proxy.size.height * (item.met ? 1 : 0.45))
                                .frame(maxHeight: .infinity, alignment: .bottom)
                                .scaleEffect(y: filled || reduceMotion ? 1 : 0.001, anchor: .bottom)
                                .animation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.7).delay(0.3 + Double(index) * 0.15),
                                           value: filled)
                        }
                        .mask(WTDropShape())
                    }
                    .frame(width: 40, height: 52)
                    Text(item.label)
                        .font(WTFont.text(12, .black))
                        .foregroundStyle(theme.textMuted)
                }
                if index < items.count - 1 { Spacer(minLength: 0) }
            }
        }
        .onAppear { filled = true }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(items.map { "\($0.label) \($0.met ? "норма" : "без норми")" }.joined(separator: ", "))
    }
}

/// Стовпці тижня, що виростають; найкращий день — помаранчевий з 👑, пунктир — норма.
public struct WTStoryBars: View {
    public struct Bar: Equatable, Sendable {
        public let label: String
        public let fraction: Double
        public let met: Bool
        public let isBest: Bool
        public init(label: String, fraction: Double, met: Bool, isBest: Bool) {
            self.label = label
            self.fraction = fraction
            self.met = met
            self.isBest = isBest
        }
    }

    @Environment(\.wtTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let bars: [Bar]
    private let goalFraction: Double
    private let goalLabel: String
    @State private var grown = false

    public init(bars: [Bar], goalFraction: Double, goalLabel: String) {
        self.bars = bars
        self.goalFraction = goalFraction
        self.goalLabel = goalLabel
    }

    public var body: some View {
        GeometryReader { proxy in
            let chart = proxy.size.height - 26
            ZStack(alignment: .bottomLeading) {
                HStack(alignment: .bottom, spacing: 10) {
                    ForEach(bars.indices, id: \.self) { index in
                        let bar = bars[index]
                        VStack(spacing: 6) {
                            Spacer(minLength: 0)
                            if bar.isBest {
                                Text("👑").font(.system(size: 22)).wtStoryAppear(delay: 1.3, pop: true)
                            }
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(fill(bar))
                                .frame(maxWidth: 34)
                                .frame(height: chart * min(1, bar.fraction))
                                .scaleEffect(y: grown || reduceMotion ? 1 : 0.001, anchor: .bottom)
                                .animation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.8).delay(0.2 + Double(index) * 0.1),
                                           value: grown)
                            Text(bar.label)
                                .font(WTFont.text(12, .black))
                                .foregroundStyle(theme.textMuted)
                                .frame(height: 14)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                Rectangle()
                    .stroke(style: StrokeStyle(lineWidth: 2, dash: [6, 5]))
                    .foregroundStyle(theme.textPrimary.opacity(0.3))
                    .frame(height: 0.5)
                    .overlay(alignment: .bottomTrailing) {
                        Text(goalLabel).font(WTFont.text(11, .black)).foregroundStyle(theme.textMuted).offset(y: -6)
                    }
                    .offset(y: -(20 + chart * min(1, goalFraction)))
            }
        }
        .onAppear { grown = true }
        .accessibilityHidden(true)
    }

    private func fill(_ bar: Bar) -> AnyShapeStyle {
        if bar.isBest { return AnyShapeStyle(LinearGradient(colors: [WTColor.orange, WTColor.orange.opacity(0.6)],
                                                            startPoint: .top, endPoint: .bottom)) }
        return AnyShapeStyle(bar.met ? theme.accent : theme.dotOff)
    }
}

/// Дуга доби: від підйому до відбою, частини доби — сегменти. Товщина й колір — скільки від
/// потрібного: ≥ 90 % — акцент, ≥ 60 % — блідий акцент, менше — помаранчевий. 🌇 — на найслабшій.
public struct WTDayArc: View {
    public struct Segment: Equatable, Sendable {
        public let title: String
        public let ratio: Double
        public init(title: String, ratio: Double) {
            self.title = title
            self.ratio = ratio
        }
    }

    @Environment(\.wtTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let segments: [Segment]
    private let markIndex: Int?
    private let startLabel: String
    private let endLabel: String
    @State private var drawn = false

    public init(segments: [Segment], markIndex: Int?, startLabel: String, endLabel: String) {
        self.segments = segments
        self.markIndex = markIndex
        self.startLabel = startLabel
        self.endLabel = endLabel
    }

    public var body: some View {
        GeometryReader { proxy in
            let radius = min(proxy.size.width / 2 - 40, proxy.size.height - 40)
            let center = CGPoint(x: proxy.size.width / 2, y: radius + 30)
            let span = Double.pi / Double(max(1, segments.count))
            ZStack {
                ForEach(segments.indices, id: \.self) { index in
                    let segment = segments[index]
                    let start = Double.pi + Double(index) * span + 0.05
                    let end = Double.pi + Double(index + 1) * span - 0.05
                    Path { path in
                        path.addArc(center: center, radius: radius, startAngle: .radians(start), endAngle: .radians(end),
                                    clockwise: false)
                    }
                    .trim(from: 0, to: drawn || reduceMotion ? 1 : 0)
                    .stroke(color(segment.ratio), style: StrokeStyle(lineWidth: 8 + min(segment.ratio, 1.2) * 20, lineCap: .round))
                    .animation(.easeOut(duration: 0.8).delay(0.2 + Double(index) * 0.25), value: drawn)
                    let middle = (start + end) / 2
                    // Довгі назви («Ранок і полудень») — у два рядки й не ближче за 46 pt до краю.
                    Text(segment.title)
                        .font(WTFont.text(12, .heavy))
                        .foregroundStyle(theme.textMuted)
                        .multilineTextAlignment(.center)
                        .frame(width: 88)
                        .position(x: min(max(center.x + (radius + 40) * cos(middle), 46), proxy.size.width - 46),
                                  y: center.y + (radius + 40) * sin(middle) - 6)
                }
                if let markIndex {
                    let angle = Double.pi + (Double(markIndex) + 0.5) * span
                    Text("🌇")
                        .font(.system(size: 26))
                        .position(x: center.x + (radius - 46) * cos(angle), y: center.y + (radius - 46) * sin(angle))
                        .wtStoryAppear(delay: 1.8, pop: true)
                }
                Text(startLabel).font(WTFont.text(12, .heavy)).foregroundStyle(theme.textMuted)
                    .position(x: center.x - radius, y: center.y + 26)
                Text(endLabel).font(WTFont.text(12, .heavy)).foregroundStyle(theme.textMuted)
                    .position(x: center.x + radius, y: center.y + 26)
            }
        }
        .frame(height: 210)
        .onAppear { drawn = true }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(segments.map { "\($0.title): \(Int(($0.ratio * 100).rounded())) %" }.joined(separator: ", "))
    }

    private func color(_ ratio: Double) -> Color {
        if ratio >= 0.9 { return theme.accent }
        if ratio >= 0.6 { return theme.accent.opacity(0.55) }
        return WTColor.orange
    }
}

/// Біле кільце рівня на «воді»: «РІВЕНЬ / 8» або «6→8».
public struct WTStoryLevelRing: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let value: String
    private let fraction: Double
    @State private var shown: Double = 0

    public init(value: String, fraction: Double) {
        self.value = value
        self.fraction = fraction
    }

    public var body: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.25), lineWidth: 14)
            Circle()
                .trim(from: 0, to: max(0.001, reduceMotion ? fraction : shown))
                .stroke(Color.white, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text("РІВЕНЬ").font(WTFont.text(12, .black)).tracking(0.4).opacity(0.8)
                Text(value).font(WTFont.number(52, .semibold))
            }
            .wtStoryAppear(delay: 1.2, pop: true)
        }
        .foregroundStyle(.white)
        .frame(width: 170, height: 170)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 1.4).delay(0.3)) { shown = fraction }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Ланцюжок серії: кружки з підписами, з'єднані рисками; з'являються по черзі.
public struct WTStoryChain: View {
    @Environment(\.wtTheme) private var theme
    private let labels: [String]

    public init(labels: [String]) { self.labels = labels }

    public var body: some View {
        HStack(spacing: 0) {
            ForEach(labels.indices, id: \.self) { index in
                if index > 0 {
                    Rectangle().fill(Color.white.opacity(0.6)).frame(width: 8, height: 3)
                        .wtStoryAppear(delay: 0.6 + Double(index) * 0.07, pop: true)
                }
                Text(labels[index])
                    .font(WTFont.text(12, .black))
                    .foregroundStyle(theme.waterDeep)
                    .frame(width: 30, height: 30)
                    .background(Color.white.opacity(0.95), in: Circle())
                    .wtStoryAppear(delay: 0.6 + Double(index) * 0.07, pop: true)
            }
        }
        .accessibilityHidden(true)
    }
}

/// Мозаїка місяця: комірки днів з'являються по черзі. Помаранчева рамка — найдовша серія.
public struct WTMonthMosaic: View {
    public enum CellState: Equatable, Sendable { case met, partial, empty, future }
    public struct Cell: Equatable, Sendable {
        public let label: String
        public let state: CellState
        public let highlighted: Bool
        public init(label: String, state: CellState, highlighted: Bool) {
            self.label = label
            self.state = state
            self.highlighted = highlighted
        }
    }

    @Environment(\.wtTheme) private var theme
    private let weekdayLabels: [String]
    private let leadingBlanks: Int
    private let cells: [Cell]

    public init(weekdayLabels: [String], leadingBlanks: Int, cells: [Cell]) {
        self.weekdayLabels = weekdayLabels
        self.leadingBlanks = leadingBlanks
        self.cells = cells
    }

    public var body: some View {
        // Ідентифікатори різні для кожної групи: з однаковими 0…6 сітка зливала назви днів,
        // порожні клітинки й перший тиждень місяця в одні й ті самі комірки.
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 7), spacing: 8) {
            ForEach(weekdayLabels.indices.map { "weekday.\($0)" }, id: \.self) { id in
                let index = Int(id.dropFirst("weekday.".count)) ?? 0
                Text(weekdayLabels[index]).font(WTFont.text(11, .black)).foregroundStyle(theme.textMuted)
            }
            ForEach((0..<leadingBlanks).map { "blank.\($0)" }, id: \.self) { _ in Color.clear.frame(height: 40) }
            ForEach(cells.indices.map { "day.\($0)" }, id: \.self) { id in
                let index = Int(id.dropFirst("day.".count)) ?? 0
                let cell = cells[index]
                Text(cell.label)
                    .font(WTFont.text(12, .black))
                    .foregroundStyle(cell.state == .met || cell.state == .partial ? .white : theme.textMuted)
                    .frame(width: 40, height: 40)
                    .background(fill(cell.state), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(cell.highlighted ? WTColor.orange : .clear, lineWidth: 3)
                    )
                    .wtStoryAppear(delay: 0.2 + Double(index) * 0.045, pop: true)
            }
        }
        .accessibilityHidden(true)
    }

    private func fill(_ state: CellState) -> Color {
        switch state {
        case .met: return theme.accent
        case .partial: return theme.accent.opacity(0.45)
        case .empty: return theme.dotOff
        case .future: return theme.track
        }
    }
}

/// Відра по 10 л — «понад 5 відер»; наливаються по черзі.
public struct WTBuckets: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let fractions: [Double]
    @State private var filled = false

    public init(fractions: [Double]) { self.fractions = fractions }

    public var body: some View {
        HStack(spacing: 10) {
            ForEach(fractions.indices, id: \.self) { index in
                ZStack(alignment: .bottom) {
                    GeometryReader { proxy in
                        Rectangle()
                            .fill(Color.white.opacity(0.95))
                            .frame(height: proxy.size.height * fractions[index])
                            .frame(maxHeight: .infinity, alignment: .bottom)
                            .scaleEffect(y: filled || reduceMotion ? 1 : 0.001, anchor: .bottom)
                            .animation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.9).delay(0.6 + Double(index) * 0.2),
                                       value: filled)
                    }
                    .mask(WTBucketShape())
                    WTBucketShape().stroke(Color.white, style: StrokeStyle(lineWidth: 2.5, lineJoin: .round))
                }
                .frame(width: 50, height: 52)
                .overlay(alignment: .top) {
                    Path { path in
                        path.move(to: CGPoint(x: 8, y: 0))
                        path.addQuadCurve(to: CGPoint(x: 42, y: 0), control: CGPoint(x: 25, y: -14))
                    }
                    .stroke(Color.white, lineWidth: 2)
                }
            }
        }
        .onAppear { filled = true }
        .accessibilityHidden(true)
    }
}

struct WTBucketShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + rect.width * 0.08, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - rect.width * 0.08, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - rect.width * 0.18, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.18, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// Два стовпці поруч — «будні проти вихідних»; другий — помаранчевий.
public struct WTVersusBars: View {
    public struct Item: Equatable, Sendable {
        public let value: String
        public let label: String
        public let fraction: Double
        public init(value: String, label: String, fraction: Double) {
            self.value = value
            self.label = label
            self.fraction = fraction
        }
    }

    @Environment(\.wtTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let items: [Item]
    @State private var grown = false

    public init(items: [Item]) { self.items = items }

    public var body: some View {
        HStack(alignment: .bottom, spacing: 18) {
            ForEach(items.indices, id: \.self) { index in
                let item = items[index]
                VStack(spacing: 8) {
                    Text(item.value).font(WTFont.number(26, .semibold)).foregroundStyle(theme.textPrimary)
                    UnevenRoundedRectangle(topLeadingRadius: 18, bottomLeadingRadius: 10, bottomTrailingRadius: 10,
                                           topTrailingRadius: 18, style: .continuous)
                        .fill(index == 0 ? theme.accent : WTColor.orange)
                        .frame(width: 84, height: 150 * min(1, item.fraction))
                        .scaleEffect(y: grown || reduceMotion ? 1 : 0.001, anchor: .bottom)
                        .animation(.timingCurve(0.22, 1, 0.36, 1, duration: 1).delay(0.3 + Double(index) * 0.2), value: grown)
                    Text(item.label).font(WTFont.text(13, .black)).foregroundStyle(theme.textMuted)
                }
                .frame(width: 120)
            }
        }
        .frame(maxWidth: .infinity)
        .onAppear { grown = true }
        .accessibilityElement(children: .combine)
    }
}

/// Плашки на «воді»: «🎉 Новий рівень», «🏅 2 досягнення».
public struct WTStoryBadges: View {
    private let texts: [String]

    public init(_ texts: [String]) { self.texts = texts }

    public var body: some View {
        WTFlowLayout(spacing: 10) {
            ForEach(texts.indices, id: \.self) { index in
                Text(texts[index])
                    .font(WTFont.text(14, .black))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .frame(minHeight: 40)
                    .background(Color.white.opacity(0.22), in: Capsule())
                    .wtStoryAppear(delay: 1.5 + Double(index) * 0.15, pop: true)
            }
        }
    }
}

/// Рядки, що переносяться по ширині, — по центру.
public struct WTFlowLayout: Layout {
    private let spacing: CGFloat

    public init(spacing: CGFloat) { self.spacing = spacing }

    public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let height = rows.reduce(0) { $0 + $1.height } + spacing * CGFloat(max(0, rows.count - 1))
        return CGSize(width: proposal.width ?? rows.map(\.width).max() ?? 0, height: height)
    }

    public func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.midX - row.width / 2
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y + (row.height - size.height) / 2), proposal: .unspecified)
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> [(indices: [Int], width: CGFloat, height: CGFloat)] {
        var rows: [(indices: [Int], width: CGFloat, height: CGFloat)] = []
        var current: (indices: [Int], width: CGFloat, height: CGFloat) = ([], 0, 0)
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let next = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            if next > width, !current.indices.isEmpty {
                rows.append(current)
                current = ([index], size.width, size.height)
            } else {
                current = (current.indices + [index], next, max(current.height, size.height))
            }
        }
        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }
}
