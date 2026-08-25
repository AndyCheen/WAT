import SwiftUI
import Core
import Persistence
import DesignSystem
import Insights

/// «Скільки ви випили?» — довільний обʼєм (макет 1a).
struct CustomAmountSheet: View {
    @Environment(\.wtTheme) private var theme
    @Bindable var model: HomeViewModel

    var body: some View {
        WTSheet(onDismiss: { model.sheet = nil }) {
            VStack(spacing: 0) {
                Text("Скільки ви випили?")
                    .font(WTFont.display(22, .semibold))
                    .foregroundStyle(theme.textPrimary)
                    .padding(.bottom, 20)

                HStack(spacing: 22) {
                    WTStepperButton("–") { model.stepCustom(-50) }
                    VStack(spacing: 0) {
                        Text("\(model.customAmount)")
                            .font(WTFont.number(52, .semibold))
                            .foregroundStyle(theme.textPrimary)
                            .accessibilityIdentifier("custom.value")
                        Text("мл")
                            .font(WTFont.text(15, .bold))
                            .foregroundStyle(theme.textMuted)
                    }
                    .frame(minWidth: 120)
                    WTStepperButton("+") { model.stepCustom(50) }
                }
                .padding(.bottom, 22)

                HStack(spacing: 8) {
                    ForEach([150, 250, 350, 500], id: \.self) { value in
                        WTChip("\(value)", isSelected: model.customAmount == value) {
                            model.customAmount = value
                        }
                    }
                }
                .padding(.bottom, 24)

                WTPrimaryButton("Додати") { model.confirmCustom() }
                    .accessibilityIdentifier("custom.confirm")
            }
        }
    }
}

/// Серія + календар місяця (макет 1a).
struct StreakCalendarSheet: View {
    @Environment(\.wtTheme) private var theme
    @Bindable var model: HomeViewModel

    var body: some View {
        WTSheet(onDismiss: { model.sheet = nil }) {
            let report = model.monthReport
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    WTDropShape()
                        .fill(WTColor.orange)
                        .frame(width: 20, height: 20)
                    Text("\(model.streak.current) днів поспіль")
                        .font(WTFont.display(24, .semibold))
                        .foregroundStyle(theme.textPrimary)
                }
                .padding(.bottom, 4)

                Text(report.title)
                    .font(WTFont.text(15, .bold))
                    .foregroundStyle(theme.textMuted)
                    .padding(.bottom, 20)

                WTCalendarHeatmap(cells: report.days.map { CalendarCellMapper.cell($0) }, onSelect: { _ in })
            }
        }
    }
}

/// Налаштування: денна мета, нагадування, темна тема (макет 1a).
struct SettingsSheet: View {
    @Environment(\.wtTheme) private var theme
    @Bindable var model: HomeViewModel
    @Binding var themeMode: ThemeMode
    let services: AppServices

    private var isDark: Binding<Bool> {
        Binding(
            get: { themeMode == .dark },
            set: { newValue in
                themeMode = newValue ? .dark : .light
                services.profile.themeMode = themeMode
                services.profiles.save()
            }
        )
    }

    private var notificationsEnabled: Binding<Bool> {
        Binding(
            get: { services.profile.notificationsEnabled },
            set: { services.profile.notificationsEnabled = $0; services.profiles.save() }
        )
    }

    var body: some View {
        WTSheet(onDismiss: { model.sheet = nil }) {
            VStack(spacing: 0) {
                Text("Налаштування")
                    .font(WTFont.display(22, .semibold))
                    .foregroundStyle(theme.textPrimary)
                    .padding(.bottom, 24)

                HStack {
                    Text("Денна мета")
                        .font(WTFont.text(17, .bold))
                        .foregroundStyle(theme.textPrimary)
                    Spacer()
                    HStack(spacing: 14) {
                        WTStepperButton("–", size: 38) { model.changeGoal(by: -250) }
                        Text(model.goalLabel)
                            .font(WTFont.display(19, .semibold))
                            .foregroundStyle(theme.textPrimary)
                            .frame(minWidth: 56)
                            .accessibilityIdentifier("settings.goal")
                        WTStepperButton("+", size: 38) { model.changeGoal(by: 250) }
                    }
                }
                .padding(.vertical, 6)

                divider

                settingRow("Нагадування") {
                    WTToggle(isOn: notificationsEnabled)
                        .accessibilityIdentifier("settings.notifications")
                }

                divider

                settingRow("Темна тема") {
                    WTToggle(isOn: isDark)
                        .accessibilityIdentifier("settings.theme")
                }
                    .padding(.bottom, 22)

                WTPrimaryButton("Готово") { model.sheet = nil }
            }
        }
    }

    private var divider: some View {
        Rectangle().fill(theme.line).frame(height: 1).padding(.vertical, 8)
    }

    private func settingRow<Control: View>(_ title: String, @ViewBuilder control: () -> Control) -> some View {
        HStack {
            Text(title)
                .font(WTFont.text(17, .bold))
                .foregroundStyle(theme.textPrimary)
            Spacer()
            control()
        }
        .padding(.vertical, 6)
    }
}

/// Статистика за 7 днів (макет 1a).
struct WeekStatsSheet: View {
    @Environment(\.wtTheme) private var theme
    @Bindable var model: HomeViewModel

    var body: some View {
        WTSheet(onDismiss: { model.sheet = nil }) {
            let summary = model.weekSummary
            VStack(spacing: 0) {
                WTSheetTitle("Статистика", subtitle: "Останні 7 днів")
                    .padding(.bottom, 22)

                WTBarChart(
                    bars: summary.bars.enumerated().map { index, bar in
                        WTBar(
                            id: bar.key, label: bar.label, value: Double(bar.ml),
                            topLabel: Volume.litersLabel(bar.ml, fractionDigits: 1),
                            isHighlighted: index == summary.bars.count - 1
                        )
                    },
                    maxValue: Double(max(summary.bestMl, model.day.goalMl)),
                    height: 150,
                    barMaxWidth: nil
                )
                .padding(.bottom, 22)

                HStack(spacing: 10) {
                    statCell("Середнє", summary.averageMl)
                    statDivider
                    statCell("Найкращий", summary.bestMl)
                    statDivider
                    statCell("Разом", summary.totalMl)
                }
            }
        }
    }

    private func statCell(_ title: String, _ ml: Int) -> some View {
        VStack(spacing: 2) {
            Text("\(Volume.litersLabel(ml, fractionDigits: 1)) л")
                .font(WTFont.display(20, .semibold))
                .foregroundStyle(theme.textPrimary)
            Text(title)
                .font(WTFont.text(12, .heavy))
                .foregroundStyle(theme.textMuted)
        }
        .frame(maxWidth: .infinity)
    }

    private var statDivider: some View {
        Rectangle().fill(theme.line).frame(width: 1, height: 34)
    }
}

/// Досягнення сіткою 2×N (шторка з макета 1a).
struct AchievementsSheetContent: View {
    @Bindable var model: HomeViewModel

    var body: some View {
        WTSheet(maxHeightFraction: 0.78, onDismiss: { model.sheet = nil }) {
            let items = model.achievements
            VStack(spacing: 0) {
                WTSheetTitle("Досягнення", subtitle: "\(model.unlockedCount) з \(items.count) відкрито")
                    .padding(.bottom, 22)

                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                    ForEach(items) { item in
                        WTAchievementCard(
                            emoji: item.emoji, title: item.title,
                            details: item.details, isUnlocked: item.isUnlocked
                        )
                    }
                }
            }
        }
        .onAppear { model.markAchievementsSeen() }
    }
}

/// Перетворення звіту календаря в комірки дизайн-системи.
enum CalendarCellMapper {
    static func cell(_ day: CalendarDay, selected: DayKey? = nil) -> WTCalendarCell {
        WTCalendarCell(
            id: day.id,
            number: day.number,
            intensity: day.intensity,
            goalMet: day.goalMet,
            isToday: day.isToday,
            isFuture: day.isFuture,
            isSelected: selected != nil && selected == day.dayKey
        )
    }
}
