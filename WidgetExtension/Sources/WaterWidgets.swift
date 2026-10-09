import WidgetKit
import SwiftUI
import Widgets

/// Віджети «Води» (WAT-30, SPEC-WIDGETS §3). Ідентифікатори `kind` — з `WidgetKind`: їх не можна міняти,
/// інакше вже поставлені віджети зникнуть із домашнього екрана.
@main
struct WaterWidgets: WidgetBundle {
    var body: some Widget {
        TodayWidget()
        DayPartWidget()
        RhythmWidget()
        ReserveWidget()
        QuickAddWidget()
        ButtonWidget()
        ProgressWidget()
        OverviewWidget()
        if #available(iOS 18.0, *) {
            WaterControl()
        }
    }
}

struct TodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetKind.today.identifier, provider: SnapshotProvider(kind: .today)) { entry in
            FamilyView(entry: entry) { content, family in
                switch family {
                case .accessoryCircular: TodayCircularView(content)
                case .accessoryInline: TodayInlineView(content)
                default: TodayWidgetView(content)
                }
            }
            .widgetURL(WidgetLink.home.url)
        }
        .configurationDisplayName("Сьогодні")
        .description("Кільце дня: скільки випито й скільки лишилось.")
        .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryInline])
    }
}

struct DayPartWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetKind.dayPart.identifier, provider: SnapshotProvider(kind: .dayPart)) { entry in
            FamilyView(entry: entry) { content, family in
                if family == .accessoryRectangular {
                    DayPartRectangularView(content)
                } else {
                    DayPartWidgetView(content)
                }
            }
            .widgetURL(WidgetLink.home.url)
        }
        .configurationDisplayName("Частина доби")
        .description("Ціль поточної частини доби й скільки часу на неї лишилось.")
        .supportedFamilies([.systemSmall, .accessoryRectangular])
    }
}

struct RhythmWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetKind.rhythm.identifier, provider: SnapshotProvider(kind: .rhythm)) { entry in
            WidgetEntryView(entry: entry) { RhythmWidgetView($0) }
                .widgetURL(WidgetLink.stats.url)
        }
        .configurationDisplayName("Ритм дня")
        .description("Усі частини доби: що випито, яка ціль і чи встигаєш за темпом.")
        .supportedFamilies([.systemMedium])
    }
}

struct ReserveWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: WidgetKind.reserve.identifier, intent: ReserveConfigurationIntent.self,
                               provider: ConfiguredProvider<ReserveConfigurationIntent>(kind: .reserve)) { entry in
            FamilyView(entry: entry.base) { content, family in
                switch family {
                case .accessoryCircular: ReserveCircularView(content)
                case .systemMedium: ReserveWidgetView(content, style: entry.configuration.style.style, isMedium: true)
                default: ReserveWidgetView(content, style: entry.configuration.style.style, isMedium: false)
                }
            }
            .widgetURL(WidgetLink.home.url)
        }
        .configurationDisplayName("Запас води")
        .description("Рівень спадає до нуля за 10 хвилин до нагадування — випий, і він підніметься.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular])
    }
}

struct QuickAddWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetKind.quickAdd.identifier, provider: SnapshotProvider(kind: .quickAdd)) { entry in
            WidgetEntryView(entry: entry) { QuickAddWidgetView($0) }
                .widgetURL(WidgetLink.home.url)
        }
        .configurationDisplayName("Швидке додавання")
        .description("Кнопки з головного — порція одним дотиком.")
        .supportedFamilies([.systemMedium])
    }
}

struct ButtonWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: WidgetKind.button.identifier, intent: ButtonConfigurationIntent.self,
                               provider: ConfiguredProvider<ButtonConfigurationIntent>(kind: .button)) { entry in
            FamilyView(entry: entry.base) { content, family in
                let snapshot = content.snapshot
                let first = entry.configuration.first?.milliliters(in: snapshot) ?? snapshot.glassMl
                if family == .accessoryCircular {
                    ButtonCircularView(ml: first)
                } else {
                    ButtonWidgetView(content, first: first, second: entry.configuration.second?.milliliters(in: snapshot))
                }
            }
            .widgetURL(WidgetLink.home.url)
        }
        .configurationDisplayName("Кнопка")
        .description("Одна чи дві кнопки зі своїм об'ємом — змінюється в налаштуваннях віджета.")
        .supportedFamilies([.systemSmall, .accessoryCircular])
    }
}

struct ProgressWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetKind.progress.identifier, provider: SnapshotProvider(kind: .progress)) { entry in
            WidgetEntryView(entry: entry) { ProgressWidgetView($0) }
                .widgetURL(WidgetLink.progress.url)
        }
        .configurationDisplayName("Прогрес")
        .description("Рівень, серія й завдання дня та тижня.")
        .supportedFamilies([.systemMedium])
    }
}

struct OverviewWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetKind.overview.identifier, provider: SnapshotProvider(kind: .overview)) { entry in
            WidgetEntryView(entry: entry) { OverviewWidgetView($0) }
                .widgetURL(WidgetLink.home.url)
        }
        .configurationDisplayName("Огляд дня")
        .description("Сума дня, серія, рівень, ритм дня й кнопки — усе в одному.")
        .supportedFamilies([.systemLarge])
    }
}

/// Обгортка, що знає розмір віджета: на екрані блокування — свої в'юшки.
private struct FamilyView<Content: View>: View {
    @Environment(\.widgetFamily) private var family
    let entry: SnapshotEntry
    @ViewBuilder let content: (WidgetContent, WidgetFamily) -> Content

    var body: some View {
        WidgetEntryView(entry: entry) { content($0, family) }
    }
}
