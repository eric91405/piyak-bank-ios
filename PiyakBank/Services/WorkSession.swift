import Foundation
import SwiftData

// Preserve model/property names for in-place migration of existing stores.
@Model
final class WorkSession {
    @Attribute(.unique) var id: String
    var startedAt: Date
    var endedAt: Date?
    var segmentsData: Data
    var isActive: Bool
    /// Optional for lightweight migration. Historical/manual pay records have no timer proof.
    var rewardTrackingData: Data?

    // Decoding is not free and list views read `segments` many times per frame.
    // The cache is keyed by the stored blob, so any write — including a rollback
    // that restores an older blob — invalidates it without extra bookkeeping.
    @Transient private var cachedSegmentsData: Data?
    @Transient private var cachedSegments: [WageSegment]?

    var segments: [WageSegment] {
        get { (try? decodedSegments()) ?? [] }
        set {
            // Never replace valid data with an empty blob if encoding fails.
            if let data = try? JSONEncoder().encode(newValue) {
                segmentsData = data
                cachedSegmentsData = data
                cachedSegments = newValue
            }
        }
    }

    func decodedSegments() throws -> [WageSegment] {
        let data = segmentsData
        if let cachedSegments, cachedSegmentsData == data { return cachedSegments }
        let decoded = try JSONDecoder().decode([WageSegment].self, from: data)
        cachedSegmentsData = data
        cachedSegments = decoded
        return decoded
    }

    func rewardTracking() throws -> RewardTracking? {
        try rewardTrackingData.map { try JSONDecoder().decode(RewardTracking.self, from: $0) }
    }

    func setRewardTracking(_ tracking: RewardTracking) throws {
        rewardTrackingData = try JSONEncoder().encode(tracking)
    }

    init(id: String = UUID().uuidString, startedAt: Date = .now, wage: Int) {
        self.id = id
        self.startedAt = startedAt
        self.isActive = true
        self.segmentsData = Data()
        self.segments = [.init(start: startedAt, hourlyWage: wage)]
    }

    /// Keep live SwiftData references consistent after a failed write and rollback.
    func restorePoint() -> () -> Void {
        let values = (startedAt, endedAt, segmentsData, isActive, rewardTrackingData)
        return { [self] in
            startedAt = values.0; endedAt = values.1
            segmentsData = values.2; isActive = values.3
            rewardTrackingData = values.4
        }
    }

    func accrued(until now: Date = .now) -> Int { EarningsCalculator.total(segments, until: now) }
    var currentWage: Int { segments.last?.hourlyWage ?? 0 }
}
