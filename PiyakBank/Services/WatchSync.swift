import Foundation
import WatchConnectivity
import Combine
#if os(iOS)
import SceneKit
import UIKit
#endif

@MainActor
final class WatchSync: NSObject, ObservableObject, WCSessionDelegate {
    @Published private(set) var lastReceived: SessionStatePayload?
    @Published private(set) var isReachable = false
    @Published private(set) var isSending = false
    @Published var errorMessage: String?
    var onRemoteCommand: ((WatchCommand) throws -> Void)?
    var onRequestSnapshot: (() -> Void)?

    private let session: WCSession? = WCSession.isSupported() ? .default : nil
    private var lastSnapshot: SessionSnapshot?
    private var lastEquipped: [String: String] = [:]
    private var lastPortrait: WatchPortrait?
    private var receivedCache = WatchStateCache()
    private var outgoingState = WatchStateOutbox()
    private var portraitTask: Task<Void, Never>?
    private var lastQueuedPortraitIdentity: String?
    private var legacyWatchRequestedPortrait = false
    private var restoredCache = false
    private static let cacheKey = "watch_cached_state_v2"
    private static let sentPortraitKey = "watch_sent_portrait_v1"
    private static let issuedAtKey = "watch_state_last_issued_at"
    private nonisolated static let portraitTransferKey = "piyakPortraitV1"

    func activate() {
        if !restoredCache {
            restoredCache = true
            let defaults = UserDefaults.standard
            outgoingState = WatchStateOutbox(lastIssuedAt: defaults.object(forKey: Self.issuedAtKey) as? Date)
            if let data = defaults.data(forKey: Self.cacheKey),
               let cache = try? JSONDecoder().decode(WatchStateCache.self, from: data) {
                receivedCache = cache
            } else if let data = defaults.data(forKey: "watch_cached_state"),
                      let state = try? JSONDecoder().decode(SessionStatePayload.self, from: data) {
                receivedCache = WatchStateCache(legacyState: state)
            }
            lastReceived = receivedCache.state
            #if os(iOS)
            if let data = defaults.data(forKey: Self.sentPortraitKey),
               let portrait = try? JSONDecoder().decode(WatchPortrait.self, from: data), portrait.isValid {
                lastPortrait = portrait
            }
            #endif
        }
        session?.delegate = self
        session?.activate()
    }

    func send(snapshot: SessionSnapshot) {
        lastSnapshot = snapshot
        guard let session, session.activationState == .activated, let data = stateData else { return }
        #if os(iOS)
        guard session.isPaired, session.isWatchAppInstalled else { return }
        #endif
        do { try session.updateApplicationContext(["state": data]) }
        catch { errorMessage = "워치 동기화를 기다리고 있어요. 앱을 다시 열면 재시도해요." }
        if session.isReachable {
            session.sendMessage(["state": data], replyHandler: nil, errorHandler: { _ in })
        }
    }

    func send(equipped: [String: String]) {
        lastEquipped = equipped
        #if os(iOS)
        preparePortraitIfNeeded()
        sendPortrait()
        #endif
        if let snapshot = lastSnapshot { send(snapshot: snapshot) }
    }

    /// Status changes are frequent; the rendered portrait only changes when the
    /// person re-equips something. Shipping the PNG with every state update wastes
    /// the message budget, so state stays small and the portrait moves separately.
    private var stateData: Data? {
        guard let snapshot = lastSnapshot else { return nil }
        let previous = outgoingState.lastIssuedAt
        let payload = outgoingState.payload(snapshot: snapshot, equipped: lastEquipped, now: .now)
        if payload.stateIssuedAt != previous {
            UserDefaults.standard.set(payload.stateIssuedAt, forKey: Self.issuedAtKey)
        }
        return try? JSONEncoder().encode(payload)
    }

    private var expectedPortraitIdentity: String { WatchPortrait.identity(for: lastEquipped) }

    #if os(iOS)
    private func preparePortraitIfNeeded() {
        guard let session, session.activationState == .activated,
              session.isPaired, session.isWatchAppInstalled,
              lastPortrait?.identity != expectedPortraitIdentity, portraitTask == nil else { return }
        let equipped = lastEquipped
        // Do not launch overlapping SceneKit renders during rapid outfit changes.
        // Finish the current render, discard a stale result, then render the latest.
        portraitTask = Task { [weak self] in
            let data = await Task.detached(priority: .utility) {
                let scene = PiyakScene.make(equipped: equipped, animated: false, icon: true)
                let renderer = SCNRenderer(device: nil, options: nil)
                renderer.scene = scene
                renderer.pointOfView = scene.rootNode.childNodes.first { $0.camera != nil }
                return renderer.snapshot(atTime: 0, with: CGSize(width: 144, height: 144), antialiasingMode: .multisampling2X).pngData()
            }.value
            guard let self else { return }
            self.portraitTask = nil
            guard self.lastEquipped == equipped else {
                self.preparePortraitIfNeeded()
                return
            }
            guard let data else { return }
            let portrait = WatchPortrait(equipped: equipped, data: data)
            guard portrait.isValid else { return }
            self.lastPortrait = portrait
            if let encoded = try? JSONEncoder().encode(portrait) {
                UserDefaults.standard.set(encoded, forKey: Self.sentPortraitKey)
            }
            self.sendPortrait()
        }
    }

    private var portraitData: Data? {
        guard let portrait = lastPortrait, portrait.identity == expectedPortraitIdentity else { return nil }
        return try? JSONEncoder().encode(portrait)
    }

    private func sendPortrait(force: Bool = false) {
        guard let session, session.activationState == .activated,
              session.isPaired, session.isWatchAppInstalled, let data = portraitData else { return }
        let identity = expectedPortraitIdentity
        let pending = session.outstandingUserInfoTransfers.filter { $0.userInfo[Self.portraitTransferKey] is Data }
        for transfer in pending where transfer.userInfo["portraitIdentity"] as? String != identity {
            transfer.cancel()
        }
        guard !pending.contains(where: { $0.userInfo["portraitIdentity"] as? String == identity }),
              force || lastQueuedPortraitIdentity != identity else { return }
        var message: [String: Any] = [Self.portraitTransferKey: data, "portraitIdentity": identity]
        if legacyWatchRequestedPortrait { message["portrait"] = lastPortrait?.data }
        session.transferUserInfo(message)
        lastQueuedPortraitIdentity = identity
    }
    #endif

    func requestState() {
        guard let session, session.activationState == .activated else { return }
        isReachable = session.isReachable
        if let data = session.receivedApplicationContext["state"] as? Data { receive(data) }
        guard session.isReachable else { return }
        session.sendMessage(["requestState": true, "portraitIdentity": receivedCache.displayedPortraitIdentity ?? ""], replyHandler: { [weak self] reply in
            let state = reply["state"] as? Data
            let portrait = reply[Self.portraitTransferKey] as? Data
            Task { @MainActor in
                if let portrait { self?.receivePortrait(portrait) }
                if let state { self?.receive(state) }
            }
        }, errorHandler: { _ in })
    }

    func sendCommand(_ action: String) {
        guard !isSending else { return }
        guard let session, session.activationState == .activated, session.isReachable,
              let current = lastReceived?.snapshot else {
            errorMessage = "iPhone과 연결한 뒤 다시 눌러 주세요. 오프라인 요청은 나중에 실행되지 않아요."
            return
        }
        let command = WatchCommand(action: action, sessionId: current.sessionId)
        guard let data = try? JSONEncoder().encode(command) else { return }
        isSending = true
        session.sendMessage(["command": data], replyHandler: { [weak self] reply in
            let state = reply["state"] as? Data
            let error = reply["error"] as? String
            Task { @MainActor in
                self?.isSending = false
                if let state { self?.receive(state) }
                self?.errorMessage = error
            }
        }, errorHandler: { [weak self] _ in
            Task { @MainActor in
                self?.isSending = false
                self?.errorMessage = "확인 응답을 받지 못했어요. iPhone의 근무 상태를 확인한 뒤 다시 시도해 주세요."
            }
        })
    }

    private func receive(_ data: Data) {
        guard let payload = try? JSONDecoder().decode(SessionStatePayload.self, from: data),
              receivedCache.receive(payload) else { return }
        persistReceivedCache()
    }

    private func receivePortrait(_ data: Data) {
        guard let portrait = try? JSONDecoder().decode(WatchPortrait.self, from: data),
              receivedCache.receive(portrait) else { return }
        persistReceivedCache()
    }

    private func persistReceivedCache() {
        lastReceived = receivedCache.state
        if let data = try? JSONEncoder().encode(receivedCache) {
            UserDefaults.standard.set(data, forKey: Self.cacheKey)
        }
    }

    nonisolated func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
        Task { @MainActor in
            self.isReachable = session.isReachable
            #if os(iOS)
            self.send(equipped: self.lastEquipped)
            self.sendPortrait()
            self.onRequestSnapshot?()
            #else
            self.requestState()
            #endif
        }
    }
    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in
            self.isReachable = session.isReachable
            #if os(watchOS)
            self.requestState()
            #else
            self.preparePortraitIfNeeded()
            self.sendPortrait()
            self.onRequestSnapshot?()
            #endif
        }
    }
    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        if let data = userInfo[Self.portraitTransferKey] as? Data {
            Task { @MainActor in self.receivePortrait(data) }
        } else if let data = userInfo["portrait"] as? Data {
            Task { @MainActor in
                if self.receivedCache.receiveLegacyPortrait(data) { self.persistReceivedCache() }
            }
        }
    }
    nonisolated func session(_ session: WCSession, didReceiveApplicationContext context: [String: Any]) {
        guard let data = context["state"] as? Data else { return }
        Task { @MainActor in self.receive(data) }
    }
    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        guard let data = message["state"] as? Data else { return }
        Task { @MainActor in self.receive(data) }
    }
    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any],
                             replyHandler: @escaping ([String: Any]) -> Void) {
        let commandData = message["command"] as? Data
        let requestsState = message["requestState"] as? Bool == true
        let knownPortraitIdentity = message["portraitIdentity"] as? String
        Task { @MainActor in
            var reply: [String: Any] = [:]
            do {
                if let commandData {
                    guard let handler = self.onRemoteCommand else { throw SessionSyncError.unavailable }
                    try handler(JSONDecoder().decode(WatchCommand.self, from: commandData))
                }
            } catch { reply["error"] = error.localizedDescription }
            self.onRequestSnapshot?()
            if let data = self.stateData { reply["state"] = data }
            #if os(iOS)
            if requestsState { self.legacyWatchRequestedPortrait = knownPortraitIdentity == nil }
            if requestsState, knownPortraitIdentity != self.expectedPortraitIdentity {
                self.preparePortraitIfNeeded()
                // Recover a fresh Watch installation immediately when the small
                // portrait fits the interactive reply; larger images use the queue.
                if let data = self.portraitData, data.count <= 48 * 1_024 {
                    if knownPortraitIdentity == nil, var payload = self.outgoingState.state {
                        // Older Watch versions only read the original combined
                        // state reply. Send that format only for their explicit request.
                        payload.portrait = self.lastPortrait?.data
                        payload.portraitIdentity = nil
                        reply["state"] = try? JSONEncoder().encode(payload)
                    } else {
                        reply[Self.portraitTransferKey] = data
                    }
                } else {
                    self.sendPortrait(force: true)
                }
            }
            #endif
            replyHandler(reply)
        }
    }
    #if os(iOS)
    nonisolated func session(_ session: WCSession, didFinish userInfoTransfer: WCSessionUserInfoTransfer, error: Error?) {
        guard error != nil, userInfoTransfer.userInfo[Self.portraitTransferKey] is Data,
              let identity = userInfoTransfer.userInfo["portraitIdentity"] as? String else { return }
        Task { @MainActor in
            if self.lastQueuedPortraitIdentity == identity { self.lastQueuedPortraitIdentity = nil }
        }
    }
    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor in
            self.lastQueuedPortraitIdentity = nil
            self.send(equipped: self.lastEquipped)
            self.onRequestSnapshot?()
        }
    }
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) { session.activate() }
    #endif
}

private enum SessionSyncError: LocalizedError {
    case unavailable
    var errorDescription: String? { "iPhone 앱을 열어 초기 설정을 마쳐 주세요." }
}
