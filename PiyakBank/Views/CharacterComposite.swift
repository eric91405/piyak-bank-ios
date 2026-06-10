import SwiftUI
import SwiftData

/// 방 5슬롯(z-order) + 캐릭터 + 액세서리 오버레이 합성.
/// - 방: bg → wallDeco → bigFurniture → floorProp → rug (뒤→앞)
/// - 캐릭터: bodyFront(통합 실루엣 Method B)가 베이스 몸체.
///   없으면 piyak_base. head/eyes/headband/neck만 오버레이.
struct CharacterComposite: View {
    var showRoom: Bool = true
    var fillRoom: Bool = false
    @Query private var owned: [OwnedItem]

    /// 정규화 앵커 좌표 (0~1, 캐릭터 프레임 기준). 실제 에셋 보고 미세조정.
    private static let anchor: [DecorSlot: CGPoint] = [
        .head:     CGPoint(x: 0.50, y: 0.12),
        .headband: CGPoint(x: 0.50, y: 0.26),
        .eyes:     CGPoint(x: 0.50, y: 0.44),
        .neck:     CGPoint(x: 0.50, y: 0.70),
    ]
    private static let overlaySlots: [DecorSlot] = [.neck, .headband, .head, .eyes]
    private static let roomSlots: [DecorSlot] = [.bg, .wallDeco, .bigFurniture, .floorProp, .rug]

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {  
                if showRoom {
                    ForEach(Self.roomSlots, id: \.self) { slot in
                        if let id = equipped[slot] {
                            Image(assetName(id))
                                .resizable()
                                .aspectRatio(contentMode: fillRoom ? .fill : .fit)
                                .frame(width: geo.size.width, height: geo.size.height, alignment: .bottom)
                                .clipped()
                        }
                    }
                }
                character(in: geo.size)
            }
        }
    }

    @ViewBuilder
    private func character(in size: CGSize) -> some View {
        ZStack {
            // 베이스 = 통합 실루엣 의상 (없으면 맨몸)
            Image(equipped[.bodyFront].map(assetName) ?? "piyak_base")
                .resizable().scaledToFit()
            // 액세서리 오버레이 (앵커 위치)
            ForEach(Self.overlaySlots, id: \.self) { slot in
                if let id = equipped[slot], let a = Self.anchor[slot] {
                    Image(assetName(id)).resizable().scaledToFit()
                        .frame(width: size.width * 0.5)
                        .position(x: size.width * a.x, y: size.height * a.y)
                }
            }
        }
    }

    private var equipped: [DecorSlot: String] {
        var m: [DecorSlot: String] = [:]
        for o in owned { if let s = o.equippedSlot { m[s] = o.catalogId } }
        return m
    }
}
