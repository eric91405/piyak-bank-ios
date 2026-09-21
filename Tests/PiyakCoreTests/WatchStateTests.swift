import Foundation
import Testing
@testable import PiyakCore

private let watchOutfitA = ["bodyFront": "bodyFront.hoodie_mint", "floorProp": "floorProp.plant"]
private let watchOutfitB = ["bodyFront": "bodyFront.overalls", "floorProp": "floorProp.plant"]

private func watchPayload(equipped: [String: String] = watchOutfitA,
                          time: TimeInterval = 10, legacy: Bool = false,
                          portrait: Data? = nil) -> SessionStatePayload {
    var snapshot = SessionSnapshot.empty
    snapshot.capturedAt = Date(timeIntervalSince1970: time)
    return SessionStatePayload(snapshot: snapshot, equipped: equipped, portrait: portrait,
                               portraitIdentity: legacy ? nil : WatchPortrait.identity(for: equipped))
}

@Test func portraitIdentityUsesEquipmentAndRendererVersion() {
    let reordered = Dictionary(uniqueKeysWithValues: watchOutfitA.sorted { $0.key > $1.key })
    #expect(WatchPortrait.identity(for: reordered) == WatchPortrait.identity(for: watchOutfitA))
    #expect(WatchPortrait.identity(for: watchOutfitA) != WatchPortrait.identity(for: watchOutfitB))
    #expect(WatchPortrait.identity(for: watchOutfitA, version: 1) != WatchPortrait.identity(for: watchOutfitA, version: 2))
    #expect(WatchPortrait.identity(for: ["a:": "b"]) != WatchPortrait.identity(for: ["a": ":b"]))
}

@Test func portraitBeforeStateSurvivesAppTermination() throws {
    let portrait = WatchPortrait(equipped: watchOutfitA, data: Data([1, 2, 3]))
    var cache = WatchStateCache()
    let receivedPortrait = cache.receive(portrait)
    #expect(receivedPortrait)
    #expect(cache.state == nil)
    #expect(cache.displayedPortraitIdentity == nil)
    let stored = try JSONEncoder().encode(cache)
    var restored = try JSONDecoder().decode(WatchStateCache.self, from: stored)
    let receivedState = restored.receive(watchPayload())
    #expect(receivedState)
    #expect(restored.state?.portrait == portrait.data)
    #expect(restored.displayedPortraitIdentity == portrait.identity)
}

@Test func stateBeforePortraitRecoversAndStatusRefreshKeepsTheImage() throws {
    var cache = WatchStateCache()
    let portrait = WatchPortrait(equipped: watchOutfitA, data: Data([1]))
    let receivedState = cache.receive(watchPayload())
    #expect(receivedState)
    #expect(cache.displayedPortraitIdentity == nil)
    let receivedPortrait = cache.receive(portrait)
    let refreshedState = cache.receive(watchPayload(time: 20))
    #expect(receivedPortrait)
    #expect(refreshedState)
    #expect(cache.state?.portrait == portrait.data)
    #expect(cache.displayedPortraitIdentity == portrait.identity)
    let encoded = try JSONEncoder().encode(cache)
    let restored = try JSONDecoder().decode(WatchStateCache.self, from: encoded)
    #expect(restored.displayedPortraitIdentity == portrait.identity)
}

@Test func delayedPortraitCannotReplaceNewerEquipment() {
    var cache = WatchStateCache()
    let first = WatchPortrait(equipped: watchOutfitA, data: Data([1]))
    let second = WatchPortrait(equipped: watchOutfitB, data: Data([2]))
    cache.receive(watchPayload())
    cache.receive(first)
    cache.receive(watchPayload(equipped: watchOutfitB, time: 20))
    #expect(cache.state?.portrait == nil)
    cache.receive(second)
    cache.receive(first)
    #expect(cache.state?.portrait == second.data)
    #expect(cache.displayedPortraitIdentity == second.identity)
    let receivedStaleState = cache.receive(watchPayload(time: 10))
    #expect(!receivedStaleState)
    #expect(cache.state?.equipped == watchOutfitB)
}

@Test func futurePortraitWaitsForItsMatchingStateAndSurvivesRelaunch() throws {
    var cache = WatchStateCache()
    let first = WatchPortrait(equipped: watchOutfitA, data: Data([1]))
    let second = WatchPortrait(equipped: watchOutfitB, data: Data([2]))
    cache.receive(watchPayload())
    cache.receive(first)
    cache.receive(second)
    #expect(cache.state?.portrait == first.data)
    let encoded = try JSONEncoder().encode(cache)
    var restored = try JSONDecoder().decode(WatchStateCache.self, from: encoded)
    restored.receive(watchPayload(equipped: watchOutfitB, time: 20))
    #expect(restored.state?.portrait == second.data)
}

@Test func portraitCacheIsBoundedWithoutEvictingTheCurrentOutfit() {
    var cache = WatchStateCache()
    let displayed = WatchPortrait(equipped: watchOutfitA, data: Data([1]))
    cache.receive(watchPayload())
    cache.receive(displayed)
    for index in 0..<20 {
        cache.receive(WatchPortrait(equipped: ["headTop": "hat-\(index)"], data: Data([2])))
    }
    #expect(cache.portraits.count == 3)
    #expect(cache.state?.portrait == displayed.data)
    #expect(cache.displayedPortraitIdentity == displayed.identity)
}

@Test func rendererVersionAndEquipmentMustBothMatchTheState() {
    var cache = WatchStateCache()
    var newer = WatchPortrait(equipped: watchOutfitA, data: Data([2]))
    newer.version = WatchPortrait.rendererVersion + 1
    cache.receive(newer)
    cache.receive(watchPayload())
    #expect(cache.state?.portrait == nil)
    var payload = watchPayload(time: 20)
    payload.portraitIdentity = newer.identity
    cache.receive(payload)
    #expect(cache.state?.portrait == newer.data)
    payload = watchPayload(equipped: watchOutfitB, time: 30)
    payload.portraitIdentity = newer.identity
    cache.receive(payload)
    #expect(cache.state?.portrait == nil)
}

@Test func legacyEmbeddedPortraitMigratesButRawPNGCannotOverrideLabelledState() throws {
    let legacy = watchPayload(legacy: true, portrait: Data([1]))
    var cache = WatchStateCache(legacyState: legacy)
    #expect(cache.state?.portrait == Data([1]))
    let receivedLegacy = cache.receiveLegacyPortrait(Data([2]))
    #expect(receivedLegacy)
    #expect(cache.state?.portrait == Data([2]))
    cache.receive(watchPayload(time: 20))
    let receivedUnlabelled = cache.receiveLegacyPortrait(Data([3]))
    #expect(!receivedUnlabelled)
    #expect(cache.state?.portrait == Data([2]))

    let oldJSON = try JSONEncoder().encode(legacy)
    let decoded = try JSONDecoder().decode(SessionStatePayload.self, from: oldJSON)
    #expect(decoded.portraitIdentity == nil)
}

@Test func legacyPortraitBeforeStateIsPersistedAndDiscardedForNewProtocol() throws {
    var cache = WatchStateCache()
    let receivedLegacy = cache.receiveLegacyPortrait(Data([1]))
    #expect(receivedLegacy)
    let data = try JSONEncoder().encode(cache)
    var legacy = try JSONDecoder().decode(WatchStateCache.self, from: data)
    legacy.receive(watchPayload(legacy: true))
    #expect(legacy.state?.portrait == Data([1]))
    var modern = try JSONDecoder().decode(WatchStateCache.self, from: data)
    modern.receive(watchPayload())
    #expect(modern.state?.portrait == nil)
}

@Test func invalidOrDuplicatePortraitDoesNotCauseRepeatedCacheWrites() {
    var cache = WatchStateCache()
    let receivedEmpty = cache.receive(WatchPortrait(equipped: watchOutfitA, data: Data()))
    let receivedOversized = cache.receive(WatchPortrait(equipped: watchOutfitA, data: Data(repeating: 1, count: 512 * 1_024 + 1)))
    #expect(!receivedEmpty)
    #expect(!receivedOversized)
    let portrait = WatchPortrait(equipped: watchOutfitA, data: Data([1]))
    let receivedPortrait = cache.receive(portrait)
    let receivedDuplicate = cache.receive(portrait)
    #expect(receivedPortrait)
    #expect(!receivedDuplicate)
    cache.receive(watchPayload())
    let receivedDuplicateState = cache.receive(watchPayload())
    #expect(!receivedDuplicateState)
}

@Test func equipmentMessagesWithTheSameSnapshotCannotArriveBackwards() throws {
    let snapshot = watchPayload().snapshot
    let issued = Date(timeIntervalSince1970: 100)
    var outbox = WatchStateOutbox()
    let first = outbox.payload(snapshot: snapshot, equipped: watchOutfitA, now: issued)
    let second = outbox.payload(snapshot: snapshot, equipped: watchOutfitB, now: issued)
    let resend = outbox.payload(snapshot: snapshot, equipped: watchOutfitB, now: issued.addingTimeInterval(50))
    #expect(resend == second)
    #expect(first.snapshot.capturedAt == second.snapshot.capturedAt)
    let firstIssued = try #require(first.stateIssuedAt)
    let secondIssued = try #require(second.stateIssuedAt)
    #expect(secondIssued > firstIssued)

    var cache = WatchStateCache()
    cache.receive(second)
    let staleAccepted = cache.receive(first)
    #expect(!staleAccepted)
    #expect(cache.state?.equipped == watchOutfitB)
    let saved = try JSONEncoder().encode(cache)
    var restored = try JSONDecoder().decode(WatchStateCache.self, from: saved)
    let staleAfterRelaunch = restored.receive(first)
    #expect(!staleAfterRelaunch)
}

@Test func stateOrderingSurvivesBackwardClockWithoutChangingEarningsDates() throws {
    let original = watchPayload(time: 100).snapshot
    var firstRun = WatchStateOutbox()
    let first = firstRun.payload(snapshot: original, equipped: watchOutfitA,
                                 now: Date(timeIntervalSince1970: 200))
    var relaunched = WatchStateOutbox(lastIssuedAt: firstRun.lastIssuedAt)
    let earlier = watchPayload(time: 50).snapshot
    let next = relaunched.payload(snapshot: earlier, equipped: watchOutfitB,
                                  now: Date(timeIntervalSince1970: 60))
    let firstIssued = try #require(first.stateIssuedAt)
    let nextIssued = try #require(next.stateIssuedAt)
    #expect(nextIssued > firstIssued)
    #expect(next.snapshot == earlier)
    var cache = WatchStateCache()
    cache.receive(first)
    let newerAccepted = cache.receive(next)
    #expect(newerAccepted)
    #expect(cache.state?.equipped == watchOutfitB)

    var legacyCache = WatchStateCache()
    legacyCache.receive(watchPayload(time: 100, legacy: true))
    let olderLegacyAccepted = legacyCache.receive(watchPayload(time: 50, legacy: true))
    #expect(!olderLegacyAccepted)
}

@Test func orderedStateReplacesPersistedLegacyCacheAfterClockCorrection() throws {
    let now = Date(timeIntervalSince1970: 1_780_012_800)
    let future = now.addingTimeInterval(7 * 24 * 60 * 60)
    let legacy = watchPayload(time: future.timeIntervalSince1970, legacy: true,
                              portrait: Data([1]))
    let stored = try JSONEncoder().encode(WatchStateCache(legacyState: legacy))
    var cache = try JSONDecoder().decode(WatchStateCache.self, from: stored)
    let updatedPortrait = WatchPortrait(equipped: watchOutfitB, data: Data([2]))
    cache.receive(updatedPortrait)

    var outbox = WatchStateOutbox()
    let modern = outbox.payload(snapshot: watchPayload(time: now.timeIntervalSince1970).snapshot,
                                equipped: watchOutfitB, now: now)
    let received = cache.receive(modern)

    #expect(received)
    #expect(cache.state?.snapshot == modern.snapshot)
    #expect(cache.state?.stateIssuedAt == now)
    #expect(cache.state?.equipped == watchOutfitB)
    #expect(cache.state?.portrait == updatedPortrait.data)
    #expect(cache.displayedPortraitIdentity == updatedPortrait.identity)
}

@Test func orderedCacheRejectsDelayedLegacyStateAndPortraitAfterRelaunch() throws {
    var outbox = WatchStateOutbox()
    let first = outbox.payload(snapshot: watchPayload(time: 100).snapshot,
                               equipped: watchOutfitB, now: Date(timeIntervalSince1970: 100))
    var original = WatchStateCache()
    original.receive(first)
    original.receive(WatchPortrait(equipped: watchOutfitB, data: Data([2])))
    let stored = try JSONEncoder().encode(original)
    var cache = try JSONDecoder().decode(WatchStateCache.self, from: stored)
    let expectedState = cache.state
    let expectedPortraits = cache.portraits

    // A legacy message can have a later earnings date without being newer state.
    let stale = watchPayload(time: 100 + 7 * 24 * 60 * 60, legacy: true,
                             portrait: Data([9]))
    let receivedLegacy = cache.receive(stale)
    let receivedRawPortrait = cache.receiveLegacyPortrait(Data([9]))
    #expect(!receivedLegacy)
    #expect(!receivedRawPortrait)
    #expect(cache.state == expectedState)
    #expect(cache.portraits == expectedPortraits)

    let next = outbox.payload(snapshot: watchPayload(time: 50).snapshot,
                              equipped: watchOutfitA, now: Date(timeIntervalSince1970: 50))
    let receivedModern = cache.receive(next)
    #expect(receivedModern)
    #expect(cache.state?.equipped == watchOutfitA)
    #expect(cache.state?.portrait == nil)
    let receivedOlderModern = cache.receive(first)
    #expect(!receivedOlderModern)
}
