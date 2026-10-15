import SceneKit
import SwiftUI

/// One renderer, one finite presentation. No scene or animation survives dismissal.
struct UsageGuideSceneView: UIViewRepresentable {
    let page: UsageGuidePage
    let active: Bool
    let animated: Bool

    @MainActor final class Coordinator {
        var page: UsageGuidePage?
        var animated = false
        var generation = 0
        var completion: Task<Void, Never>?

        func stop(_ view: SCNView) {
            generation += 1
            completion?.cancel()
            completion = nil
            page = nil
            view.scene?.rootNode.removeAllActions()
            view.isPlaying = false
            view.rendersContinuously = false
            view.scene = nil
            view.pointOfView = nil
        }

        func configure(_ view: SCNView, page: UsageGuidePage, animated: Bool) {
            guard self.page != page || self.animated != animated else { return }
            stop(view)
            self.page = page
            self.animated = animated
            view.scene = UsageGuideScene.make(page: page, animated: animated)
            view.pointOfView = view.scene?.rootNode.childNode(withName: "camera", recursively: false)
            view.scene?.isPaused = !animated
            view.isPlaying = animated
            view.rendersContinuously = animated
            view.setNeedsDisplay()
            guard animated else { return }
            let token = generation
            completion = Task { @MainActor [weak self, weak view] in
                do { try await Task.sleep(for: .seconds(5.6)) } catch { return }
                guard let self, let view, self.generation == token else { return }
                // Rebuild the settled pose rather than freezing halfway through an action.
                view.scene = UsageGuideScene.make(page: page, animated: false)
                view.pointOfView = view.scene?.rootNode.childNode(withName: "camera", recursively: false)
                view.scene?.isPaused = true
                view.isPlaying = false
                view.rendersContinuously = false
                view.setNeedsDisplay()
                self.completion = nil
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.backgroundColor = .clear
        view.isOpaque = false
        view.antialiasingMode = .multisampling4X
        view.autoenablesDefaultLighting = false
        view.allowsCameraControl = false
        return view
    }
    func updateUIView(_ view: SCNView, context: Context) {
        guard active else { context.coordinator.stop(view); return }
        view.preferredFramesPerSecond = ProcessInfo.processInfo.thermalState == .nominal ? 60 : 30
        context.coordinator.configure(view, page: page, animated: animated)
    }
    static func dismantleUIView(_ view: SCNView, coordinator: Coordinator) { coordinator.stop(view) }
}

/// Guide-only geometry and choreography leave the shared room and exported assets untouched.
enum UsageGuideScene {
    static func make(page: UsageGuidePage, animated: Bool) -> SCNScene {
        let room = page == .welcome || page == .decorate
        var items = PiyakScene.defaultItems
        if page == .decorate {
            items["bigFurniture"] = "bigFurniture.sofa"
            items["headTop"] = "headTop.beret"
            items["wallDeco"] = "wallDeco.frame"
        }
        let scene = PiyakScene.make(equipped: items, animated: false, icon: !room)
        scene.background.contents = UIColor.clear
        guard let chick = scene.rootNode.childNode(withName: "piyak", recursively: false) else { return scene }
        if room {
            if let camera = scene.rootNode.childNode(withName: "camera", recursively: false) {
                camera.camera?.orthographicScale = 3.45
            }
            if animated {
                appear(chick, delay: 0.15)
                wave(chick)
                if page == .welcome {
                    for (index, node) in scene.rootNode.childNodes.filter({ $0.camera == nil && $0.light == nil && $0 !== chick }).enumerated() {
                        appear(node, delay: Double(index) * 0.025)
                    }
                } else {
                    for (index, name) in ["room.rug", "room.furniture", "room.prop", "room.wall"].enumerated() {
                        if let node = scene.rootNode.childNode(withName: name, recursively: false) {
                            appear(node, delay: 0.5 + Double(index) * 0.45)
                        }
                    }
                }
            }
            if page == .decorate {
                let reward = coin()
                reward.position = SCNVector3(1.15, 2.1, 0.8)
                reward.eulerAngles.x = .pi / 2
                scene.rootNode.addChildNode(reward)
                if animated {
                    appear(reward, delay: 0.4)
                    reward.runAction(.sequence([.wait(duration: 0.7),
                        .rotateBy(x: 0, y: .pi * 2, z: 0, duration: 1.6)]))
                }
            }
        } else {
            let camera = scene.rootNode.childNode(withName: "camera", recursively: false)
            camera?.position = SCNVector3(0.3, 2.2, 9)
            camera?.look(at: SCNVector3(0, page == .work ? 0.7 : 1.2, 0))
            camera?.camera?.orthographicScale = 2.15
            chick.position = SCNVector3(-1.35, -0.05, 0.65)
            chick.scale = SCNVector3(0.43, 0.43, 0.43)
            let plinth = cylinder(radius: 1.7, depth: 0.14, tint: 0xE4DCF7)
            plinth.position = SCNVector3(0, -0.15, 0)
            scene.rootNode.addChildNode(plinth)
            if page == .work { clock(in: scene, animated: animated) }
            else { devices(in: scene, animated: animated) }
            if animated { appear(chick, delay: 0.3); wave(chick) }
        }
        return scene
    }

    private static func clock(in scene: SCNScene, animated: Bool) {
        let clock = SCNNode()
        clock.position = SCNVector3(0.4, 1.2, 0)
        clock.eulerAngles.y = -0.12
        scene.rootNode.addChildNode(clock)
        let rim = cylinder(radius: 1.02, depth: 0.24, tint: 0xB7A4E8)
        rim.eulerAngles.x = .pi / 2
        clock.addChildNode(rim)
        let face = cylinder(radius: 0.91, depth: 0.045, tint: 0xFFF9EC)
        face.eulerAngles.x = .pi / 2
        face.position.z = 0.14
        clock.addChildNode(face)
        for index in 0..<12 {
            let angle = Float(index) * .pi / 6
            let tick = box(0.035, index.isMultiple(of: 3) ? 0.13 : 0.07, 0.03, tint: 0x9B8AB9)
            tick.position = SCNVector3(sin(angle) * 0.75, cos(angle) * 0.75, 0.18)
            tick.simdEulerAngles.z = -angle
            clock.addChildNode(tick)
        }
        let hand = SCNNode()
        let pointer = box(0.055, 0.63, 0.05, tint: 0x6653BE)
        pointer.position = SCNVector3(0, 0.25, 0.21)
        hand.addChildNode(pointer)
        clock.addChildNode(hand)
        let shortHand = box(0.075, 0.4, 0.06, tint: 0xF1A15D)
        shortHand.eulerAngles.z = -1.0
        shortHand.position = SCNVector3(0.14, 0.09, 0.22)
        clock.addChildNode(shortHand)
        let pin = SCNNode(geometry: SCNSphere(radius: 0.09))
        pin.geometry?.materials = [material(0x6653BE)]
        pin.position.z = 0.25
        clock.addChildNode(pin)
        let knob = box(0.38, 0.16, 0.2, tint: 0xFFDB63)
        knob.position.y = 1.1
        clock.addChildNode(knob)
        if animated {
            appear(clock, delay: 0)
            hand.runAction(.sequence([
                .rotateBy(x: 0, y: 0, z: -2, duration: 1.8),
                .wait(duration: 0.9),
                .rotateBy(x: 0, y: 0, z: -2, duration: 1.8)
            ]))
        } else { hand.eulerAngles.z = -4 }
    }

    private static func devices(in scene: SCNScene, animated: Bool) {
        let phone = SCNNode()
        phone.position = SCNVector3(-0.55, 1.25, 0)
        phone.eulerAngles = SCNVector3(-0.07, -0.18, -0.12)
        phone.addChildNode(box(1.3, 2.45, 0.22, tint: 0x70618E, radius: 0.17))
        let phoneScreen = box(1.13, 2.23, 0.035, tint: 0xFFF9EC, radius: 0.12)
        phoneScreen.position.z = 0.13
        phone.addChildNode(phoneScreen)
        let island = box(0.38, 0.08, 0.025, tint: 0x34354C)
        island.position = SCNVector3(0, 1.0, 0.16)
        phone.addChildNode(island)
        screenContent(in: phone, scale: 1, at: SCNVector3(0, 0.12, 0.17), animated: animated)
        scene.rootNode.addChildNode(phone)

        let watch = SCNNode()
        watch.position = SCNVector3(1.0, 1.0, 0.65)
        watch.eulerAngles = SCNVector3(-0.1, -0.25, 0.13)
        watch.addChildNode(box(0.67, 2.45, 0.14, tint: 0xB7A4E8, radius: 0.14))
        let buckle = box(0.48, 0.3, 0.16, tint: 0xD8CEEC)
        buckle.position.y = 0.98
        watch.addChildNode(buckle)
        watch.addChildNode(box(1.08, 1.28, 0.32, tint: 0xD7D5E3, radius: 0.21))
        let watchScreen = box(0.94, 1.13, 0.05, tint: 0x34354C, radius: 0.18)
        watchScreen.position.z = 0.18
        watch.addChildNode(watchScreen)
        let crown = cylinder(radius: 0.095, depth: 0.13, tint: 0xB9B4CE)
        crown.eulerAngles.z = .pi / 2
        crown.position = SCNVector3(0.58, 0.18, 0)
        watch.addChildNode(crown)
        screenContent(in: watch, scale: 0.68, at: SCNVector3(0, 0, 0.22), animated: animated, darkScreen: true)
        scene.rootNode.addChildNode(watch)
        for index in 0..<3 {
            let dot = SCNNode(geometry: SCNSphere(radius: 0.055))
            dot.geometry?.materials = [material(0xFFDB63)]
            dot.position = SCNVector3(0.25 + Float(index) * 0.17, 2.35, 0.65)
            scene.rootNode.addChildNode(dot)
            if animated {
                dot.runAction(.sequence([.wait(duration: 0.9 + Double(index) * 0.16),
                    .repeat(.sequence([.fadeOpacity(to: 0.15, duration: 0.25), .fadeIn(duration: 0.25)]), count: 5)]))
            }
        }
        if animated {
            appear(phone, delay: 0)
            appear(watch, delay: 0.4)
            for node in [phone, watch] {
                node.runAction(.sequence([.wait(duration: 0.8),
                    .repeat(.sequence([.moveBy(x: 0, y: 0.09, z: 0, duration: 0.8),
                                      .moveBy(x: 0, y: -0.09, z: 0, duration: 0.8)]), count: 2)]))
            }
        }
    }

    private static func screenContent(in device: SCNNode, scale: Float, at position: SCNVector3,
                                      animated: Bool, darkScreen: Bool = false) {
        let content = SCNNode()
        content.position = position
        content.scale = SCNVector3(scale, scale, scale)
        let portrait = SCNPlane(width: 0.72, height: 0.72)
        let portraitMaterial = SCNMaterial()
        portraitMaterial.diffuse.contents = UIImage(named: "AppMascot")
        portraitMaterial.lightingModel = .constant
        portrait.materials = [portraitMaterial]
        let mascot = SCNNode(geometry: portrait)
        mascot.position.y = 0.27
        content.addChildNode(mascot)
        let amountNode = lettering("₩2,500", height: 0.16, tint: darkScreen ? 0xFFDB63 : 0x6653BE)
        amountNode.position = SCNVector3(0, -0.26, 0.02)
        content.addChildNode(amountNode)
        let button = box(0.7, 0.22, 0.025, tint: 0xFFDB63)
        button.position.y = -0.55
        content.addChildNode(button)
        let playNode = lettering("▶", height: 0.1, tint: 0x34354C)
        playNode.position = SCNVector3(0, -0.55, 0.025)
        content.addChildNode(playNode)
        device.addChildNode(content)
        if animated {
            button.runAction(.sequence([.wait(duration: 1.1),
                .repeat(.sequence([.scale(to: 0.91, duration: 0.18), .scale(to: 1, duration: 0.18),
                                   .wait(duration: 0.55)]), count: 3)]))
        }
    }

    private static func appear(_ node: SCNNode, delay: Double) {
        let scale = node.simdScale
        node.simdScale = scale * 0.01
        node.opacity = 0
        let grow = SCNAction.customAction(duration: 0.65) { target, time in
            let progress = min(1, Float(time) / 0.65)
            let eased = 1 - pow(1 - progress, 3)
            target.simdScale = scale * eased
        }
        node.runAction(.sequence([.wait(duration: delay), .group([grow, .fadeIn(duration: 0.4)])]))
    }
    private static func wave(_ chick: SCNNode) {
        guard let wing = chick.childNode(withName: "wing.right", recursively: true) else { return }
        wing.runAction(.sequence([.wait(duration: 0.85),
            .repeat(.sequence([.rotateBy(x: 0, y: 0, z: 0.65, duration: 0.3),
                               .rotateBy(x: 0, y: 0, z: -0.65, duration: 0.3),
                               .wait(duration: 0.3)]), count: 4)]))
    }
    private static func coin() -> SCNNode {
        let node = cylinder(radius: 0.3, depth: 0.09, tint: 0xFFDB63)
        let face = lettering("P", height: 0.31, tint: 0xC38E39)
        face.eulerAngles.x = -.pi / 2
        face.position = SCNVector3(0, 0.055, 0)
        node.addChildNode(face)
        return node
    }
    private static func lettering(_ text: String, height: Float, tint: UInt) -> SCNNode {
        let shape = SCNText(string: text, extrusionDepth: 0.01)
        shape.font = UIFont.systemFont(ofSize: 1, weight: .bold)
        shape.flatness = 0.02
        shape.materials = [material(tint)]
        let node = SCNNode(geometry: shape)
        let (low, high) = node.boundingBox
        var pivot = matrix_identity_float4x4
        pivot.columns.3 = SIMD4<Float>((low.x + high.x) / 2, (low.y + high.y) / 2, (low.z + high.z) / 2, 1)
        node.simdPivot = pivot
        node.simdScale = SIMD3(repeating: height / max(high.y - low.y, 0.01))
        return node
    }
    private static func material(_ tint: UInt) -> SCNMaterial {
        let result = SCNMaterial()
        result.diffuse.contents = UIColor(red: CGFloat((tint >> 16) & 255) / 255,
                                          green: CGFloat((tint >> 8) & 255) / 255,
                                          blue: CGFloat(tint & 255) / 255, alpha: 1)
        result.lightingModel = .physicallyBased
        result.roughness.contents = 0.7
        return result
    }
    private static func box(_ width: CGFloat, _ height: CGFloat, _ depth: CGFloat, tint: UInt, radius: CGFloat = 0.04) -> SCNNode {
        if radius > 0.04 {
            // A shallow SCNBox limits its corner radius to half its depth.
            // Extrude a rounded face so thin device screens retain rounded corners.
            let path = UIBezierPath(roundedRect: CGRect(x: -width / 2, y: -height / 2, width: width, height: height),
                                    cornerRadius: min(radius, min(width, height) / 2))
            path.flatness = 0.01
            let shape = SCNShape(path: path, extrusionDepth: depth)
            shape.chamferRadius = min(0.012, depth / 4)
            shape.materials = [material(tint)]
            let node = SCNNode(geometry: shape)
            var pivot = matrix_identity_float4x4
            pivot.columns.3.z = Float(depth / 2)
            node.simdPivot = pivot
            return node
        }
        let shape = SCNBox(width: width, height: height, length: depth,
                           chamferRadius: min(radius, min(width, min(height, depth)) / 2))
        shape.materials = [material(tint)]
        return SCNNode(geometry: shape)
    }
    private static func cylinder(radius: CGFloat, depth: CGFloat, tint: UInt) -> SCNNode {
        let shape = SCNCylinder(radius: radius, height: depth)
        shape.radialSegmentCount = 48
        shape.materials = [material(tint)]
        return SCNNode(geometry: shape)
    }
}
