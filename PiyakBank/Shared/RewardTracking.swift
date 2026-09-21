import Foundation
import Darwin

enum RewardClock {
    /// A boot-scoped value distinguishes restarts even when the new uptime has
    /// already exceeded the saved one. Never sent to Watch, exports or a server.
    static let bootSessionID: String = {
        var size = 0
        guard sysctlbyname("kern.bootsessionuuid", nil, &size, nil, 0) == 0, size > 1 else {
            return "process-" + UUID().uuidString
        }
        var value = [CChar](repeating: 0, count: size)
        guard sysctlbyname("kern.bootsessionuuid", &value, &size, nil, 0) == 0 else {
            return "process-" + UUID().uuidString
        }
        return String(cString: value)
    }()
    /// Unlike wall time, this clock cannot jump when Date & Time is changed.
    /// CLOCK_MONOTONIC_RAW also advances while the device is asleep.
    static func now() -> TimeInterval {
        Double(clock_gettime_nsec_np(CLOCK_MONOTONIC_RAW)) / 1_000_000_000
    }
}

struct RewardClockAnchor: Codable {
    var date: Date
    var tick: TimeInterval
    var bootSessionID: String?
}

/// Persisted separately from editable salary segments. No polling or background task
/// is required: checkpoints happen on lifecycle events and explicit timer actions.
struct RewardTracking: Codable {
    var intervals: [RewardInterval] = []
    var anchorDate: Date
    var anchorTick: TimeInterval
    var working: Bool
    var capturedSeconds: TimeInterval = 0
    var bootSessionID: String?
    static let maximumSessionSeconds: TimeInterval = 24 * 60 * 60

    init(date: Date, tick: TimeInterval, working: Bool, bootSessionID: String? = nil) {
        anchorDate = date
        anchorTick = tick
        self.working = working
        self.bootSessionID = bootSessionID
    }

    mutating func checkpoint(date: Date, tick: TimeInterval, working nextWorking: Bool, bootSessionID currentBoot: String? = nil) {
        let wallElapsed = date.timeIntervalSince(anchorDate)
        let elapsed = tick - anchorTick
        if bootSessionID == currentBoot, working, wallElapsed.isFinite, elapsed.isFinite, wallElapsed > 0, elapsed > 0 {
            // A forward clock jump cannot manufacture elapsed time. A restart or
            // backward jump cannot create a negative or oversized reward interval.
            let seconds = max(0, min(wallElapsed, elapsed,
                                    Self.maximumSessionSeconds - capturedSeconds))
            if seconds > 0 {
                let end = anchorDate.addingTimeInterval(seconds)
                if let last = intervals.last, last.end == anchorDate {
                    intervals[intervals.count - 1].end = end
                } else {
                    intervals.append(RewardInterval(start: anchorDate, end: end))
                }
                capturedSeconds += seconds
            }
        }
        anchorDate = date
        anchorTick = tick
        working = nextWorking
        bootSessionID = currentBoot
    }
}
