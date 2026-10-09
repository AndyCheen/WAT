import WidgetKit
import SwiftUI
import Core
import Widgets

/// Запис таймлайну: що малювати о `date`. `content == nil` — знімка ще немає, «Відкрий застосунок».
struct SnapshotEntry: TimelineEntry {
    let date: Date
    let content: WidgetContent?
    let relevance: TimelineEntryRelevance?
}

/// Таймлайн зі знімка застосунку (SPEC-WIDGETS §9.3). Час — `SystemClock` лише тут, на межі з WidgetKit:
/// уся логіка записів — чиста `WidgetTimeline` у пакеті, з тестами на фіксованих датах.
enum SnapshotTimeline {
    static func timeline(_ kind: WidgetKind) -> Timeline<SnapshotEntry> {
        let clock = SystemClock()
        let calendar = CalendarService(clock: clock)
        let now = clock.now
        let snapshot = WidgetSnapshotStore.shared.read()
        let pickerCloses = WidgetCustomPicker.shared.closesAt(kind, now: now)
        let dates = WidgetTimeline.dates(for: kind, snapshot: snapshot, from: now, calendar: calendar,
                                         pickerClosesAt: pickerCloses)
        let entries = dates.map { date in
            entry(snapshot, at: date, calendar: calendar, pickerOpen: pickerCloses.map { date < $0 } ?? false)
        }
        // Після останнього запису WidgetKit попросить новий таймлайн — знімок до того часу вже інший.
        return Timeline(entries: entries, policy: .after(dates.last ?? now.addingTimeInterval(3600)))
    }

    static func current(_ kind: WidgetKind) -> SnapshotEntry {
        let clock = SystemClock()
        let calendar = CalendarService(clock: clock)
        return entry(WidgetSnapshotStore.shared.read(), at: clock.now, calendar: calendar,
                     pickerOpen: WidgetCustomPicker.shared.isOpen(kind, at: clock.now))
    }

    /// Галерея віджетів системи й заглушка — типовий день о 13:25, а не порожній знімок: о пів на одинадцяту
    /// вечора галерея інакше показувала б «Добраніч» замість того, що віджет робить удень.
    static func sample() -> SnapshotEntry {
        let calendar = CalendarService(clock: SystemClock())
        let noon = WidgetTimeline.date(of: calendar.today, minute: 13 * 60 + 25, calendar: calendar) ?? calendar.now
        return entry(WidgetSnapshot.sample(at: noon, calendar: calendar), at: noon, calendar: calendar)
    }

    private static func entry(_ snapshot: WidgetSnapshot?, at date: Date, calendar: CalendarService,
                              pickerOpen: Bool = false) -> SnapshotEntry {
        guard let snapshot else { return SnapshotEntry(date: date, content: nil, relevance: nil) }
        let content = WidgetContent(snapshot: snapshot, at: date, calendar: calendar, customPickerOpen: pickerOpen)
        return SnapshotEntry(date: date, content: content,
                             relevance: TimelineEntryRelevance(score: WidgetTimeline.relevance(content.day)))
    }
}

struct SnapshotProvider: TimelineProvider {
    let kind: WidgetKind

    func placeholder(in context: Context) -> SnapshotEntry { SnapshotTimeline.sample() }

    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        completion(context.isPreview ? SnapshotTimeline.sample() : SnapshotTimeline.current(kind))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        completion(SnapshotTimeline.timeline(kind))
    }
}

/// Спільна обгортка в'юшки: тема з `colorScheme`, кнопки — інтентами, порожній стан без знімка.
struct WidgetEntryView<Content: View>: View {
    let entry: SnapshotEntry
    @ViewBuilder let content: (WidgetContent) -> Content

    var body: some View {
        Group {
            if let widgetContent = entry.content {
                content(widgetContent)
            } else {
                WidgetEmptyView()
            }
        }
        .wtWidgetTheme()
        .environment(\.widgetActionButton, .intents)
    }
}

extension WidgetActionButtonFactory {
    /// Кнопки віджетів — `Button(intent:)`: порція виконується в процесі застосунку (`WidgetIntents.swift`).
    static let intents = WidgetActionButtonFactory { action, label in
        switch action {
        case let .add(ml, _):
            AnyView(Button(intent: AddWaterWidgetIntent(ml: ml)) { label }.buttonStyle(.plain))
        case let .undo(intakeId):
            AnyView(Button(intent: UndoWaterWidgetIntent(intakeId: intakeId)) { label }.buttonStyle(.plain))
        case let .showCustomPicker(kind):
            AnyView(Button(intent: CustomPickerIntent(kind: kind, open: true)) { label }.buttonStyle(.plain))
        case let .hideCustomPicker(kind):
            AnyView(Button(intent: CustomPickerIntent(kind: kind, open: false)) { label }.buttonStyle(.plain))
        }
    }
}
