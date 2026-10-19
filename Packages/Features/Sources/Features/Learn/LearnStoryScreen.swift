import SwiftUI
import DesignSystem

/// Історія «Знань» — повноекранні слайди з тапом, як звіт-історія (SPEC-LEARN §5; макет Design/Learn.html,
/// варіант A, рішення від 19.10.2026). Гортання — тапом без автоперемикання; останній — службовий фініш.
public struct LearnStoryScreen: View {
    @Environment(\.wtTheme) private var theme
    @State private var model: LearnStoryModel
    private let onClose: () -> Void
    private let onNavigate: (LearnDestination) -> Void

    init(services: AppServices, storyId: String, startSlide: Int? = nil, onClose: @escaping () -> Void,
         onNavigate: @escaping (LearnDestination) -> Void) {
        _model = State(initialValue: LearnStoryModel(services: services, storyId: storyId, startSlide: startSlide))
        self.onClose = onClose
        self.onNavigate = onNavigate
    }

    public var body: some View {
        WTStoryPlayer(
            count: model.count,
            index: $model.slideIndex,
            header: model.story.shelf.title,
            style: { model.style(at: $0) },
            onClose: onClose,
            closeIdentifier: "learn.close"
        ) { index in
            Group {
                if model.slides.indices.contains(index) {
                    slide(model.slides[index], at: index)
                } else {
                    finish
                }
            }
            .environment(\.wtLearnInk, WTLearnInk.of(model.style(at: index), theme: theme))
            .id("\(model.story.id).\(index)")
        }
        // Досягнення за читання — тостом після закриття: поверх фінішу він ліг би на «Готово».
        .onDisappear { model.announceUnlocks() }
        // Лише на вході у фініш: повернення з нього назад — не подія.
        .wtFeedback(trigger: model.isFinish) { $0 ? .goalReached : nil }
    }

    // MARK: - Слайди

    @ViewBuilder
    private func slide(_ slide: LearnSlide, at index: Int) -> some View {
        let ink = slide.style.isOnColor ? Color.white : theme.textPrimary
        VStack(alignment: .leading, spacing: 0) {
            switch slide.kind {
            case .cover:
                kicker(slide.kicker, style: slide.style)
                visual(slide.visual)
                    .frame(maxHeight: 330)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .wtStoryAppear(delay: 0.1)
                Text(slide.title)
                    .font(WTFont.display(38, .heavy))
                    .fixedSize(horizontal: false, vertical: true)
                    .wtStoryAppear(delay: 0.3)
                    .accessibilityIdentifier("learn.headline")
                if let text = slide.text { paragraph(text, style: slide.style).padding(.top, 10).wtStoryAppear(delay: 0.4) }
                Text("Тапни праворуч, щоб гортати ›")
                    .font(WTFont.text(13, .heavy))
                    .opacity(0.75)
                    .padding(.top, 22)
                    .wtStoryAppear(delay: 1.2)

            case .fact:
                kicker(slide.kicker, style: slide.style)
                if case .body = slide.visual {
                    HStack(alignment: .center, spacing: 6) {
                        number(slide.number)
                        visual(slide.visual).frame(maxWidth: .infinity)
                    }
                    .frame(height: 320)
                    .padding(.top, 10)
                    headline(slide.title).padding(.top, 8)
                    if let text = slide.text { paragraph(text, style: slide.style).padding(.top, 10).wtStoryAppear(delay: 0.5) }
                    Spacer(minLength: 12)
                } else {
                    if slide.number != nil { number(slide.number).padding(.top, 8) }
                    headline(slide.title).padding(.top, 8)
                    visual(slide.visual)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(.vertical, 16)
                        .wtStoryAppear(delay: slide.visual?.isInteractive == true ? 0.2 : 0)
                    if let text = slide.text { paragraph(text, style: slide.style, muted: true).wtStoryAppear(delay: 0.5) }
                }
                sourceLine(slide.source, style: slide.style)

            case .list:
                kicker(slide.kicker, style: slide.style)
                headline(slide.title).padding(.top, 8)
                if slide.visual != nil {
                    visual(slide.visual)
                        .frame(maxWidth: .infinity)
                        .frame(maxHeight: 230)
                        .padding(.vertical, 14)
                }
                VStack(spacing: 10) {
                    ForEach(slide.items.indices, id: \.self) { item in
                        row(slide.items[item]).wtStoryAppear(delay: 0.35 + Double(item) * 0.12)
                    }
                }
                .padding(.top, slide.visual == nil ? 20 : 0)
                if let text = slide.text { paragraph(text, style: slide.style, muted: true).padding(.top, 14).wtStoryAppear(delay: 0.9) }
                Spacer(minLength: 12)
                sourceLine(slide.source, style: slide.style)

            case let .quiz(isTrue, explanation):
                kicker(slide.kicker, style: slide.style)
                visual(slide.visual).frame(height: 150).frame(maxWidth: .infinity).padding(.vertical, 12)
                quizCard(slide.title, isTrue: isTrue, explanation: explanation, at: index)
                    .wtStoryAppear(delay: 0.15)
                Spacer(minLength: 12)
                sourceLine(slide.source, style: slide.style)

            case let .quizScore(button, destination):
                kicker(slide.kicker, style: slide.style)
                visual(slide.visual).frame(maxHeight: 260).frame(maxWidth: .infinity).padding(.vertical, 12)
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    WTCountUpText(Double(model.correctAnswers)).font(WTFont.number(96, .semibold))
                        .accessibilityIdentifier("learn.quiz.score")
                    Text(slide.title).font(WTFont.display(30, .heavy))
                }
                .wtStoryAppear(delay: 0.2)
                if let text = slide.text { paragraph(text, style: slide.style).padding(.top, 8).wtStoryAppear(delay: 0.4) }
                Spacer(minLength: 12)
                actionButton(button, style: slide.style) { model.finish(); onNavigate(destination) }

            case let .action(button, destination):
                kicker(slide.kicker, style: slide.style)
                headline(slide.title).padding(.top, 8)
                visual(slide.visual)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.vertical, 16)
                if let text = slide.text { paragraph(text, style: slide.style).wtStoryAppear(delay: 0.5) }
                actionButton(button, style: slide.style) { model.finish(); onNavigate(destination) }
                    .padding(.top, 18)
            }
        }
        .foregroundStyle(ink)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.top, 34)
        .accessibilityElement(children: .contain)
    }

    // MARK: - Вікторина

    /// Твердження на лицьовому боці, відповідь — на звороті (рішення від 19.10.2026: переворот з варіанту B).
    private func quizCard(_ statement: String, isTrue: Bool, explanation: String, at index: Int) -> some View {
        let answer = model.answers[index]
        return WTLearnFlipCard(flipped: answer != nil) {
            VStack(alignment: .leading, spacing: 18) {
                Text(statement)
                    .font(WTFont.display(25, .heavy))
                    .foregroundStyle(theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("learn.headline")
                Spacer(minLength: 0)
                HStack(spacing: 10) {
                    quizButton("Правда", value: true, at: index)
                    quizButton("Міф", value: false, at: index)
                }
            }
            .padding(22)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .frame(height: 290)
            .background(card(WTRadius.card))
        } back: {
            let correct = answer == isTrue
            VStack(alignment: .leading, spacing: 10) {
                Text(correct ? "✓ Правильно" : "Не зовсім")
                    .font(WTFont.text(13, .black))
                    .foregroundStyle(correct ? WTColor.successText : WTColor.orange)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background((correct ? WTColor.successText : WTColor.orange).opacity(0.14), in: Capsule())
                    .accessibilityIdentifier("learn.quiz.result")
                Text(isTrue ? "Це правда" : "Це міф")
                    .font(WTFont.display(30, .heavy))
                    .foregroundStyle(theme.textPrimary)
                Text(explanation)
                    .font(WTFont.text(17, .bold))
                    .foregroundStyle(theme.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(22)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .frame(height: 290)
            .background(card(WTRadius.card))
        }
        .wtFeedback(trigger: answer) { value in
            guard let value else { return nil }
            return value == isTrue ? .goalReached : .tap
        }
    }

    private func quizButton(_ title: String, value: Bool, at index: Int) -> some View {
        Button { model.answer(value, at: index) } label: {
            Text(title)
                .font(WTFont.text(17, .black))
                .foregroundStyle(theme.textButton)
                .frame(maxWidth: .infinity, minHeight: 56)
                .background(theme.chip, in: RoundedRectangle(cornerRadius: WTRadius.button, style: .continuous))
        }
        .buttonStyle(WTPressStyle())
        .accessibilityIdentifier(value ? "learn.quiz.true" : "learn.quiz.myth")
    }

    // MARK: - Фініш

    private var finish: some View {
        let story = model.story
        let shelf = LearnCatalog.stories(in: story.shelf)
        let read = shelf.filter { model.services.learn.progress($0.id)?.isCompleted == true || $0 == story }.count
        return VStack(spacing: 0) {
            ZStack {
                Circle().fill(theme.accent.opacity(0.18)).frame(width: 108, height: 108)
                WTIcons.check(color: .white, size: 36)
                    .frame(width: 84, height: 84)
                    .background(theme.accent, in: Circle())
            }
            .wtStoryAppear(pop: true)
            Text("Прочитано")
                .font(WTFont.display(30, .heavy))
                .foregroundStyle(theme.textPrimary)
                .padding(.top, 18)
                .wtStoryAppear(delay: 0.15)
                .accessibilityIdentifier("learn.finish")
            Text("Полиця «\(story.shelf.title)» · \(read) з \(shelf.count)")
                .font(WTFont.text(15, .heavy))
                .foregroundStyle(theme.textMuted)
                .padding(.top, 4)
                .wtStoryAppear(delay: 0.25)
            nextRow(model.next).padding(.top, 26).wtStoryAppear(delay: 0.4)
            if !story.sources.isEmpty || story.shelf == .body {
                VStack(alignment: .leading, spacing: 10) {
                    if !story.sources.isEmpty { sources(story.sources) }
                    if story.shelf == .body {
                        Text("Це не медична порада. Якщо маєш хвороби нирок чи серця, норму визначає лікар.")
                            .font(WTFont.text(12, .bold))
                            .foregroundStyle(theme.textMuted)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(theme.chip, in: RoundedRectangle(cornerRadius: WTRadius.control, style: .continuous))
                    }
                }
                .padding(.top, 18)
                .wtStoryAppear(delay: 0.55)
            }
            Spacer(minLength: 12)
            WTPrimaryButton("Готово", action: onClose)
                .accessibilityIdentifier("learn.done")
                .wtStoryAppear(delay: 0.7)
        }
        .padding(.top, 50)
    }

    private func nextRow(_ next: LearnStory) -> some View {
        Button { model.open(next) } label: {
            HStack(spacing: 14) {
                Text(next.emoji)
                    .font(.system(size: 26))
                    .frame(width: 56, height: 56)
                    .background(WTStoryBackground(style: next.shelf.style))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                VStack(alignment: .leading, spacing: 1) {
                    Text("ДАЛІ").font(WTFont.text(11, .black)).tracking(0.5).foregroundStyle(theme.textMuted)
                    Text(next.title).font(WTFont.text(16, .heavy)).foregroundStyle(theme.textPrimary)
                    Text("\(next.minutes) хв").font(WTFont.text(12, .bold)).foregroundStyle(theme.textMuted)
                }
                Spacer(minLength: 4)
                WTIcons.chevronRight(color: theme.accent, size: 15)
            }
            .padding(12)
            .background(card(WTRadius.panel))
        }
        .buttonStyle(WTPressStyle(scale: 0.98))
        .accessibilityIdentifier("learn.next")
    }

    private func sources(_ sources: [LearnSource]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("ДЖЕРЕЛА").font(WTFont.text(11, .black)).tracking(0.5).foregroundStyle(theme.textMuted)
            ForEach(sources.indices, id: \.self) { index in
                Text("\(index + 1). \(sources[index].full)")
                    .font(WTFont.text(12, .bold))
                    .foregroundStyle(theme.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Ілюстрації

    @ViewBuilder
    private func visual(_ visual: LearnVisual?) -> some View {
        switch visual {
        case .drop(let level): WTLearnDrop(level: level)
        case .emoji(let emoji): WTLearnEmoji(emoji).frame(maxHeight: 230)
        case .body(let fraction): WTLearnBody(fraction: fraction)
        case .bodyMap(let badges): WTLearnBody(fraction: 1, badges: badges)
        case let .columns(left, right): WTLearnColumns(left: left, right: right)
        case .question: WTLearnQuestion()
        case let .ring(total, caption, segments): WTLearnSegmentRing(total: total, caption: caption, segments: segments)
        case .level(let level): WTLearnLevel(level: level).frame(maxHeight: 300)
        case let .glasses(full, bonus, locked, chip, legend):
            WTLearnGlasses(full: full, bonus: bonus, locked: locked, chip: chip, legend: legend)
        case let .ladder(nodes, progress): WTLearnLadder(nodes: nodes, progress: progress)
        case let .stack(unit, caption, segments): WTLearnStackBar(unit: unit, caption: caption, segments: segments)
        case let .bars(bars, legend): WTLearnBars(bars: bars, legend: legend)
        case .tiles(let items): WTLearnTiles(items: items)
        case let .chain(days, labels, caption): WTLearnChain(days: days, labels: labels, caption: caption)
        case .tokens(let tokens): WTLearnTokens(tokens: tokens)
        case let .dayLine(drops, bells, start, end): WTLearnDayLine(drops: drops, bells: bells, start: start, end: end)
        case .dots(let count): DotsVisual(count: count)
        case .homeRing(let percent):
            ZStack {
                WTProgressRing(progress: Double(percent) / 100, diameter: 210, lineWidth: 18)
                Text("\(percent)%").font(WTFont.number(52, .semibold)).foregroundStyle(theme.textPrimary)
            }
        case let .dayPartPill(title, xp, timeLeft):
            VStack(spacing: 16) {
                WTProgressRing(progress: 0.45, diameter: 150, lineWidth: 14)
                WTDayPartPill(.pending(fraction: 0.6, title: title, xp: xp, timeLeft: timeLeft), accessibilityLabel: title)
            }
        case let .colorScale(verdicts, prompt): WTLearnColorScale(verdicts: verdicts, prompt: prompt)
        case let .curve(modes, captions, start, end): WTLearnCurve(modes: modes, captions: captions, start: start, end: end)
        case let .chips(options, limit, prompt):
            WTLearnChips(options: options, limit: limit, prompt: prompt) { picked in
                "Твої якорі: \(picked.joined(separator: " і ")). Постав склянку поруч."
            }
        case let .miniHome(goal, buttons):
            WTLearnMiniHome(goal: goal, buttons: buttons.prefix(3).map { (HomeScreen.amountTitle($0), $0) },
                            volume: { ReportFormat.volume($0) })
        case let .factors(base, label, factors):
            WTLearnFactors(base: Double(base), baseLabel: label, factors: factors,
                           format: { ReportFormat.volume(Int($0)) })
        case nil: EmptyView()
        }
    }

    // MARK: - Будівельні блоки

    private func kicker(_ text: String, style: WTStoryStyle) -> some View {
        Text(text.uppercased())
            .font(WTFont.text(13, .black))
            .tracking(0.6)
            .foregroundStyle(style.isOnColor ? Color.white.opacity(0.8) : theme.textMuted)
            .wtStoryAppear()
    }

    private func headline(_ text: String) -> some View {
        Text(text)
            .font(WTFont.display(28, .heavy))
            .fixedSize(horizontal: false, vertical: true)
            .wtStoryAppear(delay: 0.1)
            .accessibilityIdentifier("learn.headline")
    }

    private func paragraph(_ text: String, style: WTStoryStyle, muted: Bool = false) -> some View {
        Text(text)
            .font(WTFont.text(muted ? 15 : 17, .bold))
            .foregroundStyle(style.isOnColor ? Color.white.opacity(0.92) : muted ? theme.textMuted : theme.textPrimary)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private func number(_ number: LearnSlide.Number?) -> some View {
        if let number {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                if !number.prefix.isEmpty { Text(number.prefix) }
                WTCountUpText(number.value, decimals: number.decimals)
                if !number.unit.isEmpty {
                    Text(number.unit).font(WTFont.text(30, .heavy)).opacity(0.75)
                }
            }
            .font(WTFont.number(88, .semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .wtStoryAppear(delay: 0.08)
        }
    }

    private func row(_ item: LearnSlide.Item) -> some View {
        HStack(spacing: 14) {
            Text(item.emoji)
                .font(.system(size: 22))
                .frame(width: 46, height: 46)
                .background(theme.chip, in: Circle())
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title).font(WTFont.text(16, .heavy)).foregroundStyle(theme.textPrimary)
                if let detail = item.detail {
                    Text(detail).font(WTFont.text(13, .bold)).foregroundStyle(theme.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 4)
            if let value = item.value {
                Text(value).font(WTFont.text(15, .black)).foregroundStyle(WTColor.orange)
            }
        }
        .padding(.vertical, 11)
        .padding(.horizontal, 14)
        .background(card(WTRadius.tile))
        .accessibilityElement(children: .combine)
    }

    /// Підкладка картки з тінню: тінь на самій формі, а не на вмісті — інакше текст «світиться».
    private func card(_ radius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous).fill(theme.card).wtShadow(.card)
    }

    @ViewBuilder
    private func sourceLine(_ source: LearnSource?, style: WTStoryStyle) -> some View {
        if let source { LearnSourceLine(source: source, onColor: style.isOnColor) }
    }

    private func actionButton(_ title: String, style: WTStoryStyle, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(WTFont.display(18, .semibold))
                .foregroundStyle(style.isOnColor ? theme.waterDeep : .white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 17)
                .background(style.isOnColor ? Color.white : style == .learnWarm ? WTColor.orange : theme.accent,
                            in: RoundedRectangle(cornerRadius: WTRadius.primaryButton, style: .continuous))
        }
        .buttonStyle(WTPressStyle())
        .accessibilityIdentifier("learn.action")
        .wtStoryAppear(delay: 0.6)
    }
}

/// «Звідки цифра? Popkin et al., 2010» — тап розгортає повну назву джерела.
private struct LearnSourceLine: View {
    @Environment(\.wtTheme) private var theme
    let source: LearnSource
    let onColor: Bool
    @State private var expanded = false

    var body: some View {
        Button { withAnimation(WTAnimation.fade) { expanded.toggle() } } label: {
            VStack(alignment: .leading, spacing: 4) {
                (Text("Звідки цифра? ") + Text(source.short).underline(pattern: .dash))
                    .font(WTFont.text(12, .heavy))
                if expanded {
                    Text(source.full)
                        .font(WTFont.text(12, .bold))
                        .fixedSize(horizontal: false, vertical: true)
                        .transition(.opacity)
                }
            }
            .foregroundStyle(onColor ? Color.white.opacity(0.85) : theme.textMuted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("learn.source")
    }
}

/// 66 крапель — «стільки днів до звички».
private struct DotsVisual: View {
    @Environment(\.wtLearnInk) private var ink
    let count: Int

    var body: some View {
        WTDropGrid(count: count, columns: 11, color: ink.fill)
            .frame(maxWidth: 320)
    }
}
