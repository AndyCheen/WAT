import Foundation

/// Українська плюралізація: «1 день», «2 дні», «5 днів».
///
/// До перенесення рядків у `.xcstrings` числа з іменниками йдуть лише через цю функцію,
/// а не через конкатенацію (SPEC-NOTIFICATIONS §14.1).
public enum Plural {
    /// Форма слова для числа `n`, без самого числа.
    public static func uk(_ n: Int, one: String, few: String, many: String) -> String {
        let value = abs(n)
        let lastTwo = value % 100
        let last = value % 10
        if last == 1 && lastTwo != 11 { return one }
        if (2...4).contains(last) && !(12...14).contains(lastTwo) { return few }
        return many
    }

    /// «12 днів» — число й узгоджене слово.
    public static func days(_ n: Int) -> String {
        "\(n) \(uk(n, one: "день", few: "дні", many: "днів"))"
    }
}
