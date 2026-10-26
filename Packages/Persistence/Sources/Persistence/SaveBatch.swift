import Foundation
import SwiftData
import Core

/// Пакет збережень — для масових дій: демо-історії й заповнення днів у режимі розробника (WAT-68). Кожна порція
/// зберігає контекст кілька разів (день, XP, завдання, метрики), і на 60 днях це третина часу заповнення. Поки пакет
/// відкритий, `save()` сховищ нічого не пише; закриття зберігає один раз. Читання це не міняє: вибірки SwiftData
/// бачать і ще не збережене.
///
/// Пакет — на один крок (день), не на всю історію: незбережене перебирає кожна вибірка, і пакет на тисячі записів
/// повільніший, ніж без пакета взагалі. Лише для коду, що виконується від початку до кінця сам: дія людини
/// зберігається, як завжди.
@MainActor
public enum SaveBatch {
    private static var depth = 0

    public static var isOpen: Bool { depth > 0 }

    public static func run<Result>(_ context: ModelContext, _ work: () throws -> Result) rethrows -> Result {
        depth += 1
        defer {
            depth -= 1
            if depth == 0 { context.saveLoggingErrors() }
        }
        return try work()
    }
}

extension ModelContext {
    /// Збереження сховищ: у відкритому `SaveBatch` — відкладене до його кінця. Сховища — на головному акторі, як і пакет.
    @MainActor
    func saveLoggingErrors(_ label: String = "save") {
        guard !SaveBatch.isOpen else { return }
        do { try save() } catch { AppLog.persistence.error("\(label): \(error)") }
    }
}
