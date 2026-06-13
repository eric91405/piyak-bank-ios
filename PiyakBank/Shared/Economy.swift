import Foundation
import SwiftData

// MARK: - 슬롯 정의 (방 5슬롯 + 착용 앵커 5종)

enum DecorSlot: String, Codable, CaseIterable {
    // 방 배치 슬롯 (뒤 → 앞)
    case bg            // 배경 테마
    case wallDeco      // 벽 장식
    case bigFurniture  // 큰 가구 (책장 등)
    case floorProp     // 바닥 소품 (화분 등)
    case rug           // 러그 (캐릭터 발 아래)
    // 캐릭터 착용 앵커
    case headTop          // ① 머리 위
    case eyes          // ② 눈
    case headband      // ③ 머리 둘레
    case neck          // ④ 목
    case bodyFront     // ⑤ 몸 앞 (통합 실루엣 Method B)
    
    
    var isRoom: Bool {
        switch self {
        case .bg, .wallDeco, .bigFurniture, .floorProp, .rug: return true
        default: return false
        }
    }
    
    /// 방 슬롯 z-order (작을수록 뒤)
    var roomZ: Int {
        switch self {
        case .bg: return 0
        case .wallDeco: return 1
        case .bigFurniture: return 2
        case .floorProp: return 3
        case .rug: return 4
        default: return 99
        }
    }
}

// MARK: - 카탈로그 아이템 (상점 진열 단위)

@Model
final class CatalogItem {
    /// "{slot}.{name}" 형식, asset catalog id와 1:1 (예: "bg.cozy_cream")
    @Attribute(.unique) var id: String
    var slotRaw: String
    var displayName: String
    /// 포인트 가격 (무료=0, IAP=결제 전용이라 0)
    var price: Int
    /// true면 포인트로 못 사고 StoreKit 결제 전용
    var isIAP: Bool
    /// 신규 유저 기본 보유
    var isDefaultOwned: Bool
    
    var slot: DecorSlot { DecorSlot(rawValue: slotRaw) ?? .floorProp }
    
    init(id: String, slot: DecorSlot, displayName: String,
         price: Int = 0, isIAP: Bool = false, isDefaultOwned: Bool = false) {
        self.id = id
        self.slotRaw = slot.rawValue
        self.displayName = displayName
        self.price = price
        self.isIAP = isIAP
        self.isDefaultOwned = isDefaultOwned
    }
}

// MARK: - 보유 아이템

@Model
final class OwnedItem {
    @Attribute(.unique) var catalogId: String
    var acquiredAt: Date
    /// 현재 착용/배치 중인 슬롯. nil이면 보관함에만 있음
    var equippedSlotRaw: String?
    
    var equippedSlot: DecorSlot? {
        get { equippedSlotRaw.flatMap { DecorSlot(rawValue: $0) } }
        set { equippedSlotRaw = newValue?.rawValue }
    }
    
    init(catalogId: String, acquiredAt: Date = .now, equippedSlot: DecorSlot? = nil) {
        self.catalogId = catalogId
        self.acquiredAt = acquiredAt
        self.equippedSlotRaw = equippedSlot?.rawValue
    }
}

// MARK: - 포인트 원장 (단일 잔액 필드 대신 거래 기록으로 추적)

enum TxKind: String, Codable {
    case accrual    // 근무 적립 (+)
    case purchase   // 아이템 구매 (-)
    case refund     // 환불 (+, 50% floor)
    case adjust     // 수동 보정
}

@Model
final class PointTransaction {
    @Attribute(.unique) var id: UUID
    /// 내부 계산은 Decimal, 저장은 정수 포인트(floor 적용 후)
    var amount: Int
    var kindRaw: String
    var date: Date
    /// 관련 세션/아이템 id (감사 추적용)
    var relatedId: String?
    var note: String?
    
    var kind: TxKind { TxKind(rawValue: kindRaw) ?? .adjust }
    
    init(amount: Int, kind: TxKind, date: Date = .now,
         relatedId: String? = nil, note: String? = nil) {
        self.id = UUID()
        self.amount = amount
        self.kindRaw = kind.rawValue
        self.date = date
        self.relatedId = relatedId
        self.note = note
    }
}

// MARK: - EconomyStore (원장 합산 · 구매 · 환불 · 착용 · 시드)

@MainActor
final class EconomyStore {
    let context: ModelContext
    
    init(context: ModelContext) {
        self.context = context
    }
    
    // 잔액 = 원장 전체 합산 (lazy)
    var balance: Int {
        let all = (try? context.fetch(FetchDescriptor<PointTransaction>())) ?? []
        return all.reduce(0) { $0 + $1.amount }
    }
    
    /// 특정 날짜의 적립 합 (자정 리셋 없이 날짜 필터로 계산)
    func dailyAccrued(on day: Date) -> Int {
        let cal = Calendar.current
        let start = cal.startOfDay(for: day)
        guard let end = cal.date(byAdding: .day, value: 1, to: start) else { return 0 }
        let desc = FetchDescriptor<PointTransaction>(
            predicate: #Predicate { $0.date >= start && $0.date < end && $0.kindRaw == "accrual" }
        )
        let txs = (try? context.fetch(desc)) ?? []
        return txs.reduce(0) { $0 + $1.amount }
    }
    
    // MARK: 적립
    
    func recordAccrual(_ amount: Int, sessionId: String, at date: Date = .now) {
        guard amount > 0 else { return }
        context.insert(PointTransaction(amount: amount, kind: .accrual,
                                        date: date, relatedId: sessionId))
        try? context.save()
    }
    
    // MARK: 구매 / 환불
    
    enum PurchaseError: Error { case alreadyOwned, insufficient, iapOnly, notFound }
    
    func purchase(_ catalogId: String) throws {
        guard let item = catalog(catalogId) else { throw PurchaseError.notFound }
        if item.isIAP { throw PurchaseError.iapOnly }      // StoreKit 경유해야 함
        if owned(catalogId) != nil { throw PurchaseError.alreadyOwned }
        guard balance >= item.price else { throw PurchaseError.insufficient }
        
        context.insert(PointTransaction(amount: -item.price, kind: .purchase,
                                        relatedId: catalogId))
        context.insert(OwnedItem(catalogId: catalogId))
        try? context.save()
    }
    
    /// IAP 결제 성공 후 StoreManager가 호출 (포인트 차감 없이 보유 추가)
    func grantIAP(_ catalogId: String) {
        guard owned(catalogId) == nil else { return }
        context.insert(OwnedItem(catalogId: catalogId))
        try? context.save()
    }
    
    func refund(_ catalogId: String) {
        guard let owned = owned(catalogId), let item = catalog(catalogId) else { return }
        if item.isIAP { return }  // IAP는 자체 환불 정책
        let back = Int((Decimal(item.price) * 0.5 as NSDecimalNumber).doubleValue)  // 50% floor
        context.insert(PointTransaction(amount: back, kind: .refund, relatedId: catalogId))
        context.delete(owned)
        try? context.save()
    }
    
    // MARK: 착용 / 배치
    
    func equip(_ catalogId: String) {
        guard let target = owned(catalogId), let item = catalog(catalogId) else { return }
        let slot = item.slot
        // 같은 슬롯의 기존 착용 해제 (슬롯당 1개)
        for o in ownedAll() where o.equippedSlot == slot {
            o.equippedSlot = nil
        }
        target.equippedSlot = slot
        try? context.save()
        NotificationCenter.default.post(name: .piyakEquippedChanged, object: nil)
    }
    
    func unequip(slot: DecorSlot) {
        for o in ownedAll() where o.equippedSlot == slot {
            o.equippedSlot = nil
        }
        try? context.save()
        NotificationCenter.default.post(name: .piyakEquippedChanged, object: nil)
    }
    
    func equippedId(for slot: DecorSlot) -> String? {
        ownedAll().first { $0.equippedSlot == slot }?.catalogId
    }
    
    func equippedMap() -> [String: String] {
        var m: [String: String] = [:]
        for o in ownedAll() {
            if let s = o.equippedSlotRaw { m[s] = o.catalogId }
        }
        return m
    }
    
    // MARK: 조회
    
    func catalog(_ id: String) -> CatalogItem? {
        let desc = FetchDescriptor<CatalogItem>(predicate: #Predicate { $0.id == id })
        return (try? context.fetch(desc))?.first
    }
    
    func owned(_ id: String) -> OwnedItem? {
        let desc = FetchDescriptor<OwnedItem>(predicate: #Predicate { $0.catalogId == id })
        return (try? context.fetch(desc))?.first
    }
    
    func ownedAll() -> [OwnedItem] {
        (try? context.fetch(FetchDescriptor<OwnedItem>())) ?? []
    }
    
    func catalogAll() -> [CatalogItem] {
        (try? context.fetch(FetchDescriptor<CatalogItem>())) ?? []
    }
    
    // MARK: 시드 (없는 항목만 추가 — 카탈로그 확장 시 재설치 불필요)
    func seedIfNeeded() {
        for s in CatalogSeed.items {
            guard catalog(s.id) == nil else { continue }   // 이미 있으면 건너뜀
            let item = CatalogItem(id: s.id, slot: s.slot, displayName: s.name,
                                   price: s.price, isIAP: s.isIAP, isDefaultOwned: s.defaultOwned)
            context.insert(item)
            if s.defaultOwned && owned(s.id) == nil {
                let o = OwnedItem(catalogId: s.id)
                o.equippedSlot = s.slot
                context.insert(o)
            }
        }
        try? context.save()
    }
}

// MARK: - 카탈로그 시드 (catalog_seed.json 대응 핵심 항목)

struct CatalogSeed {
    let id: String; let slot: DecorSlot; let name: String
    let price: Int; let isIAP: Bool; let defaultOwned: Bool
    
    static let items: [CatalogSeed] = [
        // 기본 보유 (무료)
        .init(id: "bg.cozy_cream",        slot: .bg,        name: "포근한 크림", price: 0, isIAP: false, defaultOwned: true),
        .init(id: "floorProp.plant",      slot: .floorProp, name: "화분",       price: 0, isIAP: false, defaultOwned: true),
        .init(id: "rug.oval_coral",       slot: .rug,       name: "코랄 러그",   price: 0, isIAP: false, defaultOwned: true),
        .init(id: "bodyFront.hoodie_mint",slot: .bodyFront, name: "민트 후드티", price: 0, isIAP: false, defaultOwned: true),
        // IAP 전용 (결제)
        .init(id: "bodyFront.graduation_gown", slot: .bodyFront, name: "졸업 가운", price: 0, isIAP: true, defaultOwned: false),
        // 포인트 구매 (가격 티어: 저 8~12k / 중 15~25k / 고 40~80k)
        .init(id: "bg.night_sky",     slot: .bg,           name: "밤하늘",     price: 25000, isIAP: false, defaultOwned: false),
        .init(id: "wallDeco.clock",   slot: .wallDeco,     name: "벽시계",     price: 9000,  isIAP: false, defaultOwned: false),
        .init(id: "bigFurniture.bookshelf", slot: .bigFurniture, name: "책장", price: 45000, isIAP: false, defaultOwned: false),
        .init(id: "bg.sky_blue",     slot: .bg, name: "맑은 하늘", price: 18000, isIAP: false, defaultOwned: false),
        .init(id: "bg.sakura_pink",  slot: .bg, name: "벚꽃",     price: 22000, isIAP: false, defaultOwned: false),
        
        // 러그
        .init(id: "rug.round_stripe", slot: .rug, name: "줄무늬 러그", price: 12000, isIAP: false, defaultOwned: false),
        .init(id: "rug.cloud",        slot: .rug, name: "구름 러그",   price: 16000, isIAP: false, defaultOwned: false),
        .init(id: "rug.star",         slot: .rug, name: "별 러그",     price: 16000, isIAP: false, defaultOwned: false),
        // 바닥 소품
        .init(id: "floorProp.lamp",   slot: .floorProp, name: "스탠드 조명", price: 14000, isIAP: false, defaultOwned: false),
        .init(id: "floorProp.books",  slot: .floorProp, name: "책 더미",    price: 10000, isIAP: false, defaultOwned: false),
        .init(id: "floorProp.puppy",  slot: .floorProp, name: "강아지 인형", price: 20000, isIAP: false, defaultOwned: false),
        
        // 벽장식
        .init(id: "wallDeco.frame",  slot: .wallDeco, name: "액자",   price: 11000, isIAP: false, defaultOwned: false),
        .init(id: "wallDeco.mirror", slot: .wallDeco, name: "거울",   price: 13000, isIAP: false, defaultOwned: false),
        // 가구
        .init(id: "bigFurniture.nightstand", slot: .bigFurniture, name: "협탁", price: 40000, isIAP: false, defaultOwned: false),
        .init(id: "bigFurniture.shelf",      slot: .bigFurniture, name: "벽 선반", price: 38000, isIAP: false, defaultOwned: false),
        
        // 액세서리
        .init(id: "headTop.straw_hat",  slot: .headTop, name: "밀짚모자",   price: 12000, isIAP: false, defaultOwned: false),
        .init(id: "eyes.round_glasses", slot: .eyes,    name: "둥근안경",   price: 15000, isIAP: false, defaultOwned: false),
        .init(id: "neck.scarf_coral",   slot: .neck,    name: "포근 목도리", price: 10000, isIAP: false, defaultOwned: false),
        
        //추가
        // 배경
        .init(id: "bg.mint_garden", slot: .bg, name: "민트 가든", price: 20000, isIAP: false, defaultOwned: false),
        .init(id: "bg.lavender", slot: .bg, name: "라벤더", price: 22000, isIAP: false, defaultOwned: false),
        .init(id: "bg.sunset", slot: .bg, name: "노을", price: 24000, isIAP: false, defaultOwned: false),
        .init(id: "bg.ocean", slot: .bg, name: "바다", price: 24000, isIAP: false, defaultOwned: false),
        .init(id: "bg.forest", slot: .bg, name: "숲속", price: 26000, isIAP: false, defaultOwned: false),

        // 벽장식
        .init(id: "wallDeco.garland", slot: .wallDeco, name: "가랜드", price: 9000, isIAP: false, defaultOwned: false),
        .init(id: "wallDeco.poster", slot: .wallDeco, name: "삐약 포스터", price: 10000, isIAP: false, defaultOwned: false),
        .init(id: "wallDeco.window", slot: .wallDeco, name: "창문", price: 13000, isIAP: false, defaultOwned: false),
        .init(id: "wallDeco.hanging_plant", slot: .wallDeco, name: "행잉플랜트", price: 12000, isIAP: false, defaultOwned: false),
        .init(id: "wallDeco.photo_frames", slot: .wallDeco, name: "사진 액자", price: 11000, isIAP: false, defaultOwned: false),
        .init(id: "wallDeco.moon_lamp", slot: .wallDeco, name: "달 조명", price: 14000, isIAP: false, defaultOwned: false),

        // 가구
        .init(id: "bigFurniture.sofa", slot: .bigFurniture, name: "소파", price: 42000, isIAP: false, defaultOwned: false),
        .init(id: "bigFurniture.wardrobe", slot: .bigFurniture, name: "옷장", price: 44000, isIAP: false, defaultOwned: false),
        .init(id: "bigFurniture.piano", slot: .bigFurniture, name: "피아노", price: 80000, isIAP: false, defaultOwned: false),
        .init(id: "bigFurniture.desk", slot: .bigFurniture, name: "책상", price: 40000, isIAP: false, defaultOwned: false),
        .init(id: "bigFurniture.fridge", slot: .bigFurniture, name: "냉장고", price: 48000, isIAP: false, defaultOwned: false),
        .init(id: "bigFurniture.tv", slot: .bigFurniture, name: "TV", price: 60000, isIAP: false, defaultOwned: false),

        // 소품
        .init(id: "floorProp.moon_jar", slot: .floorProp, name: "달항아리", price: 18000, isIAP: false, defaultOwned: false),
        .init(id: "floorProp.cactus", slot: .floorProp, name: "선인장", price: 12000, isIAP: false, defaultOwned: false),
        .init(id: "floorProp.balloons", slot: .floorProp, name: "풍선", price: 14000, isIAP: false, defaultOwned: false),
        .init(id: "floorProp.toybox", slot: .floorProp, name: "장난감 상자", price: 16000, isIAP: false, defaultOwned: false),
        .init(id: "floorProp.coin_pile", slot: .floorProp, name: "동전 더미", price: 22000, isIAP: false, defaultOwned: false),

        // 러그
        .init(id: "rug.checker", slot: .rug, name: "체크 러그", price: 13000, isIAP: false, defaultOwned: false),
        .init(id: "rug.heart", slot: .rug, name: "하트 러그", price: 15000, isIAP: false, defaultOwned: false),
        .init(id: "rug.rainbow", slot: .rug, name: "무지개 러그", price: 17000, isIAP: false, defaultOwned: false),
        .init(id: "rug.leaf", slot: .rug, name: "잎사귀 러그", price: 14000, isIAP: false, defaultOwned: false),
        .init(id: "rug.donut", slot: .rug, name: "도넛 러그", price: 16000, isIAP: false, defaultOwned: false),

        // 옷
        .init(id: "bodyFront.stripe_tee", slot: .bodyFront, name: "줄무늬 티", price: 15000, isIAP: false, defaultOwned: false),
        .init(id: "bodyFront.overalls", slot: .bodyFront, name: "멜빵바지", price: 18000, isIAP: false, defaultOwned: false),
        .init(id: "bodyFront.sweater", slot: .bodyFront, name: "니트 스웨터", price: 17000, isIAP: false, defaultOwned: false),
        .init(id: "bodyFront.raincoat", slot: .bodyFront, name: "비옷", price: 19000, isIAP: false, defaultOwned: false),
        .init(id: "bodyFront.suit_vest", slot: .bodyFront, name: "정장 조끼", price: 25000, isIAP: false, defaultOwned: false),
        .init(id: "bodyFront.pajama", slot: .bodyFront, name: "잠옷", price: 16000, isIAP: false, defaultOwned: false),
        .init(id: "bodyFront.padding_vest", slot: .bodyFront, name: "패딩 조끼", price: 22000, isIAP: false, defaultOwned: false),

        // 모자
        .init(id: "headTop.beret", slot: .headTop, name: "베레모", price: 12000, isIAP: false, defaultOwned: false),
        .init(id: "headTop.party_cone", slot: .headTop, name: "파티 고깔", price: 9000, isIAP: false, defaultOwned: false),
        .init(id: "headTop.crown", slot: .headTop, name: "왕관", price: 30000, isIAP: false, defaultOwned: false),
        .init(id: "headTop.beanie", slot: .headTop, name: "비니", price: 13000, isIAP: false, defaultOwned: false),
        .init(id: "headTop.cap", slot: .headTop, name: "캡모자", price: 14000, isIAP: false, defaultOwned: false),
        .init(id: "headTop.wizard_hat", slot: .headTop, name: "마법사 모자", price: 20000, isIAP: false, defaultOwned: false),
        .init(id: "headTop.flower", slot: .headTop, name: "꽃 장식", price: 10000, isIAP: false, defaultOwned: false),
        .init(id: "headTop.chef_hat", slot: .headTop, name: "요리사 모자", price: 15000, isIAP: false, defaultOwned: false),

        // 눈
        .init(id: "eyes.sunglasses", slot: .eyes, name: "선글라스", price: 16000, isIAP: false, defaultOwned: false),
        .init(id: "eyes.heart_glasses", slot: .eyes, name: "하트 안경", price: 15000, isIAP: false, defaultOwned: false),
        .init(id: "eyes.star_glasses", slot: .eyes, name: "별 안경", price: 15000, isIAP: false, defaultOwned: false),
        .init(id: "eyes.monocle", slot: .eyes, name: "외알 안경", price: 18000, isIAP: false, defaultOwned: false),
        .init(id: "eyes.goggles", slot: .eyes, name: "고글", price: 17000, isIAP: false, defaultOwned: false),
        .init(id: "eyes.eyepatch", slot: .eyes, name: "안대", price: 14000, isIAP: false, defaultOwned: false),
        .init(id: "eyes.glasses_red", slot: .eyes, name: "빨간 뿔테", price: 13000, isIAP: false, defaultOwned: false),
        .init(id: "eyes.glasses_blue", slot: .eyes, name: "파란 뿔테", price: 13000, isIAP: false, defaultOwned: false),

        // 목
        .init(id: "neck.ribbon", slot: .neck, name: "리본", price: 10000, isIAP: false, defaultOwned: false),
        .init(id: "neck.bowtie", slot: .neck, name: "나비넥타이", price: 12000, isIAP: false, defaultOwned: false),
        .init(id: "neck.gold_chain", slot: .neck, name: "골드 체인", price: 28000, isIAP: false, defaultOwned: false),
        .init(id: "neck.scarf_mint", slot: .neck, name: "민트 목도리", price: 11000, isIAP: false, defaultOwned: false),
        .init(id: "neck.pearl", slot: .neck, name: "진주 목걸이", price: 24000, isIAP: false, defaultOwned: false),
        .init(id: "neck.bandana", slot: .neck, name: "반다나", price: 10000, isIAP: false, defaultOwned: false),
        .init(id: "neck.bell", slot: .neck, name: "방울", price: 9000, isIAP: false, defaultOwned: false),
        .init(id: "neck.tie", slot: .neck, name: "넥타이", price: 13000, isIAP: false, defaultOwned: false),
    ]
}

// MARK: - asset 이름 변환
// 카탈로그 id "bg.cozy_cream" → asset 이름 "bg_cozy_cream"
// (Xcode asset 이름의 점은 namespace로 오인될 수 있어 언더스코어로 통일)
func assetName(_ catalogId: String) -> String {
    catalogId.replacingOccurrences(of: ".", with: "_")
}

extension Notification.Name {
    static let piyakEquippedChanged = Notification.Name("piyakEquippedChanged")
}
