import SwiftUI
import Combine

struct HomeView: View {
    @EnvironmentObject var session: SessionController
    @Environment(\.modelContext) private var context
    @State private var showWageSheet = false
    @State private var now = Date()
    
    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    
    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                PB.C.bg.ignoresSafeArea()
                
                CharacterComposite(showRoom: true, fillRoom: true,
                                   isWorking: session.snapshot.isRunning && !session.snapshot.isPaused)
                .frame(maxWidth: .infinity)
                .frame(height: 440)
                .clipped()
                
                
                VStack(spacing: 24) {
                    Spacer().frame(height: 420)   // 캐릭터 영역만큼 띄우기
                    
                    VStack(spacing: 4) {
                        Text("오늘 번 돈").font(PB.F.body(13))
                            .foregroundStyle(PB.C.textBrown.opacity(0.5))
                        Text(displayAmount.won)
                            .font(PB.F.amount(44))
                            .foregroundStyle(PB.C.textBrown)
                            .contentTransition(.numericText())
                    }
                    
                    Text(statusText)
                        .font(PB.F.body(15))
                        .foregroundStyle(PB.C.textBrown.opacity(0.6))
                    
                    Spacer()
                    controls
                }
                .padding(24)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        HistoryView()
                    } label: {
                        Image(systemName: "list.bullet.rectangle")
                            .foregroundStyle(PB.C.textBrown)
                    }
                }
            }
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
    
    // 오늘 누적(원장) + 현재 세션 진행분
    private var displayAmount: Int {
        let today = EconomyStore(context: context).dailyAccrued(on: now)
        return today + session.snapshot.accrued
    }
    
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

