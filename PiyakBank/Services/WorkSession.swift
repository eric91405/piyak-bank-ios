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

    var segments: [WageSegment] {
        get { (try? decodedSegments()) ?? [] }
        set {
            // Never replace valid data with an empty blob if encoding fails.
            if let data = try? JSONEncoder().encode(newValue) { segmentsData = data }
        }
    }

    func decodedSegments() throws -> [WageSegment] {
        try JSONDecoder().decode([WageSegment].self, from: segmentsData)
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
        let values = (startedAt, endedAt, segmentsData, isActive)
        return { [self] in
            startedAt = values.0; endedAt = values.1
            segmentsData = values.2; isActive = values.3
        }
    }

    func accrued(until now: Date = .now) -> Int { EarningsCalculator.total(segments, until: now) }
    var currentWage: Int { segments.last?.hourlyWage ?? 0 }
}
