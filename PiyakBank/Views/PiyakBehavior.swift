import Foundation
import SceneKit
#if canImport(UIKit)
import UIKit
private typealias RoomColor = UIColor
#else
import AppKit
private typealias RoomColor = NSColor
#endif

/// A small, bounded choreography: grounded footsteps, a clear walking aisle and equipped-object visits.
/// SceneKit owns the clock; no per-frame SwiftUI state or background timer keeps an offscreen room alive.
final class PiyakBehavior {
    private struct RestPose {
        let node: SCNNode
        let position: SCNVector3
        let rotation: SCNVector3
        let scale: SCNVector3
        init(_ node: SCNNode) { self.node = node; position = node.position; rotation = node.eulerAngles; scale = node.scale }
        func restore() { node.position = position; node.eulerAngles = rotation; node.scale = scale }
    }

    private let scene: SCNScene
    private let chick: SCNNode
    private let equipped: [String: String]
    private let rig: [String: SCNNode]
    private let rest: [RestPose]
    private let movingProps: [RestPose]
    private let book: SCNNode
    private let wateringCan: SCNNode
    private let drops: [SCNNode]
    private let notes: [SCNNode]
    // SwiftUI configures from the main thread while SceneKit samples actions on
    // its render thread. Pose changes and action generations must be serialized.
    private let stateLock = NSRecursiveLock()
    private var working: Bool?
    private var generation: UInt64 = 0
    private var activeVisit: PiyakRoomVisit?
    private var dismountDestination: PiyakRoomPoint?
    private var reactionSequence: UInt64 = 0
    private var reactionActivity: PiyakActivity?
    private var isReacting = false
    private var activity = ""
    private let announce: (String) -> Void

    init?(scene: SCNScene, equipped: [String: String], announce: @escaping (String) -> Void) {
        guard let chick = scene.rootNode.childNode(withName: "piyak", recursively: false) else { return nil }
        self.scene = scene; self.chick = chick; self.equipped = equipped; self.announce = announce
        let names = ["bodyRig", "headRig", "eyes", "wing.left", "wing.right", "foot.left", "foot.right"]
        rig = Dictionary(uniqueKeysWithValues: names.compactMap { name in
            chick.childNode(withName: name, recursively: true).map { (name, $0) }
        })
        rest = rig.values.map(RestPose.init)
        var props: [RestPose] = []
        scene.rootNode.enumerateChildNodes { node, _ in
            if let name = node.name,
               ["plant.leaf", "puppy.tail", "piano.key", "balloon."].contains(where: name.hasPrefix) {
                props.append(RestPose(node))
            }
        }
        movingProps = props
        book = Self.makeBook(); book.isHidden = true; chick.addChildNode(book)
        wateringCan = Self.makeWateringCan(); wateringCan.isHidden = true; chick.addChildNode(wateringCan)
        drops = (0..<6).map { _ in
            let drop = Self.sphere(0.025, 0x8CD7EB)
            drop.scale = SCNVector3(0.8, 1.4, 0.8); drop.isHidden = true; chick.addChildNode(drop)
            return drop
        }
        notes = (0..<3).map { i in
            let text = SCNText(string: i.isMultiple(of: 2) ? "♪" : "♫", extrusionDepth: 0.015)
            text.font = .systemFont(ofSize: 1, weight: .semibold); text.flatness = 0.15
            let node = Self.node(text, 0xB696DA); node.scale = SCNVector3(0.18, 0.18, 0.18)
            node.isHidden = true; scene.rootNode.addChildNode(node); return node
        }
    }

    var currentActivity: String {
        stateLock.lock(); defer { stateLock.unlock() }
        return activity
    }

    func configure(working: Bool) {
        stateLock.lock(); defer { stateLock.unlock() }
        guard self.working != working else { return }
        self.working = working
        isReacting = false
        reactionActivity = nil
        generation &+= 1
        let token = generation
        scene.rootNode.removeAction(forKey: "piyak.life")
        neutral()
        // A mode switch may arrive midway through sitting, including a previous
        // interrupted dismount. Preserve its floor waypoint until fully off the
        // sofa; never project a seated position straight down through the cushion.
        let floorPoint = dismountDestination ?? (activeVisit?.activity == .rest ? activeVisit?.point : nil)
        activeVisit = nil
        var actions: [SCNAction] = []
        var routeStart = point
        if let floorPoint, abs(chick.position.y) > 0.001 || point.distance(to: floorPoint) > 0.025 {
            dismountDestination = floorPoint
            actions += dismount(to: floorPoint, token: token)
            routeStart = floorPoint
        } else {
            dismountDestination = nil
        }
        // First reach the standard starting point from the current pose, including after a mode change.
        actions += routine(from: routeStart, working: working, token: token)
        scene.rootNode.runAction(.sequence(actions), forKey: "piyak.life")
    }

    /// Accept only one touch choreography at a time. The same SceneKit action
    /// owns its acknowledgement, safe travel, interaction, cooldown and return
    /// to the routine; no extra timer or independently running action is added.
    @discardableResult
    func react() -> Bool {
        stateLock.lock(); defer { stateLock.unlock() }
        guard let working, !isReacting, !scene.isPaused, !scene.rootNode.isPaused,
              scene.rootNode.action(forKey: "piyak.life") != nil else { return false }
        let floorPoint = dismountDestination ?? (activeVisit?.activity == .rest ? activeVisit?.point : nil)
        generation &+= 1
        let token = generation
        scene.rootNode.removeAction(forKey: "piyak.life")
        neutral()
        activeVisit = nil
        isReacting = true
        var actions: [SCNAction] = []
        var routeStart = point
        if let floorPoint, abs(chick.position.y) > 0.001 || point.distance(to: floorPoint) > 0.025 {
            dismountDestination = floorPoint
            actions += dismount(to: floorPoint, token: token)
            routeStart = floorPoint
        } else {
            dismountDestination = nil
        }
        let selected = PiyakActivityPlan.reaction(equipped: equipped, working: working,
                                                  sequence: reactionSequence, at: routeStart)
        reactionSequence &+= 1
        reactionActivity = selected.activity
        if selected.activity != .greet && selected.activity != .celebrate {
            // Acknowledge immediately where the chick is standing before the
            // longer walk to an object. Never teleport across room furniture.
            let hello = PiyakRoomVisit(activity: .greet, point: routeStart,
                                       facing: .init(x: 2, z: 6), duration: 1.4)
            actions += visit(hello, token: token)
        }
        actions += travel(from: routeStart, to: selected.point, working: working, token: token)
        actions += visit(selected, token: token)
        // This scene-clock cooldown pauses with the view. Rapid taps cannot
        // queue another reaction while a pose or the final settling is active.
        actions.append(.wait(duration: 0.6))
        actions.append(event(token: token) { behavior in
            behavior.isReacting = false
            behavior.reactionActivity = nil
        })
        actions += routine(from: selected.point, working: working, token: token)
        scene.rootNode.runAction(.sequence(actions), forKey: "piyak.life")
        return true
    }

    func stop() {
        stateLock.lock(); defer { stateLock.unlock() }
        generation &+= 1
        scene.rootNode.removeAction(forKey: "piyak.life")
        working = nil
        isReacting = false; reactionActivity = nil
        activeVisit = nil; dismountDestination = nil; activity = ""
        neutral()
        chick.position = SCNVector3(SCNFloat(PiyakActivityPlan.home.x), 0, SCNFloat(PiyakActivityPlan.home.z))
        chick.eulerAngles.y = 0.18
    }

    private var point: PiyakRoomPoint { .init(x: Double(chick.position.x), z: Double(chick.position.z)) }

    private func routine(from start: PiyakRoomPoint, working: Bool, token: UInt64) -> [SCNAction] {
        var actions = travel(from: start, to: PiyakActivityPlan.home, working: working, token: token)
        var cursor = PiyakActivityPlan.home
        var loop: [SCNAction] = []
        for destination in PiyakActivityPlan.itinerary(equipped: equipped, working: working) {
            loop += travel(from: cursor, to: destination.point, working: working, token: token)
            loop += visit(destination, token: token)
            cursor = destination.point
        }
        loop += travel(from: cursor, to: PiyakActivityPlan.home, working: working, token: token)
        actions.append(.repeatForever(.sequence(loop)))
        return actions
    }

    private func visit(_ destination: PiyakRoomVisit, token: UInt64) -> [SCNAction] {
        [turn(toward: heading(from: destination.point, to: destination.facing), token: token),
         event(token: token) { $0.activeVisit = destination },
         announcement(destination.activity.title, token: token),
         pose(duration: destination.duration, token: token) { behavior, elapsed in
             behavior.perform(destination, elapsed: elapsed)
         },
         event(token: token) { behavior in
             behavior.neutral()
             // Keep the endpoint exact even if the renderer skips the final
             // pose sample. A sofa visit already descends to this floor point.
             behavior.chick.position = SCNVector3(SCNFloat(destination.point.x), 0, SCNFloat(destination.point.z))
             behavior.activeVisit = nil
         }]
    }

    private func travel(from: PiyakRoomPoint, to: PiyakRoomPoint, working: Bool, token: UInt64) -> [SCNAction] {
        var current = from
        var actions: [SCNAction] = []
        for destination in PiyakActivityPlan.route(from: from, to: to) {
            let start = current
            let duration = max(0.55, start.distance(to: destination) / (working ? 0.42 : 0.36))
            actions.append(turn(toward: heading(from: start, to: destination), token: token))
            actions.append(announcement("우리 방을 산책하는 중", token: token))
            actions.append(pose(duration: duration, token: token) { behavior, t in
                let progress = min(1, t / duration)
                behavior.neutral()
                behavior.chick.position = SCNVector3(SCNFloat(start.x + (destination.x - start.x) * progress), 0,
                                               SCNFloat(start.z + (destination.z - start.z) * progress))
                let envelope = min(Self.smooth(t / 0.18), Self.smooth((duration - t) / 0.18))
                let gait = sin(t * .pi * 2 / 0.56) * envelope
                // The root stays on the floor; alternate feet lift while the planted foot bears weight.
                behavior.rig["foot.left"]?.position.y += SCNFloat(max(0, gait) * 0.12)
                behavior.rig["foot.right"]?.position.y += SCNFloat(max(0, -gait) * 0.12)
                behavior.rig["foot.left"]?.eulerAngles.x = SCNFloat(max(0, gait) * 0.25)
                behavior.rig["foot.right"]?.eulerAngles.x = SCNFloat(max(0, -gait) * 0.25)
                behavior.rig["bodyRig"]?.eulerAngles.z = SCNFloat(gait * 0.065)
                behavior.rig["headRig"]?.eulerAngles.z = SCNFloat(-gait * 0.035)
                behavior.rig["wing.left"]?.eulerAngles.x = SCNFloat(gait * 0.32)
                behavior.rig["wing.right"]?.eulerAngles.x = SCNFloat(-gait * 0.32)
                behavior.blink(t)
            })
            actions.append(event(token: token) { behavior in
                behavior.neutral()
                behavior.chick.position = SCNVector3(SCNFloat(destination.x), 0, SCNFloat(destination.z))
            })
            current = destination
        }
        return actions
    }

    private func turn(toward target: Double, token: UInt64) -> SCNAction {
        // Read the starting heading at execution time, not while the itinerary is assembled.
        var start = 0.0
        return .sequence([
            event(token: token) { behavior in
                behavior.neutral()
                start = Double(behavior.chick.eulerAngles.y)
            },
            pose(duration: 0.42, token: token) { behavior, time in
                behavior.chick.eulerAngles.y = SCNFloat(start + Self.angleDifference(start, target) * Self.smooth(time / 0.42))
            },
            event(token: token) { $0.chick.eulerAngles.y = SCNFloat(target) }
        ])
    }

    private func dismount(to destination: PiyakRoomPoint, token: UInt64) -> [SCNAction] {
        let start = chick.position
        let startAngle = Double(chick.eulerAngles.y)
        let exitAngle = heading(from: point, to: destination)
        let duration = 0.9
        return [
            announcement("자리에서 사뿐히 내려오는 중", token: token),
            pose(duration: duration, token: token) { behavior, time in
                let p = Self.smooth(time / duration)
                behavior.neutral()
                behavior.chick.position = SCNVector3(
                    start.x + (SCNFloat(destination.x) - start.x) * SCNFloat(p),
                    start.y * SCNFloat(1 - p) + SCNFloat(sin(p * .pi) * 0.12),
                    start.z + (SCNFloat(destination.z) - start.z) * SCNFloat(p))
                behavior.chick.eulerAngles.y = SCNFloat(startAngle + Self.angleDifference(startAngle, exitAngle) * p)
            },
            event(token: token) { behavior in
                behavior.neutral()
                behavior.chick.position = SCNVector3(SCNFloat(destination.x), 0, SCNFloat(destination.z))
                behavior.dismountDestination = nil
            }
        ]
    }

    private func withState(_ token: UInt64, _ body: (PiyakBehavior) -> Void) {
        stateLock.lock(); defer { stateLock.unlock() }
        guard generation == token else { return }
        body(self)
    }

    private func event(token: UInt64, _ body: @escaping (PiyakBehavior) -> Void) -> SCNAction {
        .run { [weak self] _ in self?.withState(token, body) }
    }

    private func pose(duration: TimeInterval, token: UInt64,
                      _ body: @escaping (PiyakBehavior, Double) -> Void) -> SCNAction {
        .customAction(duration: duration) { [weak self] _, time in
            self?.withState(token) { body($0, Double(time)) }
        }
    }

    private func announcement(_ label: String, token: UInt64) -> SCNAction {
        .run { [weak self] _ in
            guard let self else { return }
            self.stateLock.lock()
            let shouldAnnounce = self.generation == token && self.activity != label
            if shouldAnnounce { self.activity = label }
            self.stateLock.unlock()
            // The UI delivery closure must hop to main itself. Never wait for
            // the main actor while holding the render-thread state lock.
            if shouldAnnounce { self.announce(label) }
        }
    }

    #if DEBUG
    struct DebugSnapshot: Codable {
        let generation: UInt64
        let working: Bool?
        let activity: String
        let visit: String?
        let dismounting: Bool
        let position: [Double]
        let heading: Double
        let leftFootHeight: Double
        let rightFootHeight: Double
        let bookVisible: Bool
        let wateringCanVisible: Bool
        let reacting: Bool
        let reaction: String?
    }

    /// Compile a renderer probe with -DDEBUG, advance that renderer's scene
    /// time, then sample here. No timer or debug animation path affects the app.
    func debugSnapshot() -> DebugSnapshot {
        stateLock.lock(); defer { stateLock.unlock() }
        return DebugSnapshot(generation: generation, working: working, activity: activity,
            visit: activeVisit?.activity.rawValue, dismounting: dismountDestination != nil,
            position: [Double(chick.position.x), Double(chick.position.y), Double(chick.position.z)],
            heading: Double(chick.eulerAngles.y), leftFootHeight: Double(rig["foot.left"]?.position.y ?? 0),
            rightFootHeight: Double(rig["foot.right"]?.position.y ?? 0), bookVisible: !book.isHidden,
            wateringCanVisible: !wateringCan.isHidden, reacting: isReacting,
            reaction: reactionActivity?.rawValue)
    }
    #endif

    private func neutral() {
        rest.forEach { $0.restore() }; movingProps.forEach { $0.restore() }
        book.isHidden = true; wateringCan.isHidden = true
        drops.forEach { $0.isHidden = true }; notes.forEach { $0.isHidden = true }
    }

    private func perform(_ visit: PiyakRoomVisit, elapsed t: Double) {
        neutral()
        let envelope = min(Self.smooth(t / 0.6), Self.smooth((visit.duration - t) / 0.6))
        let sway = sin(t * 2.2) * envelope
        rig["headRig"]?.eulerAngles.y = SCNFloat(sway * 0.045)
        blink(t)
        switch visit.activity {
        case .greet:
            rig["wing.right"]?.eulerAngles.z += SCNFloat((1.6 + sin(t * 7) * 0.25) * envelope)
            rig["headRig"]?.eulerAngles.z = SCNFloat(-0.12 * envelope)
        case .celebrate:
            // The root and feet remain planted; express joy through the rig
            // rather than bringing back the old floating/bobbing animation.
            let flutter = sin(t * 13) * 0.28
            rig["wing.right"]?.eulerAngles.z += SCNFloat((1.4 + flutter) * envelope)
            rig["wing.left"]?.eulerAngles.z -= SCNFloat((1.4 + flutter) * envelope)
            rig["headRig"]?.eulerAngles.z = SCNFloat(sin(t * 5) * 0.13 * envelope)
            rig["headRig"]?.eulerAngles.x = SCNFloat(-0.07 * envelope)
            rig["bodyRig"]?.eulerAngles.z = SCNFloat(sin(t * 5) * 0.035 * envelope)
        case .lookAround:
            rig["headRig"]?.eulerAngles.y = SCNFloat(sin(t * 1.35) * 0.32 * envelope)
        case .stretch:
            rig["wing.right"]?.eulerAngles.z += SCNFloat(1.9 * envelope)
            rig["wing.left"]?.eulerAngles.z -= SCNFloat(1.9 * envelope)
            rig["headRig"]?.eulerAngles.x = SCNFloat(-0.14 * envelope)
            rig["bodyRig"]?.scale.y *= SCNFloat(1 + 0.025 * envelope)
        case .water:
            wateringCan.isHidden = envelope < 0.05
            wateringCan.eulerAngles.x = SCNFloat(0.18 + 0.12 * envelope)
            rig["wing.right"]?.eulerAngles.x = SCNFloat(-1.2 * envelope)
            rig["wing.right"]?.eulerAngles.z -= SCNFloat(0.4 * envelope)
            rig["headRig"]?.eulerAngles.x = SCNFloat(0.1 * envelope)
            for (i, drop) in drops.enumerated() {
                let phase = (t * 1.5 + Double(i) / Double(drops.count)).truncatingRemainder(dividingBy: 1)
                drop.isHidden = envelope < 0.5
                drop.position = SCNVector3(0.3, SCNFloat(0.92 - phase * 0.48), SCNFloat(1.04 + phase * 0.07))
                drop.opacity = CGFloat((1 - phase) * 0.85)
            }
            animateProps(prefix: "plant.leaf", angle: sway * 0.06)
        case .read:
            book.isHidden = envelope < 0.05
            book.eulerAngles.x = SCNFloat(-0.38 + sin(t * 0.85) * 0.025)
            rig["wing.left"]?.eulerAngles.x = SCNFloat(-1.1 * envelope)
            rig["wing.right"]?.eulerAngles.x = SCNFloat(-1.1 * envelope)
            rig["headRig"]?.eulerAngles.x = SCNFloat((0.15 + sin(t * 1.3) * 0.04) * envelope)
            if let page = book.childNode(withName: "book.page", recursively: false) {
                page.eulerAngles.z = SCNFloat(-0.12 + sin(max(0, t - 2) * 0.85) * 0.20)
            }
        case .work, .piano:
            rig["wing.left"]?.eulerAngles.x = SCNFloat((-1.2 + sin(t * 7) * 0.17) * envelope)
            rig["wing.right"]?.eulerAngles.x = SCNFloat((-1.2 + cos(t * 7) * 0.17) * envelope)
            rig["headRig"]?.eulerAngles.x = SCNFloat((0.12 + sin(t * 3) * 0.035) * envelope)
            if visit.activity == .piano {
                for (i, pose) in movingProps.enumerated() where pose.node.name?.hasPrefix("piano.key") == true {
                    pose.node.position.y -= SCNFloat(max(0, sin(t * 7 + Double(i))) * 0.018 * envelope)
                }
                for (i, note) in notes.enumerated() {
                    let p = (t * 0.4 + Double(i) / 3).truncatingRemainder(dividingBy: 1)
                    note.isHidden = envelope < 0.2
                    note.position = SCNVector3(SCNFloat(-1.8 + Double(i) * 0.32), SCNFloat(1.4 + p * 0.55), -0.7)
                    note.opacity = CGFloat(sin(p * .pi) * envelope)
                }
            }
        case .rest:
            if let seat = scene.rootNode.childNode(withName: "interaction.seat", recursively: true) {
                let destination = seat.convertPosition(SCNVector3Zero, to: scene.rootNode)
                let enter = Self.smooth(t / 1.25), leave = Self.smooth((visit.duration - t) / 1.25)
                let p = min(enter, leave)
                chick.position = SCNVector3(SCNFloat(visit.point.x) + (destination.x - SCNFloat(visit.point.x)) * SCNFloat(p),
                                           destination.y * SCNFloat(p) + SCNFloat(sin(p * .pi) * 0.1),
                                           SCNFloat(visit.point.z) + (destination.z - SCNFloat(visit.point.z)) * SCNFloat(p))
                let startAngle = heading(from: visit.point, to: visit.facing)
                chick.eulerAngles.y = SCNFloat(startAngle + Self.angleDifference(startAngle, 0.18) * p)
                rig["foot.left"]?.eulerAngles.x = SCNFloat(-0.7 * p)
                rig["foot.right"]?.eulerAngles.x = SCNFloat(-0.7 * p)
                rig["foot.left"]?.position.z += SCNFloat(0.14 * p)
                rig["foot.right"]?.position.z += SCNFloat(0.14 * p)
                rig["bodyRig"]?.scale.y *= SCNFloat(1 - 0.15 * p)
                rig["bodyRig"]?.position.y -= SCNFloat(0.06 * p)
                rig["headRig"]?.position.y -= SCNFloat(0.15 * p)
                rig["headRig"]?.eulerAngles.z = SCNFloat(sin(t * 0.85) * 0.08 * envelope)
                if t > 2, t < visit.duration - 1.5 { rig["eyes"]?.scale.y *= 0.15 }
            }
        case .pet:
            rig["wing.right"]?.eulerAngles.x = SCNFloat((-0.85 + sin(t * 4) * 0.14) * envelope)
            rig["headRig"]?.eulerAngles.x = SCNFloat(0.16 * envelope)
            animateProps(prefix: "puppy.tail", angle: sin(t * 10) * 0.5 * envelope)
        case .play:
            rig["wing.right"]?.eulerAngles.x = SCNFloat((-0.75 + sin(t * 3) * 0.28) * envelope)
            rig["headRig"]?.eulerAngles.z = SCNFloat(sway * 0.1)
            animateProps(prefix: "balloon.", angle: sin(t * 2) * 0.08 * envelope)
        case .tidy:
            rig["wing.left"]?.eulerAngles.x = SCNFloat((-0.9 + sin(t * 3.5) * 0.16) * envelope)
            rig["wing.right"]?.eulerAngles.x = SCNFloat((-0.9 - sin(t * 3.5) * 0.16) * envelope)
            rig["headRig"]?.eulerAngles.x = SCNFloat(0.16 * envelope)
        case .watch, .inspect:
            rig["headRig"]?.eulerAngles.z = SCNFloat(sway * 0.16)
            rig["headRig"]?.eulerAngles.x = SCNFloat(-0.05 * envelope)
            rig["wing.right"]?.eulerAngles.z += SCNFloat(max(0, sway) * 0.3)
        }
    }

    private func animateProps(prefix: String, angle: Double) {
        for (i, pose) in movingProps.enumerated() where pose.node.name?.hasPrefix(prefix) == true {
            pose.node.eulerAngles.z += SCNFloat(angle * (i.isMultiple(of: 2) ? 1 : -0.8))
        }
    }
    private func blink(_ time: Double) {
        let phase = (time + 2.4).truncatingRemainder(dividingBy: 4.8)
        let closed = max(0, 1 - abs(phase - 2.7) / 0.11)
        rig["eyes"]?.scale.y *= SCNFloat(1 - 0.94 * closed)
    }
    private func heading(from: PiyakRoomPoint, to: PiyakRoomPoint) -> Double { atan2(to.x - from.x, to.z - from.z) }
    private static func smooth(_ x: Double) -> Double { let v = min(1, max(0, x)); return v * v * (3 - 2 * v) }
    private static func angleDifference(_ from: Double, _ to: Double) -> Double { atan2(sin(to - from), cos(to - from)) }

    private static func makeBook() -> SCNNode {
        let root = SCNNode(); root.position = SCNVector3(0, 0.96, 0.68)
        for side: SCNFloat in [-1, 1] {
            let half = SCNNode(); half.position.x = side * 0.16; half.eulerAngles.z = side * 0.14
            let cover = box(0.34, 0.035, 0.4, 0x718BBB); half.addChildNode(cover)
            let pages = box(0.30, 0.055, 0.35, 0xFFF6DD); pages.position.y = 0.038; half.addChildNode(pages)
            for line in 0..<4 {
                let ink = box(0.22, 0.002, 0.008, 0xB0A699)
                ink.position = SCNVector3(0, 0.067, SCNFloat(line) * 0.052 - 0.075); half.addChildNode(ink)
            }
            if side > 0 { half.name = "book.page" }
            root.addChildNode(half)
        }
        return root
    }
    private static func makeWateringCan() -> SCNNode {
        let root = SCNNode(); root.position = SCNVector3(0.3, 1.02, 0.66)
        let body = node(SCNCylinder(radius: 0.17, height: 0.25), 0x8BBAC7); root.addChildNode(body)
        let rim = node(SCNTorus(ringRadius: 0.15, pipeRadius: 0.022), 0xD6ECED); rim.position.y = 0.125; root.addChildNode(rim)
        let handle = node(SCNTorus(ringRadius: 0.17, pipeRadius: 0.026), 0x8BBAC7)
        handle.eulerAngles.x = .pi / 2; handle.position.z = -0.18; root.addChildNode(handle)
        let spout = node(SCNCone(topRadius: 0.04, bottomRadius: 0.055, height: 0.32), 0x8BBAC7)
        spout.eulerAngles.x = .pi / 2; spout.position = SCNVector3(0, 0.025, 0.24); root.addChildNode(spout)
        let tip = sphere(0.065, 0xD6ECED); tip.scale.z = 0.45; tip.position = SCNVector3(0, 0.025, 0.4); root.addChildNode(tip)
        return root
    }
    private static func box(_ x: CGFloat, _ y: CGFloat, _ z: CGFloat, _ tint: UInt) -> SCNNode {
        node(SCNBox(width: x, height: y, length: z, chamferRadius: min(x, y, z) * 0.3), tint)
    }
    private static func sphere(_ radius: CGFloat, _ tint: UInt) -> SCNNode {
        let geometry = SCNSphere(radius: radius); geometry.segmentCount = 16; return node(geometry, tint)
    }
    private static func node(_ geometry: SCNGeometry, _ tint: UInt) -> SCNNode {
        let material = SCNMaterial()
        material.diffuse.contents = RoomColor(red: CGFloat((tint >> 16) & 255) / 255,
            green: CGFloat((tint >> 8) & 255) / 255, blue: CGFloat(tint & 255) / 255, alpha: 1)
        material.lightingModel = .physicallyBased; material.roughness.contents = 0.75
        geometry.materials = [material]; return SCNNode(geometry: geometry)
    }
}
