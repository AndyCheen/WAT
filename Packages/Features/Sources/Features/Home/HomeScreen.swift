import SwiftUI
import Core
import Persistence
import DesignSystem

/// Макет 1a — головний екран.
public struct HomeScreen: View {
    @Environment(\.wtTheme) private var theme
    @State private var model: HomeViewModel
    private let services: AppServices
    private let onOpenSettings: () -> Void
    private let onOpenProgress: () -> Void
    private let onOpenLevelRoad: () -> Void
    private let onOpenStats: () -> Void
    private let onOpenAchievements: () -> Void
    private let onOpenPrize: (String) -> Void
    /// Головний — верхній екран стека. Пропозиція графіка не з'являється під іншим екраном (WAT-41).
    private let isOnTop: () -> Bool

    public init(
        services: AppServices,
        onOpenSettings: @escaping () -> Void,
        onOpenProgress: @escaping () -> Void,
        onOpenLevelRoad: @escaping () -> Void = {},
        onOpenStats: @escaping () -> Void,
        onOpenAchievements: @escaping () -> Void,
        onOpenPrize: @escaping (String) -> Void = { _ in },
        isOnTop: @escaping () -> Bool = { true }
    ) {
        self.services = services
        _model = State(initialValue: HomeViewModel(services: services))
        self.onOpenSettings = onOpenSettings
        self.onOpenProgress = onOpenProgress
        self.onOpenLevelRoad = onOpenLevelRoad
        self.onOpenStats = onOpenStats
        self.onOpenAchievements = onOpenAchievements
        self.onOpenPrize = onOpenPrize
        self.isOnTop = isOnTop
    }

    public var body: some View {
        ZStack {
            theme.screen.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    ring
                    quickAdd
                    tasks
                    history
                }
                .wtScreenTopPadding()
                .padding(.horizontal, WTSpacing.screenSideHome)
                .padding(.bottom, WTSpacing.screenBottom)
                .wtNoTopOverscroll()
            }
            // Bounce лише коли контент реально не влазить — інакше короткий екран
            // (як цей, коли історія порожня) можна відтягнути й відпустити на порожньому місці.
            .scrollBounceBehavior(.basedOnSize)

            toast

            sheets

            if let item = model.achievementDetail {
                AchievementDetailModal(item: item, onClose: { model.dismissAchievement() })
            }
        }
        .onAppear {
            model.onOpenAchievements = onOpenAchievements
            model.onOpenPrize = onOpenPrize
            model.onOpenLevelRoad = onOpenLevelRoad
            model.reload()
        }
        .onChange(of: model.epoch) { model.reload() }
        // Тап по сповіщенню просить шторку «Інше» з типовою порцією чи картку досягнення.
        .onChange(of: services.router.pendingHomeIntent, initial: true) {
            if let intent = services.router.takeHomeIntent() { model.apply(intent) }
        }
        // Пропозиція графіка — на відкритті застосунку, коли тап по сповіщенню вже встиг дійти (WAT-41).
        .task(id: services.activation) {
            try? await Task.sleep(for: HomeViewModel.scheduleOfferDelay)
            guard !Task.isCancelled else { return }
            model.offerScheduleIfNeeded(activation: services.activation, isHomeOnTop: isOnTop())
        }
        // Одне джерело правди для вібрації на всі дії екрана.
        .wtFeedback(trigger: model.pulse) { pulse in
            switch pulse?.kind {
            case .added: return .add
            case .goalReached: return .goalReached
            case .levelUp: return .levelUp
            case .achievementUnlocked: return .goalReached
            case .removed: return .remove
            case .capped: return .tap
            case nil: return nil
            }
        }
    }

    // MARK: - Шапка

    private var header: some View {
        HStack {
            WTCircleButton(size: 42, action: onOpenSettings) {
                WTIcons.gear(color: theme.accent)
            }
            .accessibilityIdentifier("home.settings")

            Spacer()

            HStack(spacing: 12) {
                Button { model.present(.calendar) } label: {
                    Group {
                        switch model.streakIndicator {
                        case .streak(let days):
                            WTStreakDrop(count: days, numberColor: theme.textPrimary)
                        case .dots(let dots):
                            HStack(spacing: 4) {
                                ForEach(Array(dots.enumerated()), id: \.offset) { _, done in
                                    Circle()
                                        .fill(done ? theme.accent : theme.dotOff)
                                        .frame(width: 10, height: 10)
                                }
                            }
                        }
                    }
                    // Крапки — 10 pt: без прозорого поля в них важко влучити.
                    .frame(height: 44)
                    .contentShape(Rectangle())
                    .animation(WTAnimation.fade, value: model.streakIndicator)
                }
                .buttonStyle(WTPressStyle(scale: 0.94))
                .accessibilityIdentifier("home.weekDots")

                Button(action: onOpenProgress) {
                    WTLevelDrop(
                        level: model.level.level,
                        color: theme.accent,
                        hasBadge: model.hasNewAchievements,
                        badgeBorder: theme.screen
                    )
                }
                .buttonStyle(WTPressStyle())
                .accessibilityIdentifier("home.level")
            }
        }
        .padding(.bottom, 22)
    }

    // MARK: - Кільце

    private var ring: some View {
        VStack(spacing: 10) {
            Button(action: onOpenStats) {
                ZStack {
                    WTProgressRing(progress: model.day.progressFraction)
                    VStack(spacing: 6) {
                        Text(model.pctLabel)
                            .font(WTFont.number(64, .semibold))
                            .foregroundStyle(theme.textPrimary)
                            // Значення змінюється миттєво, морфляться лише гліфи —
                            // без «підрахунку вгору», інакше e2e читали б проміжні числа.
                            .contentTransition(.numericText(value: Double(model.day.completionPct)))
                            .animation(WTAnimation.fade, value: model.day.completionPct)
                            .accessibilityIdentifier("home.percent")
                        Text(model.volumeLabel)
                            .font(WTFont.text(17, .bold))
                            .foregroundStyle(theme.textMuted)
                            .accessibilityIdentifier("home.volume")
                    }
                }
            }
            .buttonStyle(WTPressStyle(scale: 0.98, opacity: 0.85))

            // Стеля 120 % працює з першого дня, але користувач ніколи не бачив,
            // чому відсоток перестав рости.
            if let note = model.cappedNote {
                Text(note)
                    .font(WTFont.text(13, .bold))
                    .foregroundStyle(theme.textMuted)
                    .multilineTextAlignment(.center)
                    .transition(.opacity)
                    .accessibilityIdentifier("home.cappedNote")
            }

            // Капсула частини доби (WAT-40). З приміткою про стелю не зустрічається: стеля —
            // лише після закритої норми, а тоді капсули вже немає. `TimelineView` лише будить
            // екран щохвилини, час модель бере з `Clock`.
            TimelineView(.everyMinute) { _ in
                if let line = model.dayPartLine() {
                    WTDayPartPill(line.content, accessibilityLabel: line.accessibilityLabel)
                        .transition(.opacity)
                        .accessibilityIdentifier("home.dayPart")
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 14)
        .padding(.bottom, 24)
    }

    // MARK: - Швидке додавання

    private var quickAdd: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            // За позицією, а не значенням: дві однакові кнопки — вибір людини (WAT-45), а однакові
            // ідентифікатори в одному `LazyVGrid` злили б комірки.
            ForEach(Array(model.quickAmounts.enumerated()), id: \.offset) { _, amount in
                WTQuickButton(Self.amountTitle(amount, model.volumeUnit)) { model.add(amount) }
                    .accessibilityIdentifier("home.add.\(amount)")
            }
            WTQuickButton("Інше", isAccent: true) { model.openCustom() }
                .accessibilityIdentifier("home.add.custom")
        }
        .padding(.bottom, 28)
    }

    /// Підпис кнопки порції — один для головного й екрана «Кнопки порцій» (WAT-45): до 1 л — мілілітри,
    /// далі літри з тими знаками, що потрібні, — «1 л», «1.05 л», «1.5 л». Не «0.5 л» з макета 1a:
    /// з одним знаком після коми крок 50 мл двічі показував те саме число.
    /// В унціях — «8 унц.» (WAT-46).
    static func amountTitle(_ ml: Int, _ unit: VolumeUnit = .milliliters) -> String {
        guard unit.isMetric else { return unit.portion(ml) }
        guard ml >= 1000 else { return "\(ml) мл" }
        var liters = Volume.litersLabel(ml, fractionDigits: 2)
        while liters.hasSuffix("0") { liters.removeLast() }
        if liters.hasSuffix(".") { liters.removeLast() }
        return "\(liters) л"
    }

    // MARK: - Завдання

    private var tasks: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                WTSectionLabel("ЗАВДАННЯ НА СЬОГОДНІ", size: 15)
                Spacer(minLength: 8)
                // Ховати нема чого, доки жодне завдання не виконане.
                if model.completedQuestCount > 0 {
                    WTSectionAction(
                        model.showCompletedQuests ? "Сховати" : "Виконані · \(model.completedQuestCount)",
                        action: { model.toggleCompletedQuests() }
                    )
                    .accessibilityIdentifier("home.tasks.toggleCompleted")
                }
            }
            .padding(.bottom, 14)

            ForEach(model.visibleQuests) { quest in
                WTTaskRow(title: quest.title, progress: quest.progressLabel, isDone: quest.isDone)
            }

            if model.allQuestsDone && !model.showCompletedQuests {
                Text("Усі завдання виконані 🎉")
                    .font(WTFont.text(14, .bold))
                    .foregroundStyle(theme.textMuted)
                    .padding(.vertical, 8)
            }
        }
        .padding(.bottom, 22)
    }

    // MARK: - Історія

    private var history: some View {
        VStack(alignment: .leading, spacing: 0) {
            WTSectionLabel("ІСТОРІЯ", size: 15)
                .padding(.bottom, 16)

            if model.history.isEmpty {
                Text("Сьогодні ще немає записів")
                    .font(WTFont.text(14, .bold))
                    .foregroundStyle(theme.textMuted)
                    .padding(.vertical, 8)
            } else {
                ForEach(Array(model.history.enumerated()), id: \.element.id) { index, item in
                    WTHistoryRow(
                        amountLabel: model.volumeUnit.portion(item.amountMl),
                        timeLabel: item.timeLabel,
                        isLast: index == model.history.count - 1,
                        isOpen: model.openHistoryId == item.id,
                        onTap: { withAnimation(WTAnimation.fade) { model.toggleHistory(id: item.id) } },
                        onDelete: { model.remove(id: item.id) }
                    )
                }
            }
        }
        .accessibilityIdentifier("home.history")
    }

    // MARK: - Тост

    @ViewBuilder
    private var toast: some View {
        if let toast = model.toast {
            VStack {
                Spacer()
                WTToast(
                    toast.message,
                    actionTitle: toast.actionTitle,
                    onAction: toast.actionTitle == nil ? nil : { model.performToastAction() },
                    onDismiss: { model.dismissToast() }
                )
                // Два видалення поспіль дають однаковий текст — без `id` таймер
                // автозникнення успадкувався б від попереднього тоста.
                .id(toast.id)
                .padding(.bottom, 28)
            }
            .zIndex(8)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    // MARK: - Шторки

    @ViewBuilder
    private var sheets: some View {
        // «Склянка» й «Графік дня» — вікна на весь екран, а не шторки: виїжджають знизу цілком (§7.1, §27).
        if model.sheet == .glass {
            GlassScreen(model: model)
                .zIndex(11)
                .transition(.move(edge: .bottom))
        } else if model.sheet == .schedule {
            ScheduleScreen(model: model)
                .zIndex(11)
                .transition(.move(edge: .bottom))
        } else if let sheet = model.sheet {
            Group {
                switch sheet {
                case .custom:
                    CustomAmountSheet(model: model)
                case .calendar:
                    StreakCalendarSheet(model: model)
                case .stats:
                    WeekStatsSheet(model: model)
                case .permission:
                    NotificationPermissionSheet(model: model)
                case .glass, .schedule:
                    EmptyView()
                }
            }
            .zIndex(10)
            .transition(.opacity)
        }
    }
}
