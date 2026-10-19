import Foundation
import SwiftData

/// Прогрес однієї історії розділу «Знання» (SPEC-LEARN §6). Рядок з'являється, щойно історію побачили в
/// бібліотеці: історія без рядка — нова, з оновлення, і для неї горить крапка «нове» на кнопці головного.
@Model
public final class LearnProgress {
    @Attribute(.unique) public var storyId: String = ""
    /// Коли історію вперше показала бібліотека — для крапки «нове».
    public var seenAt: Date = Date.distantPast
    /// Слайд, на якому людина зупинилась: незакінчена історія відкривається з нього.
    public var lastSlide: Int = 0
    /// Коли дочитано до фінішу; `nil` — ще ні. Повторне читання дату не переписує.
    public var completedAt: Date?

    public init(storyId: String, seenAt: Date, lastSlide: Int = 0, completedAt: Date? = nil) {
        self.storyId = storyId
        self.seenAt = seenAt
        self.lastSlide = lastSlide
        self.completedAt = completedAt
    }

    public var isCompleted: Bool { completedAt != nil }
}
