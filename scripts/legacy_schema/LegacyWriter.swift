import Foundation
import SwiftData

@main struct LegacyWriter {
    @MainActor static func main() throws {
        guard CommandLine.arguments.count == 3 else {
            throw LegacyFixture.Failure(message: "Usage: legacy-writer seed|verify WORK_DIRECTORY")
        }
        let root = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
        let source = root.appendingPathComponent("legacy/default.store")
        let report = root.appendingPathComponent("legacy-snapshot.json")
        try FileManager.default.createDirectory(at: source.deletingLastPathComponent(), withIntermediateDirectories: true)
        let schema = Schema([CatalogItem.self, OwnedItem.self, PointTransaction.self, WorkSession.self])
        let container = try ModelContainer(for: schema, configurations: ModelConfiguration(url: source))
        let context = container.mainContext
        context.autosaveEnabled = false
        let store = EconomyStore(context: context)
        switch CommandLine.arguments[1] {
        case "seed":
            try LegacyFixture.require(try context.fetch(FetchDescriptor<WorkSession>()).isEmpty, "Source must start empty")
            store.seedIfNeeded()
            context.insert(OwnedItem(catalogId: "headTop.straw_hat", acquiredAt: LegacyFixture.reference, equippedSlot: .headTop))
            // An old IAP ownership must survive the move to the free catalog too.
            store.grantIAP("bodyFront.graduation_gown")
            store.equip("bodyFront.graduation_gown")
            for owned in store.ownedAll() { owned.acquiredAt = LegacyFixture.reference }

            let transactions: [(Int, TxKind, String?, String?)] = [
                (70_000, .accrual, "legacy-completed-night", "야간 근무 · 보존"),
                (-12_000, .purchase, "headTop.straw_hat", nil),
                (6_000, .refund, "rug.round_stripe", "환불 기록"),
                (-3, .adjust, nil, "소수 잔액 경계")
            ]
            for (index, value) in transactions.enumerated() {
                let transaction = PointTransaction(amount: value.0, kind: value.1, date: LegacyFixture.reference,
                                                   relatedId: value.2, note: value.3)
                transaction.id = UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", index + 1))!
                context.insert(transaction)
            }
            let start = LegacyFixture.reference
            let night = WorkSession(id: "legacy-completed-night", startedAt: start, wage: 12_000)
            night.segments = [
                WageSegment(start: start, end: start.addingTimeInterval(1_800), hourlyWage: 12_000),
                WageSegment(start: start.addingTimeInterval(1_800), end: start.addingTimeInterval(2_700), hourlyWage: 0),
                WageSegment(start: start.addingTimeInterval(2_700), end: start.addingTimeInterval(6_300), hourlyWage: 18_000)
            ]
            night.endedAt = start.addingTimeInterval(6_300)
            night.isActive = false
            context.insert(night)
            let secondStart = start.addingTimeInterval(86_400)
            let second = WorkSession(id: "legacy-completed-fraction", startedAt: secondStart, wage: 9_999)
            second.segments = [WageSegment(start: secondStart, end: secondStart.addingTimeInterval(1_800), hourlyWage: 9_999)]
            second.endedAt = secondStart.addingTimeInterval(1_800)
            second.isActive = false
            context.insert(second)
            context.insert(WorkSession(id: LegacyFixture.activeID,
                                       startedAt: LegacyFixture.now.addingTimeInterval(-1_800), wage: 30_000))
            try context.save()
            let snapshot = try LegacySnapshot(context: context)
            try LegacyFixture.require(snapshot.records.count == 3 && snapshot.ownership.count == 6, "Incomplete fixture")
            try LegacyFixture.require(store.balance == LegacyFixture.oldBalance, "Unexpected old balance")
            try LegacyFixture.write(snapshot, to: report)
            print("PASS old c70a8be schema created: 3 records, 6 owned items, 4 transactions")
        case "verify":
            try LegacyFixture.require(try LegacySnapshot(context: context) == LegacyFixture.read(LegacySnapshot.self, at: report),
                                      "Migration modified the original store")
            print("PASS original store remains readable by the original schema with identical contents")
        default:
            throw LegacyFixture.Failure(message: "Unknown legacy writer mode")
        }
    }
}
