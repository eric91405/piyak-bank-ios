import Foundation
import UserNotifications

@MainActor
final class NotificationScheduler: SessionReminding {
    private let center = UNUserNotificationCenter.current()
    private var pendingUpdate: Task<Void, Never>?
    private let identifiers = (0..<48).map { "piyak.reminder.\($0)" }

    func requestAuth() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
    }

    func update(snapshot: SessionSnapshot, interval: ReminderInterval, enabled: Bool) {
        // Serialize cancellation and addition so an older asynchronous cancellation
        // cannot delete newly scheduled notifications after a quick pause/resume.
        let previous = pendingUpdate
        previous?.cancel()
        pendingUpdate = Task {
            await previous?.value
            guard !Task.isCancelled else { return }
            let old = await center.pendingNotificationRequests()
            center.removePendingNotificationRequests(withIdentifiers:
                old.map(\.identifier).filter { $0.hasPrefix("piyak.") })
            guard enabled, snapshot.isRunning, !snapshot.isPaused, !Task.isCancelled else { return }
            let settings = await center.notificationSettings()
            guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
            let now = Date()
            for index in 0..<48 {
                guard !Task.isCancelled else { return }
                let offset = Double((index + 1) * interval.rawValue * 60)
                guard offset <= 24 * 3600 else { break }
                let fire = now.addingTimeInterval(offset)
                let content = UNMutableNotificationContent()
                content.title = "삐약, 잠깐 쉬어 갈까요?"
                content.body = "이번 근무 예상 수익은 \(snapshot.amount(at: fire).won)이에요. 근무를 마쳤다면 종료해 주세요."
                content.sound = .default
                content.userInfo = ["deeplink": "piyakbank://home"]
                let request = UNNotificationRequest(identifier: identifiers[index], content: content,
                    trigger: UNTimeIntervalNotificationTrigger(timeInterval: offset, repeats: false))
                do { try await center.add(request) }
                catch { return } // Permission and delivery status are shown in Settings.
            }
        }
    }
}
