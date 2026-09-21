import SwiftUI
import WatchKit

@main
struct PiyakWatchApp: App {
    @StateObject private var sync = WatchSync()
    @Environment(\.scenePhase) private var phase
    var body: some Scene {
        WindowGroup {
            WatchRootView().environmentObject(sync)
                .onAppear { sync.activate() }
                .onChange(of: phase) { _, value in if value == .active { sync.requestState() } }
        }
    }
}

struct WatchRootView: View {
    @EnvironmentObject var sync: WatchSync
    @State private var confirmStop = false
    private var state: SessionSnapshot { sync.lastReceived?.snapshot ?? .empty }

    private var mascot: Image {
        if let data = sync.lastReceived?.portrait, let image = UIImage(data: data) { return Image(uiImage: image) }
        return Image("WatchMascot")
    }

    var body: some View {
        TabView {
            TimelineView(.periodic(from: .now, by: 1)) { timeline in
                VStack(spacing: 8) {
                    mascot.resizable().scaledToFit().frame(height: 56).accessibilityHidden(true)
                    Text(state.isRunning ? "이번 근무 예상 수익" : "오늘 예상 수익")
                        .font(.caption).foregroundStyle(.secondary)
                    Text((state.isRunning ? state.amount(at: timeline.date) : state.today(at: timeline.date)).won)
                        .font(.system(.title2, design: .rounded, weight: .bold))
                        .foregroundStyle(.yellow).minimumScaleFactor(0.6).lineLimit(1)
                    Text(state.isPaused ? "쉬는 중" : (state.isRunning ? "일하는 중" : "근무 대기"))
                        .font(.caption.bold())
                    if !sync.isReachable {
                        Text("마지막 동기화 기준 · 연결 대기").font(.caption2).foregroundStyle(.orange)
                    }
                }
            }
            ScrollView {
                VStack(spacing: 10) {
                    Text("삐약 컨트롤").font(.headline)
                    Text("시급 \((state.preferredWage ?? 10_000).won)")
                        .font(.caption).foregroundStyle(.secondary)
                    if state.isRunning {
                        Button(state.isPaused ? "계속 일하기" : "잠깐 쉬기") {
                            sync.sendCommand(state.isPaused ? "resume" : "pause")
                        }.tint(PB.C.brandYellow).foregroundStyle(PB.C.ink)
                        Button("근무 마치기", role: .destructive) { confirmStop = true }
                    } else {
                        Button("근무 시작") { sync.sendCommand("start") }
                            .tint(PB.C.brandYellow).foregroundStyle(PB.C.ink)
                    }
                    Button("상태 새로고침", systemImage: "arrow.clockwise") { sync.requestState() }
                        .buttonStyle(.bordered)
                    if sync.isSending { ProgressView("iPhone 확인 중") }
                    if !sync.isReachable { Text("근무 제어는 iPhone 연결이 필요해요.").font(.caption2) }
                }.buttonStyle(.borderedProminent).disabled(sync.isSending)
            }
            VStack(spacing: 8) {
                mascot.resizable().scaledToFit().frame(height: 112).accessibilityHidden(true)
                Text("너의 작은 친구, 삐약이").font(.headline)
                Text(sync.lastReceived?.portrait == nil ? "iPhone 앱을 열면 꾸민 모습이 도착해요." : "iPhone에서 꾸민 모습이에요.")
                    .font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    .lineLimit(3).fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 8)
            }
        }
        .tabViewStyle(.verticalPage)
        .confirmationDialog("근무를 마치고 기록할까요?", isPresented: $confirmStop) {
            Button("근무 마치기") { sync.sendCommand("stop") }
        } message: { Text("시급과 무관하게 휴식을 뺀 타이머 10분에 100P, 하루 최대 4,800P를 받아요.") }
        .alert("연결 확인", isPresented: Binding(get: { sync.errorMessage != nil }, set: { if !$0 { sync.errorMessage = nil } })) {
            Button("확인") { sync.errorMessage = nil }
        } message: { Text(sync.errorMessage ?? "") }
    }
}
