import Foundation
import SwiftData
import Testing
@testable import PiyakCore

/// An editor in one iPad window can outlive deletion/reset in another window.
/// Use a persisted store because deleted-model invalidation is runtime-dependent.
@Suite(.serialized) @MainActor
struct StaleRecordTests {
    @Test func deletedRecordCannotBeSavedByAnotherWindow() throws {
        let fixture = try StaleRecordFixture()
        defer { fixture.clean() }
        let editing = try fixture.makeRecord()
        let revision = try fixture.store.revision(for: editing)
        let draft = fixture.editedSegments

        try fixture.store.deleteRecord(editing)
        #expect(try fixture.records().isEmpty)
        expectMissingRecord {
            try fixture.store.replaceRecord(editing, segments: draft, now: fixture.now)
        }
        expectMissingRecord { try fixture.store.deleteRecord(editing) }
        expectMissingRecord {
            try fixture.store.replaceRecord(revision: revision, segments: draft, now: fixture.now)
        }
        expectMissingRecord { try fixture.store.deleteRecord(revision: revision) }

        #expect(try fixture.records().isEmpty)
        #expect(try fixture.store.dailyAccrued(on: fixture.now, now: fixture.now) == 0)
        #expect(try fixture.store.balance() == 1_000)
    }

    @Test func resetRecordCannotBeResurrectedByAnotherWindow() throws {
        let fixture = try StaleRecordFixture()
        defer { fixture.clean() }
        let editing = try fixture.makeRecord()
        let revision = try fixture.store.revision(for: editing)
        let draft = fixture.editedSegments

        try fixture.store.resetAll()
        #expect(try fixture.records().isEmpty)
        expectMissingRecord {
            try fixture.store.replaceRecord(editing, segments: draft, now: fixture.now)
        }
        expectMissingRecord { try fixture.store.deleteRecord(editing) }
        expectMissingRecord {
            try fixture.store.replaceRecord(revision: revision, segments: draft, now: fixture.now)
        }
        expectMissingRecord { try fixture.store.deleteRecord(revision: revision) }

        #expect(try fixture.records().isEmpty)
        #expect(try fixture.store.dailyAccrued(on: fixture.now, now: fixture.now) == 0)
        #expect(try fixture.store.balance() == 0)
        #expect(try fixture.store.ownedAll().count == 4)
    }

    @Test func staleEditorAndDeleteConfirmationPreserveOtherWindowsEdit() throws {
        let fixture = try StaleRecordFixture()
        defer { fixture.clean() }
        let record = try fixture.makeRecord()
        let firstWindow = try fixture.store.revision(for: record)
        let secondWindow = firstWindow
        var latestSegments = fixture.editedSegments
        latestSegments[0].hourlyWage = 20_000
        try fixture.store.replaceRecord(revision: secondWindow, segments: latestSegments, now: fixture.now)

        expectChangedRecord {
            try fixture.store.replaceRecord(revision: firstWindow, segments: fixture.editedSegments, now: fixture.now)
        }
        expectChangedRecord { try fixture.store.deleteRecord(revision: firstWindow) }

        let saved = try #require(fixture.records().first)
        #expect(try fixture.records().count == 1)
        #expect(try saved.decodedSegments() == latestSegments)
        #expect(saved.accrued(until: fixture.now) == 20_000)
        #expect(try fixture.store.balance() == 1_000)
    }

    @Test func freshRevisionCanSaveAndDeleteWithoutChangingPoints() throws {
        let fixture = try StaleRecordFixture()
        defer { fixture.clean() }
        let record = try fixture.makeRecord()
        let revision = try fixture.store.revision(for: record)
        try fixture.store.replaceRecord(revision: revision, segments: fixture.editedSegments, now: fixture.now)

        let saved = try #require(fixture.records().first)
        #expect(saved.accrued(until: fixture.now) == 12_000)
        #expect(try fixture.store.balance() == 1_000)
        try fixture.store.deleteRecord(revision: fixture.store.revision(for: saved))
        #expect(try fixture.records().isEmpty)
        #expect(try fixture.store.balance() == 1_000)
    }

    @Test func detachedModelCannotMasqueradeAsAnExistingRecord() throws {
        let fixture = try StaleRecordFixture()
        defer { fixture.clean() }
        let saved = try fixture.makeRecord()
        let detached = WorkSession(id: saved.id, startedAt: fixture.editedSegments[0].start, wage: 12_000)
        detached.isActive = false
        detached.segments = fixture.editedSegments

        expectMissingRecord { _ = try fixture.store.revision(for: detached) }
        expectMissingRecord { try fixture.store.replaceRecord(detached, segments: fixture.editedSegments, now: fixture.now) }
        expectMissingRecord { try fixture.store.deleteRecord(detached) }
        #expect(try fixture.records().count == 1)
        #expect(saved.accrued(until: fixture.now) == 10_000)
        #expect(try fixture.store.balance() == 1_000)
    }

    private func expectMissingRecord(_ save: () throws -> Void) {
        do {
            try save()
            Issue.record("A stale editor reported success after the record was removed")
        } catch EconomyStore.StoreError.notFound {
            // The editor can display a recoverable error without reviving data.
        } catch {
            Issue.record("Expected a missing-record error, received: \(error)")
        }
    }

    private func expectChangedRecord(_ action: () throws -> Void) {
        do {
            try action()
            Issue.record("A stale revision changed a record that another window had updated")
        } catch EconomyStore.StoreError.recordChanged {
            // Existing changes remain intact until the person reopens the editor.
        } catch {
            Issue.record("Expected a changed-record error, received: \(error)")
        }
    }
}

@MainActor private final class StaleRecordFixture {
    let directory: URL
    let container: ModelContainer
    let store: EconomyStore
    let now = Date(timeIntervalSince1970: 1_780_012_800)

    var editedSegments: [WageSegment] {
        [.init(start: now.addingTimeInterval(-7200), end: now.addingTimeInterval(-3600), hourlyWage: 12_000)]
    }

    init() throws {
        directory = FileManager.default.temporaryDirectory.appending(path: "PiyakStaleRecord-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let schema = Schema([CatalogItem.self, OwnedItem.self, PointTransaction.self, WorkSession.self, RewardReceipt.self])
        container = try ModelContainer(for: schema, configurations: ModelConfiguration(url: directory.appending(path: "review.store")))
        container.mainContext.autosaveEnabled = false
        store = EconomyStore(context: container.mainContext)
        try store.migrateRewardsIfNeeded(now: now)
        try store.seedIfNeeded()
        container.mainContext.insert(PointTransaction(amount: 1_000, kind: .adjust))
        try container.mainContext.save()
    }

    func makeRecord() throws -> WorkSession {
        try store.replaceRecord(nil, segments: [
            .init(start: now.addingTimeInterval(-7200), end: now.addingTimeInterval(-3600), hourlyWage: 10_000)
        ], now: now)
        return try #require(records().first)
    }

    func records() throws -> [WorkSession] {
        try container.mainContext.fetch(FetchDescriptor<WorkSession>())
    }

    func clean() {
        try? FileManager.default.removeItem(at: directory)
    }
}
