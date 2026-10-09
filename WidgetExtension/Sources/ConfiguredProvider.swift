import WidgetKit
import AppIntents
import Widgets

/// Запис віджета з налаштуванням: таймлайн той самий, що в простих, налаштування — поруч.
struct ConfiguredEntry<Intent: WidgetConfigurationIntent>: TimelineEntry {
    let base: SnapshotEntry
    let configuration: Intent

    var date: Date { base.date }
    var relevance: TimelineEntryRelevance? { base.relevance }
}

struct ConfiguredProvider<Intent: WidgetConfigurationIntent>: AppIntentTimelineProvider {
    let kind: WidgetKind

    func placeholder(in context: Context) -> ConfiguredEntry<Intent> {
        ConfiguredEntry(base: SnapshotTimeline.sample(), configuration: Intent())
    }

    func snapshot(for configuration: Intent, in context: Context) async -> ConfiguredEntry<Intent> {
        ConfiguredEntry(base: context.isPreview ? SnapshotTimeline.sample() : SnapshotTimeline.current(kind),
                        configuration: configuration)
    }

    func timeline(for configuration: Intent, in context: Context) async -> Timeline<ConfiguredEntry<Intent>> {
        let timeline = SnapshotTimeline.timeline(kind)
        return Timeline(entries: timeline.entries.map { ConfiguredEntry(base: $0, configuration: configuration) },
                        policy: timeline.policy)
    }
}
