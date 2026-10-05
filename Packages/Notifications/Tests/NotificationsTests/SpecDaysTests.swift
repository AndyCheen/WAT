import XCTest
import Core
import Persistence
@testable import Notifications

/// Чотири дні з SPEC-NOTIFICATIONS §6.1 — дослівно, з очікуваними часами (§16.11).
/// Норма 2000 мл, 08:00–22:00, порція 250 мл; рахуються лише сповіщення типу 1.
///
/// Чекпоінти частин доби (етап B) тут вимкнені: аналіз §6.1 порівнює алгоритми нагадувань
/// самі по собі. Той самий день «забудька» з усіма типами — §6.3, `CheckpointTests`.
final class SpecDaysTests: XCTestCase {
    private let simulator: DaySimulator = {
        var simulator = DaySimulator()
        simulator.preferences.checkpointsEnabled = false
        return simulator
    }()

    /// «На темпі»: 250 мл кожні 1 год 45 хв, норму закрито → жодного нагадування (критерій §19.3).
    func testOnPaceDayHasNoReminders() {
        let day = (0..<8).map { step -> (Int, Int, Int) in
            let minutes = 8 * 60 + step * 105
            return (minutes / 60, minutes % 60, 250)
        }
        XCTAssertEqual(simulator.reminders(intakes: intakes(day)), [])
    }

    /// «Забудько»: порції о 08:30, 13:00, 15:00, 18:30, разом 1,05 л.
    func testForgetfulDay() {
        let day = intakes([(8, 30, 250), (13, 0, 250), (15, 0, 300), (18, 30, 250)])
        XCTAssertEqual(simulator.reminders(intakes: day), ["11:09", "11:39", "14:37", "16:37", "17:07"])
    }

    /// «Подорож»: жодної порції → 4 нагадування від підйому, далі тиша (критерій §19.4).
    func testTravelDay() {
        XCTAssertEqual(simulator.reminders(intakes: []), ["09:42", "10:12", "12:12", "12:42"])
    }

    /// «Нарада 9–12, далі регулярно, 1,85 л». ТЗ не дає порцій дня — фікстура підібрана так,
    /// що виходить описане: 4 нагадування, два з них на нараді.
    private let meeting = intakes([
        (8, 30, 250), (12, 10, 300), (13, 30, 250), (15, 30, 250), (17, 0, 250), (19, 30, 300), (20, 30, 250)
    ])

    func testMeetingDay() {
        XCTAssertEqual(simulator.reminders(intakes: meeting), ["11:09", "11:39", "15:07", "19:12"])
    }

    /// Те саме з тихим періодом 9–12: два нагадування наради зсуваються на 12:00 і зливаються в одне.
    func testMeetingDayWithQuietPeriodMergesAtNoon() {
        var simulator = simulator
        simulator.preferences.quietWindows = [QuietWindow(fromMinutes: 9 * 60, toMinutes: 12 * 60)]
        XCTAssertEqual(simulator.reminders(intakes: meeting), ["12:00", "15:07", "19:12"])
    }
}
