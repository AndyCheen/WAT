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

/// Годинник зі зсувом — «машина часу» режиму розробника (WAT-68): час іде, як іде, але від іншої миті. Зсув
/// міняється на ходу, тож сервіси, що вже тримають цей годинник, бачать новий час з наступного читання.
public final class OffsetClock: Clock, @unchecked Sendable {
    private let base: Clock
    private let lock = NSLock()
    private var _offset: TimeInterval

    public init(base: Clock = SystemClock(), offset: TimeInterval = 0) {
        self.base = base
        self._offset = offset
    }

    public var offset: TimeInterval {
        get { lock.lock(); defer { lock.unlock() }; return _offset }
        set { lock.lock(); defer { lock.unlock() }; _offset = newValue }
    }

    public var now: Date { base.now.addingTimeInterval(offset) }
    public var timeZone: TimeZone { base.timeZone }
}

/// Фіксований час — для unit-тестів і UI-фікстур.
public final class FixedClock: Clock, @unchecked Sendable {
    private let lock = NSLock()
    private var _now: Date
    private var _timeZone: TimeZone

    public init(now: Date, timeZone: TimeZone = TimeZone(identifier: "Europe/Kyiv") ?? .current) {
        self._now = now
        self._timeZone = timeZone
    }

    public var now: Date {
        lock.lock(); defer { lock.unlock() }
        return _now
    }

    public var timeZone: TimeZone {
        lock.lock(); defer { lock.unlock() }
        return _timeZone
    }

    /// Переліт у інший пояс — для тестів доби й сповіщень (SPEC-NOTIFICATIONS §16.6).
    public func setTimeZone(_ zone: TimeZone) {
        lock.lock(); defer { lock.unlock() }
        _timeZone = zone
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
