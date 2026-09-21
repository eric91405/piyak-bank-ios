import Foundation
import SwiftData

// Shared by separate old/current executables, both compiled as module PiyakBank.
// These transport types do not replace or modify either version's @Model types.
enum LegacyFixture {
    static let reference = ISO8601DateFormatter().date(from: "2026-09-01T14:30:00Z")!
    static let now = reference.addingTimeInterval(3 * 86_400 + 3_600)
    static let activeID = "legacy-active"
    static let oldBalance = 63_997
    static let convertedBalance = 3_199
    static let closedPay = 28_999

    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    static func require(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
        guard try condition() else { throw Failure(message: message) }
    }

    static func write<T: Encodable>(_ value: T, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(value).write(to: url, options: .atomic)
    }

    static func read<T: Decodable>(_ type: T.Type, at url: URL) throws -> T {
        try JSONDecoder().decode(type, from: Data(contentsOf: url))
    }
}

struct LegacySnapshot: Codable, Equatable {
    struct Record: Codable, Equatable {
        let id: String
        let startedAt: Date
        let endedAt: Date?
        let segmentsData: Data
        let isActive: Bool
    }
    struct Ownership: Codable, Equatable {
        let catalogId: String
        let acquiredAt: Date
        let equippedSlotRaw: String?
    }
    struct Catalog: Codable, Equatable {
        let id: String
        let slotRaw: String
        let displayName: String
        let price: Int
        let isIAP: Bool
        let isDefaultOwned: Bool
    }
    struct Transaction: Codable, Equatable {
        let id: UUID
        let amount: Int
        let kindRaw: String
        let date: Date
        let relatedId: String?
        let note: String?
    }
    let records: [Record]
    let ownership: [Ownership]
    let catalog: [Catalog]
    let transactions: [Transaction]

    @MainActor init(context: ModelContext) throws {
        records = try context.fetch(FetchDescriptor<WorkSession>()).map {
            Record(id: $0.id, startedAt: $0.startedAt, endedAt: $0.endedAt,
                   segmentsData: $0.segmentsData, isActive: $0.isActive)
        }.sorted { $0.id < $1.id }
        ownership = try context.fetch(FetchDescriptor<OwnedItem>()).map {
            Ownership(catalogId: $0.catalogId, acquiredAt: $0.acquiredAt, equippedSlotRaw: $0.equippedSlotRaw)
        }.sorted { $0.catalogId < $1.catalogId }
        catalog = try context.fetch(FetchDescriptor<CatalogItem>()).map {
            Catalog(id: $0.id, slotRaw: $0.slotRaw, displayName: $0.displayName, price: $0.price,
                    isIAP: $0.isIAP, isDefaultOwned: $0.isDefaultOwned)
        }.sorted { $0.id < $1.id }
        transactions = try context.fetch(FetchDescriptor<PointTransaction>()).map {
            Transaction(id: $0.id, amount: $0.amount, kindRaw: $0.kindRaw, date: $0.date,
                        relatedId: $0.relatedId, note: $0.note)
        }.sorted { $0.id.uuidString < $1.id.uuidString }
    }
}
