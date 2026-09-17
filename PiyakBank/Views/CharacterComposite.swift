import SwiftUI
import SwiftData
import SceneKit

struct CharacterComposite: View {
    @Query private var owned: [OwnedItem]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var phase
    var showRoom = true
    var fillRoom = false
    var isWorking = false
    var workedHours: Double = 0
    var preview: [String: String]?
    @State private var visible = false

    private var equipped: [String: String] {
        if let preview { return preview }
        var result: [String: String] = [:]
        for item in owned { if let slot = item.equippedSlotRaw { result[slot] = item.catalogId } }
        return result
    }
    var body: some View {
        PiyakSceneView(equipped: equipped, working: isWorking,
                       animated: visible && phase == .active && !reduceMotion && isWorking, icon: !showRoom)
            .accessibilityHidden(true)
            .onAppear { visible = true }
            .onDisappear { visible = false }
    }
}

struct PiyakSceneView: UIViewRepresentable {
    var equipped: [String: String]
    var working = false
    var animated = true
    var icon = false

    final class Coordinator {
        var key = ""
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
        return view
    }
    func updateUIView(_ view: SCNView, context: Context) {
        let key = equipped.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: ";") + "\(working)\(icon)"
        if key != context.coordinator.key {
            context.coordinator.key = key
            view.scene = PiyakScene.make(equipped: equipped, working: working, animated: true, icon: icon)
            view.pointOfView = view.scene?.rootNode.childNodes.first { $0.camera != nil }
            view.setNeedsDisplay()
        }
        view.scene?.isPaused = !animated
        view.isPlaying = animated
    }
    static func dismantleUIView(_ view: SCNView, coordinator: Coordinator) {
        view.isPlaying = false; view.scene = nil
    }
}
