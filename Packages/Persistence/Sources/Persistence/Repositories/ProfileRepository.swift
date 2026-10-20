import Foundation
import SwiftData
import Core

@MainActor
public protocol ProfileRepositoryProtocol: AnyObject {
    func profile() -> UserProfile
    func currentGoalMl(on day: DayKey) -> Int
    func goalRevisions() -> [GoalRevision]
    @discardableResult
    func setGoal(_ ml: Int, source: GoalSource, effectiveFrom day: DayKey, at date: Date) -> GoalRevision
    func quickAddPresets(_ place: PresetPlace) -> [QuickAddPreset]
    func updatePreset(_ preset: QuickAddPreset, amountMl: Int)
    func resetPresets(_ place: PresetPlace)
    func save()
}

@MainActor
public final class ProfileRepository: ProfileRepositoryProtocol {
    private let context: ModelContext

    public init(context: ModelContext) {
        self.context = context
    }

    public func profile() -> UserProfile {
        let existing = (try? context.fetch(FetchDescriptor<UserProfile>())) ?? []
        if let first = existing.first { return first }
        let created = UserProfile()
        context.insert(created)
        save()
        return created
    }

    /// Норма, що діяла на вказану добу: остання ревізія з `effectiveFrom <= day`.
    public func currentGoalMl(on day: DayKey) -> Int {
        let key = day.rawValue
        var descriptor = FetchDescriptor<GoalRevision>(
            predicate: #Predicate { $0.effectiveFromKey <= key },
            sortBy: [SortDescriptor(\.effectiveFromKey, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        if let revision = (try? context.fetch(descriptor))?.first {
            return revision.goalMl
        }
        return 2000
    }

    public func goalRevisions() -> [GoalRevision] {
        let descriptor = FetchDescriptor<GoalRevision>(
            sortBy: [SortDescriptor(\.effectiveFromKey, order: .reverse)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    @discardableResult
    public func setGoal(_ ml: Int, source: GoalSource, effectiveFrom day: DayKey, at date: Date) -> GoalRevision {
        let clamped = GoalRevision.clamp(ml)
        let key = day.rawValue
        let existing = (try? context.fetch(
            FetchDescriptor<GoalRevision>(predicate: #Predicate { $0.effectiveFromKey == key })
        ))?.first

        if let existing {
            existing.goalMl = clamped
            existing.sourceRaw = source.rawValue
            existing.createdAt = date
            save()
            return existing
        }

        let revision = GoalRevision(effectiveFromKey: key, goalMl: clamped, source: source, createdAt: date)
        context.insert(revision)
        save()
        return revision
    }

    /// Сід окремо на кожне місце: БД, де були лише кнопки головного, отримає підказки шторки.
    public func quickAddPresets(_ place: PresetPlace = .home) -> [QuickAddPreset] {
        let raw = place.rawValue
        let descriptor = FetchDescriptor<QuickAddPreset>(
            predicate: #Predicate { $0.placeRaw == raw },
            sortBy: [SortDescriptor(\.order)]
        )
        let existing = (try? context.fetch(descriptor)) ?? []
        if !existing.isEmpty { return existing }
        let created = place.defaults(for: profile().volumeUnit).enumerated().map { QuickAddPreset(place: place, order: $0, amountMl: $1) }
        created.forEach { context.insert($0) }
        save()
        return created
    }

    public func updatePreset(_ preset: QuickAddPreset, amountMl: Int) {
        preset.amountMl = Intake.clamp(amountMl)
        save()
    }

    public func resetPresets(_ place: PresetPlace) {
        for (preset, amount) in zip(quickAddPresets(place), place.defaults(for: profile().volumeUnit)) {
            preset.amountMl = amount
            preset.enabled = true
        }
        save()
    }

    public func save() {
        do { try context.save() } catch { AppLog.persistence.error("save: \(error)") }
    }
}
