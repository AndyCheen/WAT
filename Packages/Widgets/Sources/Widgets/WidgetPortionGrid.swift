import Core

/// Фіксовані об'єми кнопки віджета (WAT-59) — та сама сітка, що й у кнопок головного (`VolumeSteps.preset`),
/// у системі людини: 50…1000 мл кроком 50 і далі кроком 100 або 2…32 унц. кроком 1 і далі кроком 2.
///
/// Одиниця — в ідентифікаторі: `ml.250` чи `oz.8`. Ідентифікатор зберігає вже поставлений віджет, тож `ml.N`
/// читається завжди, і в унціях теж — нова система лише міняє, що пропонує вікно «Змінити віджет». Мілілітрова
/// сітка в унціях давала «2 унц.», «3 унц.», «5 унц.»… з повторами: 50 і 59 мл обидва — «2 унц.».
public enum WidgetPortionGrid {
    /// Межі однієї порції — `Intake` (50…2000 мл). `Persistence` розширення не лінкує; збіг тримає тест у `Features`.
    public static let rangeMl = 50...2000

    public static func ids(for unit: VolumeUnit) -> [String] {
        let grid = VolumeSteps.preset(unit)
        var ids: [String] = []
        var units = grid.stepped(0, up: true)
        while unit.milliliters(units: units) <= rangeMl.upperBound {
            // Ціла унція нижче межі (1 унц. = 30 мл) порцією не стане — пропускаємо.
            if unit.milliliters(units: units) >= rangeMl.lowerBound { ids.append(id(units: units, in: unit)) }
            units = grid.stepped(units, up: true)
        }
        return ids
    }

    public static func id(units: Int, in unit: VolumeUnit) -> String {
        "\(prefix(unit)).\(units)"
    }

    /// Об'єм фіксованого ідентифікатора; `nil` — це не фіксований об'єм (`glass`, `home.N`).
    public static func milliliters(id: String) -> Int? {
        for unit in VolumeUnit.allCases {
            let head = prefix(unit) + "."
            guard id.hasPrefix(head), let units = Int(id.dropFirst(head.count)) else { continue }
            return unit.milliliters(units: units)
        }
        return nil
    }

    private static func prefix(_ unit: VolumeUnit) -> String {
        unit.isMetric ? "ml" : "oz"
    }
}
