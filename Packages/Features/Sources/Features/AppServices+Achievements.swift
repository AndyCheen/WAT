import Foundation
import Core
import Metrics
import Gamification

/// Екрани для пасхалки «Як риба у воді» — усі, крім DEBUG (SPEC-ACHIEVEMENTS-CATALOG §4.10).
/// Скільки їх, стільки й ціль пасхалки в каталозі — тест тримає обидва числа разом.
public enum AppScreen: String, CaseIterable, Sendable {
    case home, progress, achievements, prizes, levelRoad, stats, report, settings, notifications, portionButtons, learn
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

/// Що зараз не можна перекривати вікном відкриття (SPEC-ACHIEVEMENTS §8.5). Пауза — за причиною, а не лічильником:
/// повторний початок тієї самої паузи (`onAppear` двічі, шторка змінила шторку) нічого не ламає.
public enum CelebrationPause: Hashable, Sendable {
    case onboarding
    /// Шторка чи повноекранне вікно головного («Склянка», «Графік дня»).
    case homeSheet
    /// Тост головного: «Порцію видалено · Скасувати», новий графік — вікно після нього.
    case homeToast
    case report
    case learnStory
    case levelRoad
    case prizeCard
    case permissionRequest
}

extension AppServices {
    /// Записати дію й, якщо вона щось відкрила, показати вікно відкриття поверх будь-якого екрана.
    ///
    /// - Parameter announce: `false` — коли дія частина ширшої, що показує вікно сама (порція через «Інше»
    ///   на головному): інакше вікно з'явилося б раніше, ніж головний вирішив, чи потрібен тост рівня.
    public func record(_ action: AchievementAction, announce: Bool = true) {
        guard let event = action.event else { return }
        guard metrics.record(MetricEvent(
            name: event.key, value: 1, occurredAt: calendar.now, sourceRef: event.ref
        )) != nil else { return }
        metrics.commit()
        if announce { presentCelebrations(context: .action) }
    }

    // MARK: - Вікно відкриття (WAT-60, SPEC-ACHIEVEMENTS §8)

    /// Показати невідсвятковане одним вікном. Під час паузи вікно чекає її кінця.
    ///
    /// - Parameter level: рівень, піднятий тією самою дією, — рядок на останній сторінці (§8.2). Лише вищий за
    ///   вже святкований: рівень, знятий відкатом і досягнутий знову, удруге не святкується.
    /// - Returns: є що святкувати — вікно показано чи чекає паузи. Головний тоді не показує тост рівня.
    @discardableResult
    public func presentCelebrations(context: Celebration.Context, level: Int? = nil) -> Bool {
        let pending = gamification.achievements.pendingCelebrations(since: celebrationsSince)
        if let shown = celebration {
            guard !Set(shown.keys).isSubset(of: pending) else { return true }
            // Поки вікно було на екрані, порцію скасували (віджет у фоні): зняте відкатом не святкуємо.
            celebration = nil
        }
        guard !pending.isEmpty else { return false }
        guard celebrationPauses.isEmpty else {
            let previous = deferredCelebration
            // Дія важливіша за «поки тебе не було», а рівень з неї не губиться.
            deferredCelebration = (
                context: previous?.context == .action ? .action : context,
                level: [previous?.level, level].compactMap { $0 }.max()
            )
            return true
        }
        deferredCelebration = nil
        let progress = gamification.levelProgress()
        let levelUp = level.flatMap { claimLevelCelebration($0) ? $0 : nil }
            .map { CelebrationPresenter.LevelUp(number: $0, fraction: $0 == progress.level ? progress.fraction : 0) }
        celebration = CelebrationPresenter.make(
            gamification.pendingCelebrations(since: celebrationsSince),
            all: gamification.achievementSnapshots(), context: context, level: levelUp
        )
        return true
    }

    /// Вікно закрили. Позначає відкрите відсвяткованим і побаченим (§8.3); «Обрати приз» / «Відкрити 🎁» ведуть
    /// на 3f з вікном «Шлях рівнів».
    public func dismissCelebration(later: Bool = false) {
        guard let shown = celebration else { return }
        gamification.markCelebrated(keys: shown.keys)
        celebration = nil
        if shown.opensLevelRoad, !later { router.open(path: [.levelRoad]) }
        // Відкрите, поки вікно було на екрані (порція з віджета, поки застосунок у фоні), — наступним вікном.
        presentCelebrations(context: .whileAway)
    }

    public func beginCelebrationPause(_ reason: CelebrationPause) {
        celebrationPauses.insert(reason)
    }

    /// Кінець останньої паузи показує, що назбиралось: і те, що просили показати, і відкрите без прохання —
    /// дочитана історія «Знань» сама вікна не просить.
    public func endCelebrationPause(_ reason: CelebrationPause) {
        guard celebrationPauses.remove(reason) != nil, celebrationPauses.isEmpty else { return }
        let request = deferredCelebration
        presentCelebrations(context: request?.context ?? .action, level: request?.level)
    }

    /// Рівень ще не святкували — тепер святкуємо: тостом чи рядком у вікні (§8.5).
    @discardableResult
    func claimLevelCelebration(_ level: Int) -> Bool {
        guard level > profile.highestCelebratedLevel else { return false }
        profile.highestCelebratedLevel = level
        profiles.save()
        return true
    }

    /// Системний запит дозволу сповіщень — вікно відкриття його не перекриває (§8.5).
    public func requestNotificationAuthorization() async {
        beginCelebrationPause(.permissionRequest)
        await notifications.requestAuthorization()
        endCelebrationPause(.permissionRequest)
    }

    /// Демо-історія й сіди e2e: усе, що вони відкрили, — відсвятковане, як після оновлення (§8.5). Інакше
    /// перший кадр сценарію перекрило б вікно на десятки сторінок.
    func settleCelebrations() {
        profile.celebrationsSince = calendar.now
        profile.highestCelebratedLevel = max(profile.highestCelebratedLevel, gamification.levelProgress().level)
        profiles.save()
        gamification.markCelebrated(keys: gamification.pendingCelebrations(since: .distantPast).map(\.key))
        celebration = nil
        deferredCelebration = nil
    }

    /// Без знімків: перевірка йде на кожну дію, а знімки каталогу потрібні, лише коли вікно справді буде.
    var hasPendingCelebrations: Bool { !gamification.achievements.pendingCelebrations(since: celebrationsSince).isEmpty }

    private var celebrationsSince: Date { profile.celebrationsSince ?? .distantPast }
}
