import Foundation
import AppKit
import SceneKit
import Darwin

/// Deterministic, bounded behavior QA. Run after the asset/static-scene checks,
/// with simulators and other GPU work stopped. No wall-clock sleeps or timers.
///
/// xcrun swiftc -DDEBUG PiyakBank/Views/PiyakScene.swift \
///   PiyakBank/Shared/PiyakActivityPlan.swift PiyakBank/Views/PiyakBehavior.swift \
///   scripts/ProbeRoomBehavior.swift -o /tmp/piyak-behavior-probe
/// /tmp/piyak-behavior-probe /tmp/piyak-behavior-evidence
///
/// SCNRenderer.update(atTime:) advances actions in 0.1 simulated-second steps.
/// One 64×64 warm-up initializes the renderer, then only evidence frames render
/// through Metal (at most eight GPU snapshots total, evidence at 640×480).
/// Exit 2 means the headless action clock did not advance or the time budget
/// expired; it is not a claim that device behavior is broken.
@main
struct ProbeRoomBehavior {
    struct Finding: Codable {
        let room: String
        let detail: String
    }
    struct Sample: Codable {
        let time: Double
        let state: PiyakBehavior.DebugSnapshot
    }
    struct Frame: Codable {
        let file: String
        let room: String
        let activity: String
        let time: Double
        let state: PiyakBehavior.DebugSnapshot
    }
    struct RoomReport: Codable {
        let name: String
        let equipped: [String: String]
        let observedVisits: [String]
        let simulatedSeconds: Double
        let updates: Int
        let samples: [Sample]
        let testedPause: Bool
        let testedStop: Bool
        let testedDismount: Bool
    }
    struct Report: Codable {
        let generatedAt: String
        let updateClockSupported: Bool
        let completedWithinBudget: Bool
        let wallSeconds: Double
        let gpuSnapshots: Int
        let findings: [Finding]
        let limitations: [String]
        let rooms: [RoomReport]
        let frames: [Frame]
    }
    struct StoryFrame {
        let label: String
        let image: NSImage
    }
    struct ProbeError: Error, CustomStringConvertible {
        let description: String
        init(_ description: String) { self.description = description }
    }

    final class Evidence {
        let directory: URL
        let started = Date()
        var frames: [Frame] = []
        var story: [StoryFrame] = []
        var findings: [Finding] = []
        var clockSupported = true
        var completedWithinBudget = true
        private var findingKeys: Set<String> = []

        init(_ directory: URL) { self.directory = directory }
        var overBudget: Bool { Date().timeIntervalSince(started) > 20 }

        func issue(_ room: String, _ detail: String) {
            if findingKeys.insert(room + detail).inserted { findings.append(Finding(room: room, detail: detail)) }
        }

        func capture(_ probe: RoomProbe, activity: String) throws {
            guard frames.count + RoomProbe.warmupSnapshots < 8 else { return }
            if overBudget { completedWithinBudget = false; return }
            let state = probe.behavior.debugSnapshot()
            let image = probe.renderer.snapshot(atTime: probe.clock,
                with: CGSize(width: 640, height: 480), antialiasingMode: .multisampling4X)
            let filename = String(format: "%02d-%@-%@.png", frames.count + 1, probe.name, activity)
            try png(image).write(to: directory.appendingPathComponent(filename))
            frames.append(Frame(file: filename, room: probe.name, activity: activity, time: probe.time, state: state))
            story.append(StoryFrame(label: "\(probe.name) · \(activity) · \(String(format: "%.1f", probe.time)) s", image: image))
        }
    }

    final class RoomProbe {
        private(set) static var warmupSnapshots = 0
        let name: String
        let equipped: [String: String]
        let renderer: SCNRenderer
        let scene: SCNScene
        let behavior: PiyakBehavior
        let baseClock = ProcessInfo.processInfo.systemUptime
        var time = 0.0
        var updates = 0
        var samples: [Sample] = []
        var observedVisits: Set<String> = []
        var testedPause = false, testedStop = false, testedDismount = false
        private var previous: PiyakBehavior.DebugSnapshot?
        private var largestMovement = 0.0
        private let initialPosition: [Double]
        var clock: Double { baseClock + time }

        init(name: String, equipped: [String: String]) throws {
            self.name = name; self.equipped = equipped
            let roomScene = PiyakScene.make(equipped: equipped, animated: false)
            guard let controller = PiyakBehavior(scene: roomScene, equipped: equipped, announce: { _ in }) else {
                throw ProbeError("\(name): missing named character rig")
            }
            scene = roomScene
            behavior = controller
            renderer = SCNRenderer(device: nil, options: nil)
            initialPosition = controller.debugSnapshot().position
            renderer.scene = scene
            renderer.pointOfView = scene.rootNode.childNodes.first { $0.camera != nil }
            scene.isPaused = false
            renderer.isPlaying = true
            behavior.configure(working: false)
            // A command-line process has no AppKit run-loop transaction commit.
            // Flush the initial graph/actions explicitly. Only the first room
            // takes a tiny warm-up snapshot to initialize SceneKit's renderer;
            // subsequent updates remain CPU-only and never become a GPU loop.
            SCNTransaction.flush()
            if Self.warmupSnapshots == 0 {
                _ = renderer.snapshot(atTime: baseClock, with: CGSize(width: 64, height: 64), antialiasingMode: .none)
                Self.warmupSnapshots += 1
                SCNTransaction.flush()
            }
            renderer.update(atTime: baseClock)
        }

        @discardableResult
        func advance(_ evidence: Evidence) -> PiyakBehavior.DebugSnapshot {
            time += 0.1
            renderer.update(atTime: clock)
            updates += 1
            let state = behavior.debugSnapshot()
            if let visit = state.visit { observedVisits.insert(visit) }
            let finite = state.position + [state.heading, state.leftFootHeight, state.rightFootHeight]
            if finite.contains(where: { !$0.isFinite }) {
                evidence.issue(name, "Non-finite root or foot transform.")
            }
            if state.position.count == 3 {
                largestMovement = max(largestMovement, distance(state.position, initialPosition))
                if state.visit != "rest" && !state.dismounting && abs(state.position[1]) > 0.001 {
                    evidence.issue(name, "Root leaves the floor outside a sofa/rest transition.")
                }
                if !(-2.15...1.2).contains(state.position[0]) || !(-1.45...1.6).contains(state.position[2]) {
                    evidence.issue(name, "Root leaves the room's allowed walk/seat bounds.")
                }
                if state.position[1] < -0.005 {
                    evidence.issue(name, "Root falls below the floor.")
                }
            }
            if state.leftFootHeight < -0.001 || state.rightFootHeight < -0.001 {
                evidence.issue(name, "Foot pivot falls below the floor.")
            }
            if let previous, previous.position.count == 3, state.position.count == 3 {
                let step = distance(state.position, previous.position)
                // At 0.1 second steps, normal walking is ~0.04 units and a sofa
                // transition is below 0.2. Leave margin for timing quantization.
                if step > 0.30 { evidence.issue(name, "A pose jumps more than 0.30 units in one 0.1-second update.") }
            }
            // Preserve all dismount samples, plus a compact 0.5s path trace.
            if updates.isMultiple(of: 5) || state.dismounting || state.visit != previous?.visit {
                samples.append(Sample(time: time, state: state))
            }
            previous = state
            if time >= 20 && (largestMovement < 0.025 || observedVisits.isSubset(of: ["greet"])) {
                evidence.clockSupported = false
            }
            return state
        }

        func checkPauseAndStop(_ evidence: Evidence) {
            let before = behavior.debugSnapshot()
            scene.isPaused = true; renderer.isPlaying = false
            for _ in 0..<3 {
                time += 0.1
                renderer.update(atTime: clock)
            }
            let paused = behavior.debugSnapshot()
            if distance(before.position, paused.position) > 0.0001 ||
                abs(before.leftFootHeight - paused.leftFootHeight) > 0.0001 ||
                abs(before.rightFootHeight - paused.rightFootHeight) > 0.0001 {
                evidence.issue(name, "Pose changes while renderer and scene are paused.")
            }
            testedPause = true
            behavior.stop()
            scene.isPaused = false; renderer.isPlaying = true
            for _ in 0..<5 {
                time += 0.1
                renderer.update(atTime: clock)
            }
            let stopped = behavior.debugSnapshot()
            let home = [PiyakActivityPlan.home.x, 0, PiyakActivityPlan.home.z]
            if distance(home, stopped.position) > 0.0001 || stopped.working != nil || !stopped.activity.isEmpty {
                evidence.issue(name, "Stopped behavior changes pose/state after subsequent renderer updates.")
            }
            testedStop = true
            renderer.isPlaying = false
            renderer.scene = nil
        }

        func report() -> RoomReport {
            RoomReport(name: name, equipped: equipped, observedVisits: observedVisits.sorted(), simulatedSeconds: time,
                updates: updates, samples: samples, testedPause: testedPause, testedStop: testedStop,
                testedDismount: testedDismount)
        }
    }

    static func main() throws {
        let output = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "/tmp/piyak-behavior-evidence")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let evidence = Evidence(output)
        var reports: [RoomReport] = []
        let combinations: [(String, [String: String], Set<String>)] = [
            ("plant-piano", ["floorProp": "floorProp.plant", "bigFurniture": "bigFurniture.piano"], ["water", "piano"]),
            ("puppy-sofa", ["floorProp": "floorProp.puppy", "bigFurniture": "bigFurniture.sofa"], ["pet", "rest"]),
            // Neither main test room reads; a short third probe verifies the
            // actual book attachment instead of synthesizing a pretend pose.
            ("books-desk", ["floorProp": "floorProp.books", "bigFurniture": "bigFurniture.desk"], ["read"])
        ]
        for (name, changes, targets) in combinations {
            if evidence.overBudget || !evidence.clockSupported {
                if evidence.overBudget { evidence.completedWithinBudget = false }
                break
            }
            let report: RoomReport = try autoreleasepool {
                var equipped = PiyakScene.defaultItems
                equipped.merge(changes) { _, new in new }
                let probe = try RoomProbe(name: name, equipped: equipped)
                var captured: Set<String> = []
                var lastVisit: String?
                var visitStarted = 0.0
                var switchTime: Double?
                var switchHeight = 0.0
                var capturedDismount = false
                var dismountFinished = name != "puppy-sofa"
                while probe.time < 110 && evidence.clockSupported && !evidence.overBudget {
                    let state = probe.advance(evidence)
                    if state.visit != lastVisit { visitStarted = probe.time; lastVisit = state.visit }
                    if let visit = state.visit, targets.contains(visit), !captured.contains(visit), probe.time - visitStarted >= 1.5 {
                        if visit == "rest" && state.position[1] <= 0.1 {
                            // A sofa visit without a seat anchor never rises.
                            if probe.time - visitStarted > 3 { evidence.issue(name, "Rest activity does not reach the sofa seat anchor.") }
                        } else {
                            if visit == "water" && !state.wateringCanVisible { evidence.issue(name, "Water activity has no visible watering can.") }
                            if visit == "read" && !state.bookVisible { evidence.issue(name, "Read activity has no visible book.") }
                            try evidence.capture(probe, activity: visit)
                            captured.insert(visit)
                            if visit == "rest" {
                                // Switch modes while the model is visibly seated,
                                // then verify the first update is not a fall to y=0.
                                let before = probe.behavior.debugSnapshot()
                                probe.behavior.configure(working: true)
                                let configured = probe.behavior.debugSnapshot()
                                if distance(before.position, configured.position) > 0.0001 {
                                    evidence.issue(name, "Mode configuration immediately teleports the seated character.")
                                }
                                if !configured.dismounting { evidence.issue(name, "Mode switch while seated does not start a dismount.") }
                                switchTime = probe.time
                                switchHeight = before.position[1]
                            }
                        }
                    }
                    if let switchTime, !dismountFinished {
                        let elapsed = probe.time - switchTime
                        if elapsed > 0.05 && elapsed < 0.25 && switchHeight > 0.1 && state.position[1] < 0.02 {
                            evidence.issue(name, "Mode change drops the seated root straight to the floor.")
                        }
                        if elapsed >= 0.3 && state.dismounting && !capturedDismount {
                            try evidence.capture(probe, activity: "dismount")
                            capturedDismount = true
                        }
                        if elapsed > 0.1 && !state.dismounting {
                            if abs(state.position[1]) > 0.001 { evidence.issue(name, "Dismount ends above the floor.") }
                            let expected = PiyakActivityPlan.itinerary(equipped: equipped, working: false).first { $0.activity == .rest }?.point
                            if let expected, hypot(state.position[0] - expected.x, state.position[2] - expected.z) > 0.06 {
                                evidence.issue(name, "Dismount does not return to the sofa's original floor waypoint.")
                            }
                            probe.testedDismount = true
                            dismountFinished = true
                            try evidence.capture(probe, activity: "dismounted")
                        } else if elapsed > 2.5 {
                            evidence.issue(name, "Dismount does not finish within 2.5 simulated seconds.")
                            break
                        }
                    }
                    if captured.isSuperset(of: targets) && dismountFinished { break }
                }
                if evidence.overBudget { evidence.completedWithinBudget = false }
                if evidence.clockSupported && evidence.completedWithinBudget {
                    let missing = targets.subtracting(captured)
                    if !missing.isEmpty { evidence.issue(name, "Required interactions were not captured: \(missing.sorted().joined(separator: ", ")).") }
                    probe.checkPauseAndStop(evidence)
                } else {
                    probe.behavior.stop(); probe.renderer.isPlaying = false; probe.renderer.scene = nil
                }
                return probe.report()
            }
            reports.append(report)
        }
        if !evidence.story.isEmpty { try storyboard(evidence.story, at: output.appendingPathComponent("behavior-storyboard.png")) }
        let report = Report(generatedAt: ISO8601DateFormatter().string(from: Date()),
            updateClockSupported: evidence.clockSupported, completedWithinBudget: evidence.completedWithinBudget,
            wallSeconds: Date().timeIntervalSince(evidence.started), gpuSnapshots: evidence.frames.count + RoomProbe.warmupSnapshots,
            findings: evidence.findings, limitations: [
                "Renderer actions are advanced by supplied time, not wall-clock timers; this does not measure device frame rate, heat or battery.",
                "If updateClockSupported is false, this headless SceneKit configuration did not advance actions. Inspect one iPhone simulator rather than adding timed rendering loops.",
                "Inspect behavior-storyboard.png for convincing contact with the plant, piano, pet and sofa; numeric bounds cannot prove visual quality.",
                "The 20-second work budget is checked between updates/snapshots. A synchronous Metal snapshot already in progress cannot be interrupted.",
                "The reading image uses a third books/desk room because plant/piano and puppy/sofa have no reading visit."
            ], rooms: reports, frames: evidence.frames)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(report).write(to: output.appendingPathComponent("behavior-report.json"))
        print("Behavior probe: \(reports.count) rooms, \(evidence.frames.count) evidence + \(RoomProbe.warmupSnapshots) warm-up GPU snapshots, \(evidence.findings.count) findings.")
        print("Clock supported: \(evidence.clockSupported); within budget: \(evidence.completedWithinBudget). Evidence: \(output.path)")
        for issue in evidence.findings { print("[\(issue.room)] \(issue.detail)") }
        if !evidence.clockSupported || !evidence.completedWithinBudget { exit(2) }
        if !evidence.findings.isEmpty { exit(1) }
    }

    static func distance(_ a: [Double], _ b: [Double]) -> Double {
        guard a.count == 3, b.count == 3 else { return .infinity }
        return sqrt(zip(a, b).reduce(0) { $0 + pow($1.0 - $1.1, 2) })
    }

    static func png(_ image: NSImage) throws -> Data {
        guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
              let data = bitmap.representation(using: .png, properties: [:]) else {
            throw ProbeError("Could not encode evidence PNG.")
        }
        return data
    }

    static func storyboard(_ frames: [StoryFrame], at destination: URL) throws {
        let columns = 3, cellWidth = 480, cellHeight = 390, header = 54
        let rows = (frames.count + columns - 1) / columns
        let width = columns * cellWidth, height = rows * cellHeight + header
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: bitmap) else { throw ProbeError("Could not allocate storyboard.") }
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = context
        NSColor(calibratedWhite: 0.94, alpha: 1).setFill()
        NSRect(x: 0, y: 0, width: width, height: height).fill()
        ("Piyak Bank — actual room behavior" as NSString).draw(at: CGPoint(x: 16, y: height - 36), withAttributes: [
            .font: NSFont.systemFont(ofSize: 20, weight: .semibold), .foregroundColor: NSColor.darkGray
        ])
        let paragraph = NSMutableParagraphStyle(); paragraph.alignment = .center
        for (index, frame) in frames.enumerated() {
            let x = index % columns * cellWidth, y = height - header - (index / columns + 1) * cellHeight
            NSColor.white.setFill()
            NSBezierPath(roundedRect: CGRect(x: x + 6, y: y + 6, width: cellWidth - 12, height: cellHeight - 12), xRadius: 10, yRadius: 10).fill()
            frame.image.draw(in: CGRect(x: x + 12, y: y + 36, width: cellWidth - 24, height: 342),
                             from: .zero, operation: .sourceOver, fraction: 1)
            (frame.label as NSString).draw(in: CGRect(x: x + 8, y: y + 10, width: cellWidth - 16, height: 22), withAttributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular),
                .foregroundColor: NSColor.darkGray, .paragraphStyle: paragraph
            ])
        }
        context.flushGraphics(); NSGraphicsContext.restoreGraphicsState()
        guard let png = bitmap.representation(using: .png, properties: [:]) else { throw ProbeError("Could not encode storyboard.") }
        try png.write(to: destination)
    }
}
