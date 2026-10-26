import SwiftUI
import Core
import Persistence
import Gamification
import Notifications
import DesignSystem

/// «Режим розробника» (WAT-68) — з «Налаштувань», лише в DEBUG-збірці. Дані для тестування: годинник, дні, гра,
/// вікна, скидання. Тексти — `DeveloperPresenter`, дії — `AppServices+Developer`.
public struct DeveloperScreen: View {
    @Environment(\.wtTheme) private var theme
    @State private var model: DeveloperModel
    @State private var pendingReset: EraseScope?
    private let onBack: () -> Void
    private let onOpen: (AppRoute) -> Void
    private let onOpenOnboarding: () -> Void

    public init(services: AppServices, onBack: @escaping () -> Void, onOpen: @escaping (AppRoute) -> Void,
                onOpenOnboarding: @escaping () -> Void) {
        _model = State(initialValue: DeveloperModel(services: services))
        self.onBack = onBack
        self.onOpen = onOpen
        self.onOpenOnboarding = onOpenOnboarding
    }

    public var body: some View {
        DeveloperPageLayout(title: "Режим розробника", onBack: onBack) {
            DeveloperNote("Дії йдуть повз правила гри, а далі — звичайним шляхом: XP, рівні, вікна відкриття, сповіщення.")
            state
            clock
            days
            game
            notifications
            windows
            reset
        }
        .overlay { busyOverlay }
        .animation(WTAnimation.fade, value: model.busy == nil)
        .onAppear { model.reload() }
        // Вікно відкриття, нова доба, зсув годинника.
        .onChange(of: model.epoch) { model.reload() }
        .confirmationDialog(resetTitle, isPresented: isConfirmingReset, titleVisibility: .visible) {
            Button("Скинути й закрити застосунок", role: .destructive) {
                if let pendingReset { model.reset(pendingReset) }
            }
            .accessibilityIdentifier("developer.reset.confirm")
            Button("Скасувати", role: .cancel) { pendingReset = nil }
        } message: {
            Text(resetMessage)
        }
    }

    // MARK: - Секції

    private var state: some View {
        DeveloperSection(title: "СТАН") {
            DeveloperValueRow(title: "Зараз", value: model.nowLabel, identifier: "developer.now")
            WTDivider()
            DeveloperValueRow(title: "Рівень", value: model.levelLabel, identifier: "developer.level")
            WTDivider()
            DeveloperValueRow(title: "Серія", value: model.streakLabel, identifier: "developer.streak")
            WTDivider()
            DeveloperValueRow(title: "Сьогодні", value: model.todayLabel, identifier: "developer.today")
        }
    }

    @ViewBuilder
    private var clock: some View {
        if let offset = model.clockOffsetLabel {
            DeveloperSection(title: "ГОДИННИК") {
                DeveloperValueRow(title: "Зсув", value: offset, identifier: "developer.clock.offset")
                DeveloperChips(chips: [
                    .init(id: "developer.clock.plus1h", title: "+1 год") { model.shiftClock(hours: 1) },
                    .init(id: "developer.clock.plus6h", title: "+6 год") { model.shiftClock(hours: 6) },
                    .init(id: "developer.clock.plus1d", title: "+1 день") { model.shiftClock(hours: 24) },
                    .init(id: "developer.clock.minus1h", title: "−1 год") { model.shiftClock(hours: -1) },
                    .init(id: "developer.clock.minus1d", title: "−1 день") { model.shiftClock(hours: -24) },
                    .init(id: "developer.clock.reset", title: "Справжній час") { model.resetClock() }
                ])
                DeveloperNote("Нова доба, дедлайни завдань і несподівані — без очікування. Зсув живе між запусками. "
                              + "Порції, додані в «майбутньому», після повернення часу лишаються в майбутніх днях.")
            }
        }
    }

    private var days: some View {
        DeveloperSection(title: "ДНІ") {
            WTNavigationRow("Редагувати день", value: "норма, порції") { onOpen(.developer(.day)) }
                .accessibilityIdentifier("developer.days")
            WTDivider()
            WTSettingRow("Серія закритих днів", subtitle: "До сьогодні; вже закриті не чіпаються") { EmptyView() }
            DeveloperChips(chips: [3, 7, 14, 30].map { count in
                .init(id: "developer.closeDays.\(count)", title: ReportFormat.daysWord(count, withNumber: true)) {
                    model.closeDays(count)
                }
            })
            WTDivider()
            WTNavigationRow("Демо-історія", value: "60 днів") { model.seedDemo() }
                .accessibilityIdentifier("developer.seedDemo")
            DeveloperNote("Додається поверх наявних порцій — для чистого вигляду спершу «Скинути прогрес».")
        }
    }

    private var game: some View {
        DeveloperSection(title: "ГРА") {
            WTNavigationRow("Досягнення", value: "\(model.unlockedCount) / \(model.achievements.count)") {
                onOpen(.developer(.achievements))
            }
            .accessibilityIdentifier("developer.achievements")
            WTDivider()
            WTNavigationRow("Завдання", value: "\(model.quests.count) зараз") { onOpen(.developer(.quests)) }
                .accessibilityIdentifier("developer.quests")
            WTDivider()
            ForEach(RewardCatalog.all, id: \.key) { prize in
                WTSettingRow("\(prize.emoji) \(prize.title)", subtitle: "Готових: \(model.prizeCounts[prize.key] ?? 0)") {
                    WTSectionAction("+1") { model.grantPrize(prize.key) }
                        .accessibilityIdentifier("developer.prize.\(prize.key)")
                }
            }
            if model.hasActiveBoost {
                WTSettingRow("Буст діє", subtitle: "Закінчити зараз, не чекаючи півночі") {
                    WTSectionAction("Зупинити") { model.stopBoost() }
                        .accessibilityIdentifier("developer.prize.stopBoost")
                }
            }
            WTDivider()
            WTSettingRow("Рівень", subtitle: "\(model.level.xpIntoLevel) / \(model.level.xpForNextLevel) XP") {
                WTValueStepper("\(model.level.level)", identifier: "developer.level.stepper",
                               onDecrement: { model.stepLevel(up: false) },
                               onIncrement: { model.stepLevel(up: true) })
            }
            DeveloperChips(chips: DeveloperModel.levelPresets.map { value in
                .init(id: "developer.level.\(value)", title: "\(value)", isSelected: model.level.level == value) {
                    model.setLevel(value)
                }
            } + [
                .init(id: "developer.level.almost", title: "За 10 XP до наступного") { model.almostNextLevel() },
                .init(id: "developer.xp.50", title: "+50 XP") { model.awardXp(50) },
                .init(id: "developer.xp.500", title: "+500 XP") { model.awardXp(500) }
            ])
            DeveloperNote("Рівень ставиться на поріг (плюс XP досягнення рівня, якщо воно відкрилось); униз видані "
                          + "призи й досягнення лишаються. «+50 XP» — з бустом і множником, як справжній XP.")
        }
    }

    private var notifications: some View {
        DeveloperSection(title: "СПОВІЩЕННЯ") {
            DeveloperNote("Справжнє сповіщення з текстом і діями, як із плану. Банер видно й у відкритому застосунку; "
                          + "за 30 с — встигнеш заблокувати телефон.")
            DeveloperChips(chips: DeveloperPresenter.notificationDelays.map { seconds in
                .init(id: "developer.notify.delay.\(seconds)", title: "За \(seconds) с",
                      isSelected: model.notificationDelay == seconds) { model.notificationDelay = seconds }
            })
            WTDivider()
            DeveloperChips(chips: DeveloperPresenter.notificationSamples.map { sample, title in
                .init(id: "developer.notify.\(sample.rawValue)", title: title) { model.sendNotification(sample) }
            } + [.init(id: "developer.notify.echo", title: "Відлуння (одразу)") { model.sendEcho() }])
            if let notice = model.notificationNotice {
                DeveloperNote(notice)
                    .accessibilityIdentifier("developer.notify.notice")
            }
        }
    }

    private var windows: some View {
        DeveloperSection(title: "ВІКНА Й ЕКРАНИ") {
            WTNavigationRow("Онбординг першого запуску") { onOpenOnboarding() }
                .accessibilityIdentifier("developer.onboarding")
            WTDivider()
            WTNavigationRow("Звіт за минулий тиждень") { onOpen(.report([])) }
                .accessibilityIdentifier("developer.report")
            WTDivider()
            WTNavigationRow("План сповіщень") { onOpen(.notificationPlan) }
                .accessibilityIdentifier("developer.notificationPlan")
            WTDivider()
            WTNavigationRow("Галерея віджетів") { onOpen(.widgetGallery) }
                .accessibilityIdentifier("developer.widgets")
            WTDivider()
            WTSettingRow("Вікно «Графік дня»", subtitle: "Повз правило частоти") { EmptyView() }
            DeveloperChips(chips: DeveloperPresenter.scheduleDemos.map { demo, title in
                .init(id: "developer.schedule.\(demo.rawValue)", title: title) { model.showSchedule(demo) }
            })
            WTDivider()
            WTSettingRow("Тап по сповіщенню", subtitle: "Куди веде кожен тип") { EmptyView() }
            DeveloperChips(chips: DeveloperPresenter.notificationTaps.map { type, title in
                .init(id: "developer.tap.\(type.key)", title: title) { model.tapNotification(type) }
            })
        }
    }

    private var reset: some View {
        DeveloperSection(title: "СКИДАННЯ") {
            WTNavigationRow("Скинути прогрес") { pendingReset = .progress }
                .accessibilityIdentifier("developer.reset.progress")
            WTDivider()
            WTNavigationRow("Скинути все") { pendingReset = .everything }
                .accessibilityIdentifier("developer.reset.everything")
            DeveloperNote("Прогрес — порції, XP, досягнення, завдання, призи; профіль і налаштування лишаються. "
                          + "Усе — як нова установка, з онбордингом. Застосунок закриється — відкрий його знову.")
        }
    }

    /// Масова дія: сторінка під індикатором не реагує, і «назад» посеред заповнення не кине його напівдорозі.
    @ViewBuilder
    private var busyOverlay: some View {
        if let busy = model.busy {
            ZStack {
                theme.screen.opacity(0.9).ignoresSafeArea()
                WTCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(busy.title)
                            .font(WTFont.text(17, .bold))
                            .foregroundStyle(theme.textPrimary)
                        WTProgressBar(fraction: busy.fraction)
                        Text("\(Int((busy.fraction * 100).rounded())) %")
                            .font(WTFont.number(15, .semibold))
                            .foregroundStyle(theme.textMuted)
                            .accessibilityIdentifier("developer.busy")
                    }
                }
                .padding(.horizontal, WTSpacing.screenSide)
            }
            .transition(.opacity)
        }
    }

    // MARK: - Підтвердження скидання

    private var isConfirmingReset: Binding<Bool> {
        Binding(get: { pendingReset != nil }, set: { if !$0 { pendingReset = nil } })
    }

    private var resetTitle: String {
        pendingReset == .everything ? "Скинути все?" : "Скинути прогрес?"
    }

    private var resetMessage: String {
        let erased = pendingReset == .everything
            ? "Зникне все, зокрема профіль, норма й налаштування; наступний запуск відкриє онбординг."
            : "Зникнуть порції, XP, рівні, досягнення, завдання, призи й журнали. Профіль, норма, розклад, кнопки "
                + "й сповіщення лишаться."
        return erased + " Застосунок закриється — відкрий його знову."
    }
}
