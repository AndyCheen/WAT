import Foundation
import OSLog

/// Тонка обгортка над OSLog, щоб модулі не тягли залежність від конкретного бекенду.
public enum AppLog {
    private static let subsystem = "com.watertracker.app"

    public static let persistence = Logger(subsystem: subsystem, category: "persistence")
    public static let metrics = Logger(subsystem: subsystem, category: "metrics")
    public static let hydration = Logger(subsystem: subsystem, category: "hydration")
    public static let gamification = Logger(subsystem: subsystem, category: "gamification")
    public static let ui = Logger(subsystem: subsystem, category: "ui")
}
