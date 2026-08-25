import SwiftUI

/// Комірка календаря у вигляді, потрібному для рендера.
public struct WTCalendarCell: Identifiable, Equatable, Sendable {
    public let id: String
    public let number: Int?
    public let intensity: Double
    public let goalMet: Bool
    public let isToday: Bool
    public let isFuture: Bool
    public let isSelected: Bool

    public init(
        id: String, number: Int?, intensity: Double, goalMet: Bool,
        isToday: Bool, isFuture: Bool, isSelected: Bool
    ) {
        self.id = id
        self.number = number
        self.intensity = intensity
        self.goalMet = goalMet
        self.isToday = isToday
        self.isFuture = isFuture
        self.isSelected = isSelected
    }
}

/// Календар-теплокарта місяця (макет 4a): колір = % норми, галочка = ціль виконана.
public struct WTCalendarHeatmap: View {
    @Environment(\.wtTheme) private var theme
    private let cells: [WTCalendarCell]
    private let onSelect: (WTCalendarCell) -> Void

    public init(cells: [WTCalendarCell], onSelect: @escaping (WTCalendarCell) -> Void) {
        self.cells = cells
        self.onSelect = onSelect
    }

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)

    public var body: some View {
        VStack(spacing: 8) {
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(WTCalendarHeatmap.weekdays, id: \.self) { day in
                    Text(day)
                        .font(WTFont.text(11, .heavy))
                        .foregroundStyle(WTColor.textQuaternary)
                }
            }

            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(cells) { cell in
                    Color.clear
                        .aspectRatio(1, contentMode: .fit)
                        .overlay {
                            if let number = cell.number {
                                dayView(cell, number: number)
                            }
                        }
                }
            }
        }
    }

    @ViewBuilder
    private func dayView(_ cell: WTCalendarCell, number: Int) -> some View {
        Button {
            guard !cell.isFuture else { return }
            onSelect(cell)
        } label: {
            GeometryReader { proxy in
                let size = min(proxy.size.width, proxy.size.height) * 0.78
                ZStack(alignment: .bottomTrailing) {
                    ZStack {
                        Circle().fill(fill(cell))
                        if cell.isToday {
                            Circle().stroke(theme.textPrimary, lineWidth: 2)
                        }
                        if cell.isSelected {
                            Circle().stroke(theme.textPrimary.opacity(0.45), lineWidth: 3).padding(-3)
                        }
                        Text("\(number)")
                            .font(WTFont.text(10, .bold))
                            .foregroundStyle(textColor(cell))
                    }
                    .frame(width: size, height: size)

                    if cell.goalMet {
                        ZStack {
                            Circle().fill(WTColor.success)
                            WTIcons.check(color: .white, size: 6)
                        }
                        .frame(width: 12, height: 12)
                        .overlay(Circle().stroke(theme.card, lineWidth: 1.5))
                        .offset(x: 2, y: 2)
                    }
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
            }
        }
        .buttonStyle(.plain)
        .disabled(cell.isFuture)
    }

    private func fill(_ cell: WTCalendarCell) -> Color {
        if cell.isFuture { return WTColor.neutralFuture }
        return WTColor.calendarFill(pct: Int(cell.intensity * 100))
    }

    private func textColor(_ cell: WTCalendarCell) -> Color {
        if cell.isFuture { return WTColor.futureText }
        return cell.intensity > 0.45 ? .white : WTColor.textTertiary
    }

    public static let weekdays = ["Пн", "Вт", "Ср", "Чт", "Пт", "Сб", "Нд"]
}

/// Легенда «% від денної норми» — градієнтна смуга під календарем.
public struct WTCalendarLegend: View {
    @Environment(\.wtTheme) private var theme

    public init() {}

    public var body: some View {
        VStack(spacing: 6) {
            Text("% ВІД ДЕННОЇ НОРМИ")
                .font(WTFont.text(10, .heavy))
                .tracking(0.3)
                .foregroundStyle(WTColor.textQuaternary)

            Capsule()
                .fill(
                    LinearGradient(
                        colors: [WTColor.neutralEmpty, Color(hex: "#5aa9f0")],
                        startPoint: .leading, endPoint: .trailing
                    )
                )
                .frame(height: 8)

            HStack {
                Text("0")
                Spacer()
                Text("50%")
                Spacer()
                Text("100%")
            }
            .font(WTFont.text(11, .bold))
            .foregroundStyle(theme.textMuted)
        }
    }
}

/// Теплокарта «Коли ти пʼєш»: 7 рядків × 9 годинних бакетів.
public struct WTWeekHourHeatmap: View {
    @Environment(\.wtTheme) private var theme
    private let hours: [Int]
    private let levels: [[Int]]

    public init(hours: [Int], levels: [[Int]]) {
        self.hours = hours
        self.levels = levels
    }

    public var body: some View {
        VStack(spacing: 5) {
            ForEach(Array(levels.enumerated()), id: \.offset) { rowIndex, row in
                HStack(spacing: 6) {
                    Text(WTCalendarHeatmap.weekdays[rowIndex])
                        .font(WTFont.text(11, .heavy))
                        .foregroundStyle(theme.textMuted)
                        .frame(width: 22, alignment: .leading)

                    HStack(spacing: 4) {
                        ForEach(Array(row.enumerated()), id: \.offset) { _, level in
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(WTColor.heatmapFill(level: level))
                                .aspectRatio(1.3, contentMode: .fit)
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
            }

            HStack(spacing: 6) {
                Color.clear.frame(width: 22)
                HStack(spacing: 4) {
                    ForEach(hours, id: \.self) { hour in
                        Text("\(hour)")
                            .font(WTFont.text(10, .bold))
                            .foregroundStyle(WTColor.textQuaternary)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .padding(.top, 2)

            HStack(spacing: 6) {
                Spacer()
                Text("менше")
                    .font(WTFont.text(11, .bold))
                    .foregroundStyle(theme.textMuted)
                ForEach(0..<4, id: \.self) { level in
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(WTColor.heatmapFill(level: level == 0 ? 0 : level + 1))
                        .frame(width: 12, height: 12)
                }
                Text("більше")
                    .font(WTFont.text(11, .bold))
                    .foregroundStyle(theme.textMuted)
            }
            .padding(.top, 12)
        }
    }
}
