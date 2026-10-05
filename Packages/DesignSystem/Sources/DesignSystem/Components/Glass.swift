import SwiftUI

// Вікно «Склянка» (SPEC-NOTIFICATIONS §7.1, макет Design/Notifications.html, кадри 1–3).
// Склянка тут і візуал, і контрол: рівень води тягнуть пальцем, окремого повзунка немає.

public extension WTTheme {
    /// Контур склянки: на темному екрані напівпрозорий білий, на світлому — тон тексту.
    var glassStroke: Color { isDark ? Color.white.opacity(0.25) : textPrimary.opacity(0.2) }
    /// Глибина «води» внизу історій-звітів — третя зупинка градієнта кільця.
    var waterDeep: Color { isDark ? Color(hex: "#2a55c9") : textButton }
}

/// Контур склянки — трапеція з заокругленим дном. Пропорції з макета (220 × 290).
public struct WTGlassShape: Shape {
    public init() {}

    public func path(in rect: CGRect) -> Path {
        let sx = rect.width / 220, sy = rect.height / 290
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * sx, y: rect.minY + y * sy) }
        var path = Path()
        path.move(to: p(14, 14))
        path.addLine(to: p(206, 14))
        path.addLine(to: p(184, 266))
        path.addQuadCurve(to: p(168, 280), control: p(182, 280))
        path.addLine(to: p(52, 280))
        path.addQuadCurve(to: p(36, 266), control: p(38, 280))
        path.closeSubpath()
        return path
    }

    /// Рівень повної й порожньої склянки в координатах макета: вода не торкається країв.
    static let fullY: CGFloat = 30
    static let emptyY: CGFloat = 278

    static func levelY(_ fraction: Double, height: CGFloat) -> CGFloat {
        (emptyY - CGFloat(max(0, min(1, fraction))) * (emptyY - fullY)) * height / 290
    }
}

/// Поверхня води з хвилею. `phase` рухається в часі — без Reduce Motion.
struct WTWaterShape: Shape {
    var fraction: Double
    var phase: Double
    var amplitude: CGFloat = 4

    var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(fraction, phase) }
        set { fraction = newValue.first; phase = newValue.second }
    }

    func path(in rect: CGRect) -> Path {
        let level = WTGlassShape.levelY(fraction, height: rect.height)
        let wavelength = 22 * rect.width / 220
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        var x = rect.minX
        while x <= rect.maxX {
            path.addLine(to: CGPoint(x: x, y: level + sin(x / wavelength + phase) * amplitude))
            x += 4
        }
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// Склянка з водою — без взаємодії: калібрування, ілюстрації.
public struct WTGlassIllustration: View {
    @Environment(\.wtTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let fraction: Double
    private let waves: Bool

    public init(fraction: Double, waves: Bool = true) {
        self.fraction = fraction
        self.waves = waves
    }

    public var body: some View {
        TimelineView(.animation(paused: reduceMotion || !waves)) { context in
            let phase = reduceMotion || !waves ? 0 : context.date.timeIntervalSinceReferenceDate * 3
            ZStack {
                WTWaterShape(fraction: fraction, phase: phase, amplitude: waves ? 4 : 0)
                    .fill(LinearGradient(colors: [theme.ringStart, theme.ringEnd], startPoint: .top, endPoint: .bottom))
                    .clipShape(WTGlassShape())
                WTGlassShape().stroke(theme.glassStroke, style: StrokeStyle(lineWidth: 5, lineJoin: .round))
            }
        }
        .aspectRatio(220 / 290, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

/// Склянка-контрол (§7.1, п. 3): рівень іде за пальцем із кроком `step`, легкий «тік» на кожному
/// кроці. Для VoiceOver — регульований елемент ±`step`, значення дає викликач («175 мл, три чверті»).
public struct WTGlass: View {
    @Environment(\.wtTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding private var ml: Int
    private let capacity: Int
    private let step: Int
    private let minimum: Int
    private let accessibilityValueText: String

    public init(ml: Binding<Int>, capacity: Int, step: Int = 25, minimum: Int = 50, accessibilityValue: String) {
        _ml = ml
        self.capacity = capacity
        self.step = step
        self.minimum = minimum
        self.accessibilityValueText = accessibilityValue
    }

    private var fraction: Double { capacity > 0 ? Double(ml) / Double(capacity) : 0 }

    public var body: some View {
        GeometryReader { proxy in
            let height = proxy.size.height
            TimelineView(.animation(paused: reduceMotion)) { context in
                let phase = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate * 3
                ZStack(alignment: .top) {
                    WTWaterShape(fraction: fraction, phase: phase)
                        .fill(LinearGradient(colors: [theme.ringStart, theme.ringEnd], startPoint: .top, endPoint: .bottom))
                        .clipShape(WTGlassShape())
                    WTGlassShape().stroke(theme.glassStroke, style: StrokeStyle(lineWidth: 5, lineJoin: .round))
                    // «Ручка» на поверхні — підказка, що рівень можна тягнути.
                    Capsule()
                        .fill(Color.white.opacity(0.95))
                        .frame(width: proxy.size.width * 0.2, height: 6)
                        .offset(y: WTGlassShape.levelY(fraction, height: height) - 3)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0).onChanged { value in
                    let full = WTGlassShape.levelY(1, height: height), empty = WTGlassShape.levelY(0, height: height)
                    let fraction = (empty - value.location.y) / (empty - full)
                    set(Int((Double(fraction) * Double(capacity)).rounded()))
                }
            )
            .animation(reduceMotion ? nil : WTAnimation.press, value: ml)
        }
        .aspectRatio(220 / 290, contentMode: .fit)
        .wtFeedback(.toggle, trigger: ml)
        .accessibilityElement()
        .accessibilityLabel("Склянка")
        .accessibilityValue(accessibilityValueText)
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: set(ml + step)
            case .decrement: set(ml - step)
            @unknown default: break
            }
        }
        .accessibilityIdentifier("glass.control")
    }

    private func set(_ value: Int) {
        let stepped = Int((Double(value) / Double(step)).rounded()) * step
        let clamped = max(minimum, min(capacity, stepped))
        if clamped != ml { ml = clamped }
    }
}

/// Позначки часток праворуч від склянки: «Повна», «¾», «½», «¼» навпроти свого рівня.
public struct WTGlassTicks: View {
    @Environment(\.wtTheme) private var theme
    private let marks: [(title: String, fraction: Double)]
    private let current: Double

    /// Ширина колонки — «Повна» в один рядок; стільки ж відступу ліворуч тримає склянку по центру.
    public static let width: CGFloat = 58

    public init(marks: [(title: String, fraction: Double)], current: Double) {
        self.marks = marks
        self.current = current
    }

    public var body: some View {
        GeometryReader { proxy in
            ForEach(marks.indices, id: \.self) { index in
                let mark = marks[index]
                let on = mark.fraction <= current + 1e-6
                HStack(spacing: 5) {
                    Capsule().fill(on ? theme.accent : theme.dotOff).frame(width: 10, height: 2)
                    Text(mark.title)
                        .font(WTFont.text(12, .black))
                        .foregroundStyle(on ? theme.textButton : theme.textMuted)
                        .fixedSize()
                }
                .offset(y: WTGlassShape.levelY(mark.fraction, height: proxy.size.height) - 8)
            }
        }
        .frame(width: Self.width, alignment: .leading)
        .accessibilityHidden(true)
    }
}

/// Чип частки: «½» і під ним «125 мл».
public struct WTFractionChip: View {
    @Environment(\.wtTheme) private var theme
    private let title: String
    private let subtitle: String?
    private let isSelected: Bool
    private let numeric: Bool
    private let action: () -> Void

    /// `numeric` — заголовок-число (калібрування «200 / 250 / 300») набирається Fredoka.
    public init(_ title: String, subtitle: String? = nil, isSelected: Bool, numeric: Bool = false,
                action: @escaping () -> Void) {
        self.title = title
        self.subtitle = subtitle
        self.isSelected = isSelected
        self.numeric = numeric
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            VStack(spacing: 0) {
                Text(title)
                    .font(numeric ? WTFont.number(17, .semibold) : WTFont.text(17, .heavy))
                    .foregroundStyle(isSelected ? .white : theme.textButton)
                if let subtitle {
                    Text(subtitle)
                        .font(WTFont.text(11, .heavy))
                        .foregroundStyle(isSelected ? .white : theme.textMuted)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(isSelected ? theme.accent : theme.chip,
                        in: RoundedRectangle(cornerRadius: WTRadius.chip, style: .continuous))
        }
        .buttonStyle(WTPressStyle())
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Бульбашки, що повільно спливають на тлі вікна. Лише декор: без Reduce Motion і без VoiceOver.
public struct WTBubbles: View {
    @Environment(\.wtTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init() {}

    public var body: some View {
        if !reduceMotion {
            TimelineView(.animation) { context in
                GeometryReader { proxy in
                    let t = context.date.timeIntervalSinceReferenceDate
                    ForEach(0..<9, id: \.self) { index in
                        let size = CGFloat(8 + (index % 3) * 6)
                        let duration = Double(9 + (index % 4) * 3)
                        let progress = ((t + Double(index) * 1.7) / duration).truncatingRemainder(dividingBy: 1)
                        Circle()
                            .fill(theme.accent.opacity(0.10))
                            .frame(width: size, height: size)
                            .position(x: proxy.size.width * (0.08 + CGFloat(index) * 0.11),
                                      y: proxy.size.height + size - CGFloat(progress) * (proxy.size.height + size * 2))
                    }
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}

/// Стан «записано» після вікна «Склянка»: «+250», «мл · 13 % норми» і кільце дня.
public struct WTRecordedOverlay: View {
    @Environment(\.wtTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let amount: Int
    private let caption: String
    private let dayFraction: Double
    @State private var shown = false

    public init(amount: Int, caption: String, dayFraction: Double) {
        self.amount = amount
        self.caption = caption
        self.dayFraction = dayFraction
    }

    public var body: some View {
        ZStack {
            LinearGradient(colors: [theme.ringStart, theme.ringEnd], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            VStack(spacing: 8) {
                Text("+\(amount)")
                    .font(WTFont.number(72, .semibold))
                    .scaleEffect(shown || reduceMotion ? 1 : 0.6)
                Text(caption)
                    .font(WTFont.text(18, .heavy))
                ZStack {
                    Circle().stroke(Color.white.opacity(0.3), lineWidth: 12)
                    Circle()
                        .trim(from: 0, to: max(0.001, min(1, dayFraction)))
                        .stroke(Color.white, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                .frame(width: 120, height: 120)
                .padding(.top, 18)
            }
            .foregroundStyle(.white)
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) { shown = true }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("glass.recorded")
    }
}
