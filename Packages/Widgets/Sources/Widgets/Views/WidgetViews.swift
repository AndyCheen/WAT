import SwiftUI
import WidgetKit
import Core
import DesignSystem

/// Що малює один запис таймлайну: знімок і стан доби на цю хвилину.
public struct WidgetContent: Equatable, Sendable {
    public let snapshot: WidgetSnapshot
    public let day: WidgetDay

    public init(snapshot: WidgetSnapshot, day: WidgetDay) {
        self.snapshot = snapshot
        self.day = day
    }

    public init(snapshot: WidgetSnapshot, at date: Date, calendar: CalendarService) {
        self.init(snapshot: snapshot, day: WidgetDay.resolve(snapshot, at: date, calendar: calendar))
    }
}

// MARK: - 1. Сьогодні (S)

public struct TodayWidgetView: View {
    @Environment(\.wtTheme) private var theme
    let content: WidgetContent

    public init(_ content: WidgetContent) { self.content = content }

    public var body: some View {
        let day = content.day
        VStack(spacing: 0) {
            HStack {
                WidgetCaption(text: "Сьогодні")
                Spacer(minLength: 4)
                if let streak = day.streak { StreakBadge(count: streak) }
            }
            Spacer(minLength: 4)
            ZStack {
                WidgetRing(fraction: day.fraction, lineWidth: 11)
                Text("\(day.percent)%")
                    .font(WTFont.number(24))
                    .foregroundStyle(theme.textPrimary)
                    .contentTransition(.numericText())
            }
            .frame(width: 86, height: 86)
            Spacer(minLength: 4)
            Text(WidgetPresenter.ringVolume(countedMl: day.countedMl, goalMl: day.goalMl))
                .font(WTFont.text(14, .heavy))
                .foregroundStyle(theme.textPrimary)
            Text(WidgetPresenter.todayFootnote(day))
                .font(WTFont.text(12, .bold))
                .foregroundStyle(day.goalMet ? WTColor.successText : theme.textMuted)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .wtWidgetContainer { theme.card }
    }
}

// MARK: - 2. Частина доби (S)

public struct DayPartWidgetView: View {
    @Environment(\.wtTheme) private var theme
    let content: WidgetContent

    public init(_ content: WidgetContent) { self.content = content }

    public var body: some View {
        let part = WidgetPresenter.part(content.day, xp: content.snapshot.dayPartXp)
        let done = part.kind == .closed || part.kind == .goalMet
        VStack(alignment: .leading, spacing: 6) {
            WidgetCaption(text: part.caption)
            Spacer(minLength: 0)
            if done {
                ZStack {
                    Circle().fill(WTColor.success)
                    WTIcons.check(color: .white, size: 15)
                }
                .frame(width: 30, height: 30)
                .widgetAccentable()
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(part.value).font(WTFont.number(32)).foregroundStyle(theme.textPrimary)
                    if let unit = part.unit {
                        Text(unit).font(WTFont.text(15, .bold)).foregroundStyle(theme.textMuted)
                    }
                }
            }
            Text(part.headline)
                .font(WTFont.text(15, .heavy))
                .foregroundStyle(done ? WTColor.successText : theme.textPrimary)
            Spacer(minLength: 0)
            WidgetBar(fraction: part.fraction, isDone: done)
            HStack(spacing: 4) {
                Text(part.footnote).foregroundStyle(theme.textMuted)
                if let xp = part.xp {
                    Text("·").foregroundStyle(theme.textMuted)
                    Text(xp).foregroundStyle(theme.textButton)
                }
            }
            .font(WTFont.text(12, .heavy))
        }
        .lineLimit(1)
        .minimumScaleFactor(0.75)
        .frame(maxWidth: .infinity, alignment: .leading)
        .wtWidgetContainer { theme.card }
    }
}

// MARK: - 3. Ритм дня (M)

public struct RhythmWidgetView: View {
    @Environment(\.wtTheme) private var theme
    let content: WidgetContent

    public init(_ content: WidgetContent) { self.content = content }

    public var body: some View {
        let day = content.day
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                WidgetCaption(text: "Ритм дня")
                Spacer(minLength: 0)
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(WidgetPresenter.liters(day.countedMl)).font(WTFont.number(32))
                    Text("л").font(WTFont.text(16, .bold))
                }
                .foregroundStyle(theme.textPrimary)
                Text("з \(WidgetPresenter.liters(day.goalMl)) л · \(day.percent)%")
                    .font(WTFont.text(12, .bold))
                    .foregroundStyle(theme.textMuted)
                Spacer(minLength: 0)
                if let pace = WidgetPresenter.pace(day) {
                    Text(pace)
                        .font(WTFont.text(12, .heavy))
                        .foregroundStyle(day.goalMet || (day.paceDeltaMl ?? 0) >= 50 ? WTColor.successText : theme.textPrimary)
                }
            }
            .frame(width: 112, alignment: .leading)
            HStack(spacing: WidgetMetrics.gap) {
                ForEach(Array(day.blocks.enumerated()), id: \.offset) { _, block in
                    BlockColumn(block: block, rhythm: day.dayRhythmEnabled)
                }
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.75)
        .wtWidgetContainer { theme.card }
    }
}

private struct BlockColumn: View {
    @Environment(\.wtTheme) private var theme
    let block: WidgetDay.Block
    let rhythm: Bool

    var body: some View {
        let current = block.position == .current
        let done = rhythm && block.isReached
        VStack(spacing: 5) {
            Text((done ? "✓ " : "") + WidgetPresenter.blockValue(block, rhythm: rhythm))
                .font(WTFont.text(11, .black))
                .foregroundStyle(current ? theme.textPrimary : theme.textMuted)
            GeometryReader { proxy in
                let height = proxy.size.height
                ZStack(alignment: .bottom) {
                    RoundedRectangle(cornerRadius: WTRadius.chip, style: .continuous).fill(theme.track)
                    RoundedRectangle(cornerRadius: WTRadius.chip - 2, style: .continuous)
                        .fill(done ? AnyShapeStyle(WTColor.success)
                                   : AnyShapeStyle(LinearGradient(colors: [theme.ringStart, theme.ringEnd],
                                                                  startPoint: .top, endPoint: .bottom)))
                        .frame(height: height * block.fraction)
                        .widgetAccentable()
                    if current && rhythm {
                        // Ризка «за темпом зараз»: вище заливки — відстаєш, нижче — випереджаєш.
                        Rectangle()
                            .fill(theme.textPrimary.opacity(0.7))
                            .frame(height: 2)
                            .padding(.horizontal, -2)
                            .offset(y: -height * block.paceFraction)
                            .frame(maxHeight: .infinity, alignment: .bottom)
                    }
                }
            }
            .frame(maxWidth: 58)
            .overlay {
                if current {
                    RoundedRectangle(cornerRadius: WTRadius.chip, style: .continuous).stroke(theme.accent, lineWidth: 2)
                }
            }
            Text(WidgetPresenter.blockHours(block))
                .font(WTFont.text(11, .heavy))
                .foregroundStyle(theme.textMuted)
        }
        .opacity(block.position == .future ? 0.55 : 1)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - 4. Запас води (S, M)

/// Вигляд «Запасу води» — параметр «Вигляд» у «Змінити віджет» (рішення від 08.10.2026).
public enum ReserveStyle: String, CaseIterable, Sendable {
    /// Вода піднімається по всьому віджету — типово.
    case water
    /// Колба з позначкою «½» на тлі глибокої води.
    case flask
}

public struct ReserveWidgetView: View {
    @Environment(\.wtTheme) private var theme
    let content: WidgetContent
    let style: ReserveStyle
    let isMedium: Bool

    public init(_ content: WidgetContent, style: ReserveStyle, isMedium: Bool) {
        self.content = content
        self.style = style
        self.isMedium = isMedium
    }

    public var body: some View {
        let day = content.day
        let text = WidgetPresenter.reserve(day)
        let fraction = day.phase == .active ? day.reserveFraction : 0
        HStack(spacing: 12) {
            switch style {
            case .water:
                waterText(text, fraction: fraction)
            case .flask:
                flaskText(text, fraction: fraction)
            }
            if isMedium {
                buttons
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.75)
        .wtWidgetContainer { background(fraction) }
    }

    @ViewBuilder
    private func background(_ fraction: Double) -> some View {
        switch style {
        case .water:
            ZStack {
                theme.card
                WidgetWaterShape(fraction: fraction)
                    .fill(LinearGradient(colors: waterColors, startPoint: .top, endPoint: .bottom))
                    .widgetAccentable()
            }
        case .flask:
            LinearGradient(colors: [theme.ringEnd, theme.waterDeep], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }

    /// Світла тема — світла вода й темний текст; темна — глибока вода й світлий: текст читається і над
    /// водою, і під нею без перемикання кольору.
    private var waterColors: [Color] {
        theme.isDark ? [theme.ringEnd, theme.waterDeep] : [theme.ringStart, theme.ringEnd]
    }

    private func waterText(_ text: WidgetPresenter.Reserve, fraction: Double) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            WidgetCaption(text: "Запас води")
            Spacer(minLength: 0)
            Text("\(Int((fraction * 100).rounded()))%")
                .font(WTFont.number(isMedium ? 34 : 30))
                .contentTransition(.numericText())
            Text(text.headline).font(WTFont.text(15, .black))
            Text(text.footnote).font(WTFont.text(12, .bold)).opacity(0.75)
        }
        .foregroundStyle(theme.textPrimary)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private func flaskText(_ text: WidgetPresenter.Reserve, fraction: Double) -> some View {
        Group {
            if isMedium {
                HStack(spacing: 12) {
                    Flask(fraction: fraction).frame(width: 42, height: 110)
                    VStack(alignment: .leading, spacing: 3) {
                        WidgetCaption(text: "Запас води", color: .white.opacity(0.72))
                        Text(text.headline).font(WTFont.text(18, .black))
                        Text(text.footnote).font(WTFont.text(12, .bold)).opacity(0.72)
                    }
                    Spacer(minLength: 0)
                }
            } else {
                VStack(spacing: 6) {
                    HStack(spacing: 10) {
                        Flask(fraction: fraction).frame(width: 40, height: 96)
                        VStack(alignment: .leading, spacing: 0) {
                            Text("\(Int((fraction * 100).rounded()))%").font(WTFont.number(26))
                            Text("запас").font(WTFont.text(11, .bold)).opacity(0.72)
                        }
                    }
                    Spacer(minLength: 0)
                    Text(text.headline).font(WTFont.text(15, .black))
                    Text(text.footnote).font(WTFont.text(12, .bold)).opacity(0.72)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .foregroundStyle(Color.white)
    }

    @ViewBuilder
    private var buttons: some View {
        if let undo = content.day.undo {
            UndoPanel(undo: undo, compact: true, onDeep: style == .flask)
                .frame(width: 104)
        } else {
            VStack(spacing: WidgetMetrics.gap) {
                ForEach(Array(content.snapshot.homeButtons.prefix(3).enumerated()), id: \.offset) { _, ml in
                    WidgetActionButton(.add(ml: ml, source: .widget)) {
                        if style == .flask {
                            Text(WidgetPresenter.addTitle(ml))
                                .font(WTFont.text(14, .heavy))
                                .foregroundStyle(Color.white)
                                .frame(maxWidth: .infinity, minHeight: WidgetMetrics.buttonHeight)
                                .background(Color.white.opacity(0.18),
                                            in: RoundedRectangle(cornerRadius: WTRadius.control, style: .continuous))
                        } else {
                            PortionLabel(title: WidgetPresenter.addTitle(ml), fontSize: 14)
                        }
                    }
                }
            }
            .frame(width: 96)
        }
    }
}

/// Колба з позначкою «½» — одна звичайна склянка.
private struct Flask: View {
    @Environment(\.wtTheme) private var theme
    let fraction: Double

    var body: some View {
        ZStack {
            Capsule().fill(Color.white.opacity(0.16))
            WidgetWaterShape(fraction: fraction, amplitude: 2.5)
                .fill(LinearGradient(colors: [.white, theme.ringStart], startPoint: .top, endPoint: .bottom))
                .clipShape(Capsule())
                .widgetAccentable()
            Capsule().stroke(Color.white.opacity(0.55), lineWidth: 2.5)
            HStack(spacing: 2) {
                Capsule().fill(Color.white.opacity(0.75)).frame(width: 9, height: 2.5)
                Text("½").font(WTFont.text(9, .black)).foregroundStyle(Color.white.opacity(0.8))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 6)
        }
        .accessibilityHidden(true)
    }
}

// MARK: - 5. Швидке додавання (M)

public struct QuickAddWidgetView: View {
    @Environment(\.wtTheme) private var theme
    let content: WidgetContent

    public init(_ content: WidgetContent) { self.content = content }

    public var body: some View {
        let day = content.day
        HStack(spacing: 16) {
            Link(destination: WidgetLink.home.url) {
                VStack(spacing: 8) {
                    ZStack {
                        WidgetRing(fraction: day.fraction, lineWidth: 12)
                        Text("\(day.percent)%").font(WTFont.number(24)).foregroundStyle(theme.textPrimary)
                    }
                    .frame(width: 92, height: 92)
                    Text(WidgetPresenter.ringVolume(countedMl: day.countedMl, goalMl: day.goalMl))
                        .font(WTFont.text(12, .heavy))
                        .foregroundStyle(theme.textPrimary)
                }
            }
            .frame(width: 104)
            if let undo = day.undo {
                UndoPanel(undo: undo)
            } else {
                let columns = [GridItem(.flexible(), spacing: WidgetMetrics.gap), GridItem(.flexible(), spacing: WidgetMetrics.gap)]
                LazyVGrid(columns: columns, spacing: WidgetMetrics.gap) {
                    // Дублі кнопок дозволені (WAT-45) — ідентифікатор за позицією, не за значенням.
                    ForEach(Array(content.snapshot.homeButtons.prefix(3).enumerated()), id: \.offset) { _, ml in
                        WidgetActionButton(.add(ml: ml, source: .widget)) {
                            PortionLabel(title: WidgetPresenter.amount(ml), height: 62)
                        }
                    }
                    Link(destination: WidgetLink.custom.url) {
                        PortionLabel(title: "Інше", prominent: true, height: 62)
                    }
                }
            }
        }
        .lineLimit(1)
        .wtWidgetContainer { theme.card }
    }
}

// MARK: - 6. Кнопка (S)

public struct ButtonWidgetView: View {
    @Environment(\.wtTheme) private var theme
    let content: WidgetContent
    let first: Int
    let second: Int?

    public init(_ content: WidgetContent, first: Int, second: Int?) {
        self.content = content
        self.first = first
        self.second = second
    }

    public var body: some View {
        let day = content.day
        VStack(spacing: WidgetMetrics.gap) {
            HStack(spacing: 7) {
                WidgetRing(fraction: day.fraction, lineWidth: 4).frame(width: 22, height: 22)
                Text(WidgetPresenter.ringVolume(countedMl: day.countedMl, goalMl: day.goalMl))
                    .font(WTFont.text(13, .heavy))
                    .foregroundStyle(theme.textPrimary)
                Spacer(minLength: 0)
            }
            if let undo = day.undo {
                UndoPanel(undo: undo, compact: true)
            } else if let second {
                Spacer(minLength: 0)
                WidgetActionButton(.add(ml: first, source: .widget)) {
                    PortionLabel(title: WidgetPresenter.addTitle(first), prominent: true, height: 46, fontSize: 17)
                }
                WidgetActionButton(.add(ml: second, source: .widget)) {
                    PortionLabel(title: WidgetPresenter.addTitle(second), height: 46, fontSize: 17)
                }
            } else {
                Spacer(minLength: 0)
                WidgetActionButton(.add(ml: first, source: .widget)) {
                    ZStack {
                        Circle()
                            .fill(LinearGradient(colors: [theme.ringStart, theme.ringEnd], startPoint: .top, endPoint: .bottom))
                            .widgetAccentable()
                        VStack(spacing: 0) {
                            Text("+" + WidgetPresenter.number(first)).font(WTFont.number(28))
                            Text(WidgetPresenter.unitWord(first)).font(WTFont.text(12, .heavy)).opacity(0.9)
                        }
                        .foregroundStyle(Color.white)
                    }
                    .frame(width: 96, height: 96)
                }
                Spacer(minLength: 0)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.75)
        .wtWidgetContainer { theme.card }
    }
}

// MARK: - 7. Прогрес (M)

public struct ProgressWidgetView: View {
    @Environment(\.wtTheme) private var theme
    let content: WidgetContent

    public init(_ content: WidgetContent) { self.content = content }

    public var body: some View {
        let snapshot = content.snapshot
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    WTLevelDrop(level: snapshot.level.level, color: theme.accent, size: 32).widgetAccentable()
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Рівень \(snapshot.level.level)").font(WTFont.text(15, .black)).foregroundStyle(theme.textPrimary)
                        Text(WidgetPresenter.xpLeft(snapshot.level)).font(WTFont.text(11, .bold)).foregroundStyle(theme.textMuted)
                    }
                }
                WidgetBar(fraction: snapshot.level.fraction)
                Spacer(minLength: 0)
                if let streak = content.day.streak {
                    HStack(spacing: 8) {
                        StreakBadge(count: streak, size: 20)
                        Text(WidgetPresenter.streakWord(streak))
                            .font(WTFont.text(12, .bold))
                            .foregroundStyle(theme.textMuted)
                    }
                }
            }
            .frame(width: 124, alignment: .leading)
            Rectangle().fill(theme.track).frame(width: 1)
            VStack(alignment: .leading, spacing: 3) {
                if content.day.questsAreCurrent {
                    WidgetCaption(text: "Сьогодні")
                    ForEach(Array(snapshot.dailyQuests.prefix(2).enumerated()), id: \.offset) { _, quest in
                        QuestLine(quest: quest)
                    }
                    if let weekly = snapshot.weeklyQuests.first(where: { !$0.isDone }) ?? snapshot.weeklyQuests.first {
                        WidgetCaption(text: "Цього тижня").padding(.top, 3)
                        QuestLine(quest: weekly)
                    }
                } else {
                    Spacer(minLength: 0)
                    Text("Нові завдання — у застосунку")
                        .font(WTFont.text(13, .bold))
                        .foregroundStyle(theme.textMuted)
                        .lineLimit(2)
                    Spacer(minLength: 0)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .wtWidgetContainer { theme.card }
    }
}

private struct QuestLine: View {
    @Environment(\.wtTheme) private var theme
    let quest: WidgetSnapshot.Quest

    var body: some View {
        HStack(spacing: 7) {
            if quest.isDone {
                ZStack {
                    Circle().fill(WTColor.success)
                    WTIcons.check(color: .white, size: 9)
                }
                .frame(width: 18, height: 18)
            } else {
                WidgetRing(fraction: quest.fraction, lineWidth: 3.5).frame(width: 18, height: 18)
            }
            Text(quest.title)
                .font(WTFont.text(13, .bold))
                .foregroundStyle(quest.isDone ? theme.textMuted : theme.textPrimary)
            Spacer(minLength: 2)
            Text(quest.progressLabel)
                .font(WTFont.text(11, .black))
                .foregroundStyle(quest.isDone ? WTColor.successText : theme.textMuted)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - 8. Огляд дня (L)

public struct OverviewWidgetView: View {
    @Environment(\.wtTheme) private var theme
    let content: WidgetContent

    public init(_ content: WidgetContent) { self.content = content }

    public var body: some View {
        let day = content.day
        let snapshot = content.snapshot
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 16) {
                Link(destination: WidgetLink.home.url) {
                    ZStack {
                        WidgetRing(fraction: day.fraction, lineWidth: 14)
                        Text("\(day.percent)%").font(WTFont.number(30)).foregroundStyle(theme.textPrimary)
                    }
                    .frame(width: 112, height: 112)
                }
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text(WidgetPresenter.liters(day.countedMl)).font(WTFont.number(32)).foregroundStyle(theme.textPrimary)
                        Text("/ \(WidgetPresenter.liters(day.goalMl)) л").font(WTFont.text(15, .bold)).foregroundStyle(theme.textMuted)
                    }
                    Text(headline(day))
                        .font(WTFont.text(13, .heavy))
                        .foregroundStyle(day.goalMet ? WTColor.successText : theme.textPrimary)
                    Link(destination: WidgetLink.progress.url) {
                        HStack(spacing: 12) {
                            if let streak = day.streak { StreakBadge(count: streak, size: 17) }
                            HStack(spacing: 5) {
                                WTLevelDrop(level: snapshot.level.level, color: theme.accent, size: 26).widgetAccentable()
                                Text("\(snapshot.level.xpIntoLevel)/\(snapshot.level.xpForNextLevel) XP")
                                    .font(WTFont.text(12, .bold))
                                    .foregroundStyle(theme.textMuted)
                            }
                        }
                    }
                }
            }
            Spacer(minLength: 0)
            Link(destination: WidgetLink.stats.url) {
                VStack(alignment: .leading, spacing: 9) {
                    WidgetCaption(text: "Ритм дня")
                    ForEach(Array(day.blocks.enumerated()), id: \.offset) { _, block in
                        HStack(spacing: 10) {
                            Text(WidgetPresenter.blockHours(block))
                                .font(WTFont.text(12, .heavy))
                                .foregroundStyle(theme.textMuted)
                                .frame(width: 44, alignment: .leading)
                            WidgetBar(fraction: block.fraction, isDone: day.dayRhythmEnabled && block.isReached,
                                      height: 10, highlighted: block.position == .current)
                            Text(((day.dayRhythmEnabled && block.isReached) ? "✓ " : "")
                                 + WidgetPresenter.blockValue(block, rhythm: day.dayRhythmEnabled))
                                .font(WTFont.text(12, .black))
                                .foregroundStyle(block.position == .current ? theme.textPrimary : theme.textMuted)
                                .frame(width: 84, alignment: .trailing)
                        }
                        .opacity(block.position == .future ? 0.55 : 1)
                    }
                }
            }
            Spacer(minLength: 0)
            if let undo = day.undo {
                HStack(spacing: 12) {
                    ZStack {
                        Circle().fill(WTColor.success)
                        WTIcons.check(color: .white, size: 12)
                    }
                    .frame(width: 26, height: 26)
                    Text(WidgetPresenter.addTitle(undo.ml)).font(WTFont.number(20)).foregroundStyle(theme.textPrimary)
                    WidgetActionButton(.undo(intakeId: undo.intakeId)) {
                        Text("Скасувати")
                            .font(WTFont.text(13, .heavy))
                            .foregroundStyle(theme.textButton)
                            .padding(.horizontal, 14)
                            .frame(height: 30)
                            .background(theme.button, in: Capsule())
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 50)
            } else {
                HStack(spacing: WidgetMetrics.gap) {
                    ForEach(Array(snapshot.homeButtons.prefix(3).enumerated()), id: \.offset) { _, ml in
                        WidgetActionButton(.add(ml: ml, source: .widget)) {
                            PortionLabel(title: WidgetPresenter.amount(ml), height: 50)
                        }
                    }
                    Link(destination: WidgetLink.custom.url) {
                        PortionLabel(title: "Інше", prominent: true, height: 50)
                    }
                }
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .wtWidgetContainer { theme.card }
    }

    private func headline(_ day: WidgetDay) -> String {
        if day.goalMet { return "✓ Норму закрито" }
        let left = WidgetPresenter.left(day.leftMl)
        guard let pace = WidgetPresenter.pace(day) else { return left }
        return "\(left) · \(pace)"
    }
}

// MARK: - Екран блокування

/// Кільце «Сьогодні» — відсоток норми.
public struct TodayCircularView: View {
    let content: WidgetContent

    public init(_ content: WidgetContent) { self.content = content }

    public var body: some View {
        Gauge(value: content.day.fraction) {
            Image(systemName: "drop.fill")
        } currentValueLabel: {
            Text("\(content.day.percent)%").font(.system(size: 15, weight: .bold, design: .rounded))
        }
        .gaugeStyle(.accessoryCircularCapacity)
        .widgetAccentable()
        .containerBackground(for: .widget) { AccessoryWidgetBackground() }
    }
}

/// Рядок над годинником.
public struct TodayInlineView: View {
    let content: WidgetContent

    public init(_ content: WidgetContent) { self.content = content }

    public var body: some View {
        Text(WidgetPresenter.inline(content.day))
            .containerBackground(for: .widget) { Color.clear }
    }
}

/// Прямокутник «Частина доби».
public struct DayPartRectangularView: View {
    let content: WidgetContent

    public init(_ content: WidgetContent) { self.content = content }

    public var body: some View {
        let part = WidgetPresenter.part(content.day, xp: content.snapshot.dayPartXp)
        let deadline = part.deadlineMinute.map { " · до \(DayPartPresenter.clock($0))" } ?? ""
        VStack(alignment: .leading, spacing: 2) {
            Text(part.caption.uppercased() + (part.kind == .pending ? deadline : ""))
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .opacity(0.8)
            Text(rectangularHeadline(part))
                .font(.system(size: 16, weight: .bold, design: .rounded))
            Gauge(value: part.fraction) { EmptyView() }
                .gaugeStyle(.accessoryLinearCapacity)
                .widgetAccentable()
        }
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .containerBackground(for: .widget) { Color.clear }
    }

    private func rectangularHeadline(_ part: WidgetPresenter.Part) -> String {
        switch part.kind {
        case .pending, .wholeDay: return "ще \(part.value) \(part.unit ?? "")"
        case .closed: return "✓ закрито"
        case .goalMet: return "✓ Норму закрито"
        case .beforeWake: return "підйом о \(part.value)"
        case .afterSleep: return "\(part.value) норми"
        }
    }
}

/// Кільце «Запас води». Віджет «Запас» і так перемальовується кожні 5 хв (`WidgetKind.cadence`), тож звичайний
/// `Gauge`: `ProgressView(timerInterval:)` поза WidgetKit — спінер, і галерея показувала б не те, що екран блокування.
public struct ReserveCircularView: View {
    let content: WidgetContent

    public init(_ content: WidgetContent) { self.content = content }

    public var body: some View {
        let day = content.day
        let active = day.phase == .active
        Gauge(value: active ? day.reserveFraction : 0) {
            EmptyView()
        } currentValueLabel: {
            Image(systemName: active ? (day.reserveIsEmpty ? "drop" : "drop.fill") : "moon.zzz.fill")
        }
        .gaugeStyle(.accessoryCircularCapacity)
        .widgetAccentable()
        .containerBackground(for: .widget) { AccessoryWidgetBackground() }
    }
}

/// Кругла кнопка «+250» — працює після розблокування.
public struct ButtonCircularView: View {
    let ml: Int

    public init(ml: Int) { self.ml = ml }

    public var body: some View {
        WidgetActionButton(.add(ml: ml, source: .widget)) {
            VStack(spacing: -2) {
                Text("+" + WidgetPresenter.number(ml)).font(.system(size: 18, weight: .bold, design: .rounded))
                Text(WidgetPresenter.unitWord(ml)).font(.system(size: 10, weight: .semibold, design: .rounded))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .containerBackground(for: .widget) { AccessoryWidgetBackground() }
    }
}

// MARK: - Порожній стан

/// Знімка ще немає — застосунок не відкривали після встановлення.
public struct WidgetEmptyView: View {
    @Environment(\.wtTheme) private var theme

    public init() {}

    public var body: some View {
        VStack(spacing: 8) {
            WTDropShape().fill(theme.accent).frame(width: 30, height: 30).widgetAccentable()
            Text("Відкрий застосунок, щоб почати")
                .font(WTFont.text(13, .heavy))
                .foregroundStyle(theme.textPrimary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .wtWidgetContainer { theme.card }
    }
}
