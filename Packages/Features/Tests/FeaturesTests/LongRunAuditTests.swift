import XCTest
import Foundation
import SwiftData
import Core
import Persistence
import Gamification
import Notifications
@testable import Features

// Аудит 60 днів (WAT-67): різні типи людей через `HomeViewModel` і справжні планувальник, пікери й сповіщення на
// `FixedClock` — норма, XP, рівні, досягнення, призи, успішність завдань, навантаження сповіщеннями. Не перевірка, а
// вимірювання для калібрування; звичайний прогін пакетів його пропускає.
//
//     WT_AUDIT=1 WT_AUDIT_OUT=<тека> swift test --package-path Packages/Features --parallel --filter LongRunAuditTests
//
// Звіт — `long-<персона>.txt` у `WT_AUDIT_OUT`. Прогін персони — 1–3 хв.

// MARK: - Випадковість

struct SimRNG {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
    mutating func unit() -> Double { Double(next() >> 11) / Double(UInt64(1) << 53) }
    mutating func int(_ range: ClosedRange<Int>) -> Int { range.lowerBound + Int(next() % UInt64(range.count)) }
    mutating func chance(_ p: Double) -> Bool { unit() < p }
    mutating func pick<T>(_ items: [T]) -> T { items[int(0...(items.count - 1))] }
}

// MARK: - Персони

struct LongRunPersona {
    struct Portion {
        /// Хвилина від півночі дня людини; ≥ 1440 — уже після півночі.
        var minute: Int
        var ml: Int
        var custom = false
        var undo = false
    }

    let key: String
    let title: String
    var days = 60
    var seed: UInt64
    var plan: (_ day: Int, _ weekday: Int, _ rng: inout SimRNG) -> [Portion]
    var configure: @MainActor (AppServices) -> Void = { _ in }
    var authorization: NotificationAuthorization = .authorized
    var usesFreezes = true
    var usesBoosts = true
    var reactive = false
    var reactiveResponseRate = 0.8
    /// Між власними порціями — «+склянка» на таку частку сповіщень.
    var hybridResponseRate = 0.0
    var acceptsSchedule = false
}

enum LongRunPersonas {
    static func hm(_ h: Int, _ m: Int) -> Int { h * 60 + m }

    /// Рівно, 8 × 250, норма щодня.
    static let ideal = LongRunPersona(key: "ideal", title: "Ідеальний: 8×250 рівномірно, норма щодня", seed: 1) { _, _, rng in
        let base = [hm(8, 10), hm(9, 50), hm(11, 20), hm(12, 50), hm(14, 30), hm(16, 0), hm(17, 40), hm(19, 20)]
        return base.map { .init(minute: $0 + rng.int(-12...12), ml: 250) }
    }

    /// Звичайна людина: кнопки 200/500, іноді «Інше» 300; будні ≈ 75 % норми, вихідні ≈ 50 %, пізніший підйом.
    static let typical = LongRunPersona(key: "typical", title: "Типовий: будні ~75 % норми, вихідні ~50 %", seed: 2) { _, weekday, rng in
        let weekend = weekday >= 6
        let start = weekend ? hm(10, 0) : hm(8, 15)
        let closes = rng.chance(weekend ? 0.5 : 0.75)
        let target = closes ? rng.int(2000...2400) : rng.int(1100...1850)
        var portions: [LongRunPersona.Portion] = []
        var total = 0
        var minute = start + rng.int(0...30)
        while total < target, minute < hm(22, 30) {
            let custom = rng.chance(0.12)
            let ml = custom ? 300 : rng.pick([200, 200, 500])
            portions.append(.init(minute: minute, ml: ml, custom: custom))
            total += ml
            minute += rng.int(70...160)
        }
        if rng.chance(0.06), let last = portions.last {
            portions.append(.init(minute: last.minute + 2, ml: 500, undo: true))
        }
        return portions
    }

    /// 2–3 великі порції (500/1000), без системи; норма ≈ 45 %.
    static let gulper = LongRunPersona(key: "gulper", title: "Великими ковтками: 2–4 порції по 500–1000", seed: 3) { _, _, rng in
        let count = rng.int(2...4)
        var minutes = (0..<count).map { _ in rng.int(hm(9, 30)...hm(21, 30)) }.sorted()
        for i in 1..<minutes.count where minutes[i] - minutes[i - 1] < 45 { minutes[i] = minutes[i - 1] + 45 }
        return minutes.map { .init(minute: $0, ml: rng.pick([500, 500, 1000])) }
    }

    /// Активний 4–6 днів, потім зникає на 2–5 днів.
    static let onOff: LongRunPersona = {
        var rng = SimRNG(state: 44)
        var active = Set<Int>()
        var day = 1
        while day <= 60 {
            let on = rng.int(4...6)
            for d in day..<(day + on) { active.insert(d) }
            day += on + rng.int(2...5)
        }
        return LongRunPersona(key: "onoff", title: "З перервами: 4–6 днів активно, 2–5 зникає", seed: 4) { d, weekday, rng in
            guard active.contains(d) else { return [] }
            return typical.plan(d, weekday, &rng)
        }
    }()

    /// Спортсмен: п'є 3200–3800 мл (стеля 120 % норми 2000 — 2400).
    static let heavy = LongRunPersona(key: "heavy", title: "Перепиває: 3200–3800 мл при нормі 2000", seed: 5) { _, _, rng in
        var portions: [LongRunPersona.Portion] = []
        var minute = hm(7, 0) + rng.int(0...20)
        var total = 0
        let target = rng.int(3200...3800)
        while total < target {
            let ml = rng.pick([500, 1000, 500])
            portions.append(.init(minute: minute, ml: ml))
            total += ml
            minute += rng.int(60...110)
        }
        return portions
    }

    /// Не відкриває застосунок сам: п'є лише з дії «+склянка» на сповіщенні (80 % відгуку).
    static let reactive = LongRunPersona(key: "reactive", title: "Реагує на сповіщення: «+склянка» на 80 % з них", seed: 6,
                                         plan: { _, _, _ in [] }, reactive: true)

    /// Без «Ритму дня» й без дозволу на сповіщення, решта — як «Типовий».
    static let plain = LongRunPersona(key: "plain", title: "Без ритму дня й без сповіщень (типовий патерн)", seed: 7,
                                      plan: typical.plan,
                                      configure: { $0.profile.dayRhythmEnabled = false },
                                      authorization: .denied)

    /// Сова при типовому розкладі 08–22: п'є з 11:00 до ~01:30, частина порцій — після півночі.
    static let owl = LongRunPersona(key: "owl", title: "Сова: 11:00–01:30 при розкладі 08:00–22:00", seed: 8) { _, _, rng in
        var portions: [LongRunPersona.Portion] = []
        var minute = hm(11, 0) + rng.int(0...40)
        var total = 0
        let target = rng.int(1900...2300)
        while total < target {
            let ml = rng.pick([200, 500, 500])
            portions.append(.init(minute: minute, ml: ml))
            total += ml
            minute += rng.int(90...150)
        }
        return portions
    }

    /// Згасання: перші 10 днів — норма щодня, далі ймовірність відкрити застосунок падає з 1 до ~0,2 і порцій менше.
    static let fading = LongRunPersona(key: "fading", title: "Згасання: старт на 100 %, далі інтерес падає", seed: 9) { d, weekday, rng in
        if d <= 10 { return ideal.plan(d, weekday, &rng).enumerated().compactMap { $0.offset % 4 == 3 ? nil : LongRunPersona.Portion(minute: $0.element.minute, ml: $0.element.ml + 85) } }
        let p = max(0.2, 1 - Double(d - 10) / 50 * 0.8)
        guard rng.chance(p) else { return [] }
        let count = rng.int(1...4)
        return (0..<count).map { i in .init(minute: hm(9, 0) + i * rng.int(120...200), ml: rng.pick([200, 500])) }
    }

    /// Реагує на кожне сповіщення.
    static let reactive100 = LongRunPersona(key: "reactive100", title: "Реагує на 100 % сповіщень «+склянкою»", seed: 10,
                                            plan: { _, _, _ in [] }, reactive: true, reactiveResponseRate: 1)

    /// Найреалістичніший: п'є сам, як «Недобирає», і відповідає на 40 % сповіщень.
    static let hybrid = LongRunPersona(key: "hybrid", title: "Гібрид: п'є сам ~1500 мл і відповідає на 40 % сповіщень", seed: 11,
                                       plan: { _, weekday, rng in
        let start = weekday >= 6 ? hm(10, 0) : hm(8, 20)
        var portions: [LongRunPersona.Portion] = []
        var minute = start + rng.int(0...30)
        var total = 0
        let target = rng.int(1200...1800)
        while total < target, minute < hm(21, 30) {
            let ml = rng.pick([200, 300, 500])
            portions.append(.init(minute: minute, ml: ml))
            total += ml
            minute += rng.int(100...190)
        }
        return portions
    }, hybridResponseRate: 0.4)

    static let all: [LongRunPersona] = [ideal, typical, gulper, onOff, heavy, reactive, plain, owl, fading]
}

// MARK: - Прогін

@MainActor
final class LongRunSimulation {
    let persona: LongRunPersona
    private var rng: SimRNG
    private(set) var services: AppServices!
    private var clock: FixedClock!
    private var center: InMemoryNotificationCenter!
    private var model: HomeViewModel!

    static let zone = TimeZone(identifier: "Europe/Kyiv")!
    /// Пн 5 жовтня 2026: усередині — перехід на зимовий час (25.10), повні 26.10 і 24.11, зміна місяців.
    static let start: Date = {
        var c = DateComponents(); c.year = 2026; c.month = 10; c.day = 5; c.hour = 0
        return calendar.date(from: c)!
    }()
    static let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian); c.timeZone = zone; return c
    }()

    struct DayTally {
        var celebrations: [String] = []
        var toasts: [String] = []
        var sheets: [String] = []
        var haptics: [String] = []
        var actions = 0
        var streak: Int?
        var freezesUsed = 0
        var boostsUsed = 0
        var notes: [String] = []
        var loudMoments: [String] = []
    }

    private(set) var tallies: [DayTally]

    init(_ persona: LongRunPersona) {
        self.persona = persona
        self.rng = SimRNG(state: persona.seed)
        self.tallies = Array(repeating: DayTally(), count: persona.days + 2)
    }

    static func date(day: Int, minute: Int) -> Date {
        let base = calendar.date(byAdding: .day, value: day - 1 + minute / 1440, to: start)!
        let m = minute % 1440
        return calendar.date(bySettingHour: m / 60, minute: m % 60, second: 0, of: base)!
    }

    static func weekday(_ day: Int) -> Int { (day - 1) % 7 + 1 }

    func run() async {
        let authorized = persona.authorization == .authorized
        center = InMemoryNotificationCenter(status: authorized ? .notDetermined : persona.authorization,
                                            grantsOnRequest: authorized)
        clock = FixedClock(now: Self.date(day: 1, minute: 8 * 60 + 5), timeZone: Self.zone)
        services = AppServices(container: Database.makeInMemoryContainer(), clock: clock, notificationCenter: center)
        services.bootstrap()
        services.handleBecameActive()
        model = HomeViewModel(services: services)
        services.profile.notificationsEnabled = authorized
        services.profile.glassConfirmed = true
        services.profile.onboardingState = .completed
        persona.configure(services)
        services.profiles.save()
        if authorized { _ = await services.notifications.requestAuthorization() }
        services.touch()
        await services.notifications.rescheduleNow()
        model.reload()
        _ = drainCelebrations(day: 1)
        _ = drainToasts(day: 1)
        await services.handleEnteredBackground()

        for day in 1...persona.days {
            if persona.reactive {
                await runReactiveDay(day)
                harvestLogs()
                continue
            }
            var portions = persona.plan(day, Self.weekday(day), &rng).sorted { $0.minute < $1.minute }
            for i in portions.indices.dropFirst() where portions[i].minute <= portions[i - 1].minute {
                portions[i].minute = portions[i - 1].minute + 1
            }
            let plannedMl = portions.filter { !$0.undo }.reduce(0) { $0 + $1.ml }
            for (index, portion) in portions.enumerated() {
                await respondToNotifications(day: day, until: Self.date(day: day, minute: portion.minute))
                await open(at: Self.date(day: day, minute: portion.minute), day: day)
                var signals: [String] = []
                if index == 0 { signals += morningRoutine(day: day, plannedMl: plannedMl) }
                signals += perform(portion, day: day)
                if index == portions.count - 1 { signals += eveningCheck(day: day) }
                tallies[day].streak = services.gamification.streakSummary().current
                if signals.count >= 3 {
                    tallies[day].loudMoments.append("\(Self.clock(portion.minute)) +\(portion.ml): " + signals.joined(separator: "; "))
                }
                await services.handleEnteredBackground()
            }
            await respondToNotifications(day: day, until: Self.date(day: day + 1, minute: 0))
            harvestLogs()
        }
        await open(at: Self.date(day: persona.days + 1, minute: 7 * 60), day: persona.days + 1)
        await services.handleEnteredBackground()
        harvestLogs()
    }

    /// Гібрид: між власними порціями відповідає «+склянкою» на частину сповіщень (застосунок у фоні).
    private func respondToNotifications(day: Int, until limit: Date) async {
        guard persona.hybridResponseRate > 0 else { return }
        for _ in 0..<12 {
            let now = clock.now
            guard let next = services.notifications.lastPlan.items
                .filter({ $0.fireAt > now && $0.fireAt < limit && Self.actionable.contains($0.type) })
                .min(by: { $0.fireAt < $1.fireAt }) else { return }
            guard decide(next.id, rate: persona.hybridResponseRate) else {
                clock.set(next.fireAt.addingTimeInterval(30))
                continue
            }
            clock.set(next.fireAt.addingTimeInterval(120))
            await services.handleNotificationResponse(responseInfo(next))
            tallies[day].actions += 1
            tallies[day].notes.append("+склянка з \(next.type) \(Self.timeText(next.fireAt))")
        }
    }

    /// Як iOS: відповідь несе `userInfo` доставленого запиту — там і об'єм дії («Закрити норму»).
    private func responseInfo(_ item: PlannedNotification) -> NotificationResponseInfo {
        let info = center.scheduled.first { $0.identifier == item.id }?.userInfo ?? [:]
        return NotificationResponseInfo(identifier: item.id, action: .addGlass, userInfo: info)
    }

    /// Відповісти чи ні — від ідентифікатора сповіщення, а не з послідовного генератора: інакше будь-яка зміна часу
    /// сповіщень зсуває всі подальші рішення, і порівняння двох версій міряє шум.
    private func decide(_ identifier: String, rate: Double) -> Bool {
        Double(StableHash.fnv1a("\(persona.seed)|\(identifier)") % 10_000) / 10_000 < rate
    }

    struct HarvestedLog {
        let dayKey: String
        let type: NotificationType
        var fireAt = Date.distantPast
        var slot = ""
        var quick = false
        let suppressed: Bool
        let responded: Bool
    }
    /// Журнал застосунок чистить через `logRetentionDays` — знімаємо його щодня.
    private(set) var harvested: [String: HarvestedLog] = [:]

    private func harvestLogs() {
        let now = clock.now
        for log in NotificationStore(context: services.container.mainContext)
            .logs(firingFrom: now.addingTimeInterval(-3 * 86_400), to: now)
        where log.cancelledAt == nil && log.fireAt <= now {
            harvested[log.identifier] = HarvestedLog(
                dayKey: log.dayKey, type: NotificationType(rawValue: log.typeRaw) ?? .reminder,
                fireAt: log.fireAt, slot: log.slot,
                quick: log.openedAt != nil || log.responseRaw == NotificationResponseKind.snooze.rawValue
                    || (log.respondedAt.map { $0.timeIntervalSince(log.fireAt) <= 15 * 60 } ?? false),
                suppressed: log.suppressedAt != nil,
                responded: log.responseRaw != NotificationResponseKind.none.rawValue
            )
        }
    }

    private static func clock(_ minute: Int) -> String { String(format: "%02d:%02d", (minute / 60) % 24, minute % 60) }

    private func open(at date: Date, day: Int) async {
        clock.set(date)
        services.handleBecameActive()
        await services.notifications.rescheduleNow()
        model.reload()
        tallies[day].actions += 0
        _ = drainCelebrations(day: day, prefix: "на відкритті")
        _ = drainToasts(day: day)
        // Як `HomeScreen.task(id: activation)`: пропозиція графіка на чистому відкритті.
        model.offerScheduleIfNeeded(activation: services.activation, isHomeOnTop: true)
        if case .schedule? = model.sheet, let content = model.scheduleContent {
            let before = services.profile.weekSchedule
            if persona.acceptsSchedule { model.acceptSchedule() } else { model.declineSchedule() }
            tallies[day].sheets.append("графік дня: \(content.title) → \(persona.acceptsSchedule ? "так" : "ні"); було \(before.weekday.wakeMinutes / 60):\(before.weekday.wakeMinutes % 60)–\(before.weekday.sleepMinutes / 60), стало \(services.profile.weekSchedule.weekday.wakeMinutes / 60):\(services.profile.weekSchedule.weekday.wakeMinutes % 60)–\(services.profile.weekSchedule.weekday.sleepMinutes / 60)")
            _ = drainToasts(day: day)
            _ = drainCelebrations(day: day, prefix: "після графіка")
        }
    }

    /// Ранок: заморозка, якщо вчора серію обірвано, і буст, якщо день планується повним.
    private func morningRoutine(day: Int, plannedMl: Int) -> [String] {
        var signals: [String] = []
        let game = services.gamification
        if persona.usesFreezes, case .yesterday(savedStreak: let saved) = game.freezeTarget(), saved >= 2,
           let freeze = game.prizes().first(where: { $0.key == RewardCatalog.freezeKey && $0.state == .ready }) {
            if game.useFreeze(prizeId: freeze.id) {
                services.touch()
                tallies[day].freezesUsed += 1
                signals.append("🧊 заморозка рятує серію \(saved)")
                services.presentCelebrations(context: .action)
                signals += drainCelebrations(day: day, prefix: "після заморозки")
            }
        }
        if persona.usesBoosts, plannedMl >= services.hydration.todaySnapshot().goalMl,
           game.xp.boostMultiplier(at: clock.now) == 1,
           let boost = game.prizes().first(where: { RewardCatalog.boostKeys.contains($0.key) && $0.state == .ready }) {
            if game.activateBoost(prizeId: boost.id) {
                services.touch()
                tallies[day].boostsUsed += 1
                signals.append("\(boost.emoji) буст")
                services.presentCelebrations(context: .action)
                signals += drainCelebrations(day: day, prefix: "після буста")
            }
        }
        return signals
    }

    private func perform(_ portion: LongRunPersona.Portion, day: Int) -> [String] {
        var signals: [String] = []
        tallies[day].actions += 1
        if portion.custom {
            model.openCustom()
            model.customAmount = portion.ml
            model.confirmCustom()
        } else {
            model.add(portion.ml)
        }
        if let pulse = model.pulse, let text = Self.haptic(pulse.kind) {
            tallies[day].haptics.append(text)
            signals.append("вібрація: \(text)")
        }
        signals += drainCelebrations(day: day)
        signals += drainToasts(day: day)
        if portion.undo, let id = model.history.first(where: { $0.amountMl == portion.ml })?.id {
            model.remove(id: id)
            signals.append("видалено")
            signals += drainToasts(day: day)
            signals += drainCelebrations(day: day)
        }
        return signals
    }

    private static func haptic(_ kind: HomePulse.Kind) -> String? {
        switch kind {
        case .levelUp(let level): return "рівень \(level)"
        case .goalReached: return "норма"
        case .celebration: return "вікно"
        case .gift: return "подарунок"
        case .questDone: return "завдання"
        case .added, .removed, .capped: return nil
        }
    }

    private func drainCelebrations(day: Int, prefix: String = "вікно") -> [String] {
        var signals: [String] = []
        for _ in 0..<6 {
            guard let shown = services.celebration else { break }
            var text = shown.pages.map { "\($0.emoji) \($0.title)" }.joined(separator: ", ")
            if let level = shown.level { text += " + рівень \(level.number)" }
            tallies[min(day, tallies.count - 1)].celebrations.append(text)
            signals.append("\(prefix): \(text)")
            services.dismissCelebration(later: true)
            model.celebrationDidClose()
        }
        return signals
    }

    private func drainToasts(day: Int) -> [String] {
        var signals: [String] = []
        while let toast = model.toast {
            tallies[min(day, tallies.count - 1)].toasts.append(toast.message)
            signals.append("тост: \(toast.message)")
            model.dismissToast()
        }
        if let sheet = model.sheet {
            tallies[min(day, tallies.count - 1)].sheets.append("\(sheet)")
            signals.append("шторка: \(sheet)")
            model.dismissSheet()
        }
        return signals
    }

    private func eveningCheck(day: Int) -> [String] {
        var signals: [String] = []
        let road = services.gamification.levelRoad()
        for node in road.pending {
            switch node.reward {
            case .choice(let grants)?:
                // Розумна людина: заморозку, якщо її немає, інакше буст.
                let hasFreeze = services.gamification.prizes().contains { $0.key == RewardCatalog.freezeKey && $0.state == .ready }
                let pick = grants.first { hasFreeze ? $0.key != RewardCatalog.freezeKey : $0.key == RewardCatalog.freezeKey } ?? grants[0]
                _ = services.gamification.claimChoice(level: node.level, key: pick.key)
                signals.append("вибір рівня \(node.level): \(pick.key)")
            case .mystery?:
                let grants = services.gamification.openMystery(level: node.level) ?? []
                signals.append("🎁 рівня \(node.level): \(grants.map { "\($0.key)×\($0.count)" })")
            default:
                break
            }
            services.touch()
            services.presentCelebrations(context: .action)
            signals += drainCelebrations(day: day, prefix: "вікно шляху")
        }
        services.gamification.markAchievementsSeen()
        services.gamification.markPrizesSeen()
        return signals
    }

    // MARK: - Реактивна людина

    private static let actionable: Set<NotificationType> = [.reminder, .morning, .checkpoint, .challenge, .evening, .comeback]

    private func runReactiveDay(_ day: Int) async {
        let dayEnd = Self.date(day: day + 1, minute: 0)
        var actions = 0
        var lookedInEvening = false
        while actions < 16 {
            let now = clock.now
            let next = services.notifications.lastPlan.items
                .filter { $0.fireAt > now && $0.fireAt < dayEnd && Self.actionable.contains($0.type) }
                .min { $0.fireAt < $1.fireAt }
            // Увечері раз зазирнути в застосунок — забрати призи шляху й побачити вікна.
            let eveningLook = Self.date(day: day, minute: 21 * 60 + 40)
            if !lookedInEvening, now < eveningLook, next.map({ $0.fireAt > eveningLook }) ?? true {
                lookedInEvening = true
                await open(at: eveningLook, day: day)
                _ = eveningCheck(day: day)
                tallies[day].streak = services.gamification.streakSummary().current
                await services.handleEnteredBackground()
                continue
            }
            guard let next else { break }
            if !decide(next.id, rate: persona.reactiveResponseRate) {
                clock.set(next.fireAt.addingTimeInterval(60))
                tallies[day].notes.append("проігнорував \(next.type) \(Self.timeText(next.fireAt))")
                continue
            }
            clock.set(next.fireAt.addingTimeInterval(120))
            await services.handleNotificationResponse(responseInfo(next))
            tallies[day].actions += 1
            tallies[day].notes.append("+склянка з \(next.type) \(Self.timeText(next.fireAt))")
            actions += 1
        }
        tallies[day].streak = services.gamification.streakSummary().current
    }

    static func timeText(_ date: Date) -> String {
        let p = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", p.hour ?? 0, p.minute ?? 0)
    }

    // MARK: - Звіт

    func report() -> String {
        let context = services.container.mainContext
        let store = GamificationStore(context: context)
        let cal = services.calendar
        let days = persona.days
        let dayKeys = (1...days).map { cal.dayKey(for: Self.date(day: $0, minute: 12 * 60)).rawValue }
        let indexByKey = Dictionary(uniqueKeysWithValues: dayKeys.enumerated().map { ($1, $0 + 1) })

        // XP
        var xpByDay = Array(repeating: 0, count: days + 2)
        var xpByReason: [String: Int] = [:]
        var xpByWeekReason: [Int: [String: Int]] = [:]
        for entry in store.xpEntries(dayKey: nil) where entry.revertedAt == nil {
            let index = indexByKey[entry.dayKey] ?? (days + 1)
            xpByDay[index] += entry.effectiveAmount
            xpByReason["\(entry.reason)", default: 0] += entry.effectiveAmount
            xpByWeekReason[(index - 1) / 7 + 1, default: [:]]["\(entry.reason)", default: 0] += entry.effectiveAmount
        }
        let curve = LinearLevelCurve()
        var cumulative = 0
        var levelByDay = Array(repeating: 1, count: days + 2)
        for d in 0...(days + 1) {
            cumulative += xpByDay[d]
            levelByDay[d] = LevelCalculator.progress(totalXp: cumulative, curve: curve).level
        }

        // Досягнення
        var achByDay: [Int: [String]] = [:]
        var unlockedTotal = 0
        for progress in store.allAchievementProgress() {
            guard let at = progress.unlockedAt, let def = AchievementCatalog.definition(progress.defKey) else { continue }
            unlockedTotal += 1
            let index = indexByKey[cal.dayKey(for: at).rawValue] ?? 0
            achByDay[index, default: []].append("\(def.emoji)\(def.title)[\(def.difficulty)]")
        }

        // Призи
        let items = store.rewardItems()
        var prizeEarned: [String: Int] = [:]
        var prizeBySource: [String: Int] = [:]
        var prizeState: [String: Int] = [:]
        var prizeByDay: [Int: [String]] = [:]
        for item in items {
            prizeEarned[item.defKey, default: 0] += 1
            prizeBySource["\(item.source)", default: 0] += 1
            prizeState["\(item.defKey):\(item.state)", default: 0] += 1
            let index = indexByKey[cal.dayKey(for: item.acquiredAt).rawValue] ?? 0
            prizeByDay[index, default: []].append(RewardCatalog.definition(item.defKey)?.emoji ?? item.defKey)
        }

        // Завдання
        let quests = store.quests(scope: nil, periodKey: nil)
        var questStats: [String: (issued: Int, done: Int, expired: Int, cancelled: Int, active: Int, xp: Int)] = [:]
        var questsByDay: [Int: (issued: Int, done: Int)] = [:]
        for quest in quests {
            var s = questStats[quest.defKey] ?? (0, 0, 0, 0, 0, 0)
            s.issued += 1
            switch QuestState(rawValue: quest.stateRaw) ?? .active {
            case .completed, .claimed: s.done += 1; s.xp += quest.rewardXp
            case .expired: s.expired += 1
            case .cancelled: s.cancelled += 1
            case .active: s.active += 1
            }
            questStats[quest.defKey] = s
            if quest.periodKey.count == 10 || quest.periodKey.hasPrefix("adhoc:") {
                let key = quest.periodKey.hasPrefix("adhoc:") ? String(quest.periodKey.dropFirst(6)) : quest.periodKey
                if let index = indexByKey[key] {
                    var q = questsByDay[index] ?? (0, 0)
                    q.issued += 1
                    if quest.stateRaw == QuestState.completed.rawValue || quest.stateRaw == QuestState.claimed.rawValue { q.done += 1 }
                    questsByDay[index] = q
                }
            }
        }

        // Сповіщення
        var notifByDay: [Int: (active: Int, passive: Int, suppressed: Int)] = [:]
        var notifByType: [String: Int] = [:]
        var responded = 0
        for log in harvested.values {
            let index = indexByKey[log.dayKey] ?? 0
            var n = notifByDay[index] ?? (0, 0, 0)
            if log.suppressed { n.suppressed += 1 }
            else if log.type == .report { n.passive += 1 }
            else { n.active += 1 }
            notifByDay[index] = n
            if !log.suppressed { notifByType["\(log.type)", default: 0] += 1 }
            if log.responded { responded += 1 }
        }
        let notMetDays = (1...days).filter { d in
            let s = services.hydration.snapshot(for: DayKey(rawValue: dayKeys[d - 1])); return s.totalMl > 0 && s.totalMl < s.goalMl
        }
        let activeOnNotMet = notMetDays.reduce(0) { $0 + (notifByDay[$1]?.active ?? 0) }
        let atCap = (1...days).filter { (notifByDay[$0]?.active ?? 0) >= 8 }.count

        // Дні
        var lines: [String] = ["===== \(persona.title) [\(persona.key)] =====", ""]
        var normDays = 0
        var totalMl = 0
        var activeDays = 0
        var rows: [String] = []
        rows.append("д | дата | дн | мл | норма | ✓ | серія | XP дня | рів. | досягн. | вікна | тости | шторки | сповіщ. акт/пас/прих | завд. вид/вик | призи | 🧊/⚡")
        for d in 1...days {
            let key = dayKeys[d - 1]
            let snap = services.hydration.snapshot(for: DayKey(rawValue: key))
            let met = snap.totalMl >= snap.goalMl
            if met { normDays += 1 }
            if snap.totalMl > 0 { activeDays += 1 }
            totalMl += snap.totalMl
            let t = tallies[d]
            let n = notifByDay[d] ?? (0, 0, 0)
            let q = questsByDay[d] ?? (0, 0)
            rows.append([
                "\(d)", String(key.dropFirst(5)), ["Пн", "Вт", "Ср", "Чт", "Пт", "Сб", "Нд"][Self.weekday(d) - 1],
                "\(snap.totalMl)", "\(snap.goalMl)", met ? "✓" : (snap.totalMl == 0 ? "·" : "✗"),
                t.streak.map(String.init) ?? "-", "\(xpByDay[d])", "\(levelByDay[d])",
                "\(achByDay[d]?.count ?? 0)", "\(t.celebrations.count)", "\(t.toasts.count)", "\(t.sheets.count)",
                "\(n.active)/\(n.passive)/\(n.suppressed)", "\(q.issued)/\(q.done)",
                (prizeByDay[d] ?? []).joined(), "\(t.freezesUsed)/\(t.boostsUsed)"
            ].joined(separator: " | "))
        }

        let summary = services.gamification.streakSummary()
        let level = services.gamification.levelProgress()
        lines.append("ПІДСУМОК")
        lines.append("  активних днів: \(activeDays)/\(days), норма: \(normDays) (\(normDays * 100 / days) %), середнє мл в активний день: \(activeDays > 0 ? totalMl / activeDays : 0)")
        lines.append("  рівень: \(level.level) (\(level.totalXp) XP), XP/день сер.: \(level.totalXp / days), серія зараз \(summary.current), найдовша \(summary.longest)")
        let checkpoints = [1, 7, 14, 30, 60].filter { $0 <= days }
        lines.append("  рівень на днях \(checkpoints): \(checkpoints.map { levelByDay[$0] })")
        var achCum: [Int] = []
        for c in checkpoints { achCum.append((0...c).reduce(0) { $0 + (achByDay[$1]?.count ?? 0) }) }
        lines.append("  досягнень відкрито: \(unlockedTotal) з \(AchievementCatalog.active.count); накопичено на днях \(checkpoints): \(achCum)")
        lines.append("  призи отримано: \(prizeEarned.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }); за джерелом: \(prizeBySource.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" })")
        lines.append("  стан призів: \(prizeState.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" })")
        lines.append("  заморозок використано: \(tallies.reduce(0) { $0 + $1.freezesUsed }), бустів: \(tallies.reduce(0) { $0 + $1.boostsUsed })")
        let totalXp = max(1, xpByReason.values.reduce(0, +))
        lines.append("  XP за джерелами: " + xpByReason.sorted { $0.value > $1.value }.map { "\($0.key)=\($0.value) (\($0.value * 100 / totalXp)%)" }.joined(separator: ", "))
        lines.append("  вікна відкриття: \(tallies.reduce(0) { $0 + $1.celebrations.count }), тости: \(tallies.reduce(0) { $0 + $1.toasts.count }), шторки: \(tallies.reduce(0) { $0 + $1.sheets.count })")
        let activeNotifs = notifByDay.values.reduce(0) { $0 + $1.active }
        let maxActive = notifByDay.values.map(\.active).max() ?? 0
        lines.append("  сповіщення: активних \(activeNotifs) (\(String(format: "%.1f", Double(activeNotifs) / Double(days)))/день, макс. \(maxActive)), тихих \(notifByDay.values.reduce(0) { $0 + $1.passive }), приховано \(notifByDay.values.reduce(0) { $0 + $1.suppressed }), з відповіддю \(responded)")
        lines.append("  у дні без норми (\(notMetDays.count)): \(notMetDays.isEmpty ? 0 : activeOnNotMet / notMetDays.count)/день; днів із ≥ 8 активних: \(atCap)")
        lines.append("  за типами: " + notifByType.sorted { $0.value > $1.value }.map { "\($0.key)=\($0.value)" }.joined(separator: ", "))
        lines.append("")
        lines.append("ТИЖНІ: тиждень | норма днів | XP | рівень на кінець | досягнень | XP за джерелами")
        for w in 1...((days + 6) / 7) {
            let range = ((w - 1) * 7 + 1)...min(w * 7, days)
            let norm = range.filter { d in
                let s = services.hydration.snapshot(for: DayKey(rawValue: dayKeys[d - 1])); return s.totalMl >= s.goalMl
            }.count
            let xp = range.reduce(0) { $0 + xpByDay[$1] }
            let ach = range.reduce(0) { $0 + (achByDay[$1]?.count ?? 0) }
            let reasons = (xpByWeekReason[w] ?? [:]).sorted { $0.value > $1.value }.map { "\($0.key)=\($0.value)" }.joined(separator: ", ")
            lines.append("  т\(w) | \(norm)/\(range.count) | \(xp) | \(levelByDay[range.upperBound]) | \(ach) | \(reasons)")
        }
        lines.append("")
        lines.append("ЗАВДАННЯ: ключ | видано | виконано | прострочено | скасовано | активні | XP")
        for (key, s) in questStats.sorted(by: { $0.key < $1.key }) {
            let rate = s.issued > 0 ? s.done * 100 / s.issued : 0
            lines.append("  \(key) | \(s.issued) | \(s.done) (\(rate)%) | \(s.expired) | \(s.cancelled) | \(s.active) | \(s.xp)")
        }
        // Завдання з успіхом нижче 25 % — кожен інстанс: день, параметри, результат і що людина зробила того дня.
        let weak = Set(questStats.filter { $0.value.issued >= 5 && $0.value.done * 3 < $0.value.issued }.map(\.key))
        if !weak.isEmpty {
            lines.append("")
            lines.append("ЗАВДАННЯ З УСПІХОМ < 25 % — ДЕТАЛЬНО")
            for quest in quests.filter({ weak.contains($0.defKey) }).sorted(by: { $0.periodKey < $1.periodKey }) {
                let day = quest.periodKey.hasPrefix("adhoc:") ? String(quest.periodKey.dropFirst(6)) : quest.periodKey
                let portions = day.count == 10
                    ? services.hydration.intakes(for: DayKey(rawValue: day)).map { "\(Self.timeText($0.createdAt))·\($0.amountMl)" }.joined(separator: " ")
                    : ""
                let params = [quest.deadlineMinute.map { "T=\(Self.clock($0))" }, quest.count.map { "N=\($0)" },
                              quest.targetMl.map { "ціль=\($0)" }, quest.blockIndex.map { "блок=\($0)" }]
                    .compactMap { $0 }.joined(separator: " ")
                lines.append("  \(quest.defKey) \(quest.periodKey) \(params) → \(QuestState(rawValue: quest.stateRaw) ?? .active) | \(portions)")
            }
        }
        lines.append("")
        lines.append("ДНІ")
        lines += rows.map { "  " + $0 }
        lines.append("")
        lines.append("ДОСЯГНЕННЯ ЗА ДНЯМИ")
        for d in achByDay.keys.sorted() { lines.append("  д\(d): \(achByDay[d]!.joined(separator: ", "))") }
        lines.append("")
        lines.append("ГУЧНІ МОМЕНТИ (3+ сигнали) і вікна")
        for d in 1...days {
            let t = tallies[d]
            for m in t.loudMoments { lines.append("  д\(d) \(m)") }
            if !t.sheets.isEmpty { lines.append("  д\(d) шторки: \(t.sheets)") }
        }
        lines.append("")
        let pace = harvested.values.filter { !$0.suppressed && ($0.type == .reminder || $0.type == .checkpoint) }
        lines.append("СПРАВЖНІ ВІДПОВІДІ (≤ 15 хв, тап) на нагадування й чекпоінти: \(pace.filter(\.quick).count) з \(pace.count) = \(pace.isEmpty ? 0 : pace.filter(\.quick).count * 100 / pace.count) %")
        lines.append("ДНІ НА ЛІМІТІ (≥ 8 активних)")
        let byDay = Dictionary(grouping: harvested.values.filter { !$0.suppressed && $0.type != .report }, by: \.dayKey)
        for key in byDay.keys.sorted() where (byDay[key]?.count ?? 0) >= 8 {
            let items = byDay[key]!.sorted { $0.fireAt < $1.fireAt }
                .map { "\(Self.timeText($0.fireAt)) \($0.type)\($0.slot == "followUp" ? "+" : "")\($0.responded ? "✓" : "")" }
            let snap = services.hydration.snapshot(for: DayKey(rawValue: key))
            lines.append("  \(key) (\(snap.totalMl) мл): \(items.joined(separator: ", "))")
        }
        lines.append("")
        lines.append("ТОСТИ (унікальні): " + Set(tallies.flatMap(\.toasts)).sorted().joined(separator: " | "))
        if persona.reactive {
            lines.append("")
            lines.append("РЕАКТИВНИЙ: перші 5 днів")
            for d in 1...min(5, days) { lines.append("  д\(d): \(tallies[d].notes.joined(separator: "; "))") }
        }
        return lines.joined(separator: "\n")
    }
}

@MainActor
final class LongRunAuditTests: XCTestCase {
    override func setUp() async throws {
        try await super.setUp()
        try XCTSkipUnless(ProcessInfo.processInfo.environment["WT_AUDIT"] == "1", "аудит — лише на вимогу")
    }

    func testIdeal() async { await audit(LongRunPersonas.ideal) }
    func testTypical() async { await audit(LongRunPersonas.typical) }
    func testGulper() async { await audit(LongRunPersonas.gulper) }
    func testOnOff() async { await audit(LongRunPersonas.onOff) }
    func testHeavy() async { await audit(LongRunPersonas.heavy) }
    func testReactive() async { await audit(LongRunPersonas.reactive) }
    func testPlain() async { await audit(LongRunPersonas.plain) }
    func testOwl() async { await audit(LongRunPersonas.owl) }
    func testFading() async { await audit(LongRunPersonas.fading) }
    func testReactive100() async { await audit(LongRunPersonas.reactive100) }
    func testHybrid() async { await audit(LongRunPersonas.hybrid) }
    func testOwlAccepts() async {
        let owl = LongRunPersonas.owl
        await audit(LongRunPersona(key: "owl-accepts", title: "Сова, що приймає пропозицію графіка", seed: owl.seed,
                                   plan: owl.plan, acceptsSchedule: true))
    }

    private func audit(_ persona: LongRunPersona) async {
        let started = Date()
        let simulation = LongRunSimulation(persona)
        await simulation.run()
        let text = simulation.report() + "\n\n(прогін: \(Int(Date().timeIntervalSince(started))) с)"
        if let dir = ProcessInfo.processInfo.environment["WT_AUDIT_OUT"] {
            try? text.write(to: URL(fileURLWithPath: dir).appendingPathComponent("long-\(persona.key).txt"),
                            atomically: true, encoding: .utf8)
        } else {
            print(text)
        }
    }
}
