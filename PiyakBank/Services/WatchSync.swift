import Foundation
import WatchConnectivity
import Combine

/// 폰↔워치 공유 페이로드
struct SessionStatePayload: Codable {
    var isRunning: Bool
    var isPaused: Bool
    var startedAt: Date?
    var accrued: Int
    var wage: Int
    var equipped: [String: String]?
    var command: String?
    var commandWage: Int?
    
    init(snapshot s: SessionSnapshot, equipped: [String: String]? = nil) {
        isRunning = s.isRunning; isPaused = s.isPaused
        startedAt = s.startedAt; accrued = s.accrued; wage = s.wage
        self.equipped = equipped
    }
    
    init(command: String, wage: Int? = nil) {
        isRunning = false; isPaused = false; startedAt = nil
        accrued = 0; self.wage = 0
        self.command = command; self.commandWage = wage
    }
}

@MainActor
final class WatchSync: NSObject, ObservableObject, WCSessionDelegate {

    @Published var lastReceived: SessionStatePayload?
    /// 워치에서 받은 명령을 폰 SessionController로 전달
    var onRemoteCommand: ((String, Int?) -> Void)?

    private let session: WCSession? = WCSession.isSupported() ? .default : nil

    func activate() {
        session?.delegate = self
        session?.activate()
    }
    
    private var lastSnapshot: SessionSnapshot?
        private var lastEquipped: [String: String]?

        func send(snapshot: SessionSnapshot) {
            lastSnapshot = snapshot
            guard let session, session.activationState == .activated else { return }
            let payload = SessionStatePayload(snapshot: snapshot, equipped: lastEquipped)
            guard let data = try? JSONEncoder().encode(payload) else { return }
            if session.isReachable {
                session.sendMessage(["state": data], replyHandler: nil)
            }
            try? session.updateApplicationContext(["state": data])
        }

        /// 착용 변경 시 호출 — 마지막 세션 상태에 얹어서 재전송
        func send(equipped: [String: String]) {
            lastEquipped = equipped
            let snap = lastSnapshot ?? SessionSnapshot(isRunning: false, isPaused: false,
                                                       sessionId: nil, startedAt: nil,
                                                       accrued: 0, wage: 0)
            send(snapshot: snap)
        }

    /// 워치 → 폰: 원격 명령 전송
    func sendCommand(_ command: String, wage: Int? = nil) {
        guard let session else { return }
        let payload = SessionStatePayload(command: command, wage: wage)
        guard let data = try? JSONEncoder().encode(payload) else { return }
        if session.isReachable {
            session.sendMessage(["command": data], replyHandler: nil)
        } else {
            try? session.updateApplicationContext(["command": data])
        }
    }

    // MARK: WCSessionDelegate

    nonisolated func session(_ session: WCSession,
                             activationDidCompleteWith state: WCSessionActivationState,
                             error: Error?) {}

    nonisolated func session(_ session: WCSession,
                             didReceiveApplicationContext ctx: [String: Any]) {
        handle(ctx)
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        handle(message)
    }

    private nonisolated func handle(_ dict: [String: Any]) {
        print("📥 수신:", dict.keys)
        let data = (dict["state"] ?? dict["command"]) as? Data
        guard let data, let payload = try? JSONDecoder().decode(SessionStatePayload.self, from: data) else { return }
        Task { @MainActor in
            if let cmd = payload.command {
                self.onRemoteCommand?(cmd, payload.commandWage)
            } else {
                self.lastReceived = payload
            }
        }
    }

    #if os(iOS)
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) { session.activate() }
    #endif
}
