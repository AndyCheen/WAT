import Foundation
import Core

/// Об'єм у тексті екранів — у системі людини (WAT-46). Метричні формати місць показу лишились
/// як були (на них стоять тести й e2e), тож кожне місце передає свій, а унції однакові скрізь: «8 oz».
extension VolumeUnit {
    /// Позначення поруч із великим числом («300» + «мл»).
    var symbol: String { isMetric ? "мл" : Self.ounceSymbol }

    /// Голе число в одиницях системи — для великих цифр і чипів, де позначення стоїть окремо.
    func number(_ ml: Int) -> String { "\(units(ml))" }

    /// Порція: «250 мл» / «8 oz».
    func portion(_ ml: Int) -> String { format(ml) { "\($0) мл" } }
}
