import SwiftUI
import Core
import Persistence
import DesignSystem

/// «Кнопки порцій» (WAT-45) — окремий екран із «Налаштувань», рідними рядками-степерами, як
/// «Сповіщення». Кількість кнопок фіксована: три з «Інше» — сітка 2×2, чотири чипи — ширина шторки.
public struct PortionButtonsScreen: View {
    @Environment(\.wtTheme) private var theme
    @State private var model: PortionButtonsModel
    private let onBack: () -> Void

    public init(services: AppServices, onBack: @escaping () -> Void) {
        _model = State(initialValue: PortionButtonsModel(services: services))
        self.onBack = onBack
    }

    public var body: some View {
        ZStack {
            theme.screen.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: WTSpacing.cardGap) {
                    WTNavBar(title: "Кнопки порцій", onBack: onBack)
                    section("НА ГОЛОВНОМУ", place: .home, rowTitle: "Кнопка")
                    section("У ВІКНІ «ІНШЕ»", place: .customSheet, rowTitle: "Підказка")
                }
                .wtScreenTopPadding()
                .padding(.horizontal, WTSpacing.screenSide)
                .padding(.bottom, WTSpacing.screenBottom)
                .wtNoTopOverscroll()
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .onAppear { model.reload() }
    }

    private func section(_ title: String, place: PresetPlace, rowTitle: String) -> some View {
        let amounts = model.amounts(place)
        let prefix = place == .home ? "portions.home" : "portions.custom"
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                WTSectionLabel(title)
                Spacer(minLength: 8)
                if !model.isDefault(place) {
                    WTSectionAction("Повернути типові") {
                        withAnimation(WTAnimation.fade) { model.reset(place) }
                    }
                    .accessibilityIdentifier("\(prefix).reset")
                }
            }
            WTCard {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(amounts.enumerated()), id: \.offset) { index, ml in
                        if index > 0 { WTDivider() }
                        WTSettingRow("\(rowTitle) \(index + 1)") {
                            WTValueStepper(HomeScreen.amountTitle(ml, model.volumeUnit),
                                           identifier: "\(prefix).\(index)",
                                           onDecrement: { model.step(place, at: index, up: false) },
                                           onIncrement: { model.step(place, at: index, up: true) })
                        }
                    }
                }
            }
        }
    }
}
