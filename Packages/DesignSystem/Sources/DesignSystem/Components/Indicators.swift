import SwiftUI

/// Кільце прогресу головного екрана: 242 pt, товщина 17, градієнт, старт з −90°.
public struct WTProgressRing: View {
    @Environment(\.wtTheme) private var theme
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
                .animation(WTAnimation.ring, value: progress)
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

    public init(level: Int, fraction: Double, diameter: CGFloat = 112) {
        self.level = level
        self.fraction = fraction
        self.diameter = diameter
    }

    public var body: some View {
        ZStack {
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

/// Горизонтальний XP-бар (шторка «Нагороди за рівні»).
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
            }
        }
        .frame(height: height)
    }
}
