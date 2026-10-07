import Foundation
import Observation
import Core
import Persistence
import Metrics

/// Що робити зі сповіщенням, яке настало при відкритому застосунку (§16.7).
public enum NotificationPresentation: Sendable, Equatable {
    /// Людина вже бачить кільце — не показуємо, у журналі «придушене».
    case suppress
    /// Зміст на головному не видно — показуємо банером.
    case banner
}

/// Оркестратор сповіщень: журнал, перепланування, відповіді, дозвіл (SPEC-NOTIFICATIONS §16).
///
/// Сам нічого не знає про воду й гейміфікацію — стан приходить через `contextProvider`
/// від композиційного кореня. Підписаний на шину метрик лише заради `intake.added`: так
/// атрибуція «сповіщення виконано» працює однаково для порцій із застосунку, з дії
/// сповіщення й (згодом) з віджета — і лягає в той самий `commit()`, що й порція.
@MainActor
@Observable
public final class NotificationService: MetricsSubscriber {
    @ObservationIgnored private let store: NotificationStoreProtocol
    @ObservationIgnored private let profiles: ProfileRepositoryProtocol
    @ObservationIgnored private let metrics: MetricsService
    @ObservationIgnored private let calendar: CalendarService
    @ObservationIgnored public let center: NotificationCenterProtocol
    @ObservationIgnored public let rules: NotificationRules
    @ObservationIgnored private let bubbleSoundAvailable: Bool

    /// Збирає `NotificationContext` — ставить `AppServices`.
    @ObservationIgnored public var contextProvider: (() -> NotificationContext)?

    /// `nil` — ще не перевіряли: шторку дозволу до першої перевірки не показуємо.
    public private(set) var authorization: NotificationAuthorization?
    public private(set) var lastPlan: NotificationPlan = .empty
    /// Змінюється після кожного проходу — екрани «Сповіщення» й DEBUG-план перечитують стан.
    public private(set) var revision = 0

    @ObservationIgnored private var rescheduleTask: Task<Void, Never>?
    @ObservationIgnored private var needsAnotherPass = false
    @ObservationIgnored private var attributionOverride: String?
    @ObservationIgnored private var intakeSinceLastPass = false
    /// Склянка й система об'єму, з якими зареєстровано категорії: назва дії «+250 мл» / «+8 oz».
    @ObservationIgnored private var registeredGlass: (ml: Int, unit: VolumeUnit)?

    public init(
        store: NotificationStoreProtocol,
        profiles: ProfileRepositoryProtocol,
        metrics: MetricsService,
        calendar: CalendarService,
        center: NotificationCenterProtocol,
        rules: NotificationRules = .default,
        bubbleSoundAvailable: Bool = false
    ) {
        self.store = store
        self.profiles = profiles
        self.metrics = metrics
        self.calendar = calendar
        self.center = center
        self.rules = rules
        self.bubbleSoundAvailable = bubbleSoundAvailable
    }

    public func bootstrap() {
        metrics.subscribe(self)
        _ = store.settings()
    }

    public var settings: NotificationSettings { store.settings() }

    public func preferences() -> NotificationPreferences {
        NotificationPreferences(profile: profiles.profile(), settings: store.settings(), quietPeriods: store.quietPeriods())
    }

    // MARK: - Перепланування (§16.3)

    /// Попросити перепланування. Іде асинхронно, після поточної дії — поза шляхом, який міряє
    /// `PerformanceTests`. Кілька запитів поспіль зливаються в один прохід.
    public func setNeedsReschedule() {
        guard rescheduleTask == nil else {
            needsAnotherPass = true
            return
        }
        rescheduleTask = Task { [weak self] in
            await self?.drain()
        }
    }

    /// Перепланувати й дочекатися: перед відходом у фон, після дії зі сповіщення, у тестах.
    public func rescheduleNow() async {
        if rescheduleTask != nil { needsAnotherPass = true } else { setNeedsReschedule() }
        await rescheduleTask?.value
    }

    /// Проходи йдуть строго по черзі: два паралельні перемежовувались би на `await`
    /// і знімали б запити одне одного.
    private func drain() async {
        repeat {
            needsAnotherPass = false
            await performReschedule()
        } while needsAnotherPass
        rescheduleTask = nil
    }

    private func performReschedule() async {
        authorization = await center.authorization()
        let now = calendar.now
        markDelivered(before: now)
        if intakeSinceLastPass {
            intakeSinceLastPass = false
            clearDeliveredDrinkPrompts(now: now)
        }

        let preferences = preferences()
        let context = contextProvider?() ?? NotificationContext(now: now, timeZone: calendar.calendar.timeZone)
        let plan = NotificationPlanner.plan(
            context: context, preferences: preferences, journal: journal(around: now), rules: rules
        )
        lastPlan = plan

        // Без дозволу чи з вимкненим головним вимикачем перемикачі зберігаються, але нічого
        // не планується, а вже заплановане знімається (§16.5).
        let active = authorization == .authorized && preferences.isEnabled
        if active { registerCategoriesIfNeeded(preferences) }
        let sound = SoundResolver.resolve(preferences.sound, bubbleAvailable: bubbleSoundAvailable)
        let requests = active ? NotificationScheduler.requests(for: plan, sound: sound, calendar: calendar.calendar) : []
        await NotificationScheduler.apply(requests, to: center)

        syncJournal(with: active ? plan.items : [], now: calendar.now)
        store.deleteLogs(firedBefore: now.addingTimeInterval(-Double(rules.logRetentionDays) * 86_400))
        metrics.commit()
        revision &+= 1
    }

    /// «Доставлено» видно лише коли застосунок працює: запити, час яких минув і які не
    /// скасовано, позначаються доставленими при кожному переплануванні (§16.8).
    private func markDelivered(before now: Date) {
        for log in store.logs(firingFrom: now.addingTimeInterval(-8 * 86_400), to: now)
        where log.deliveredAt == nil && log.cancelledAt == nil && log.suppressedAt == nil {
            log.deliveredAt = log.fireAt
            metrics.record(MetricEvent(
                name: .notificationDelivered, value: 1, occurredAt: log.fireAt, sourceRef: log.id,
                payload: ["type": log.type.key]
            ))
        }
    }

    /// «Давно не пив» після того, як людина випила, лише заважає (§6.4).
    private func clearDeliveredDrinkPrompts(now: Date) {
        let today = calendar.dayKey(for: now).rawValue
        let drinkTypes: Set<NotificationType> = [.reminder, .checkpoint, .morning, .evening, .comeback]
        let identifiers = store.logs(firingFrom: calendar.startOfDay(now), to: now.addingTimeInterval(1))
            .filter { $0.dayKey == today && drinkTypes.contains($0.type) && $0.cancelledAt == nil }
            .map(\.identifier)
        center.removeDelivered(identifiers: identifiers)
    }

    private func syncJournal(with items: [PlannedNotification], now: Date) {
        let planned = Set(items.map(\.id))
        for item in items {
            if let log = store.log(identifier: item.id) {
                log.typeRaw = item.type.rawValue
                log.slot = item.slot
                log.fireAt = item.fireAt
                log.variant = item.variant
                log.plannedAt = now
                log.cancelledAt = nil
            } else {
                store.insert(NotificationLog(
                    identifier: item.id, type: item.type, slot: item.slot, dayKey: item.dayKey.rawValue,
                    fireAt: item.fireAt, plannedAt: now, variant: item.variant
                ))
            }
        }
        for log in store.logs(firingFrom: now, to: .distantFuture)
        where !planned.contains(log.identifier) && log.cancelledAt == nil && log.type != .echo {
            log.cancelledAt = now
        }
    }

    /// Журнал за 8 днів — вистачає на повернення 7-го дня й ротацію текстів.
    public func journal(around now: Date) -> NotificationJournal {
        let entries = store.logs(firingFrom: now.addingTimeInterval(-8 * 86_400), to: .distantFuture).map { log in
            let status: JournalEntry.Status
            if log.cancelledAt != nil { status = .cancelled }
            else if log.suppressedAt != nil { status = .suppressed }
            else if log.fireAt <= now { status = .delivered }
            else { status = .pending }
            return JournalEntry(
                identifier: log.identifier, type: log.type, slot: log.slot, dayKey: DayKey(rawValue: log.dayKey),
                fireAt: log.fireAt, variant: log.variant, status: status, response: log.response,
                respondedAt: log.respondedAt
            )
        }
        return NotificationJournal(entries: entries)
    }

    // MARK: - Взаємодія та відповіді (§3.2, §6.4)

    /// Відкриття застосунку чи дія в ньому: ланцюг нагадувань стартує не раніше ніж через 30 хв.
    public func recordInteraction(at date: Date) {
        store.settings().lastInteractionAt = date
    }

    public func isIntakeResponded(_ identifier: String) -> Bool {
        store.log(identifier: identifier)?.response == .intake
    }

    /// Порція з дії сповіщення зараховується саме йому, а не «найсвіжішому».
    public func beginAttribution(identifier: String) { attributionOverride = identifier }
    public func endAttribution() { attributionOverride = nil }

    public func recordOpen(identifier: String, at date: Date) {
        let log = logEntry(for: identifier, at: date)
        log.openedAt = log.openedAt ?? date
        if log.response == .none {
            log.response = .open
            log.respondedAt = date
        }
        metrics.record(MetricEvent(name: .notificationOpened, value: 1, occurredAt: date, sourceRef: log.id))
        metrics.commit()
    }

    /// «Нагадати за годину»: одне основне через 60 хв, далі ланцюг як звичайно. Не рахується
    /// проігноруванням (§6.4).
    public func snooze(identifier: String, at date: Date) {
        let log = logEntry(for: identifier, at: date)
        log.response = .snooze
        log.respondedAt = date
        metrics.record(MetricEvent(name: .notificationSnoozed, value: 1, occurredAt: date, sourceRef: log.id))
        metrics.commit()
    }

    /// «Не сьогодні»: пауза мотиваційних типів до 00:00. Порятунок серії не зачіпає (§6.4, §12.1).
    public func pause(identifier: String?, at date: Date) {
        store.settings().pausedUntil = calendar.date(from: calendar.dayKey(offsetDays: 1, from: calendar.dayKey(for: date)))
        var ref = UUID()
        if let identifier {
            let log = logEntry(for: identifier, at: date)
            log.response = .pause
            log.respondedAt = date
            ref = log.id
        }
        metrics.record(MetricEvent(name: .notificationPaused, value: 1, occurredAt: date, sourceRef: ref))
        metrics.commit()
    }

    /// «На паузі до завтра · Відновити» на екрані налаштувань (§13.2).
    public func resume() {
        store.settings().pausedUntil = nil
        store.save()
    }

    public func isPaused(at date: Date) -> Bool {
        store.settings().pausedUntil.map { date < $0 } ?? false
    }

    public func markSuppressed(identifier: String, at date: Date) {
        logEntry(for: identifier, at: date).suppressedAt = date
        store.save()
    }

    public nonisolated static func presentation(forIdentifier identifier: String) -> NotificationPresentation {
        switch PlannedNotification.type(ofIdentifier: identifier) {
        case .reminder, .morning, .evening, .checkpoint, .challenge: return .suppress
        default: return .banner
        }
    }

    /// Рядок журналу для відповіді. Якщо його немає (база очищена між плануванням і відповіддю) —
    /// створюється з ідентифікатора, щоб ідемпотентність і метрики працювали.
    private func logEntry(for identifier: String, at date: Date) -> NotificationLog {
        if let log = store.log(identifier: identifier) { return log }
        let type = PlannedNotification.type(ofIdentifier: identifier) ?? .reminder
        let parts = identifier.split(separator: ".")
        let day = parts.count > 2 ? String(parts[2]) : calendar.dayKey(for: date).rawValue
        let log = NotificationLog(identifier: identifier, type: type, slot: "", dayKey: day,
                                  fireAt: date, plannedAt: date, variant: 0)
        log.deliveredAt = date
        store.insert(log)
        return log
    }

    // MARK: - Атрибуція порції (§3.2)

    public func metricsDidRecord(_ event: RecordedMetricEvent, service: MetricsService) {
        guard event.name == .intakeAdded else { return }
        intakeSinceLastPass = true
        let at = event.occurredAt
        let target: NotificationLog?
        if let identifier = attributionOverride {
            target = store.log(identifier: identifier)
        } else {
            // Одна порція — одному сповіщенню, найсвіжішому з доставлених за останню годину.
            let window = TimeInterval(rules.responseWindowMinutes * 60)
            let respondable: Set<NotificationType> = [.reminder, .checkpoint, .morning, .evening, .rescue, .comeback]
            target = store.logs(firingFrom: at.addingTimeInterval(-window), to: at.addingTimeInterval(1))
                .filter { respondable.contains($0.type) && $0.cancelledAt == nil && $0.suppressedAt == nil }
                .last
        }
        guard let log = target, log.response != .intake else { return }
        log.deliveredAt = log.deliveredAt ?? min(log.fireAt, at)
        log.respondedAt = at
        log.response = .intake
        log.intakeId = event.sourceRef
        let minutes = max(0, at.timeIntervalSince(log.fireAt) / 60)
        metrics.record(MetricEvent(name: .reminderResponded, value: minutes.rounded(), occurredAt: at, sourceRef: log.id))
    }

    // MARK: - Відлуння (§12.1, тип 8)

    /// Розблокування від порції, внесеної поза відкритим застосунком, — одразу сповіщенням.
    public func sendEcho(title: String, body: String, route: NotificationTapRoute, intakeId: UUID, at date: Date) async {
        let preferences = preferences()
        // Холодний старт від дії: перший прохід перепланування ще не встиг перевірити дозвіл.
        if authorization == nil { authorization = await center.authorization() }
        guard authorization == .authorized, preferences.isEnabled, preferences.echoEnabled else { return }
        let day = calendar.dayKey(for: date)
        let identifier = "wt.echo.\(day.rawValue).\(intakeId.uuidString.prefix(8).lowercased())"
        let userInfo = [UserInfoKey.type: NotificationType.echo.key, UserInfoKey.route: route.encoded]
        await center.add(ScheduledRequest(
            identifier: identifier, title: title, body: body, categoryId: nil,
            sound: SoundResolver.resolve(preferences.sound, bubbleAvailable: bubbleSoundAvailable),
            trigger: .immediate, fireAt: date, userInfo: userInfo, fingerprint: identifier
        ))
        let log = NotificationLog(identifier: identifier, type: .echo, slot: "echo", dayKey: day.rawValue,
                                  fireAt: date, plannedAt: date, variant: 0)
        log.deliveredAt = date
        store.insert(log)
        store.save()
    }

    // MARK: - Дозвіл (§16.5)

    public func refreshAuthorization() async {
        authorization = await center.authorization()
    }

    /// Системний запит. Після нього шторку вже не показуємо — далі лише з налаштувань.
    @discardableResult
    public func requestAuthorization() async -> Bool {
        store.settings().permissionPromptState = .finished
        store.save()
        let granted = await center.requestAuthorization()
        authorization = await center.authorization()
        setNeedsReschedule()
        return granted
    }

    /// Шторку «Нагадувати, коли забудеш про воду?» показуємо після порції, якщо системний запит
    /// ще не робили: першого разу — одразу, після «Не зараз» — через 3 дні, далі ніколи.
    public func shouldOfferPermission(at date: Date) -> Bool {
        guard authorization == .notDetermined, profiles.profile().notificationsEnabled else { return false }
        let settings = store.settings()
        switch settings.permissionPromptState {
        case .notAsked:
            return true
        case .postponed:
            guard let postponed = settings.permissionPromptPostponedAt else { return true }
            return calendar.daysBetween(calendar.dayKey(for: postponed), calendar.dayKey(for: date))
                >= rules.permissionRepromptDays
        case .finished:
            return false
        }
    }

    /// «Не зараз»: першого разу — спитаємо ще через 3 дні, вдруге — лише з налаштувань.
    public func postponePermissionPrompt(at date: Date) {
        let settings = store.settings()
        if settings.permissionPromptState == .notAsked {
            settings.permissionPromptState = .postponed
            settings.permissionPromptPostponedAt = date
        } else {
            settings.permissionPromptState = .finished
        }
        store.save()
    }

    // MARK: - Тихі періоди (§13.2)

    public func quietPeriods() -> [QuietPeriod] { store.quietPeriods() }

    @discardableResult
    public func addQuietPeriod(fromMinutes: Int, toMinutes: Int, weekdayMask: Int) -> QuietPeriod {
        store.addQuietPeriod(fromMinutes: fromMinutes, toMinutes: toMinutes, weekdayMask: weekdayMask)
    }

    public func deleteQuietPeriod(_ period: QuietPeriod) { store.delete(period) }

    // MARK: - DEBUG

    /// «Тестове за 5 с» на екрані «План сповіщень»: нагадування з усіма діями, щоб руками
    /// перевірити «+склянку» у фоні й поведінку при відкритому застосунку. Префікс `debug.` —
    /// поза диффом планувальника, тож наступне перепланування його не зніме.
    public func scheduleTestReminder(after seconds: TimeInterval = 5) async {
        let preferences = preferences()
        registerCategoriesIfNeeded(preferences)
        let fireAt = calendar.now.addingTimeInterval(seconds)
        var parts = calendar.calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: fireAt)
        parts.timeZone = calendar.calendar.timeZone
        let identifier = "debug.\(UUID().uuidString.prefix(8).lowercased())"
        await center.add(ScheduledRequest(
            identifier: identifier, title: "💧 Час на воду", body: "Тестове нагадування — спробуй дії",
            categoryId: NotificationCategory.reminder.rawValue,
            sound: SoundResolver.resolve(preferences.sound, bubbleAvailable: bubbleSoundAvailable),
            trigger: .calendar(parts, floating: false), fireAt: fireAt,
            userInfo: [UserInfoKey.glassMl: String(preferences.glassMl),
                       UserInfoKey.portionMl: String(lastPlan.typicalPortionMl),
                       UserInfoKey.route: NotificationTapRoute.customAmount(ml: lastPlan.typicalPortionMl).encoded],
            fingerprint: identifier
        ))
    }

    // MARK: - Категорії (§16.4)

    /// Назва дії «+250 мл» належить категорії, а не запиту — при зміні склянки категорії
    /// реєструються наново.
    private func registerCategoriesIfNeeded(_ preferences: NotificationPreferences) {
        let key = (ml: preferences.glassMl, unit: preferences.volumeUnit)
        guard registeredGlass.map({ $0 != key }) ?? true else { return }
        registeredGlass = key
        center.setCategories(Self.categories(glassMl: key.ml, unit: key.unit))
    }

    public static func categories(glassMl: Int, unit: VolumeUnit = .milliliters) -> [NotificationCategorySpec] {
        let add = NotificationActionSpec(id: NotificationActionID.addGlass,
                                         title: "+" + unit.format(glassMl) { "\($0) мл" })
        return [
            NotificationCategorySpec(id: NotificationCategory.reminder.rawValue, actions: [
                add,
                NotificationActionSpec(id: NotificationActionID.otherAmount, title: "Інший об'єм", opensApp: true),
                NotificationActionSpec(id: NotificationActionID.snooze, title: "Нагадати за годину"),
                NotificationActionSpec(id: NotificationActionID.pause, title: "Не сьогодні", destructive: true)
            ]),
            NotificationCategorySpec(id: NotificationCategory.glass.rawValue, actions: [add])
        ]
    }
}
