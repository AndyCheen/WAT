import SwiftUI
import Core
import Persistence
import DesignSystem
import Notifications

/// DEBUG-екран «План сповіщень»: усе заплановане з часами, причому до того, як iOS щось
/// доставить, — для ручної перевірки й як джерело даних для e2e (SPEC-NOTIFICATIONS §16.11).
struct NotificationPlanScreen: View {
    @Environment(\.wtTheme) private var theme
    private let services: AppServices
    private let onBack: () -> Void

    init(services: AppServices, onBack: @escaping () -> Void) {
        self.services = services
        self.onBack = onBack
    }

    private var plan: NotificationPlan { services.notifications.lastPlan }

    var body: some View {
        ZStack {
            theme.screen.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: WTSpacing.cardGap) {
                    WTNavBar(title: "План сповіщень", onBack: onBack)
                    WTCard {
                        VStack(alignment: .leading, spacing: 6) {
                            line("Дозвіл", authorization)
                            line("Типова порція P", "\(plan.typicalPortionMl) мл")
                            line("Остання дія", plan.lastActionDay?.rawValue ?? "—")
                            line("Пауза", services.notifications.isPaused(at: services.calendar.now) ? "до 00:00" : "ні")
                            line("Заплановано", "\(plan.items.count)")
                            HStack {
                                WTSectionAction("Перепланувати") { services.notifications.setNeedsReschedule() }
                                    .accessibilityIdentifier("plan.reschedule")
                                Spacer()
                                WTSectionAction("Тестове за 5 с") {
                                    Task { await services.notifications.scheduleTestReminder() }
                                }
                                .accessibilityIdentifier("plan.test")
                            }
                            .padding(.top, 6)
                        }
                    }
                    ForEach(plan.items) { item in
                        WTCard {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("\(stamp(item.fireAt)) · \(item.type.key) · \(item.slot)")
                                    .font(WTFont.text(13, .heavy))
                                    .foregroundStyle(theme.accent)
                                    .accessibilityIdentifier("plan.row.\(item.id)")
                                Text(item.title)
                                    .font(WTFont.text(16, .bold))
                                    .foregroundStyle(theme.textPrimary)
                                Text(item.body)
                                    .font(WTFont.text(14, .semibold))
                                    .foregroundStyle(theme.textMuted)
                            }
                        }
                    }
                }
                .wtScreenTopPadding()
                .padding(.horizontal, WTSpacing.screenSide)
                .padding(.bottom, WTSpacing.screenBottom)
                .wtNoTopOverscroll()
            }
        }
    }

    private var authorization: String {
        switch services.notifications.authorization {
        case .authorized: return "є"
        case .denied: return "відмовлено"
        case .notDetermined: return "ще не питали"
        case nil: return "…"
        }
    }

    private func line(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).font(WTFont.text(14, .bold)).foregroundStyle(theme.textMuted)
            Spacer()
            Text(value).font(WTFont.text(14, .bold)).foregroundStyle(theme.textPrimary)
        }
    }

    private func stamp(_ date: Date) -> String {
        let calendar = services.calendar.calendar
        let weekday = (calendar.component(.weekday, from: date) + 5) % 7
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%@ %02d:%02d", CalendarService.weekdayLabels[weekday], parts.hour ?? 0, parts.minute ?? 0)
    }
}
