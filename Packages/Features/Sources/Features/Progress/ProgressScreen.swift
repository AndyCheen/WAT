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
    private let onOpenAllPrizes: () -> Void

    /// - Parameter opensLevelRoad: одразу з вікном «Шлях рівнів» — тост рівня з вибором чи 🎁 і
    ///   `--start-screen level-road`.
    public init(
        services: AppServices,
        opensLevelRoad: Bool = false,
        onBack: @escaping () -> Void,
        onOpenAllAchievements: @escaping () -> Void,
        onOpenAllPrizes: @escaping () -> Void
    ) {
        _model = State(initialValue: ProgressViewModel(services: services, opensLevelRoad: opensLevelRoad))
        self.onBack = onBack
        self.onOpenAllAchievements = onOpenAllAchievements
        self.onOpenAllPrizes = onOpenAllPrizes
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

            // «Шлях рівнів» — вікно на весь екран, а не шторка: виїжджає знизу цілком (SPEC-PRIZES §16.5).
            if model.showLevelRoad, let road = model.levelRoad {
                LevelRoadScreen(model: road, onClose: { model.closeLevelRoad() })
                    .zIndex(11)
                    .transition(.move(edge: .bottom))
            }
            if let item = model.selectedAchievement {
                AchievementDetailModal(item: item, onClose: { model.selectAchievement(nil) })
            }
            if let selection = model.prizes.selected {
                PrizeDetailModal(model: model.prizes, selection: selection)
            }
        }
        .onAppear { model.reload() }
        .onChange(of: model.epoch) { model.reload() }
        .wtFeedback(trigger: model.selectedAchievement?.key) { $0 == nil ? nil : .tap }
        .wtFeedback(trigger: model.prizes.selected?.id) { $0 == nil ? nil : .tap }
        .wtFeedback(trigger: model.prizes.feedback) { $0?.feedback }
    }

    // MARK: - Рівень

    private var levelBlock: some View {
        Button { model.openLevelRoad() } label: {
            VStack(spacing: 10) {
                WTLevelDonut(
                    level: model.level.level, fraction: model.level.fraction,
                    boostBadge: model.prizes.inventory.active.first.map(PrizePresenter.boostBadge),
                    isNew: model.pendingReward != nil
                )
                Text(model.xpLabel)
                    .font(WTFont.text(13, .bold))
                    .foregroundStyle(theme.textMuted)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(WTPressStyle(scale: 0.97))
        .padding(.bottom, 22)
        .accessibilityValue(levelAccessibilityValue)
        .accessibilityHint("Шлях рівнів")
        .accessibilityIdentifier("progress.level")
    }

    private var levelAccessibilityValue: String {
        [
            model.prizes.inventory.active.first.map { "Діє \($0.title.lowercased())" },
            model.pendingReward.map { _ in "Чекає приз" }
        ].compactMap { $0 }.joined(separator: ", ")
    }

    /// Найближча нагорода, а поки вибір чи 🎁 чекають — заклик до них (SPEC-PRIZES §16.6).
    @ViewBuilder
    private var nextRewardBlock: some View {
        if let pending = model.pendingReward, let reward = pending.reward {
            let call = LevelRoadPresenter.pendingCall(reward)
            rewardBlock(
                label: LevelRoadPresenter.pendingLabel(level: pending.level), labelColor: WTColor.orange,
                icon: call.icon, title: call.title, subtitle: call.subtitle, isCallToAction: true
            )
        } else if let next = model.road.nextReward, let reward = next.reward {
            let ahead = LevelRoadPresenter.upcoming(reward)
            rewardBlock(
                label: LevelRoadPresenter.nextLabel(level: next.level), labelColor: nil,
                icon: ahead.icon, title: ahead.title, subtitle: ahead.subtitle, isCallToAction: false
            )
        }
    }

    private func rewardBlock(
        label: String, labelColor: Color?, icon: WTRoadIcon, title: String, subtitle: String, isCallToAction: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            WTSectionLabel(label, color: labelColor)
                .padding(.bottom, 12)
            WTNextRewardRow(icon: icon, title: title, subtitle: subtitle, isCallToAction: isCallToAction) {
                model.openLevelRoad()
            }
            .accessibilityIdentifier("progress.nextReward")
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

    /// Лише отримані й не використані (SPEC-PRIZES §4): діючий буст — статусом у заголовку,
    /// готові — стосами. Без жодного призу блоку немає зовсім, разом із заголовком:
    /// про майбутні вже розповідає «НАГОРОДА НА РІВНІ N».
    @ViewBuilder
    private var prizesBlock: some View {
        let inventory = model.prizes.inventory
        if !inventory.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                // Лічильника в заголовку немає: зі стосами число рядків ≠ числу призів,
                // і поруч із «×2» він читався б як третє число про одне.
                HStack(spacing: 10) {
                    WTSectionLabel("ПРИЗИ")
                    if let active = inventory.active.first {
                        activePrizePill(active)
                    }
                    Spacer(minLength: 8)
                    WTSectionAction("Всі", action: onOpenAllPrizes)
                        .accessibilityIdentifier("progress.allPrizes")
                }
                .padding(.bottom, inventory.ready.isEmpty ? 0 : 8)

                PrizeStackRows(model: model.prizes, identifierPrefix: "progress.prizes.row")
            }
            .padding(.bottom, 22)
        }
    }

    private func activePrizePill(_ prize: RewardSnapshot) -> some View {
        TimelineView(.periodic(from: model.prizes.now, by: 60)) { _ in
            let now = model.prizes.now
            let presenter = model.prizes.presenter
            WTPrizeStatusPill(
                label: presenter.pillLabel(prize),
                remaining: PrizePresenter.shortDuration(prize.remaining(at: now)),
                accessibilityLabel: presenter.activeAccessibilityLabel(prize),
                accessibilityValue: presenter.activeAccessibilityValue(prize, at: now),
                identifier: "progress.prizes.active",
                onTap: { model.prizes.select(.active(prize)) }
            )
        }
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
}
