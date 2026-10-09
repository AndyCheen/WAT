import WidgetKit
import SwiftUI
import AppIntents
import Widgets

/// «Вода +250 мл» — у Пункті керування, на екрані блокування й на кнопці дії (iOS 18, SPEC-WIDGETS §6).
/// Об'єм — так само, як у віджета «Кнопка»; дія — той самий інтент у процесі застосунку.
@available(iOS 18.0, *)
struct WaterControl: ControlWidget {
    static let kind = "com.watertracker.control.add"

    var body: some ControlWidgetConfiguration {
        AppIntentControlConfiguration(kind: Self.kind, provider: WaterControlProvider()) { value in
            ControlWidgetButton(action: AddWaterWidgetIntent(ml: value)) {
                Label("+\(WidgetPresenter.amount(value))", systemImage: "drop.fill")
            }
        }
        .displayName("Додати воду")
        .description("Порція одним натисканням, без відкриття застосунку.")
    }
}

@available(iOS 18.0, *)
struct WaterControlConfiguration: ControlConfigurationIntent {
    static let title: LocalizedStringResource = "Додати воду"

    @Parameter(title: "Об'єм")
    var portion: PortionChoice?
}

@available(iOS 18.0, *)
struct WaterControlProvider: AppIntentControlValueProvider {
    func previewValue(configuration: WaterControlConfiguration) -> Int {
        configuration.portion?.milliliters(in: nil) ?? 250
    }

    func currentValue(configuration: WaterControlConfiguration) async throws -> Int {
        let snapshot = WidgetSnapshotStore.shared.read()
        return configuration.portion?.milliliters(in: snapshot) ?? snapshot?.glassMl ?? 250
    }
}
