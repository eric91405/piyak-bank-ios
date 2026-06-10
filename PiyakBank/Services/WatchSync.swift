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
    // 워치 → 폰 원격 명령
    var command: String?      // "start" | "stop" | "pause" | "resume"
    var commandWage: Int?

    init(snapshot s: SessionSnapshot) {
        isRunning = s.isRunning; isPaused = s.isPaused
        startedAt = s.startedAt; accrued = s.accrued; wage = s.wage
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

    func send(snapshot: SessionSnapshot) {
        print("📤 폰 send 호출:", snapshot.isRunning, "reachable:", session?.isReachable ?? false)
        guard let session, session.activationState == .activated else {
            print("📤 ❌ 세션 비활성")
            return
        }
        let payload = SessionStatePayload(snapshot: snapshot)
        guard let data = try? JSONEncoder().encode(payload) else { return }
        // 즉시 전달 시도 (reachable일 때)
        if session.isReachable {
            session.sendMessage(["state": data], replyHandler: nil)
        }
        // 항상 최신 상태도 보장 (정지/시작 같은 전이 누락 방지)
        try? session.updateApplicationContext(["state": data])
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
