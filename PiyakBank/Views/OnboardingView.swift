import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject private var session: SessionController
    @State private var wage = "10000"
    let onComplete: () -> Void
    private var valid: Bool { (1...EarningsCalculator.maximumWage).contains(Int(wage) ?? 0) }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    Image("AppMascot").resizable().scaledToFit().frame(height: 175)
                        .accessibilityHidden(true)
                    VStack(spacing: 10) {
                        Text("일하는 나에게,\n작은 친구 하나.")
                            .font(.system(.largeTitle, design: .rounded, weight: .heavy))
                        Text("내 시간을 기록하고\n삐약이의 작은 세상을 키워요.")
                            .font(.body).foregroundStyle(PB.C.secondary)
                    }.multilineTextAlignment(.center)
                    VStack(alignment: .leading, spacing: 18) {
                        feature("clock.fill", "시작, 휴식, 마침", "일한 시간에 입력한 시급을 곱해 예상 수익을 계산해요.")
                        feature("sparkles", "차곡차곡, 나만의 방", "근무를 마치면 꾸미기 포인트를 받아요. 첫 버전은 무료예요.")
                        feature("lock.fill", "내 기록은 내 기기에", "회원가입과 광고가 없어요. 근무와 대화 내용을 개발자 서버로 보내지 않아요.")
                    }.gameCard()
                    VStack(alignment: .leading, spacing: 10) {
                        Text("기본 시급을 알려주세요").font(.headline)
                        HStack {
                            TextField("시급", text: $wage).keyboardType(.numberPad)
                                .font(.system(.title2, design: .rounded, weight: .bold))
                                .accessibilityLabel("기본 시급, 원")
                            Text("원 / 시간").foregroundStyle(PB.C.secondary)
                        }.padding(16).background(PB.C.surface, in: RoundedRectangle(cornerRadius: 16))
                        Text("1~1,000,000원 · 나중에 바꿀 수 있어요")
                            .font(.caption).foregroundStyle(PB.C.secondary)
                    }
                    Text("예상 수익은 세금·수당을 반영하지 않아요. 포인트는 현금이나 금융 자산이 아니며, 현금 전환·송금·인출 기능은 없어요.")
                        .font(.caption).foregroundStyle(PB.C.secondary)
                    NavigationLink("개인정보 처리방침 확인") { PrivacyView() }.font(.subheadline)
                    Button("삐약이 만나러 가기") {
                        guard let value = Int(wage), valid else { return }
                        session.preferredWage = value
                        onComplete()
                    }.buttonStyle(GameButtonStyle()).disabled(!valid)
                }.padding(24).frame(maxWidth: 560).frame(maxWidth: .infinity)
            }.background(PB.C.bg.ignoresSafeArea()).foregroundStyle(PB.C.textBrown)
                .onAppear { wage = String(session.preferredWage) }
        }
    }
    private func feature(_ icon: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon).foregroundStyle(PB.C.coral).frame(width: 24).font(.title3)
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.subheadline.bold())
                Text(detail).font(.caption).foregroundStyle(PB.C.secondary)
            }
        }
    }
}
