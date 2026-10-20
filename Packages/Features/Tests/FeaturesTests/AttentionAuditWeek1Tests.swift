import XCTest
import Core
@testable import Features

/// Аудит «звернень до уваги» першого тижня (AUDIT-ATTENTION-WEEK1.md, WAT-29). Не перевірка, а вимірювання:
/// друкує, що людина побачила й відчула за тиждень `FirstWeekSimulation`. Звичайний прогін пакетів його пропускає —
/// числа звіту тут не закріплені, і приглушення їх змінить. Межі досягнень тримає `AchievementBudgetTests`.
///
///     WT_AUDIT=1 WT_AUDIT_OUT=/tmp swift test --package-path Packages/Features --filter AttentionAuditWeek1Tests
///
/// `WT_AUDIT_OUT` — тека для `audit-<варіант>.txt` (`typical`, `explorer`, `diligent`, `no-followups`, `rarer`,
/// `weekend`, `quiet`); без неї звіт іде в stdout.
@MainActor
final class AttentionAuditWeek1Tests: XCTestCase {

    override func setUp() async throws {
        try await super.setUp()
        try XCTSkipUnless(ProcessInfo.processInfo.environment["WT_AUDIT"] == "1", "аудит — лише на вимогу")
    }

    func testWeekOneTypical() async throws {
        await audit(FirstWeekSimulation(FirstWeekSimulation.typicalWeek), "typical", title: "Типовий новачок")
    }

    func testWeekOneExplorer() async throws {
        await audit(FirstWeekSimulation(FirstWeekSimulation.explorerWeek(), explorer: true), "explorer", title: "Дослідник")
    }

    func testWeekOneDiligent() async throws {
        await audit(FirstWeekSimulation(FirstWeekSimulation.diligentWeek()), "diligent",
                    title: "Старанний: норма 7/7, рівно в ціль")
    }

    // Варіанти налаштувань, що вже є в застосунку, — щоб оцінити пропозиції щодо сповіщень числами.

    func testWeekOneWithoutFollowUps() async throws {
        let simulation = FirstWeekSimulation(FirstWeekSimulation.typicalWeek) { services in
            services.notifications.settings.followUpEnabled = false
        }
        await audit(simulation, "no-followups", title: "Без повторних нагадувань")
    }

    func testWeekOneRarer() async throws {
        let simulation = FirstWeekSimulation(FirstWeekSimulation.typicalWeek) { services in
            services.notifications.settings.reminderFrequency = .rarer
        }
        await audit(simulation, "rarer", title: "Частота «рідше»")
    }

    func testWeekOneWeekendSchedule() async throws {
        let simulation = FirstWeekSimulation(FirstWeekSimulation.typicalWeek) { services in
            services.profile.weekSchedule = FirstWeekSimulation.weekendLater
        }
        await audit(simulation, "weekend", title: "Окремий розклад вихідних 09:30–23:00")
    }

    func testWeekOneQuietCombo() async throws {
        let simulation = FirstWeekSimulation(FirstWeekSimulation.typicalWeek) { services in
            services.notifications.settings.followUpEnabled = false
            services.profile.weekSchedule = FirstWeekSimulation.weekendLater
        }
        await audit(simulation, "quiet", title: "Без повторних + розклад вихідних")
    }

    private func audit(_ simulation: FirstWeekSimulation, _ suffix: String, title: String) async {
        await simulation.run()
        let text = simulation.report(title: title)
        // stdout xctest буферизує впереміш із власними рядками — для читання краще файл.
        if let dir = ProcessInfo.processInfo.environment["WT_AUDIT_OUT"] {
            let url = URL(fileURLWithPath: dir).appendingPathComponent("audit-\(suffix).txt")
            try? text.write(to: url, atomically: true, encoding: .utf8)
        } else {
            print(text)
        }
    }
}
