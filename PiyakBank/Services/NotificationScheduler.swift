import Foundation
import UserNotifications

@MainActor
final class NotificationScheduler: SessionReminding {
    private let center = UNUserNotificationCenter.current()
    private lazy var reconciler = ReminderReconciler(client: SystemReminderClient(center: center))

    func requestAuth() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
    }

    func update(snapshot: SessionSnapshot, interval: ReminderInterval, enabled: Bool) {
        reconciler.update(plan: ReminderPlan(snapshot: snapshot, intervalMinutes: interval.rawValue, enabled: enabled))
    }
}

@MainActor
private final class SystemReminderClient: ReminderNotificationClient {
    private let center: UNUserNotificationCenter
    init(center: UNUserNotificationCenter) { self.center = center }

    func pendingReminders() async -> [ReminderNotification] {
        let requests = await center.pendingNotificationRequests()
        return requests.map { request in
            let fireDate: Date?
            if let trigger = request.trigger as? UNCalendarNotificationTrigger {
                fireDate = trigger.nextTriggerDate()
            } else if let trigger = request.trigger as? UNTimeIntervalNotificationTrigger {
                fireDate = trigger.nextTriggerDate()
            } else {
                fireDate = nil
            }
            return ReminderNotification(identifier: request.identifier,
                fireDate: fireDate ?? .distantPast,
                title: request.content.title, body: request.content.body,
                deepLink: request.content.userInfo["deeplink"] as? String ?? "")
        }
    }

    func canSchedule() async -> Bool {
        let settings = await center.notificationSettings()
        return settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
    }

    func removeReminders(withIdentifiers identifiers: [String]) {
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    func addReminder(_ reminder: ReminderNotification) async throws {
        guard reminder.fireDate > Date() else { return }
        let content = UNMutableNotificationContent()
        content.title = reminder.title
        content.body = reminder.body
        content.sound = .default
        content.userInfo = ["deeplink": reminder.deepLink]
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let components = calendar.dateComponents([.calendar, .timeZone, .year, .month, .day, .hour, .minute, .second], from: reminder.fireDate)
        let request = UNNotificationRequest(identifier: reminder.identifier, content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false))
        try await center.add(request)
    }
}
