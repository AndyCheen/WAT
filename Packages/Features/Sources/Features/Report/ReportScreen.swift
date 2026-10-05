import SwiftUI
import Core
import DesignSystem

/// Екран «Звіт» — історія з інфографіки (SPEC-NOTIFICATIONS §11.3; макет Design/Notifications.html,
/// кадри 4–6; рішення від 05.10.2026: замість таблиці статистики, яка вже є на 4a).
///
/// Гортання — тапом без автоперемикання: людина читає у своєму темпі. На останньому слайді —
/// «Готово», попередній період і, для злитого звіту, «Далі: травень ›».
public struct ReportScreen: View {
    @Environment(\.wtTheme) private var theme
    @State private var model: ReportViewModel
    private let onClose: () -> Void

    public init(services: AppServices, periods: [ReportPeriod], onClose: @escaping () -> Void) {
        _model = State(initialValue: ReportViewModel(services: services, periods: periods))
        self.onClose = onClose
    }

    public var body: some View {
        WTStoryPlayer(
            count: model.slides.count,
            index: $model.slideIndex,
            header: model.header,
            style: { model.slides.indices.contains($0) ? model.slides[$0].style : .plain },
            onClose: onClose
        ) { index in
            if model.slides.indices.contains(index) {
                slide(model.slides[index], isLast: index == model.slides.count - 1)
            }
        }
    }

    // MARK: - Слайди

    @ViewBuilder
    private func slide(_ slide: ReportSlide, isLast: Bool) -> some View {
        switch slide {
        case let .cover(kicker, value, decimals, unit, caption, visual, pill, foot, waveLevel):
            ZStack(alignment: .topLeading) {
                WTStoryWaves(level: waveLevel)
                    .padding(.horizontal, -28)
                    .padding(.bottom, -WTSpacing.screenBottom)
                VStack(alignment: .leading, spacing: 0) {
                    kickerText(kicker, onWater: true)
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        WTCountUpText(value, decimals: decimals).font(WTFont.number(104, .semibold))
                            .accessibilityIdentifier("report.headline")
                        Text(unit).font(WTFont.number(40, .semibold))
                    }
                    .padding(.top, 10)
                    .wtStoryAppear(delay: 0.1)
                    paragraph(caption, onWater: true).wtStoryAppear(delay: 0.3)
                    coverVisual(visual).padding(.top, 24)
                    Spacer(minLength: 12)
                    if let pill { WTStoryPill(pill, tone: .onWater).wtStoryAppear(delay: 1.4) }
                    if let foot { paragraph(foot, onWater: true).wtStoryAppear(delay: 1.9) }
                }
            }
            .foregroundStyle(.white)

        case let .timeline(kicker, title, blocks, drops, ticks, rows, foot):
            VStack(alignment: .leading, spacing: 0) {
                kickerText(kicker)
                headline(title).padding(.top, 8)
                WTDayTimeline(blocks: blocks, drops: drops, ticks: ticks).padding(.top, 26)
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(rows.indices, id: \.self) { index in goalRow(rows[index]) }
                }
                .padding(.top, 8)
                .wtStoryAppear(delay: 1.8)
                Spacer(minLength: 12)
                if let foot { paragraph(foot, muted: true).wtStoryAppear(delay: 2) }
                if isLast { actions() }
            }

        case let .weekGoals(kicker, goalDays, dayCount, days, pill, foot):
            VStack(alignment: .leading, spacing: 0) {
                kickerText(kicker)
                (Text("\(goalDays)").font(WTFont.number(44, .semibold)) + Text(" з \(dayCount) днів — норму закрито"))
                    .font(WTFont.display(30, .heavy))
                    .foregroundStyle(theme.textPrimary)
                    .padding(.top, 8)
                    .wtStoryAppear(delay: 0.1)
                    .accessibilityIdentifier("report.headline")
                WTWeekDrops(items: days).padding(.top, 26)
                if let pill { WTStoryPill(pill.text, tone: pill.positive ? .positive : .negative).padding(.top, 30).wtStoryAppear(delay: 1.5) }
                Spacer(minLength: 12)
                if let foot { paragraph(foot, muted: true).wtStoryAppear(delay: 1.7) }
                if isLast { actions() }
            }

        case let .bestDay(kicker, title, subtitle, bars, goalFraction, goalLabel, pill):
            VStack(alignment: .leading, spacing: 0) {
                kickerText(kicker)
                headline(title).padding(.top, 8)
                paragraph(subtitle, muted: true).wtStoryAppear(delay: 0.2)
                WTStoryBars(bars: bars, goalFraction: goalFraction, goalLabel: goalLabel)
                    .frame(height: 250)
                    .padding(.top, 26)
                Spacer(minLength: 12)
                if let pill { WTStoryPill(pill.text, tone: pill.positive ? .positive : .negative).wtStoryAppear(delay: 1.5) }
                if isLast { actions() }
            }

        case let .rhythm(kicker, title, segments, markIndex, start, end, legend, foot):
            VStack(alignment: .leading, spacing: 0) {
                kickerText(kicker)
                headline(title).padding(.top, 8)
                WTDayArc(segments: segments, markIndex: markIndex, startLabel: start, endLabel: end).padding(.top, 22)
                HStack(alignment: .top, spacing: 10) {
                    ForEach(legend.indices, id: \.self) { index in legendCard(legend[index]) }
                }
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 14)
                .wtStoryAppear(delay: 1.6)
                Spacer(minLength: 12)
                if let foot { paragraph(foot, muted: true).wtStoryAppear(delay: 1.8) }
                if isLast { actions() }
            }

        case let .mosaic(kicker, title, leadingBlanks, cells, pill):
            VStack(alignment: .leading, spacing: 0) {
                kickerText(kicker)
                headline(title).padding(.top, 8)
                WTMonthMosaic(weekdayLabels: CalendarService.weekdayLabels, leadingBlanks: leadingBlanks, cells: cells)
                    .padding(.top, 22)
                if let pill { WTStoryPill(pill.text, tone: pill.positive ? .positive : .negative).padding(.top, 22).wtStoryAppear(delay: 1.8) }
                Spacer(minLength: 12)
                if isLast { actions() }
            }

        case let .streak(kicker, value, caption, chain, badges, foot):
            VStack(spacing: 0) {
                kickerText(kicker, onWater: true).frame(maxWidth: .infinity, alignment: .leading)
                Text("🔥").font(.system(size: 84)).padding(.top, 12).wtStoryAppear(pop: true)
                WTCountUpText(Double(value), delay: 0.3).font(WTFont.number(88, .semibold))
                    .wtStoryAppear(delay: 0.3)
                    .accessibilityIdentifier("report.headline")
                paragraph(caption, onWater: true).multilineTextAlignment(.center).wtStoryAppear(delay: 0.4)
                WTStoryChain(labels: chain).padding(.top, 24)
                if !badges.isEmpty { WTStoryBadges(badges).padding(.top, 20) }
                Spacer(minLength: 12)
                if let foot { paragraph(foot, onWater: true).multilineTextAlignment(.center).wtStoryAppear(delay: 1.6) }
            }
            .foregroundStyle(.white)

        case let .game(xp, level, fraction, badges, foot):
            VStack(spacing: 0) {
                kickerText("Гра", onWater: true).frame(maxWidth: .infinity, alignment: .leading)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("+")
                    WTCountUpText(Double(xp)).accessibilityIdentifier("report.headline")
                    Text("XP").font(WTFont.number(30, .semibold))
                }
                .font(WTFont.number(76, .semibold))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 10)
                .wtStoryAppear(delay: 0.1)
                WTStoryLevelRing(value: level, fraction: fraction).padding(.top, 22)
                WTStoryBadges(badges).padding(.top, 20)
                Spacer(minLength: 12)
                if let foot { paragraph(foot, onWater: true).multilineTextAlignment(.center).wtStoryAppear(delay: 2) }
            }
            .foregroundStyle(.white)

        case let .thought(kicker, emoji, title, detail, versus):
            VStack(alignment: .leading, spacing: 0) {
                kickerText(kicker)
                Text(emoji).font(.system(size: 58)).padding(.top, 18).wtStoryAppear(pop: true)
                headline(title).padding(.top, 12)
                if !versus.isEmpty { WTVersusBars(items: versus).frame(height: 220).padding(.top, 20) }
                if let detail { paragraph(detail, muted: true).padding(.top, 12).wtStoryAppear(delay: 0.4) }
                Spacer(minLength: 12)
                if isLast { actions() }
            }

        case let .empty(title):
            VStack(alignment: .leading, spacing: 0) {
                Text("💧").font(.system(size: 58)).padding(.top, 18)
                headline(title).padding(.top, 12)
                Spacer(minLength: 12)
                actions()
            }
        }
    }

    // MARK: - Будівельні блоки

    @ViewBuilder
    private func coverVisual(_ visual: ReportSlide.CoverVisual) -> some View {
        switch visual {
        case .glass(let fraction):
            WTStoryGlass(fraction: fraction).frame(height: 198).frame(maxWidth: .infinity)
        case .drops(let count):
            WTDropGrid(count: count)
        case .buckets(let fractions):
            WTBuckets(fractions: fractions).frame(maxWidth: .infinity)
        }
    }

    private func kickerText(_ text: String, onWater: Bool = false) -> some View {
        Text(text.uppercased())
            .font(WTFont.text(13, .black))
            .tracking(0.6)
            .foregroundStyle(onWater ? Color.white.opacity(0.8) : theme.textMuted)
            .wtStoryAppear()
    }

    private func headline(_ text: String) -> some View {
        Text(text)
            .font(WTFont.display(30, .heavy))
            .foregroundStyle(theme.textPrimary)
            .fixedSize(horizontal: false, vertical: true)
            .wtStoryAppear(delay: 0.1)
            .accessibilityIdentifier("report.headline")
    }

    private func paragraph(_ text: String, onWater: Bool = false, muted: Bool = false) -> some View {
        Text(text)
            .font(WTFont.text(17, .bold))
            .foregroundStyle(onWater ? Color.white.opacity(0.92) : muted ? theme.textMuted : theme.textPrimary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func goalRow(_ row: ReportSlide.GoalRow) -> some View {
        HStack(spacing: 12) {
            Group {
                if row.reached {
                    WTIcons.check(color: .white, size: 11).frame(width: 26, height: 26).background(WTColor.success, in: Circle())
                } else {
                    Circle().stroke(theme.dotOff, lineWidth: 2).frame(width: 26, height: 26)
                }
            }
            Text(row.title).font(WTFont.text(16, .bold)).foregroundStyle(theme.textPrimary)
            Spacer()
            Text(row.value).font(WTFont.text(14, .black)).foregroundStyle(theme.textMuted)
        }
        .accessibilityElement(children: .combine)
    }

    private func legendCard(_ item: ReportSlide.Legend) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(item.caption).font(WTFont.text(11, .black)).tracking(0.3).foregroundStyle(theme.textMuted)
            Text(item.title).font(WTFont.text(18, .heavy)).foregroundStyle(theme.textPrimary)
            Text(item.value).font(WTFont.text(14, .black)).foregroundStyle(item.positive ? WTColor.successText : WTColor.orange)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .background(theme.chip, in: RoundedRectangle(cornerRadius: WTRadius.panel, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    /// Кнопки останнього слайда. Тап по них не гортає історію — кнопки забирають його самі.
    /// Останній слайд — завжди «думка» на світлому тлі, тож кнопки одного вигляду.
    private func actions() -> some View {
        VStack(spacing: 10) {
            if let next = model.nextTitle {
                WTPrimaryButton(next) { model.showNext() }
                    .accessibilityIdentifier("report.next")
            } else {
                WTPrimaryButton("Готово", action: onClose)
                    .accessibilityIdentifier("report.done")
            }
            Button(action: model.showPrevious) {
                Text(model.previousTitle)
                    .font(WTFont.text(16, .heavy))
                    .foregroundStyle(theme.textButton)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(theme.chip, in: RoundedRectangle(cornerRadius: WTRadius.control, style: .continuous))
            }
            .buttonStyle(WTPressStyle())
            .accessibilityIdentifier("report.previous")
        }
        .padding(.top, 16)
        .wtStoryAppear(delay: 0.6)
    }
}
