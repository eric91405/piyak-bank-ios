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
    case head          // ① 머리 위
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
    }

    func unequip(slot: DecorSlot) {
        for o in ownedAll() where o.equippedSlot == slot {
            o.equippedSlot = nil
        }
        try? context.save()
    }

    func equippedId(for slot: DecorSlot) -> String? {
        ownedAll().first { $0.equippedSlot == slot }?.catalogId
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

    // MARK: 시드 (최초 1회)

    func seedIfNeeded() {
        guard catalogAll().isEmpty else { return }
        for s in CatalogSeed.items {
            let item = CatalogItem(id: s.id, slot: s.slot, displayName: s.name,
                                   price: s.price, isIAP: s.isIAP, isDefaultOwned: s.defaultOwned)
            context.insert(item)
            if s.defaultOwned {
                let o = OwnedItem(catalogId: s.id)
                o.equippedSlot = s.slot   // 기본 보유는 바로 착용/배치
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
        // ... 나머지는 catalog_seed.json 로더로 확장
    ]
}
