import Foundation

/// A platform-independent description of one local notification. The system's
/// pending requests, rather than an optimistic in-memory flag, are authoritative.
struct ReminderNotification: Equatable, Sendable {
    static let identifierPrefix = "piyak.reminder."

    static func owns(identifier: String) -> Bool {
        if identifier.hasPrefix(identifierPrefix) { return true }
        // Earlier releases used piyak.<sessionID>.periodic.<index> and
        // piyak.<sessionID>.milestone.<amount>. Reconcile these on every pass,
        // including disabling reminders, without claiming all piyak.* requests.
        let parts = identifier.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4, parts[0] == "piyak", !parts[1].isEmpty,
              parts[2] == "periodic" || parts[2] == "milestone",
              !parts[3].isEmpty else { return false }
        return parts[3].utf8.allSatisfy { $0 >= 48 && $0 <= 57 }
            && UInt(parts[3]) != nil
    }

    var identifier: String
    var fireDate: Date
    var title: String
    var body: String
    var deepLink: String

    func matches(_ other: Self) -> Bool {
        identifier == other.identifier && title == other.title && body == other.body
            && deepLink == other.deepLink && abs(fireDate.timeIntervalSince(other.fireDate)) < 1
    }
}

struct ReminderPlan: Sendable {
    static let maximumPendingCount = 48
    static let schedulingHorizon: TimeInterval = 24 * 60 * 60
    private let snapshot: SessionSnapshot
    private let intervalSeconds: TimeInterval
    private let anchor: Date
    private let identifierBase: String

    init?(snapshot: SessionSnapshot, intervalMinutes: Int, enabled: Bool) {
        guard enabled, snapshot.isRunning, !snapshot.isPaused,
              let sessionID = snapshot.sessionId, intervalMinutes > 0,
              let start = snapshot.segments?.last?.start ?? snapshot.startedAt,
              start.timeIntervalSince1970.isFinite,
              start >= .distantPast, start <= .distantFuture else { return nil }
        self.snapshot = snapshot
        self.intervalSeconds = Double(intervalMinutes) * 60
        // Calendar notifications have one-second precision. Rounding the anchor
        // once keeps the same due dates across foregrounds and process restarts.
        self.anchor = Date(timeIntervalSince1970: start.timeIntervalSince1970.rounded(.up))
        self.identifierBase = ReminderNotification.identifierPrefix
            + "\(sessionID).\(Int64(anchor.timeIntervalSince1970)).\(intervalMinutes)."
    }

    func notifications(after now: Date) -> [ReminderNotification] {
        guard now.timeIntervalSince1970.isFinite,
              now >= .distantPast, now <= .distantFuture else { return [] }
        let elapsed = now.timeIntervalSince(anchor)
        let firstIndex = max(1, Int(floor(elapsed / intervalSeconds)) + 1)
        let horizon = now.addingTimeInterval(Self.schedulingHorizon)
        var result: [ReminderNotification] = []
        for offset in 0..<Self.maximumPendingCount {
            let index = firstIndex + offset
            let fire = anchor.addingTimeInterval(Double(index) * intervalSeconds)
            guard fire <= horizon else { break }
            result.append(ReminderNotification(identifier: identifierBase + String(index),
                fireDate: fire, title: "삐약, 잠깐 쉬어 갈까요?",
                body: "계속 근무 중이라면 이번 근무는 약 \(snapshot.amount(at: fire).won)이에요. 이미 마쳤다면 앱에서 종료해 주세요.",
                deepLink: "piyakbank://home"))
        }
        return result
    }
}

@MainActor
protocol ReminderNotificationClient: AnyObject {
    func pendingReminders() async -> [ReminderNotification]
    func canSchedule() async -> Bool
    func removeReminders(withIdentifiers identifiers: [String])
    func addReminder(_ reminder: ReminderNotification) async throws
}

/// Only one system mutation sequence runs at a time. A cancelled add may still
/// finish in the notification service; the next pass waits, then reconciles it.
@MainActor
final class ReminderReconciler {
    private let client: any ReminderNotificationClient
    private let now: () -> Date
    private var pendingUpdate: Task<Void, Never>?

    init(client: any ReminderNotificationClient, now: @escaping () -> Date = Date.init) {
        self.client = client
        self.now = now
    }

    func update(plan: ReminderPlan?) {
        let previous = pendingUpdate
        previous?.cancel()
        pendingUpdate = Task {
            await previous?.value
            guard !Task.isCancelled else { return }
            let pending = await client.pendingReminders()
            guard !Task.isCancelled else { return }
            let authorized: Bool
            if plan == nil { authorized = false }
            else { authorized = await client.canSchedule() }
            guard !Task.isCancelled else { return }
            let desired = authorized ? (plan?.notifications(after: now()) ?? []) : []
            let desiredByID = Dictionary(uniqueKeysWithValues: desired.map { ($0.identifier, $0) })
            let owned = pending.filter { ReminderNotification.owns(identifier: $0.identifier) }
            var matchingIDs: Set<String> = []
            var removedIDs: [String] = []
            for old in owned {
                if let expected = desiredByID[old.identifier], old.matches(expected) {
                    matchingIDs.insert(old.identifier)
                } else {
                    removedIDs.append(old.identifier)
                }
            }
            if !removedIDs.isEmpty { client.removeReminders(withIdentifiers: removedIDs) }
            for reminder in desired where !matchingIDs.contains(reminder.identifier) {
                guard !Task.isCancelled else { return }
                do { try await client.addReminder(reminder) }
                catch { return }
                // Do not cache success: a later foreground retries missing requests,
                // including partial failures, permission recovery and an empty queue.
            }
        }
    }

    func waitForPendingUpdate() async {
        await pendingUpdate?.value
    }
}
