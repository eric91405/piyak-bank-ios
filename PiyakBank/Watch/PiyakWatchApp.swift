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
// ① 실시간 적산
struct WatchAccrualPage: View {
    @EnvironmentObject var sync: WatchSync
    @State private var now = Date()
    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: 0x2A2118), .black],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            VStack(spacing: 6) {
                Image("piyak_base")
                    .resizable().scaledToFit()
                    .frame(height: 50)
                Text(amount.won)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(hex: 0xFFD64D))
                    .minimumScaleFactor(0.6).lineLimit(1)
                Text(statusLabel)
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 10).padding(.vertical, 3)
                    .background(statusColor.opacity(0.25), in: Capsule())
                    .foregroundStyle(statusColor)
                if state.isRunning && state.wage > 0 {
                    Text("시급 \(state.wage.won)")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .onReceive(tick) { now = $0 }
    }

    private var statusLabel: String {
        state.isPaused ? "일시정지" : (state.isRunning ? "적립 중" : "대기")
    }
    private var statusColor: Color {
        state.isPaused ? Color(hex: 0xFFD64D)
        : (state.isRunning ? Color(hex: 0xFF9E8A) : .gray)
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
            let s = sync.lastReceived
            if s?.isRunning == true && s?.isPaused == true {
                Button("재개") { sync.sendCommand("resume") }
                    .tint(Color(hex: 0xFF9E8A))
                Button("정지") { sync.sendCommand("stop") }
                    .tint(.red)
            } else if s?.isRunning == true {
                Button("일시정지") { sync.sendCommand("pause") }
                    .tint(Color(hex: 0xFFD64D))
                Button("정지") { sync.sendCommand("stop") }
                    .tint(.red)
            } else {
                Button("근무 시작") { sync.sendCommand("start", wage: 10000) }
                    .tint(Color(hex: 0xFF9E8A))
            }
        }
        .buttonStyle(.borderedProminent)
    }
}

// ③ 캐릭터 (폰 착용 상태 동기화)
struct WatchCharacterPage: View {
    @EnvironmentObject var sync: WatchSync

    private var equipped: [String: String] {
        sync.lastReceived?.equipped ?? [:]
    }

    var body: some View {
        ZStack {
            if let bg = equipped["bg"] {
                Image(assetName(bg))
                    .resizable().scaledToFill()
                    .ignoresSafeArea()
            } else {
                Color(hex: 0xFFF7EC).ignoresSafeArea()
            }
            ZStack {
                Image(equipped["bodyFront"].map(assetName) ?? "piyak_base")
                    .resizable().scaledToFit()
                ForEach(["neck", "eyes", "headTop"], id: \.self) { slot in
                    if let id = equipped[slot] {
                        Image(assetName(id)).resizable().scaledToFit()
                    }
                }
            }
            .padding(14)
        }
    }
}
