import SwiftUI
import SwiftData

struct DecorateView: View {
    @EnvironmentObject private var session: SessionController
    @Query(sort: \CatalogItem.price) private var catalog: [CatalogItem]
    @Query private var transactions: [PointTransaction]
    @Query private var owned: [OwnedItem]
    @State private var slot: DecorSlot = .bodyFront
    @State private var onlyOwned = false
    @State private var selected: CatalogItem?
    private var balance: Int { transactions.reduce(0) { $0 + $1.amount } }
    private var equipped: [String: String] {
        var map: [String: String] = [:]
        for item in owned { if let slot = item.equippedSlotRaw { map[slot] = item.catalogId } }
        return map
    }
    private var items: [CatalogItem] {
        catalog.filter { $0.slot == slot && (!onlyOwned || owns($0.id)) }
    }
    private func owns(_ id: String) -> Bool { owned.contains { $0.catalogId == id } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("취향을 하나씩 모아요").font(.subheadline).foregroundStyle(PB.C.secondary)
                            Text("삐약이의 작은 방").font(.system(.title2, design: .rounded, weight: .heavy))
                        }
                        Spacer(minLength: 8)
                        PointBadge(amount: balance)
                    }
                    CharacterComposite().frame(height: 260)
                        .background(LinearGradient(colors: [PB.C.lilac, Color(hex: 0xF9E8C8)], startPoint: .top, endPoint: .bottom))
                        .clipShape(RoundedRectangle(cornerRadius: 30))
                    HStack {
                        Label("꾸미기 상점", systemImage: "bag.fill").font(.headline)
                        Spacer()
                        Toggle("보유만", isOn: $onlyOwned).font(.subheadline).fixedSize()
                    }
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach([DecorSlot.bodyFront, .headTop, .eyes, .neck, .bg, .wallDeco, .bigFurniture, .floorProp, .rug], id: \.self) { category in
                                Button { slot = category } label: {
                                    Label(category.title, systemImage: category.symbol)
                                        .font(.subheadline.bold()).padding(.horizontal, 14).padding(.vertical, 12)
                                        .foregroundStyle(slot == category ? PB.C.ink : PB.C.textBrown)
                                        .background(slot == category ? PB.C.brandYellow : PB.C.surface, in: Capsule())
                                }.buttonStyle(.plain).accessibilityAddTraits(slot == category ? .isSelected : [])
                            }
                        }
                    }
                    if items.isEmpty {
                        ContentUnavailableView("아직 비어 있어요", systemImage: "shippingbox",
                                               description: Text("보유만 보기를 끄고 마음에 드는 아이템을 찾아보세요."))
                    } else {
                        LazyVGrid(columns: [.init(.adaptive(minimum: 145), spacing: 14)], spacing: 14) {
                            ForEach(items) { item in
                                Button { selected = item } label: {
                                    VStack(alignment: .leading, spacing: 8) {
                                        Image("thumb_" + assetName(item.id)).resizable().scaledToFit()
                                            .frame(maxWidth: .infinity).frame(height: 122)
                                            .background(PB.C.bg.opacity(0.65), in: RoundedRectangle(cornerRadius: 18))
                                            .overlay(alignment: .topTrailing) {
                                                if equipped[item.slotRaw] == item.id {
                                                    Image(systemName: "checkmark.circle.fill").foregroundStyle(PB.C.coral)
                                                        .font(.title3).padding(8)
                                                }
                                            }
                                        Text(item.displayName).font(.subheadline.bold())
                                        Text(owns(item.id) ? (equipped[item.slotRaw] == item.id ? "함께하는 중" : "보관함에 있어요") : item.price.points)
                                            .font(.caption.weight(.medium)).foregroundStyle(PB.C.secondary)
                                    }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                                        .background(PB.C.surface, in: RoundedRectangle(cornerRadius: 24))
                                }.buttonStyle(.plain)
                                    .accessibilityLabel("\(item.displayName), \(owns(item.id) ? "보유" : item.price.points). 미리 보기")
                            }
                        }
                    }
                    Text("포인트는 앱 안에서만 사용할 수 있어요. 실제 결제는 없어요.")
                        .font(.caption).foregroundStyle(PB.C.secondary).padding(.bottom, 10)
                }.padding(20).frame(maxWidth: 720).frame(maxWidth: .infinity)
            }
            .background(PB.C.bg.ignoresSafeArea()).foregroundStyle(PB.C.textBrown)
            .navigationTitle("꾸미기").navigationBarTitleDisplayMode(.inline)
            .sheet(item: $selected) { item in
                ItemDetailSheet(item: item, equipped: equipped, balance: balance, isOwned: owns(item.id))
                    .environmentObject(session)
            }
        }
    }
}

private struct ItemDetailSheet: View {
    @EnvironmentObject private var session: SessionController
    @Environment(\.dismiss) private var dismiss
    let item: CatalogItem
    let equipped: [String: String]
    let balance: Int
    let isOwned: Bool
    @State private var error: String?
    @State private var confirmPurchase = false
    private var isEquipped: Bool { equipped[item.slotRaw] == item.id }
    private var preview: [String: String] {
        var map = equipped; map[item.slotRaw] = item.id; return map
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    CharacterComposite(preview: preview).frame(height: 280)
                        .background(PB.C.lilac, in: RoundedRectangle(cornerRadius: 28))
                    VStack(spacing: 8) {
                        Text(item.displayName).font(.title2.bold())
                        Text("\(item.slot.title) · 미리 보는 중").font(.subheadline).foregroundStyle(PB.C.secondary)
                    }
                    if isOwned {
                        Button(isEquipped ? "보관함에 넣기" : "함께하기") {
                            action {
                                if isEquipped { try session.economy.unequip(slot: item.slot) }
                                else { try session.economy.equip(item.id) }
                            }
                        }.buttonStyle(GameButtonStyle()).disabled(isEquipped && item.slot == .bg)
                    } else {
                        Text(item.price.points).font(.system(.title, design: .rounded, weight: .bold))
                        Text(balance >= item.price ? "구매 후 남는 포인트: \((balance - item.price).points)" : "현재 보유 포인트: \(balance.points)")
                            .font(.subheadline).foregroundStyle(PB.C.secondary)
                        Button(balance >= item.price ? "포인트로 데려오기" : "\((item.price - balance).points) 더 필요해요") {
                            confirmPurchase = true
                        }.buttonStyle(GameButtonStyle()).disabled(balance < item.price)
                        Text("근무를 마치면 포인트를 받을 수 있어요. 현금 결제는 없어요.")
                            .font(.caption).foregroundStyle(PB.C.secondary)
                    }
                }.padding(20).frame(maxWidth: 600).frame(maxWidth: .infinity)
            }.background(PB.C.bg).foregroundStyle(PB.C.textBrown)
                .navigationTitle("마음에 드나요?").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("닫기") { dismiss() } } }
                .confirmationDialog("\(item.price.points)로 데려올까요?", isPresented: $confirmPurchase, titleVisibility: .visible) {
                    Button("구매하고 꾸미기") { action { try session.economy.purchase(item.id, equip: true) } }
                }
                .alert("변경하지 못했어요", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                    Button("확인") { error = nil }
                } message: { Text(error ?? "") }
        }
    }
    private func action(_ operation: () throws -> Void) {
        do { try operation(); dismiss() } catch { self.error = error.localizedDescription }
    }
}
