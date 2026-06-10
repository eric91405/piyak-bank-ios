import SwiftUI
import SwiftData

struct HistoryView: View {
    @Query(sort: \PointTransaction.date, order: .reverse) private var txs: [PointTransaction]
    @Query(sort: \WorkSession.startedAt, order: .reverse) private var sessions: [WorkSession]
    @Environment(\.modelContext) private var context
    private var store: EconomyStore { EconomyStore(context: context) }

    enum HistoryTab: String, CaseIterable {
        case sessions = "근무 기록"
        case transactions = "거래 내역"
    }
    @State private var tab: HistoryTab = .sessions

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                balanceCard
                tabPicker

                switch tab {
                case .sessions:
                    let done = sessions.filter { !$0.isActive }
                    if done.isEmpty {
                        emptyCard("아직 근무 기록이 없어요", sub: "근무를 시작하면 여기에 쌓여요!")
                    } else {
                        ForEach(done, id: \.id) { s in
                            SessionCard(session: s)
                        }
                    }
                case .transactions:
                    if txs.isEmpty {
                        emptyCard("아직 기록이 없어요", sub: "근무를 시작하면 여기에 쌓여요!")
                    } else {
                        txListCard
                    }
                }
            }
            .padding(16)
        }
        .background(PB.C.bg.ignoresSafeArea())
        .navigationTitle("기록")
        .navigationBarTitleDisplayMode(.inline)
    }

    // 탭 토글 (브랜드 캡슐)
    private var tabPicker: some View {
        HStack(spacing: 8) {
            ForEach(HistoryTab.allCases, id: \.self) { t in
                Button {
                    withAnimation(.spring(duration: 0.3)) { tab = t }
                } label: {
                    Text(t.rawValue)
                        .font(PB.F.body(14)).bold()
                        .padding(.horizontal, 18).padding(.vertical, 9)
                        .background(tab == t ? PB.C.brandYellow : .white, in: Capsule())
                        .shadow(color: PB.C.textBrown.opacity(tab == t ? 0.12 : 0.04),
                                radius: 6, y: 2)
                        .foregroundStyle(PB.C.textBrown)
                }
            }
            Spacer()
        }
    }

    private var balanceCard: some View {
        VStack(spacing: 6) {
            Text("현재 잔액").font(PB.F.body(13))
                .foregroundStyle(PB.C.textBrown.opacity(0.5))
            Text(store.balance.won)
                .font(PB.F.amount(32))
                .foregroundStyle(PB.C.textBrown)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .background(.white, in: RoundedRectangle(cornerRadius: PB.R.xl))
        .shadow(color: PB.C.textBrown.opacity(0.08), radius: 16, y: 6)
    }

    private var txListCard: some View {
        VStack(spacing: 0) {
            ForEach(Array(txs.enumerated()), id: \.element.id) { i, tx in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(label(tx)).font(PB.F.body(14))
                            .foregroundStyle(PB.C.textBrown)
                        Text(tx.date, format: .dateTime.month().day().hour().minute()
                            .locale(Locale(identifier: "ko_KR")))
                            .font(PB.F.body(11)).foregroundStyle(PB.C.textBrown.opacity(0.4))
                    }
                    Spacer()
                    Text(signed(tx.amount))
                        .font(PB.F.amount(15))
                        .foregroundStyle(tx.amount >= 0 ? PB.C.textBrown : PB.C.coral)
                }
                .padding(.vertical, 10)
                if i < txs.count - 1 {
                    Divider().overlay(PB.C.textBrown.opacity(0.06))
                }
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 6)
        .background(.white, in: RoundedRectangle(cornerRadius: PB.R.lg))
        .shadow(color: PB.C.textBrown.opacity(0.05), radius: 10, y: 4)
    }

    private func emptyCard(_ message: String, sub: String) -> some View {
        VStack(spacing: 10) {
            Text("🐤").font(.system(size: 44))
            Text(message).font(PB.F.body(14))
                .foregroundStyle(PB.C.textBrown.opacity(0.6))
            Text(sub).font(PB.F.body(12))
                .foregroundStyle(PB.C.textBrown.opacity(0.4))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .background(.white.opacity(0.6), in: RoundedRectangle(cornerRadius: PB.R.lg))
    }

    private func label(_ tx: PointTransaction) -> String {
        switch tx.kind {
        case .accrual: "근무 적립"
        case .purchase: "아이템 구매"
        case .refund: "환불 (50%)"
        case .adjust: "보정"
        }
    }
    private func signed(_ v: Int) -> String {
        (v >= 0 ? "+" : "") + v.won
    }
}

// MARK: 세션 카드

struct SessionCard: View {
    let session: WorkSession

    var body: some View {
        HStack(spacing: 14) {
            // 동전 아이콘 칩
            Text("🪙")
                .font(.system(size: 22))
                .frame(width: 44, height: 44)
                .background(PB.C.brandYellow.opacity(0.2), in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(session.startedAt, format: .dateTime.month().day()
                    .locale(Locale(identifier: "ko_KR")))
                    .font(PB.F.body(14)).bold()
                    .foregroundStyle(PB.C.textBrown)
                Text("\(timeRange) · \(durationText)")
                    .font(PB.F.body(12))
                    .foregroundStyle(PB.C.textBrown.opacity(0.45))
            }
            Spacer()
            Text("+" + session.accrued(until: session.endedAt ?? .now).won)
                .font(PB.F.amount(18))
                .foregroundStyle(PB.C.coral)
        }
        .padding(14)
        .background(.white, in: RoundedRectangle(cornerRadius: PB.R.lg))
        .shadow(color: PB.C.textBrown.opacity(0.05), radius: 10, y: 4)
    }

    private var timeRange: String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        let start = f.string(from: session.startedAt)
        let end = session.endedAt.map { f.string(from: $0) } ?? "진행 중"
        return "\(start)~\(end)"
    }

    private var durationText: String {
        guard let end = session.endedAt else { return "" }
        let mins = Int(end.timeIntervalSince(session.startedAt) / 60)
        if mins < 60 { return "\(mins)분" }
        return "\(mins / 60)시간 \(mins % 60)분"
    }
}
