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
                .overlay(alignment: .bottom) {
                    LinearGradient(colors: [.clear, PB.C.bg],
                                   startPoint: .top, endPoint: .bottom)
                        .frame(height: 60)
                }
                
                
                VStack(spacing: 24) {
                    Spacer().frame(height: 390)   // 카드가 캐릭터에 살짝 겹치게
                    
                    // 금액 플로팅 카드
                    VStack(spacing: 10) {
                        Text("오늘 번 돈").font(PB.F.body(13))
                            .foregroundStyle(PB.C.textBrown.opacity(0.5))
                        Text(displayAmount.won)
                            .font(PB.F.amount(44))
                            .foregroundStyle(isAccruing ? PB.C.coral : PB.C.textBrown)
                            .contentTransition(.numericText())
                        // 상태 캡슐 배지
                        Text(statusText)
                            .font(PB.F.body(13)).bold()
                            .padding(.horizontal, 12).padding(.vertical, 5)
                            .background(statusBadgeColor.opacity(0.15), in: Capsule())
                            .foregroundStyle(statusBadgeColor)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 22)
                    .background(.white, in: RoundedRectangle(cornerRadius: PB.R.xl))
                    .shadow(color: PB.C.textBrown.opacity(0.08), radius: 16, y: 6)
                    
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
        .sensoryFeedback(.success, trigger: session.snapshot.isRunning)
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
    
    private var isAccruing: Bool {
        session.snapshot.isRunning && !session.snapshot.isPaused
    }
    private var statusBadgeColor: Color {
        let s = session.snapshot
        if !s.isRunning { return PB.C.textBrown.opacity(0.6) }
        if s.isPaused { return PB.C.brandYellow }
        return PB.C.coral
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
        VStack(spacing: 18) {
            Text("🐤").font(.system(size: 40))
            Text("시급을 입력하세요").font(PB.F.body(17)).bold()
                .foregroundStyle(PB.C.textBrown)
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
        .presentationDetents([.height(330)])
        .presentationCornerRadius(28)
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
        .buttonStyle(SquishyButtonStyle())
    }
}

struct SquishyButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.spring(duration: 0.2), value: configuration.isPressed)
    }
}
