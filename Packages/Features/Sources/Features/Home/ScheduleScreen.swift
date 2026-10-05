import SwiftUI
import Core
import DesignSystem

/// Вікно «Графік дня» (WAT-41, SPEC-NOTIFICATIONS §27, макет Design/Schedule.html, варіант A «Час»).
///
/// На весь екран, як «Склянка»: рішення про весь день, а не дрібне налаштування. Свідомо мало всього —
/// питання, одне речення, «08:00 → 06:30» і три дії; перша версія з дугою, позначками й доказами
/// виявилась перевантаженою. Показ і закриття — через `HomeViewModel.present(_:)`.
struct ScheduleScreen: View {
    @Environment(\.wtTheme) private var theme
    let model: HomeViewModel

    var body: some View {
        ZStack {
            theme.screen.ignoresSafeArea()
            WTBubbles().ignoresSafeArea()

            if let content = model.scheduleContent {
                VStack(spacing: 0) {
                    topBar
                    Spacer(minLength: 0)
                    middle(content)
                    Spacer(minLength: 0)
                    actions
                }
                .padding(.horizontal, WTSpacing.screenSideHome)
                .padding(.bottom, WTSpacing.screenBottom)
            }
        }
    }

    private var topBar: some View {
        HStack {
            WTCircleButton(action: { model.closeSchedule() }) {
                WTIcons.close(color: theme.accent)
            }
            .accessibilityLabel("Закрити")
            .accessibilityIdentifier("schedule.close")
            Spacer()
        }
    }

    private func middle(_ content: SchedulePresenter.Content) -> some View {
        VStack(spacing: 0) {
            WTGlyphBadge(content.glyph)
                .padding(.bottom, 22)
                .wtStoryAppear(pop: true)
            if let scope = content.scope {
                WTScopePill(scope)
                    .padding(.bottom, 12)
                    .accessibilityIdentifier("schedule.scope")
                    .wtStoryAppear(delay: 0.05)
            }
            Text(content.title)
                .font(WTFont.display(28, .bold))
                .foregroundStyle(theme.textPrimary)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("schedule.title")
                .wtStoryAppear(delay: 0.1)
            Text(content.subtitle)
                .font(WTFont.text(15, .bold))
                .foregroundStyle(theme.textMuted)
                .multilineTextAlignment(.center)
                .padding(.top, 8)
                .accessibilityIdentifier("schedule.subtitle")
                .wtStoryAppear(delay: 0.18)
            times(content)
                .padding(.top, 34)
                .wtStoryAppear(delay: 0.3)
        }
    }

    /// «08:00 → 06:30» — лише межі, що змінюються; після «Налаштувати» — кроки для обох.
    @ViewBuilder
    private func times(_ content: SchedulePresenter.Content) -> some View {
        if model.scheduleAdjusting {
            VStack(spacing: 14) {
                WTTimeStepper(glyph: SchedulePresenter.wakeGlyph, value: DaySchedule.clock(model.scheduleDraft.wakeMinutes),
                              title: "Підйом", identifier: "schedule.wake",
                              onDecrement: { model.stepScheduleWake(-1) }, onIncrement: { model.stepScheduleWake(1) })
                WTTimeStepper(glyph: SchedulePresenter.sleepGlyph, value: DaySchedule.clock(model.scheduleDraft.sleepMinutes),
                              title: "Відбій", identifier: "schedule.sleep",
                              onDecrement: { model.stepScheduleSleep(-1) }, onIncrement: { model.stepScheduleSleep(1) })
            }
            .transition(.opacity)
        } else {
            VStack(spacing: 14) {
                ForEach(content.changes) { change in
                    WTTimeChange(glyph: content.changes.count > 1 ? change.glyph : nil, old: change.old, new: change.new,
                                 accessibilityLabel: change.accessibilityLabel)
                        .accessibilityIdentifier("schedule.change.\(change.bound.rawValue)")
                }
            }
            .transition(.opacity)
        }
    }

    private var actions: some View {
        VStack(spacing: 16) {
            WTPrimaryButton(model.scheduleAdjusting ? "Зберегти" : "Так, змінити") { model.acceptSchedule() }
                .accessibilityIdentifier("schedule.accept")
            HStack(spacing: 28) {
                if !model.scheduleAdjusting {
                    Button("Налаштувати") { model.adjustSchedule() }
                        .foregroundStyle(theme.textButton)
                        .accessibilityIdentifier("schedule.adjust")
                }
                Button("Ні, залишити") { model.declineSchedule() }
                    .foregroundStyle(theme.textMuted)
                    .accessibilityIdentifier("schedule.decline")
            }
            .font(WTFont.text(15, .heavy))
            .buttonStyle(WTPressStyle(scale: 0.96))
        }
    }
}
