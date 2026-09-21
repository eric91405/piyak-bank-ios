import Foundation
import SQLite3

/// Preparation preserves legacy data and never falls back after publication.
/// Obsolete copies are removed only by the explicit user-requested data reset.
enum StoreMigration {
    enum Failure: Error { case sqlite(Int32), incompleteStore, invalidBackup, ambiguousLegacyStores }

    static func prepare(legacyCandidates: [URL], destination: URL) throws {
        if FileManager.default.fileExists(atPath: destination.path) {
            try prepare(legacy: destination, destination: destination)
            return
        }
        let distinct = Set(legacyCandidates.map { $0.standardizedFileURL.resolvingSymlinksInPath() })
        let existing = distinct.filter { url in
            ["", "-wal", "-shm"].contains { FileManager.default.fileExists(atPath: url.path + $0) }
        }
        // Automatic SwiftData configurations can already reside in an App Group.
        // Never pick one arbitrarily if an earlier build left two histories.
        guard existing.count <= 1 else { throw Failure.ambiguousLegacyStores }
        guard let source = existing.first ?? legacyCandidates.first else { throw Failure.incompleteStore }
        try prepare(legacy: source, destination: destination)
    }

    static func prepare(legacy: URL, destination: URL,
                        publish: (URL, URL) throws -> Void = { try FileManager.default.moveItem(at: $0, to: $1) }) throws {
        let files = FileManager.default
        // A published store owns all subsequent writes, even when opening it fails.
        if files.fileExists(atPath: destination.path) {
            // SQLite treats a zero-byte file as a new database; never silently
            // initialize an interrupted/invalid destination over the old records.
            guard (try files.attributesOfItem(atPath: destination.path)[.size] as? NSNumber)?.int64Value ?? 0 > 0 else {
                throw Failure.incompleteStore
            }
            return
        }
        guard !["-wal", "-shm"].contains(where: { files.fileExists(atPath: destination.path + $0) }) else {
            throw Failure.incompleteStore
        }
        guard files.fileExists(atPath: legacy.path) else {
            guard !["-wal", "-shm"].contains(where: { files.fileExists(atPath: legacy.path + $0) }) else {
                throw Failure.incompleteStore
            }
            return // A genuinely new installation may let SwiftData create its store.
        }
        guard (try files.attributesOfItem(atPath: legacy.path)[.size] as? NSNumber)?.int64Value ?? 0 > 0 else {
            throw Failure.incompleteStore
        }
        try files.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        let staging = destination.deletingLastPathComponent().appendingPathComponent(".piyak-migration-" + UUID().uuidString)
        try files.createDirectory(at: staging, withIntermediateDirectories: false)
        defer { try? files.removeItem(at: staging) }
        let backup = staging.appendingPathComponent(destination.lastPathComponent)
        try snapshot(from: legacy, to: backup)
        // Both locations are on the same volume. The final name only becomes
        // visible after the complete, checked, self-contained database is closed.
        try publish(backup, destination)
    }

    /// Called only during an explicit data reset, before clearing the live store.
    /// Cleanup failures propagate; the published database and its sidecars remain untouched.
    static func removeLegacyCopies(legacyCandidates: [URL], destination: URL,
                                   remove: (URL) throws -> Void = { try FileManager.default.removeItem(at: $0) }) throws {
        let files = FileManager.default
        let published = destination.standardizedFileURL.resolvingSymlinksInPath()
        guard files.fileExists(atPath: published.path) else { throw Failure.incompleteStore }
        let attributes = try files.attributesOfItem(atPath: published.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular,
              (attributes[.size] as? NSNumber)?.int64Value ?? 0 > 0 else { throw Failure.incompleteStore }
        let protected = Set(["", "-wal", "-shm"].map {
            URL(fileURLWithPath: destination.path + $0).standardizedFileURL.resolvingSymlinksInPath().path
        })
        var obsolete: [URL] = []
        var seen: Set<String> = []
        func collect(_ url: URL, allowsDirectory: Bool = false) throws {
            let canonical = url.standardizedFileURL.resolvingSymlinksInPath().path
            guard !protected.contains(canonical), !published.path.hasPrefix(canonical + "/"),
                  files.fileExists(atPath: url.path), seen.insert(url.standardizedFileURL.path).inserted else { return }
            let type = try files.attributesOfItem(atPath: url.path)[.type] as? FileAttributeType
            guard type == .typeRegular || type == .typeSymbolicLink || (allowsDirectory && type == .typeDirectory) else {
                throw Failure.incompleteStore
            }
            obsolete.append(url)
        }
        for candidate in legacyCandidates {
            guard candidate.standardizedFileURL.resolvingSymlinksInPath() != published else { continue }
            for suffix in ["", "-wal", "-shm"] {
                try collect(URL(fileURLWithPath: candidate.path + suffix))
            }
        }
        let prefix = ".piyak-migration-"
        for child in try files.contentsOfDirectory(at: destination.deletingLastPathComponent(), includingPropertiesForKeys: nil) {
            let name = child.lastPathComponent
            guard name.hasPrefix(prefix), UUID(uuidString: String(name.dropFirst(prefix.count))) != nil else { continue }
            try collect(child, allowsDirectory: true)
        }
        for url in obsolete { try remove(url) }
    }

    private static func snapshot(from source: URL, to destination: URL) throws {
        var reader: OpaquePointer?
        var writer: OpaquePointer?
        defer { if let writer { sqlite3_close(writer) }; if let reader { sqlite3_close(reader) } }
        try checked(sqlite3_open_v2(source.path, &reader, SQLITE_OPEN_READONLY, nil))
        try checked(sqlite3_open_v2(destination.path, &writer, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil))
        guard let reader, let writer else { throw Failure.invalidBackup }
        sqlite3_busy_timeout(reader, 1_000)
        guard let backup = sqlite3_backup_init(writer, "main", reader, "main") else {
            throw Failure.sqlite(sqlite3_errcode(writer))
        }
        // SQLite's backup API includes committed WAL pages in one consistent
        // snapshot; copying the .store/.wal/.shm files independently cannot.
        let result = sqlite3_backup_step(backup, -1)
        let finish = sqlite3_backup_finish(backup)
        guard result == SQLITE_DONE else { throw Failure.sqlite(result) }
        try checked(finish)
        // Consolidate any WAL before publishing only the database file.
        try checked(sqlite3_exec(writer, "PRAGMA journal_mode=DELETE", nil, nil, nil))
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        try checked(sqlite3_prepare_v2(writer, "PRAGMA quick_check", -1, &statement, nil))
        guard sqlite3_step(statement) == SQLITE_ROW,
              let value = sqlite3_column_text(statement, 0), String(cString: value) == "ok" else {
            throw Failure.invalidBackup
        }
    }

    private static func checked(_ result: Int32) throws {
        guard result == SQLITE_OK else { throw Failure.sqlite(result) }
    }
}
