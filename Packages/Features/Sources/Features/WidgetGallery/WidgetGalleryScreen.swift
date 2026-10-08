import SwiftUI
import Core
import DesignSystem
import Widgets

/// DEBUG-екран «Галерея віджетів» (`--start-screen widgets`): усі віджети в системних розмірах на живих даних.
///
/// Домашній екран у XCUITest нестабільний, а WidgetKit малює в окремому процесі, — тож e2e і швидка
/// перевірка вигляду йдуть тут. В'юшки ті самі, що в розширенні; кнопки замість інтентів кличуть
/// `AppServices.perform(_:)` напряму — той самий шлях, що й `LiveActivityIntent` у процесі застосунку.
struct WidgetGalleryScreen: View {
    @Environment(\.wtTheme) private var theme
    private let services: AppServices
    private let onBack: () -> Void

    init(services: AppServices, onBack: @escaping () -> Void) {
        self.services = services
        self.onBack = onBack
    }

    var body: some View {
        // Порція чи перепланування — нова доба на віджетах, як після нового знімка.
        let _ = (services.epoch, services.notifications.revision)
        let content = WidgetContent(snapshot: services.makeWidgetSnapshot(plan: services.notifications.lastPlan),
                                    at: services.calendar.now, calendar: services.calendar)
        ZStack {
            theme.screen.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: WTSpacing.cardGap) {
                    WTNavBar(title: "Віджети", onBack: onBack)
                    item("Сьогодні", id: "today", size: WidgetMetrics.small) { TodayWidgetView(content) }
                    item("Частина доби", id: "dayPart", size: WidgetMetrics.small) { DayPartWidgetView(content) }
                    item("Ритм дня", id: "rhythm", size: WidgetMetrics.medium) { RhythmWidgetView(content) }
                    item("Запас води · Вода", id: "reserve.water", size: WidgetMetrics.medium) {
                        ReserveWidgetView(content, style: .water, isMedium: true)
                    }
                    item("Запас води · Колба", id: "reserve.flask", size: WidgetMetrics.small) {
                        ReserveWidgetView(content, style: .flask, isMedium: false)
                    }
                    item("Швидке додавання", id: "quickAdd", size: WidgetMetrics.medium) { QuickAddWidgetView(content) }
                    item("Кнопка", id: "button", size: WidgetMetrics.small) {
                        ButtonWidgetView(content, first: content.snapshot.glassMl, second: nil)
                    }
                    item("Прогрес", id: "progress", size: WidgetMetrics.medium) { ProgressWidgetView(content) }
                    item("Огляд дня", id: "overview", size: WidgetMetrics.large) { OverviewWidgetView(content) }
                    lockScreen(content)
                }
                .padding(.horizontal, WTSpacing.screenSide)
                .padding(.bottom, WTSpacing.screenBottom)
            }
        }
        .environment(\.isWidgetGallery, true)
        .environment(\.widgetActionButton, WidgetActionButtonFactory { [services] action, label in
            AnyView(Button { Task { await services.perform(action) } } label: { label }
                .buttonStyle(WTPressStyle())
                .accessibilityIdentifier(Self.identifier(action)))
        })
    }

    private func item<V: View>(_ title: String, id: String, size: CGSize, @ViewBuilder view: () -> V) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(WTFont.text(13, .black))
                .foregroundStyle(theme.textMuted)
                .accessibilityIdentifier("widgetGallery.title.\(id)")
            view()
                .frame(width: size.width, height: size.height)
                .wtShadow(.card)
        }
    }

    /// Екран блокування — на темному склі, як його малює система.
    private func lockScreen(_ content: WidgetContent) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Екран блокування")
                .font(WTFont.text(13, .black))
                .foregroundStyle(theme.textMuted)
            VStack(alignment: .leading, spacing: 12) {
                TodayInlineView(content)
                HStack(spacing: 12) {
                    DayPartRectangularView(content).frame(width: 158, height: 72)
                    TodayCircularView(content).frame(width: 72, height: 72)
                    ReserveCircularView(content).frame(width: 72, height: 72)
                }
                ButtonCircularView(ml: content.snapshot.glassMl).frame(width: 72, height: 72)
            }
            .foregroundStyle(.white)
            .padding(16)
            .background(LinearGradient(colors: [Color(hex: "#3e5f8f"), Color(hex: "#1f2f52")],
                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: RoundedRectangle(cornerRadius: WTRadius.card, style: .continuous))
            .environment(\.colorScheme, .dark)
        }
    }

    static func identifier(_ action: WidgetAction) -> String {
        switch action {
        case let .add(ml, _): return "widget.add.\(ml)"
        case .undo: return "widget.undo"
        }
    }
}
