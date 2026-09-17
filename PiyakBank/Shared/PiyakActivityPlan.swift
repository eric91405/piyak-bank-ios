import Foundation

/// The little room has a clear front aisle. Every walk uses it rather than crossing furniture.
struct PiyakRoomPoint: Equatable, Sendable {
    var x: Double
    var z: Double
    func distance(to other: Self) -> Double { hypot(other.x - x, other.z - z) }
}

enum PiyakActivity: String, Sendable {
    case greet, lookAround, stretch, water, read, work, piano, rest, watch, pet, play, inspect, tidy

    var title: String {
        switch self {
        case .greet: "반가워! 오늘도 함께해"
        case .lookAround: "우리 방을 산책하는 중"
        case .stretch: "쭉쭉, 기지개 켜는 중"
        case .water: "초록 친구에게 물 주는 중"
        case .read: "좋아하는 책을 읽는 중"
        case .work: "책상에서 꼼지락꼼지락"
        case .piano: "작은 연주회를 여는 중"
        case .rest: "소파에서 잠깐 쉬는 중"
        case .watch: "재미있는 장면을 구경하는 중"
        case .pet: "강아지 친구를 쓰다듬는 중"
        case .play: "장난감을 가지고 노는 중"
        case .inspect: "새로운 소품을 살펴보는 중"
        case .tidy: "내 물건을 가지런히 정리하는 중"
        }
    }
}

struct PiyakRoomVisit: Equatable, Sendable {
    var activity: PiyakActivity
    var point: PiyakRoomPoint
    var facing: PiyakRoomPoint
    var duration: TimeInterval
}

enum PiyakActivityPlan {
    static let home = PiyakRoomPoint(x: 0.15, z: 0.45)
    static let frontAisle = 1.12

    static func itinerary(equipped: [String: String], working: Bool) -> [PiyakRoomVisit] {
        var visits = [visit(.greet, home, facing: .init(x: 2, z: 6), seconds: 4)]
        let prop = equipped["floorProp"].map { id -> PiyakRoomVisit in
            let activity: PiyakActivity
            switch id {
            case "floorProp.plant", "floorProp.cactus": activity = .water
            case "floorProp.books": activity = .read
            case "floorProp.puppy": activity = .pet
            case "floorProp.balloons", "floorProp.toybox": activity = .play
            case "floorProp.coin_pile": activity = .tidy
            default: activity = .inspect
            }
            return visit(activity, .init(x: 0.83, z: 0.73), facing: .init(x: 1.65, z: 0.5), seconds: 7)
        }
        let furniture = equipped["bigFurniture"].map { id -> PiyakRoomVisit in
            let activity: PiyakActivity
            switch id {
            case "bigFurniture.sofa": activity = .rest
            case "bigFurniture.piano": activity = .piano
            case "bigFurniture.desk": activity = working ? .work : .read
            case "bigFurniture.bookshelf", "bigFurniture.shelf": activity = .read
            case "bigFurniture.tv": activity = .watch
            default: activity = .tidy
            }
            return visit(activity, .init(x: -1.28, z: 0.16), facing: .init(x: -1.45, z: -0.9), seconds: 9)
        }
        // While working, spend the first longer visit at the desk; otherwise greet the pet/plant first.
        if working, let furniture { visits.append(furniture) }
        if let prop { visits.append(prop) }
        visits.append(visit(.lookAround, .init(x: -0.45, z: 1.12), facing: .init(x: -2, z: 2), seconds: 3))
        if !working, let furniture { visits.append(furniture) }
        visits.append(visit(.stretch, .init(x: 0.05, z: 0.66), facing: .init(x: 2, z: 6), seconds: 5))
        visits.append(visit(.lookAround, .init(x: 0.58, z: 1.12), facing: .init(x: 2, z: -1), seconds: 3))
        return visits
    }

    static func route(from start: PiyakRoomPoint, to end: PiyakRoomPoint) -> [PiyakRoomPoint] {
        guard start.distance(to: end) > 0.025 else { return [] }
        if abs(start.x - end.x) < 0.025 { return [end] }
        // Travel sideways only in front of both furniture and the floor prop.
        let candidates = [PiyakRoomPoint(x: start.x, z: frontAisle),
                          PiyakRoomPoint(x: end.x, z: frontAisle), end]
        var cursor = start
        return candidates.filter { point in
            guard cursor.distance(to: point) > 0.025 else { return false }
            cursor = point
            return true
        }
    }

    private static func visit(_ activity: PiyakActivity, _ point: PiyakRoomPoint,
                              facing: PiyakRoomPoint, seconds: TimeInterval) -> PiyakRoomVisit {
        .init(activity: activity, point: point, facing: facing, duration: seconds)
    }
}
