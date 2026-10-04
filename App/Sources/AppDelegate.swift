import UIKit
import UserNotifications
import BackgroundTasks
import Features
import Notifications

/// Делегат застосунку — заради сповіщень і фонового оновлення.
///
/// Делегат центру виставляється в `didFinishLaunching`: інакше відповідь на дію, що запустила
/// застосунок, губиться (SPEC-NOTIFICATIONS §16.4).
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    static let refreshTaskId = "com.watertracker.app.refresh"

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        _ = AppContainer.services
        guard !AppContainer.launch.isUITest else { return true }
        UNUserNotificationCenter.current().delegate = self
        registerBackgroundRefresh()
        return true
    }

    // MARK: - UNUserNotificationCenterDelegate

    /// Застосунок відкритий: нагадування, ранкова склянка й вечірній підсумок не показуються —
    /// людина вже бачить кільце. Порятунок, повернення й відлуння — банером (§16.7).
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let identifier = notification.request.identifier
        switch NotificationService.presentation(forIdentifier: identifier) {
        case .suppress:
            Task { @MainActor in
                let services = AppContainer.services
                services.notifications.markSuppressed(identifier: identifier, at: services.calendar.now)
            }
            completionHandler([])
        case .banner:
            completionHandler([.banner, .list, .sound])
        }
    }

    /// Методи делегата приходять не обов'язково на головному потоці, а `UNNotificationResponse`
    /// не `Sendable` — тож спершу знімок простими значеннями, далі робота на `@MainActor`.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let request = response.notification.request
        var userInfo: [String: String] = [:]
        for (key, value) in request.content.userInfo {
            if let key = key as? String, let value = value as? String { userInfo[key] = value }
        }
        let info = NotificationResponseInfo(
            identifier: request.identifier, actionIdentifier: response.actionIdentifier, userInfo: userInfo
        )
        Task { @MainActor in
            await AppContainer.services.handleNotificationResponse(info)
            completionHandler()
        }
    }

    // MARK: - Фонове оновлення (§16.3)

    /// Лише бонус: план від нього не залежить — iOS запускає фонові задачі коли захоче.
    private func registerBackgroundRefresh() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.refreshTaskId, using: nil) { task in
            task.expirationHandler = { task.setTaskCompleted(success: false) }
            Task { @MainActor in
                await AppContainer.services.notifications.rescheduleNow()
                AppDelegate.scheduleBackgroundRefresh()
                task.setTaskCompleted(success: true)
            }
        }
    }

    @MainActor
    static func scheduleBackgroundRefresh() {
        guard !AppContainer.launch.isUITest else { return }
        let request = BGAppRefreshTaskRequest(identifier: refreshTaskId)
        request.earliestBeginDate = AppContainer.services.clock.now.addingTimeInterval(3 * 3600)
        try? BGTaskScheduler.shared.submit(request)
    }
}
