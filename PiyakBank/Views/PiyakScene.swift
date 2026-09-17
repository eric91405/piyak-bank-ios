import SceneKit
import simd
#if canImport(UIKit)
import UIKit
private typealias ClayColor = UIColor
#else
import AppKit
private typealias ClayColor = NSColor
#endif

/// Small original 3D models shared by the room, fitting previews and exported artwork.
/// Clothing is a fitted surface; decorative seams follow that surface instead of crossing it.
enum PiyakScene {
    static let defaultItems = ["bg": "bg.cozy_cream", "floorProp": "floorProp.plant",
                               "rug": "rug.oval_coral", "bodyFront": "bodyFront.hoodie_mint"]
    private typealias V = SIMD3<Float>
    private static let yellow: UInt = 0xFFD64F

    static func make(equipped: [String: String] = defaultItems, working: Bool = false,
                     animated: Bool = true, icon: Bool = false) -> SCNScene {
        let scene = SCNScene()
        let root = scene.rootNode
        let camera = SCNNode(); camera.name = "camera"
        camera.camera = SCNCamera()
        camera.camera?.usesOrthographicProjection = true
        camera.camera?.orthographicScale = icon ? 1.58 : 3.1
        camera.camera?.zNear = 0.1; camera.camera?.zFar = 100
        camera.position = icon ? SCNVector3(2.1, 2.55, 7) : SCNVector3(4.4, 4.1, 7.5)
        camera.look(at: SCNVector3(0, icon ? 1.3 : 1.05, 0))
        root.addChildNode(camera)

        let ambient = SCNNode(); ambient.light = SCNLight(); ambient.light?.type = .ambient
        ambient.light?.intensity = 330; ambient.light?.color = color(0xFFF4E0)
        root.addChildNode(ambient)
        let light = SCNNode(); light.light = SCNLight(); light.light?.type = .directional
        light.light?.intensity = 650; light.light?.castsShadow = true
        light.light?.shadowMode = .deferred; light.light?.shadowColor = color(0x43336E, alpha: 0.22)
        light.light?.shadowRadius = 8; light.light?.shadowSampleCount = 16
        light.light?.orthographicScale = 8
        light.eulerAngles = SCNVector3(-0.85, -0.6, -0.2); root.addChildNode(light)
        let fill = SCNNode(); fill.light = SCNLight(); fill.light?.type = .omni
        fill.light?.intensity = 120; fill.position = SCNVector3(4, 2, 5); root.addChildNode(fill)

        if !icon { room(root, equipped: equipped) }
        let chick = character(equipped: equipped)
        chick.position = SCNVector3(icon ? 0 : 0.15, 0, icon ? 0 : 0.35)
        chick.scale = icon ? SCNVector3(1, 1, 1) : SCNVector3(0.72, 0.72, 0.72)
        chick.simdEulerAngles.y = 0.18; root.addChildNode(chick)
        if icon {
            let (minimum, maximum) = chick.boundingBox
            let height = Float(maximum.y - minimum.y)
            let centerY = Float(maximum.y + minimum.y) * 0.5
            camera.camera?.orthographicScale = Double(max(1.48, height * 0.58))
            camera.position = SCNVector3(2.1, centerY + 1.25, 7)
            camera.look(at: SCNVector3(0, centerY, 0))
        }
        // Animation belongs to the visible room's behavior controller, never asset rendering.
        return scene
    }

    static func itemScene(id: String, slot: String) -> SCNScene {
        if slot == "bg" { return make(equipped: [slot: id], animated: false) }
        let scene = make(equipped: [:], animated: false, icon: true)
        for node in scene.rootNode.childNodes where node.camera == nil && node.light == nil {
            node.removeFromParentNode()
        }
        let content: SCNNode
        switch slot {
        case "bodyFront", "headTop", "eyes", "neck": content = character(equipped: [slot: id])
        case "bigFurniture": content = furniture(id)
        case "wallDeco": content = wallDecoration(id); content.position = SCNVector3Zero
        case "rug": content = rug(id); content.position = SCNVector3Zero
        default: content = floorProp(id)
        }
        scene.rootNode.addChildNode(content)
        // Fit the actual model, including tall hats and lamp shades. A shared fixed crop cut them off.
        if let camera = scene.rootNode.childNodes.first(where: { $0.camera != nil }) {
            let (minimum, maximum) = content.boundingBox
            let low = V(Float(minimum.x), Float(minimum.y), Float(minimum.z))
            let high = V(Float(maximum.x), Float(maximum.y), Float(maximum.z))
            let center = (low + high) * 0.5; let extent = high - low
            let radius = max(extent.y * 0.60, sqrt(extent.x * extent.x + extent.z * extent.z) * 0.59)
            camera.camera?.orthographicScale = Double(max(radius + 0.10, 0.45))
            camera.position = SCNVector3(center.x + 2.7, center.y + 2.1, center.z + 6)
            camera.look(at: SCNVector3(center.x, center.y, center.z))
        }
        return scene
    }

    private static func room(_ root: SCNNode, equipped: [String: String]) {
        let theme = equipped["bg"] ?? "bg.cozy_cream"
        let wall: UInt
        switch theme {
        case "bg.night_sky": wall = 0x7880BC
        case "bg.sky_blue": wall = 0xBCE5F5
        case "bg.sakura_pink": wall = 0xF8CEDE
        case "bg.lavender": wall = 0xD8CCF4
        case "bg.mint_garden": wall = 0xB9E6D0
        case "bg.forest": wall = 0x9AC8AD
        case "bg.ocean": wall = 0x9CDADA
        case "bg.sunset": wall = 0xFAC69E
        default: wall = 0xF3E5CB
        }
        add(box(4.8, 0.3, 3.9, 0.14, 0xE8C6A0), to: root, at: (0, -0.18, 0))
        add(box(4.8, 2.95, 0.15, 0.05, wall), to: root, at: (0, 1.18, -1.9))
        add(box(0.15, 1.3, 3.9, 0.05, wall), to: root, at: (-2.33, 0.42, 0))
        add(box(4.62, 0.16, 0.065, 0.025, 0xFFF6DF), to: root, at: (0, 0.07, -1.78))
        add(box(0.065, 0.16, 3.65, 0.025, 0xFFF6DF), to: root, at: (-2.23, 0.07, 0))
        for x in stride(from: -1.8, through: 1.8, by: 0.6) {
            add(box(0.009, 0.005, 3.64, 0, 0xD5B38D), to: root, at: (Float(x), -0.025, 0))
        }
        let night = theme == "bg.night_sky"
        add(box(1.3, 1.5, 0.15, 0.075, 0xFFFFF3), to: root, at: (0.42, 1.65, -1.76))
        add(box(1.08, 1.28, 0.04, 0.018, night ? 0x343C6B : 0xB8E7F2), to: root, at: (0.42, 1.65, -1.66))
        add(sphere(0.16, night ? 0xFFF2B7 : 0xFFE684), to: root, at: (0.66, 1.96, -1.58))
        if night {
            for p: (Float, Float) in [(-0.01, 1.94), (0.2, 2.14), (0.76, 1.49), (0.1, 1.31)] {
                add(star(radius: 0.045, depth: 0.015, tint: 0xFFF5CE), to: root, at: (p.0, p.1, -1.59))
            }
        } else {
            for x: Float in [0.08, 0.26, 0.4] {
                add(ellipsoid(0.18, 0.07, 0.035, 0xF7FFFF), to: root, at: (x, 1.79, -1.58))
            }
        }
        add(box(1.17, 0.055, 0.095, 0.02, 0xFFFFF3), to: root, at: (0.42, 1.63, -1.57))
        add(box(0.055, 1.28, 0.095, 0.02, 0xFFFFF3), to: root, at: (0.42, 1.65, -1.57))
        add(box(1.42, 0.11, 0.38, 0.045, 0xFFF3D8), to: root, at: (0.42, 0.94, -1.62))
        if let id = equipped["rug"] { let model = rug(id); model.name = "room.rug"; root.addChildNode(model) }
        if let id = equipped["floorProp"] {
            let prop = floorProp(id); prop.name = "room.prop"
            add(prop, to: root, at: (1.65, 0, 0.5))
        }
        if let id = equipped["bigFurniture"] {
            let model = furniture(id); model.name = "room.furniture"
            add(model, to: root, at: (-1.45, 0, -0.9))
        }
        if let id = equipped["wallDeco"] { let model = wallDecoration(id); model.name = "room.wall"; root.addChildNode(model) }
    }

    private static func character(equipped: [String: String]) -> SCNNode {
        let chick = SCNNode(); chick.name = "piyak"
        let body = SCNNode(); body.name = "bodyRig"
        let head = SCNNode(); head.name = "headRig"
        add(ellipsoid(0.68, 0.73, 0.55, yellow), to: body, at: (0, 0.82, 0))
        add(ellipsoid(0.76, 0.7, 0.65, yellow), to: head, at: (0, 1.66, 0))
        for side: Float in [-1, 1] {
            let wing = SCNNode(); wing.name = side < 0 ? "wing.left" : "wing.right"
            wing.simdEulerAngles.z = side * 0.22
            add(ellipsoid(0.18, 0.34, 0.205, yellow), to: wing, at: (0, -0.19, 0))
            if let id = equipped["bodyFront"], let tint = sleeveTint(id) {
                add(ellipsoid(0.195, 0.18, 0.22, tint), to: wing, at: (0, -0.07, 0))
            }
            add(wing, to: body, at: (side * 0.64, 1.04, 0.005))
            let foot = SCNNode(); foot.name = side < 0 ? "foot.left" : "foot.right"
            foot.addChildNode(ellipsoid(0.23, 0.095, 0.29, 0xF2A052))
            for dx: Float in [-0.075, 0.075] {
                let seam = tube([V(dx, 0.04, 0.17), V(dx, 0.038, 0.235)], radius: 0.008, tint: 0xDC873F)
                foot.addChildNode(seam)
            }
            add(foot, to: chick, at: (side * 0.28, 0.10, 0.18))
            add(ellipsoid(0.14, 0.075, 0.026, 0xF3A193), to: head, at: (side * 0.46, 1.47, 0.535))
        }
        let eyes = SCNNode(); eyes.name = "eyes"
        for side: Float in [-1, 1] {
            add(ellipsoid(0.061, 0.087, 0.041, 0x35334D), to: eyes, at: (side * 0.245, 0, 0.607))
            add(sphere(0.019, 0xFFFFFF), to: eyes, at: (side * 0.245 - 0.012, 0.029, 0.64))
        }
        add(eyes, to: head, at: (0, 1.74, 0))
        add(ellipsoid(0.185, 0.085, 0.165, 0xF4A34F), to: head, at: (0, 1.515, 0.65))
        add(tube([V(-0.10, 1.487, 0.755), V(0, 1.478, 0.805), V(0.10, 1.487, 0.755)], radius: 0.007, tint: 0xD1833E), to: head, at: (0, 0, 0))
        // Hair is hidden under fitted hats; it must not poke through a cap or crown.
        if equipped["headTop"] == nil || equipped["headTop"] == "headTop.flower" {
            for side: Float in [-1, 1] {
                let tuft = ellipsoid(0.072, 0.19, 0.07, yellow); tuft.simdEulerAngles.z = side * 0.55
                add(tuft, to: head, at: (side * 0.07, 2.33, -0.02))
            }
        }
        if let id = equipped["bodyFront"] { outfit(id, on: body) }
        if let id = equipped["headTop"] { hat(id, on: head) }
        if let id = equipped["eyes"] { glasses(id, on: head) }
        if let id = equipped["neck"] { neckwear(id, on: body) }
        recenter(body, pivot: V(0, 0.82, 0)); recenter(head, pivot: V(0, 1.66, 0))
        chick.addChildNode(body); chick.addChildNode(head)
        return chick
    }

    private static func sleeveTint(_ id: String) -> UInt? {
        switch id {
        case "bodyFront.hoodie_mint": return 0x76CFB8
        case "bodyFront.stripe_tee": return 0xFFF6DF
        case "bodyFront.sweater": return 0xDCA1B8
        case "bodyFront.raincoat": return 0xE9BC40
        case "bodyFront.pajama": return 0xBDAEE4
        case "bodyFront.graduation_gown": return 0x41405B
        default: return nil
        }
    }

    private static func outfit(_ id: String, on root: SCNNode) {
        let tint: UInt
        switch id {
        case "bodyFront.hoodie_mint": tint = 0x76CFB8
        case "bodyFront.stripe_tee": tint = 0xFFF6DF
        case "bodyFront.overalls": tint = 0x749ED1
        case "bodyFront.sweater": tint = 0xDCA1B8
        case "bodyFront.raincoat": tint = 0xE9BC40
        case "bodyFront.pajama": tint = 0xBDAEE4
        case "bodyFront.padding_vest": tint = 0xE99A78
        default: tint = 0x41405B
        }
        let overall = id == "bodyFront.overalls"
        root.addChildNode(cloth(y: 0.27...(overall ? 0.86 : 1.28), tint: tint))
        root.addChildNode(cloth(y: 0.28...0.335, lift: 0.039, tint: darker(tint, by: 0.88)))
        if !overall { root.addChildNode(cloth(y: 1.235...1.285, lift: 0.04, tint: darker(tint, by: 0.86))) }
        switch id {
        case "bodyFront.hoodie_mint":
            let hood = ellipsoid(0.46, 0.31, 0.39, 0x68BDA8)
            add(hood, to: root, at: (0, 1.20, -0.22))
            root.addChildNode(frontPatch(roundedRect(x: -0.26, y: 0.53, width: 0.52, height: 0.22, radius: 0.08), lift: 0.052, tint: 0x69BFA9))
            root.addChildNode(frontLine([(-0.23, 0.61), (-0.13, 0.73), (0.13, 0.73), (0.23, 0.61)], lift: 0.059, radius: 0.009, tint: 0xB7E8D8))
            for x: Float in [-0.13, 0.13] {
                root.addChildNode(frontLine([(x, 1.21), (x * 1.05, 1.1), (x * 1.2, 0.99)], lift: 0.047, radius: 0.013, tint: 0xFFF1D9))
                add(sphere(0.022, 0xE8D9BC), to: root, at: tuple(front(V(x * 1.2, 0.99, 0), lift: 0.062)))
            }
        case "bodyFront.stripe_tee":
            for y: Float in [0.42, 0.63, 0.84, 1.05] { root.addChildNode(cloth(y: y...(y + 0.072), lift: 0.041, tint: 0x6084B0)) }
            root.addChildNode(frontPatch(roundedRect(x: 0.18, y: 0.87, width: 0.19, height: 0.21, radius: 0.035), lift: 0.053, tint: 0xFFF4DD))
            root.addChildNode(frontLine([(0.2, 1.045), (0.35, 1.045)], lift: 0.06, radius: 0.008, tint: 0xC0B8A8))
        case "bodyFront.overalls":
            root.addChildNode(frontPatch(roundedRect(x: -0.31, y: 0.73, width: 0.62, height: 0.37, radius: 0.075), lift: 0.052, tint: tint))
            for x: Float in [-0.24, 0.24] {
                root.addChildNode(frontPatch(roundedRect(x: x - 0.055, y: 0.97, width: 0.11, height: 0.3, radius: 0.035), lift: 0.055, tint: 0x5C83B5))
                add(sphere(0.038, 0xF2CB66), to: root, at: tuple(front(V(x, 1.025, 0), lift: 0.069)))
            }
            root.addChildNode(frontPatch(roundedRect(x: -0.15, y: 0.78, width: 0.3, height: 0.18, radius: 0.04), lift: 0.071, tint: 0x86ADD8))
            root.addChildNode(frontLine([(-0.135, 0.935), (-0.135, 0.81), (0, 0.795), (0.135, 0.81), (0.135, 0.935)], lift: 0.078, radius: 0.006, tint: 0xE2CCA0))
            root.addChildNode(frontLine([(0, 0.3), (0, 0.6)], lift: 0.043, radius: 0.009, tint: 0x5279A7))
        case "bodyFront.sweater":
            for y: Float in [0.65, 0.9] {
                let points = (0...24).map { i -> (Float, Float) in
                    let x = Float(i) / 24 * 1.0 - 0.5
                    return (x, y + (i % 2 == 0 ? 0.035 : -0.035))
                }
                root.addChildNode(frontLine(points, lift: 0.045, radius: 0.012, tint: 0xF5D5D4))
            }
            for x: Float in [-0.42, -0.28, -0.14, 0, 0.14, 0.28, 0.42] {
                root.addChildNode(frontLine([(x * 0.9, 0.33), (x, 0.43)], lift: 0.047, radius: 0.008, tint: 0xBE829D))
            }
        case "bodyFront.raincoat":
            add(ellipsoid(0.47, 0.29, 0.4, 0xDBA931), to: root, at: (0, 1.21, -0.23))
            root.addChildNode(frontLine([(0, 0.34), (0, 1.21)], lift: 0.052, radius: 0.014, tint: 0xC18F21))
            for side: Float in [-1, 1] {
                root.addChildNode(frontPatch([(side * 0.05, 1.24), (side * 0.34, 1.20), (side * 0.22, 1.06)], lift: 0.067, tint: 0xF6D76C))
                root.addChildNode(frontPatch(roundedRect(x: side * 0.29 - 0.10, y: 0.54, width: 0.20, height: 0.18, radius: 0.035), lift: 0.061, tint: 0xF1CB57))
            }
            for y: Float in [0.55, 0.79, 1.02] { add(sphere(0.025, 0xFFF2D0), to: root, at: tuple(front(V(0.04, y, 0), lift: 0.064))) }
        case "bodyFront.suit_vest", "bodyFront.graduation_gown":
            root.addChildNode(frontPatch([(-0.25, 1.28), (0.25, 1.28), (0, 0.86)], lift: 0.048, tint: 0xFFF4DE))
            for side: Float in [-1, 1] {
                let panel: [(Float, Float)]
                if id == "bodyFront.graduation_gown" {
                    panel = [(side * 0.23, 1.26), (side * 0.36, 1.21), (side * 0.25, 0.42), (side * 0.11, 0.43)]
                } else {
                    panel = [(side * 0.27, 1.28), (side * 0.43, 1.10), (side * 0.15, 0.89), (side * 0.27, 1.10)]
                }
                root.addChildNode(frontPatch(panel, lift: 0.065, tint: id == "bodyFront.graduation_gown" ? 0xE4C464 : 0x68677D))
            }
            root.addChildNode(frontPatch([(-0.06, 1.2), (0.06, 1.2), (0.055, 1.10), (0, 0.92), (-0.055, 1.10)], lift: 0.07, tint: 0xB97F8D))
            if id == "bodyFront.suit_vest" {
                for y: Float in [0.59, 0.76, 0.9] { add(sphere(0.024, 0xB9BAC6), to: root, at: tuple(front(V(0, y, 0), lift: 0.064))) }
                root.addChildNode(frontLine([(0.23, 0.75), (0.39, 0.77)], lift: 0.05, radius: 0.013, tint: 0x8B8B9E))
            }
        case "bodyFront.pajama":
            root.addChildNode(frontLine([(0.015, 0.34), (0.015, 1.24)], lift: 0.05, radius: 0.012, tint: 0xEDE4FC))
            for y: Float in [0.57, 0.82, 1.05] { add(sphere(0.025, 0xFFF4E2), to: root, at: tuple(front(V(0.065, y, 0), lift: 0.062))) }
            for side: Float in [-1, 1] { root.addChildNode(frontPatch([(0, 1.26), (side * 0.31, 1.22), (side * 0.17, 1.03)], lift: 0.065, tint: 0xD8CAEF)) }
            for p: (Float, Float) in [(-0.3, 0.62), (0.3, 0.84), (-0.29, 0.97), (0.28, 0.46)] {
                let moon = sphere(0.035, 0xFFF0C9); add(moon, to: root, at: tuple(front(V(p.0, p.1, 0), lift: 0.062)))
            }
        case "bodyFront.padding_vest":
            for y: Float in [0.49, 0.72, 0.95] { root.addChildNode(cloth(y: y...(y + 0.025), lift: 0.045, tint: 0xCB7E60)) }
            root.addChildNode(frontLine([(0, 0.31), (0, 1.24)], lift: 0.06, radius: 0.015, tint: 0x745A57))
            add(box(0.05, 0.085, 0.025, 0.01, 0xFFF1CC), to: root, at: tuple(front(V(0, 1.1, 0), lift: 0.075)))
            for side: Float in [-1, 1] { root.addChildNode(frontLine([(side * 0.25, 0.49), (side * 0.36, 0.68)], lift: 0.05, radius: 0.013, tint: 0xAD705B)) }
        default: break
        }
    }

    private static func hat(_ id: String, on root: SCNNode) {
        switch id {
        case "headTop.flower":
            let flower = SCNNode(); flower.simdEulerAngles.z = -0.25
            for i in 0..<6 {
                let a = Float(i) * .pi / 3
                let petal = ellipsoid(0.1, 0.15, 0.065, 0xE990B0); petal.simdEulerAngles.z = -a
                add(petal, to: flower, at: (sin(a) * 0.145, cos(a) * 0.145, 0))
            }
            add(sphere(0.10, 0xFFE081), to: flower, at: (0, 0, 0.065))
            let leaf = ellipsoid(0.075, 0.18, 0.035, 0x75AD81); leaf.simdEulerAngles.z = 0.8
            add(leaf, to: flower, at: (-0.16, -0.1, -0.045))
            add(flower, to: root, at: (0.44, 2.18, 0.30))
        case "headTop.straw_hat":
            add(cylinder(0.8, 0.06, 0xE4C181), to: root, at: (0, 2.18, 0))
            add(ellipsoid(0.52, 0.33, 0.48, 0xEDCC8E), to: root, at: (0, 2.30, 0))
            for r: Float in [0.59, 0.68, 0.76] { root.addChildNode(ellipseLine(rx: r, rz: r, y: 2.217, radius: 0.007, tint: 0xCCAA71)) }
            root.addChildNode(ellipseLine(rx: 0.515, rz: 0.475, y: 2.29, radius: 0.04, tint: 0xBB7968))
            add(ellipsoid(0.13, 0.08, 0.055, 0xD78B78), to: root, at: (0.28, 2.30, 0.42))
        case "headTop.beret":
            let cap = ellipsoid(0.63, 0.20, 0.54, 0xBF776B); cap.simdEulerAngles.z = -0.16
            add(cap, to: root, at: (0.025, 2.29, 0))
            root.addChildNode(ellipseLine(rx: 0.53, rz: 0.46, y: 2.18, radius: 0.035, tint: 0xA75F56))
            add(cylinder(0.04, 0.095, 0xA75F56), to: root, at: (0.03, 2.52, 0))
        case "headTop.party_cone", "headTop.wizard_hat":
            let wizard = id == "headTop.wizard_hat"
            let tint: UInt = wizard ? 0x7164AC : 0xEA92B4
            add(cylinder(wizard ? 0.66 : 0.46, 0.065, tint), to: root, at: (0, 2.18, 0))
            add(cone(0.045, 0.44, 0.91, tint), to: root, at: (0, 2.63, 0))
            root.addChildNode(ellipseLine(rx: 0.42, rz: 0.42, y: 2.27, radius: 0.035, tint: wizard ? 0xA397D2 : 0xF7D193))
            for (x, y, z): (Float, Float, Float) in [(-0.11, 2.48, 0.28), (0.08, 2.75, 0.17), (0.22, 2.38, 0.29)] {
                add(wizard ? star(radius: 0.07, depth: 0.025, tint: 0xF5D677) : sphere(0.045, 0xFFF2CA), to: root, at: (x, y, z))
            }
            add(sphere(0.09, wizard ? 0xF5D677 : 0xFFF0D4), to: root, at: (0, 3.09, 0))
        case "headTop.crown":
            add(node(SCNTube(innerRadius: 0.43, outerRadius: 0.50, height: 0.18), 0xEBC25B, metallic: 0.38), to: root, at: (0, 2.25, 0))
            for i in 0..<7 {
                let a = Float(i) * .pi * 2 / 7
                add(cone(0.012, 0.10, 0.24, 0xEBC25B), to: root, at: (sin(a) * 0.45, 2.43, cos(a) * 0.45))
                add(sphere(0.04, 0xF8DF8B), to: root, at: (sin(a) * 0.45, 2.56, cos(a) * 0.45))
                add(sphere(0.045, i % 2 == 0 ? 0xC97099 : 0x79B9B5), to: root, at: (sin(a) * 0.50, 2.25, cos(a) * 0.50))
            }
        case "headTop.beanie":
            add(ellipsoid(0.60, 0.40, 0.54, 0xDF957E), to: root, at: (0, 2.27, 0))
            root.addChildNode(ellipseLine(rx: 0.55, rz: 0.49, y: 2.18, radius: 0.075, tint: 0xCE806B))
            for i in 0..<16 {
                let a = Float(i) * .pi * 2 / 16
                let pts = (0...12).map { j -> V in
                    let t = Float(j) / 12 * 1.25 + 0.08
                    return V(sin(a) * cos(t) * 0.608, 2.27 + sin(t) * 0.405, cos(a) * cos(t) * 0.548)
                }
                root.addChildNode(tube(pts, radius: 0.007, tint: 0xE9AC95))
            }
            add(sphere(0.14, 0xFFF0D6), to: root, at: (0, 2.74, 0))
        case "headTop.cap":
            add(ellipsoid(0.61, 0.30, 0.55, 0x7499D0), to: root, at: (0, 2.25, 0))
            root.addChildNode(ellipseLine(rx: 0.57, rz: 0.52, y: 2.18, radius: 0.035, tint: 0x557EBA))
            add(ellipsoid(0.48, 0.046, 0.36, 0x6488C0), to: root, at: (0, 2.18, 0.50))
            add(sphere(0.045, 0x4F73AC), to: root, at: (0, 2.55, 0))
            let badge = star(radius: 0.08, depth: 0.018, tint: 0xFFF1C6)
            badge.simdEulerAngles.x = -0.2; add(badge, to: root, at: (0, 2.35, 0.535))
        case "headTop.chef_hat":
            add(cylinder(0.47, 0.27, 0xF7EFD9), to: root, at: (0, 2.29, 0))
            for p: (Float, Float, Float) in [(-0.27, 2.60, 0), (0, 2.69, 0.08), (0.28, 2.61, 0), (0, 2.58, -0.21)] {
                add(sphere(0.29, 0xFFF9E9), to: root, at: p)
            }
            root.addChildNode(ellipseLine(rx: 0.473, rz: 0.473, y: 2.21, radius: 0.016, tint: 0xE2D7BD))
        default: break
        }
    }

    private static func glasses(_ id: String, on root: SCNNode) {
        let tint: UInt = id == "eyes.glasses_red" || id == "eyes.heart_glasses" ? 0xCE6278 :
            id == "eyes.glasses_blue" ? 0x4B7CB4 : id == "eyes.star_glasses" || id == "eyes.monocle" ? 0xCBA64F : 0x454457
        let single = id == "eyes.monocle" || id == "eyes.eyepatch"
        for side: Float in single ? [-1] : [-1, 1] {
            let center = V(side * 0.26, 1.745, 0)
            let outline: [(Float, Float)]
            switch id {
            case "eyes.heart_glasses": outline = heartPoints(size: 0.37).map { (Float($0.x), Float($0.y) + 0.015) }
            case "eyes.star_glasses": outline = starPoints(radius: 0.205).map { (Float($0.x), Float($0.y)) }
            case "eyes.sunglasses", "eyes.glasses_red", "eyes.glasses_blue", "eyes.eyepatch", "eyes.goggles":
                outline = roundedRect(x: -0.18, y: -0.13, width: 0.36, height: 0.26, radius: id == "eyes.goggles" ? 0.10 : 0.065)
            default: outline = (0..<40).map { i in let a = Float(i) * .pi / 20; return (cos(a) * 0.155, sin(a) * 0.155) }
            }
            let points = outline.map { headSurface(x: $0.0 + center.x, y: $0.1 + center.y, lift: 0.056) }
            let darkLens = id == "eyes.sunglasses" || id == "eyes.eyepatch"
            let lens = surfaceFan(points, tint: darkLens ? 0x393A55 : 0xBBDCE6)
            lens.geometry?.firstMaterial?.transparency = darkLens ? 0.95 : (id == "eyes.goggles" ? 0.36 : 0.10)
            lens.geometry?.firstMaterial?.writesToDepthBuffer = darkLens
            root.addChildNode(lens)
            root.addChildNode(tube(points + [points[0]], radius: id == "eyes.goggles" ? 0.034 : 0.023, tint: tint))
            if id == "eyes.monocle" {
                root.addChildNode(tube([V(-0.37, 1.60, 0.57), V(-0.48, 1.4, 0.48), V(-0.45, 1.23, 0.44), V(-0.28, 1.15, 0.53)], radius: 0.009, tint: tint))
            }
        }
        if !single {
            root.addChildNode(tube([headSurface(x: -0.09, y: 1.76, lift: 0.06), headSurface(x: 0, y: 1.80, lift: 0.06), headSurface(x: 0.09, y: 1.76, lift: 0.06)], radius: 0.018, tint: tint))
        }
        if id == "eyes.eyepatch" || id == "eyes.goggles" {
            let points = (0...64).map { i -> V in
                let a = Float(i) / 64 * .pi * 2
                return V(sin(a) * 0.745, 1.75, cos(a) * 0.645)
            }
            root.addChildNode(tube(points, radius: id == "eyes.goggles" ? 0.025 : 0.014, tint: tint))
        } else if id != "eyes.monocle" {
            for side: Float in [-1, 1] {
                root.addChildNode(tube([headSurface(x: side * 0.43, y: 1.77, lift: 0.06), V(side * 0.65, 1.76, 0.37), V(side * 0.74, 1.69, 0.09)], radius: 0.018, tint: tint))
            }
        }
    }

    private static func neckwear(_ id: String, on root: SCNNode) {
        switch id {
        case "neck.scarf_coral", "neck.scarf_mint":
            let tint: UInt = id == "neck.scarf_mint" ? 0x66BBA6 : 0xE08B91
            root.addChildNode(cloth(y: 1.15...1.28, lift: 0.089, tint: tint))
            root.addChildNode(frontPatch(roundedRect(x: 0.04, y: 0.79, width: 0.20, height: 0.40, radius: 0.04), lift: 0.10, tint: tint))
            root.addChildNode(frontPatch(roundedRect(x: -0.21, y: 0.88, width: 0.17, height: 0.32, radius: 0.04), lift: 0.09, tint: darker(tint, by: 0.9)))
            for x: Float in [0.075, 0.12, 0.165, 0.21] { root.addChildNode(frontLine([(x, 0.8), (x, 0.86)], lift: 0.109, radius: 0.008, tint: darker(tint, by: 0.8))) }
        case "neck.ribbon", "neck.bowtie":
            let ribbon = id == "neck.ribbon"
            let tint: UInt = ribbon ? 0xD98CA4 : 0x71628F
            for side: Float in [-1, 1] {
                let bow = ellipsoid(0.16, 0.105, 0.065, tint); bow.simdEulerAngles.z = side * 0.26
                add(bow, to: root, at: (side * 0.15, 1.24, 0.545))
                if ribbon { root.addChildNode(frontPatch([(side * 0.04, 1.2), (side * 0.20, 1.15), (side * 0.23, 0.99), (side * 0.10, 1.02)], lift: 0.085, tint: tint)) }
            }
            add(ellipsoid(0.07, 0.085, 0.08, darker(tint, by: 0.85)), to: root, at: (0, 1.24, 0.59))
        case "neck.bandana":
            root.addChildNode(cloth(y: 1.20...1.27, lift: 0.077, tint: 0xD17979))
            root.addChildNode(frontPatch([(-0.36, 1.23), (0.36, 1.23), (0.06, 0.91)], lift: 0.094, tint: 0xD98B85))
            root.addChildNode(frontLine([(-0.29, 1.20), (0.055, 0.965), (0.30, 1.20)], lift: 0.10, radius: 0.009, tint: 0xF7DCCD))
        case "neck.tie":
            root.addChildNode(cloth(y: 1.21...1.27, lift: 0.076, tint: 0x7B6AAB))
            root.addChildNode(frontPatch([(-0.075, 1.2), (0.075, 1.2), (0.045, 1.10), (0.10, 0.82), (0, 0.72), (-0.1, 0.82), (-0.045, 1.10)], lift: 0.091, tint: 0x79639F))
            root.addChildNode(frontLine([(-0.04, 0.94), (0.05, 0.88)], lift: 0.102, radius: 0.016, tint: 0xAB92C4))
        case "neck.gold_chain", "neck.pearl", "neck.bell":
            let pearl = id == "neck.pearl"
            let tint: UInt = pearl ? 0xFFF2D8 : 0xDDB652
            let points = (0...32).map { i -> V in
                let t = Float(i) / 32 * .pi
                let x = cos(t) * 0.48; let y = 1.28 - sin(t) * 0.24
                return front(V(x, y, 0), lift: 0.088)
            }
            root.addChildNode(tube(points, radius: 0.016, tint: tint))
            if pearl {
                for i in stride(from: 0, through: 32, by: 2) { add(sphere(0.039, tint), to: root, at: tuple(points[i])) }
            } else if id == "neck.gold_chain" {
                for i in stride(from: 0, through: 32, by: 2) {
                    let link = node(SCNTorus(ringRadius: 0.033, pipeRadius: 0.009), tint, metallic: 0.55)
                    link.simdEulerAngles.x = .pi / 2; add(link, to: root, at: tuple(points[i]))
                }
            } else {
                let bell = SCNNode(); bell.name = "neck.bell"
                add(sphere(0.092, 0xEDC45A), to: bell, at: (0, 0, 0))
                add(cylinder(0.095, 0.027, 0xC9A144), to: bell, at: (0, -0.038, 0))
                add(sphere(0.018, 0x776247), to: bell, at: (0, -0.041, 0.085))
                add(bell, to: root, at: tuple(points[16] + V(0, -0.09, 0.02)))
            }
        default: break
        }
    }

    private static func furniture(_ id: String) -> SCNNode {
        let root = SCNNode()
        let approach = SCNNode(); approach.name = "interaction.furniture"
        add(approach, to: root, at: (0, 0, 0.95))
        let contact = SCNNode(); contact.name = "interaction.furniture.contact"
        add(contact, to: root, at: (0, id == "bigFurniture.piano" ? 0.74 : 0.90,
                                  id == "bigFurniture.piano" ? 0.40 : 0.34))
        switch id {
        case "bigFurniture.bookshelf":
            add(box(1.18, 1.56, 0.095, 0.03, 0xAA815F), to: root, at: (0, 0.84, -0.22))
            for x: Float in [-0.55, 0.55] { add(box(0.11, 1.6, 0.56, 0.035, 0xCDA47B), to: root, at: (x, 0.84, 0)) }
            for y: Float in [0.10, 0.59, 1.08, 1.59] {
                add(box(1.19, 0.085, 0.58, 0.025, 0xDCB68B), to: root, at: (0, y, 0))
            }
            for (row, y) in [Float(0.33), 0.82, 1.31].enumerated() {
                for (i, tint) in [UInt(0x8AACAA), 0xA59BC4, 0xE0BA79, 0xD1948A].enumerated() {
                    let book = standingBook(width: 0.14, height: i % 2 == 0 ? 0.34 : 0.39, tint: tint)
                    if i == 3 && row == 1 { book.simdEulerAngles.z = 0.13 }
                    add(book, to: root, at: (Float(i) * 0.20 - 0.32, y, 0.08))
                }
            }
        case "bigFurniture.shelf":
            for y: Float in [0.6, 1.16] {
                add(box(1.30, 0.085, 0.46, 0.026, 0xD9B58E), to: root, at: (0, y, -0.55))
                for x: Float in [-0.47, 0.47] {
                    root.addChildNode(tube([V(x, y - 0.24, -0.79), V(x, y - 0.035, -0.39), V(x, y + 0.13, -0.79)], radius: 0.02, tint: 0x9B8773))
                }
            }
            for (i, tint) in [UInt(0xB693BA), 0x7EAFA6, 0xDCA982].enumerated() {
                add(standingBook(width: 0.12, height: 0.28 + Float(i) * 0.03, tint: tint), to: root, at: (Float(i) * 0.14 - 0.25, 0.80, -0.55))
            }
            let pot = floorProp("floorProp.plant"); pot.scale = SCNVector3(0.40, 0.40, 0.40)
            add(pot, to: root, at: (0.31, 1.21, -0.55))
            add(box(0.24, 0.30, 0.035, 0.014, 0xFFEFCE), to: root, at: (-0.3, 1.35, -0.68))
            add(heart(size: 0.11, depth: 0.015, tint: 0xDB9AA7), to: root, at: (-0.30, 1.35, -0.65))
        case "bigFurniture.sofa":
            for x: Float in [-0.48, 0.48] { for z: Float in [-0.22, 0.22] { add(cone(0.048, 0.038, 0.20, 0xAE886A), to: root, at: (x, 0.1, z)) } }
            add(box(1.29, 0.28, 0.77, 0.12, 0x87AA9B), to: root, at: (0, 0.30, 0))
            add(box(1.23, 0.64, 0.22, 0.10, 0xA8C4B5), to: root, at: (0, 0.68, -0.28))
            for x: Float in [-0.3, 0.3] { add(box(0.56, 0.17, 0.63, 0.075, 0xACCABC), to: root, at: (x, 0.47, 0.05)) }
            for x: Float in [-0.62, 0.62] { add(box(0.18, 0.43, 0.78, 0.085, 0x91B6A5), to: root, at: (x, 0.48, 0)) }
            let pillow = box(0.32, 0.32, 0.13, 0.062, 0xE8BE94); pillow.eulerAngles = SCNVector3(-0.2, 0, -0.2)
            add(pillow, to: root, at: (0.39, 0.68, -0.05))
            let seat = SCNNode(); seat.name = "interaction.seat"; add(seat, to: root, at: (-0.12, 0.49, 0.13))
        case "bigFurniture.nightstand":
            for x: Float in [-0.36, 0.36] { for z: Float in [-0.21, 0.21] { add(cylinder(0.042, 0.15, 0xA07A5C), to: root, at: (x, 0.075, z)) } }
            add(box(0.91, 0.53, 0.58, 0.045, 0xCBA782), to: root, at: (0, 0.40, 0))
            add(box(1.0, 0.085, 0.66, 0.032, 0xE5C59F), to: root, at: (0, 0.70, 0))
            for y: Float in [0.285, 0.525] {
                add(box(0.78, 0.21, 0.05, 0.023, 0xDBB98F), to: root, at: (0, y, 0.30))
                add(sphere(0.034, 0xAA8055), to: root, at: (0, y, 0.35))
            }
            let lamp = floorProp("floorProp.lamp"); lamp.scale = SCNVector3(0.32, 0.32, 0.32)
            add(lamp, to: root, at: (0.23, 0.75, -0.08))
            add(book(width: 0.33, tint: 0x9FAAC8), to: root, at: (-0.20, 0.76, 0.02))
        case "bigFurniture.wardrobe":
            add(box(1.24, 1.58, 0.67, 0.065, 0xBD9873), to: root, at: (0, 0.85, 0))
            add(box(1.34, 0.11, 0.74, 0.045, 0xDBB78E), to: root, at: (0, 1.65, 0))
            for x: Float in [-0.29, 0.29] {
                add(box(0.56, 1.39, 0.06, 0.026, 0xDDC09B), to: root, at: (x, 0.87, 0.36))
                add(box(0.41, 0.96, 0.025, 0.01, 0xCEAC84), to: root, at: (x, 0.94, 0.40))
                add(box(0.34, 0.89, 0.02, 0.009, 0xDFC19D), to: root, at: (x, 0.94, 0.42))
                add(capsule(0.023, 0.15, 0xA0784F), to: root, at: (x < 0 ? -0.075 : 0.075, 0.86, 0.44))
            }
            for x: Float in [-0.48, 0.48] { add(box(0.14, 0.13, 0.52, 0.03, 0xA88160), to: root, at: (x, 0.06, 0)) }
        case "bigFurniture.piano":
            add(box(1.30, 1.1, 0.45, 0.065, 0x525065), to: root, at: (0, 0.62, -0.12))
            add(box(1.34, 0.075, 0.5, 0.026, 0x70697D), to: root, at: (0, 1.19, -0.12))
            add(box(1.27, 0.11, 0.49, 0.04, 0x444052), to: root, at: (0, 0.65, 0.20))
            for i in 0..<14 {
                let key = SCNNode(); key.name = "piano.key.\(i)"
                add(box(0.081, 0.035, 0.31, 0.009, 0xFFF7E2), to: key, at: (0, 0, 0.13))
                add(key, to: root, at: (Float(i) * 0.085 - 0.553, 0.733, 0.095))
                if ![2, 6, 9, 13].contains(i) {
                    add(box(0.043, 0.05, 0.19, 0.009, 0x2F2C3A), to: root, at: (Float(i) * 0.085 - 0.51, 0.775, 0.155))
                }
            }
            for x: Float in [-0.52, 0.52] { add(box(0.09, 0.54, 0.12, 0.028, 0x444052), to: root, at: (x, 0.27, 0.32)) }
            add(box(0.45, 0.29, 0.035, 0.016, 0xF5E8C6), to: root, at: (0, 0.99, 0.14))
            for x: Float in [-0.15, -0.05, 0.05, 0.15] { add(box(0.002, 0.20, 0.012, 0, 0xBAAB91), to: root, at: (x, 0.99, 0.17)) }
            add(box(0.065, 0.026, 0.17, 0.012, 0xD2AE63), to: root, at: (0, 0.09, 0.21))
        case "bigFurniture.desk":
            for x: Float in [-0.52, 0.52] { for z: Float in [-0.24, 0.24] { add(cone(0.045, 0.032, 0.82, 0xB9946C), to: root, at: (x, 0.41, z)) } }
            add(box(1.33, 0.12, 0.77, 0.045, 0xDDBD97), to: root, at: (0, 0.86, 0))
            add(box(0.69, 0.14, 0.045, 0.018, 0xC4A17B), to: root, at: (0, 0.73, 0.31))
            add(sphere(0.026, 0x8C7560), to: root, at: (0, 0.73, 0.35))
            let notebook = book(width: 0.38, tint: 0x86ADA8); notebook.simdEulerAngles.y = -0.12
            add(notebook, to: root, at: (-0.15, 0.93, 0.10))
            let pencil = capsule(0.014, 0.28, 0xEBC36A); pencil.eulerAngles = SCNVector3(.pi / 2, 0.15, 0)
            add(pencil, to: root, at: (0.14, 0.94, 0.09))
            add(cylinder(0.085, 0.17, 0xDFA6A0), to: root, at: (0.44, 1.0, -0.08))
            add(cylinder(0.067, 0.008, 0x836752), to: root, at: (0.44, 1.088, -0.08))
            let handle = node(SCNTorus(ringRadius: 0.055, pipeRadius: 0.014), 0xDFA6A0); handle.simdEulerAngles.x = .pi / 2
            add(handle, to: root, at: (0.53, 1.02, -0.08))
        case "bigFurniture.fridge":
            add(box(0.92, 1.55, 0.70, 0.10, 0x8EB9AE), to: root, at: (0, 0.80, 0))
            add(box(0.86, 0.48, 0.13, 0.06, 0xC3DED0), to: root, at: (0, 1.29, 0.34))
            add(box(0.86, 0.88, 0.13, 0.06, 0xB1D1C3), to: root, at: (0, 0.57, 0.34))
            for y: Float in [0.82, 1.17] { add(capsule(0.024, 0.17, 0xF2EBD7), to: root, at: (-0.31, y, 0.44)) }
            add(star(radius: 0.085, depth: 0.025, tint: 0xE9C16E), to: root, at: (0.17, 1.34, 0.43))
            add(box(0.16, 0.19, 0.015, 0.006, 0xFFF4CF), to: root, at: (0.10, 0.89, 0.425))
            add(sphere(0.028, 0xCE8D99), to: root, at: (0.1, 0.98, 0.44))
        case "bigFurniture.tv":
            add(box(1.3, 0.40, 0.62, 0.06, 0xCCAA89), to: root, at: (0, 0.31, 0))
            for x: Float in [-0.35, 0.35] { add(box(0.53, 0.27, 0.035, 0.016, 0xB9987B), to: root, at: (x, 0.31, 0.325)) }
            for x: Float in [-0.49, 0.49] { add(cylinder(0.045, 0.12, 0x98795E), to: root, at: (x, 0.06, 0)) }
            add(box(0.35, 0.045, 0.23, 0.022, 0x4F4C61), to: root, at: (0, 0.54, -0.02))
            add(box(0.09, 0.14, 0.075, 0.025, 0x4F4C61), to: root, at: (0, 0.61, -0.08))
            add(box(1.20, 0.77, 0.13, 0.055, 0x444256), to: root, at: (0, 1.04, -0.09))
            let screen = box(1.065, 0.63, 0.025, 0.011, 0xADC7DE); screen.name = "tv.screen"
            add(screen, to: root, at: (0, 1.04, -0.013))
            add(sphere(0.10, 0xF6D687), to: root, at: (0.31, 1.18, 0.008))
            let hill = ellipsoid(0.48, 0.18, 0.01, 0x84B7A3); add(hill, to: root, at: (-0.03, 0.865, 0.01))
            add(sphere(0.016, 0x7DD0A5), to: root, at: (0.48, 0.69, -0.012))
        default: break
        }
        return root
    }

    private static func floorProp(_ id: String) -> SCNNode {
        let root = SCNNode()
        let interaction = SCNNode(); interaction.name = "interaction.prop"
        add(interaction, to: root, at: (-0.75, 0, 0.25))
        switch id {
        case "floorProp.plant", "floorProp.cactus":
            let cactus = id == "floorProp.cactus"
            add(cone(0.24, 0.17, 0.34, cactus ? 0xD6B783 : 0xCB8A72), to: root, at: (0, 0.19, 0))
            add(node(SCNTorus(ringRadius: 0.232, pipeRadius: 0.03), cactus ? 0xE8CD9E : 0xDFA48A), to: root, at: (0, 0.36, 0))
            add(cylinder(0.212, 0.016, 0x6E5A48), to: root, at: (0, 0.36, 0))
            if cactus {
                add(capsule(0.12, 0.72, 0x7AAD87), to: root, at: (0, 0.71, 0))
                for side: Float in [-1, 1] {
                    root.addChildNode(tube([V(0, 0.60, 0), V(side * 0.22, 0.60, 0), V(side * 0.22, 0.84 + side * 0.06, 0)], radius: 0.074, tint: 0x81B88E))
                }
                for y: Float in [0.5, 0.65, 0.8, 0.95] { for x: Float in [-0.045, 0.045] { add(sphere(0.011, 0xE5E9BE), to: root, at: (x, y, 0.113)) } }
                for i in 0..<5 { let a = Float(i) * .pi * 2 / 5; add(sphere(0.045, 0xE998B4), to: root, at: (cos(a) * 0.05, 1.07, sin(a) * 0.05)) }
            } else {
                root.addChildNode(tube([V(0, 0.36, 0), V(-0.02, 0.65, 0), V(0.035, 1.02, -0.01)], radius: 0.02, tint: 0x628D64))
                for i in 0..<6 {
                    let side: Float = i % 2 == 0 ? -1 : 1
                    let leaf = SCNNode(); leaf.name = "plant.leaf.\(i)"
                    leaf.eulerAngles = SCNVector3(0.12, Float(i) * 0.8, -side * 0.72)
                    add(ellipsoid(0.105, 0.24, 0.038, i % 2 == 0 ? 0x78AC7E : 0x90BE8D), to: leaf, at: (0, 0.15, 0))
                    leaf.addChildNode(tube([V(0, 0, 0.04), V(0, 0.30, 0.04)], radius: 0.007, tint: 0xC1D9A4))
                    add(leaf, to: root, at: (0, 0.50 + Float(i) * 0.075, 0))
                }
            }
        case "floorProp.lamp":
            add(cylinder(0.255, 0.08, 0xC1AB83), to: root, at: (0, 0.05, 0))
            add(cylinder(0.032, 0.97, 0xBA9454), to: root, at: (0, 0.55, 0))
            let bulb = sphere(0.075, 0xFFE8A3); bulb.name = "lamp.bulb"
            bulb.geometry?.firstMaterial?.emission.contents = color(0xFFD87A)
            add(bulb, to: root, at: (0, 1.09, 0))
            let shade = cone(0.205, 0.37, 0.38, 0xF5DFAE); shade.name = "lamp.shade"
            add(shade, to: root, at: (0, 1.17, 0))
            root.addChildNode(ellipseLine(rx: 0.37, rz: 0.37, y: 0.985, radius: 0.018, tint: 0xE3C58B))
            root.addChildNode(ellipseLine(rx: 0.205, rz: 0.205, y: 1.36, radius: 0.014, tint: 0xE3C58B))
            root.addChildNode(tube([V(0.13, 1.04, 0), V(0.13, 0.85, 0)], radius: 0.008, tint: 0xAC8D5A))
            add(sphere(0.02, 0xAC8D5A), to: root, at: (0.13, 0.84, 0))
        case "floorProp.books":
            for (i, tint) in [UInt(0x869AC3), 0xDCA191, 0x8BB1A2].enumerated() {
                let item = book(width: 0.62 - Float(i) * 0.045, tint: tint); item.simdEulerAngles.y = Float(i - 1) * 0.16
                add(item, to: root, at: (0, Float(i) * 0.135 + 0.018, 0))
            }
        case "floorProp.balloons":
            add(box(0.24, 0.08, 0.20, 0.035, 0xD7B17A), to: root, at: (0, 0.05, 0))
            for (i, tint) in [UInt(0xDEA0BC), 0x8FCABD, 0xEFD183].enumerated() {
                let x = Float(i - 1) * 0.23; let y: Float = i == 1 ? 1.23 : 1.02
                root.addChildNode(tube([V(0, 0.06, 0), V(x * 0.5, y * 0.4, 0.02), V(x, y - 0.28, 0)], radius: 0.005, tint: 0xCEBEAB))
                let balloon = ellipsoid(0.22, 0.29, 0.22, tint); balloon.name = "balloon.\(i)"
                add(balloon, to: root, at: (x, y, 0))
                add(cone(0.03, 0.015, 0.06, tint), to: root, at: (x, y - 0.30, 0))
                add(ellipsoid(0.04, 0.085, 0.015, 0xF7EDDC), to: root, at: (x - 0.08, y + 0.10, 0.18))
            }
        case "floorProp.coin_pile":
            for (x, z, count): (Float, Float, Int) in [(-0.17, 0, 5), (0.19, -0.05, 3), (0.08, 0.27, 1)] {
                for i in 0..<count {
                    let coin = cylinder(0.175, 0.06, 0xE9BF50); coin.geometry?.firstMaterial?.metalness.contents = 0.38
                    add(coin, to: root, at: (x, Float(i) * 0.064 + 0.033, z))
                }
                let ring = node(SCNTorus(ringRadius: 0.137, pipeRadius: 0.009), 0xFFE08A)
                add(ring, to: root, at: (x, Float(count) * 0.064, z))
            }
        case "floorProp.moon_jar":
            add(ellipsoid(0.35, 0.37, 0.35, 0xF8EFD7), to: root, at: (0, 0.41, 0))
            add(cylinder(0.16, 0.11, 0xF8EFD7), to: root, at: (0, 0.76, 0))
            add(cylinder(0.13, 0.009, 0xB7A88C), to: root, at: (0, 0.819, 0))
            add(node(SCNTorus(ringRadius: 0.149, pipeRadius: 0.018), 0xFFF6E2), to: root, at: (0, 0.818, 0))
            add(cylinder(0.17, 0.05, 0xE4D8BE), to: root, at: (0, 0.047, 0))
        case "floorProp.puppy":
            add(ellipsoid(0.25, 0.29, 0.24, 0xDFBE98), to: root, at: (0, 0.34, 0))
            add(sphere(0.255, 0xE7C7A2), to: root, at: (0, 0.73, 0.025))
            for side: Float in [-1, 1] {
                let ear = ellipsoid(0.105, 0.20, 0.10, 0xA67960); ear.simdEulerAngles.z = side * 0.2
                add(ear, to: root, at: (side * 0.225, 0.75, 0.03))
                add(ellipsoid(0.105, 0.12, 0.16, 0xF0D5AE), to: root, at: (side * 0.16, 0.14, 0.16))
                add(capsule(0.067, 0.25, 0xE7C7A2), to: root, at: (side * 0.22, 0.40, 0.09))
                add(sphere(0.029, 0x413C42), to: root, at: (side * 0.09, 0.76, 0.255))
            }
            add(ellipsoid(0.14, 0.08, 0.08, 0xF5E0BD), to: root, at: (0, 0.65, 0.26))
            add(ellipsoid(0.05, 0.035, 0.033, 0x51444A), to: root, at: (0, 0.68, 0.328))
            let tail = SCNNode(); tail.name = "puppy.tail"; tail.simdEulerAngles.x = -0.6
            add(capsule(0.058, 0.26, 0xAA7C61), to: tail, at: (0, 0.09, 0))
            add(tail, to: root, at: (0, 0.35, -0.20))
            let collar = node(SCNTorus(ringRadius: 0.17, pipeRadius: 0.026), 0xB5809B)
            add(collar, to: root, at: (0, 0.53, 0.025))
            add(sphere(0.035, 0xEDCA71), to: root, at: (0, 0.51, 0.21))
        case "floorProp.toybox":
            add(box(0.73, 0.37, 0.56, 0.065, 0x9FBBCD), to: root, at: (0, 0.22, 0))
            add(box(0.61, 0.028, 0.44, 0.012, 0x557F98), to: root, at: (0, 0.418, 0))
            add(box(0.77, 0.07, 0.59, 0.027, 0xB5CED9), to: root, at: (0, 0.40, 0))
            add(box(0.20, 0.065, 0.025, 0.012, 0x7397AE), to: root, at: (0, 0.25, 0.29))
            let ball = sphere(0.18, 0xE7B675); ball.name = "toy.ball"; add(ball, to: root, at: (0.12, 0.50, 0.06))
            let block = box(0.21, 0.21, 0.21, 0.022, 0xBCA3C7); block.eulerAngles = SCNVector3(0.1, 0.3, -0.14)
            add(block, to: root, at: (-0.18, 0.50, 0.10))
            add(star(radius: 0.072, depth: 0.015, tint: 0xFFF0C7), to: root, at: (-0.16, 0.5, 0.23))
            let rabbit = SCNNode()
            add(sphere(0.12, 0xF4DFBD), to: rabbit, at: (0, 0, 0))
            for x: Float in [-0.055, 0.055] { add(ellipsoid(0.04, 0.13, 0.04, 0xF4DFBD), to: rabbit, at: (x, 0.14, 0)); add(sphere(0.012, 0x615569), to: rabbit, at: (x * 0.65, 0.02, 0.11)) }
            add(rabbit, to: root, at: (-0.03, 0.57, -0.11))
        default: break
        }
        return root
    }

    private static func rug(_ id: String) -> SCNNode {
        let root = SCNNode(); root.position = SCNVector3(0.15, 0.015, 0.4)
        func flat(_ points: [CGPoint], tint: UInt, height: Float = 0.02) {
            let model = polygon(points, depth: 0.025, tint: tint); model.simdEulerAngles.x = -.pi / 2
            add(model, to: root, at: (0, height, 0))
        }
        switch id {
        case "rug.star": flat(starPoints(radius: 1.13), tint: 0xDECA87)
        case "rug.heart": flat(heartPoints(size: 2.0), tint: 0xD99BAB)
        case "rug.leaf":
            let outline = (0...40).map { i -> CGPoint in
                let a = Float(i) * .pi / 20
                return CGPoint(x: CGFloat(sin(a) * 0.73 * (0.90 + cos(a) * 0.1)), y: CGFloat(cos(a) * 1.13))
            }
            flat(outline, tint: 0x8DB69B)
            root.addChildNode(tube([V(0, 0.043, -0.94), V(0, 0.043, 0.97)], radius: 0.014, tint: 0xBDD2AA))
            for z: Float in [-0.5, -0.15, 0.2, 0.55] { for side: Float in [-1, 1] { root.addChildNode(tube([V(0, 0.043, z - 0.12), V(side * 0.49, 0.043, z + 0.19)], radius: 0.011, tint: 0xBDD2AA)) } }
        case "rug.cloud":
            for (x, z, r): (Float, Float, CGFloat) in [(-0.63, 0, 0.40), (-0.2, -0.22, 0.53), (0.32, -0.15, 0.57), (0.73, 0.08, 0.35), (0, 0.25, 0.6)] {
                add(cylinder(r, 0.03, 0xF5EEDD), to: root, at: (x, 0.015, z))
            }
        case "rug.checker":
            flat(roundedRect(x: -1, y: -0.75, width: 2, height: 1.5, radius: 0.15).map { CGPoint(x: CGFloat($0.0), y: CGFloat($0.1)) }, tint: 0xE9D9BA)
            for row in 0..<4 { for column in 0..<6 where (row + column) % 2 == 0 {
                add(box(0.285, 0.004, 0.295, 0.001, 0xA3BDAF), to: root, at: (Float(column) * 0.3 - 0.75, 0.044, Float(row) * 0.31 - 0.465))
            } }
        case "rug.rainbow":
            for (i, tint) in [UInt(0xDF9FA5), 0xE6B582, 0xE7CE90, 0x92BFA7, 0xA5A3CC].enumerated() {
                let r = Float(1.02 - Double(i) * 0.155)
                let arc = (0...48).map { j -> V in let a = Float(j) / 48 * .pi; return V(cos(a) * r, 0.20, sin(a) * r - 0.4) }
                let band = tube(arc, radius: 0.087, tint: tint); band.simdScale.y = 0.13; root.addChildNode(band)
            }
        case "rug.donut":
            let ring = node(SCNTorus(ringRadius: 0.73, pipeRadius: 0.27), 0xCDB18B)
            ring.simdScale.y = 0.09; add(ring, to: root, at: (0, 0.022, 0))
            let icing = node(SCNTorus(ringRadius: 0.73, pipeRadius: 0.21), 0xC0A1C9)
            icing.simdScale.y = 0.08; add(icing, to: root, at: (0, 0.045, 0))
            for i in 0..<18 {
                let a = Float(i) * .pi * 2 / 18; let r: Float = i % 2 == 0 ? 0.64 : 0.80
                let sprinkle = capsule(0.012, 0.09, i % 3 == 0 ? 0xF6DE99 : 0xF4CFD0)
                sprinkle.eulerAngles = SCNVector3(.pi / 2, a, 0)
                add(sprinkle, to: root, at: (sin(a) * r, 0.067, cos(a) * r))
            }
        default:
            let base = cylinder(1.1, 0.035, id == "rug.round_stripe" ? 0xC69BA2 : 0xEAAE9C)
            base.simdScale.z = 0.74; root.addChildNode(base)
            let rim = ellipseLine(rx: 1.04, rz: 0.765, y: 0.022, radius: 0.011, tint: 0xF8D6BD); root.addChildNode(rim)
            if id == "rug.round_stripe" {
                for x: Float in [-0.72, -0.36, 0, 0.36, 0.72] {
                    let halfZ = sqrt(max(0, 1 - pow((abs(x) + 0.08) / 1.05, 2))) * 0.75
                    add(box(0.12, 0.005, CGFloat(halfZ * 2), 0.002, 0xF4E4C9), to: root, at: (x, 0.022, 0))
                }
            }
        }
        return root
    }

    private static func wallDecoration(_ id: String) -> SCNNode {
        let root = SCNNode(); root.position = SCNVector3(-1.25, 1.92, -1.76)
        switch id {
        case "wallDeco.clock":
            let rim = cylinder(0.34, 0.09, 0xB49379); rim.simdEulerAngles.x = .pi / 2; root.addChildNode(rim)
            let face = cylinder(0.291, 0.035, 0xFFF2D9); face.simdEulerAngles.x = .pi / 2
            add(face, to: root, at: (0, 0, 0.065))
            for i in 0..<12 {
                let a = Float(i) * .pi / 6
                add(sphere(0.013, 0x7B6C71), to: root, at: (sin(a) * 0.25, cos(a) * 0.25, 0.09))
            }
            root.addChildNode(tube([V(0, 0.18, 0.10), V(0, 0, 0.10), V(0.12, -0.065, 0.10)], radius: 0.014, tint: 0x60596E))
            add(sphere(0.026, 0xD39A80), to: root, at: (0, 0, 0.11))
        case "wallDeco.moon_lamp":
            var outline: [CGPoint] = []
            for i in 0...40 { let a = 1.065 + Double(i) / 40 * (Double.pi * 2 - 2.13); outline.append(CGPoint(x: cos(a) * 0.32, y: sin(a) * 0.32)) }
            for i in 0...40 { let a = -1.553 - Double(i) / 40 * 3.177; outline.append(CGPoint(x: 0.15 + cos(a) * 0.28, y: sin(a) * 0.28)) }
            let moon = polygon(outline, depth: 0.09, tint: 0xF5D68D)
            moon.geometry?.firstMaterial?.emission.contents = color(0x80642E)
            root.addChildNode(moon)
            add(star(radius: 0.084, depth: 0.025, tint: 0xF7DB93), to: root, at: (0.33, 0.13, 0))
        case "wallDeco.garland":
            let string = (0...32).map { i -> V in let x = Float(i) / 32 * 1.36 - 0.68; return V(x, 0.20 + x * x * 0.36, 0) }
            root.addChildNode(tube(string, radius: 0.009, tint: 0xB4987C))
            for i in 0..<6 {
                let x = Float(i) * 0.23 - 0.57; let y = 0.19 + x * x * 0.36
                add(polygon([CGPoint(x: -0.085, y: 0), CGPoint(x: 0.085, y: 0), CGPoint(x: 0, y: -0.23)], depth: 0.024, tint: [UInt(0xD99AAC), 0xA2C5B2, 0xEDCF92][i % 3]), to: root, at: (x, y, 0))
            }
        case "wallDeco.hanging_plant":
            let plant = floorProp("floorProp.plant"); plant.scale = SCNVector3(0.56, 0.56, 0.56)
            add(plant, to: root, at: (0, -0.36, 0.08))
            for side: Float in [-1, 1] { root.addChildNode(tube([V(0, 0.45, 0), V(side * 0.17, -0.14, 0.12), V(side * 0.10, -0.29, 0.12)], radius: 0.012, tint: 0xDFCCAA)) }
            add(sphere(0.03, 0x9E8568), to: root, at: (0, 0.46, 0))
        case "wallDeco.mirror":
            let outer = ellipsoid(0.35, 0.45, 0.055, 0xDDB989); root.addChildNode(outer)
            let glass = ellipsoid(0.295, 0.39, 0.018, 0xC9DCE0); glass.geometry?.firstMaterial?.metalness.contents = 0.45
            add(glass, to: root, at: (0, 0, 0.054))
            root.addChildNode(tube([V(-0.18, 0.12, 0.076), V(-0.035, 0.29, 0.076)], radius: 0.018, tint: 0xF2F2DF))
        case "wallDeco.window":
            add(box(0.82, 0.92, 0.095, 0.043, 0xFFF0D5), to: root, at: (0, 0, 0))
            add(box(0.66, 0.76, 0.025, 0.011, 0xA8D6E0), to: root, at: (0, 0, 0.06))
            add(sphere(0.085, 0xF2D589), to: root, at: (0.14, 0.17, 0.08))
            add(box(0.035, 0.8, 0.05, 0.016, 0xFFF0D5), to: root, at: (0, 0, 0.09))
            add(box(0.73, 0.035, 0.05, 0.016, 0xFFF0D5), to: root, at: (0, -0.01, 0.09))
            add(box(0.91, 0.07, 0.20, 0.028, 0xE7CCA5), to: root, at: (0, -0.45, 0.055))
        case "wallDeco.photo_frames":
            for (x, y, size, tint): (Float, Float, Float, UInt) in [(-0.20, 0.09, 0.43, 0xE1AF91), (0.29, -0.14, 0.36, 0xAAADC8)] {
                add(box(CGFloat(size), CGFloat(size * 1.16), 0.075, 0.026, 0xF9E8CA), to: root, at: (x, y, 0))
                add(box(CGFloat(size * 0.77), CGFloat(size * 0.9), 0.018, 0.007, tint), to: root, at: (x, y, 0.05))
                add(ellipsoid(size * 0.22, size * 0.24, 0.024, 0xF3D171), to: root, at: (x, y, 0.074))
                for side: Float in [-1, 1] { add(sphere(CGFloat(size * 0.025), 0x5E5368), to: root, at: (x + side * size * 0.07, y + size * 0.03, 0.101)) }
            }
        case "wallDeco.poster":
            add(box(0.65, 0.83, 0.025, 0.008, 0xF9E8CE), to: root, at: (0, 0, 0))
            add(box(0.49, 0.57, 0.016, 0.006, 0xBACCB6), to: root, at: (0, -0.02, 0.026))
            add(ellipsoid(0.19, 0.20, 0.025, 0xEBC960), to: root, at: (0, 0.03, 0.047))
            for side: Float in [-1, 1] { add(sphere(0.016, 0x605568), to: root, at: (side * 0.068, 0.07, 0.072)) }
            add(ellipsoid(0.04, 0.021, 0.018, 0xD89857), to: root, at: (0, 0.015, 0.075))
            for x: Float in [-0.23, 0.23] { let tape = box(0.16, 0.07, 0.012, 0.004, 0xE5C98F); tape.simdEulerAngles.z = x > 0 ? -0.4 : 0.4; add(tape, to: root, at: (x, 0.37, 0.025)) }
        default:
            add(box(0.76, 0.83, 0.095, 0.037, 0xD6B389), to: root, at: (0, 0, 0))
            add(box(0.61, 0.68, 0.025, 0.011, 0xECE0C8), to: root, at: (0, 0, 0.06))
            add(box(0.48, 0.53, 0.016, 0.006, 0xB7B3CD), to: root, at: (0, 0, 0.08))
            add(star(radius: 0.17, depth: 0.025, tint: 0xF1D17B), to: root, at: (0, 0.01, 0.097))
        }
        return root
    }

    // MARK: - Fitted surfaces and reusable model parts

    private static func cloth(y range: ClosedRange<Float>, lift: Float = 0.035, tint: UInt) -> SCNNode {
        let rows = max(3, Int((range.upperBound - range.lowerBound) * 28)); let columns = 64
        var vertices: [V] = []; var normals: [V] = []; var triangles: [Int32] = []
        for row in 0...rows {
            let y = range.lowerBound + Float(row) / Float(rows) * (range.upperBound - range.lowerBound)
            let s = sqrt(max(0.02, 1 - pow((y - 0.82) / 0.73, 2)))
            for column in 0...columns {
                let a = Float(column) / Float(columns) * .pi * 2
                let point = V(sin(a) * (0.68 * s + lift), y, cos(a) * (0.55 * s + lift))
                vertices.append(point)
                normals.append(simd_normalize(V(point.x / (0.68 * 0.68), (y - 0.82) / (0.73 * 0.73), point.z / (0.55 * 0.55))))
                if row < rows && column < columns {
                    let index = Int32(row * (columns + 1) + column); let next = index + Int32(columns + 1)
                    triangles += [index, index + 1, next, index + 1, next + 1, next]
                }
            }
        }
        return mesh(vertices, normals: normals, indices: triangles, tint: tint)
    }

    /// Front overlays use the same ellipsoid as the garment, including its shell thickness.
    /// There are no straight floating strips at the sides of a curved belly.
    private static func front(_ point: V, lift: Float) -> V {
        let s = sqrt(max(0.02, 1 - pow((point.y - 0.82) / 0.73, 2)))
        let rx = 0.68 * s + 0.035; let rz = 0.55 * s + 0.035
        let z = rz * sqrt(max(0.015, 1 - pow(point.x / rx, 2))) + lift - 0.035
        return V(point.x, point.y, z)
    }

    private static func frontPatch(_ points: [(Float, Float)], lift: Float, tint: UInt) -> SCNNode {
        // Subdivide each edge and fill radially so broad patches also conform between corners.
        let center = points.reduce(V.zero) { $0 + V($1.0, $1.1, 0) } / Float(max(points.count, 1))
        var boundary: [V] = []
        for index in points.indices {
            let start = V(points[index].0, points[index].1, 0)
            let end = V(points[(index + 1) % points.count].0, points[(index + 1) % points.count].1, 0)
            let count = max(1, Int(simd_distance(start, end) / 0.035))
            for i in 0..<count { boundary.append(start + (end - start) * Float(i) / Float(count)) }
        }
        var vertices = [front(center, lift: lift)]; var normals = [V(0, 0, 1)]; var indices: [Int32] = []
        let rings = 6
        for ring in 1...rings {
            for point in boundary {
                let p = front(center + (point - center) * Float(ring) / Float(rings), lift: lift)
                vertices.append(p); normals.append(simd_normalize(V(p.x / 0.49, (p.y - 0.82) / 0.57, p.z / 0.35)))
            }
        }
        for j in boundary.indices {
            let next = (j + 1) % boundary.count
            indices += [0, Int32(1 + j), Int32(1 + next)]
            for ring in 0..<(rings - 1) {
                let a = 1 + ring * boundary.count + j; let b = 1 + ring * boundary.count + next
                let c = a + boundary.count; let d = b + boundary.count
                indices += [Int32(a), Int32(c), Int32(b), Int32(b), Int32(c), Int32(d)]
            }
        }
        let model = mesh(vertices, normals: normals, indices: indices, tint: tint)
        model.geometry?.firstMaterial?.isDoubleSided = true
        return model
    }

    private static func frontLine(_ points: [(Float, Float)], lift: Float, radius: CGFloat, tint: UInt) -> SCNNode {
        var fitted: [V] = []
        for index in 0..<(points.count - 1) {
            let a = V(points[index].0, points[index].1, 0); let b = V(points[index + 1].0, points[index + 1].1, 0)
            let steps = max(2, Int(simd_distance(a, b) / 0.025))
            for i in 0..<steps { fitted.append(front(a + (b - a) * Float(i) / Float(steps), lift: lift)) }
        }
        if let last = points.last { fitted.append(front(V(last.0, last.1, 0), lift: lift)) }
        return tube(fitted, radius: radius, tint: tint)
    }

    private static func headSurface(x: Float, y: Float, lift: Float) -> V {
        V(x, y, 0.65 * sqrt(max(0.02, 1 - pow(x / 0.76, 2) - pow((y - 1.66) / 0.70, 2))) + lift)
    }

    private static func surfaceFan(_ points: [V], tint: UInt) -> SCNNode {
        guard points.count >= 3 else { return SCNNode() }
        let center = points.reduce(V.zero, +) / Float(points.count)
        var indices: [Int32] = []
        for i in points.indices { indices += [0, Int32(i + 1), Int32((i + 1) % points.count + 1)] }
        let result = mesh([center] + points, normals: Array(repeating: V(0, 0, 1), count: points.count + 1), indices: indices, tint: tint)
        result.geometry?.firstMaterial?.isDoubleSided = true
        return result
    }

    /// A smooth swept tube is one mesh, rather than a row of intersecting cylinders.
    private static func tube(_ points: [V], radius: CGFloat, tint: UInt) -> SCNNode {
        guard points.count >= 2 else { return SCNNode() }
        let sides = 8; var vertices: [V] = []; var normals: [V] = []; var indices: [Int32] = []
        for i in points.indices {
            let previous = points[max(i - 1, 0)]; let next = points[min(i + 1, points.count - 1)]
            let delta = next - previous
            let tangent = simd_length_squared(delta) > 0.0000001 ? simd_normalize(delta) : V(0, 1, 0)
            let reference = abs(tangent.y) > 0.94 ? V(1, 0, 0) : V(0, 1, 0)
            let axis = simd_normalize(simd_cross(tangent, reference)); let other = simd_cross(tangent, axis)
            for side in 0..<sides {
                let a = Float(side) / Float(sides) * .pi * 2
                let normal = axis * cos(a) + other * sin(a)
                vertices.append(points[i] + normal * Float(radius)); normals.append(normal)
                if i < points.count - 1 {
                    let a = Int32(i * sides + side); let b = Int32(i * sides + (side + 1) % sides)
                    let c = a + Int32(sides); let d = b + Int32(sides)
                    indices += [a, b, c, b, d, c]
                }
            }
        }
        let result = mesh(vertices, normals: normals, indices: indices, tint: tint)
        result.geometry?.firstMaterial?.isDoubleSided = true
        return result
    }

    private static func ellipseLine(rx: Float, rz: Float, y: Float, radius: CGFloat, tint: UInt) -> SCNNode {
        tube((0...64).map { i in let a = Float(i) * .pi / 32; return V(sin(a) * rx, y, cos(a) * rz) }, radius: radius, tint: tint)
    }

    private static func mesh(_ points: [V], normals: [V], indices: [Int32], tint: UInt) -> SCNNode {
        let vertices = points.map { SCNVector3($0.x, $0.y, $0.z) }
        let normals = normals.map { SCNVector3($0.x, $0.y, $0.z) }
        let geometry = SCNGeometry(sources: [.init(vertices: vertices), .init(normals: normals)],
                                   elements: [SCNGeometryElement(indices: indices, primitiveType: .triangles)])
        return node(geometry, tint)
    }

    private static func roundedRect(x: Float, y: Float, width: Float, height: Float, radius: Float) -> [(Float, Float)] {
        let r = min(radius, min(width, height) * 0.5)
        let corners: [(Float, Float, Float)] = [(x + width - r, y + height - r, 0), (x + r, y + height - r, .pi / 2), (x + r, y + r, .pi), (x + width - r, y + r, .pi * 1.5)]
        return corners.flatMap { cx, cy, angle in
            (0...6).map { i in let a = angle + Float(i) / 6 * .pi / 2; return (cx + cos(a) * r, cy + sin(a) * r) }
        }
    }

    private static func standingBook(width: Float, height: Float, tint: UInt) -> SCNNode {
        let root = SCNNode()
        add(box(CGFloat(width), CGFloat(height), 0.25, 0.014, tint), to: root, at: (0, 0, 0))
        add(box(CGFloat(width * 0.63), CGFloat(height * 0.86), 0.22, 0.006, 0xF0E2C8), to: root, at: (0, 0, -0.024))
        for y in [-height * 0.32, height * 0.32] { add(box(CGFloat(width * 0.72), 0.015, 0.012, 0.003, 0xEAD5AC), to: root, at: (0, y, 0.13)) }
        return root
    }

    private static func book(width: Float, tint: UInt) -> SCNNode {
        let root = SCNNode()
        add(box(CGFloat(width), 0.10, CGFloat(width * 0.68), 0.022, tint), to: root, at: (0, 0.05, 0))
        add(box(CGFloat(width * 0.89), 0.064, CGFloat(width * 0.63), 0.012, 0xF0E4C8), to: root, at: (0.018, 0.05, 0.01))
        for y: Float in [0.018, 0.082] { add(box(CGFloat(width), 0.022, CGFloat(width * 0.68), 0.01, tint), to: root, at: (0, y, 0)) }
        return root
    }

    private static func recenter(_ node: SCNNode, pivot: V) {
        for child in node.childNodes { child.simdPosition -= pivot }
        node.simdPosition = pivot
    }

    private static func starPoints(radius: CGFloat) -> [CGPoint] {
        (0..<10).map { i in
            let a = Double(i) * .pi / 5 + .pi / 2; let r = i % 2 == 0 ? radius : radius * 0.48
            return CGPoint(x: cos(a) * r, y: sin(a) * r)
        }
    }
    private static func star(radius: CGFloat, depth: CGFloat, tint: UInt) -> SCNNode {
        polygon(starPoints(radius: radius), depth: depth, tint: tint)
    }
    private static func heartPoints(size: CGFloat) -> [CGPoint] {
        (0..<64).map { i in
            let t = Double(i) * .pi * 2 / 64
            return CGPoint(x: 16 * pow(sin(t), 3) / 32 * size,
                           y: (13 * cos(t) - 5 * cos(2 * t) - 2 * cos(3 * t) - cos(4 * t)) / 32 * size)
        }
    }
    private static func heart(size: CGFloat, depth: CGFloat, tint: UInt) -> SCNNode {
        polygon(heartPoints(size: size), depth: depth, tint: tint)
    }
    private static func polygon(_ points: [CGPoint], depth: CGFloat, tint: UInt) -> SCNNode {
        #if canImport(UIKit)
        let path = UIBezierPath()
        #else
        let path = NSBezierPath()
        #endif
        if let first = points.first { path.move(to: first) }
        for point in points.dropFirst() {
            #if canImport(UIKit)
            path.addLine(to: point)
            #else
            path.line(to: point)
            #endif
        }
        path.close()
        let shape = SCNShape(path: path, extrusionDepth: depth)
        shape.chamferRadius = min(depth * 0.3, 0.014)
        return node(shape, tint)
    }
    private static func tuple(_ p: V) -> (Float, Float, Float) { (p.x, p.y, p.z) }
    private static func darker(_ value: UInt, by factor: Float) -> UInt {
        let r = UInt(Float((value >> 16) & 255) * factor)
        let g = UInt(Float((value >> 8) & 255) * factor)
        let b = UInt(Float(value & 255) * factor)
        return (r << 16) | (g << 8) | b
    }
    private static func color(_ hex: UInt, alpha: CGFloat = 1) -> ClayColor {
        ClayColor(red: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255,
                  blue: CGFloat(hex & 255) / 255, alpha: alpha)
    }
    private static func node(_ geometry: SCNGeometry, _ tint: UInt, metallic: CGFloat = 0) -> SCNNode {
        let material = SCNMaterial(); material.diffuse.contents = color(tint)
        material.lightingModel = .physicallyBased; material.roughness.contents = 0.72
        material.metalness.contents = metallic; geometry.materials = [material]
        return SCNNode(geometry: geometry)
    }
    private static func sphere(_ radius: CGFloat, _ tint: UInt) -> SCNNode {
        let geometry = SCNSphere(radius: radius); geometry.segmentCount = 32
        return node(geometry, tint)
    }
    private static func ellipsoid(_ x: Float, _ y: Float, _ z: Float, _ tint: UInt) -> SCNNode {
        let result = sphere(1, tint); result.simdScale = V(x, y, z); return result
    }
    private static func box(_ x: CGFloat, _ y: CGFloat, _ z: CGFloat, _ bevel: CGFloat, _ tint: UInt) -> SCNNode {
        // SceneKit produces folded/exploding bevel faces when the requested radius exceeds half
        // a thin panel. All dimensional parts, including frames and miniature seams, share this guard.
        let safeBevel = min(max(0, bevel), min(x, min(y, z)) * 0.45)
        let geometry = SCNBox(width: x, height: y, length: z, chamferRadius: safeBevel)
        geometry.chamferSegmentCount = safeBevel > 0 ? 4 : 1
        return node(geometry, tint)
    }
    private static func cylinder(_ radius: CGFloat, _ height: CGFloat, _ tint: UInt) -> SCNNode {
        let geometry = SCNCylinder(radius: radius, height: height); geometry.radialSegmentCount = 40
        return node(geometry, tint)
    }
    private static func cone(_ top: CGFloat, _ bottom: CGFloat, _ height: CGFloat, _ tint: UInt) -> SCNNode {
        let geometry = SCNCone(topRadius: top, bottomRadius: bottom, height: height); geometry.radialSegmentCount = 40
        return node(geometry, tint)
    }
    private static func capsule(_ radius: CGFloat, _ height: CGFloat, _ tint: UInt) -> SCNNode {
        let geometry = SCNCapsule(capRadius: radius, height: max(height, radius * 2)); geometry.radialSegmentCount = 16
        return node(geometry, tint)
    }
    private static func add(_ node: SCNNode, to parent: SCNNode, at position: (Float, Float, Float)) {
        node.simdPosition = V(position.0, position.1, position.2); parent.addChildNode(node)
    }
}
