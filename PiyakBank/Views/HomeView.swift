import SwiftUI
import Combine

struct HomeView: View {
    @EnvironmentObject var session: SessionController
    @State private var showWageSheet = false
    @State private var now = Date()

    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            PB.C.bg.ignoresSafeArea()
            VStack(spacing: 24) {
                Spacer()
                PiyakCharacterView()          // 방 배치 + 캐릭터 합성 (에셋 연결 예정)
                    .frame(width: 220, height: 220)

                Text(displayAmount.won)
                    .font(PB.F.amount(44))
                    .foregroundStyle(PB.C.textBrown)
                    .contentTransition(.numericText())

                Text(statusText)
                    .font(PB.F.body(15))
                    .foregroundStyle(PB.C.textBrown.opacity(0.6))

                Spacer()
                controls
            }
            .padding(24)
        }
        .onReceive(tick) { date in
            now = date
            session.refreshSnapshot()
        }
        .sheet(isPresented: $showWageSheet) {
            WageEntrySheet { wage in
                session.start(wage: wage)
                showWageSheet = false
            }
        }
    }

    private var displayAmount: Int { session.snapshot.accrued }

    private var statusText: String {
        let s = session.snapshot
        if !s.isRunning { return "오늘도 삐약삐약 💰" }
        if s.isPaused { return "잠시 멈춤" }
        return "시급 \(s.wage.won) · 적립 중"
    }

    @ViewBuilder private var controls: some View {
        let s = session.snapshot
        if !s.isRunning {
            BigButton(title: "근무 시작", color: PB.C.coral) { showWageSheet = true }
        } else {
            HStack(spacing: 12) {
                BigButton(title: s.isPaused ? "재개" : "일시정지",
                          color: PB.C.brandYellow) {
                    s.isPaused ? session.resume() : session.pause()
                }
                BigButton(title: "정지", color: PB.C.coral) { session.stop() }
            }
        }
    }
}

// MARK: 시급 입력 시트 (세션 시작 시점에만)

struct WageEntrySheet: View {
    @State private var text = "10000"
    let onConfirm: (Int) -> Void

    var body: some View {
        VStack(spacing: 20) {
            Text("시급을 입력하세요").font(PB.F.body(17)).bold()
            TextField("시급", text: $text)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.center)
                .font(PB.F.amount(28))
                .padding()
                .background(PB.C.bg, in: RoundedRectangle(cornerRadius: PB.R.md))
            BigButton(title: "시작", color: PB.C.coral) {
                onConfirm(Int(text) ?? 0)
            }
        }
        .padding(28)
        .presentationDetents([.height(280)])
    }
}

// MARK: 재사용 컴포넌트

struct BigButton: View {
    let title: String; let color: Color; let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title).font(PB.F.body(17)).bold()
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity).padding(.vertical, 16)
                .background(color, in: RoundedRectangle(cornerRadius: PB.R.lg))
        }
    }
}

/// 방 슬롯 + 캐릭터 합성 (asset catalog 연결 후 Image(equippedId)로 교체)
struct PiyakCharacterView: View {
    var body: some View {
        ZStack {
            Circle().fill(PB.C.brandYellow)
                .overlay(Circle().stroke(PB.C.outline, lineWidth: 4))
            Text("🐤").font(.system(size: 90))
        }
    }
}
