import SwiftUI
import SwiftData
import StoreKit

struct DecorateView: View {
    @Environment(\.modelContext) private var context
    @Query private var catalog: [CatalogItem]
    @Query private var transactions: [PointTransaction]
    @Query private var owned: [OwnedItem]
    @EnvironmentObject private var storeManager: StoreManager
    
    @State private var selectedSlot: DecorSlot = .bg
    @State private var purchaseError: String? = nil
    @State private var confirmItem: CatalogItem? = nil
    @State private var equipBounce = false
    private var store: EconomyStore { EconomyStore(context: context) }
    
    private let roomSlots: [DecorSlot] = [.bg, .wallDeco, .bigFurniture, .floorProp, .rug]
    private let wearSlots: [DecorSlot] = [.bodyFront, .headTop, .eyes, .neck]
    
    private var balance: Int {
        transactions.reduce(0) { $0 + $1.amount }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            balanceBar
            preview
            slotPicker
            itemGrid
        }
        .background(PB.C.bg.ignoresSafeArea())
        .alert("구매할까요?", isPresented: .init(
            get: { confirmItem != nil },
            set: { if !$0 { confirmItem = nil } }
        )) {
            Button("구매") {
                if let item = confirmItem {
                    do {
                        try store.purchase(item.id)
                    } catch EconomyStore.PurchaseError.insufficient {
                        purchaseError = "포인트가 부족해요 🥲\n근무해서 더 모아볼까요?"
                    } catch {
                        purchaseError = "구매에 실패했어요"
                    }
                }
                confirmItem = nil
            }
            Button("취소", role: .cancel) { confirmItem = nil }
        } message: {
            Text(confirmItem.map { "\($0.displayName)을(를) \($0.price.won)에 구매합니다" } ?? "")
        }
        .alert("구매 실패", isPresented: .init(
            get: { purchaseError != nil },
            set: { if !$0 { purchaseError = nil } }
        )) {
            Button("확인", role: .cancel) {}
        } message: {
            Text(purchaseError ?? "")
        }
        .sensoryFeedback(.impact, trigger: owned.compactMap(\.equippedSlotRaw))
    }
    
    private var balanceBar: some View {
        HStack(spacing: 6) {
            Text("💰").font(.system(size: 14))
            Text("보유 포인트")
                .font(PB.F.body(12))
                .foregroundStyle(PB.C.textBrown.opacity(0.6))
            Text(balance.won)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(PB.C.textBrown)
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(.white, in: Capsule())
        .shadow(color: PB.C.textBrown.opacity(0.08), radius: 8, y: 3)
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }
    
    private var preview: some View {
        CharacterComposite(showRoom: true, fillRoom: false)
            .frame(maxWidth: .infinity)
            .frame(height: 320)
            .background(PB.C.bg)
            .scaleEffect(equipBounce ? 1.06 : 1.0)
            .animation(.spring(duration: 0.35, bounce: 0.5), value: equipBounce)
            .onChange(of: owned.compactMap(\.equippedSlotRaw)) { _, _ in
                equipBounce = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                    equipBounce = false
                }
            }
    }
    
    private var slotPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(roomSlots + wearSlots, id: \.self) { slot in
                    Button(slotLabel(slot)) { selectedSlot = slot }
                        .font(PB.F.body(13))
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(selectedSlot == slot ? PB.C.brandYellow : .white,
                                    in: Capsule())
                        .shadow(color: PB.C.textBrown.opacity(selectedSlot == slot ? 0.12 : 0.04),
                                radius: 6, y: 2)
                        .foregroundStyle(PB.C.textBrown)
                }
            }.padding(.horizontal, 16)
        }.padding(.vertical, 12)
    }
    
    private var itemGrid: some View {
        ScrollView {
            LazyVGrid(columns: [.init(.adaptive(minimum: 100), spacing: 12)], spacing: 12) {
                ForEach(catalog.filter { $0.slot == selectedSlot }, id: \.id) { item in
                    ItemCell(item: item,
                             isOwned: owned.contains { $0.catalogId == item.id },
                             isEquipped: store.equippedId(for: item.slot) == item.id,
                             onTap: { handleTap(item) })
                }
            }.padding(16)
        }
    }
    
    private func handleTap(_ item: CatalogItem) {
        if owned.contains(where: { $0.catalogId == item.id }) {
            if store.equippedId(for: item.slot) == item.id {
                if item.slot != .bg {                    // 배경은 해제 불가
                    store.unequip(slot: item.slot)
                }
            } else {
                store.equip(item.id)             // 보유 → 착용
            }
        } else if item.isIAP {
            if let product = storeManager.products.first(where: {
                StoreManager.productMap[$0.id] == item.id
            }) {
                Task { try? await storeManager.purchase(product) }
            }
        } else {
            confirmItem = item
        }
    }
    
    private func slotLabel(_ s: DecorSlot) -> String {
        switch s {
        case .bg: "배경"; case .wallDeco: "벽장식"; case .bigFurniture: "가구"
        case .floorProp: "소품"; case .rug: "러그"; case .bodyFront: "옷"
        case .headTop: "모자"; case .eyes: "눈"; case .headband: "머리띠"; case .neck: "목"
        }
    }
}

struct ItemCell: View {
    let item: CatalogItem; let isOwned: Bool; let isEquipped: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 6) {
                RoundedRectangle(cornerRadius: PB.R.md)
                    .fill(.white)
                    .frame(height: 80)
                    .shadow(color: PB.C.textBrown.opacity(0.06), radius: 8, y: 3)
                    .overlay(
                        RoundedRectangle(cornerRadius: PB.R.md)
                            .strokeBorder(isEquipped ? PB.C.coral : .clear, lineWidth: 2)
                    )
                    .overlay(
                        Image(assetName(item.id))
                            .resizable()
                            .scaledToFill()
                            .frame(width: 64, height: 64, alignment: .bottom)
                            .clipped()
                            .padding(8)
                    )
                    .overlay(alignment: .topTrailing) {
                        if isEquipped { Text("착용중").font(.caption2).padding(4)
                            .background(PB.C.coral, in: Capsule()).foregroundStyle(.white).padding(4) }
                    }
                Text(item.displayName).font(PB.F.body(12)).foregroundStyle(PB.C.textBrown)
                Text(badge).font(PB.F.body(11)).foregroundStyle(PB.C.textBrown.opacity(0.6))
            }
        }
    }
    private var badge: String {
        if isOwned { return "보유" }
        if item.isIAP { return "결제" }
        return item.price.won
    }
}
