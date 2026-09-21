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
    /// 포인트 가격 (기본 제공 아이템은 0)
    var price: Int
    /// 기존 저장소 호환용 필드. 무료 출시 버전은 false로 마이그레이션.
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
    case accrual    // 타이머 시간 보상 (+), 성장 경험치
    case purchase   // 아이템 구매 (-)
    case refund     // 환불 (+, 50% floor)
    case adjust     // 수동 보정
    case legacy     // 이전 단위 원장 보관용, 현재 잔액/성장에는 미포함
    case migration  // 새 단위로 전환한 잔액, 성장에는 미포함
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

/// A receipt outlives editable/deletable wage records. Its unique session ID and
/// original intervals prevent repeat settlement, backdating and duplicate-time grants.
@Model
final class RewardReceipt {
    @Attribute(.unique) var sessionId: String
    var intervalsData: Data
    var createdAt: Date
    /// Only the policy marker uses this anchor; finalized work receipts are immutable.
    var clockData: Data?

    init(sessionId: String, intervals: [RewardInterval], createdAt: Date) throws {
        self.sessionId = sessionId
        self.intervalsData = try JSONEncoder().encode(intervals)
        self.createdAt = createdAt
    }

    func intervals() throws -> [RewardInterval] {
        try JSONDecoder().decode([RewardInterval].self, from: intervalsData)
    }
}

// MARK: - EconomyStore (원장 합산 · 구매 · 환불 · 착용 · 시드)

@MainActor
final class EconomyStore {
    let context: ModelContext
    // Injected by persistence tests to exercise a disk-write failure.
    var save: () throws -> Void

    init(context: ModelContext, save: (() throws -> Void)? = nil) {
        self.context = context
        self.save = save ?? { try context.save() }
    }

    func transaction(restoring restore: () -> Void = {}, _ changes: () throws -> Void) throws {
        let marker = try rewardPolicyMarker()
        let clockData = marker?.clockData
        do {
            try changes()
            context.processPendingChanges()
            try save()
        } catch {
            context.processPendingChanges()
            context.rollback()
            marker?.clockData = clockData
            restore()
            throw error
        }
    }

    private func rewardPolicyMarker() throws -> RewardReceipt? {
        let id = "reward-policy-v1"
        return try context.fetch(FetchDescriptor<RewardReceipt>(predicate: #Predicate { $0.sessionId == id })).first
    }

    /// Advance a persisted reward calendar with measured elapsed time. Changing the
    /// phone's date between sessions cannot reset a daily cap on the same device boot.
    /// This must be called inside the caller's save transaction.
    func rewardDate(now: Date, tick: TimeInterval, bootSessionID: String) throws -> Date {
        guard tick.isFinite, let marker = try rewardPolicyMarker() else { throw StoreError.corruptRecord }
        let prior = try marker.clockData.map { try JSONDecoder().decode(RewardClockAnchor.self, from: $0) }
        let date: Date
        if let prior {
            let elapsed = tick - prior.tick
            // Reboot: unmeasurable pending timer time earns nothing. Rebase the
            // calendar without moving backwards. Offline clocks cannot attest a reboot.
            date = elapsed >= 0 && prior.bootSessionID == bootSessionID
                ? prior.date.addingTimeInterval(elapsed) : max(prior.date, now)
        } else { date = now }
        marker.clockData = try JSONEncoder().encode(RewardClockAnchor(date: date, tick: tick, bootSessionID: bootSessionID))
        return date
    }

    func balance() throws -> Int {
        try context.fetch(FetchDescriptor<PointTransaction>()).filter { $0.kind != .legacy }.reduce(0) { $0 + $1.amount }
    }

    /// Currency comes exclusively from wage records, never from game points.
    func dailyAccrued(on day: Date, includingActive: Bool = false, now: Date = .now) throws -> Int {
        var amount = 0
        for session in try context.fetch(FetchDescriptor<WorkSession>()) where includingActive || !session.isActive {
            amount += EarningsCalculator.earned(on: day, segments: try session.decodedSegments(), until: now)
        }
        return amount
    }

    enum StoreError: LocalizedError {
        case alreadyOwned, insufficient, notFound, invalidRecord, corruptRecord, activeRecord
        var errorDescription: String? {
            switch self {
            case .alreadyOwned: "이미 보유한 아이템이에요."
            case .insufficient: "포인트가 부족해요. 근무를 마치면 포인트를 받을 수 있어요."
            case .notFound: "아이템을 찾지 못했어요. 다시 열어 주세요."
            case .invalidRecord: "시간과 시급을 확인해 주세요. 구간은 겹칠 수 없고, 시급은 0~1,000,000원까지 입력할 수 있어요."
            case .corruptRecord: "근무 기록을 읽지 못했어요. 원본을 보존했으니 지원팀에 문의해 주세요."
            case .activeRecord: "진행 중인 근무를 먼저 마쳐 주세요."
            }
        }
    }

    func purchase(_ id: String, equip: Bool = false) throws {
        guard let item = try catalog(id) else { throw StoreError.notFound }
        guard try owned(id) == nil else { throw StoreError.alreadyOwned }
        guard try balance() >= item.price else { throw StoreError.insufficient }
        let restore = try equipmentRestorePoint()
        try transaction(restoring: restore) {
            context.insert(PointTransaction(amount: -item.price, kind: .purchase, relatedId: id))
            if equip {
                for previous in try ownedAll() where previous.equippedSlot == item.slot { previous.equippedSlot = nil }
            }
            context.insert(OwnedItem(catalogId: id, equippedSlot: equip ? item.slot : nil))
        }
        if equip { NotificationCenter.default.post(name: .piyakEquippedChanged, object: nil) }
    }

    func equip(_ id: String) throws {
        guard let target = try owned(id), let item = try catalog(id) else { throw StoreError.notFound }
        let restore = try equipmentRestorePoint()
        try transaction(restoring: restore) {
            for itemOwned in try ownedAll() where itemOwned.equippedSlot == item.slot {
                itemOwned.equippedSlot = nil
            }
            target.equippedSlot = item.slot
        }
        NotificationCenter.default.post(name: .piyakEquippedChanged, object: nil)
    }

    func unequip(slot: DecorSlot) throws {
        let restore = try equipmentRestorePoint()
        try transaction(restoring: restore) {
            for item in try ownedAll() where item.equippedSlot == slot { item.equippedSlot = nil }
        }
        NotificationCenter.default.post(name: .piyakEquippedChanged, object: nil)
    }

    private func equipmentRestorePoint() throws -> () -> Void {
        let values = try ownedAll().map { ($0, $0.equippedSlotRaw) }
        return { for (item, slot) in values { item.equippedSlotRaw = slot } }
    }

    func equippedMap() throws -> [String: String] {
        var result: [String: String] = [:]
        for item in try ownedAll() {
            if let slot = item.equippedSlotRaw { result[slot] = item.catalogId }
        }
        return result
    }

    func catalog(_ id: String) throws -> CatalogItem? {
        try context.fetch(FetchDescriptor<CatalogItem>(predicate: #Predicate { $0.id == id })).first
    }
    func owned(_ id: String) throws -> OwnedItem? {
        try context.fetch(FetchDescriptor<OwnedItem>(predicate: #Predicate { $0.catalogId == id })).first
    }
    func ownedAll() throws -> [OwnedItem] { try context.fetch(FetchDescriptor<OwnedItem>()) }

    /// Called inside the same transaction as stop. Even zero-point work gets a receipt
    /// so fractions accumulate without permitting retries to earn twice.
    @discardableResult
    func insertAccruals(for session: WorkSession, now: Date = .now) throws -> Int {
        let receipts = try context.fetch(FetchDescriptor<RewardReceipt>())
        guard !receipts.contains(where: { $0.sessionId == session.id }),
              let tracking = try session.rewardTracking() else { return 0 }
        let previous = try receipts.flatMap { try $0.intervals() }
        // Tracking uses a monotonic reward calendar, which intentionally differs
        // from a manually changed wall clock. Do not clip it with editable wall time.
        let newIntervals = tracking.intervals
        let priorDays = Dictionary(uniqueKeysWithValues: RewardPolicy.daily(previous, calendar: RewardPolicy.calendar).map { ($0.day, $0.points) })
        let nextDays = RewardPolicy.daily(previous + newIntervals, calendar: RewardPolicy.calendar)
        var awarded = 0
        for day in nextDays {
            let delta = max(0, day.points - priorDays[day.day, default: 0])
            if delta > 0 {
                context.insert(PointTransaction(amount: delta, kind: .accrual,
                                                date: day.day, relatedId: session.id,
                                                note: "타이머 근무 시간 보상 · 한국 시간 기준"))
                awarded += delta
            }
        }
        context.insert(try RewardReceipt(sessionId: session.id, intervals: newIntervals, createdAt: now))
        return awarded
    }

    func replaceRecord(_ record: WorkSession?, segments: [WageSegment], now: Date = .now) throws {
        guard record?.isActive != true else { throw StoreError.activeRecord }
        let sorted = segments.sorted { $0.start < $1.start }
        guard !sorted.isEmpty, let first = sorted.first, let end = sorted.last?.end,
              end <= now, end.timeIntervalSince(first.start) <= EarningsCalculator.maximumSessionDuration,
              sorted.allSatisfy({ $0.start < ($0.end ?? $0.start) && ($0.end ?? now) <= now && (0...EarningsCalculator.maximumWage).contains($0.hourlyWage) }),
              zip(sorted, sorted.dropFirst()).allSatisfy({ ($0.0.end ?? now) <= $0.1.start }) else {
            throw StoreError.invalidRecord
        }
        // Overlapping records would award the same working time twice.
        for other in try context.fetch(FetchDescriptor<WorkSession>()) where other.id != record?.id {
            let otherEnd = other.endedAt ?? now
            guard end <= other.startedAt || first.start >= otherEnd else { throw StoreError.invalidRecord }
        }
        let restore = record?.restorePoint() ?? {}
        try transaction(restoring: restore) {
            let session = record ?? WorkSession(startedAt: first.start, wage: first.hourlyWage)
            if record == nil { context.insert(session) }
            session.startedAt = first.start
            session.endedAt = end
            session.segments = sorted
            session.isActive = false
            // Pay corrections never modify finalized timer receipts or mint new points.
        }
    }

    func deleteRecord(_ record: WorkSession) throws {
        guard !record.isActive else { throw StoreError.activeRecord }
        try transaction {
            context.delete(record)
        }
    }

    /// Update catalog metadata while preserving every existing ownership and ledger entry.
    func seedIfNeeded() throws {
        try transaction {
            for seed in CatalogSeed.items {
                if let item = try catalog(seed.id) {
                    item.displayName = seed.name
                    item.price = seed.price
                    item.isIAP = false
                } else {
                    context.insert(CatalogItem(id: seed.id, slot: seed.slot, displayName: seed.name,
                                               price: seed.price, isDefaultOwned: seed.defaultOwned))
                    if seed.defaultOwned, try owned(seed.id) == nil {
                        let hasSlot = try ownedAll().contains { $0.equippedSlot == seed.slot }
                        context.insert(OwnedItem(catalogId: seed.id, equippedSlot: hasSlot ? nil : seed.slot))
                    }
                }
            }
        }
    }

    /// Preserve old records and owned items; archive the old unit of account. The
    /// in-store marker commits atomically, so reinstalling defaults cannot rerun it.
    func migrateRewardsIfNeeded(now: Date = .now) throws {
        let marker = "reward-policy-v1"
        guard try context.fetch(FetchDescriptor<RewardReceipt>(predicate: #Predicate { $0.sessionId == marker })).isEmpty else { return }
        let old = try context.fetch(FetchDescriptor<PointTransaction>())
        let priorBalance = old.filter { $0.kind != .legacy }.reduce(0) { $0 + $1.amount }
        let converted = min(RewardPolicy.pointsPerDay, max(0, priorBalance / 20))
        let values = old.map { ($0, $0.kindRaw, $0.note) }
        try transaction(restoring: {
            for (tx, kind, note) in values { tx.kindRaw = kind; tx.note = note }
        }) {
            for tx in old {
                tx.note = "이전 단위 [\(tx.kindRaw)] " + (tx.note ?? "")
                tx.kindRaw = TxKind.legacy.rawValue
            }
            if !old.isEmpty {
                context.insert(PointTransaction(amount: converted, kind: .migration, date: now,
                                                relatedId: marker,
                                                note: "이전 잔액 \(priorBalance)P를 20:1로 전환 · 최대 4,800P · 보유 아이템 유지"))
            }
            context.insert(try RewardReceipt(sessionId: marker, intervals: [], createdAt: now))
        }
    }

    func resetAll() throws {
        try transaction {
            for item in try context.fetch(FetchDescriptor<WorkSession>()) { context.delete(item) }
            for item in try context.fetch(FetchDescriptor<PointTransaction>()) { context.delete(item) }
            for item in try context.fetch(FetchDescriptor<RewardReceipt>()) { context.delete(item) }
            context.insert(try RewardReceipt(sessionId: "reward-policy-v1", intervals: [], createdAt: .now))
            for item in try ownedAll() { context.delete(item) }
            for item in try context.fetch(FetchDescriptor<CatalogItem>()) { context.delete(item) }
            // Seed in this transaction so reset cannot leave an empty, half-reset store.
            for seed in CatalogSeed.items {
                context.insert(CatalogItem(id: seed.id, slot: seed.slot, displayName: seed.name,
                                           price: seed.price, isDefaultOwned: seed.defaultOwned))
                if seed.defaultOwned { context.insert(OwnedItem(catalogId: seed.id, equippedSlot: seed.slot)) }
            }
        }
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
        // 첫 버전은 모든 아이템을 근무 포인트로 구매
        .init(id: "bodyFront.graduation_gown", slot: .bodyFront, name: "졸업 가운", price: 2000, isIAP: false, defaultOwned: false),
        // 포인트 구매 (시간 보상 가격: 소품 400~600P / 의상 750~1,250P / 가구 1,900~4,000P)
        .init(id: "bg.night_sky",     slot: .bg,           name: "밤하늘",     price: 1250, isIAP: false, defaultOwned: false),
        .init(id: "wallDeco.clock",   slot: .wallDeco,     name: "벽시계",     price: 450,  isIAP: false, defaultOwned: false),
        .init(id: "bigFurniture.bookshelf", slot: .bigFurniture, name: "책장", price: 2250, isIAP: false, defaultOwned: false),
        .init(id: "bg.sky_blue",     slot: .bg, name: "맑은 하늘", price: 900, isIAP: false, defaultOwned: false),
        .init(id: "bg.sakura_pink",  slot: .bg, name: "벚꽃",     price: 1100, isIAP: false, defaultOwned: false),
        
        // 러그
        .init(id: "rug.round_stripe", slot: .rug, name: "줄무늬 러그", price: 600, isIAP: false, defaultOwned: false),
        .init(id: "rug.cloud",        slot: .rug, name: "구름 러그",   price: 800, isIAP: false, defaultOwned: false),
        .init(id: "rug.star",         slot: .rug, name: "별 러그",     price: 800, isIAP: false, defaultOwned: false),
        // 바닥 소품
        .init(id: "floorProp.lamp",   slot: .floorProp, name: "스탠드 조명", price: 700, isIAP: false, defaultOwned: false),
        .init(id: "floorProp.books",  slot: .floorProp, name: "책 더미",    price: 500, isIAP: false, defaultOwned: false),
        .init(id: "floorProp.puppy",  slot: .floorProp, name: "강아지 인형", price: 1000, isIAP: false, defaultOwned: false),
        
        // 벽장식
        .init(id: "wallDeco.frame",  slot: .wallDeco, name: "액자",   price: 550, isIAP: false, defaultOwned: false),
        .init(id: "wallDeco.mirror", slot: .wallDeco, name: "거울",   price: 650, isIAP: false, defaultOwned: false),
        // 가구
        .init(id: "bigFurniture.nightstand", slot: .bigFurniture, name: "협탁", price: 2000, isIAP: false, defaultOwned: false),
        .init(id: "bigFurniture.shelf",      slot: .bigFurniture, name: "벽 선반", price: 1900, isIAP: false, defaultOwned: false),
        
        // 액세서리
        .init(id: "headTop.straw_hat",  slot: .headTop, name: "밀짚모자",   price: 600, isIAP: false, defaultOwned: false),
        .init(id: "eyes.round_glasses", slot: .eyes,    name: "둥근안경",   price: 750, isIAP: false, defaultOwned: false),
        .init(id: "neck.scarf_coral",   slot: .neck,    name: "포근 목도리", price: 500, isIAP: false, defaultOwned: false),
        
        //추가
        // 배경
        .init(id: "bg.mint_garden", slot: .bg, name: "민트 가든", price: 1000, isIAP: false, defaultOwned: false),
        .init(id: "bg.lavender", slot: .bg, name: "라벤더", price: 1100, isIAP: false, defaultOwned: false),
        .init(id: "bg.sunset", slot: .bg, name: "노을", price: 1200, isIAP: false, defaultOwned: false),
        .init(id: "bg.ocean", slot: .bg, name: "바다", price: 1200, isIAP: false, defaultOwned: false),
        .init(id: "bg.forest", slot: .bg, name: "숲속", price: 1300, isIAP: false, defaultOwned: false),

        // 벽장식
        .init(id: "wallDeco.garland", slot: .wallDeco, name: "가랜드", price: 450, isIAP: false, defaultOwned: false),
        .init(id: "wallDeco.poster", slot: .wallDeco, name: "삐약 포스터", price: 500, isIAP: false, defaultOwned: false),
        .init(id: "wallDeco.window", slot: .wallDeco, name: "창문", price: 650, isIAP: false, defaultOwned: false),
        .init(id: "wallDeco.hanging_plant", slot: .wallDeco, name: "행잉플랜트", price: 600, isIAP: false, defaultOwned: false),
        .init(id: "wallDeco.photo_frames", slot: .wallDeco, name: "사진 액자", price: 550, isIAP: false, defaultOwned: false),
        .init(id: "wallDeco.moon_lamp", slot: .wallDeco, name: "달 조명", price: 700, isIAP: false, defaultOwned: false),

        // 가구
        .init(id: "bigFurniture.sofa", slot: .bigFurniture, name: "소파", price: 2100, isIAP: false, defaultOwned: false),
        .init(id: "bigFurniture.wardrobe", slot: .bigFurniture, name: "옷장", price: 2200, isIAP: false, defaultOwned: false),
        .init(id: "bigFurniture.piano", slot: .bigFurniture, name: "피아노", price: 4000, isIAP: false, defaultOwned: false),
        .init(id: "bigFurniture.desk", slot: .bigFurniture, name: "책상", price: 2000, isIAP: false, defaultOwned: false),
        .init(id: "bigFurniture.fridge", slot: .bigFurniture, name: "냉장고", price: 2400, isIAP: false, defaultOwned: false),
        .init(id: "bigFurniture.tv", slot: .bigFurniture, name: "TV", price: 3000, isIAP: false, defaultOwned: false),

        // 소품
        .init(id: "floorProp.moon_jar", slot: .floorProp, name: "달항아리", price: 900, isIAP: false, defaultOwned: false),
        .init(id: "floorProp.cactus", slot: .floorProp, name: "선인장", price: 600, isIAP: false, defaultOwned: false),
        .init(id: "floorProp.balloons", slot: .floorProp, name: "풍선", price: 700, isIAP: false, defaultOwned: false),
        .init(id: "floorProp.toybox", slot: .floorProp, name: "장난감 상자", price: 800, isIAP: false, defaultOwned: false),
        .init(id: "floorProp.coin_pile", slot: .floorProp, name: "동전 더미", price: 1100, isIAP: false, defaultOwned: false),

        // 러그
        .init(id: "rug.checker", slot: .rug, name: "체크 러그", price: 650, isIAP: false, defaultOwned: false),
        .init(id: "rug.heart", slot: .rug, name: "하트 러그", price: 750, isIAP: false, defaultOwned: false),
        .init(id: "rug.rainbow", slot: .rug, name: "무지개 러그", price: 850, isIAP: false, defaultOwned: false),
        .init(id: "rug.leaf", slot: .rug, name: "잎사귀 러그", price: 700, isIAP: false, defaultOwned: false),
        .init(id: "rug.donut", slot: .rug, name: "도넛 러그", price: 800, isIAP: false, defaultOwned: false),

        // 옷
        .init(id: "bodyFront.stripe_tee", slot: .bodyFront, name: "줄무늬 티", price: 750, isIAP: false, defaultOwned: false),
        .init(id: "bodyFront.overalls", slot: .bodyFront, name: "멜빵바지", price: 900, isIAP: false, defaultOwned: false),
        .init(id: "bodyFront.sweater", slot: .bodyFront, name: "니트 스웨터", price: 850, isIAP: false, defaultOwned: false),
        .init(id: "bodyFront.raincoat", slot: .bodyFront, name: "비옷", price: 950, isIAP: false, defaultOwned: false),
        .init(id: "bodyFront.suit_vest", slot: .bodyFront, name: "정장 조끼", price: 1250, isIAP: false, defaultOwned: false),
        .init(id: "bodyFront.pajama", slot: .bodyFront, name: "잠옷", price: 800, isIAP: false, defaultOwned: false),
        .init(id: "bodyFront.padding_vest", slot: .bodyFront, name: "패딩 조끼", price: 1100, isIAP: false, defaultOwned: false),

        // 모자
        .init(id: "headTop.beret", slot: .headTop, name: "베레모", price: 600, isIAP: false, defaultOwned: false),
        .init(id: "headTop.party_cone", slot: .headTop, name: "파티 고깔", price: 450, isIAP: false, defaultOwned: false),
        .init(id: "headTop.crown", slot: .headTop, name: "왕관", price: 1500, isIAP: false, defaultOwned: false),
        .init(id: "headTop.beanie", slot: .headTop, name: "비니", price: 650, isIAP: false, defaultOwned: false),
        .init(id: "headTop.cap", slot: .headTop, name: "캡모자", price: 700, isIAP: false, defaultOwned: false),
        .init(id: "headTop.wizard_hat", slot: .headTop, name: "마법사 모자", price: 1000, isIAP: false, defaultOwned: false),
        .init(id: "headTop.flower", slot: .headTop, name: "꽃 장식", price: 500, isIAP: false, defaultOwned: false),
        .init(id: "headTop.chef_hat", slot: .headTop, name: "요리사 모자", price: 750, isIAP: false, defaultOwned: false),

        // 눈
        .init(id: "eyes.sunglasses", slot: .eyes, name: "선글라스", price: 800, isIAP: false, defaultOwned: false),
        .init(id: "eyes.heart_glasses", slot: .eyes, name: "하트 안경", price: 750, isIAP: false, defaultOwned: false),
        .init(id: "eyes.star_glasses", slot: .eyes, name: "별 안경", price: 750, isIAP: false, defaultOwned: false),
        .init(id: "eyes.monocle", slot: .eyes, name: "외알 안경", price: 900, isIAP: false, defaultOwned: false),
        .init(id: "eyes.goggles", slot: .eyes, name: "고글", price: 850, isIAP: false, defaultOwned: false),
        .init(id: "eyes.eyepatch", slot: .eyes, name: "안대", price: 700, isIAP: false, defaultOwned: false),
        .init(id: "eyes.glasses_red", slot: .eyes, name: "빨간 뿔테", price: 650, isIAP: false, defaultOwned: false),
        .init(id: "eyes.glasses_blue", slot: .eyes, name: "파란 뿔테", price: 650, isIAP: false, defaultOwned: false),

        // 목
        .init(id: "neck.ribbon", slot: .neck, name: "리본", price: 500, isIAP: false, defaultOwned: false),
        .init(id: "neck.bowtie", slot: .neck, name: "나비넥타이", price: 600, isIAP: false, defaultOwned: false),
        .init(id: "neck.gold_chain", slot: .neck, name: "골드 체인", price: 1400, isIAP: false, defaultOwned: false),
        .init(id: "neck.scarf_mint", slot: .neck, name: "민트 목도리", price: 550, isIAP: false, defaultOwned: false),
        .init(id: "neck.pearl", slot: .neck, name: "진주 목걸이", price: 1200, isIAP: false, defaultOwned: false),
        .init(id: "neck.bandana", slot: .neck, name: "반다나", price: 500, isIAP: false, defaultOwned: false),
        .init(id: "neck.bell", slot: .neck, name: "방울", price: 450, isIAP: false, defaultOwned: false),
        .init(id: "neck.tie", slot: .neck, name: "넥타이", price: 650, isIAP: false, defaultOwned: false),
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
