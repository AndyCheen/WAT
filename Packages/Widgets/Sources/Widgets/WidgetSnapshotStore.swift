import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif

/// Де лежить знімок: файл у спільному контейнері App Group (SPEC-WIDGETS §9.1).
///
/// Атомарний запис — віджет ніколи не прочитає половину файла. Знімок крихітний (~2 КБ), тож
/// кешувати його в пам'яті розширення нема сенсу: кожен таймлайн читає свіжий.
public struct WidgetSnapshotStore: Sendable {
    public static let appGroup = "group.com.watertracker.app"
    static let fileName = "widget-snapshot.json"

    public let url: URL?

    public init(url: URL?) {
        self.url = url
    }

    /// Файл у контейнері App Group; `nil`, якщо групу не підписано (SPM-тести, збірка без entitlements).
    public static var shared: WidgetSnapshotStore {
        let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)
        return WidgetSnapshotStore(url: container?.appendingPathComponent(fileName))
    }

    public func read() -> WidgetSnapshot? {
        guard let url, let data = try? Data(contentsOf: url),
              let snapshot = try? Self.decoder.decode(WidgetSnapshot.self, from: data),
              snapshot.version == WidgetSnapshot.currentVersion else { return nil }
        return snapshot
    }

    @discardableResult
    public func write(_ snapshot: WidgetSnapshot) -> Bool {
        guard let url, let data = try? Self.encoder.encode(snapshot) else { return false }
        do {
            try data.write(to: url, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return decoder
    }()
}

/// Перезавантаження таймлайнів. Протокол — заради тестів: у SPM-процесі WidgetKit нема кому слухати.
@MainActor
public protocol WidgetReloading: AnyObject {
    func reloadAll()
}

#if canImport(WidgetKit)
@MainActor
public final class WidgetCenterReloader: WidgetReloading {
    public init() {}

    public func reloadAll() {
        WidgetCenter.shared.reloadAllTimelines()
        #if os(iOS)
        if #available(iOS 18.0, *) {
            ControlCenter.shared.reloadAllControls()
        }
        #endif
    }
}
#endif
