import Foundation
import SwiftData

@MainActor private final class LegacyProbeReminders: SessionReminding {
    func update(snapshot: SessionSnapshot, interval: ReminderInterval, enabled: Bool) {}
}

@main struct CurrentVerifier {
    @MainActor static func main() throws {
        guard CommandLine.arguments.count == 3 else {
            throw LegacyFixture.Failure(message: "Usage: current-verifier migrate|reopen|verify-settled WORK_DIRECTORY")
        }
        let root = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
        let source = root.appendingPathComponent("legacy/default.store")
        let destination = root.appendingPathComponent("group/PiyakBank.store")
        let before = try LegacyFixture.read(LegacySnapshot.self, at: root.appendingPathComponent("legacy-snapshot.json"))
        // Match AppPersistence's order: relocate the old SQLite store first, then
        // open it using the current SwiftData schema, then bootstrap the economy.
        try StoreMigration.prepare(legacyCandidates: [source], destination: destination)
        let schema = Schema([CatalogItem.self, OwnedItem.self, PointTransaction.self, WorkSession.self, RewardReceipt.self])
        let container = try ModelContainer(for: schema, configurations: ModelConfiguration(url: destination))
        let context = container.mainContext
        context.autosaveEnabled = false
        let store = EconomyStore(context: context)
        let mode = CommandLine.arguments[1]
        if mode == "migrate" {
            try LegacyFixture.require(try LegacySnapshot(context: context) == before,
                                      "Schema upgrade changed historical model fields or segment bytes")
            try LegacyFixture.require(try context.fetch(FetchDescriptor<RewardReceipt>()).isEmpty,
                                      "Old schema unexpectedly already contained reward receipts")
            try LegacyFixture.require(try context.fetch(FetchDescriptor<WorkSession>()).allSatisfy { $0.rewardTrackingData == nil },
                                      "Added optional reward tracking must start nil")
            try store.migrateRewardsIfNeeded(now: LegacyFixture.now)
            try store.seedIfNeeded()
            try validateConversion(store, before: before)
            let first = try LegacySnapshot(context: context)
            try store.migrateRewardsIfNeeded(now: LegacyFixture.now.addingTimeInterval(86_400))
            try store.seedIfNeeded()
            try LegacyFixture.require(try LegacySnapshot(context: context) == first, "Second migration was not idempotent")
            try LegacyFixture.write(first, to: root.appendingPathComponent("migrated-snapshot.json"))
            print("PASS real schema upgrade, exact historical bytes/equipment, 3199P conversion, idempotent seeding")
        } else if mode == "reopen" {
            let migrated = try LegacyFixture.read(LegacySnapshot.self, at: root.appendingPathComponent("migrated-snapshot.json"))
            try LegacyFixture.require(try LegacySnapshot(context: context) == migrated, "Migration did not survive a fresh process")
            try store.migrateRewardsIfNeeded(now: LegacyFixture.now)
            try store.seedIfNeeded()
            try validateConversion(store, before: before)
            try LegacyFixture.require(try LegacySnapshot(context: context) == migrated, "Relaunch duplicated or changed migration")
            let defaultsName = "PiyakLegacyMigrationProbe." + UUID().uuidString
            let defaults = UserDefaults(suiteName: defaultsName)!
            defer { defaults.removePersistentDomain(forName: defaultsName) }
            // Simulate loss of the old active-session defaults. The database must
            // recover the active record without retroactive reward grants.
            var date = LegacyFixture.now
            var tick: TimeInterval = 100_000
            let controller = SessionController(context: context, economy: store, scheduler: LegacyProbeReminders(),
                                               defaults: defaults, now: { date }, continuousNow: { tick },
                                               bootSessionID: { "legacy-migration-probe-boot" })
            try controller.recoverIfNeeded()
            try LegacyFixture.require(controller.current?.id == LegacyFixture.activeID, "Old active record was not recovered")
            try LegacyFixture.require(controller.current?.accrued(until: date) == 15_000, "Old active wages were lost")
            try LegacyFixture.require(try store.balance() == LegacyFixture.convertedBalance, "Recovery retroactively awarded points")
            date += 600
            tick += 600
            try LegacyFixture.require(try controller.stop() == 100, "Only ten newly measured minutes should award 100P")
            try LegacyFixture.require(try store.balance() == LegacyFixture.convertedBalance + 100, "Incorrect balance after recovery")
            let records = try context.fetch(FetchDescriptor<WorkSession>())
            try LegacyFixture.require(records.count == 3 && records.allSatisfy { !$0.isActive }, "Recovered work was not settled")
            try LegacyFixture.require(records.first { $0.id == LegacyFixture.activeID }?.accrued(until: date) == 20_000,
                                      "Recovered work did not retain all old and new wages")
            try LegacyFixture.require(try store.ownedAll().count == before.ownership.count, "Recovery altered ownership")
            try LegacyFixture.write(try LegacySnapshot(context: context), to: root.appendingPathComponent("settled-snapshot.json"))
            print("PASS fresh-process reopening, active work recovery without defaults, 100P for newly measured time only")
        } else if mode == "verify-settled" {
            let settled = try LegacyFixture.read(LegacySnapshot.self, at: root.appendingPathComponent("settled-snapshot.json"))
            try LegacyFixture.require(try LegacySnapshot(context: context) == settled, "Settlement did not survive a fresh process")
            try store.migrateRewardsIfNeeded(now: LegacyFixture.now.addingTimeInterval(1_200))
            try LegacyFixture.require(try LegacySnapshot(context: context) == settled, "Post-settlement reopen reapplied conversion")
            try LegacyFixture.require(try store.balance() == LegacyFixture.convertedBalance + 100, "Final balance was not preserved")
            try LegacyFixture.require(try context.fetch(FetchDescriptor<RewardReceipt>()).count == 2, "Expected one policy and one work receipt")
            print("PASS settled wages, rewards and receipts survive another process restart")
        } else {
            throw LegacyFixture.Failure(message: "Unknown current verifier mode")
        }
    }

    @MainActor private static func validateConversion(_ store: EconomyStore, before: LegacySnapshot) throws {
        let after = try LegacySnapshot(context: store.context)
        try LegacyFixture.require(after.records == before.records && after.ownership == before.ownership,
                                  "Conversion or catalog seeding changed wages/ownership/equipment")
        try LegacyFixture.require(try store.balance() == LegacyFixture.convertedBalance, "Incorrect 20:1 converted balance")
        try LegacyFixture.require(after.transactions.count == before.transactions.count + 1, "Expected exactly one conversion transaction")
        for old in before.transactions {
            guard let archived = after.transactions.first(where: { $0.id == old.id }) else {
                throw LegacyFixture.Failure(message: "Missing historical ledger entry")
            }
            try LegacyFixture.require(archived.amount == old.amount && archived.date == old.date
                                      && archived.relatedId == old.relatedId && archived.kindRaw == "legacy"
                                      && archived.note == "이전 단위 [\(old.kindRaw)] " + (old.note ?? ""),
                                      "Historical transaction fields or archival annotation changed")
        }
        try LegacyFixture.require(after.transactions.filter { $0.kindRaw == "migration" }.count == 1, "Duplicate conversion")
        try LegacyFixture.require(after.transactions.filter { $0.kindRaw == "accrual" }.isEmpty,
                                  "Legacy wages must not count as newly earned points or experience")
        let receipts = try store.context.fetch(FetchDescriptor<RewardReceipt>())
        try LegacyFixture.require(receipts.count == 1 && receipts.first?.sessionId == "reward-policy-v1", "Invalid migration marker")
        for old in before.catalog {
            guard let updated = after.catalog.first(where: { $0.id == old.id }) else {
                throw LegacyFixture.Failure(message: "Catalog entry was removed")
            }
            try LegacyFixture.require(updated.slotRaw == old.slotRaw && !updated.isIAP, "Old catalog did not convert to free release")
            if let seed = CatalogSeed.items.first(where: { $0.id == old.id }) {
                try LegacyFixture.require(updated.price == seed.price && updated.displayName == seed.name, "Catalog metadata is stale")
            }
        }
        let records = try store.context.fetch(FetchDescriptor<WorkSession>()).filter { !$0.isActive }
        try LegacyFixture.require(records.reduce(0) { $0 + $1.accrued(until: LegacyFixture.now) } == LegacyFixture.closedPay,
                                  "Cross-midnight, paused or fractional-wage history changed")
    }
}
