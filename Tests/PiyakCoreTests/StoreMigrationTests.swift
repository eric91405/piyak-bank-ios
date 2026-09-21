import Foundation
import SQLite3
import SwiftData
import Testing
@testable import PiyakCore

private struct MigrationDiskFailure: Error {}
private final class MigrationFiles {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("PiyakMigrationTests-" + UUID().uuidString)
    var legacy: URL { root.appendingPathComponent("default.store") }
    var shared: URL { root.appendingPathComponent("group/PiyakBank.store") }
    init() throws { try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true) }
    deinit { try? FileManager.default.removeItem(at: root) }
}

@Test func migrationIncludesCommittedWALWithoutChangingSource() throws {
    let f = try MigrationFiles()
    var writer: OpaquePointer?
    #expect(sqlite3_open(f.legacy.path, &writer) == SQLITE_OK)
    defer { sqlite3_close(writer) }
    #expect(sqlite3_exec(writer, "PRAGMA journal_mode=WAL; PRAGMA wal_autocheckpoint=0; CREATE TABLE records (value INTEGER); INSERT INTO records VALUES (695);", nil, nil, nil) == SQLITE_OK)
    let original = try Data(contentsOf: f.legacy)
    #expect(FileManager.default.fileExists(atPath: f.legacy.path + "-wal"))
    try StoreMigration.prepare(legacy: f.legacy, destination: f.shared)
    #expect(try Data(contentsOf: f.legacy) == original)
    #expect(!FileManager.default.fileExists(atPath: f.shared.path + "-wal"))
    var reader: OpaquePointer?
    #expect(sqlite3_open_v2(f.shared.path, &reader, SQLITE_OPEN_READONLY, nil) == SQLITE_OK)
    defer { sqlite3_close(reader) }
    var query: OpaquePointer?
    defer { sqlite3_finalize(query) }
    #expect(sqlite3_prepare_v2(reader, "SELECT value FROM records", -1, &query, nil) == SQLITE_OK)
    #expect(sqlite3_step(query) == SQLITE_ROW)
    #expect(sqlite3_column_int(query, 0) == 695)
}

@Test func failedMigrationPublishesNothingAndCanRetry() throws {
    let f = try MigrationFiles()
    var database: OpaquePointer?
    #expect(sqlite3_open(f.legacy.path, &database) == SQLITE_OK)
    #expect(sqlite3_exec(database, "CREATE TABLE records (value INTEGER); INSERT INTO records VALUES (1);", nil, nil, nil) == SQLITE_OK)
    sqlite3_close(database)
    #expect(throws: MigrationDiskFailure.self) {
        try StoreMigration.prepare(legacy: f.legacy, destination: f.shared) { _, _ in throw MigrationDiskFailure() }
    }
    #expect(!FileManager.default.fileExists(atPath: f.shared.path))
    #expect(try FileManager.default.contentsOfDirectory(atPath: f.shared.deletingLastPathComponent().path).isEmpty)
    try StoreMigration.prepare(legacy: f.legacy, destination: f.shared)
    let published = try Data(contentsOf: f.shared)
    // Even a changed or unreadable old copy must never replace a published store.
    try Data("obsolete".utf8).write(to: f.legacy)
    try StoreMigration.prepare(legacy: f.legacy, destination: f.shared)
    #expect(try Data(contentsOf: f.shared) == published)
}

@Test func corruptOrIncompleteLegacyNeverCreatesEmptyStore() throws {
    let f = try MigrationFiles()
    try Data("not a database".utf8).write(to: f.legacy)
    #expect(throws: StoreMigration.Failure.self) { try StoreMigration.prepare(legacy: f.legacy, destination: f.shared) }
    #expect(!FileManager.default.fileExists(atPath: f.shared.path))
    try FileManager.default.removeItem(at: f.legacy)
    try Data([1]).write(to: URL(fileURLWithPath: f.legacy.path + "-wal"))
    #expect(throws: StoreMigration.Failure.self) { try StoreMigration.prepare(legacy: f.legacy, destination: f.shared) }
    #expect(!FileManager.default.fileExists(atPath: f.shared.path))
}

@Test func emptyPublishedStoreFailsClosedAndKeepsLegacy() throws {
    let f = try MigrationFiles()
    var database: OpaquePointer?
    #expect(sqlite3_open(f.legacy.path, &database) == SQLITE_OK)
    #expect(sqlite3_exec(database, "CREATE TABLE records (value INTEGER); INSERT INTO records VALUES (35);", nil, nil, nil) == SQLITE_OK)
    sqlite3_close(database)
    let original = try Data(contentsOf: f.legacy)
    try FileManager.default.createDirectory(at: f.shared.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data().write(to: f.shared)
    #expect(throws: StoreMigration.Failure.self) { try StoreMigration.prepare(legacy: f.legacy, destination: f.shared) }
    #expect(try Data(contentsOf: f.legacy) == original)
    #expect(try Data(contentsOf: f.shared).isEmpty)
}

@Test func automaticGroupStoreIsFoundAndConflictingHistoriesFailClosed() throws {
    let f = try MigrationFiles()
    let groupedLegacy = f.root.appendingPathComponent("group/default.store")
    try FileManager.default.createDirectory(at: groupedLegacy.deletingLastPathComponent(), withIntermediateDirectories: true)
    var database: OpaquePointer?
    #expect(sqlite3_open(groupedLegacy.path, &database) == SQLITE_OK)
    #expect(sqlite3_exec(database, "CREATE TABLE records (value INTEGER); INSERT INTO records VALUES (35);", nil, nil, nil) == SQLITE_OK)
    sqlite3_close(database)
    try FileManager.default.copyItem(at: groupedLegacy, to: f.legacy)
    #expect(throws: StoreMigration.Failure.self) {
        try StoreMigration.prepare(legacyCandidates: [f.legacy, groupedLegacy], destination: f.shared)
    }
    #expect(!FileManager.default.fileExists(atPath: f.shared.path))
    try FileManager.default.removeItem(at: f.legacy)
    try StoreMigration.prepare(legacyCandidates: [f.legacy, groupedLegacy, groupedLegacy], destination: f.shared)
    #expect(FileManager.default.fileExists(atPath: f.shared.path))
}

@Test @MainActor func swiftDataMigrationPreservesRecordsRewardsEquipmentAndSingleConversion() throws {
    let f = try MigrationFiles()
    let schema = Schema([CatalogItem.self, OwnedItem.self, PointTransaction.self, WorkSession.self, RewardReceipt.self])
    let original = try ModelContainer(for: schema, configurations: ModelConfiguration(url: f.legacy))
    original.mainContext.autosaveEnabled = false
    let oldStore = EconomyStore(context: original.mainContext)
    try oldStore.seedIfNeeded()
    original.mainContext.insert(PointTransaction(amount: 660, kind: .accrual))
    let now = Date(timeIntervalSince1970: 1_780_012_800)
    try oldStore.replaceRecord(nil, segments: [.init(start: now, end: now.addingTimeInterval(3600), hourlyWage: 10_000)], now: now.addingTimeInterval(3600))
    try original.mainContext.save()
    let equipment = try oldStore.equippedMap()
    let ids = try original.mainContext.fetch(FetchDescriptor<WorkSession>()).map(\.id)
    try StoreMigration.prepare(legacy: f.legacy, destination: f.shared)
    let relocated = try ModelContainer(for: schema, configurations: ModelConfiguration(url: f.shared))
    relocated.mainContext.autosaveEnabled = false
    let store = EconomyStore(context: relocated.mainContext)
    try store.migrateRewardsIfNeeded(now: now)
    try store.seedIfNeeded()
    #expect(try store.balance() == 33)
    #expect(try store.equippedMap() == equipment)
    #expect(try store.ownedAll().count == 4)
    #expect(try relocated.mainContext.fetch(FetchDescriptor<WorkSession>()).map(\.id) == ids)
    #expect(try relocated.mainContext.fetch(FetchDescriptor<WorkSession>()).first?.accrued(until: now.addingTimeInterval(3600)) == 10_000)
    relocated.mainContext.insert(PointTransaction(amount: 2, kind: .accrual))
    try relocated.mainContext.save()
    try StoreMigration.prepare(legacy: f.legacy, destination: f.shared)
    let reopened = try ModelContainer(for: schema, configurations: ModelConfiguration(url: f.shared))
    let reopenedStore = EconomyStore(context: reopened.mainContext)
    try reopenedStore.migrateRewardsIfNeeded(now: now)
    #expect(try reopenedStore.balance() == 35)
    #expect(try reopenedStore.equippedMap() == equipment)
    #expect(try reopened.mainContext.fetch(FetchDescriptor<PointTransaction>()).filter { $0.kind == .migration }.count == 1)
    #expect(try reopened.mainContext.fetch(FetchDescriptor<RewardReceipt>()).count == 1)
    #expect(try oldStore.balance() == 660)
}

@Test func explicitResetRemovesLegacyCopiesAndOnlyOwnedStagingDirectories() throws {
    let f = try MigrationFiles()
    let files = FileManager.default
    var database: OpaquePointer?
    #expect(sqlite3_open(f.legacy.path, &database) == SQLITE_OK)
    #expect(sqlite3_exec(database, "CREATE TABLE records (value INTEGER); INSERT INTO records VALUES (35);", nil, nil, nil) == SQLITE_OK)
    sqlite3_close(database)
    try StoreMigration.prepare(legacy: f.legacy, destination: f.shared)
    let published = try Data(contentsOf: f.shared)
    let groupedLegacy = f.shared.deletingLastPathComponent().appendingPathComponent("default.store")
    try files.copyItem(at: f.legacy, to: groupedLegacy)
    for url in [f.legacy, groupedLegacy, f.shared] {
        for suffix in ["-wal", "-shm"] {
            try Data(suffix.utf8).write(to: URL(fileURLWithPath: url.path + suffix))
        }
    }
    let alias = f.root.appendingPathComponent("published-alias.store")
    try files.createSymbolicLink(at: alias, withDestinationURL: f.shared)
    let staging = f.shared.deletingLastPathComponent().appendingPathComponent(".piyak-migration-" + UUID().uuidString)
    try files.createDirectory(at: staging, withIntermediateDirectories: false)
    try files.copyItem(at: f.legacy, to: staging.appendingPathComponent("PiyakBank.store"))
    let unrelated = f.shared.deletingLastPathComponent().appendingPathComponent(".piyak-migration-not-a-uuid")
    try files.createDirectory(at: unrelated, withIntermediateDirectories: false)

    let candidates = [f.legacy, groupedLegacy, f.shared, alias]
    try StoreMigration.removeLegacyCopies(legacyCandidates: candidates, destination: f.shared)
    try StoreMigration.removeLegacyCopies(legacyCandidates: candidates, destination: f.shared)
    for url in [f.legacy, groupedLegacy] {
        for suffix in ["", "-wal", "-shm"] { #expect(!files.fileExists(atPath: url.path + suffix)) }
    }
    #expect(!files.fileExists(atPath: staging.path))
    #expect(files.fileExists(atPath: unrelated.path))
    #expect(files.fileExists(atPath: alias.path))
    #expect(try Data(contentsOf: f.shared) == published)
    for suffix in ["-wal", "-shm"] {
        #expect(try Data(contentsOf: URL(fileURLWithPath: f.shared.path + suffix)) == Data(suffix.utf8))
    }
}

@Test func legacyCleanupRequiresPublishedStoreAndPropagatesDeletionFailure() throws {
    let f = try MigrationFiles()
    let original = Data("preserved old records".utf8)
    try original.write(to: f.legacy)
    #expect(throws: StoreMigration.Failure.self) {
        try StoreMigration.removeLegacyCopies(legacyCandidates: [f.legacy], destination: f.shared)
    }
    #expect(try Data(contentsOf: f.legacy) == original)
    try FileManager.default.createDirectory(at: f.shared.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data().write(to: f.shared)
    #expect(throws: StoreMigration.Failure.self) {
        try StoreMigration.removeLegacyCopies(legacyCandidates: [f.legacy], destination: f.shared)
    }
    #expect(try Data(contentsOf: f.legacy) == original)
    var database: OpaquePointer?
    #expect(sqlite3_open(f.shared.path, &database) == SQLITE_OK)
    #expect(sqlite3_exec(database, "CREATE TABLE records (value INTEGER);", nil, nil, nil) == SQLITE_OK)
    sqlite3_close(database)
    let published = try Data(contentsOf: f.shared)
    #expect(throws: MigrationDiskFailure.self) {
        try StoreMigration.removeLegacyCopies(legacyCandidates: [f.legacy], destination: f.shared) { _ in
            throw MigrationDiskFailure()
        }
    }
    #expect(try Data(contentsOf: f.legacy) == original)
    #expect(try Data(contentsOf: f.shared) == published)
}
