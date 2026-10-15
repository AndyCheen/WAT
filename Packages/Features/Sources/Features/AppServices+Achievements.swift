import Foundation
import Core
import Metrics
import Gamification

/// Екрани для пасхалки «Як риба у воді» — усі, крім DEBUG (SPEC-ACHIEVEMENTS-CATALOG §4.10).
/// Скільки їх, стільки й ціль пасхалки в каталозі — тест тримає обидва числа разом.
public enum AppScreen: String, CaseIterable, Sendable {
    case home, progress, achievements, prizes, levelRoad, stats, report, settings, notifications, portionButtons
}

/// Дія з функцією, яку відмічають «Відкриття» й пасхалки (SPEC-ACHIEVEMENTS-CATALOG §4.7, §4.10).
/// Разові мають сталий ref: повтор шина відкидає, і досягнення не перераховуються даремно.
public enum AchievementAction: Equatable, Sendable {
    /// Порція через «Інше» — ref порції: її скасували, і подія зникла разом з нею.
    case customPortion(UUID)
    case presetsChanged
    case scheduleEdited
    case scheduleOfferAccepted
    case reportFinished(ReportPeriod)
    case pastDayOpened
    case darkTheme
    /// Кожна зміна теми окремо — «Дискотека» рахує, скільки їх за хвилину.
    case themeChanged
    case screenOpened(AppScreen)
    case xpGuideOpened

    var event: (key: MetricKey, ref: UUID?)? {
        switch self {
        case .customPortion(let id): return (.customPortion, id)
        case .presetsChanged: return Self.once(.presetsChanged)
        case .scheduleEdited: return Self.once(.scheduleEdited)
        case .scheduleOfferAccepted: return Self.once(.scheduleOfferAccepted)
        case .reportFinished(let period):
            switch period {
            case .week: return Self.once(.weekReportFinished)
            case .month: return Self.once(.monthReportFinished)
            case .day: return nil
            }
        case .pastDayOpened: return Self.once(.pastDayOpened)
        case .darkTheme: return Self.once(.darkTheme)
        case .themeChanged: return (.themeChanged, nil)
        case .screenOpened(let screen):
            return (.screenOpened, DeterministicID.uuid(from: "\(MetricKey.screenOpened.rawValue):\(screen.rawValue)"))
        case .xpGuideOpened: return Self.once(.xpGuideOpened)
        }
    }

    private static func once(_ key: MetricKey) -> (key: MetricKey, ref: UUID?) {
        (key, DeterministicID.uuid(from: key.rawValue))
    }
}

/// Тост про відкрите поза головним: головний показує свій тост після власних дій, а «Відкриття» й пасхалки
/// трапляються де завгодно — в налаштуваннях, на шляху рівнів, у звіті.
public struct UnlockAnnouncement: Equatable, Identifiable {
    public let id = UUID()
    public let message: String
}

extension AppServices {
    /// Записати дію й, якщо вона щось відкрила, показати тост поверх будь-якого екрана.
    ///
    /// - Parameter announce: `false` — коли дія частина ширшої, що показує свій тост (порція через «Інше»
    ///   на головному): інакше тост головного лишився б без розблокувань.
    public func record(_ action: AchievementAction, announce: Bool = true) {
        guard let event = action.event else { return }
        guard metrics.record(MetricEvent(
            name: event.key, value: 1, occurredAt: calendar.now, sourceRef: event.ref
        )) != nil else { return }
        metrics.commit()
        if announce { announceUnlocks() }
    }

    /// Показати відкрите діями поза головним: призи, шлях рівнів, «Відкриття».
    public func announceUnlocks() {
        let unlocked = gamification.takeRecentUnlocks().achievements
        guard let message = UnlockText.message(unlocked) else { return }
        unlockAnnouncement = UnlockAnnouncement(message: message)
    }

    /// Відкрите не дією, а перерахунком: заднім числом після оновлення чи завершеним учорашнім днем.
    func announceUnlocks(keys: [String]) {
        guard !keys.isEmpty else { return }
        let snapshots = gamification.achievementSnapshots()
        let unlocked = keys.compactMap { key in snapshots.first { $0.key == key && $0.isUnlocked } }
        guard let message = UnlockText.message(unlocked) else { return }
        unlockAnnouncement = UnlockAnnouncement(message: message)
    }

    public func dismissUnlockAnnouncement() {
        unlockAnnouncement = nil
    }
}

/// Текст тоста розблокувань — один для головного й для решти екранів (SPEC-ACHIEVEMENTS §8, §4.10).
enum UnlockText {
    static func message(_ unlocked: [AchievementSnapshot]) -> String? {
        switch unlocked.count {
        case 0:
            return nil
        case 1:
            // Пасхалка має відчуватись інакше, ніж звичайне досягнення.
            return unlocked[0].isEgg
                ? "🥚 Пасхалка: \(unlocked[0].title)"
                : "🏅 Досягнення: \(unlocked[0].title)"
        default:
            return "🏅 Нові досягнення: \(unlocked.count)"
        }
    }
}
