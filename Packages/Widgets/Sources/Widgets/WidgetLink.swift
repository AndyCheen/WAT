import Foundation

/// Куди веде тап по віджету (SPEC-WIDGETS §9.4). URL будується й розбирається лише тут: віджет
/// кладе його в `widgetURL` / `Link`, застосунок розбирає в `.onOpenURL`.
public enum WidgetLink: String, CaseIterable, Sendable {
    /// Головний.
    case home
    /// Головний зі шторкою «Інше» — з останнім своїм об'ємом, як кнопка на головному.
    case custom
    /// Статистика (4a).
    case stats
    /// «Прогрес» (3f).
    case progress

    public static let scheme = "watertracker"

    public var url: URL {
        // Рядок складається з констант — `URL(string:)` тут не може повернути `nil`.
        URL(string: "\(Self.scheme)://\(rawValue)")!
    }

    public init?(url: URL) {
        guard url.scheme == Self.scheme, let host = url.host(), let link = WidgetLink(rawValue: host) else { return nil }
        self = link
    }
}
