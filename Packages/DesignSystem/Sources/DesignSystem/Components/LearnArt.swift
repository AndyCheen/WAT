import SwiftUI

// Ілюстрації розділу «Знання» (SPEC-LEARN §5.5, макет Design/Learn.html, варіант A «Історії»).
// Векторні, з «чорнила» полиці (`WTLearnInk`): той самий малюнок біліє на воді, помаранчевіє на теплому тлі
// й синіє на кольорі екрана, у тому числі в темній темі. Поява — в `onAppear` (програвач перестворює слайд на
// кожен перехід), безкінечний рух — лише через `TimelineView`: `withAnimation(.repeatForever)` уже тягнув за
// собою шапку (WAT-44). Під Reduce Motion — одразу кінцевий стан.

public extension WTTheme {
    /// Верх «води» полиці «Вода й тіло» — між `ringStart` і `ringEnd`.
    var learnWaterTop: Color { isDark ? Color(hex: "#65a0fa") : Color(hex: "#95ccf8") }
    /// «Звички»: глибока вода до нічного неба віджетів.
    var learnDeepStops: [Color] {
        isDark ? [Color(hex: "#3b6ef5"), WTColor.nightSkyTop, WTColor.nightSkyBottom]
               : [Color(hex: "#6bb6f2"), Color(hex: "#3b6ef5"), WTColor.nightSkyTop]
    }
    /// «Застосунок»: теплий фон призів.
    var learnWarmStops: [Color] {
        isDark ? [Color(hex: "#3a2a1c"), Color(hex: "#2a1f16")] : [Color(hex: "#fff8ec"), WTColor.prizeIconBg]
    }
}

/// Кольори ілюстрації на тлі слайда: порожнє, заповнення, м'яке заповнення, текст.
public struct WTLearnInk: Equatable, Sendable {
    public let empty: Color
    public let fill: Color
    public let soft: Color
    public let text: Color
    /// Підкладка під емодзі й бейджі.
    public let badge: Color
    /// Текст і галочки поверх заповнення: на білій «воді» — глибокий синій, на кольоровому — білий.
    public let onFill: Color

    public static func of(_ style: WTStoryStyle, theme: WTTheme) -> WTLearnInk {
        switch style {
        case .water, .learnWater, .learnDeep:
            return WTLearnInk(empty: .white.opacity(0.22), fill: .white.opacity(0.96), soft: .white.opacity(0.55),
                              text: .white, badge: .white.opacity(0.22), onFill: theme.waterDeep)
        case .learnWarm:
            return WTLearnInk(empty: WTColor.orange.opacity(0.16), fill: WTColor.orange, soft: Color(hex: "#ffb27a"),
                              text: theme.textPrimary, badge: theme.card, onFill: .white)
        case .plain:
            return WTLearnInk(empty: theme.track, fill: theme.accent, soft: theme.ringStart, text: theme.textPrimary,
                              badge: theme.chip, onFill: .white)
        }
    }
}

private struct WTLearnInkKey: EnvironmentKey {
    static let defaultValue = WTLearnInk.of(.plain, theme: .light)
}

public extension EnvironmentValues {
    /// Задає слайд «Знань» за своїм стилем — ілюстрації всередині про тло не знають.
    var wtLearnInk: WTLearnInk {
        get { self[WTLearnInkKey.self] }
        set { self[WTLearnInkKey.self] = newValue }
    }
}

// MARK: - Хвиля

/// Поверхня води до `level` (частка висоти між `top` і `bottom`) з хвилею, що біжить за `phase`.
struct WTLearnWave: Shape {
    var level: Double
    var phase: Double
    var amplitude: CGFloat
    var top: CGFloat = 0
    var bottom: CGFloat = 1

    var animatableData: Double {
        get { level }
        set { level = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let yTop = rect.minY + rect.height * top, yBottom = rect.minY + rect.height * bottom
        let y = yBottom - CGFloat(max(0, min(1, level))) * (yBottom - yTop)
        let wavelength = rect.width / 1.6
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        var x = rect.minX
        while x <= rect.maxX + 4 {
            path.addLine(to: CGPoint(x: x, y: y + sin(x / wavelength * 2 * .pi + phase) * amplitude))
            x += 4
        }
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// Рівень, що наливається від нуля на появі.
private struct WTFillOnAppear: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let target: Double
    let delay: Double
    @Binding var value: Double

    func body(content: Content) -> some View {
        content.onAppear {
            guard !reduceMotion else { value = target; return }
            withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 1.6).delay(delay)) { value = target }
        }
    }
}

// MARK: - Крапля

/// Обкладинка полиці «Вода й тіло»: крапля, що наливається, хвилі й бульбашки.
public struct WTLearnDrop: View {
    @Environment(\.wtLearnInk) private var ink
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let level: Double
    @State private var shown: Double = 0

    public init(level: Double = 0.55) { self.level = level }

    public var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack {
                WTDropShape().fill(ink.empty)
                TimelineView(.animation(paused: reduceMotion)) { context in
                    let t = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate
                    ZStack {
                        WTLearnWave(level: shown, phase: t * 1.8, amplitude: size.height * 0.022, top: 0.083, bottom: 0.915)
                            .fill(ink.soft)
                        WTLearnWave(level: shown - 0.04, phase: -t * 1.3 + 1, amplitude: size.height * 0.018,
                                    top: 0.083, bottom: 0.915)
                            .fill(ink.fill)
                        if !reduceMotion { bubbles(t: t, size: size) }
                    }
                }
                .mask(WTDropShape())
                WTDropShape().stroke(ink.fill.opacity(0.75), lineWidth: max(2, size.width * 0.015))
                Ellipse()
                    .fill(Color.white.opacity(0.55))
                    .frame(width: size.width * 0.08, height: size.height * 0.19)
                    .rotationEffect(.degrees(24))
                    .position(x: size.width * 0.36, y: size.height * 0.5)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .modifier(WTFillOnAppear(target: level, delay: 0.2, value: $shown))
        .accessibilityHidden(true)
    }

    private func bubbles(t: Double, size: CGSize) -> some View {
        ForEach(0..<4, id: \.self) { index in
            let progress = (t * 0.28 + Double(index) * 0.27).truncatingRemainder(dividingBy: 1)
            let x = size.width * (0.42 + 0.06 * Double(index % 3)) + sin(t * 2 + Double(index)) * 4
            let y = size.height * (0.88 - 0.42 * progress)
            Circle()
                .fill(ink.fill)
                .frame(width: size.width * (0.02 + 0.008 * Double(index % 2)))
                .opacity(progress < 0.8 ? 0.85 : (1 - progress) * 4)
                .position(x: x, y: y)
        }
    }
}

// MARK: - Емодзі-значок

/// Обкладинка без власної ілюстрації: емодзі в колі, довкола повільно ходять три крапки.
public struct WTLearnEmoji: View {
    @Environment(\.wtLearnInk) private var ink
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let emoji: String

    public init(_ emoji: String) { self.emoji = emoji }

    public var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            ZStack {
                Circle().fill(ink.empty).frame(width: side * 0.8, height: side * 0.8)
                Text(emoji).font(.system(size: side * 0.38))
                    .wtStoryAppear(delay: 0.15, pop: true)
                TimelineView(.animation(paused: reduceMotion)) { context in
                    let angle = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate * 0.6
                    ForEach(0..<3, id: \.self) { index in
                        let a = angle + Double(index) * 2.1
                        Circle()
                            .fill(ink.soft)
                            .frame(width: side * (0.05 + 0.02 * Double(index)), height: side * (0.05 + 0.02 * Double(index)))
                            .offset(x: cos(a) * side * 0.46, y: sin(a) * side * 0.46)
                    }
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

// MARK: - Тіло

/// Силует людини в сітці 200 × 300: голова, тулуб, руки трохи врізнобіч, ноги. Підшляхи перетинаються —
/// заливка з ненульовим правилом дає один силует.
public struct WTBodyShape: Shape {
    public init() {}

    public func path(in rect: CGRect) -> Path {
        let sx = rect.width / 200, sy = rect.height / 300
        func r(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect {
            CGRect(x: rect.minX + x * sx, y: rect.minY + y * sy, width: w * sx, height: h * sy)
        }
        var path = Path()
        path.addEllipse(in: r(73, 13, 54, 54))
        path.addRoundedRect(in: r(58, 74, 84, 124), cornerSize: CGSize(width: 32 * sx, height: 32 * sy))
        for (x, angle) in [(CGFloat(36), 14.0), (CGFloat(140), -14.0)] {
            let arm = Path(roundedRect: r(x, 80, 24, 104), cornerSize: CGSize(width: 12 * sx, height: 12 * sy))
            let pivot = CGPoint(x: rect.minX + (x + 12) * sx, y: rect.minY + 84 * sy)
            let transform = CGAffineTransform(translationX: pivot.x, y: pivot.y)
                .rotated(by: angle * .pi / 180)
                .translatedBy(x: -pivot.x, y: -pivot.y)
            path.addPath(arm, transform: transform)
        }
        path.addRoundedRect(in: r(66, 150, 31, 142), cornerSize: CGSize(width: 15.5 * sx, height: 15.5 * sy))
        path.addRoundedRect(in: r(103, 150, 31, 142), cornerSize: CGSize(width: 15.5 * sx, height: 15.5 * sy))
        return path
    }
}

/// Силует, що наливається водою до `fraction`; з `badges` — карта тіла: емодзі там, де вода працює.
public struct WTLearnBody: View {
    @Environment(\.wtLearnInk) private var ink
    @Environment(\.wtTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let fraction: Double
    private let badges: [String]
    @State private var shown: Double = 0

    /// Точки карти тіла (частки ширини й висоти): шкіра руки, кров у грудях, коліно, нирки.
    private static let points: [CGPoint] = [CGPoint(x: 0.23, y: 0.45), CGPoint(x: 0.5, y: 0.33),
                                            CGPoint(x: 0.4, y: 0.8), CGPoint(x: 0.6, y: 0.56)]

    public init(fraction: Double, badges: [String] = []) {
        self.fraction = fraction
        self.badges = badges
    }

    public var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack {
                WTBodyShape().fill(badges.isEmpty ? ink.empty : ink.soft)
                if badges.isEmpty {
                    TimelineView(.animation(paused: reduceMotion)) { context in
                        let t = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate
                        ZStack {
                            WTLearnWave(level: shown, phase: t * 1.6, amplitude: size.height * 0.012, top: 0.043, bottom: 0.973)
                                .fill(ink.soft)
                            WTLearnWave(level: shown - 0.02, phase: -t * 1.2, amplitude: size.height * 0.01,
                                        top: 0.043, bottom: 0.973)
                                .fill(ink.fill)
                        }
                    }
                    .mask(WTBodyShape())
                }
                ForEach(badges.indices, id: \.self) { index in
                    let point = Self.points[index % Self.points.count]
                    Text(badges[index])
                        .font(.system(size: size.width * 0.12))
                        .frame(width: size.width * 0.24, height: size.width * 0.24)
                        .background(theme.card, in: Circle())
                        .shadow(color: WTShadow.card.color.opacity(3), radius: 6, y: 3)
                        .position(x: size.width * point.x, y: size.height * point.y)
                        .wtStoryAppear(delay: 0.25 + Double(index) * 0.14, pop: true)
                }
            }
        }
        .aspectRatio(2.0 / 3.0, contentMode: .fit)
        .modifier(WTFillOnAppear(target: fraction, delay: 0.15, value: $shown))
        .accessibilityHidden(true)
    }
}

// MARK: - Питання

/// Вікторина: крапля з «?», що похитується.
public struct WTLearnQuestion: View {
    @Environment(\.wtLearnInk) private var ink
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init() {}

    public var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { context in
            let t = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate
            GeometryReader { proxy in
                ZStack {
                    WTDropShape().fill(ink.empty)
                    Text("?")
                        .font(WTFont.number(proxy.size.height * 0.42, .semibold))
                        .foregroundStyle(ink.fill)
                        .offset(y: proxy.size.height * 0.1)
                }
                .rotationEffect(.degrees(sin(t * 2.1) * 4), anchor: .bottom)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

// MARK: - Рівень

/// Крапля рівня з номером і зірочками, що мерехтять.
public struct WTLearnLevel: View {
    @Environment(\.wtLearnInk) private var ink
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let level: Int

    public init(level: Int) { self.level = level }

    public var body: some View {
        GeometryReader { proxy in
            let side = proxy.size.width
            ZStack {
                WTDropShape().fill(ink.empty)
                WTDropShape().stroke(ink.fill.opacity(0.7), lineWidth: max(2, side * 0.015))
                VStack(spacing: 0) {
                    Text("РІВЕНЬ").font(WTFont.text(side * 0.07, .black)).tracking(1.5)
                    Text("\(level)").font(WTFont.number(side * 0.36, .semibold))
                }
                .foregroundStyle(ink.fill)
                .offset(y: side * 0.13)
                .wtStoryAppear(delay: 0.2, pop: true)
                TimelineView(.animation(paused: reduceMotion)) { context in
                    let t = reduceMotion ? 1.0 : context.date.timeIntervalSinceReferenceDate
                    ForEach(Self.sparkles.indices, id: \.self) { index in
                        let spark = Self.sparkles[index]
                        let pulse = reduceMotion ? 1 : 0.55 + 0.45 * sin(t * 2.6 + Double(index) * 1.7)
                        WTSparkleShape()
                            .fill(ink.fill)
                            .frame(width: side * spark.z, height: side * spark.z)
                            .scaleEffect(pulse)
                            .opacity(pulse)
                            .position(x: side * spark.x, y: side * spark.y)
                    }
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }

    private static let sparkles: [(x: Double, y: Double, z: Double)] = [
        (0.18, 0.28, 0.08), (0.84, 0.38, 0.1), (0.76, 0.14, 0.06), (0.14, 0.66, 0.06)
    ]
}

/// Чотирикутна зірочка.
struct WTSparkleShape: Shape {
    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY), r = min(rect.width, rect.height) / 2, k = r * 0.26
        var path = Path()
        path.move(to: CGPoint(x: c.x, y: c.y - r))
        path.addLine(to: CGPoint(x: c.x + k, y: c.y - k))
        path.addLine(to: CGPoint(x: c.x + r, y: c.y))
        path.addLine(to: CGPoint(x: c.x + k, y: c.y + k))
        path.addLine(to: CGPoint(x: c.x, y: c.y + r))
        path.addLine(to: CGPoint(x: c.x - k, y: c.y + k))
        path.addLine(to: CGPoint(x: c.x - r, y: c.y))
        path.addLine(to: CGPoint(x: c.x - k, y: c.y - k))
        path.closeSubpath()
        return path
    }
}

// MARK: - Плитки

/// Два ряди по дві: емодзі в колі й підпис — «Втома · Увага · Голова · Настрій».
public struct WTLearnTiles: View {
    public struct Item: Equatable, Sendable {
        public let emoji: String
        public let caption: String
        public init(emoji: String, caption: String) {
            self.emoji = emoji
            self.caption = caption
        }
    }

    @Environment(\.wtLearnInk) private var ink
    private let items: [Item]

    public init(items: [Item]) { self.items = items }

    public var body: some View {
        LazyVGrid(columns: [GridItem(.fixed(130), spacing: 18), GridItem(.fixed(130))], spacing: 18) {
            ForEach(items.indices, id: \.self) { index in
                VStack(spacing: 8) {
                    Text(items[index].emoji)
                        .font(.system(size: 38))
                        .frame(width: 86, height: 86)
                        .background(ink.empty, in: Circle())
                    Text(items[index].caption)
                        .font(WTFont.text(14, .heavy))
                        .foregroundStyle(ink.text)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .wtStoryAppear(delay: 0.15 + Double(index) * 0.12, pop: true)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(items.map(\.caption).joined(separator: ", "))
    }
}
