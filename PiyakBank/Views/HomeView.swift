import SwiftUI
import SwiftData

struct HomeView: View {
    @EnvironmentObject private var session: SessionController
    @EnvironmentObject private var router: AppRouter
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Query private var transactions: [PointTransaction]
    @State private var showWage = false
    @State private var confirmStop = false
    @State private var reward: Int?
    @State private var interactionID = 0
    @State private var lastInteractionAt: TimeInterval = -.infinity
    @State private var activity = "반가워! 오늘도 함께해"
    @AppStorage("room_animations_enabled") private var roomAnimationsEnabled = true

    private var balance: Int { transactions.filter { $0.kind != .legacy }.reduce(0) { $0 + $1.amount } }
    private var earnedPoints: Int { transactions.filter { $0.kind == .accrual }.reduce(0) { $0 + $1.amount } }
    private var running: Bool { session.snapshot.isRunning }
    private var paused: Bool { session.snapshot.isPaused }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    header
                    if horizontalSizeClass == .regular {
                        HStack(alignment: .top, spacing: 22) {
                            VStack(spacing: 18) { room; growth }
                                .frame(maxWidth: .infinity)
                            VStack(spacing: 18) {
                                TimelineView(.periodic(from: .now, by: 1)) { earnings(at: $0.date) }
                                shopLink
                            }.frame(maxWidth: 340)
                        }
                    } else {
                        room
                        TimelineView(.periodic(from: .now, by: 1)) { earnings(at: $0.date) }
                        growth
                        shopLink
                    }
                }
                .padding(.horizontal, 20).padding(.vertical, 16)
                .frame(maxWidth: horizontalSizeClass == .regular ? 1080 : 640).frame(maxWidth: .infinity)
            }
            .background(PB.C.bg.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .bottom, spacing: 0) { controls }
            .sheet(isPresented: $showWage) {
                WageEntrySheet(initialWage: session.preferredWage) { wage in
                    if session.perform({ try session.start(wage: wage) }) {
                        session.preferredWage = wage
                        showWage = false
                    }
                }
            }
            .confirmationDialog("근무를 마치고 기록할까요?", isPresented: $confirmStop, titleVisibility: .visible) {
                Button("근무 마치기") {
                    session.perform { reward = try session.stop() }
                }
            } message: { Text("휴식을 뺀 타이머 근무 10분마다 100P, 하루 최대 4,800P를 받아요. 시급은 포인트에 영향을 주지 않아요.") }
            .alert("오늘도 수고했어요!", isPresented: Binding(get: { reward != nil }, set: { if !$0 { reward = nil } })) {
                Button("삐약이와 계속하기") { reward = nil }
            } message: {
                Text((reward ?? 0) > 0
                     ? "근무를 저장하고 \((reward ?? 0).points)를 적립했어요. 삐약이의 방에서 사용해 보세요."
                     : "근무를 저장했어요. 이번에 추가된 포인트는 없어요. 하루 최대 4,800P까지, 같은 날의 타이머 근무 시간을 합쳐 적립해요.")
            }
            .sensoryFeedback(.success, trigger: reward)
            .sensoryFeedback(.selection, trigger: interactionID)
        }
    }

    private var shopLink: some View {
Button { router.tab = .decorate } label: {
                        HStack(spacing: 14) {
                            Image(systemName: "gift.fill").font(.title2).foregroundStyle(PB.C.ink)
                                .frame(width: 48, height: 48).background(.white.opacity(0.6), in: RoundedRectangle(cornerRadius: 16))
                            VStack(alignment: .leading, spacing: 4) {
                                Text("작은 방, 커다란 취향").font(.headline)
                                Text("모은 포인트로 삐약이의 방을 꾸며요").font(.caption)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right").font(.subheadline.bold())
                        }.foregroundStyle(PB.C.ink).gameCard(PB.C.mint)
                    }.buttonStyle(.plain)
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 3) {
                Text(Date(), format: .dateTime.month().day().weekday().locale(Locale(identifier: "ko_KR")))
                    .font(.caption.weight(.medium)).foregroundStyle(PB.C.secondary)
                Text("삐약이의 하루").font(.system(.title2, design: .rounded, weight: .heavy))
                    .foregroundStyle(PB.C.textBrown)
            }
            Spacer(minLength: 8)
            PointBadge(amount: balance)
        }
    }

    private var room: some View {
        VStack(spacing: 0) {
            HStack {
                Label(activity,
                      systemImage: paused ? "moon.zzz.fill" : "sparkles")
                    .font(.system(.footnote, design: .rounded, weight: .semibold))
                    .foregroundStyle(PB.C.ink)
                Spacer()
                Text("Lv. \(max(1, earnedPoints / RewardPolicy.pointsPerLevel + 1))")
                    .font(.system(.caption, design: .rounded, weight: .heavy))
                    .padding(.horizontal, 9).padding(.vertical, 6)
                    .background(.white.opacity(0.8), in: Capsule()).foregroundStyle(PB.C.ink)
            }.padding(.horizontal, 20).padding(.top, 18)
            CharacterComposite(isWorking: running && !paused,
                               animateLife: roomAnimationsEnabled && !showWage && reward == nil && !confirmStop,
                               interactionID: interactionID, onInteract: playWithPiyak,
                               onActivity: { activity = $0 })
                .frame(height: verticalSizeClass == .compact ? 220 : (horizontalSizeClass == .regular ? 420 : 295))
                .overlay(alignment: .bottomTrailing) {
                    Button(action: playWithPiyak) {
                        Label("놀아주기", systemImage: "hand.tap.fill")
                            .font(.subheadline.bold()).foregroundStyle(PB.C.ink)
                            .padding(.horizontal, 14).padding(.vertical, 11)
                            .background(.white, in: Capsule())
                            .shadow(color: .black.opacity(0.06), radius: 8, y: 3)
                    }
                    .accessibilityLabel("삐약이와 놀아주기")
                    .accessibilityHint("삐약이가 인사하거나 방 안의 가구와 소품으로 놀아요")
                    .padding(16)
                }
                .overlay(alignment: .bottomLeading) {
                    Button {
                        roomAnimationsEnabled.toggle()
                        activity = roomAnimationsEnabled ? "삐약이가 다시 움직여요" : "움직임을 잠시 쉬고 있어요"
                    } label: {
                        Image(systemName: roomAnimationsEnabled ? "pause.fill" : "play.fill")
                            .font(.subheadline.bold()).foregroundStyle(PB.C.ink)
                            .frame(width: 44, height: 44).background(.white.opacity(0.9), in: Circle())
                    }
                    .accessibilityLabel(roomAnimationsEnabled ? "삐약이 움직임 멈추기" : "삐약이 움직임 재생")
                    .padding(16)
                }
            Text("삐약이를 톡 눌러서 함께 놀아요")
                .font(.caption).foregroundStyle(PB.C.secondary)
                .padding(.horizontal, 20).padding(.bottom, 14)
        }
        .background(LinearGradient(colors: [Color(hex: 0xE5DCF5), Color(hex: 0xF7E7CB)], startPoint: .topLeading, endPoint: .bottomTrailing))
        .clipShape(RoundedRectangle(cornerRadius: 32))
    }

    private func playWithPiyak() {
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastInteractionAt >= 0.8 else { return }
        lastInteractionAt = now
        interactionID &+= 1
    }

    private func earnings(at date: Date) -> some View {
        let seconds = EarningsCalculator.workingSeconds(session.snapshot.segments ?? [], until: date)
        let todayPoints = transactions.filter {
            $0.kind == .accrual && RewardPolicy.calendar.isDate($0.date, inSameDayAs: date)
        }.reduce(0) { $0 + $1.amount }
        return VStack(alignment: .leading, spacing: 13) {
            HStack {
                Label("오늘의 예상 수익", systemImage: "sun.max.fill").font(.subheadline.weight(.semibold))
                    .foregroundStyle(PB.C.secondary)
                Spacer()
                if running {
                    Label(paused ? "쉬는 중" : "근무 중", systemImage: paused ? "pause.circle.fill" : "record.circle")
                        .font(.caption.bold()).foregroundStyle(PB.C.coral)
                }
            }
            Text(session.snapshot.today(at: date).won)
                .font(.system(.largeTitle, design: .rounded, weight: .heavy))
                .monospacedDigit().foregroundStyle(PB.C.textBrown)
                .minimumScaleFactor(0.6).lineLimit(1)
                .accessibilityLabel("오늘의 예상 수익 \(session.snapshot.today(at: date).won)")
            if running {
                ViewThatFits(in: .horizontal) {
                    HStack { details(seconds: seconds); Spacer(); Text("이번 근무 \(session.snapshot.amount(at: date).won)") }
                    VStack(alignment: .leading, spacing: 5) { details(seconds: seconds); Text("이번 근무 \(session.snapshot.amount(at: date).won)") }
                }.font(.caption).foregroundStyle(PB.C.secondary)
                if let start = session.snapshot.startedAt, date.timeIntervalSince(start) > 12 * 3600 {
                    Label("근무를 마쳤나요? 한 타이머의 보상은 누적 유급 24시간까지만 계산돼요. 그 뒤에는 근무를 마치고 새로 시작해 주세요. 예상 수익은 계속 기록돼요.", systemImage: "clock.badge.exclamationmark")
                        .font(.caption).foregroundStyle(PB.C.coral)
                }
            }
            Text("세전 단순 추정치 · 실제 급여와 다를 수 있어요")
                .font(.caption2).foregroundStyle(PB.C.secondary)
            Divider()
            ViewThatFits(in: .horizontal) {
                HStack {
                    Text("오늘 받은 꾸미기 포인트")
                    Spacer()
                    Text("\(todayPoints.points) / \(RewardPolicy.pointsPerDay.points)").bold().monospacedDigit()
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("오늘 받은 꾸미기 포인트")
                    Text("\(todayPoints.points) / \(RewardPolicy.pointsPerDay.points)").bold().monospacedDigit()
                }
            }.font(.caption).foregroundStyle(PB.C.textBrown)
            Text("시급과 무관하게 타이머 10분에 100P · 근무를 마치면 적립돼요")
                .font(.caption2).foregroundStyle(PB.C.secondary)
            Text("하루 한도는 한국 시간 00시에 새로 시작해요")
                .font(.caption2).foregroundStyle(PB.C.secondary)
        }.gameCard()
    }
    private func details(seconds: TimeInterval) -> some View {
        Label("\(Int(seconds) / 3600)시간 \(Int(seconds) % 3600 / 60)분 · 휴식 제외", systemImage: "clock")
    }
    private var growth: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("삐약이의 성장 노트", systemImage: "leaf.fill").font(.subheadline.bold())
                Spacer()
                Text("\(max(0, earnedPoints % RewardPolicy.pointsPerLevel).points) / \(RewardPolicy.pointsPerLevel.points)")
                    .font(.caption).foregroundStyle(PB.C.secondary)
            }
            ProgressView(value: Double(max(0, earnedPoints % RewardPolicy.pointsPerLevel)), total: Double(RewardPolicy.pointsPerLevel)).tint(PB.C.coral)
            Text("타이머 보상 4,800P를 모을 때마다 한 레벨씩 자라요. 하루 한도 안에서 인정된 근무 8시간에 해당해요. 포인트를 써도 레벨은 유지돼요.")
                .font(.caption).foregroundStyle(PB.C.secondary)
        }.foregroundStyle(PB.C.textBrown).gameCard()
    }
    private var controls: some View {
        HStack(spacing: 12) {
            if running {
                Button { session.perform { if paused { try session.resume() } else { try session.pause() } } } label: {
                    Label(paused ? "계속 일하기" : "잠깐 쉬기", systemImage: paused ? "play.fill" : "pause.fill")
                }.buttonStyle(GameButtonStyle(color: PB.C.lilac))
                Button { confirmStop = true } label: { Label("근무 마치기", systemImage: "checkmark") }
                    .buttonStyle(GameButtonStyle())
            } else {
                Button { showWage = true } label: { Label("삐약이와 근무 시작", systemImage: "play.fill") }
                    .buttonStyle(GameButtonStyle())
            }
        }
        .padding(.horizontal, 20).padding(.top, 10).padding(.bottom, 14)
        .frame(maxWidth: 640).frame(maxWidth: .infinity).background(PB.C.bg.opacity(0.96))
    }
}

struct WageEntrySheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var text: String
    let onConfirm: (Int) -> Void
    init(initialWage: Int, onConfirm: @escaping (Int) -> Void) {
        _text = State(initialValue: String(initialWage)); self.onConfirm = onConfirm
    }
    private var valid: Bool { (1...EarningsCalculator.maximumWage).contains(Int(text) ?? 0) }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        TextField("시급", text: $text).keyboardType(.numberPad)
                            .font(.system(.title2, design: .rounded, weight: .bold))
                            .accessibilityLabel("시급, 원")
                        Text("원 / 시간").foregroundStyle(.secondary)
                    }
                } header: { Text("오늘의 시급") } footer: { Text("1~1,000,000원. 입력한 시급은 다음 근무에도 기억해요. 휴식은 무급으로 계산해요.") }
                Section {
                    Text("시급은 예상 수익에만 반영돼요. 꾸미기 포인트는 휴식을 뺀 타이머 10분에 100P, 하루 최대 4,800P예요. 현금으로 바꿀 수 없어요.")
                        .font(.footnote).foregroundStyle(.secondary)
                    Text("예상 수익에는 세금·수당·사업장별 정산 규칙이 반영되지 않아요.")
                        .font(.footnote).foregroundStyle(.secondary)
                    Button("근무 시작") { if let wage = Int(text), valid { onConfirm(wage) } }
                        .buttonStyle(GameButtonStyle()).disabled(!valid)
                }
            }
            .navigationTitle("출근 준비").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("취소") { dismiss() } } }
        }.presentationDetents([.medium, .large])
    }
}
