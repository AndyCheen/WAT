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
    @FocusState private var typing: Bool

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
                        amountField
                        Text(model.customUnitCaption)
                            .font(WTFont.text(15, .bold))
                            .foregroundStyle(theme.textMuted)
                            .accessibilityIdentifier("custom.unit")
                    }
                    .frame(minWidth: 120)
                    // Уся колонка — ціль для тапу: саме число вузьке, а «мл» під ним — частина того ж поля.
                    .contentShape(Rectangle())
                    .onTapGesture { typing = true }
                    WTStepperButton("+") { model.stepCustom(50) }
                }
                .padding(.bottom, 22)

                HStack(spacing: 8) {
                    ForEach(Array(model.customChips.enumerated()), id: \.offset) { _, value in
                        WTChip("\(value)", isSelected: model.customAmount == value) {
                            model.selectCustom(value)
                        }
                    }
                }
                .padding(.bottom, 24)

                WTPrimaryButton("Додати", isEnabled: model.isCustomAmountValid) { model.confirmCustom() }
                    .accessibilityIdentifier("custom.confirm")
            }
        }
        .onChange(of: typing) { _, now in
            if now { model.beginCustomTyping() } else { model.endCustomTyping() }
        }
        // Степер і чип завершують ввід у моделі — клавіатура ховається слідом.
        .onChange(of: model.customTyped == nil) { _, ended in
            if ended { typing = false }
        }
    }

    /// Тап по числу — цифрова клавіатура (WAT-50). Набране замінює значення, тож поки нічого не набрано,
    /// попереднє видно сірим підказом. Підказ — свій текст, а не `prompt`: той бере колір самого поля й виглядав
    /// би як уже введене число. Прихований він тримає ширину набраного (`customAmount` іде за цифрами), тож
    /// колонка не стрибає. `fixedSize` — інакше поле розтягнулось би й розсунуло степери до країв.
    private var amountField: some View {
        ZStack(alignment: .leading) {
            Text(verbatim: "\(model.customAmount)")
                .foregroundStyle(theme.textMuted)
                .opacity(model.customFieldText.isEmpty ? 1 : 0)
                .accessibilityHidden(true)
            TextField("", text: Binding(get: { model.customFieldText }, set: { model.typeCustom($0) }))
                .foregroundStyle(theme.textPrimary)
                .multilineTextAlignment(.center)
                .wtNumberPad()
                .focused($typing)
                .tint(theme.accent)
                .fixedSize()
                .accessibilityLabel("Скільки води, мл")
                .accessibilityIdentifier("custom.value")
        }
        .font(WTFont.number(52, .semibold))
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
