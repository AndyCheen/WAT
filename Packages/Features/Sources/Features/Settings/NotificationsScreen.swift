import SwiftUI
import Core
import Persistence
import DesignSystem
import Notifications

/// Екран «Сповіщення» — рядки етапів A і B з SPEC-NOTIFICATIONS §15.1. Відкривається з екрана
/// «Налаштування» (WAT-15); повна верстка — WAT-18; рядки етапу B — за макетом
/// Design/Notifications.html (кадр 7), тими самими компонентами.
public struct NotificationsScreen: View {
    @Environment(\.wtTheme) private var theme
    @State private var model: NotificationsSettingsModel
    private let onBack: () -> Void
    private let onOpenPlan: () -> Void

    public init(services: AppServices, onBack: @escaping () -> Void, onOpenPlan: @escaping () -> Void = {}) {
        _model = State(initialValue: NotificationsSettingsModel(services: services))
        self.onBack = onBack
        self.onOpenPlan = onOpenPlan
    }

    public var body: some View {
        ZStack {
            theme.screen.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: WTSpacing.cardGap) {
                    WTNavBar(title: "Сповіщення", onBack: onBack)
                    banners
                    WTCard {
                        WTSettingRow("Сповіщення", subtitle: "Нагадування, підсумки й порятунок серії") {
                            WTToggle(isOn: model.master).accessibilityIdentifier("notifications.master")
                        }
                    }
                    daySchedule
                    quietPeriods
                    duringDay
                    evening
                    reports
                    other
                    #if DEBUG
                    WTCard {
                        WTNavigationRow("План сповіщень", value: "DEBUG", action: onOpenPlan)
                            .accessibilityIdentifier("notifications.plan")
                    }
                    #endif
                }
                .wtScreenTopPadding()
                .padding(.horizontal, WTSpacing.screenSide)
                .padding(.bottom, WTSpacing.screenBottom)
                .wtNoTopOverscroll()
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .onAppear { model.refresh() }
    }

    // MARK: - Плашки

    @ViewBuilder
    private var banners: some View {
        let _ = model.revision
        if model.authorization == .denied {
            // Перемикачі працюють і зберігаються, але без дозволу нічого не планується (§16.5).
            WTNoticeBanner("Сповіщення вимкнені в налаштуваннях iOS", actionTitle: "Відкрити",
                           identifier: "notifications.denied") {
                model.openSystemSettings()
            }
        }
        if model.isPaused {
            WTNoticeBanner("На паузі до завтра", actionTitle: "Відновити", identifier: "notifications.paused") {
                model.resume()
            }
        }
    }

    // MARK: - Режим дня

    private var daySchedule: some View {
        section("РЕЖИМ ДНЯ") {
            WTSettingRow("Підйом") {
                WTValueStepper(NotificationsSettingsModel.time(model.profile.wakeMinutes), identifier: "notifications.wake",
                               onDecrement: { model.stepWake(-1) }, onIncrement: { model.stepWake(1) })
            }
            WTDivider()
            WTSettingRow("Відбій") {
                WTValueStepper(NotificationsSettingsModel.time(model.profile.sleepMinutes), identifier: "notifications.sleep",
                               onDecrement: { model.stepSleep(-1) }, onIncrement: { model.stepSleep(1) })
            }
            WTDivider()
            WTSettingRow("Окремо для вихідних") {
                WTToggle(isOn: model.weekendSchedule).accessibilityIdentifier("notifications.weekend")
            }
            if model.profile.weekendScheduleEnabled {
                WTSettingRow("Підйом у вихідні") {
                    WTValueStepper(NotificationsSettingsModel.time(model.profile.weekendWakeMinutes),
                                   identifier: "notifications.weekendWake",
                                   onDecrement: { model.stepWake(-1, weekend: true) },
                                   onIncrement: { model.stepWake(1, weekend: true) })
                }
                WTSettingRow("Відбій у вихідні") {
                    WTValueStepper(NotificationsSettingsModel.time(model.profile.weekendSleepMinutes),
                                   identifier: "notifications.weekendSleep",
                                   onDecrement: { model.stepSleep(-1, weekend: true) },
                                   onIncrement: { model.stepSleep(1, weekend: true) })
                }
            }
            WTDivider()
            WTSettingRow("Моя склянка", subtitle: "Для «+склянка» в сповіщеннях") {
                WTValueStepper("\(model.profile.glassMl) мл", identifier: "notifications.glass",
                               onDecrement: { model.stepGlass(-1) }, onIncrement: { model.stepGlass(1) })
            }
        }
    }

    // MARK: - Тихі періоди

    private var quietPeriods: some View {
        section("ТИХІ ПЕРІОДИ") {
            ForEach(Array(model.quietPeriods.enumerated()), id: \.element.id) { index, period in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        WTWeekdayPicker(
                            titles: CalendarService.weekdayLabels,
                            isSelected: { period.weekdayMask & (1 << $0) != 0 },
                            identifierPrefix: "notifications.quiet.\(index).day",
                            onToggle: { model.toggleDay($0, of: period) }
                        )
                        Spacer(minLength: 0)
                    }
                    HStack {
                        WTValueStepper(NotificationsSettingsModel.time(period.fromMinutes),
                                       identifier: "notifications.quiet.\(index).from",
                                       onDecrement: { model.stepQuiet(period, from: true, -1) },
                                       onIncrement: { model.stepQuiet(period, from: true, 1) })
                        Spacer(minLength: 4)
                        WTValueStepper(NotificationsSettingsModel.time(period.toMinutes),
                                       identifier: "notifications.quiet.\(index).to",
                                       onDecrement: { model.stepQuiet(period, from: false, -1) },
                                       onIncrement: { model.stepQuiet(period, from: false, 1) })
                    }
                    WTSectionAction("Видалити") { model.delete(period) }
                        .accessibilityIdentifier("notifications.quiet.\(index).delete")
                }
                .padding(.vertical, 8)
                WTDivider()
            }
            WTSectionAction("+ Додати тихий період") { model.addQuietPeriod() }
                .frame(minHeight: 44)
                .accessibilityIdentifier("notifications.quiet.add")
        }
    }

    // MARK: - Протягом дня

    private var duringDay: some View {
        section("ПРОТЯГОМ ДНЯ") {
            WTSettingRow("Нагадування пити", subtitle: "Коли відстаєш від свого темпу") {
                WTToggle(isOn: model.toggle(\.remindersEnabled)).accessibilityIdentifier("notifications.reminders")
            }
            if model.settings.remindersEnabled {
                VStack(spacing: 10) {
                    WTSegmentedTabs(titles: ["За темпом", "Рівні інтервали"], selection: model.reminderModeIndex,
                                    onSelect: model.selectReminderMode)
                    if model.settings.reminderMode == .pace {
                        WTSegmentedTabs(titles: ["Рідше", "Звичайно", "Частіше"], selection: model.frequencyIndex,
                                        onSelect: model.selectFrequency)
                    } else {
                        WTSegmentedTabs(titles: NotificationSettings.intervalChoices.map(Self.interval),
                                        selection: model.intervalIndex, onSelect: model.selectInterval)
                    }
                }
                .padding(.bottom, 4)
                WTSettingRow("Повторне через 30 хв") {
                    WTToggle(isOn: model.toggle(\.followUpEnabled)).accessibilityIdentifier("notifications.followUp")
                }
            }
            // Без ритму дня чекпоінтів немає зовсім (WAT-42) — перемикач, що нічого не змінює, не показуємо.
            if model.profile.dayRhythmEnabled {
                WTDivider()
                WTSettingRow("Частини доби", subtitle: "«До 12:00 — ще 150 мл», якщо можна встигнути") {
                    WTToggle(isOn: model.toggle(\.checkpointsEnabled)).accessibilityIdentifier("notifications.checkpoints")
                }
            }
            WTDivider()
            WTSettingRow("Ранкова склянка", subtitle: "Якщо зранку ще немає порцій") {
                WTToggle(isOn: model.toggle(\.morningEnabled)).accessibilityIdentifier("notifications.morning")
            }
            if model.settings.morningEnabled {
                WTSegmentedTabs(titles: ["О підйомі", "Свій час"], selection: model.morningCustomIndex,
                                onSelect: model.selectMorningCustom)
                if let minutes = model.settings.morningCustomMinutes {
                    WTSettingRow("Час") {
                        WTValueStepper(NotificationsSettingsModel.time(minutes), identifier: "notifications.morningTime",
                                       onDecrement: { model.stepMorning(-1) }, onIncrement: { model.stepMorning(1) })
                    }
                }
            }
        }
    }

    // MARK: - Увечері

    private var evening: some View {
        section("УВЕЧЕРІ") {
            WTSettingRow("Вечірній підсумок", subtitle: "Скільки лишилось до норми") {
                WTToggle(isOn: model.toggle(\.eveningEnabled)).accessibilityIdentifier("notifications.evening")
            }
            if model.settings.eveningEnabled {
                WTSegmentedTabs(titles: ["За 2 год до відбою", "Свій час"], selection: model.eveningCustomIndex,
                                onSelect: model.selectEveningCustom)
                if let minutes = model.settings.eveningCustomMinutes {
                    WTSettingRow("Час") {
                        WTValueStepper(NotificationsSettingsModel.time(minutes), identifier: "notifications.eveningTime",
                                       onDecrement: { model.stepEvening(-1) }, onIncrement: { model.stepEvening(1) })
                    }
                }
            }
            WTDivider()
            WTSettingRow("Порятунок серії", subtitle: "Коли заморозка ще може врятувати серію") {
                WTToggle(isOn: model.toggle(\.rescueEnabled)).accessibilityIdentifier("notifications.rescue")
            }
        }
    }

    // MARK: - Звіти (§11.1)

    private var reports: some View {
        section("ЗВІТИ") {
            WTSettingRow("Денний", subtitle: "Тихо, о відбої") {
                WTToggle(isOn: model.toggle(\.dailyReportEnabled)).accessibilityIdentifier("notifications.reportDay")
            }
            WTDivider()
            WTSettingRow("Тижневий", subtitle: "Підсумки минулого тижня") {
                WTToggle(isOn: model.toggle(\.weeklyReportEnabled)).accessibilityIdentifier("notifications.reportWeek")
            }
            if model.settings.weeklyReportEnabled {
                HStack {
                    WTWeekdayPicker(
                        titles: CalendarService.weekdayLabels,
                        isSelected: { $0 == model.settings.weeklyReportWeekday },
                        identifierPrefix: "notifications.reportWeekday",
                        onToggle: model.selectReportWeekday
                    )
                    Spacer(minLength: 0)
                }
                WTSettingRow("Час") {
                    WTValueStepper(NotificationsSettingsModel.time(model.settings.weeklyReportMinutes),
                                   identifier: "notifications.reportWeekTime",
                                   onDecrement: { model.stepReportTime(weekly: true, -1) },
                                   onIncrement: { model.stepReportTime(weekly: true, 1) })
                }
            }
            WTDivider()
            WTSettingRow("Місячний", subtitle: "1-го числа") {
                WTToggle(isOn: model.toggle(\.monthlyReportEnabled)).accessibilityIdentifier("notifications.reportMonth")
            }
            if model.settings.monthlyReportEnabled {
                WTSettingRow("Час") {
                    WTValueStepper(NotificationsSettingsModel.time(model.settings.monthlyReportMinutes),
                                   identifier: "notifications.reportMonthTime",
                                   onDecrement: { model.stepReportTime(weekly: false, -1) },
                                   onIncrement: { model.stepReportTime(weekly: false, 1) })
                }
            }
        }
    }

    // MARK: - Інше

    private var other: some View {
        section("ІНШЕ") {
            VStack(alignment: .leading, spacing: 8) {
                Text("Звук сповіщень")
                    .font(WTFont.text(16, .bold))
                    .foregroundStyle(theme.textPrimary)
                WTSegmentedTabs(titles: ["Булькання", "Системний", "Без звуку"], selection: model.soundIndex,
                                onSelect: model.selectSound)
            }
            .padding(.vertical, 8)
            WTDivider()
            WTSettingRow("Досягнення поза застосунком") {
                WTToggle(isOn: model.toggle(\.echoEnabled)).accessibilityIdentifier("notifications.echo")
            }
            WTDivider()
            WTSettingRow("Повернення після перерви", subtitle: "Два повідомлення, далі тиша") {
                WTToggle(isOn: model.toggle(\.comebackEnabled)).accessibilityIdentifier("notifications.comeback")
            }
        }
    }

    // MARK: - Будова

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            WTSectionLabel(title)
            WTCard {
                VStack(alignment: .leading, spacing: 0) { content() }
            }
        }
    }

    private static func interval(_ minutes: Int) -> String {
        minutes % 60 == 0 ? "\(minutes / 60) год" : "\(minutes) хв"
    }
}
