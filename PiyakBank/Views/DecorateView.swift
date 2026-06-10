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
    private var store: EconomyStore { EconomyStore(context: context) }
    
    private let roomSlots: [DecorSlot] = [.bg, .wallDeco, .bigFurniture, .floorProp, .rug]
    private let wearSlots: [DecorSlot] = [.bodyFront, .head, .eyes, .headband, .neck]
    
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
    }
    
    private var balanceBar: some View {
        HStack {
            Text("보유 포인트")
                .font(PB.F.body(13))
                .foregroundStyle(PB.C.textBrown.opacity(0.7))
            Spacer()
            Text(balance.won)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(PB.C.textBrown)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(PB.C.brandYellow.opacity(0.25))
    }
    
    private var preview: some View {
        CharacterComposite(showRoom: true, fillRoom: false)
            .frame(maxWidth: .infinity)
            .frame(height: 320)
            .background(PB.C.bg)
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
            store.equip(item.id)            // 보유 → 착용
        } else if item.isIAP {
            if let product = storeManager.products.first(where: {
                StoreManager.productMap[$0.id] == item.id
            }) {
                Task { try? await storeManager.purchase(product) }
            }
        } else {
            try? store.purchase(item.id)    // 포인트 구매
        }
    }
    
    private func slotLabel(_ s: DecorSlot) -> String {
        switch s {
        case .bg: "배경"; case .wallDeco: "벽장식"; case .bigFurniture: "가구"
        case .floorProp: "소품"; case .rug: "러그"; case .bodyFront: "옷"
        case .head: "모자"; case .eyes: "눈"; case .headband: "머리띠"; case .neck: "목"
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
                    .overlay(
                        Image(assetName(item.id)).resizable().scaledToFit().padding(8)
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
