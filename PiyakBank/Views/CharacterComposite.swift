import SwiftUI
import SwiftData
import SceneKit
import simd

struct CharacterComposite: View {
    @Query private var owned: [OwnedItem]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var phase
    var showRoom = true
    var fillRoom = false
    var isWorking = false
    var workedHours: Double = 0
    var preview: [String: String]?
    var animateLife = false
    var allowsInspection = false
    var inspectionYaw: Double = 0
    var inspectionZoom: Double = 1
    var inspectionResetID = 0
    var interactionID = 0
    var onInteract: (() -> Void)?
    var onActivity: (String) -> Void = { _ in }
    @State private var visible = false
    @State private var intersectsScreen = true
    @State private var powerLimited = ProcessInfo.processInfo.isLowPowerModeEnabled
    @State private var thermalState = ProcessInfo.processInfo.thermalState

    private var equipped: [String: String] {
        if let preview { return preview }
        var result: [String: String] = [:]
        for item in owned { if let slot = item.equippedSlotRaw { result[slot] = item.catalogId } }
        return result
    }
    private var shouldAnimate: Bool {
        animateLife && visible && intersectsScreen && phase == .active && !reduceMotion && !powerLimited
            && thermalState != .serious && thermalState != .critical
    }
    private var playbackPauseReason: String? {
        guard animateLife, visible, intersectsScreen, phase == .active else { return nil }
        if thermalState == .serious || thermalState == .critical { return "기기가 식을 때까지 쉬고 있어요" }
        if powerLimited { return "저전력 모드에서는 쉬고 있어요" }
        if reduceMotion { return "동작 줄이기 설정으로 쉬고 있어요" }
        return nil
    }
    private var debugPlaybackGate: String? {
        #if DEBUG
        guard CommandLine.arguments.contains("--debug-room-status") else { return nil }
        return "life=\(animateLife) visible=\(visible) viewport=\(intersectsScreen) phase=\(phase) reduceMotion=\(reduceMotion) lowPower=\(powerLimited) thermal=\(thermalState.rawValue)"
        #else
        return nil
        #endif
    }
    var body: some View {
        PiyakSceneView(equipped: equipped, working: isWorking,
                       animated: shouldAnimate, icon: !showRoom,
                       allowsInspection: allowsInspection, inspectionYaw: inspectionYaw,
                       inspectionZoom: inspectionZoom, inspectionResetID: inspectionResetID,
                       interactionID: interactionID, onInteract: onInteract,
                       onActivity: onActivity,
                       debugPlaybackGate: debugPlaybackGate, playbackPauseReason: playbackPauseReason)
            .accessibilityHidden(true)
            .onGeometryChange(for: CGRect.self) { geometry in
                geometry.frame(in: .global)
            } action: { frame in
                // Keep the last known visibility until direct observation has
                // a usable frame; an initial empty measurement is not evidence
                // that the room is outside the viewport.
                guard !frame.isNull, !frame.isInfinite, frame.width > 0, frame.height > 0,
                      [frame.minX, frame.minY, frame.width, frame.height].allSatisfy(\.isFinite) else {
                    #if DEBUG
                    if CommandLine.arguments.contains("--debug-room-status") {
                        print("[PiyakRoom] viewport measurement deferred: frame=\(frame)")
                    }
                    #endif
                    return
                }
                let screen = UIScreen.main.bounds
                guard !screen.isNull, !screen.isInfinite, screen.width > 0, screen.height > 0 else { return }
                let intersection = frame.intersection(screen)
                let visible = !intersection.isNull && intersection.height > 24 && intersection.width > 0
                #if DEBUG
                if CommandLine.arguments.contains("--debug-room-status") {
                    print("[PiyakRoom] viewport frame=\(frame) screen=\(screen) intersection=\(intersection) visible=\(visible)")
                }
                #endif
                intersectsScreen = visible
            }
            .onAppear { visible = true }
            .onDisappear { visible = false }
            .onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)) { _ in
                powerLimited = ProcessInfo.processInfo.isLowPowerModeEnabled
            }
            .onReceive(NotificationCenter.default.publisher(for: ProcessInfo.thermalStateDidChangeNotification)) { _ in
                thermalState = ProcessInfo.processInfo.thermalState
            }
    }
}

struct PiyakSceneView: UIViewRepresentable {
    var equipped: [String: String]
    var working = false
    var animated = true
    var icon = false
    var allowsInspection = false
    var inspectionYaw: Double = 0
    var inspectionZoom: Double = 1
    var inspectionResetID = 0
    var interactionID = 0
    var onInteract: (() -> Void)?
    var onActivity: (String) -> Void = { _ in }
    var debugPlaybackGate: String?
    var playbackPauseReason: String?

    final class Coordinator: NSObject {
        var key = ""
        var behavior: PiyakBehavior?
        var onActivity: (String) -> Void = { _ in }
        var invalidated = false
        var sceneGeneration = 0
        var lastActivity = ""
        var wasAnimating = false
        var playbackPauseReason: String?
        var onInteract: (() -> Void)?
        var lastInteractionID: Int?
        private var characterTap: UITapGestureRecognizer?
        private(set) var inspectionEnabled = false
        private weak var inspectionView: SCNView?
        private let observedGestures = NSHashTable<UIGestureRecognizer>.weakObjects()
        private var activeGestures: Set<ObjectIdentifier> = []
        private var inspectionOrigin = SIMD3<Float>.zero
        private(set) var inspectionTarget = SCNVector3Zero
        private var inspectionScale: Double = 1
        private var inspectionInput: (yaw: Double, zoom: Double, resetID: Int)?
        var isInspecting: Bool { inspectionEnabled && !activeGestures.isEmpty }
        #if DEBUG
        var lastDiagnostic = ""
        #endif

        func enableCharacterTap(in view: SCNView, enabled: Bool) {
            guard enabled else {
                if let characterTap { view.removeGestureRecognizer(characterTap) }
                characterTap = nil
                return
            }
            guard characterTap == nil else { return }
            let tap = UITapGestureRecognizer(target: self, action: #selector(tappedCharacter(_:)))
            tap.cancelsTouchesInView = false
            view.addGestureRecognizer(tap)
            characterTap = tap
        }

        @objc private func tappedCharacter(_ gesture: UITapGestureRecognizer) {
            guard !invalidated, gesture.state == .ended,
                  let view = gesture.view as? SCNView,
                  let hit = view.hitTest(gesture.location(in: view), options: [
                    .searchMode: SCNHitTestSearchMode.closest.rawValue
                  ]).first else { return }
            var node: SCNNode? = hit.node
            while let current = node {
                if current.name == "piyak" { onInteract?(); return }
                node = current.parent
            }
        }

        func captureInspectionCamera(in view: SCNView) {
            guard let camera = view.pointOfView else { return }
            inspectionOrigin = camera.simdWorldPosition
            let forward = camera.simdWorldFront
            // PiyakScene frames the model by looking at its center on z = 0.
            // Recover that actual center so tall hats keep their fitted crop.
            let distance = abs(forward.z) > 0.001 ? -inspectionOrigin.z / forward.z : 0
            let target = inspectionOrigin + forward * distance
            inspectionTarget = SCNVector3(target.x, target.y, target.z)
            inspectionScale = camera.camera?.orthographicScale ?? 1
            inspectionInput = nil
        }

        func applyInspection(in view: SCNView, yaw: Double, zoom: Double, resetID: Int) {
            guard inspectionEnabled, let camera = view.pointOfView else { return }
            let zoom = min(1.6, max(0.7, zoom))
            if let previous = inspectionInput,
               previous.yaw == yaw, previous.zoom == zoom, previous.resetID == resetID { return }
            inspectionInput = (yaw, zoom, resetID)
            let target = SIMD3<Float>(Float(inspectionTarget.x), Float(inspectionTarget.y), Float(inspectionTarget.z))
            let orbit = simd_quatf(angle: Float(yaw), axis: SIMD3<Float>(0, 1, 0))
            let offset = orbit.act(inspectionOrigin - target)
            SCNTransaction.begin()
            SCNTransaction.animationDuration = 0
            camera.simdWorldPosition = target + offset
            camera.look(at: inspectionTarget)
            camera.camera?.orthographicScale = inspectionScale / zoom
            view.defaultCameraController.pointOfView = camera
            view.defaultCameraController.target = inspectionTarget
            SCNTransaction.commit()
            // A button changes one frame, not the idle rendering policy. Gestures
            // still use SceneKit's camera and their existing temporary clock.
            SCNTransaction.flush()
            view.setNeedsDisplay()
        }

        func observeCameraGestures(in view: SCNView, enabled: Bool) {
            inspectionEnabled = enabled
            inspectionView = view
            guard enabled else { removeCameraObservers(); return }
            // Keep SceneKit's own pan/pinch implementation and delegates. These
            // targets only control when it needs a continuous rendering clock.
            for gesture in view.gestureRecognizers ?? [] where !observedGestures.contains(gesture) {
                gesture.addTarget(self, action: #selector(cameraGestureChanged(_:)))
                observedGestures.add(gesture)
            }
        }

        func removeCameraObservers() {
            for gesture in observedGestures.allObjects {
                gesture.removeTarget(self, action: #selector(cameraGestureChanged(_:)))
            }
            observedGestures.removeAllObjects()
            activeGestures.removeAll()
        }

        @objc private func cameraGestureChanged(_ gesture: UIGestureRecognizer) {
            guard inspectionEnabled, !invalidated, let view = inspectionView else { return }
            let wasInspecting = isInspecting
            switch gesture.state {
            case .began, .changed: activeGestures.insert(ObjectIdentifier(gesture))
            case .ended, .cancelled, .failed: activeGestures.remove(ObjectIdentifier(gesture))
            case .possible: return
            @unknown default: activeGestures.remove(ObjectIdentifier(gesture))
            }
            view.rendersContinuously = wasAnimating || isInspecting
            if isInspecting && !wasInspecting { SCNTransaction.flush() }
            // The final camera position must render once after pan/pinch ends;
            // inertia is disabled, so no idle display loop is necessary.
            view.setNeedsDisplay()
        }
    }
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.backgroundColor = .clear
        view.isOpaque = false
        view.antialiasingMode = .multisampling4X
        view.preferredFramesPerSecond = 24
        view.autoenablesDefaultLighting = false
        view.allowsCameraControl = false
        view.defaultCameraController.inertiaEnabled = false
        view.rendersContinuously = false
        return view
    }
    func updateUIView(_ view: SCNView, context: Context) {
        let coordinator = context.coordinator
        coordinator.onActivity = onActivity
        coordinator.onInteract = onInteract
        let pauseReasonChanged = coordinator.playbackPauseReason != playbackPauseReason
        let resumed = animated && !coordinator.wasAnimating
        coordinator.playbackPauseReason = playbackPauseReason
        let key = equipped.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: ";") + "\(icon)"
        let sceneChanged = key != coordinator.key
        if sceneChanged {
            context.coordinator.key = key
            coordinator.sceneGeneration += 1
            let generation = coordinator.sceneGeneration
            coordinator.behavior?.stop()
            view.scene = PiyakScene.make(equipped: equipped, animated: false, icon: icon)
            view.pointOfView = view.scene?.rootNode.childNodes.first { $0.camera != nil }
            coordinator.captureInspectionCamera(in: view)
            if let scene = view.scene, !icon {
                coordinator.behavior = PiyakBehavior(scene: scene, equipped: equipped) { [weak coordinator] label in
                    Task { @MainActor [weak coordinator] in
                        guard let coordinator, !coordinator.invalidated, coordinator.sceneGeneration == generation,
                              coordinator.wasAnimating, coordinator.playbackPauseReason == nil,
                              coordinator.behavior?.currentActivity == label,
                              coordinator.lastActivity != label else { return }
                        coordinator.lastActivity = label
                        coordinator.onActivity(label)
                    }
                }
            } else { coordinator.behavior = nil }
            view.setNeedsDisplay()
        }
        let inspectionStarted = allowsInspection && !coordinator.inspectionEnabled
        view.allowsCameraControl = allowsInspection
        coordinator.enableCharacterTap(in: view, enabled: onInteract != nil && !allowsInspection)
        coordinator.observeCameraGestures(in: view, enabled: allowsInspection)
        if inspectionStarted {
            // Some OS versions install default recognizers when the view joins
            // its window. Observe those once the current layout transaction ends.
            DispatchQueue.main.async { [weak view, weak coordinator] in
                guard let view, let coordinator, coordinator.inspectionEnabled, !coordinator.invalidated else { return }
                coordinator.observeCameraGestures(in: view, enabled: true)
            }
        }
        view.defaultCameraController.target = allowsInspection ? coordinator.inspectionTarget : SCNVector3(0, icon ? 1.3 : 1.0, 0)
        coordinator.applyInspection(in: view, yaw: inspectionYaw, zoom: inspectionZoom, resetID: inspectionResetID)
        // Start the renderer before adding root custom actions. SceneKit cannot
        // infer a continuously changing surface from these actions alone.
        let rendererActive = animated || allowsInspection
        view.scene?.isPaused = !rendererActive
        view.isPlaying = rendererActive
        view.rendersContinuously = animated || coordinator.isInspecting
        if allowsInspection && !animated && view.scene?.rootNode.action(forKey: "piyak.life") != nil {
            coordinator.behavior?.stop()
        }
        if animated { coordinator.behavior?.configure(working: working) }
        if (animated && !coordinator.wasAnimating) || (rendererActive && sceneChanged) || inspectionStarted {
            SCNTransaction.flush()
            view.setNeedsDisplay()
        }
        coordinator.wasAnimating = animated
        if coordinator.lastInteractionID != interactionID {
            let hasPreviousValue = coordinator.lastInteractionID != nil
            coordinator.lastInteractionID = interactionID
            if hasPreviousValue, onInteract != nil {
                if animated {
                    if coordinator.behavior?.react() == true {
                        SCNTransaction.flush()
                        view.setNeedsDisplay()
                    }
                } else {
                    // A touch still receives a response while motion is paused.
                    // Never override Reduce Motion, low power, thermal or user pause.
                    let generation = coordinator.sceneGeneration
                    let expectedID = interactionID
                    Task { @MainActor [weak coordinator] in
                        guard let coordinator, !coordinator.invalidated,
                              coordinator.sceneGeneration == generation,
                              coordinator.lastInteractionID == expectedID,
                              !coordinator.wasAnimating else { return }
                        let label = coordinator.playbackPauseReason.map { "반가워! " + $0 }
                            ?? "반가워! 쉬면서도 함께할게"
                        coordinator.lastActivity = label
                        coordinator.onActivity(label)
                    }
                }
            }
        }
        if pauseReasonChanged || resumed {
            let generation = coordinator.sceneGeneration
            let expectedReason = playbackPauseReason
            // Deliver after SwiftUI's update transaction. On recovery, read the
            // current action rather than leaving the previous pause reason up
            // until the next furniture visit happens to start.
            Task { @MainActor [weak coordinator] in
                guard let coordinator, !coordinator.invalidated, coordinator.sceneGeneration == generation,
                      coordinator.playbackPauseReason == expectedReason else { return }
                let label: String
                if let expectedReason { label = expectedReason }
                else {
                    guard coordinator.wasAnimating else { return }
                    let current = coordinator.behavior?.currentActivity ?? ""
                    label = current.isEmpty ? "반가워! 오늘도 함께해" : current
                }
                guard coordinator.lastActivity != label else { return }
                coordinator.lastActivity = label
                coordinator.onActivity(label)
            }
        }
        #if DEBUG
        if let debugPlaybackGate, CommandLine.arguments.contains("--debug-room-status") {
            let state = coordinator.behavior?.debugSnapshot()
            let diagnostic = "[PiyakRoom] \(debugPlaybackGate) animated=\(animated) playing=\(view.isPlaying) continuous=\(view.rendersContinuously) paused=\(String(describing: view.scene?.isPaused)) behaviorWorking=\(String(describing: state?.working)) activity=\(state?.activity ?? "<no behavior>") actions=\(view.scene?.rootNode.actionKeys ?? [])"
            if diagnostic != coordinator.lastDiagnostic {
                coordinator.lastDiagnostic = diagnostic
                print(diagnostic)
            }
        }
        #endif
    }
    static func dismantleUIView(_ view: SCNView, coordinator: Coordinator) {
        coordinator.invalidated = true
        coordinator.sceneGeneration += 1
        coordinator.removeCameraObservers()
        coordinator.enableCharacterTap(in: view, enabled: false)
        coordinator.onInteract = nil
        coordinator.behavior?.stop(); coordinator.behavior = nil
        coordinator.wasAnimating = false
        view.rendersContinuously = false; view.isPlaying = false; view.scene = nil
    }
}
