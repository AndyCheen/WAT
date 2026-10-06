import Foundation
import SwiftUI
import Observation
import Core
import DesignSystem
import Gamification

/// Модель вікна «Шлях рівнів» (SPEC-PRIZES §16): знімок шляху, вибір, таємний приз, довідник XP,
/// повтор прогресу. Кешує знімок і перечитує його в `reload()`, як решта ViewModel-ів.
@MainActor
@Observable
public final class LevelRoadModel {
    /// Розкриття таємного призу, що зараз грає.
    struct Reveal: Equatable {
        let level: Int
        let kicker: String
        let outcome: WTMysteryReveal.Outcome
    }

    private let services: AppServices
    private let defaults: UserDefaults

    public private(set) var road: LevelRoadSnapshot
    private(set) var rows: [LevelRoadRow]
    /// Обраний варіант у вузлі «вибір» — до «Забрати».
    private(set) var selection: (level: Int, key: String)?
    /// Вибір щойно забрано — картка показує «✓ у твоїх призах», доки не згорнеться.
    private(set) var claimedLevel: Int?
    private(set) var reveal: Reveal?
    private(set) var showsGuide = false
    /// Позиція лінії рейки в рівнях від першого рядка — анімується для повтору прогресу (§16.15).
    private(set) var railPosition: Double
    private(set) var feedback: PrizeFeedback?

    /// Скільки картка вибору тримає підтвердження, перш ніж згорнутися в «Обрано з двох».
    var claimHold: Duration = .milliseconds(1400)
    private var collapseTask: Task<Void, Never>?

    static let seenTotalXpKey = "levelRoad.seenTotalXp"

    public init(services: AppServices, defaults: UserDefaults = .standard) {
        self.services = services
        self.defaults = defaults
        let road = services.gamification.levelRoad()
        self.road = road
        self.rows = LevelRoadPresenter.rows(road)
        self.railPosition = Self.position(of: road.progress)
    }

    public func reload() {
        road = services.gamification.levelRoad()
        rows = LevelRoadPresenter.rows(road)
        railPosition = Self.position(of: road.progress)
    }

    var focusLevel: Int { road.focusLevel }

    var headerTitle: String { "Рівень \(road.progress.level)" }
    var headerXp: String { "\(road.progress.xpIntoLevel) / \(road.progress.xpForNextLevel)" }
    var headerXpSuffix: String { "XP до рівня \(road.progress.nextLevel)" }
    var hereValue: String { "\(road.progress.xpIntoLevel) / \(road.progress.xpForNextLevel)" }

    // MARK: - Повтор прогресу (§16.15)

    /// Лінія доростає від місця, де була на минулому відкритті. Перше відкриття й незмінний XP —
    /// без анімації; позначка оновлюється щоразу.
    func replayProgress(reduceMotion: Bool) {
        let total = road.progress.totalXp
        let seen = defaults.object(forKey: Self.seenTotalXpKey) as? Int
        defaults.set(total, forKey: Self.seenTotalXpKey)
        guard !reduceMotion, let seen, seen < total else { return }
        let from = LevelCalculator.progress(totalXp: seen, curve: services.gamification.xp.curve)
        railPosition = Self.position(of: from)
        withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.8).delay(0.45)) {
            railPosition = Self.position(of: road.progress)
        }
    }

    /// Перший рядок — рівень 1, тож поточний рівень N з часткою f — це N − 1 + f.
    static func position(of progress: LevelProgress) -> Double {
        Double(progress.level - 1) + progress.fraction
    }

    // MARK: - Вибір (§16.3)

    func selectedKey(level: Int) -> String? {
        selection?.level == level ? selection?.key : nil
    }

    func select(level: Int, key: String) {
        guard claimedLevel == nil else { return }
        withAnimation(WTAnimation.fade) { selection = (level, key) }
        sendFeedback(.toggle)
    }

    /// Вибір остаточний: підтвердження в самій картці, потім вона згортається в «Обрано з двох».
    func claim(level: Int) {
        guard let key = selectedKey(level: level), claimedLevel == nil,
              services.gamification.claimChoice(level: level, key: key) else { return }
        services.touch()
        sendFeedback(.goalReached)
        withAnimation(WTAnimation.toast) { claimedLevel = level }
        collapseTask?.cancel()
        collapseTask = Task { [weak self, claimHold] in
            try? await Task.sleep(for: claimHold)
            guard !Task.isCancelled, let self else { return }
            withAnimation(WTAnimation.sheet) {
                self.claimedLevel = nil
                self.selection = nil
                self.reload()
            }
        }
    }

    // MARK: - Таємний приз (§16.2)

    func open(level: Int) {
        guard reveal == nil, case .mystery(let pool)? = LevelRoadCatalog.node(forLevel: level),
              let grants = services.gamification.openMystery(level: level) else { return }
        services.touch()
        withAnimation(WTAnimation.fade) {
            reveal = Reveal(
                level: level, kicker: LevelRoadPresenter.revealKicker(level: level, pool: pool),
                outcome: LevelRoadPresenter.revealOutcome(grants)
            )
        }
    }

    func finishReveal() {
        withAnimation(WTAnimation.fade) {
            reveal = nil
            reload()
        }
    }

    // MARK: - Довідник «Звідки XP» (§16.14)

    var guideRows: [WTXPGuideRow] {
        LevelRoadPresenter.guideRows(rules: services.gamification.xp.rules, dayRhythm: services.profile.dayRhythmEnabled)
    }

    func setGuide(_ shown: Bool) {
        withAnimation(WTAnimation.fade) { showsGuide = shown }
        if shown { sendFeedback(.tap) }
    }

    private func sendFeedback(_ value: WTFeedback) {
        feedback = PrizeFeedback(serial: (feedback?.serial ?? 0) + 1, feedback: value)
    }
}
