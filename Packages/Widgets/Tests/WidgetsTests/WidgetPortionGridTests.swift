import XCTest
import Core
@testable import Widgets

/// Фіксовані об'єми кнопки віджета в системі людини (WAT-59).
final class WidgetPortionGridTests: XCTestCase {
    /// Мілілітрова сітка — та сама, що стояла у вікні «Змінити віджет» до WAT-59: ідентифікатори не змінились.
    func testMetricGridIsTheOldOne() {
        let old = Array(stride(from: 50, through: 1000, by: 50)) + Array(stride(from: 1100, through: 2000, by: 100))
        XCTAssertEqual(WidgetPortionGrid.ids(for: .milliliters), old.map { "ml.\($0)" })
    }

    /// Унції — цілі, як кнопки головного: 2…32 кроком 1, далі кроком 2 до межі 2000 мл (66 унц. = 1952 мл).
    func testOunceGridFollowsPresetSteps() {
        let ids = WidgetPortionGrid.ids(for: .usFluidOunces)
        let expected = Array(2...32) + Array(stride(from: 34, through: 66, by: 2))
        XCTAssertEqual(ids, expected.map { "oz.\($0)" })
        XCTAssertEqual(WidgetPortionGrid.milliliters(id: "oz.2"), 59, "1 унц. = 30 мл — нижче межі порції")
        XCTAssertEqual(WidgetPortionGrid.milliliters(id: "oz.66"), 1952)
    }

    /// В унціях жодного повтору й жодного округленого підпису: кожен вузол — своє число унцій.
    func testOunceLabelsAreDistinctAndExact() {
        let oz = VolumeUnit.usFluidOunces
        let labels = WidgetPortionGrid.ids(for: oz).compactMap(WidgetPortionGrid.milliliters(id:)).map(oz.label)
        XCTAssertEqual(Set(labels).count, labels.count)
        XCTAssertEqual(labels.prefix(3), ["2 унц.", "3 унц.", "4 унц."])
        let metric = Array(stride(from: 50, through: 200, by: 50)).map(oz.label)
        XCTAssertEqual(metric, ["2 унц.", "3 унц.", "5 унц.", "7 унц."], "стара сітка в унціях — з пропусками")
    }

    /// Поставлений віджет зберігає ідентифікатор: `ml.N` читається й після переходу на унції, і навпаки.
    func testIdsOfBothSystemsResolve() {
        XCTAssertEqual(WidgetPortionGrid.milliliters(id: "ml.250"), 250)
        XCTAssertEqual(WidgetPortionGrid.milliliters(id: "oz.8"), 237)
        XCTAssertEqual(WidgetPresenter.amount(WidgetPortionGrid.milliliters(id: "ml.250")!, unit: .usFluidOunces), "8 унц.")
        XCTAssertEqual(WidgetPresenter.amount(WidgetPortionGrid.milliliters(id: "oz.8")!), "237 мл")
        XCTAssertNil(WidgetPortionGrid.milliliters(id: "glass"))
        XCTAssertNil(WidgetPortionGrid.milliliters(id: "home.1"))
        XCTAssertNil(WidgetPortionGrid.milliliters(id: "oz.x"))
    }
}
