import SwiftUI
import Core
import Persistence
import DesignSystem

/// Шторка «Розрахунок норми» з макета 4a.
///
/// **Поки не підключена.** За рішенням від 25.08.2026 денна норма змінюється лише
/// в налаштуваннях, а розрахунок за формулою додається пізніше. Верстка збережена
/// повністю — щоб увімкнути, досить показати `GoalCalculatorSheet(model:)`
/// з екрана 4a за прапорцем `model.showCalculator`.
/// Доменна частина (`GoalFormula`, `SpecGoalFormula`, `MockupGoalFormula`) лишається
/// робочою й покрита тестами в пакеті `Hydration`.
struct GoalCalculatorSheet: View {
    @Environment(\.wtTheme) private var theme
    @Bindable var model: StatsViewModel

    var body: some View {
        WTSheet(maxHeightFraction: 0.8, onDismiss: { model.showCalculator = false }) {
            VStack(alignment: .leading, spacing: 0) {
                Text("Розрахунок норми")
                    .font(WTFont.display(22, .semibold))
                    .foregroundStyle(theme.textPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 22)

                WTSectionLabel("ВАГА").padding(.bottom, 10)
                HStack(spacing: 20) {
                    WTStepperButton("−", size: 36) { model.stepWeight(-1) }
                    Text("\(Int(model.weightKg)) кг")
                        .font(WTFont.display(24, .bold))
                        .foregroundStyle(theme.textPrimary)
                        .frame(minWidth: 70)
                    WTStepperButton("+", size: 36) { model.stepWeight(1) }
                }
                .frame(maxWidth: .infinity)
                .padding(.bottom, 18)

                WTSectionLabel("РІВЕНЬ АКТИВНОСТІ").padding(.bottom, 10)
                WTSegmentedTabs(
                    titles: ActivityLevel.allCases.map(\.title),
                    selection: model.activity.rawValue,
                    filled: true,
                    onSelect: { model.activity = ActivityLevel(rawValue: $0) ?? .medium }
                )
                .padding(.bottom, 18)

                WTSectionLabel("КЛІМАТ").padding(.bottom, 10)
                WTSegmentedTabs(
                    titles: ClimateLevel.allCases.map(\.title),
                    selection: model.climate.rawValue,
                    filled: true,
                    onSelect: { model.climate = ClimateLevel(rawValue: $0) ?? .moderate }
                )
                .padding(.bottom, 24)

                VStack(spacing: 6) {
                    WTSectionLabel("РЕКОМЕНДОВАНА НОРМА", size: 12)
                    Text("\(model.calculatedGoal) мл")
                        .font(WTFont.display(30, .bold))
                        .foregroundStyle(theme.textPrimary)
                        .accessibilityIdentifier("calculator.result")
                }
                .frame(maxWidth: .infinity)
                .padding(18)
                .background(theme.chip, in: RoundedRectangle(cornerRadius: WTRadius.button, style: .continuous))
                .padding(.bottom, 18)

                Button { model.applyCalculatedGoal() } label: {
                    Text("Застосувати")
                        .font(WTFont.display(15, .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(theme.accent, in: RoundedRectangle(cornerRadius: WTRadius.control, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("calculator.apply")
            }
        }
    }
}
