import SwiftUI
import Combine
import SwiftData

struct HomeView: View {
    @EnvironmentObject var session: SessionController
    @Environment(\.modelContext) private var context
    @State private var showWageSheet = false
    @State private var now = Date()
    @State private var showChat = false
    @State private var bubbleText = ""
    @State private var bubbleTick = 0
    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var workedHours: Double {
        let s = session.snapshot
        guard s.isRunning, s.wage > 0 else { return 0 }
        return Double(s.accrued) / Double(s.wage)
    }

    static func cheers(for s: SessionSnapshot, hours: Double) -> [String] {
        if !s.isRunning {
            return ["오늘도 화이팅이야 삐약!", "쉬는 것도 중요해~", "나 보러 와줘서 고마워!"]
        }
        if s.isPaused {
            return ["꿀휴식 중~ 🍯", "물 한 잔 마시고 가자!"]
        }
        if hours >= 4 {
            return ["너무 무리하지는 마... 삐약", "조금만 더! 거의 다 왔어!", "오늘 진짜 고생 많았어 🥲"]
        }
        if hours >= 2 {
            return ["벌써 \(Int(hours))시간! 대단해!", "조금 힘들지? 같이 버티자!", "간식 하나 먹고 해~"]
        }
        return ["돈 버는 중! 멋져 삐약!", "차곡차곡 쌓이고 있어!", "이 돈으로 뭐 살까~?"]
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                PB.C.bg.ignoresSafeArea()


                CharacterComposite(showRoom: true, fillRoom: true,
                                   isWorking: session.snapshot.isRunning && !session.snapshot.isPaused,
                                   workedHours: workedHours)
                .onTapGesture { showChat = true }
                .sheet(isPresented: $showChat) {
                    PiyakChatView(engine: PiyakChatEngine(
                        container: context.container,
                        snapshot: .capture(context: context)
                    ))
                }
                .frame(maxWidth: .infinity)
                .frame(height: 500)
                .clipped()
                .ignoresSafeArea(edges: .top)
                .overlay(alignment: .bottom) {
                    LinearGradient(colors: [.clear, PB.C.bg],
                                   startPoint: .top, endPoint: .bottom)
                    .frame(height: 60)
                }
                .overlay(alignment: .top) {
                    if !bubbleText.isEmpty {
                        Text(bubbleText)
                            .font(PB.F.body(13)).bold()
                            .foregroundStyle(PB.C.textBrown)
                            .padding(.horizontal, 14)
                            .padding(.top, 9)
                            .padding(.bottom, 19)   // 9 + 꼬리 높이 10
                            .background {
                                SpeechBubbleShape()
                                    .fill(.white)
                                    .shadow(color: PB.C.textBrown.opacity(0.1), radius: 8, y: 3)
                            }
                            .padding(.top, 130)
                            .transition(.scale(scale: 0.8).combined(with: .opacity))
                    }
                }

                VStack(spacing: 24) {
                    Spacer().frame(height: 434)

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
                        .padding(.bottom, 40)
                }
                .padding(24)
            }
            .overlay(alignment: .topTrailing) {
                NavigationLink {
                    HistoryView()
                } label: {
                    Image(systemName: "list.bullet.rectangle")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(PB.C.textBrown)
                        .padding(11)
                        .background(.white.opacity(0.95), in: Circle())
                        .shadow(color: PB.C.textBrown.opacity(0.1), radius: 6, y: 2)
                }
                .padding(.trailing, 20)
                .padding(.top, 50)
            }
        }
        .onReceive(tick) { date in
            now = date
            session.refreshSnapshot()

            bubbleTick += 1
            if bubbleTick % 15 == 1 {
                withAnimation(.spring(duration: 0.4)) {
                    bubbleText = Self.cheers(for: session.snapshot, hours: workedHours).randomElement() ?? ""
                }
            }
            if bubbleTick % 15 == 8 {
                withAnimation(.easeOut(duration: 0.3)) { bubbleText = "" }
            }
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
            .disabled((Int(text) ?? 0) <= 0)
            .opacity((Int(text) ?? 0) <= 0 ? 0.4 : 1.0)
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

struct SpeechBubbleShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let tailW: CGFloat = 18, tailH: CGFloat = 10
        let body = CGRect(x: 0, y: 0, width: rect.width, height: rect.height - tailH)
        p.addRoundedRect(in: body, cornerSize: .init(width: 16, height: 16))
        // 아래 가운데 꼬리 (캐릭터 쪽으로)
        p.move(to: .init(x: rect.midX - tailW / 2, y: body.maxY - 1))
        p.addQuadCurve(to: .init(x: rect.midX, y: rect.maxY),
                       control: .init(x: rect.midX - 4, y: body.maxY + tailH * 0.6))
        p.addQuadCurve(to: .init(x: rect.midX + tailW / 2, y: body.maxY - 1),
                       control: .init(x: rect.midX + 4, y: body.maxY + tailH * 0.6))
        p.closeSubpath()
        return p
    }
}
