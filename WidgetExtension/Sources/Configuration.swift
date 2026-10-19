import AppIntents
import Widgets

/// Об'єм кнопки — у налаштуванні самого віджета (рішення від 08.10.2026, SPEC-WIDGETS §4.2).
///
/// «Моя склянка» й «Кнопка N з головного» йдуть за застосунком: змінив там — змінилося й у віджеті.
/// Фіксований об'єм — з тієї ж сітки, що й кнопки головного (`PresetRules`: 50 мл до 1 л, 100 мл від 1 л).
/// Підпис зберігається в самій сутності: віджети iOS кешують сутності з однаковим `id`, і обчислюваний
/// підпис у вікні «Змінити віджет» застарівав би.
struct PortionChoice: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Об'єм"
    static let defaultQuery = PortionChoiceQuery()

    /// `glass`, `home.0`…`home.2` або `ml.250`.
    let id: String
    let title: String

    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(title)") }

    static let glassId = "glass"

    /// Об'єм за поточним знімком. Кнопки головного, якої вже немає, — склянка.
    func milliliters(in snapshot: WidgetSnapshot?) -> Int {
        Self.milliliters(id: id, in: snapshot)
    }

    static func milliliters(id: String, in snapshot: WidgetSnapshot?) -> Int {
        let glass = snapshot?.glassMl ?? 250
        if id.hasPrefix("ml."), let ml = Int(id.dropFirst(3)) { return ml }
        if id.hasPrefix("home."), let index = Int(id.dropFirst(5)), let buttons = snapshot?.homeButtons,
           buttons.indices.contains(index) {
            return buttons[index]
        }
        return glass
    }

    static func make(id: String, snapshot: WidgetSnapshot?) -> PortionChoice {
        let ml = milliliters(id: id, in: snapshot)
        // У системі людини (WAT-58); сітка фіксованих — мілілітрова, як `PresetRules`.
        let amount = WidgetPresenter.amount(ml, unit: snapshot?.volumeUnit ?? .milliliters)
        if id == glassId { return PortionChoice(id: id, title: "Моя склянка · \(amount)") }
        if id.hasPrefix("home."), let index = Int(id.dropFirst(5)) {
            return PortionChoice(id: id, title: "Кнопка \(index + 1) з головного · \(amount)")
        }
        return PortionChoice(id: id, title: amount)
    }

    /// Сітка `PresetRules.stepped`: 50…1000 кроком 50, далі до 2000 кроком 100.
    static let grid: [Int] = Array(stride(from: 50, through: 1000, by: 50)) + Array(stride(from: 1100, through: 2000, by: 100))
}

struct PortionChoiceQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [PortionChoice] {
        let snapshot = WidgetSnapshotStore.shared.read()
        return identifiers.map { PortionChoice.make(id: $0, snapshot: snapshot) }
    }

    func suggestedEntities() async throws -> [PortionChoice] {
        let snapshot = WidgetSnapshotStore.shared.read()
        return Self.suggestedIds(snapshot).map { PortionChoice.make(id: $0, snapshot: snapshot) }
    }

    func defaultResult() async -> PortionChoice? {
        PortionChoice.make(id: PortionChoice.glassId, snapshot: WidgetSnapshotStore.shared.read())
    }

    static func suggestedIds(_ snapshot: WidgetSnapshot?) -> [String] {
        let linked = [PortionChoice.glassId] + (0..<max(1, min(3, snapshot?.homeButtons.count ?? 3))).map { "home.\($0)" }
        return linked + PortionChoice.grid.map { "ml.\($0)" }
    }
}

/// Друга кнопка «Двох кнопок». Окремий тип лише заради свого типового значення: iOS бере типове значення
/// параметра з `defaultResult()` запиту — одне на тип, — і з одним типом на обидві кнопки кожен новий віджет
/// показував дві однакові «Моя склянка» (250 + 250).
struct SecondPortionChoice: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Об'єм"
    static let defaultQuery = SecondPortionChoiceQuery()

    let id: String
    let title: String

    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(title)") }

    func milliliters(in snapshot: WidgetSnapshot?) -> Int { PortionChoice.milliliters(id: id, in: snapshot) }

    static func make(id: String, snapshot: WidgetSnapshot?) -> SecondPortionChoice {
        let choice = PortionChoice.make(id: id, snapshot: snapshot)
        return SecondPortionChoice(id: choice.id, title: choice.title)
    }

    /// Склянка й перша більша кнопка головного (`WidgetSnapshot.pairSecondHomeIndex`).
    static func defaultId(_ snapshot: WidgetSnapshot?) -> String {
        guard let snapshot else { return "home.1" }
        return snapshot.pairSecondHomeIndex.map { "home.\($0)" } ?? PortionChoice.glassId
    }
}

struct SecondPortionChoiceQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [SecondPortionChoice] {
        let snapshot = WidgetSnapshotStore.shared.read()
        return identifiers.map { SecondPortionChoice.make(id: $0, snapshot: snapshot) }
    }

    func suggestedEntities() async throws -> [SecondPortionChoice] {
        let snapshot = WidgetSnapshotStore.shared.read()
        return PortionChoiceQuery.suggestedIds(snapshot).map { SecondPortionChoice.make(id: $0, snapshot: snapshot) }
    }

    func defaultResult() async -> SecondPortionChoice? {
        let snapshot = WidgetSnapshotStore.shared.read()
        return SecondPortionChoice.make(id: SecondPortionChoice.defaultId(snapshot), snapshot: snapshot)
    }
}

/// «Кнопка» — одна (рішення від 12.10.2026): дві — окремий віджет «Дві кнопки». Налаштування «Кнопка 2» тут
/// ніхто б не знайшов, а з типовою склянкою на обох кожен новий віджет мав дві однакові кнопки. Назва `first`
/// лишилась від тих часів — щоб уже поставлені віджети зберегли обраний об'єм.
struct ButtonConfigurationIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Кнопка"
    static let description = IntentDescription("Одна кнопка, що одразу додає порцію.")

    @Parameter(title: "Об'єм")
    var first: PortionChoice?
}

struct ButtonPairConfigurationIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Дві кнопки"
    static let description = IntentDescription("Дві кнопки, що одразу додають порцію.")

    @Parameter(title: "Кнопка 1")
    var first: PortionChoice?

    @Parameter(title: "Кнопка 2")
    var second: SecondPortionChoice?
}

/// Вигляд «Запасу води» — обидва погоджені в макеті (рішення від 08.10.2026).
enum ReserveStyleOption: String, AppEnum {
    case water
    case flask

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Вигляд"
    static let caseDisplayRepresentations: [ReserveStyleOption: DisplayRepresentation] = [
        .water: "Вода",
        .flask: "Колба"
    ]

    var style: ReserveStyle { self == .flask ? .flask : .water }
}

struct ReserveConfigurationIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Запас води"
    static let description = IntentDescription("Скільки води ще вистачить до наступної склянки.")

    @Parameter(title: "Вигляд", default: .water)
    var style: ReserveStyleOption
}
