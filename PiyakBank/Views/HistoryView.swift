import SwiftUI
import SwiftData

struct HistoryView: View {
    @Query(sort: \PointTransaction.date, order: .reverse) private var txs: [PointTransaction]
    @Environment(\.modelContext) private var context
    private var store: EconomyStore { EconomyStore(context: context) }

    var body: some View {
        List {
            Section {
                HStack {
                    Text("현재 잔액").font(PB.F.body(15)).foregroundStyle(PB.C.textBrown)
                    Spacer()
                    Text(store.balance.won).font(PB.F.amount(20)).foregroundStyle(PB.C.textBrown)
                }
            }
            Section("거래 내역") {
                if txs.isEmpty {
                    VStack(spacing: 12) {
                        Text("🐤").font(.system(size: 48))
                        Text("아직 기록이 없어요")
                            .font(PB.F.body(15))
                            .foregroundStyle(PB.C.textBrown.opacity(0.6))
                        Text("근무를 시작하면 여기에 쌓여요!")
                            .font(PB.F.body(13))
                            .foregroundStyle(PB.C.textBrown.opacity(0.4))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 32)
                    .listRowBackground(Color.clear)
                } else {
                    ForEach(txs, id: \.id) { tx in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(label(tx)).font(PB.F.body(15))
                                Text(tx.date, format: .dateTime.month().day().hour().minute())
                                    .font(PB.F.body(12)).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(signed(tx.amount))
                                .font(PB.F.amount(16))
                                .foregroundStyle(tx.amount >= 0 ? PB.C.textBrown : PB.C.coral)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(PB.C.bg.ignoresSafeArea())
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
