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

@Test func touchingAnEmptyRoomAlternatesGroundedGreetingAndHappyWings() {
    let current = PiyakRoomPoint(x: -0.45, z: PiyakActivityPlan.frontAisle)
    let reactions = (0..<6).map {
        PiyakActivityPlan.reaction(equipped: [:], working: false, sequence: UInt64($0), at: current)
    }
    #expect(reactions.map(\.activity) == [.greet, .celebrate, .greet, .celebrate, .greet, .celebrate])
    #expect(reactions.allSatisfy { $0.point == current && $0.duration > 0 })
    #expect(reactions.allSatisfy { PiyakActivityPlan.route(from: current, to: $0.point).isEmpty })
    #expect(!reactions.contains { [.water, .rest, .piano, .read].contains($0.activity) })
}

@Test func touchesCycleOnlyThroughEquippedObjectInteractions() {
    let equipment = ["floorProp": "floorProp.plant", "bigFurniture": "bigFurniture.piano"]
    let reactions = (0..<8).map {
        PiyakActivityPlan.reaction(equipped: equipment, working: false,
                                  sequence: UInt64($0), at: PiyakActivityPlan.home)
    }
    #expect(reactions.map(\.activity) == [.greet, .celebrate, .water, .piano, .greet, .celebrate, .water, .piano])
    let automatic = PiyakActivityPlan.itinerary(equipped: equipment, working: false)
    for reaction in reactions where [.water, .piano].contains(reaction.activity) {
        let original = automatic.first { $0.activity == reaction.activity }
        #expect(reaction.point == original?.point)
        #expect(reaction.facing == original?.facing)
        #expect(reaction.duration <= 6)
    }
}

@Test func touchingAOneObjectRoomDoesNotReserveAnEmptyFurnitureTurn() {
    let equipment = ["floorProp": "floorProp.puppy"]
    let reactions = (0..<6).map {
        PiyakActivityPlan.reaction(equipped: equipment, working: false,
                                  sequence: UInt64($0), at: PiyakActivityPlan.home).activity
    }
    #expect(reactions == [.greet, .celebrate, .pet, .greet, .celebrate, .pet])
    let farFuture = PiyakActivityPlan.reaction(equipped: equipment, working: false,
                                              sequence: .max, at: PiyakActivityPlan.home)
    #expect([PiyakActivity.greet, .celebrate, .pet].contains(farFuture.activity))
}

@Test func touchUsesTheCurrentWorkModeAndKeepsSofaEntryAndExitTime() {
    let desk = ["bigFurniture": "bigFurniture.desk"]
    #expect(PiyakActivityPlan.reaction(equipped: desk, working: true, sequence: 2,
                                      at: PiyakActivityPlan.home).activity == .work)
    #expect(PiyakActivityPlan.reaction(equipped: desk, working: false, sequence: 2,
                                      at: PiyakActivityPlan.home).activity == .read)
    let sofa = PiyakActivityPlan.reaction(equipped: ["bigFurniture": "bigFurniture.sofa"],
                                         working: false, sequence: 2, at: PiyakActivityPlan.home)
    #expect(sofa.activity == .rest)
    #expect(sofa.duration > 2 * 1.25) // The existing seat transition needs 1.25s in each direction.
}

@Test func touchObjectTravelKeepsTheSameSafeFrontAisle() {
    let equipment = ["floorProp": "floorProp.puppy", "bigFurniture": "bigFurniture.sofa"]
    var current = PiyakRoomPoint(x: 0.83, z: 0.73)
    for sequence in 0..<8 {
        let selected = PiyakActivityPlan.reaction(equipped: equipment, working: false,
                                                 sequence: UInt64(sequence), at: current)
        var previous = current
        for next in PiyakActivityPlan.route(from: current, to: selected.point) {
            if abs(next.x - previous.x) > 0.025 {
                #expect(previous.z == PiyakActivityPlan.frontAisle)
                #expect(next.z == PiyakActivityPlan.frontAisle)
            }
            previous = next
        }
        #expect(previous == selected.point)
        current = selected.point
    }
}
