import Foundation
import Core
import Persistence

/// План → запити в центр сповіщень і дифф із тим, що вже чекає доставки (§16.2, п. 4).
///
/// Ідентифікатори детерміновані, тож перепланування на кожну дію знімає лише зайве й додає
/// нове чи змінене, а незмінене не чіпає.
public enum NotificationScheduler {
    /// Відлуння додається поза планом і живе недовго — дифф його не знімає.
    static func isManaged(_ identifier: String) -> Bool {
        identifier.hasPrefix("wt.") && !identifier.hasPrefix("wt.echo.")
    }

    public static func requests(for plan: NotificationPlan, sound: NotificationSoundSpec, calendar: Calendar) -> [ScheduledRequest] {
        plan.items.map { item in
            let trigger = ScheduledRequest.Trigger.calendar(
                components(for: item.fireAt, floating: item.isFloating, calendar: calendar),
                floating: item.isFloating
            )
            var userInfo = [
                UserInfoKey.type: item.type.key,
                UserInfoKey.slot: item.slot,
                UserInfoKey.day: item.dayKey.rawValue,
                UserInfoKey.route: item.tapRoute.encoded,
                UserInfoKey.glassMl: String(plan.glassMl),
                UserInfoKey.portionMl: String(plan.typicalPortionMl)
            ]
            let fingerprint = Self.fingerprint(item: item, sound: sound, trigger: trigger, userInfo: userInfo)
            userInfo[UserInfoKey.fingerprint] = fingerprint
            return ScheduledRequest(
                identifier: item.id, title: item.title, body: item.body, categoryId: item.category?.rawValue,
                sound: sound, trigger: trigger, fireAt: item.fireAt, userInfo: userInfo, fingerprint: fingerprint
            )
        }
    }

    /// Знімає зайве й додає нове чи змінене. Повертає, скільки запитів додано й знято.
    @MainActor
    @discardableResult
    public static func apply(_ desired: [ScheduledRequest], to center: NotificationCenterProtocol) async -> (added: Int, removed: Int) {
        let pending = await center.pendingRequests().filter { isManaged($0.identifier) }
        let wanted = Dictionary(desired.map { ($0.identifier, $0) }, uniquingKeysWith: { first, _ in first })
        let stale = pending.map(\.identifier).filter { wanted[$0] == nil }
        center.removePending(identifiers: stale)

        let current = Dictionary(pending.map { ($0.identifier, $0.fingerprint) }, uniquingKeysWith: { first, _ in first })
        var added = 0
        // Запит із тим самим ідентифікатором iOS заміняє — окремо знімати не треба.
        for request in desired where current[request.identifier] != request.fingerprint {
            await center.add(request)
            added += 1
        }
        return (added, stale.count)
    }

    /// Ранкова склянка, вечір, порятунок і повернення — «плаваючі» компоненти без поясу: після
    /// перельоту 08:00 лишається 08:00 місцевого. Нагадування — абсолютний момент (§16.2).
    static func components(for date: Date, floating: Bool, calendar: Calendar) -> DateComponents {
        var parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        parts.timeZone = floating ? nil : calendar.timeZone
        return parts
    }

    private static func fingerprint(item: PlannedNotification, sound: NotificationSoundSpec,
                                    trigger: ScheduledRequest.Trigger, userInfo: [String: String]) -> String {
        let info = userInfo.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: "&")
        let raw = [item.id, item.title, item.body, item.category?.rawValue ?? "-", "\(sound)", "\(trigger)", info]
            .joined(separator: "|")
        return String(StableHash.fnv1a(raw), radix: 16)
    }
}

/// «Булькання / Системний / Без звуку» (§14.4). Окремо від `soundEnabled`, що стосується звуків
/// у застосунку: можна вимкнути булькання при додаванні й лишити чутні нагадування.
public enum SoundResolver {
    /// Короткий тихий звук ≤ 1 с у бандлі. Ассет — окрема задача; до його появи — системний.
    public static let bubbleAsset = "drop.caf"

    public static func resolve(_ sound: NotificationSound, bubbleAvailable: Bool) -> NotificationSoundSpec {
        switch sound {
        case .silent: return .none
        case .system: return .systemDefault
        case .bubble: return bubbleAvailable ? .named(bubbleAsset) : .systemDefault
        }
    }
}
