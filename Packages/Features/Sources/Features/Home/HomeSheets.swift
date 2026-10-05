import SwiftUI
import Core
import Persistence
import DesignSystem
import Insights

/// «Скільки води?» — довільний обʼєм (макет 1a). Не «Скільки ви випили?»: застосунок звертається
/// на «ти», а «скільки ти випив» мало б рід — тексти нейтральні (SPEC-NOTIFICATIONS §14.1).
struct CustomAmountSheet: View {
    @Environment(\.wtTheme) private var theme
    @Bindable var model: HomeViewModel

    var body: some View {
        WTSheet(onDismiss: { model.dismissSheet() }) {
            VStack(spacing: 0) {
                Text("Скільки води?")
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
        WTSheet(onDismiss: { model.dismissSheet() }) {
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

/// Налаштування: денна мета, нагадування, ритм дня, вібрація, темна тема (макет 1a).
struct SettingsSheet: View {
    @Environment(\.wtTheme) private var theme
    @Bindable var model: HomeViewModel
    @Binding var themeMode: ThemeMode
    @Binding var hapticsEnabled: Bool
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

    /// Прапорець уже був у моделі профілю, але ним ніхто не керував.
    private var haptics: Binding<Bool> {
        Binding(
            get: { hapticsEnabled },
            set: { newValue in
                hapticsEnabled = newValue
                services.profile.hapticsEnabled = newValue
                services.profiles.save()
            }
        )
    }

    private var dayRhythm: Binding<Bool> {
        Binding(get: { model.dayRhythmEnabled },
                set: { newValue in withAnimation(WTAnimation.sheet) { model.setDayRhythm(newValue) } })
    }

    var body: some View {
        WTSheet(onDismiss: { model.dismissSheet() }) {
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

                // Шторка не вміщує всіх параметрів — рядок веде на екран «Сповіщення» (§15.1).
                WTNavigationRow("Нагадування", value: model.notificationsSummary) {
                    model.openNotificationSettings()
                }
                .accessibilityIdentifier("settings.notifications")

                divider

                // Тимчасово тут: місце перемикача — окреме вікно налаштувань (WAT-15). Не на екрані
                // «Сповіщення»: він стосується й гри, і звітів (SPEC-NOTIFICATIONS §28).
                settingRow("Ритм дня", subtitle: model.dayRhythmEnabled ? "Цілі на ранок, день і вечір" : "Просто норма за день") {
                    WTToggle(isOn: dayRhythm)
                        .accessibilityIdentifier("settings.dayRhythm")
                }
                if model.offersIntervalReminders {
                    WTNoticeBanner("Нагадування «за темпом» теж ділять день на частини",
                                   actionTitle: "Рівні інтервали", identifier: "settings.intervalOffer") {
                        withAnimation(WTAnimation.sheet) { model.switchRemindersToInterval() }
                    }
                    .padding(.top, 4)
                    .transition(.opacity)
                }

                divider

                settingRow("Вібрація") {
                    WTToggle(isOn: haptics)
                        .accessibilityIdentifier("settings.haptics")
                }

                divider

                settingRow("Темна тема") {
                    WTToggle(isOn: isDark)
                        .accessibilityIdentifier("settings.theme")
                }
                    .padding(.bottom, 22)

                WTPrimaryButton("Готово") { model.dismissSheet() }
            }
        }
    }

    private var divider: some View {
        Rectangle().fill(theme.line).frame(height: 1).padding(.vertical, 8)
    }

    private func settingRow<Control: View>(_ title: String, subtitle: String? = nil,
                                           @ViewBuilder control: () -> Control) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(WTFont.text(17, .bold))
                    .foregroundStyle(theme.textPrimary)
                if let subtitle {
                    Text(subtitle)
                        .font(WTFont.text(13, .semibold))
                        .foregroundStyle(theme.textMuted)
                }
            }
            Spacer()
            control()
        }
        .padding(.vertical, 6)
    }
}

/// «Нагадувати, коли забудеш про воду?» — разова шторка після першої порції замість системного
/// запиту на першому запуску: запит без контексту — найчастіша причина відмови (SPEC-NOTIFICATIONS §16.5).
/// Коли з'явиться онбординг 5a–5f, цей крок переїде туди (§21).
struct NotificationPermissionSheet: View {
    @Environment(\.wtTheme) private var theme
    @Bindable var model: HomeViewModel

    var body: some View {
        WTSheet(onDismiss: { model.postponeNotifications() }) {
            VStack(spacing: 0) {
                WTSheetTitle(
                    "Нагадувати, коли забудеш про воду?",
                    subtitle: "Лише коли відстаєш від свого темпу — хто п'є рівномірно, нагадувань не отримує"
                )
                .multilineTextAlignment(.center)
                .padding(.bottom, 24)

                WTPrimaryButton("Увімкнути") { model.enableNotifications() }
                    .accessibilityIdentifier("permission.enable")
                    .padding(.bottom, 4)

                WTSectionAction("Не зараз") { model.postponeNotifications() }
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("permission.later")
            }
        }
    }
}

/// Статистика за 7 днів (макет 1a).
struct WeekStatsSheet: View {
    @Environment(\.wtTheme) private var theme
    @Bindable var model: HomeViewModel

    var body: some View {
        WTSheet(onDismiss: { model.dismissSheet() }) {
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
