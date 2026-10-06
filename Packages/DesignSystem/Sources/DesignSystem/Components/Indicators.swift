import SwiftUI

/// Кільце прогресу головного екрана: 242 pt, товщина 17, градієнт, старт з −90°.
public struct WTProgressRing: View {
    @Environment(\.wtTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let progress: Double
    private let diameter: CGFloat
    private let lineWidth: CGFloat

    public init(progress: Double, diameter: CGFloat = 242, lineWidth: CGFloat = 20.6) {
        self.progress = progress
        self.diameter = diameter
        self.lineWidth = lineWidth
    }

    public var body: some View {
        ZStack {
            Circle()
                .stroke(theme.track, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.001, min(1, progress)))
                .stroke(
                    LinearGradient(
                        colors: [theme.ringStart, theme.ringEnd],
                        startPoint: .top,
                        endPoint: UnitPoint(x: 0.4, y: 1)
                    ),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                // Пружина трохи перелітає ціль — при Reduce Motion це зайвий рух.
                .animation(reduceMotion ? WTAnimation.fade : WTAnimation.ring, value: progress)
        }
        .padding(lineWidth / 2)
        .frame(width: diameter, height: diameter)
    }
}

/// Донат рівня (макет 3f): conic-градієнт + внутрішнє коло кольору екрана.
public struct WTLevelDonut: View {
    @Environment(\.wtTheme) private var theme
    private let level: Int
    private let fraction: Double
    private let diameter: CGFloat
    private let boostBadge: String?
    private let isNew: Bool

    /// - Parameters:
    ///   - boostBadge: «⚡ ×2» — діє подвійний XP (WAT-34).
    ///   - isNew: на шляху рівнів чекає вибір чи таємний приз (WAT-44) — крапка «нове».
    public init(level: Int, fraction: Double, diameter: CGFloat = 112, boostBadge: String? = nil, isNew: Bool = false) {
        self.level = level
        self.fraction = fraction
        self.diameter = diameter
        self.boostBadge = boostBadge
        self.isNew = isNew
    }

    public var body: some View {
        ZStack {
            // Заливка донату — стопи `AngularGradient` не інтерполюються, тому вона
            // лишається статичною основою…
            Circle()
                .fill(
                    AngularGradient(
                        stops: [
                            .init(color: theme.accent, location: 0),
                            .init(color: theme.accent, location: max(0.001, min(1, fraction))),
                            .init(color: theme.track, location: max(0.001, min(1, fraction))),
                            .init(color: theme.track, location: 1)
                        ],
                        center: .center,
                        startAngle: .degrees(-90),
                        endAngle: .degrees(270)
                    )
                )
            // …а рух дає обвід, який уміє анімувати `trim`. Без нього приріст XP
            // стрибав без переходу.
            Circle()
                .trim(from: 0, to: max(0.001, min(1, fraction)))
                .stroke(theme.accent, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .padding(4)
                .animation(WTAnimation.ring, value: fraction)
            Circle()
                .fill(theme.screen)
                .padding(8)
            VStack(spacing: 0) {
                Text("\(level)")
                    .font(WTFont.number(32, .bold))
                    .foregroundStyle(theme.textPrimary)
                Text("РІВЕНЬ")
                    .font(WTFont.text(10, .heavy))
                    .tracking(0.3)
                    .foregroundStyle(theme.textMuted)
            }
        }
        .frame(width: diameter, height: diameter)
        .overlay(alignment: .topTrailing) {
            // Крапка на колі, а не в куті рамки: донат круглий, і кут рамки від нього далеко.
            if isNew { WTNewDot().scaleEffect(1.4).offset(x: -diameter * 0.1, y: diameter * 0.1) }
        }
        .overlay(alignment: .bottomTrailing) {
            if let boostBadge {
                WTBoostBadge(label: boostBadge, fontSize: 13, border: theme.screen)
                    .fixedSize()
                    .offset(x: 8, y: -2)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(WTAnimation.toast, value: boostBadge)
    }
}

/// Кільце «N/M» на екрані досягнень (макет 2e).
public struct WTCountRing: View {
    @Environment(\.wtTheme) private var theme
    private let value: Int
    private let total: Int

    public init(value: Int, total: Int) {
        self.value = value
        self.total = total
    }

    public var body: some View {
        ZStack {
            Circle()
                .stroke(Color(hex: "#dce8f3"), lineWidth: 7)
            Circle()
                .trim(from: 0, to: total > 0 ? Double(value) / Double(total) : 0)
                .stroke(theme.accent, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(value)/\(total)")
                .font(WTFont.number(14, .semibold))
                .foregroundStyle(theme.textPrimary)
        }
        .padding(3.5)
        .frame(width: 62, height: 62)
    }
}

/// Лічильник набору «ВІДКРИТО / 3 / 24» (екран 2e, SPEC-ACHIEVEMENTS §5.2).
///
/// Свідомо без смуги й кільця: частку видно із самої сітки, а число однаково
/// доречне і для 7, і для 240 елементів — верстка від розміру каталогу не залежить.
/// Пара «маленький лейбл — велике число» та сама, що й у донаті рівня на 3f.
public struct WTStatCounter: View {
    @Environment(\.wtTheme) private var theme
    private let label: String
    private let value: Int
    private let total: Int

    public init(label: String, value: Int, total: Int) {
        self.label = label
        self.value = value
        self.total = total
    }

    public var body: some View {
        VStack(spacing: 4) {
            Text(label)
                .font(WTFont.text(11, .heavy))
                .tracking(0.3)
                .foregroundStyle(theme.textMuted)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(value)")
                    .font(WTFont.number(34, .semibold))
                    .foregroundStyle(theme.accent)
                    .contentTransition(.numericText(value: Double(value)))
                Text("/ \(total)")
                    .font(WTFont.number(20, .medium))
                    .foregroundStyle(theme.textMuted)
            }
        }
        .frame(maxWidth: .infinity)
        // Лейбл і число — один елемент для VoiceOver; підпис задає екран.
        .accessibilityElement(children: .ignore)
    }
}

/// Горизонтальний бар: XP у шапці шляху рівнів, час буста, ліміти.
public struct WTProgressBar: View {
    @Environment(\.wtTheme) private var theme
    private let fraction: Double
    private let height: CGFloat
    private let fill: Color?
    private let track: Color?

    public init(fraction: Double, height: CGFloat = 10, fill: Color? = nil, track: Color? = nil) {
        self.fraction = fraction
        self.height = height
        self.fill = fill
        self.track = track
    }

    public var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(track ?? theme.track)
                Capsule()
                    .fill(fill ?? theme.accent)
                    .frame(width: proxy.size.width * max(0, min(1, fraction)))
                    .animation(WTAnimation.ring, value: fraction)
            }
        }
        .frame(height: height)
    }
}

/// Капсула поточної частини доби під кільцем головного (WAT-40, `Design/DayPart.html`, варіант A).
///
/// Кільце — доба, капсула — її частина; міні-кільце всередині — частка цілі частини. Рядок лише
/// інформує: тапу немає, бо порцію додають кнопки під ним. Усі тексти готує екран.
public struct WTDayPartPill: View {
    public enum Content: Equatable, Sendable {
        /// «До 12:00 — ще 100 мл» · «+10 XP» · «35 хв».
        case pending(fraction: Double, title: String, xp: String, timeLeft: String)
        /// «Ранок і полудень закрито».
        case closed(title: String)
    }

    @Environment(\.wtTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let content: Content
    private let accessibilityLabel: String

    public init(_ content: Content, accessibilityLabel: String) {
        self.content = content
        self.accessibilityLabel = accessibilityLabel
    }

    public var body: some View {
        HStack(spacing: 8) {
            switch content {
            case let .pending(fraction, title, xp, timeLeft):
                miniRing(fraction)
                Text(title)
                    .foregroundStyle(theme.textPrimary)
                separator
                Text(xp)
                    .font(WTFont.text(14, .black))
                    .foregroundStyle(theme.textButton)
                separator
                Text(timeLeft)
                    .foregroundStyle(theme.textMuted)
            case let .closed(title):
                ZStack {
                    Circle().fill(WTColor.success)
                    WTIcons.check(color: .white, size: 12)
                }
                .frame(width: 24, height: 24)
                .transition(reduceMotion ? .opacity : .scale(scale: 0.3).combined(with: .opacity))
                Text(title)
                    .foregroundStyle(WTColor.successText)
            }
        }
        .font(WTFont.text(14, .heavy))
        .lineLimit(1)
        .minimumScaleFactor(0.85)
        .padding(.leading, 7)
        .padding(.trailing, 14)
        .frame(height: 38)
        .background(isClosed ? WTColor.successText.opacity(0.12) : theme.chip, in: Capsule())
        .animation(reduceMotion ? WTAnimation.fade : WTAnimation.toast, value: isClosed)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var isClosed: Bool {
        if case .closed = content { return true }
        return false
    }

    private var separator: some View {
        Text("·").foregroundStyle(theme.textMuted)
    }

    private func miniRing(_ fraction: Double) -> some View {
        ZStack {
            Circle().stroke(theme.dotOff, lineWidth: 4)
            Circle()
                .trim(from: 0, to: max(0.001, min(1, fraction)))
                .stroke(theme.accent, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(reduceMotion ? WTAnimation.fade : WTAnimation.ring, value: fraction)
        }
        .padding(2)
        .frame(width: 24, height: 24)
    }
}
