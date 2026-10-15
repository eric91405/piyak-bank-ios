import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject private var session: SessionController
    @State private var wage = "10000"
    @State private var showingSetup = false
    @State private var loadedWage = false
    @FocusState private var editingWage: Bool
    let onComplete: () -> Void
    private var valid: Bool { (1...EarningsCalculator.maximumWage).contains(Int(wage) ?? 0) }
    var body: some View {
        Group {
            if showingSetup {
                setup
            } else {
                UsageGuideView(mode: .firstLaunch) { showingSetup = true }
            }
        }
        .onAppear {
            guard !loadedWage else { return }
            wage = String(session.preferredWage)
            loadedWage = true
        }
    }

    private var setup: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    Image("AppMascot").resizable().scaledToFit().frame(height: 140)
                        .accessibilityHidden(true)
                    VStack(spacing: 10) {
                        Text("이제, 함께 시작해요")
                            .font(.system(.largeTitle, design: .rounded, weight: .heavy))
                        Text("예상 수익을 계산할\n기본 시급을 알려주세요.")
                            .font(.body).foregroundStyle(PB.C.secondary)
                    }.multilineTextAlignment(.center)
                    VStack(alignment: .leading, spacing: 10) {
                        Text("기본 시급").font(.headline)
                        HStack {
                            TextField("시급", text: $wage).keyboardType(.numberPad)
                                .focused($editingWage)
                                .font(.system(.title2, design: .rounded, weight: .bold))
                                .accessibilityLabel("기본 시급, 원")
                            Text("원 / 시간").foregroundStyle(PB.C.secondary)
                        }.padding(16).background(PB.C.surface, in: RoundedRectangle(cornerRadius: 16))
                        Text("1~1,000,000원 · 나중에 설정에서 바꿀 수 있어요.\n시급은 예상 수익에만 반영되며 꾸미기 포인트에는 영향을 주지 않아요.")
                            .font(.caption).foregroundStyle(PB.C.secondary)
                        if !valid {
                            Text("1~1,000,000원 사이의 숫자를 입력해 주세요.")
                                .font(.caption).foregroundStyle(PB.C.accent)
                        }
                    }
                    Label("회원가입과 광고 없이 사용해요.\n근무 기록을 개발자 서버로 보내지 않아요.", systemImage: "lock.shield")
                        .font(.footnote).foregroundStyle(PB.C.secondary)
                    Text("예상 수익은 세금·수당을 반영하지 않아요. 포인트는 현금이나 금융 자산이 아니며, 현금 전환·송금·인출 기능은 없어요.")
                        .font(.caption).foregroundStyle(PB.C.secondary)
                    NavigationLink("개인정보 처리방침 확인") { PrivacyView() }.font(.subheadline)
                }.padding(24).frame(maxWidth: 560).frame(maxWidth: .infinity)
            }.background(PB.C.bg.ignoresSafeArea()).foregroundStyle(PB.C.textBrown)
                .navigationTitle("마지막 준비").navigationBarTitleDisplayMode(.inline)
                .scrollDismissesKeyboard(.interactively)
                .safeAreaInset(edge: .bottom) {
                    Button("삐약이 만나러 가기") {
                        guard let value = Int(wage), valid else { return }
                        editingWage = false
                        session.preferredWage = value
                        onComplete()
                    }.buttonStyle(GameButtonStyle()).disabled(!valid)
                        .padding(.horizontal, 24).padding(.top, 12).padding(.bottom, 16)
                        .frame(maxWidth: 560).frame(maxWidth: .infinity).background(PB.C.bg)
                }
                .toolbar {
                    ToolbarItemGroup(placement: .keyboard) {
                        Spacer()
                        Button("입력 완료") { editingWage = false }
                    }
                }
        }
    }
}
