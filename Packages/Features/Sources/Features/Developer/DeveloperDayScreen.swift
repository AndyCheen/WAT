import SwiftUI
import Core
import Hydration
import DesignSystem

/// Режим розробника → «Редагувати день» (WAT-68): будь-який з останніх 365 днів чи сьогодні — норма дня, порції з
/// точним часом, заповнення до відсотка норми, заморозка. Системні вибори дати й часу — свідомо: свого компонента для
/// точної хвилини в `DesignSystem` немає, а DEBUG-екрану рідний вигляд важить менше за точність.
struct DeveloperDayScreen: View {
    @Environment(\.wtTheme) private var theme
    @State private var model: DeveloperDayModel
    private let onBack: () -> Void

    init(services: AppServices, onBack: @escaping () -> Void) {
        _model = State(initialValue: DeveloperDayModel(services: services))
        self.onBack = onBack
    }

    var body: some View {
        DeveloperPageLayout(title: "День", onBack: onBack) {
            pickDay
            figures
            fill
            addIntake
            intakes
        }
        .onAppear { model.reload() }
        .onChange(of: model.epoch) { model.reload() }
    }

    // MARK: - Секції

    private var pickDay: some View {
        DeveloperSection(title: "ДЕНЬ") {
            WTSettingRow(model.title, subtitle: model.distance) {
                DatePicker("", selection: $model.selectedDate, in: model.dateRange, displayedComponents: .date)
                    .labelsHidden()
                    .tint(theme.accent)
                    .environment(\.locale, Locale(identifier: "uk_UA"))
                    .accessibilityIdentifier("developer.day.picker")
            }
            DeveloperChips(chips: [
                .init(id: "developer.day.previous", title: "← Попередній") { model.step(-1) },
                model.canGoForward ? .init(id: "developer.day.next", title: "Наступний →") { model.step(1) } : nil,
                .init(id: "developer.day.yesterday", title: "Учора") { model.jump(daysAgo: 1) },
                .init(id: "developer.day.today", title: "Сьогодні") { model.jump(daysAgo: 0) }
            ].compactMap { $0 })
        }
    }

    private var figures: some View {
        DeveloperSection(title: "ПОКАЗНИКИ") {
            WTSettingRow("Норма дня", subtitle: "Лише цей день") {
                WTValueStepper(model.goalLabel, identifier: "developer.day.goal",
                               onDecrement: { model.stepGoal(up: false) },
                               onIncrement: { model.stepGoal(up: true) })
            }
            WTDivider()
            DeveloperValueRow(title: "Зараховано", value: model.volumeLabel, identifier: "developer.day.volume")
            WTDivider()
            DeveloperValueRow(title: "Норму закрито", value: model.day.snapshot.goalMet ? "так" : "ні",
                              identifier: "developer.day.goalMet")
            WTDivider()
            WTSettingRow("Заморожено", subtitle: "Тримає серію без призу") {
                WTToggle(isOn: Binding(get: { model.day.isFrozen }, set: { model.setFrozen($0) }))
                    .accessibilityIdentifier("developer.day.frozen")
            }
        }
    }

    private var fill: some View {
        DeveloperSection(title: "ЗАПОВНИТИ ЗАНОВО") {
            DeveloperNote("Порції дня замінюються новими — рівно від підйому до відбою"
                          + (model.day.isToday ? ", не пізніше, ніж зараз." : "."))
            DeveloperChips(chips: DeveloperDayModel.fillPercents.map { percent in
                .init(id: "developer.day.fill.\(percent)", title: percent == 0 ? "Очистити" : "\(percent) %") {
                    model.fill(percent)
                }
            })
        }
    }

    private var addIntake: some View {
        DeveloperSection(title: "ДОДАТИ ПОРЦІЮ") {
            WTSettingRow("Час") {
                DatePicker("", selection: $model.time, displayedComponents: .hourAndMinute)
                    .labelsHidden()
                    .tint(theme.accent)
                    .environment(\.locale, Locale(identifier: "uk_UA"))
                    .accessibilityIdentifier("developer.day.time")
            }
            WTDivider()
            WTSettingRow("Об'єм") {
                WTValueStepper(model.amountLabel, identifier: "developer.day.amount",
                               onDecrement: { model.stepAmount(up: false) },
                               onIncrement: { model.stepAmount(up: true) })
            }
            DeveloperChips(chips: DeveloperDayModel.amountPresets.map { ml in
                .init(id: "developer.day.amount.\(ml)", title: "\(ml)", isSelected: model.amountMl == ml) {
                    model.amountMl = ml
                }
            })
            WTPrimaryButton("Додати о \(model.timeLabel)", isEnabled: model.canAdd) { model.addIntake() }
                .accessibilityIdentifier("developer.day.add")
                .padding(.vertical, 8)
            if !model.canAdd {
                DeveloperNote("Порцій із майбутнього не буває — зсунь годинник уперед на головній сторінці.")
            }
        }
    }

    private var intakes: some View {
        DeveloperSection(title: "ПОРЦІЇ · \(model.day.intakes.count)") {
            if model.day.intakes.isEmpty {
                DeveloperNote("Порцій за цей день немає.")
            }
            ForEach(Array(model.day.intakes.enumerated()), id: \.element.id) { index, intake in
                if index > 0 { WTDivider() }
                WTSettingRow(model.intakeLabel(intake)) {
                    WTSectionAction("Видалити") { model.remove(intake) }
                        .accessibilityIdentifier("developer.day.remove.\(index)")
                }
            }
        }
    }
}
