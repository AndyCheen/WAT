import SwiftUI
import Core
import Persistence
import DesignSystem

/// Макет 1a — головний екран.
public struct HomeScreen: View {
    @Environment(\.wtTheme) private var theme
    @State private var model: HomeViewModel
    @Binding private var themeMode: ThemeMode
    @Binding private var hapticsEnabled: Bool
    private let services: AppServices
    private let onOpenProgress: () -> Void
    private let onOpenStats: () -> Void

    public init(
        services: AppServices,
        themeMode: Binding<ThemeMode>,
        hapticsEnabled: Binding<Bool>,
        onOpenProgress: @escaping () -> Void,
        onOpenStats: @escaping () -> Void
    ) {
        self.services = services
        _model = State(initialValue: HomeViewModel(services: services))
        _themeMode = themeMode
        _hapticsEnabled = hapticsEnabled
        self.onOpenProgress = onOpenProgress
        self.onOpenStats = onOpenStats
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
            }
            // Bounce лише коли контент реально не влазить — інакше короткий екран
            // (як цей, коли історія порожня) можна відтягнути й відпустити на порожньому місці.
            .scrollBounceBehavior(.basedOnSize)

            toast

            sheets
        }
        .onAppear { model.reload() }
        // Одне джерело правди для вібрації на всі дії екрана.
        .wtFeedback(trigger: model.pulse) { pulse in
            switch pulse?.kind {
            case .added: return .add
            case .goalReached: return .goalReached
            case .levelUp: return .levelUp
            case .removed: return .remove
            case .capped: return .tap
            case nil: return nil
            }
        }
    }

    // MARK: - Шапка

    private var header: some View {
        HStack {
            WTCircleButton(size: 42, action: { model.present(.settings) }) {
                WTIcons.gear(color: theme.accent)
            }
            .accessibilityIdentifier("home.settings")

            Spacer()

            HStack(spacing: 12) {
                Button { model.present(.calendar) } label: {
                    HStack(spacing: 4) {
                        ForEach(Array(model.weekDots.enumerated()), id: \.offset) { _, done in
                            Circle()
                                .fill(done ? theme.accent : theme.dotOff)
                                .frame(width: 10, height: 10)
                        }
                    }
                    // Крапки — 10 pt: без прозорого поля в них важко влучити.
                    .frame(height: 44)
                    .contentShape(Rectangle())
                    .animation(WTAnimation.fade, value: model.weekDots)
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
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 14)
        .padding(.bottom, 24)
    }

    // MARK: - Швидке додавання

    private var quickAdd: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            ForEach(model.quickAmounts, id: \.self) { amount in
                WTQuickButton(Self.amountTitle(amount)) { model.add(amount) }
                    .accessibilityIdentifier("home.add.\(amount)")
            }
            WTQuickButton("Інше", isAccent: true) { model.present(.custom) }
                .accessibilityIdentifier("home.add.custom")
        }
        .padding(.bottom, 28)
    }

    /// Підписи як у макеті 1a: «200 мл», «0.5 л», «1 л».
    static func amountTitle(_ ml: Int) -> String {
        guard ml >= 500 else { return "\(ml) мл" }
        return ml % 1000 == 0 ? "\(ml / 1000) л" : "\(Volume.litersLabel(ml, fractionDigits: 1)) л"
    }

    // MARK: - Завдання

    private var tasks: some View {
        VStack(alignment: .leading, spacing: 0) {
            WTSectionLabel("ЗАВДАННЯ НА СЬОГОДНІ", size: 15)
                .padding(.bottom, 14)
            ForEach(model.quests) { quest in
                WTTaskRow(title: quest.title, progress: quest.progressLabel, isDone: quest.isDone)
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
                        amountLabel: "\(item.amountMl) мл",
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
                    onAction: toast.actionTitle == nil ? nil : { model.undoToast() },
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
        if let sheet = model.sheet {
            Group {
                switch sheet {
                case .custom:
                    CustomAmountSheet(model: model)
                case .calendar:
                    StreakCalendarSheet(model: model)
                case .settings:
                    SettingsSheet(
                        model: model, themeMode: $themeMode,
                        hapticsEnabled: $hapticsEnabled, services: services
                    )
                case .stats:
                    WeekStatsSheet(model: model)
                case .achievements:
                    AchievementsSheetContent(model: model)
                }
            }
            .zIndex(10)
            .transition(.opacity)
        }
    }
}
