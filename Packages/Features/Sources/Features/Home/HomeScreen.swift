import SwiftUI
import Core
import Persistence
import DesignSystem

/// Макет 1a — головний екран.
public struct HomeScreen: View {
    @Environment(\.wtTheme) private var theme
    @State private var model: HomeViewModel
    @Binding private var themeMode: ThemeMode
    private let services: AppServices
    private let onOpenProgress: () -> Void
    private let onOpenStats: () -> Void

    public init(
        services: AppServices,
        themeMode: Binding<ThemeMode>,
        onOpenProgress: @escaping () -> Void,
        onOpenStats: @escaping () -> Void
    ) {
        self.services = services
        _model = State(initialValue: HomeViewModel(services: services))
        _themeMode = themeMode
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
                .padding(.top, WTSpacing.screenTop)
                .padding(.horizontal, WTSpacing.screenSideHome)
                .padding(.bottom, WTSpacing.screenBottom)
            }

            sheets
        }
        .onAppear { model.reload() }
    }

    // MARK: - Шапка

    private var header: some View {
        HStack {
            WTCircleButton(size: 42, action: { model.sheet = .settings }) {
                WTIcons.gear(color: theme.accent)
            }
            .accessibilityIdentifier("home.settings")

            Spacer()

            HStack(spacing: 12) {
                Button { model.sheet = .calendar } label: {
                    HStack(spacing: 4) {
                        ForEach(Array(model.weekDots.enumerated()), id: \.offset) { _, done in
                            Circle()
                                .fill(done ? theme.accent : theme.dotOff)
                                .frame(width: 10, height: 10)
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("home.weekDots")

                Button(action: onOpenProgress) {
                    WTLevelDrop(
                        level: model.level.level,
                        color: theme.accent,
                        hasBadge: model.hasNewAchievements,
                        badgeBorder: theme.screen
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("home.level")
            }
        }
        .padding(.bottom, 22)
    }

    // MARK: - Кільце

    private var ring: some View {
        Button(action: onOpenStats) {
            ZStack {
                WTProgressRing(progress: model.day.progressFraction)
                VStack(spacing: 6) {
                    Text(model.pctLabel)
                        .font(WTFont.number(64, .semibold))
                        .foregroundStyle(theme.textPrimary)
                        .accessibilityIdentifier("home.percent")
                    Text(model.volumeLabel)
                        .font(WTFont.text(17, .bold))
                        .foregroundStyle(theme.textMuted)
                        .accessibilityIdentifier("home.volume")
                }
            }
        }
        .buttonStyle(.plain)
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
            WTQuickButton("Інше", isAccent: true) { model.sheet = .custom }
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
                    SettingsSheet(model: model, themeMode: $themeMode, services: services)
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
