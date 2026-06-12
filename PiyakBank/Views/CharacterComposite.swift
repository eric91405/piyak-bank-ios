import SwiftUI
import SwiftData

struct CharacterComposite: View {
    var showRoom: Bool = true
    var fillRoom: Bool = false
    var isWorking: Bool = false
    var workedHours: Double = 0
    @Query private var owned: [OwnedItem]
    
    @State private var bob = false
    
    private static let overlaySlots: [DecorSlot] = [.neck, .headband, .eyes, .headTop]
    private static let roomSlots: [DecorSlot] = [.bg, .wallDeco, .bigFurniture, .floorProp, .rug]
    
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                if showRoom {
                    ForEach(Self.roomSlots, id: \.self) { slot in
                        if let id = equipped[slot] {
                            if fillRoom {
                                Image(assetName(id))
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: geo.size.width, height: geo.size.height, alignment: .bottom)
                                    .clipped()
                            } else {
                                // 꾸미기: 연장분 잘라내고 원본 정사각 영역만
                                let side = min(geo.size.width, geo.size.height)
                                Image(assetName(id))
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: side, height: side, alignment: .bottom)
                                    .clipped()
                                    .frame(width: geo.size.width, height: geo.size.height, alignment: .bottom)
                            }
                        }
                    }
                }
                TimelineView(.animation) { timeline in
                    let t = timeline.date.timeIntervalSinceReferenceDate
                    let period = isWorking ? 0.5 : 2.4      // 근무중 빠르게
                    let height = isWorking ? 10.0 : 5.0     // 근무중 크게
                    character(in: geo.size)
                        .offset(y: -abs(sin(t * .pi / period)) * height)
                }
            }
        }
    }
    
    @ViewBuilder
    private func character(in size: CGSize) -> some View {
        ZStack {
            Image(equipped[.bodyFront].map(assetName) ?? "piyak_base")
                .resizable().scaledToFit()
            ForEach(Self.overlaySlots, id: \.self) { slot in
                if let id = equipped[slot] {
                    Image(assetName(id))
                        .resizable().scaledToFit()
                }
            }
            if workedHours >= 4 {
                Image("piyak_face_tired").resizable().scaledToFit()
            } else if workedHours >= 2 {
                Image("piyak_face_sweat").resizable().scaledToFit()
            }
        }
    }
    
    
    private var equipped: [DecorSlot: String] {
        var m: [DecorSlot: String] = [:]
        for o in owned { if let s = o.equippedSlot { m[s] = o.catalogId } }
        return m
    }
}
