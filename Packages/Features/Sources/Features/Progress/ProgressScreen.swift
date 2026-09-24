import SwiftUI
import Core
import DesignSystem
import Gamification

/// Макет 3f — рівень, нагороди, завдання, призи, досягнення.
public struct ProgressScreen: View {
    @Environment(\.wtTheme) private var theme
    @State private var model: ProgressViewModel
    private let onBack: () -> Void
    private let onOpenAllAchievements: () -> Void

    public init(services: AppServices, onBack: @escaping () -> Void, onOpenAllAchievements: @escaping () -> Void) {
        _model = State(initialValue: ProgressViewModel(services: services))
        self.onBack = onBack
        self.onOpenAllAchievements = onOpenAllAchievements
    }

    public var body: some View {
        ZStack {
            theme.screen.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        WTCircleButton(size: 38, action: onBack) {
                            WTIcons.chevronLeft(color: theme.accent)
                        }
                        .accessibilityIdentifier("progress.back")
                        Spacer()
                    }
                    .padding(.bottom, 20)

                    levelBlock
                    nextRewardBlock
                    tasksBlock
                    prizesBlock
                    achievementsBlock
                }
                .wtScreenTopPadding()
                .padding(.horizontal, WTSpacing.screenSide)
                .padding(.bottom, WTSpacing.screenBottom)
                .wtNoTopOverscroll()
            }
            // Bounce лише коли контент реально не влазить.
            .scrollBounceBehavior(.basedOnSize)

            if model.showLevelRewards { levelRewardsSheet }
            if let item = model.selectedAchievement {
                AchievementDetailModal(item: item, onClose: { model.selectAchievement(nil) })
            }
        }
        .onAppear { model.reload() }
        .wtFeedback(trigger: model.selectedAchievement?.key) { $0 == nil ? nil : .tap }
    }

    // MARK: - Рівень

    private var levelBlock: some View {
        Button { model.present(\.showLevelRewards) } label: {
            VStack(spacing: 10) {
                WTLevelDonut(level: model.level.level, fraction: model.level.fraction)
                Text(model.xpLabel)
                    .font(WTFont.text(13, .bold))
                    .foregroundStyle(theme.textMuted)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(WTPressStyle(scale: 0.97))
        .padding(.bottom, 22)
        .accessibilityIdentifier("progress.level")
    }

    private var nextRewardBlock: some View {
        VStack(alignment: .leading, spacing: 0) {
            WTSectionLabel("НАГОРОДА НА РІВНІ \(model.nextReward.level)")
                .padding(.bottom, 12)
            ForEach(model.nextReward.rewards) { reward in
                HStack(spacing: 14) {
                    Text(reward.emoji).font(.system(size: 30))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(reward.title)
                            .font(WTFont.display(16, .semibold))
                            .foregroundStyle(theme.textPrimary)
                        Text(reward.details)
                            .font(WTFont.text(13, .bold))
                            .foregroundStyle(theme.textMuted)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 10)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(theme.line).frame(height: 1)
                }
            }
        }
        .padding(.bottom, 22)
    }

    // MARK: - Завдання

    private var tasksBlock: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                WTSectionLabel("ЗАВДАННЯ")
                Spacer(minLength: 8)
                // Ховати нема чого, доки жодне завдання не виконане.
                if model.completedQuestCount > 0 {
                    WTSectionAction(
                        model.showCompletedQuests ? "Сховати" : "Виконані · \(model.completedQuestCount)",
                        action: { model.toggleCompletedQuests() }
                    )
                    .accessibilityIdentifier("progress.tasks.toggleCompleted")
                }
            }
            .padding(.bottom, 12)

            WTSectionLabel("СЬОГОДНІ", size: 12, color: theme.accent)
                .padding(.bottom, 8)
            questRows(model.visibleDailyQuests)

            WTSectionLabel("ЦЬОГО ТИЖНЯ", size: 12, color: theme.accent)
                .padding(.top, 16)
                .padding(.bottom, 8)
            questRows(model.visibleWeeklyQuests)
        }
        .padding(.bottom, 22)
    }

    /// Порожній підсписок означає «все виконано» — інших причин не показати квест немає.
    @ViewBuilder
    private func questRows(_ quests: [QuestSnapshot]) -> some View {
        if quests.isEmpty {
            Text("Усі завдання виконані 🎉")
                .font(WTFont.text(14, .bold))
                .foregroundStyle(theme.textMuted)
                .padding(.vertical, 8)
        } else {
            ForEach(quests) { quest in
                WTTaskRow(title: quest.title, progress: quest.progressLabel, isDone: quest.isDone)
            }
        }
    }

    // MARK: - Призи

    @ViewBuilder
    private var prizesBlock: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                WTSectionLabel("ПРИЗИ")
                Text("\(model.prizes.count)")
                    .font(WTFont.text(13, .heavy))
                    .foregroundStyle(theme.accent)
            }
            .padding(.bottom, 12)

            if model.prizes.isEmpty {
                Text("Призи зʼявляться за виконані завдання та нові рівні")
                    .font(WTFont.text(13, .bold))
                    .foregroundStyle(theme.textMuted)
                    .padding(.bottom, 4)
            } else {
                VStack(spacing: 10) {
                    ForEach(model.prizes) { prize in
                        WTPrizeCard(
                            emoji: prize.emoji, title: prize.title, details: prize.details,
                            isActivated: prize.isActivated,
                            onActivate: { model.activate(prize: prize) }
                        )
                    }
                }
            }
        }
        .padding(.bottom, 22)
    }

    // MARK: - Досягнення

    /// Вітрина, а не звіт: ні лічильника «N/M», ні підказки «найближче», ні досягнень
    /// з нульовим прогресом — усе це живе на 2e, куди веде «Всі» (SPEC-ACHIEVEMENTS §4).
    private var achievementsBlock: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                WTSectionLabel("ДОСЯГНЕННЯ", size: 15)
                Spacer()
                // «Всі» лишається навіть при порожній вітрині — це єдиний вхід на 2e.
                WTSectionAction("Всі", action: onOpenAllAchievements)
                    .accessibilityIdentifier("progress.allAchievements")
            }
            .padding(.bottom, 14)

            if model.achievementShowcase.isEmpty {
                Text("Перший запис води відкриє першу нагороду")
                    .font(WTFont.text(13, .bold))
                    .foregroundStyle(theme.textMuted)
                    .accessibilityIdentifier("progress.achievements.hint")
            } else {
                // Неповний другий ряд добивається по лівому краю — `LazyVGrid` так і робить.
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 14) {
                    ForEach(model.achievementShowcase) { item in
                        WTAchievementBadge(
                            emoji: item.emoji,
                            title: item.title,
                            isUnlocked: item.isUnlocked,
                            isNew: item.isNew,
                            fraction: item.fraction,
                            accessibilityValue: item.progressAccessibilityValue,
                            onTap: { model.selectAchievement(item) }
                        )
                        .accessibilityIdentifier("progress.achievements.badge.\(item.key)")
                    }
                }
            }
        }
    }

    // MARK: - Шторки

    private var levelRewardsSheet: some View {
        WTSheet(maxHeightFraction: 0.78, onDismiss: { model.dismiss(\.showLevelRewards) }) {
            VStack(alignment: .leading, spacing: 0) {
                WTSheetTitle(
                    "Нагороди за рівні",
                    subtitle: "Рівень \(model.level.level) · \(model.xpLabel)"
                )
                .padding(.bottom, 14)

                WTProgressBar(fraction: model.level.fraction)
                    .padding(.bottom, 22)

                VStack(alignment: .leading, spacing: 16) {
                    ForEach(model.levelRewards) { reward in
                        WTLevelRewardRow(
                            level: reward.level, emoji: reward.emoji, title: reward.title,
                            details: reward.details, isUnlocked: reward.isUnlocked
                        )
                    }
                }
            }
        }
        .zIndex(10)
    }
}
