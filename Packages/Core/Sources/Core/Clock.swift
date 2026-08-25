import Foundation

/// Єдине джерело часу в застосунку.
///
/// Жоден модуль не викликає `Date()` напряму — інакше тести на стріки, ролловер дня
/// й добові розрізи стають недетермінованими (див. PLAN.md §1).
public protocol Clock: Sendable {
    var now: Date { get }
    var timeZone: TimeZone { get }
}

public struct SystemClock: Clock {
    public init() {}
    public var now: Date { Date() }
    public var timeZone: TimeZone { .current }
}

/// Фіксований час — для unit-тестів і UI-фікстур.
public final class FixedClock: Clock, @unchecked Sendable {
    private let lock = NSLock()
    private var _now: Date
    public let timeZone: TimeZone

    public init(now: Date, timeZone: TimeZone = TimeZone(identifier: "Europe/Kyiv") ?? .current) {
        self._now = now
        self.timeZone = timeZone
    }

    public var now: Date {
        lock.lock(); defer { lock.unlock() }
        return _now
    }

    public func set(_ date: Date) {
        lock.lock(); defer { lock.unlock() }
        _now = date
    }

    public func advance(by interval: TimeInterval) {
        lock.lock(); defer { lock.unlock() }
        _now = _now.addingTimeInterval(interval)
    }
}
