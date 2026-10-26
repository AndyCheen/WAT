import SwiftUI
import Core
import Persistence
import DesignSystem

/// Екран «Налаштування» на весь екран (WAT-15) — замість шторки на головному. У стеку навігації,
/// а не знизу, як «Склянка»: з нього йдуть далі («Сповіщення»), і «назад» має вертати сюди
/// (рішення від 07.10.2026). Верстка — компонентами екрана «Сповіщення», щоб обидва були рідні.
public struct SettingsScreen: View {
    @Environment(\.wtTheme) private var theme
    @State private var model: SettingsModel
    @Binding private var themeMode: ThemeMode
    @Binding private var hapticsEnabled: Bool
    private let onBack: () -> Void
    private let onOpenNotifications: () -> Void
    private let onOpenLearn: (String) -> Void
    private let onOpenPortionButtons: () -> Void
    private let onOpenOnboarding: () -> Void
    private let onOpenDeveloper: () -> Void
    @State private var onboardingDesign = OnboardingDesign.current

    public init(
        services: AppServices,
        themeMode: Binding<ThemeMode>,
        hapticsEnabled: Binding<Bool>,
        onBack: @escaping () -> Void,
        onOpenNotifications: @escaping () -> Void,
        onOpenPortionButtons: @escaping () -> Void,
        onOpenLearn: @escaping (String) -> Void = { _ in },
        onOpenOnboarding: @escaping () -> Void = {},
        onOpenDeveloper: @escaping () -> Void = {}
    ) {
        self.onOpenOnboarding = onOpenOnboarding
        self.onOpenDeveloper = onOpenDeveloper
        _model = State(initialValue: SettingsModel(services: services))
        _themeMode = themeMode
        _hapticsEnabled = hapticsEnabled
        self.onBack = onBack
        self.onOpenNotifications = onOpenNotifications
        self.onOpenPortionButtons = onOpenPortionButtons
        self.onOpenLearn = onOpenLearn
    }

    public var body: some View {
        ZStack {
            theme.screen.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: WTSpacing.cardGap) {
                    WTNavBar(title: "Налаштування", onBack: onBack)
                    water
                    units
                    rhythm
                    app
                    temporary
                    #if DEBUG
                    developer
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
        // Повторний онбординг відкривається поверх цього екрана й міняє норму — `onAppear` після нього не прийде.
        .onChange(of: model.epoch) { model.refresh() }
        .onDisappear { model.dismissOffers() }
    }

    // MARK: - Секції

    private var water: some View {
        section("ВОДА") {
            WTSettingRow("Денна мета", subtitle: model.goalStepLabel) {
                WTValueStepper(model.goalLabel, identifier: "settings.goal",
                               onDecrement: { model.stepGoal(up: false) },
                               onIncrement: { model.stepGoal(up: true) })
            }
            WTDivider()
            WTNavigationRow("Кнопки порцій", value: model.quickAmountsSummary, action: onOpenPortionButtons)
                .accessibilityIdentifier("settings.portions")
            WTDivider()
            // Повторний онбординг (WAT-56, SPEC-ONBOARDING §7.1): перерахувати норму, пройти пропущене.
            WTNavigationRow("Підібрати під себе", action: onOpenOnboarding)
                .accessibilityIdentifier("settings.onboarding")
        }
    }

    /// Система вимірювання (WAT-58) — ті самі рядки й тексти, що на кроці «Одиниці» онбордингу: людина
    /// впізнає вибір, а не вчиться другому. Окрема секція, а не рядок «Води»: вага й час — не про воду.
    private var units: some View {
        section("ОДИНИЦІ") {
            VStack(spacing: 16) {
                WTSegmentRow(unitRows[0].title, options: unitRows[0].options,
                             selection: VolumeUnit.allCases.firstIndex(of: model.volumeUnit) ?? 0,
                             identifierPrefix: "settings.units.volume") { index in
                    withAnimation(WTAnimation.fade) { model.setVolumeUnit(VolumeUnit.allCases[index]) }
                }
                WTSegmentRow(unitRows[1].title, options: unitRows[1].options,
                             selection: MassUnit.allCases.firstIndex(of: model.massUnit) ?? 0,
                             identifierPrefix: "settings.units.mass") { model.setMassUnit(MassUnit.allCases[$0]) }
                WTSegmentRow(unitRows[2].title, options: unitRows[2].options,
                             selection: TimeFormat.allCases.firstIndex(of: model.timeFormat) ?? 0,
                             identifierPrefix: "settings.units.time") { model.setTimeFormat(TimeFormat.allCases[$0]) }
            }
            .padding(.vertical, 10)
        }
    }

    private var unitRows: [OnboardingPresenter.UnitRow] { OnboardingPresenter.unitRows }

    private var rhythm: some View {
        section("РИТМ І НАГАДУВАННЯ") {
            // Не на екрані «Сповіщення»: перемикач стосується й гри, і звітів (SPEC-NOTIFICATIONS §28).
            WTSettingRow("Ритм дня",
                         subtitle: model.dayRhythmEnabled ? "Цілі на ранок, день і вечір" : "Просто норма за день") {
                WTToggle(isOn: dayRhythm).accessibilityIdentifier("settings.dayRhythm")
            }
            if model.offersIntervalReminders {
                WTNoticeBanner("Нагадування «за темпом» теж ділять день на частини",
                               actionTitle: "Рівні інтервали", identifier: "settings.intervalOffer") {
                    withAnimation(WTAnimation.sheet) { model.switchRemindersToInterval() }
                }
                .padding(.vertical, 6)
                .transition(.opacity)
            }
            WTDivider()
            WTNavigationRow("Нагадування", value: model.notificationsSummary, action: onOpenNotifications)
                .accessibilityIdentifier("settings.notifications")
        }
    }

    private var app: some View {
        section("ЗАСТОСУНОК") {
            WTSettingRow("Вібрація") {
                WTToggle(isOn: haptics).accessibilityIdentifier("settings.haptics")
            }
            WTDivider()
            // Три варіанти (WAT-66): з перемикача «Темна тема» до системної вже не повернутись.
            WTSegmentRow("Тема", options: SettingsModel.themeModes.map(SettingsModel.themeTitle),
                         selection: SettingsModel.themeModes.firstIndex(of: themeMode) ?? 0,
                         identifierPrefix: "settings.theme") { index in
                themeMode = SettingsModel.themeModes[index]
                model.setThemeMode(themeMode)
            }
            .padding(.vertical, 10)
            WTDivider()
            // Контекстний вхід у «Знання» (SPEC-LEARN §3.2) — історія «Перші кроки».
            WTNavigationRow("Як користуватися", action: { onOpenLearn("app.start") })
                .accessibilityIdentifier("settings.learn")
        }
    }

    /// Тимчасово (рішення від 19.10.2026): дизайн онбордингу до вибору остаточного в WAT-57 — тоді секція зникає.
    private var temporary: some View {
        section("ТИМЧАСОВО") {
            WTSegmentRow("Дизайн онбордингу", options: OnboardingDesign.allCases.map(\.title),
                         selection: OnboardingDesign.allCases.firstIndex(of: onboardingDesign) ?? 0,
                         identifierPrefix: "settings.onboardingDesign") { index in
                onboardingDesign = OnboardingDesign.allCases[index]
                OnboardingDesign.current = onboardingDesign
            }
            .padding(.vertical, 8)
        }
    }

    /// Режим розробника (WAT-68) — лише в DEBUG-збірці: дані для тестування повз правила гри.
    private var developer: some View {
        section("РОЗРОБНИК") {
            WTNavigationRow("Режим розробника", value: "DEBUG", action: onOpenDeveloper)
                .accessibilityIdentifier("settings.developer")
        }
    }

    // MARK: - Прив'язки

    private var dayRhythm: Binding<Bool> {
        Binding(get: { model.dayRhythmEnabled },
                set: { newValue in withAnimation(WTAnimation.sheet) { model.setDayRhythm(newValue) } })
    }

    /// Стан теми й вібрації живе в `RootView` — контейнер теми мусить перемалюватися одразу.
    private var haptics: Binding<Bool> {
        Binding(get: { hapticsEnabled },
                set: { hapticsEnabled = $0; model.setHaptics($0) })
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            WTSectionLabel(title)
            WTCard {
                VStack(alignment: .leading, spacing: 0) { content() }
            }
        }
    }
}
