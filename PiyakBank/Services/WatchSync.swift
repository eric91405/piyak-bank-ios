import Foundation
import WatchConnectivity
import Combine
#if os(iOS)
import SceneKit
import UIKit
#endif

struct SessionStatePayload: Codable, Sendable {
    var snapshot: SessionSnapshot
    var equipped: [String: String]
    var portrait: Data?
}

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
    private var lastPortrait: Data?
    private var portraitTask: Task<Void, Never>?

    func activate() {
        if let data = UserDefaults.standard.data(forKey: "watch_cached_state") {
            lastReceived = try? JSONDecoder().decode(SessionStatePayload.self, from: data)
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
        #if os(iOS)
        let changed = equipped != lastEquipped
        #endif
        lastEquipped = equipped
        #if os(iOS)
        if let session, session.activationState == .activated, session.isPaired,
           session.isWatchAppInstalled, changed || (lastPortrait == nil && portraitTask == nil) {
            portraitTask?.cancel()
            portraitTask = Task { [weak self] in
                let data = await Task.detached(priority: .utility) {
                    let scene = PiyakScene.make(equipped: equipped, animated: false, icon: true)
                    let renderer = SCNRenderer(device: nil, options: nil)
                    renderer.scene = scene
                    renderer.pointOfView = scene.rootNode.childNodes.first { $0.camera != nil }
                    return renderer.snapshot(atTime: 0, with: CGSize(width: 144, height: 144), antialiasingMode: .multisampling2X).pngData()
                }.value
                guard !Task.isCancelled, let self, self.lastEquipped == equipped else { return }
                self.lastPortrait = data
                self.portraitTask = nil
                if let snapshot = self.lastSnapshot { self.send(snapshot: snapshot) }
            }
        }
        #endif
        if let snapshot = lastSnapshot { send(snapshot: snapshot) }
    }

    private var stateData: Data? {
        guard let snapshot = lastSnapshot else { return nil }
        return try? JSONEncoder().encode(SessionStatePayload(snapshot: snapshot, equipped: lastEquipped, portrait: lastPortrait))
    }

    func requestState() {
        guard let session, session.activationState == .activated else { return }
        isReachable = session.isReachable
        if let data = session.receivedApplicationContext["state"] as? Data { receive(data) }
        guard session.isReachable else { return }
        session.sendMessage(["requestState": true], replyHandler: { [weak self] reply in
            if let data = reply["state"] as? Data {
                Task { @MainActor in self?.receive(data) }
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
        guard let payload = try? JSONDecoder().decode(SessionStatePayload.self, from: data) else { return }
        if let current = lastReceived?.snapshot.capturedAt, let incoming = payload.snapshot.capturedAt, incoming < current { return }
        lastReceived = payload
        UserDefaults.standard.set(data, forKey: "watch_cached_state")
    }

    nonisolated func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
        Task { @MainActor in
            self.isReachable = session.isReachable
            #if os(iOS)
            self.send(equipped: self.lastEquipped)
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
            self.onRequestSnapshot?()
            #endif
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
            replyHandler(reply)
        }
    }
    #if os(iOS)
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) { session.activate() }
    #endif
}

private enum SessionSyncError: LocalizedError {
    case unavailable
    var errorDescription: String? { "iPhone 앱을 열어 초기 설정을 마쳐 주세요." }
}
