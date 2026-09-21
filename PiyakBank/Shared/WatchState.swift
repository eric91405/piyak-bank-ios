import Foundation

struct SessionStatePayload: Codable, Equatable, Sendable {
    var snapshot: SessionSnapshot
    var equipped: [String: String]
    /// Kept for decoding the earlier combined state cache. New state messages omit it.
    var portrait: Data?
    var portraitIdentity: String? = nil
    /// Transport ordering is independent of the snapshot's earnings/calendar date.
    var stateIssuedAt: Date? = nil
}

struct WatchStateOutbox {
    private(set) var state: SessionStatePayload?
    private(set) var lastIssuedAt: Date?

    init(lastIssuedAt: Date? = nil) {
        self.lastIssuedAt = lastIssuedAt.flatMap { $0.timeIntervalSinceReferenceDate.isFinite ? $0 : nil }
    }

    mutating func payload(snapshot: SessionSnapshot, equipped: [String: String], now: Date) -> SessionStatePayload {
        var next = SessionStatePayload(snapshot: snapshot, equipped: equipped, portrait: nil,
                                       portraitIdentity: WatchPortrait.identity(for: equipped),
                                       stateIssuedAt: state?.stateIssuedAt)
        // A resend of identical state retains its original issue time. An outfit
        // change gets its own ordering even when the earnings snapshot is unchanged.
        if let state, next == state { return state }
        var issued = now.timeIntervalSinceReferenceDate.isFinite ? now : (lastIssuedAt ?? .distantPast)
        if let previous = lastIssuedAt, issued <= previous {
            issued = Date(timeIntervalSinceReferenceDate: previous.timeIntervalSinceReferenceDate.nextUp)
        }
        next.stateIssuedAt = issued
        lastIssuedAt = issued
        state = next
        return next
    }
}

struct WatchPortrait: Codable, Equatable, Sendable {
    // Bump when the portrait renderer changes so a cached older rendering is refreshed.
    static let rendererVersion = 1
    let equipped: [String: String]
    let data: Data
    var version = rendererVersion

    var identity: String { Self.identity(for: equipped, version: version) }
    var isValid: Bool { version > 0 && !data.isEmpty && data.count <= 512 * 1_024 }

    static func identity(for equipped: [String: String], version: Int = rendererVersion) -> String {
        // Length prefixes make the identity independent of dictionary order and avoid
        // delimiter collisions without adding a hashing dependency to the Watch app.
        let items = equipped.sorted { $0.key < $1.key }.map {
            "\($0.key.utf8.count):\($0.key)\($0.value.utf8.count):\($0.value)"
        }.joined()
        return "piyak-portrait-\(version)|" + items
    }
}

/// Independent image persistence lets a background portrait arrive before the first
/// state, including when watchOS terminates the app between those two deliveries.
struct WatchStateCache: Codable {
    private(set) var state: SessionStatePayload?
    private(set) var portraits: [WatchPortrait] = []
    private var pendingLegacyPortrait: Data?

    init(legacyState: SessionStatePayload? = nil) {
        if let legacyState { _ = receive(legacyState) }
    }

    var displayedPortraitIdentity: String? {
        guard let state, state.portrait != nil else { return nil }
        return expectedIdentity(for: state)
    }

    @discardableResult
    mutating func receive(_ payload: SessionStatePayload) -> Bool {
        if let current = state?.stateIssuedAt, let incoming = payload.stateIssuedAt {
            if incoming < current { return false }
        } else if let current = state?.snapshot.capturedAt,
                  let incoming = payload.snapshot.capturedAt, incoming < current {
            // Payloads from earlier phone versions do not carry an issue date.
            return false
        }
        let previous = state
        var next = payload
        if let data = payload.portrait {
            let legacyPortrait = WatchPortrait(equipped: payload.equipped, data: data)
            if legacyPortrait.identity == expectedIdentity(for: payload), legacyPortrait.isValid {
                cache(legacyPortrait)
            }
        }
        if payload.portraitIdentity == nil, let data = pendingLegacyPortrait {
            cache(WatchPortrait(equipped: payload.equipped, data: data))
        }
        pendingLegacyPortrait = nil
        next.portrait = portrait(for: next)?.data
        state = next
        trim()
        return previous != next
    }

    @discardableResult
    mutating func receive(_ portrait: WatchPortrait) -> Bool {
        guard portrait.isValid else { return false }
        let oldPortraits = portraits
        let oldState = state
        cache(portrait)
        if var current = state {
            current.portrait = self.portrait(for: current)?.data
            state = current
        }
        trim()
        return oldPortraits != portraits || oldState != state
    }

    /// Compatibility with a phone that still sends an unlabelled PNG. Its old
    /// protocol cannot establish image ordering, so never accept it once a labelled
    /// state is available. New-format transfers always use the identity check above.
    @discardableResult
    mutating func receiveLegacyPortrait(_ data: Data) -> Bool {
        guard state?.portraitIdentity == nil, !data.isEmpty, data.count <= 512 * 1_024 else { return false }
        guard let state else {
            guard pendingLegacyPortrait != data else { return false }
            pendingLegacyPortrait = data
            return true
        }
        return receive(WatchPortrait(equipped: state.equipped, data: data))
    }

    private func expectedIdentity(for state: SessionStatePayload) -> String {
        state.portraitIdentity ?? WatchPortrait.identity(for: state.equipped)
    }

    private func portrait(for state: SessionStatePayload) -> WatchPortrait? {
        portraits.first {
            $0.identity == expectedIdentity(for: state) && $0.equipped == state.equipped && $0.isValid
        }
    }

    private mutating func cache(_ portrait: WatchPortrait) {
        portraits.removeAll { $0.identity == portrait.identity }
        portraits.append(portrait)
    }

    private mutating func trim() {
        // Keep the displayed image plus a small number of out-of-order arrivals.
        // Stale transfers cannot evict the image matching the current equipment.
        while portraits.count > 3 {
            let expected = state.map { expectedIdentity(for: $0) }
            let index = portraits.firstIndex { $0.identity != expected } ?? 0
            portraits.remove(at: index)
        }
    }
}
