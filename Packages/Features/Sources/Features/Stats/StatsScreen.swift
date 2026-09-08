import SwiftUI
import Core
import Persistence
import DesignSystem
import Insights

/// Макет 4a — «Норма води»: рівномірність, обʼєм по днях, календар, деталі дня,
/// типова доба, теплокарта часу, калькулятор норми.
public struct StatsScreen: View {
    @Environment(\.wtTheme) private var theme
    @State private var model: StatsViewModel
    private let onBack: () -> Void

    public init(services: AppServices, onBack: @escaping () -> Void) {
        _model = State(initialValue: StatsViewModel(services: services))
        self.onBack = onBack
    }

    public var body: some View {
        ZStack {
            theme.screen.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: WTSpacing.cardGap) {
                    header
                    evennessCard
                    volumeCard
                    calendarCard
                    if let detail = model.dayDetail { dayDetailCard(detail) }
                    periodSwitch
                    typicalDayCard
                    heatmapCard
                }
                .padding(.top, WTSpacing.screenTop)
                .padding(.horizontal, WTSpacing.screenSide)
                .padding(.bottom, WTSpacing.screenBottom)
            }
            // Див. WAT-9/WAT-31: без ignoresSafeArea тут screenTop додається
            // поверх системної safe area — сумарний відступ виходить майже
            // вдвічі більшим за задум макета.
            .ignoresSafeArea(.container, edges: .top)

            if model.showTypicalInfo { typicalInfoModal.zIndex(11) }
        }
    }

    private var header: some View {
        HStack {
            WTCircleButton(size: 38, action: onBack) {
                WTIcons.chevronLeft(color: theme.accent)
            }
            .accessibilityIdentifier("stats.back")
            Spacer()
            Text("Норма води")
                .font(WTFont.display(20, .semibold))
                .foregroundStyle(theme.textPrimary)
            Spacer()
            // Симетричний відступ: у макеті 4a праворуч порожньо.
            // Розрахунок норми поки не показуємо — норма змінюється в налаштуваннях.
            Color.clear.frame(width: 38, height: 38)
        }
        .padding(.bottom, 2)
    }

    // MARK: - Рівномірність

    private var evennessCard: some View {
        WTCard {
            let report = model.evenness
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Рівномірність за день")
                        .font(WTFont.display(16, .semibold))
                        .foregroundStyle(theme.textPrimary)
                    Spacer()
                    Text("\(report.score) / 100")
                        .font(WTFont.text(13, .heavy))
                        .foregroundStyle(WTColor.warnText)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(WTColor.warnBg, in: Capsule())
                }
                .padding(.bottom, 18)

                VStack(spacing: 16) {
                    ForEach(report.rows) { row in
                        WTEvennessRowView(
                            label: row.label,
                            valueLabel: "\(row.ml) мл",
                            fraction: row.fraction,
                            tickFraction: row.tickFraction
                        )
                    }
                }
                .padding(.bottom, 16)

                WTLegend(items: [
                    (.square(theme.accent), "випито"),
                    (.tick(WTColor.textTertiary), "ціль")
                ])
                .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: - Обʼєм по днях

    private var volumeCard: some View {
        WTCard {
            let report = model.volumeChart
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Обʼєм по днях")
                        .font(WTFont.display(16, .semibold))
                        .foregroundStyle(theme.textPrimary)
                    Spacer()
                    WTSegmentedTabs(
                        titles: VolumeChartMode.allCases.map(\.title),
                        selection: model.chartMode.rawValue,
                        onSelect: { model.chartMode = VolumeChartMode(rawValue: $0) ?? .days7 }
                    )
                    .frame(width: 150)
                }
                .padding(.bottom, 16)

                WTBarChart(
                    bars: report.bars.map {
                        WTBar(id: $0.key, label: $0.label, value: Double($0.ml))
                    },
                    maxValue: Double(report.maxValue),
                    goalValue: Double(report.goalMl)
                )
                .padding(.bottom, 14)

                WTLegend(items: [(.dashed(theme.textMuted), "Ціль \(model.goalLabel)")])
            }
        }
    }

    // MARK: - Календар

    private var calendarCard: some View {
        WTCard {
            let report = model.calendarReport
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Календар пиття")
                        .font(WTFont.display(16, .semibold))
                        .foregroundStyle(theme.textPrimary)
                    Spacer()
                    HStack(spacing: 8) {
                        monthArrow(systemName: "chevron.left", enabled: report.canGoBack) {
                            model.shiftMonth(-1)
                        }
                        Text(report.title)
                            .font(WTFont.text(13, .bold))
                            .foregroundStyle(theme.textMuted)
                            .frame(minWidth: 104)
                        monthArrow(systemName: "chevron.right", enabled: report.canGoForward) {
                            model.shiftMonth(1)
                        }
                    }
                }
                .padding(.bottom, 16)

                if report.hasData {
                    WTCalendarHeatmap(
                        cells: report.days.map { CalendarCellMapper.cell($0, selected: model.selectedDay) },
                        onSelect: { cell in
                            guard let number = cell.number else { return }
                            model.select(day: DayKey(rawValue: String(format: "%@-%02d", report.month.rawValue, number)))
                        }
                    )
                    .padding(.bottom, 16)

                    WTCalendarLegend()
                        .padding(.bottom, 12)

                    HStack(spacing: 8) {
                        ZStack(alignment: .bottomTrailing) {
                            Circle().fill(Color(hex: "#5aa9f0").opacity(0.85)).frame(width: 16, height: 16)
                            ZStack {
                                Circle().fill(WTColor.success)
                                WTIcons.check(color: .white, size: 6)
                            }
                            .frame(width: 10, height: 10)
                            .overlay(Circle().stroke(theme.card, lineWidth: 1.5))
                            .offset(x: 3, y: 3)
                        }
                        Text("= ціль виконана (100%+ норми)")
                            .font(WTFont.text(11, .bold))
                            .foregroundStyle(theme.textMuted)
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    VStack(spacing: 8) {
                        Text("🗓️").font(.system(size: 26))
                        Text("Тут ще немає даних за цей місяць")
                            .font(WTFont.text(13, .bold))
                            .foregroundStyle(WTColor.textQuaternary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 34)
                }
            }
        }
    }

    private func monthArrow(systemName: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(enabled ? theme.accent : WTColor.neutralDisabled)
                .frame(width: 26, height: 26)
                .background(enabled ? theme.chip : Color.clear, in: Circle())
        }
        .buttonStyle(WTPressStyle())
        .disabled(!enabled)
    }

    // MARK: - Деталі дня

    private func dayDetailCard(_ detail: DayDetailReport) -> some View {
        WTCard {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Рівномірність за день")
                        .font(WTFont.display(16, .semibold))
                        .foregroundStyle(theme.textPrimary)
                    Spacer()
                    WTCircleButton(size: 26, action: { model.select(day: nil) }) {
                        WTIcons.close(color: theme.accent)
                    }
                }
                .padding(.bottom, 4)

                Text("\(detail.title) · \(detail.litersLabel) л · \(detail.completionPct)% від норми")
                    .font(WTFont.text(12, .bold))
                    .foregroundStyle(theme.textMuted)
                    .padding(.bottom, 16)

                WTBarChart(
                    bars: detail.rhythm.map {
                        WTBar(id: "\($0.id)", label: $0.label, value: Double($0.ml), topLabel: "\($0.ml)")
                    },
                    maxValue: Double(max(detail.rhythm.map(\.ml).max() ?? 1, 1)),
                    height: 110,
                    barMaxWidth: 30
                )

                Text("Історія внесень")
                    .font(WTFont.display(16, .semibold))
                    .foregroundStyle(theme.textPrimary)
                    .padding(.top, 22)
                    .padding(.bottom, 14)

                if detail.hasEntries {
                    ForEach(Array(detail.entries.enumerated()), id: \.element.id) { index, entry in
                        WTHistoryStaticRow(
                            amountLabel: "\(entry.amountMl) мл",
                            timeLabel: entry.timeLabel,
                            isLast: index == detail.entries.count - 1
                        )
                    }
                } else {
                    Text("Немає внесень за цей день")
                        .font(WTFont.text(13, .bold))
                        .foregroundStyle(WTColor.textQuaternary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
            }
        }
    }

    // MARK: - Період

    private var periodSwitch: some View {
        WTSegmentedTabs(
            titles: StatsPeriod.allCases.map(\.title),
            selection: model.period.rawValue,
            onSelect: { model.period = StatsPeriod(rawValue: $0) ?? .week7 }
        )
    }

    // MARK: - Типова доба

    private var typicalDayCard: some View {
        WTCard {
            let report = model.typicalDay
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    Text("Типова доба — медіана і розкид")
                        .font(WTFont.display(16, .semibold))
                        .foregroundStyle(theme.textPrimary)
                    Button { model.present(\.showTypicalInfo) } label: {
                        Text("i")
                            .font(WTFont.display(12, .bold))
                            .foregroundStyle(theme.accent)
                            .frame(width: 18, height: 18)
                            .background(theme.chip, in: Circle())
                    }
                    .buttonStyle(WTPressStyle())
                }
                .padding(.bottom, 16)

                if report.rows.isEmpty {
                    Text("Замало даних — графік зʼявиться після кількох днів обліку")
                        .font(WTFont.text(13, .bold))
                        .foregroundStyle(theme.textMuted)
                        .padding(.vertical, 12)
                } else {
                    VStack(spacing: 18) {
                        ForEach(report.rows) { row in
                            WTMedianSpreadRow(
                                label: row.label,
                                percentLabel: row.percentLabel,
                                median: row.median,
                                low: row.low,
                                high: row.high,
                                ideal: row.ideal
                            )
                        }
                    }
                    .padding(.bottom, 18)

                    WTLegend(items: [
                        (.square(theme.accent), "медіана"),
                        (.bar(Color(hex: "#2D5493")), "розкид"),
                        (.tick(WTColor.textTertiary), "ціль")
                    ])
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

    // MARK: - Теплокарта

    private var heatmapCard: some View {
        WTCard {
            let report = model.heatmap
            VStack(alignment: .leading, spacing: 0) {
                Text("Коли ти пʼєш")
                    .font(WTFont.display(16, .semibold))
                    .foregroundStyle(theme.textPrimary)
                    .padding(.bottom, 4)
                Text(report.subtitle)
                    .font(WTFont.text(12, .bold))
                    .foregroundStyle(theme.textMuted)
                    .padding(.bottom, 16)

                WTWeekHourHeatmap(
                    hours: report.hours,
                    levels: report.rows.map { $0.map(\.level) }
                )
            }
        }
    }

    private var typicalInfoModal: some View {
        WTModal(maxWidth: 320, onDismiss: { model.dismiss(\.showTypicalInfo) }) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Про графік")
                        .font(WTFont.display(17, .semibold))
                        .foregroundStyle(theme.textPrimary)
                    Spacer()
                    Button { model.dismiss(\.showTypicalInfo) } label: {
                        Text("×")
                            .font(.system(size: 14, weight: .heavy))
                            .foregroundStyle(WTColor.textTertiary)
                            .frame(width: 28, height: 28)
                            .background(WTColor.neutralTrack, in: Circle())
                    }
                    .buttonStyle(WTPressStyle())
                }

                Text("Графік показує, як зазвичай розподіляється вода протягом дня за обраний період.")
                    .font(WTFont.text(13, .medium))
                    .foregroundStyle(WTColor.textTertiary)

                VStack(alignment: .leading, spacing: 10) {
                    infoLine("Медіана", "типова частка на цей період.")
                    infoLine("Розкид", "наскільки по-різному минали дні. Чим ширше — тим менш стабільна звичка.")
                    infoLine("Ціль", "скільки мало припадати на цей період за ідеального розподілу.")
                }
                .padding(14)
                .background(Color(hex: "#f6f9fd"), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
    }

    private func infoLine(_ term: String, _ text: String) -> some View {
        (Text(term).font(WTFont.text(13, .bold)).foregroundColor(theme.textPrimary)
            + Text(" — \(text)").font(WTFont.text(13, .medium)).foregroundColor(WTColor.textSecondary))
            .fixedSize(horizontal: false, vertical: true)
    }
}
