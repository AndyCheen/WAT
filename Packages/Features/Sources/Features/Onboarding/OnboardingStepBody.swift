import SwiftUI
import Core
import Persistence
import DesignSystem

/// Вміст кроку — заголовок і контроли. Однаковий для «Сцени» й «Кроків» (SPEC-ONBOARDING §10): там, де
/// «Сцена» показує картинку вгорі (число норми, склянку, екран блокування), «Кроки» малюють її тут.
struct OnboardingStepBody: View {
    @Environment(\.wtTheme) private var theme
    @Bindable var model: OnboardingModel
    let design: OnboardingDesign
    private typealias P = OnboardingPresenter

    private var answers: OnboardingAnswers { model.draft.answers }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            switch model.step {
            case .hello: hello
            case .units: question { units }
            case .gender: question { gender }
            case .age: question { age }
            case .weight: question { weight }
            case .activity: question { activity }
            case .goal: question { goal }
            case .day: question { day }
            case .rhythm: question { rhythm }
            case .glass: question { glass }
            case .reminders: question { reminders }
            case .done: done
            }
            Color.clear.frame(height: 1).id(Self.bottomAnchor)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Низ вмісту — сюди каркас докручує панель, коли крок розкрився (`OnboardingModel.expansion`).
    static let bottomAnchor = "onboarding.bottom"

    private func question<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        Group {
            OnboardingHeader(kicker: P.stepLabel(model.step), header: model.header, centered: false, step: model.step)
            content()
        }
    }

    // MARK: - Вітання

    @ViewBuilder
    private var hello: some View {
        if model.mode == .firstRun {
            if design == .steps {
                WTLearnDrop(level: 0.62)
                    .environment(\.wtLearnInk, WTLearnInk.of(.plain, theme: theme))
                    .frame(width: 190)
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 8)
            }
            OnboardingHeader(kicker: nil, header: model.header, centered: true, step: .hello)
        } else {
            OnboardingHeader(kicker: nil, header: model.header, centered: false, step: .hello)
            WTSummaryCard(rows: P.current(model.baseline, reminders: model.reminders).map(Self.summaryRow),
                          identifierPrefix: "onboarding.current")
        }
    }

    // MARK: - Одиниці

    private var units: some View {
        VStack(spacing: 16) {
            WTSegmentRow(P.unitRows[0].title, options: P.unitRows[0].options,
                         selection: VolumeUnit.allCases.firstIndex(of: answers.volumeUnit) ?? 0,
                         current: current(\.volumeUnit, VolumeUnit.allCases), identifierPrefix: "onboarding.units.volume") {
                model.draft.answers.volumeUnit = VolumeUnit.allCases[$0]
            }
            WTSegmentRow(P.unitRows[1].title, options: P.unitRows[1].options,
                         selection: MassUnit.allCases.firstIndex(of: answers.massUnit) ?? 0,
                         current: current(\.massUnit, MassUnit.allCases), identifierPrefix: "onboarding.units.mass") {
                model.draft.answers.massUnit = MassUnit.allCases[$0]
            }
            WTSegmentRow(P.unitRows[2].title, options: P.unitRows[2].options,
                         selection: TimeFormat.allCases.firstIndex(of: answers.timeFormat) ?? 0,
                         current: current(\.timeFormat, TimeFormat.allCases), identifierPrefix: "onboarding.units.time") {
                model.draft.answers.timeFormat = TimeFormat.allCases[$0]
            }
        }
    }

    /// Індекс поточного значення для крапки «зараз» — лише в повторному проході.
    private func current<Value: Equatable>(_ keyPath: KeyPath<OnboardingAnswers, Value>, _ all: [Value]) -> Int? {
        model.mode == .revisit ? all.firstIndex(of: model.baseline.answers[keyPath: keyPath]) : nil
    }

    // MARK: - Стать і стан

    @ViewBuilder
    private var gender: some View {
        ForEach(P.genderOptions, id: \.id) { option in
            WTChoiceRow(option.title, badge: model.isCurrent(\.gender, option.value) ? P.nowBadge : nil,
                        isSelected: answers.gender == option.value) {
                withAnimation(WTAnimation.sheet) {
                    model.draft.answers.gender = option.value
                    if option.value != .female { model.draft.answers.condition = .none }
                }
            }
            .accessibilityIdentifier("onboarding.gender.\(option.id)")
        }
        if answers.gender == .female {
            VStack(alignment: .leading, spacing: 10) {
                Text(P.conditionQuestion)
                    .font(WTFont.text(15, .heavy))
                    .foregroundStyle(theme.textPrimary)
                WTFlowLayout(spacing: 8) {
                    ForEach(P.conditionOptions, id: \.id) { option in
                        WTChoiceChip(option.title, isSelected: answers.condition == option.value,
                                     isCurrent: model.isCurrent(\.condition, option.value)) {
                            model.draft.answers.condition = option.value
                        }
                        .accessibilityIdentifier("onboarding.condition.\(option.id)")
                    }
                }
                WTDisclaimer(P.conditionDisclaimer)
                    .accessibilityIdentifier("onboarding.condition.disclaimer")
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.card, in: RoundedRectangle(cornerRadius: WTRadius.button, style: .continuous))
            .wtShadow(.card)
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }

    // MARK: - Вік

    @ViewBuilder
    private var age: some View {
        WTWheelPicker(value: Binding(get: { model.ageWheelValue }, set: { model.setAge($0) }),
                      range: OnboardingAnswers.ageRange, isDimmed: answers.age == nil, accessibilityTitle: "Вік")
            .frame(maxWidth: .infinity)
            .accessibilityIdentifier("onboarding.age.wheel")
        HStack {
            Spacer()
            WTChoiceChip(P.ageNotSpecified, isSelected: answers.age == nil, isCurrent: model.isCurrent(\.age, nil)) {
                model.setAge(nil)
            }
            .accessibilityIdentifier("onboarding.age.none")
            Spacer()
        }
        WTWasLine(wasContent(model.mark(for: .age)), identifier: "onboarding.age.mark") { model.revert(.age) }
            .frame(maxWidth: .infinity)
    }

    // MARK: - Вага

    @ViewBuilder
    private var weight: some View {
        let value = model.weightValue
        if design == .steps {
            HStack(spacing: 20) {
                WTStepperButton("–", size: 46) { model.stepWeight(-1) }
                    .accessibilityLabel("Менше")
                    .accessibilityIdentifier("onboarding.weight.minus")
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(value)")
                        .font(WTFont.number(76, .semibold))
                        .foregroundStyle(theme.textPrimary)
                        .contentTransition(.numericText())
                        .accessibilityIdentifier("onboarding.weight.value")
                    Text(P.weightUnit(value, answers.massUnit))
                        .font(WTFont.text(22, .heavy))
                        .foregroundStyle(theme.textMuted)
                }
                .animation(WTAnimation.fade, value: value)
                WTStepperButton("+", size: 46) { model.stepWeight(1) }
                    .accessibilityLabel("Більше")
                    .accessibilityIdentifier("onboarding.weight.plus")
            }
            .frame(maxWidth: .infinity)
        }
        WTRulerPicker(value: $model.weightValue, range: P.weightRange(answers.massUnit), marked: weightMark,
                      accessibilityTitle: "Вага", accessibilityValue: P.weight(answers.weightKg, answers.massUnit),
                      identifier: "onboarding.weight.ruler")
            .id(answers.massUnit)
        if design == .scene {
            HStack(spacing: 10) {
                Spacer()
                WTChoiceChip("−1 \(P.weightUnit(1, answers.massUnit))", isSelected: false) { model.stepWeight(-1) }
                    .accessibilityIdentifier("onboarding.weight.minus")
                WTChoiceChip("+1 \(P.weightUnit(1, answers.massUnit))", isSelected: false) { model.stepWeight(1) }
                    .accessibilityIdentifier("onboarding.weight.plus")
                Spacer()
            }
        }
        WTWasLine(wasContent(model.mark(for: .weight)), identifier: "onboarding.weight.mark") { model.revert(.weight) }
            .frame(maxWidth: .infinity)
    }

    /// Крапка «зараз» на лінійці — лише для відомої ваги в повторному проході.
    private var weightMark: Int? {
        guard model.mode == .revisit, model.baseline.weightKnown else { return nil }
        return P.weightNumber(model.baseline.answers.weightKg, answers.massUnit)
    }

    // MARK: - Активність

    private var activity: some View {
        ForEach(P.activityOptions, id: \.id) { option in
            WTChoiceRow(option.title, subtitle: option.subtitle, glyph: option.glyph,
                        badge: model.isCurrent(\.activity, option.value) ? P.nowBadge : nil,
                        isSelected: answers.activity == option.value) {
                model.draft.answers.activity = option.value
            }
            .accessibilityIdentifier("onboarding.activity.\(option.id)")
        }
    }

    // MARK: - Норма

    @ViewBuilder
    private var goal: some View {
        if design == .steps { goalHero }
        if model.offersGoalChoice {
            ForEach(P.goalOptions(baseline: model.baseline), id: \.id) { option in
                WTChoiceRow(option.title, subtitle: option.subtitle,
                            badge: option.value == .keepCurrent ? P.nowBadge : nil,
                            isSelected: model.draft.goalChoice == option.value) {
                    withAnimation(WTAnimation.fade) { model.draft.goalChoice = option.value }
                }
                .accessibilityIdentifier("onboarding.goal.\(option.id)")
            }
        }
        if design == .scene && model.canAdjustGoal {
            WTSettingRow(P.goalAdjustTitle) {
                WTValueStepper(P.adjustLabel(model.draft.goalAdjustMl, answers.volumeUnit), identifier: "onboarding.goal.adjust",
                               onDecrement: { model.stepGoal(-1) }, onIncrement: { model.stepGoal(1) })
            }
        }
        WTGoalBreakdown(rows: model.goalParts.map(Self.breakdownRow))
        WTDisclaimer(P.goalDisclaimer)
            .accessibilityIdentifier("onboarding.goal.disclaimer")
    }

    /// «Кроки»: крапля й число з ± — те, що «Сцена» показує вгорі.
    private var goalHero: some View {
        let parts = P.goalParts(model.goalMl, answers.volumeUnit)
        return VStack(spacing: 4) {
            WTLearnDrop(level: min(0.94, max(0.3, Double(model.goalMl) / 4000)))
                .environment(\.wtLearnInk, WTLearnInk.of(.plain, theme: theme))
                .frame(width: 120)
            HStack(spacing: 18) {
                WTStepperButton("–", size: 46) { model.stepGoal(-1) }
                    .opacity(model.canAdjustGoal ? 1 : 0)
                    .disabled(!model.canAdjustGoal)
                    .accessibilityLabel("Менше")
                    .accessibilityIdentifier("onboarding.goal.minus")
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(parts.number)
                        .font(WTFont.number(64, .semibold))
                        .contentTransition(.numericText())
                        .accessibilityIdentifier("onboarding.goal.value")
                    Text(parts.unit).font(WTFont.text(24, .heavy))
                }
                .foregroundStyle(theme.textPrimary)
                .animation(WTAnimation.fade, value: parts.number)
                WTStepperButton("+", size: 46) { model.stepGoal(1) }
                    .opacity(model.canAdjustGoal ? 1 : 0)
                    .disabled(!model.canAdjustGoal)
                    .accessibilityLabel("Більше")
                    .accessibilityIdentifier("onboarding.goal.plus")
            }
            HStack(spacing: 8) {
                Text(P.goalCaption).font(WTFont.text(14, .heavy)).foregroundStyle(theme.textMuted)
                if model.mode == .revisit && !model.offersGoalChoice { WTMarkPill(P.nowBadge) }
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - День

    @ViewBuilder
    private var day: some View {
        if design == .steps {
            WTSceneDayTrack(rows: OnboardingSceneArt.dayRows(answers, blocks: false), axis: OnboardingSceneArt.dayAxis)
                .environment(\.wtLearnInk, WTLearnInk.of(.plain, theme: theme))
        }
        WTCard {
            VStack(spacing: 0) {
                timeRow(.wake, weekend: false, glyph: "☀️", title: "Підйом", id: "wake")
                WTDivider()
                timeRow(.sleep, weekend: false, glyph: "🌙", title: "Відбій", id: "sleep")
                WTDivider()
                WTSettingRow("У вихідні інакше") {
                    WTToggle(isOn: $model.draft.answers.week.weekendEnabled)
                        .accessibilityIdentifier("onboarding.day.weekend")
                }
                if answers.week.weekendEnabled {
                    WTDivider()
                    timeRow(.wake, weekend: true, glyph: "☀️", title: "Підйом у вихідні", id: "weekendWake")
                    WTDivider()
                    timeRow(.sleep, weekend: true, glyph: "🌙", title: "Відбій у вихідні", id: "weekendSleep")
                }
            }
        }
    }

    private func timeRow(_ bound: OnboardingModel.TimeBound, weekend: Bool, glyph: String, title: String, id: String) -> some View {
        let schedule = weekend ? answers.week.weekend : answers.week.weekday
        let minutes = bound == .wake ? schedule.wakeMinutes : schedule.sleepMinutes
        return HStack(spacing: 12) {
            Text(glyph).font(.system(size: 18)).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(WTFont.text(16, .bold)).foregroundStyle(theme.textPrimary)
                timeMark(model.timeMark(bound, weekend: weekend), bound: bound, weekend: weekend, id: id)
            }
            Spacer(minLength: 8)
            WTValueStepper(P.clock(minutes, answers.timeFormat), identifier: "onboarding.day.\(id)",
                           onDecrement: { model.stepTime(bound, weekend: weekend, direction: -1) },
                           onIncrement: { model.stepTime(bound, weekend: weekend, direction: 1) })
        }
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private func timeMark(_ mark: OnboardingModel.Mark, bound: OnboardingModel.TimeBound, weekend: Bool, id: String) -> some View {
        switch mark {
        case .current:
            WTMarkPill(P.nowBadge)
        case .was(let old):
            Button {
                withAnimation(WTAnimation.fade) { model.revertTime(bound, weekend: weekend) }
            } label: {
                HStack(spacing: 4) {
                    Text("\(P.wasPrefix.lowercased()) \(old)").foregroundStyle(theme.textMuted)
                    Image(systemName: "arrow.uturn.backward").foregroundStyle(theme.textButton)
                }
                .font(WTFont.text(12, .heavy))
            }
            .buttonStyle(WTPressStyle())
            .accessibilityLabel("\(P.revert): \(old)")
            .accessibilityIdentifier("onboarding.day.\(id).revert")
        case .none, .typical:
            EmptyView()
        }
    }

    // MARK: - Ритм

    @ViewBuilder
    private var rhythm: some View {
        ForEach(P.rhythmOptions, id: \.id) { option in
            WTChoiceRow(option.title, subtitle: option.subtitle,
                        badge: model.isCurrent(\.dayRhythm, option.value) ? P.nowBadge : nil,
                        isSelected: answers.dayRhythm == option.value) {
                withAnimation(WTAnimation.fade) { model.draft.answers.dayRhythm = option.value }
            }
            .accessibilityIdentifier("onboarding.rhythm.\(option.id)")
        }
        if OnboardingChanges.switchesToIntervals(baseline: model.baseline, draft: model.draft) {
            Text(P.intervalsNote)
                .font(WTFont.text(13, .heavy))
                .foregroundStyle(theme.textMuted)
                .frame(maxWidth: .infinity)
                .transition(.opacity)
                .accessibilityIdentifier("onboarding.rhythm.intervals")
        }
    }

    // MARK: - Склянка

    @ViewBuilder
    private var glass: some View {
        if design == .steps {
            WTGlassIllustration(fraction: 0.75)
                .frame(height: 120 + CGFloat(answers.glassMl - 200) * 0.35)
                .frame(maxWidth: .infinity, minHeight: 190, alignment: .bottom)
                .animation(WTAnimation.sheet, value: answers.glassMl)
        }
        WTFlowLayout(spacing: 8) {
            ForEach(OnboardingAnswers.glassChoicesMl, id: \.self) { ml in
                WTChoiceChip(P.volume(ml, answers.volumeUnit), isSelected: answers.glassMl == ml,
                             isCurrent: model.isCurrent(\.glassMl, ml)) {
                    model.draft.answers.glassMl = ml
                }
                .accessibilityIdentifier("onboarding.glass.\(ml)")
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Нагадування

    @ViewBuilder
    private var reminders: some View {
        if design == .steps {
            WTLockScreenPreview(time: P.lockTime, date: P.lockDate, appName: "WaterTracker", stamp: "зараз",
                                title: P.previewTitle, message: P.previewBody(answers), actions: P.previewActions(answers))
                .padding(14)
                .background(WTStoryBackground(style: .learnDeep)
                    .clipShape(RoundedRectangle(cornerRadius: WTRadius.card, style: .continuous)))
                .environment(\.wtLearnInk, WTLearnInk.of(.learnDeep, theme: theme))
        }
        if model.mode == .revisit && model.reminders == .granted {
            WTMarkPill(P.nowBadge).frame(maxWidth: .infinity)
        }
    }

    // MARK: - Фініш

    @ViewBuilder
    private var done: some View {
        if model.mode == .firstRun {
            if design == .steps {
                WTLearnDrop(level: 0.86)
                    .environment(\.wtLearnInk, WTLearnInk.of(.plain, theme: theme))
                    .frame(width: 130)
                    .overlay(alignment: .center) { WTSceneCheck().offset(y: 18) }
                    .frame(maxWidth: .infinity)
            }
            OnboardingHeader(kicker: nil, header: .init(title: P.doneTitle, subtitle: P.doneSubtitle), centered: true, step: .done)
            WTSummaryCard(rows: P.summary(answers, goalMl: model.goalMl, reminders: model.reminders).map(Self.summaryRow),
                          identifierPrefix: "onboarding.summary")
        } else {
            let changes = model.changes
            if changes.isEmpty {
                OnboardingHeader(kicker: nil, header: .init(title: P.noChangesTitle, subtitle: P.noChangesSubtitle),
                                 centered: true, step: .done)
            } else {
                OnboardingHeader(kicker: nil, header: .init(title: P.changesTitle, subtitle: P.changesSubtitle),
                                 centered: false, step: .done)
                WTSummaryCard(rows: changes.map { WTSummaryCard.Row(id: $0.id, glyph: $0.glyph, title: $0.title, value: $0.new, old: $0.old) },
                              identifierPrefix: "onboarding.change")
                Text(P.restUnchanged)
                    .font(WTFont.text(13, .heavy))
                    .foregroundStyle(theme.textMuted)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: - Перетворення

    private func wasContent(_ mark: OnboardingModel.Mark) -> WTWasLine.Content {
        switch mark {
        case .none: return .none
        case .current: return .pill(P.nowBadge)
        case .typical: return model.mode == .firstRun ? .hint(P.typicalHint) : .pill(P.typicalBadge)
        case .was(let old): return .was("\(P.wasPrefix) \(old) ·", revert: P.revert)
        }
    }

    static func summaryRow(_ row: OnboardingPresenter.SummaryRow) -> WTSummaryCard.Row {
        WTSummaryCard.Row(id: row.id, glyph: row.glyph, title: row.title, value: row.value, detail: row.detail)
    }

    static func breakdownRow(_ row: OnboardingPresenter.PartRow) -> WTGoalBreakdown.Row {
        let tone: WTGoalBreakdown.Row.Tone
        switch row.tone {
        case .weight: tone = .primary
        case .age: tone = .outline
        case .activity: tone = .secondary
        case .extra: tone = .extra
        }
        return WTGoalBreakdown.Row(id: row.id, tone: tone, title: row.title, value: row.value, weight: max(0, row.ml))
    }
}

/// Надзаголовок «НОРМА · 2 / 5», заголовок і підпис. Ідентифікатор заголовка — `onboarding.title.<крок>`: за ним
/// e2e знають, на якому кроці вони зараз.
struct OnboardingHeader: View {
    @Environment(\.wtTheme) private var theme
    let kicker: String?
    let header: OnboardingPresenter.Header
    let centered: Bool
    let step: OnboardingStep

    var body: some View {
        VStack(alignment: centered ? .center : .leading, spacing: 8) {
            if let kicker {
                Text(kicker)
                    .font(WTFont.text(12, .black))
                    .tracking(0.6)
                    .foregroundStyle(theme.accent)
            }
            Text(header.title)
                .font(WTFont.display(27, .bold))
                .foregroundStyle(theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("onboarding.title.\(step.rawValue)")
            if let subtitle = header.subtitle {
                Text(subtitle)
                    .font(WTFont.text(15, .bold))
                    .foregroundStyle(theme.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .multilineTextAlignment(centered ? .center : .leading)
        .frame(maxWidth: .infinity, alignment: centered ? .center : .leading)
    }
}

/// Нижні кнопки кроку: головна дія й тихе посилання під нею.
struct OnboardingFooter: View {
    @Environment(\.wtTheme) private var theme
    let model: OnboardingModel
    private typealias P = OnboardingPresenter

    private struct Action {
        let title: String
        let id: String
        var quiet = true
        let run: () -> Void
    }

    var body: some View {
        let (primary, secondary) = actions
        VStack(spacing: 2) {
            WTPrimaryButton(primary.title, action: primary.run)
                .accessibilityIdentifier(primary.id)
            if let secondary {
                Button(secondary.title, action: secondary.run)
                    .font(WTFont.text(15, .heavy))
                    .foregroundStyle(secondary.quiet ? theme.textMuted : theme.textButton)
                    .frame(minHeight: 44)
                    .buttonStyle(WTPressStyle())
                    .accessibilityIdentifier(secondary.id)
            }
        }
    }

    private var actions: (Action, Action?) {
        let next = Action(title: P.next, id: "onboarding.next", run: model.next)
        switch model.step {
        case .hello:
            return model.mode == .firstRun
                ? (Action(title: P.start, id: "onboarding.next", run: model.next),
                   Action(title: P.skip, id: "onboarding.skip", run: model.skip))
                : (Action(title: P.start, id: "onboarding.next", run: model.next),
                   Action(title: P.notNow, id: "onboarding.close", run: model.close))
        case .goal:
            return (Action(title: model.mode == .firstRun ? P.acceptGoal : P.next, id: "onboarding.next", run: model.next), nil)
        case .reminders:
            switch model.reminders {
            case .granted:
                return (next, nil)
            case .denied:
                return (Action(title: P.openSettings, id: "onboarding.reminders.settings", run: model.openSystemSettings), next)
            case .notAsked, .postponed, .disabledInApp:
                return (Action(title: P.enable, id: "onboarding.reminders.enable", run: model.enableReminders),
                        Action(title: P.notNow, id: "onboarding.reminders.later", run: model.postponeReminders))
            }
        case .done:
            if model.mode == .firstRun {
                return (Action(title: P.finish, id: "onboarding.finish", run: { model.finish() }),
                        Action(title: "📖 \(P.howTo)", id: "onboarding.learn", quiet: false, run: { model.finish(.learn) }))
            }
            return model.changes.isEmpty
                ? (Action(title: P.ready, id: "onboarding.save", run: model.save), nil)
                : (Action(title: P.save, id: "onboarding.save", run: model.save),
                   Action(title: P.cancel, id: "onboarding.cancel", run: model.confirmExit))
        default:
            return (next, nil)
        }
    }
}
