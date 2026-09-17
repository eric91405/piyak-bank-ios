import Testing
@testable import PiyakCore

@Test func activitiesUseOnlyEquippedFurniture() {
    let empty = PiyakActivityPlan.itinerary(equipped: [:], working: false)
    #expect(!empty.contains { [.water, .piano, .rest, .read].contains($0.activity) })
    let room = PiyakActivityPlan.itinerary(equipped: ["floorProp": "floorProp.plant", "bigFurniture": "bigFurniture.piano"], working: false)
    #expect(room.contains { $0.activity == .water })
    #expect(room.contains { $0.activity == .piano })
    #expect(!room.contains { $0.activity == .rest })
    #expect(PiyakActivityPlan.itinerary(equipped: ["bigFurniture": "bigFurniture.bookshelf"], working: false).contains { $0.activity == .read })
}

@Test func routesStayOnClearFrontAisle() {
    let visits = PiyakActivityPlan.itinerary(equipped: ["floorProp": "floorProp.puppy", "bigFurniture": "bigFurniture.sofa"], working: false)
    var start = PiyakActivityPlan.home
    for visit in visits + visits {
        let route = PiyakActivityPlan.route(from: start, to: visit.point)
        var prior = start
        for point in route {
            #expect((-1.4...1.0).contains(point.x))
            #expect((0.1...1.2).contains(point.z))
            if abs(point.x - prior.x) > 0.001 {
                #expect(point.z == PiyakActivityPlan.frontAisle)
                #expect(prior.z == PiyakActivityPlan.frontAisle)
            }
            prior = point
        }
        #expect(prior == visit.point)
        start = visit.point
    }
}

@Test func workingChangesDeskActivityWithoutInventingFurniture() {
    let equipment = ["bigFurniture": "bigFurniture.desk", "floorProp": "floorProp.plant"]
    let working = PiyakActivityPlan.itinerary(equipped: equipment, working: true)
    let resting = PiyakActivityPlan.itinerary(equipped: equipment, working: false)
    #expect(working[1].activity == .work)
    #expect(resting.contains { $0.activity == .read })
    #expect(!resting.contains { $0.activity == .work })
    #expect(PiyakActivityPlan.route(from: .init(x: 0, z: 0.5), to: .init(x: 0, z: 0.5)).isEmpty)
}
