import SwiftUI
import Core
import Persistence
import DesignSystem

/// Вікно «Склянка» (SPEC-NOTIFICATIONS §7.1, макет Design/Notifications.html, кадри 1–3).
///
/// Відкривається лише тапом по ранковій склянці. Окреме вікно на весь екран, а не шторка
/// (рішення від 05.10.2026): склянка — головний контрол, їй потрібна висота. Показ і закриття —
/// через `HomeViewModel.present(_:)`, як і шторок: тоді спрацьовує той самий шлях порції
/// з тостами розблокувань.
struct GlassScreen: View {
    @Environment(\.wtTheme) private var theme
    @Bindable var model: HomeViewModel

    var body: some View {
        ZStack {
            theme.screen.ignoresSafeArea()
            WTBubbles().ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                switch model.glassStage {
                case .pour: pour
                case .calibrate: calibrate
                }
            }
            .padding(.horizontal, WTSpacing.screenSideHome)
            .padding(.bottom, WTSpacing.screenBottom)

            if let recorded = model.glassRecorded {
                WTRecordedOverlay(amount: model.volumeUnit.number(recorded),
                                  caption: "\(model.volumeUnit.symbol) · \(percentOfGoal(recorded)) % норми",
                                  dayFraction: model.day.progressFraction)
                    .transition(.opacity)
            }
        }
    }

    private var topBar: some View {
        HStack {
            WTCircleButton(action: { model.dismissSheet() }) {
                WTIcons.close(color: theme.accent)
            }
            .accessibilityLabel("Закрити")
            .accessibilityIdentifier("glass.close")
            Spacer()
            Text(model.glassStage == .pour ? "РАНКОВА СКЛЯНКА" : "МОЯ СКЛЯНКА")
                .font(WTFont.text(12, .black))
                .tracking(0.4)
                .foregroundStyle(theme.textMuted)
            Spacer()
            Color.clear.frame(width: 38, height: 38)
        }
        .padding(.bottom, 18)
    }

    // MARK: - Скільки з неї

    private var pour: some View {
        VStack(spacing: 0) {
            // Текст — ранкова склянка з §14.2: вікно відкривається лише з неї.
            Text("Доброго ранку ☀️")
                .font(WTFont.display(28, .bold))
                .foregroundStyle(theme.textPrimary)
            Text("Склянка води після сну — найпростіший старт дня")
                .font(WTFont.text(15, .bold))
                .foregroundStyle(theme.textMuted)
                .multilineTextAlignment(.center)
                .padding(.top, 6)

            value(model.glassAmount, caption: model.glassFractionWord ?? " ")

            HStack(alignment: .bottom, spacing: 10) {
                Color.clear.frame(width: WTGlassTicks.width)
                WTGlass(ml: $model.glassAmount, capacity: model.glassCapacity, step: model.glassDragStepMl,
                        accessibilityValue: model.glassAccessibilityValue)
                WTGlassTicks(marks: model.glassFractions, current: Double(model.glassAmount) / Double(model.glassCapacity))
            }
            .frame(maxHeight: .infinity)
            .padding(.top, 10)

            HStack(spacing: 8) {
                ForEach(model.glassFractions.reversed(), id: \.fraction) { mark in
                    let ml = model.glassMl(for: mark.fraction)
                    WTFractionChip(mark.title, subtitle: model.volumeUnit.portion(ml), isSelected: model.glassAmount == ml) {
                        model.selectGlassFraction(mark.fraction)
                    }
                    .accessibilityIdentifier("glass.chip.\(Int(mark.fraction * 100))")
                }
            }
            .padding(.vertical, 18)

            WTPrimaryButton("Записати \(model.volumeUnit.portion(model.glassAmount))") { model.confirmGlass() }
                .accessibilityIdentifier("glass.record")

            HStack(spacing: 4) {
                Text("Моя склянка: \(model.volumeUnit.portion(model.glassCapacity)) ·")
                    .foregroundStyle(theme.textMuted)
                Button("змінити") { model.recalibrateGlass() }
                    .foregroundStyle(theme.textButton)
                    .font(WTFont.text(13, .black))
                    .accessibilityIdentifier("glass.change")
            }
            .font(WTFont.text(13, .bold))
            .padding(.top, 14)
        }
    }

    // MARK: - Яка в тебе склянка

    private var calibrate: some View {
        VStack(spacing: 0) {
            Text("Скільки в твоїй склянці?")
                .font(WTFont.display(28, .bold))
                .foregroundStyle(theme.textPrimary)
                .multilineTextAlignment(.center)
            Text("Задаєш один раз — далі «склянка» в кнопках і сповіщеннях означатиме саме її")
                .font(WTFont.text(15, .bold))
                .foregroundStyle(theme.textMuted)
                .multilineTextAlignment(.center)
                .padding(.top, 6)

            value(model.calibrationChoice, caption: "≈ \(glassesPerDay) таких склянок на день — твоя норма")

            WTGlassIllustration(fraction: 1, waves: false)
                .scaleEffect(calibrationScale, anchor: .bottom)
                .animation(.spring(response: 0.45, dampingFraction: 0.7), value: model.calibrationChoice)
                .frame(maxHeight: .infinity, alignment: .bottom)
                .padding(.vertical, 10)

            HStack(spacing: 8) {
                ForEach(model.calibrationChoices, id: \.self) { ml in
                    WTFractionChip(model.volumeUnit.number(ml), isSelected: model.calibrationChoice == ml, numeric: true) {
                        model.calibrationChoice = ml
                    }
                    .accessibilityIdentifier("glass.calibrate.\(ml)")
                }
            }
            .padding(.vertical, 18)

            WTPrimaryButton("Готово") { model.confirmCalibration() }
                .accessibilityIdentifier("glass.calibrate.done")

            Text("Інший об'єм — у налаштуваннях сповіщень")
                .font(WTFont.text(13, .bold))
                .foregroundStyle(theme.textMuted)
                .padding(.top, 14)
        }
    }

    // MARK: - Спільне

    private func value(_ ml: Int, caption: String) -> some View {
        VStack(spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(model.volumeUnit.number(ml))
                    .font(WTFont.number(64, .semibold))
                    .foregroundStyle(theme.textPrimary)
                    .contentTransition(.numericText())
                    .accessibilityIdentifier("glass.value")
                Text(model.volumeUnit.symbol)
                    .font(WTFont.text(17, .heavy))
                    .foregroundStyle(theme.textMuted)
            }
            Text(caption)
                .font(WTFont.text(14, .black))
                .foregroundStyle(theme.textButton)
        }
        .padding(.top, 18)
    }

    /// Склянка росте з об'ємом: 200 мл — 62 % висоти, 400 мл — уся.
    private var calibrationScale: CGFloat {
        let choices = model.calibrationChoices
        guard let low = choices.first, let high = choices.last, high > low else { return 1 }
        return 0.62 + 0.38 * CGFloat(model.calibrationChoice - low) / CGFloat(high - low)
    }

    private var glassesPerDay: Int {
        Int((Double(model.day.goalMl) / Double(max(1, model.calibrationChoice))).rounded())
    }

    private func percentOfGoal(_ ml: Int) -> Int {
        Int((Double(ml) / Double(max(1, model.day.goalMl)) * 100).rounded())
    }
}
