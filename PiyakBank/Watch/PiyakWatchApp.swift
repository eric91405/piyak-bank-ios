import SwiftUI
import WatchConnectivity
import Combine

@main
struct PiyakWatchApp: App {
    @StateObject private var sync = WatchSync()
    var body: some Scene {
        WindowGroup {
            WatchRootView().environmentObject(sync)
                .onAppear { sync.activate() }
        }
    }
}

struct WatchRootView: View {
    @EnvironmentObject var sync: WatchSync

    var body: some View {
        TabView {
            WatchAccrualPage().tag(0)   // ① 실시간 적산
            WatchControlPage().tag(1)   // ② 시작/정지 제어
            WatchCharacterPage().tag(2) // ③ 삐약이
        }
        .tabViewStyle(.verticalPage)
    }
}

// ① 실시간 적산
struct WatchAccrualPage: View {
    @EnvironmentObject var sync: WatchSync
    @State private var now = Date()
    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 8) {
            Text("🐤").font(.system(size: 32))
            Text(amount.won).font(.system(size: 26, weight: .bold, design: .rounded))
            Text(state.isRunning ? "적립 중" : "대기")
                .font(.footnote).foregroundStyle(.secondary)
        }
        .onReceive(tick) { now = $0 }
    }
    private var state: SessionStatePayload {
        sync.lastReceived ?? SessionStatePayload(snapshot:
            .init(isRunning: false, isPaused: false, sessionId: nil,
                  startedAt: nil, accrued: 0, wage: 0))
    }
    private var amount: Int {
        guard let start = state.startedAt, state.isRunning, !state.isPaused else { return state.accrued }
        let extra = floorToInt(Decimal(state.wage) / 3600 * Decimal(now.timeIntervalSince(start)))
        return max(state.accrued, extra)
    }
}

// ② 제어 (워치 → 폰 명령)
struct WatchControlPage: View {
    @EnvironmentObject var sync: WatchSync
    var body: some View {
        VStack(spacing: 10) {
            if sync.lastReceived?.isRunning == true {
                Button("일시정지") { sync.sendCommand("pause") }
                Button("정지", role: .destructive) { sync.sendCommand("stop") }
            } else {
                Button("근무 시작") { sync.sendCommand("start", wage: 10000) }
            }
        }
        .buttonStyle(.borderedProminent)
    }
}

// ③ 캐릭터
struct WatchCharacterPage: View {
    var body: some View {
        ZStack { Color(hex: 0xFFF7EC).ignoresSafeArea(); Text("🐤").font(.system(size: 70)) }
    }
}
