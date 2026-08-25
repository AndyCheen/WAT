import SwiftUI

/// Дані одного стовпчика — DesignSystem не знає про доменні типи.
public struct WTBar: Identifiable, Equatable, Sendable {
    public let id: String
    public let label: String
    public let value: Double
    public let topLabel: String?
    public let isHighlighted: Bool

    public init(id: String, label: String, value: Double, topLabel: String? = nil, isHighlighted: Bool = false) {
        self.id = id
        self.label = label
        self.value = value
        self.topLabel = topLabel
        self.isHighlighted = isHighlighted
    }
}

/// Стовпчиковий графік з пунктирною лінією цілі (макет 4a, «Обʼєм по днях»).
public struct WTBarChart: View {
    @Environment(\.wtTheme) private var theme
    private let bars: [WTBar]
    private let maxValue: Double
    private let goalValue: Double?
    private let height: CGFloat
    private let barMaxWidth: CGFloat?

    public init(
        bars: [WTBar],
        maxValue: Double,
        goalValue: Double? = nil,
        height: CGFloat = 130,
        barMaxWidth: CGFloat? = 26
    ) {
        self.bars = bars
        self.maxValue = maxValue
        self.goalValue = goalValue
        self.height = height
        self.barMaxWidth = barMaxWidth
    }

    private func barHeight(_ value: Double) -> CGFloat {
        guard maxValue > 0 else { return 10 }
        return max(value > 0 ? 10 : 4, CGFloat(value / maxValue) * (height - 20))
    }

    public var body: some View {
        VStack(spacing: 8) {
            ZStack(alignment: .bottom) {
                if let goalValue, maxValue > 0 {
                    VStack {
                        Spacer()
                        Line()
                            .stroke(theme.textMuted, style: StrokeStyle(lineWidth: 2, dash: [5, 4]))
                            .frame(height: 2)
                            .padding(.bottom, barHeight(goalValue))
                    }
                }

                HStack(alignment: .bottom, spacing: 6) {
                    ForEach(bars) { bar in
                        VStack(spacing: 6) {
                            if let topLabel = bar.topLabel {
                                Text(topLabel)
                                    .font(WTFont.text(11, .heavy))
                                    .foregroundStyle(theme.textMuted)
                            }
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(bar.value > 0 ? (bar.isHighlighted ? theme.ringEnd : theme.accent) : WTColor.neutralEmpty)
                                .frame(maxWidth: barMaxWidth)
                                .frame(height: barHeight(bar.value))
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
            .frame(height: height)

            HStack(spacing: 6) {
                ForEach(bars) { bar in
                    Text(bar.label)
                        .font(WTFont.text(12, .heavy))
                        .foregroundStyle(theme.textMuted)
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }
}

struct Line: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.width, y: rect.midY))
        return path
    }
}

/// Рядок «Рівномірність за день»: смуга випитого + ризка цілі.
public struct WTEvennessRowView: View {
    @Environment(\.wtTheme) private var theme
    private let label: String
    private let valueLabel: String
    private let fraction: Double
    private let tickFraction: Double

    public init(label: String, valueLabel: String, fraction: Double, tickFraction: Double) {
        self.label = label
        self.valueLabel = valueLabel
        self.fraction = fraction
        self.tickFraction = tickFraction
    }

    public var body: some View {
        HStack(spacing: 10) {
            Text(label)
                .font(WTFont.text(13, .bold))
                .foregroundStyle(WTColor.textSecondary)
                .frame(width: 66, alignment: .leading)

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(WTColor.neutralTrack)
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(theme.accent)
                        .frame(width: proxy.size.width * max(0, min(1, fraction)))
                    Rectangle()
                        .fill(WTColor.textTertiary)
                        .frame(width: 2)
                        .padding(.vertical, -3)
                        .offset(x: proxy.size.width * max(0, min(1, tickFraction)) - 1)
                }
            }
            .frame(height: 16)

            Text(valueLabel)
                .font(WTFont.text(12, .bold))
                .foregroundStyle(theme.textMuted)
                .frame(width: 58, alignment: .trailing)
        }
    }
}

/// Рядок «Типова доба»: медіана + міжквартильний розкид + ризка цілі.
public struct WTMedianSpreadRow: View {
    @Environment(\.wtTheme) private var theme
    private let label: String
    private let percentLabel: String
    private let median: Double
    private let low: Double
    private let high: Double
    private let ideal: Double

    public init(
        label: String, percentLabel: String,
        median: Double, low: Double, high: Double, ideal: Double
    ) {
        self.label = label
        self.percentLabel = percentLabel
        self.median = median
        self.low = low
        self.high = high
        self.ideal = ideal
    }

    /// Частки нормуємо до 60 % ширини — щоб типові 30–40 % не тиснулись у ліву третину.
    private static let scale: Double = 1 / 0.6

    private func clamp(_ value: Double) -> Double { max(0, min(1, value * Self.scale)) }

    public var body: some View {
        HStack(spacing: 10) {
            Text(label)
                .font(WTFont.text(13, .bold))
                .foregroundStyle(WTColor.textSecondary)
                .frame(width: 66, alignment: .leading)

            GeometryReader { proxy in
                let width = proxy.size.width
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(WTColor.neutralTrack)
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(theme.accent)
                        .frame(width: width * clamp(median))
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(Color(hex: "#2D5493").opacity(0.8))
                        .frame(width: max(2, width * (clamp(high) - clamp(low))), height: 4)
                        .offset(x: width * clamp(low))
                    Rectangle()
                        .fill(WTColor.textTertiary)
                        .frame(width: 2)
                        .padding(.vertical, -3)
                        .offset(x: width * clamp(ideal) - 1)
                }
            }
            .frame(height: 16)

            Text(percentLabel)
                .font(WTFont.text(12, .bold))
                .foregroundStyle(theme.textMuted)
                .frame(width: 44, alignment: .trailing)
        }
    }
}

/// Легенда під графіком: набір «маркер + підпис».
public struct WTLegend: View {
    public enum Marker {
        case square(Color)
        case bar(Color)
        case tick(Color)
        case dashed(Color)
    }

    @Environment(\.wtTheme) private var theme
    private let items: [(Marker, String)]

    public init(items: [(Marker, String)]) {
        self.items = items
    }

    public var body: some View {
        HStack(spacing: 18) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(spacing: 6) {
                    marker(item.0)
                    Text(item.1)
                        .font(WTFont.text(11, .bold))
                        .foregroundStyle(theme.textMuted)
                }
            }
        }
    }

    @ViewBuilder
    private func marker(_ marker: Marker) -> some View {
        switch marker {
        case .square(let color):
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 10, height: 10)
        case .bar(let color):
            RoundedRectangle(cornerRadius: 2).fill(color.opacity(0.8)).frame(width: 10, height: 6)
        case .tick(let color):
            Rectangle().fill(color).frame(width: 2, height: 11)
        case .dashed(let color):
            Line().stroke(color, style: StrokeStyle(lineWidth: 2, dash: [3, 3])).frame(width: 16, height: 2)
        }
    }
}
