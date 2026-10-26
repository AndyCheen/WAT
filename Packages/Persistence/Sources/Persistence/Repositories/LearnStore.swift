import Foundation
import SwiftData
import Core

/// Прогрес читання історій «Знань» (SPEC-LEARN §6).
///
/// Рядки кешуються словником: бібліотека читає всі історії на кожне `reload()`, а `@Attribute(.unique)` у
/// SwiftData при повторній вставці мовчки робить upsert — рядок завжди спершу шукається тут.
@MainActor
public final class LearnStore {
    private let context: ModelContext
    private var cache: [String: LearnProgress]?

    public init(context: ModelContext) {
        self.context = context
    }

    public func progress(_ storyId: String) -> LearnProgress? {
        loaded()[storyId]
    }

    /// Чи бачила бібліотека хоч одну історію — до першого відкриття розділу крапка «нове» горить завжди.
    public var hasVisited: Bool { !loaded().isEmpty }

    /// Бібліотеку відкрито: усі показані історії стають «баченими».
    public func markSeen(_ storyIds: [String], at date: Date) {
        var changed = false
        for id in storyIds where loaded()[id] == nil {
            insert(LearnProgress(storyId: id, seenAt: date))
            changed = true
        }
        if changed { save() }
    }

    /// Людина перегорнула слайд. Історію могли відкрити повз бібліотеку (контекстний вхід) — тоді рядок
    /// з'являється тут і вона теж перестає бути новою.
    public func saveSlide(_ slide: Int, of storyId: String, at date: Date) {
        let row = row(storyId, at: date)
        guard row.lastSlide != slide else { return }
        row.lastSlide = slide
        save()
    }

    /// Дочитано до фінішу. Повертає `true` лише першого разу.
    @discardableResult
    public func complete(_ storyId: String, at date: Date) -> Bool {
        let row = row(storyId, at: date)
        row.lastSlide = 0
        let isFirst = row.completedAt == nil
        if isFirst { row.completedAt = date }
        save()
        return isFirst
    }

    private func row(_ storyId: String, at date: Date) -> LearnProgress {
        if let existing = loaded()[storyId] { return existing }
        let row = LearnProgress(storyId: storyId, seenAt: date)
        insert(row)
        return row
    }

    private func insert(_ row: LearnProgress) {
        context.insert(row)
        var cache = loaded()
        cache[row.storyId] = row
        self.cache = cache
    }

    private func loaded() -> [String: LearnProgress] {
        if let cache { return cache }
        let rows = (try? context.fetch(FetchDescriptor<LearnProgress>())) ?? []
        let cache = Dictionary(rows.map { ($0.storyId, $0) }, uniquingKeysWith: { first, _ in first })
        self.cache = cache
        return cache
    }

    private func save() {
        context.saveLoggingErrors("learn save")
    }
}
