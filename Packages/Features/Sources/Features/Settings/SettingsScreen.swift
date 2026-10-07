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

    public init(
        services: AppServices,
        themeMode: Binding<ThemeMode>,
        hapticsEnabled: Binding<Bool>,
        onBack: @escaping () -> Void,
        onOpenNotifications: @escaping () -> Void
    ) {
        _model = State(initialValue: SettingsModel(services: services))
        _themeMode = themeMode
        _hapticsEnabled = hapticsEnabled
        self.onBack = onBack
        self.onOpenNotifications = onOpenNotifications
    }

    public var body: some View {
        ZStack {
            theme.screen.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: WTSpacing.cardGap) {
                    WTNavBar(title: "Налаштування", onBack: onBack)
                    water
                    rhythm
                    app
                }
                .wtScreenTopPadding()
                .padding(.horizontal, WTSpacing.screenSide)
                .padding(.bottom, WTSpacing.screenBottom)
                .wtNoTopOverscroll()
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .onAppear { model.refresh() }
        .onDisappear { model.dismissOffers() }
    }

    // MARK: - Секції

    private var water: some View {
        section("ВОДА") {
            WTSettingRow("Денна мета", subtitle: "Крок — 250 мл") {
                WTValueStepper(model.goalLabel, identifier: "settings.goal",
                               onDecrement: { model.changeGoal(by: -250) },
                               onIncrement: { model.changeGoal(by: 250) })
            }
        }
    }

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
            WTSettingRow("Темна тема") {
                WTToggle(isOn: isDark).accessibilityIdentifier("settings.theme")
            }
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

    private var isDark: Binding<Bool> {
        Binding(get: { themeMode == .dark },
                set: { themeMode = $0 ? .dark : .light; model.setThemeMode(themeMode) })
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
