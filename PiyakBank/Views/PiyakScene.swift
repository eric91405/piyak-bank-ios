import SceneKit
#if canImport(UIKit)
import UIKit
private typealias ClayColor = UIColor
#else
import AppKit
private typealias ClayColor = NSColor
#endif

/// Native, lit geometry. Room and outfit changes share the same 3D model as previews.
/// No downloaded models, network assets or continuously rebuilt SwiftUI animation.
enum PiyakScene {
    static let defaultItems = ["bg": "bg.cozy_cream", "floorProp": "floorProp.plant",
                               "rug": "rug.oval_coral", "bodyFront": "bodyFront.hoodie_mint"]

    static func make(equipped: [String: String] = defaultItems, working: Bool = false,
                     animated: Bool = true, icon: Bool = false) -> SCNScene {
        let scene = SCNScene()
        let root = scene.rootNode
        let camera = SCNNode()
        camera.camera = SCNCamera()
        camera.camera?.usesOrthographicProjection = true
        camera.camera?.orthographicScale = icon ? 1.65 : 3.1
        camera.camera?.zNear = 0.1
        camera.camera?.zFar = 100
        camera.position = icon ? SCNVector3(2.1, 2.65, 7) : SCNVector3(4.4, 4.1, 7.5)
        camera.look(at: SCNVector3(0, icon ? 1.3 : 1.15, 0))
        root.addChildNode(camera)

        let ambient = SCNNode()
        ambient.light = SCNLight(); ambient.light?.type = .ambient
        ambient.light?.intensity = 330; ambient.light?.color = color(0xFFF4E0)
        root.addChildNode(ambient)
        let light = SCNNode()
        light.light = SCNLight(); light.light?.type = .directional
        light.light?.intensity = 650
        light.light?.castsShadow = true
        light.light?.shadowMode = .deferred
        light.light?.shadowColor = color(0x43336E, alpha: 0.22)
        light.light?.shadowRadius = 8
        light.light?.shadowSampleCount = 16
        light.light?.orthographicScale = 8
        light.eulerAngles = SCNVector3(-0.85, -0.6, -0.2)
        root.addChildNode(light)
        let fill = SCNNode()
        fill.light = SCNLight(); fill.light?.type = .omni; fill.light?.intensity = 120
        fill.position = SCNVector3(4, 2, 5); root.addChildNode(fill)

        if !icon { room(root, equipped: equipped) }
        let chick = character(equipped: equipped)
        chick.position = SCNVector3(icon ? 0 : 0.15, 0, icon ? 0 : 0.35)
        chick.eulerAngles.y = 0.18
        root.addChildNode(chick)
        if animated {
            let up = SCNAction.moveBy(x: 0, y: working ? 0.12 : 0.035, z: 0, duration: working ? 0.65 : 1.7)
            up.timingMode = .easeInEaseOut
            let down = up.reversed(); down.timingMode = .easeInEaseOut
            chick.runAction(.repeatForever(.sequence([up, down])))
            if let eyes = chick.childNode(withName: "eyes", recursively: true) {
                let close = SCNAction.scale(to: 0.85, duration: 0.1)
                eyes.runAction(.repeatForever(.sequence([.wait(duration: 4), close, .scale(to: 1, duration: 0.1)])))
            }
        }
        return scene
    }

    static func itemScene(id: String, slot: String) -> SCNScene {
        if ["bodyFront", "headTop", "eyes", "neck"].contains(slot) {
            return make(equipped: [slot: id], animated: false, icon: true)
        }
        if slot == "bg" { return make(equipped: [slot: id], animated: false) }
        let scene = make(equipped: [:], animated: false, icon: true)
        for node in scene.rootNode.childNodes where node.camera == nil && node.light == nil { node.removeFromParentNode() }
        let content: SCNNode
        switch slot {
        case "bigFurniture": content = furniture(id)
        case "wallDeco": content = wallDecoration(id); content.position = SCNVector3(0, 0.5, 0)
        case "rug": content = rug(id)
        default: content = floorProp(id)
        }
        scene.rootNode.addChildNode(content)
        if let camera = scene.rootNode.childNodes.first(where: { $0.camera != nil }) {
            camera.camera?.orthographicScale = slot == "rug" ? 1.45 : 0.95
            camera.position = SCNVector3(2.8, 2.5, 5)
            camera.look(at: SCNVector3(0, slot == "rug" ? 0 : 0.65, 0))
        }
        return scene
    }

    private static func room(_ root: SCNNode, equipped: [String: String]) {
        let theme = equipped["bg"] ?? "bg.cozy_cream"
        let wall: UInt = theme.contains("night") ? 0x7880BC : theme.contains("sky") ? 0xBCE5F5 :
            theme.contains("sakura") ? 0xF8CEDE : theme.contains("lavender") ? 0xD8CCF4 :
            theme.contains("mint") ? 0xB9E6D0 : theme.contains("forest") ? 0x9AC8AD :
            theme.contains("ocean") ? 0x9CDADA : theme.contains("sunset") ? 0xFAC69E : 0xDAD9F5
        add(box(4.8, 0.3, 3.9, 0.18, 0xEDCCA4), to: root, at: (0, -0.18, 0))
        add(box(4.8, 2.95, 0.15, 0.08, wall), to: root, at: (0, 1.18, -1.9))
        add(box(0.15, 1.3, 3.9, 0.07, wall), to: root, at: (-2.33, 0.42, 0))
        // Floor boards and a bright, recessed window establish a little playroom.
        for x in stride(from: -1.8, through: 1.8, by: 0.6) {
            add(box(0.018, 0.005, 3.6, 0, 0xDDB991), to: root, at: (Float(x), -0.025, 0))
        }
        add(box(1.22, 1.45, 0.12, 0.18, 0xFFFFF3), to: root, at: (0.4, 1.65, -1.76))
        add(box(1.02, 1.24, 0.14, 0.15, theme.contains("night") ? 0x3D477C : 0xB8E7F2), to: root, at: (0.4, 1.65, -1.68))
        add(sphere(0.19, 0xFFE684), to: root, at: (0.61, 1.93, -1.53))
        add(box(1.17, 0.065, 0.18, 0.02, 0xFFFFF3), to: root, at: (0.4, 1.63, -1.57))
        add(box(0.065, 1.28, 0.18, 0.02, 0xFFFFF3), to: root, at: (0.4, 1.65, -1.57))
        if let id = equipped["rug"] { root.addChildNode(rug(id)) }
        if let id = equipped["floorProp"] {
            let prop = floorProp(id); prop.position = SCNVector3(1.65, 0, 0.5); root.addChildNode(prop)
        }
        if let id = equipped["bigFurniture"] {
            let furniture = furniture(id); furniture.position = SCNVector3(-1.45, 0, -0.9)
            root.addChildNode(furniture)
        }
        if let id = equipped["wallDeco"] { root.addChildNode(wallDecoration(id)) }
    }

    private static func character(equipped: [String: String]) -> SCNNode {
        let chick = SCNNode()
        let yellow: UInt = 0xFFD64F
        add(ellipsoid(0.68, 0.73, 0.55, yellow), to: chick, at: (0, 0.82, 0))
        add(ellipsoid(0.76, 0.7, 0.65, yellow), to: chick, at: (0, 1.66, 0))
        for side: Float in [-1, 1] {
            let wing = ellipsoid(0.19, 0.39, 0.21, yellow)
            wing.eulerAngles = SCNVector3(0, 0, side * 0.35)
            add(wing, to: chick, at: (side * 0.65, 0.88, 0.02))
            add(ellipsoid(0.24, 0.11, 0.32, 0xF5A05B), to: chick, at: (side * 0.29, 0.09, 0.23))
            add(ellipsoid(0.14, 0.075, 0.045, 0xF3A193), to: chick, at: (side * 0.47, 1.47, 0.54))
        }
        let eyes = SCNNode(); eyes.name = "eyes"
        for side: Float in [-1, 1] {
            add(ellipsoid(0.057, 0.083, 0.047, 0x35334D), to: eyes, at: (side * 0.245, 1.73, 0.609))
            add(sphere(0.018, 0xFFFFFF), to: eyes, at: (side * 0.245 - 0.009, 1.754, 0.647))
        }
        chick.addChildNode(eyes)
        add(ellipsoid(0.19, 0.093, 0.18, 0xF4A34F), to: chick, at: (0, 1.51, 0.657))
        for side: Float in [-1, 1] {
            let tuft = ellipsoid(0.075, 0.22, 0.075, yellow)
            tuft.eulerAngles = SCNVector3(0, 0, side * 0.55)
            add(tuft, to: chick, at: (side * 0.07, 2.33, -0.02))
        }
        if let id = equipped["bodyFront"] { outfit(id, on: chick) }
        if let id = equipped["headTop"] { hat(id, on: chick) }
        if let id = equipped["eyes"] { glasses(id, on: chick) }
        if let id = equipped["neck"] { neckwear(id, on: chick) }
        return chick
    }

    private static func outfit(_ id: String, on chick: SCNNode) {
        let tint: UInt = id.contains("mint") ? 0x72D5B8 : id.contains("overalls") ? 0x6D9CD9 :
            id.contains("raincoat") ? 0xF4C348 : id.contains("sweater") ? 0xDB92AD :
            id.contains("pajama") ? 0xBCACEA : id.contains("stripe") ? 0xFFF7E4 :
            id.contains("padding") ? 0xF09A74 : 0x42435B
        add(ellipsoid(0.7, 0.58, 0.58, tint), to: chick, at: (0, 0.78, 0))
        if id.contains("stripe") || id.contains("padding") {
            for y: Float in [0.49, 0.66, 0.83] {
                add(box(0.96, 0.06, 0.05, 0.02, id.contains("stripe") ? 0x557EB5 : 0xC46D4F), to: chick, at: (0, y, 0.51))
            }
        } else if id.contains("overalls") {
            for x: Float in [-0.3, 0.3] {
                add(box(0.13, 0.48, 0.06, 0.025, 0x6D9CD9), to: chick, at: (x, 1.04, 0.47))
                add(sphere(0.04, 0xFFDD6D), to: chick, at: (x, 0.9, 0.54))
            }
        } else if id.contains("gown") {
            add(box(0.16, 0.76, 0.07, 0.03, 0xE5BC57), to: chick, at: (0, 0.72, 0.55))
        } else {
            add(box(0.38, 0.2, 0.06, 0.07, tint), to: chick, at: (0, 0.64, 0.56))
            for x: Float in [-0.12, 0.12] {
                add(sphere(0.027, 0xFFFBEA), to: chick, at: (x, 1.07, 0.45))
            }
        }
    }

    private static func hat(_ id: String, on chick: SCNNode) {
        if id.contains("flower") {
            for i in 0..<5 {
                let a = Double(i) * .pi * 2 / 5
                add(sphere(0.11, 0xEC96B0), to: chick, at: (Float(cos(a)) * 0.14 + 0.36, 2.23 + Float(sin(a)) * 0.14, 0.23))
            }
            add(sphere(0.085, 0xFFE46C), to: chick, at: (0.36, 2.23, 0.32)); return
        }
        let tint: UInt = id.contains("wizard") ? 0x7A6ABD : id.contains("party") ? 0xF199B7 :
            id.contains("crown") ? 0xEDBB49 : id.contains("straw") ? 0xE7C780 :
            id.contains("chef") ? 0xFFFCF0 : id.contains("cap") ? 0x769DE0 : 0xE18475
        if id.contains("cone") || id.contains("wizard") {
            add(node(SCNCone(topRadius: 0.02, bottomRadius: 0.39, height: 0.8), tint), to: chick, at: (0, 2.56, 0))
            add(cylinder(0.48, 0.07, tint), to: chick, at: (0, 2.2, 0))
            add(sphere(0.085, 0xFFE173), to: chick, at: (0, 2.99, 0))
        } else if id.contains("crown") {
            add(cylinder(0.39, 0.21, tint), to: chick, at: (0, 2.24, 0))
            for x: Float in [-0.3, 0, 0.3] {
                add(node(SCNCone(topRadius: 0, bottomRadius: 0.12, height: 0.25), tint), to: chick, at: (x, 2.43, 0.1))
                add(sphere(0.04, 0xCF729F), to: chick, at: (x, 2.24, 0.36))
            }
        } else if id.contains("chef") {
            add(cylinder(0.37, 0.3, tint), to: chick, at: (0, 2.34, 0))
            for x: Float in [-0.25, 0, 0.25] { add(sphere(0.26, tint), to: chick, at: (x, 2.56, 0)) }
        } else {
            add(ellipsoid(0.48, id.contains("beanie") ? 0.37 : 0.23, 0.45, tint), to: chick, at: (0, 2.25, 0))
            if id.contains("straw") { add(cylinder(0.69, 0.055, tint), to: chick, at: (0, 2.19, 0)) }
            if id.contains("cap") { add(ellipsoid(0.38, 0.045, 0.36, tint), to: chick, at: (0, 2.18, 0.42)) }
            if id.contains("beanie") { add(sphere(0.12, 0xFFF3DD), to: chick, at: (0, 2.63, 0)) }
            if id.contains("beret") { add(cylinder(0.045, 0.1, tint), to: chick, at: (0, 2.5, 0)) }
        }
    }

    private static func glasses(_ id: String, on chick: SCNNode) {
        let tint: UInt = id.contains("red") || id.contains("heart") ? 0xD65D78 :
            id.contains("blue") ? 0x427EBD : id.contains("star") ? 0xDAAA39 : 0x444459
        let sides: [Float] = id.contains("monocle") || id.contains("eyepatch") ? [-1] : [-1, 1]
        for side in sides {
            if id.contains("sunglasses") || id.contains("eyepatch") || id.contains("goggles") {
                add(box(0.36, 0.25, 0.065, 0.1, tint), to: chick, at: (side * 0.26, 1.73, 0.64))
            } else if id.contains("star") || id.contains("heart") {
                let shape = id.contains("star") ? star(radius: 0.19, depth: 0.04, tint: tint) : heart(size: 0.24, depth: 0.035, tint: tint)
                add(shape, to: chick, at: (side * 0.26, 1.73, 0.67))
            } else {
                let ring = node(SCNTorus(ringRadius: 0.16, pipeRadius: 0.025), tint)
                ring.eulerAngles.x = .pi / 2
                add(ring, to: chick, at: (side * 0.26, 1.73, 0.67))
            }
        }
        if sides.count == 2 { add(box(0.23, 0.035, 0.05, 0.01, tint), to: chick, at: (0, 1.74, 0.68)) }
    }

    private static func neckwear(_ id: String, on chick: SCNNode) {
        let tint: UInt = id.contains("mint") ? 0x64C9AC : id.contains("gold") || id.contains("bell") ? 0xDDB452 :
            id.contains("pearl") ? 0xFFF2D8 : id.contains("tie") ? 0x7560A8 : 0xE68692
        if id.contains("chain") || id.contains("pearl") || id.contains("bell") {
            for i in 0..<11 {
                let a = Double(i) * .pi / 10
                add(sphere(id.contains("pearl") ? 0.047 : 0.029, tint), to: chick,
                    at: (Float(cos(a)) * 0.4, 1.25 - Float(sin(a)) * 0.17, 0.52))
            }
            if id.contains("bell") { add(sphere(0.095, tint), to: chick, at: (0, 1.04, 0.6)) }
        } else if id.contains("ribbon") || id.contains("bowtie") {
            for side: Float in [-1, 1] {
                let bow = ellipsoid(0.16, 0.09, 0.07, tint); bow.eulerAngles = SCNVector3(0, 0, side * 0.3)
                add(bow, to: chick, at: (side * 0.14, 1.25, 0.57))
            }
            add(sphere(0.06, tint), to: chick, at: (0, 1.25, 0.62))
        } else {
            add(box(0.72, 0.15, 0.1, 0.07, tint), to: chick, at: (0, 1.25, 0.45))
            let tail = box(id.contains("tie") ? 0.13 : 0.2, 0.39, 0.06, 0.03, tint)
            tail.eulerAngles.z = -0.14
            add(tail, to: chick, at: (0.12, 1.03, 0.58))
        }
    }

    private static func rug(_ id: String) -> SCNNode {
        let root = SCNNode(); root.position = SCNVector3(0.15, 0.015, 0.4)
        if id.contains("star") || id.contains("heart") {
            let shape = id.contains("star") ? star(radius: 1.2, depth: 0.04, tint: 0xE1CB83) : heart(size: 1.55, depth: 0.04, tint: 0xDC9AB1)
            shape.eulerAngles.x = -.pi / 2; root.addChildNode(shape)
        } else if id.contains("donut") {
            root.addChildNode(node(SCNTorus(ringRadius: 0.8, pipeRadius: 0.2), 0xB19CCE))
            root.scale.y = 0.15
        } else {
            let base = cylinder(1.1, 0.035, id.contains("leaf") ? 0x8ABAA1 : id.contains("cloud") ? 0xF3EFE9 : 0xF0AE9D)
            base.scale.z = 0.74; root.addChildNode(base)
            if id.contains("cloud") {
                for x: Float in [-0.6, 0.6] { add(cylinder(0.5, 0.04, 0xF3EFE9), to: root, at: (x, 0, 0.4)) }
            }
            if id.contains("stripe") || id.contains("checker") {
                for x: Float in [-0.6, -0.2, 0.2, 0.6] {
                    add(box(0.15, 0.012, 1.25, 0.03, 0xFFF1D4), to: root, at: (x, 0.022, 0))
                }
                if id.contains("checker") {
                    for z: Float in [-0.4, 0, 0.4] { add(box(1.6, 0.015, 0.15, 0.03, 0xFFF1D4), to: root, at: (0, 0.03, z)) }
                }
            }
            if id.contains("rainbow") {
                for (i, tint) in [UInt(0xE6A3A9), 0xEDD28F, 0x90C9B9, 0x9DABDE].enumerated() {
                    let ring = node(SCNTorus(ringRadius: CGFloat(0.9 - Double(i) * 0.16), pipeRadius: 0.07), tint)
                    ring.scale.y = 0.1; ring.position.y = 0.04; root.addChildNode(ring)
                }
            }
        }
        return root
    }

    private static func floorProp(_ id: String) -> SCNNode {
        let root = SCNNode()
        if id.contains("plant") || id.contains("cactus") {
            add(node(SCNCone(topRadius: 0.25, bottomRadius: 0.18, height: 0.38), 0xD58D73), to: root, at: (0, 0.2, 0))
            add(cylinder(0.22, 0.02, 0x796854), to: root, at: (0, 0.39, 0))
            for (x, y) in [(Float(-0.17), Float(0.62)), (0, 0.85), (0.18, 0.7)] {
                let leaf = ellipsoid(id.contains("cactus") ? 0.11 : 0.16, 0.31, 0.11, 0x76AA82)
                leaf.eulerAngles = SCNVector3(0, 0, -x * 2); add(leaf, to: root, at: (x, y, 0))
            }
        } else if id.contains("lamp") {
            add(cylinder(0.25, 0.08, 0xDAC49A), to: root, at: (0, 0.05, 0))
            add(cylinder(0.035, 0.95, 0xD5AE62), to: root, at: (0, 0.5, 0))
            add(node(SCNCone(topRadius: 0.22, bottomRadius: 0.38, height: 0.4), 0xFFEBB5), to: root, at: (0, 1.12, 0))
        } else if id.contains("books") {
            for (i, tint) in [UInt(0x8295CA), 0xE0A28F, 0x98B998].enumerated() {
                let book = box(0.6, 0.14, 0.43, 0.035, tint); book.eulerAngles = SCNVector3(0, Float(i) * 0.18, 0)
                add(book, to: root, at: (0, Float(i) * 0.16 + 0.1, 0))
            }
        } else if id.contains("balloons") {
            for (i, tint) in [UInt(0xDF9EC2), 0x8FCFC0, 0xFFE189].enumerated() {
                let x = Float(i - 1) * 0.23
                add(cylinder(0.007, 0.8, 0xE8D8C9), to: root, at: (x, 0.4, 0))
                add(ellipsoid(0.22, 0.29, 0.22, tint), to: root, at: (x, 0.95 + Float(i % 2) * 0.28, 0))
            }
        } else if id.contains("coin") {
            for i in 0..<7 { add(cylinder(0.18, 0.07, 0xE9BF50), to: root, at: (i < 4 ? -0.15 : 0.16, Float(i % 4) * 0.08 + 0.04, 0)) }
        } else if id.contains("jar") {
            add(ellipsoid(0.34, 0.37, 0.34, 0xFFF6DF), to: root, at: (0, 0.39, 0))
            add(cylinder(0.15, 0.12, 0xFFF6DF), to: root, at: (0, 0.75, 0))
        } else if id.contains("puppy") {
            add(sphere(0.28, 0xE8C9A2), to: root, at: (0, 0.29, 0))
            add(sphere(0.24, 0xE8C9A2), to: root, at: (0, 0.64, 0.08))
            for x: Float in [-0.2, 0.2] { add(ellipsoid(0.1, 0.18, 0.09, 0xA87962), to: root, at: (x, 0.65, 0.08)) }
            for x: Float in [-0.09, 0.09] { add(sphere(0.027, 0x3F3C4B), to: root, at: (x, 0.67, 0.29)) }
            add(sphere(0.04, 0x3F3C4B), to: root, at: (0, 0.56, 0.3))
        } else {
            add(box(0.62, 0.42, 0.52, 0.07, 0x96B4D6), to: root, at: (0, 0.24, 0))
            add(sphere(0.18, 0xE6B267), to: root, at: (0.12, 0.52, 0))
            add(box(0.2, 0.23, 0.2, 0.02, 0xC398B8), to: root, at: (-0.15, 0.48, 0))
        }
        return root
    }

    private static func furniture(_ id: String) -> SCNNode {
        let root = SCNNode()
        if id.contains("sofa") {
            add(box(1.22, 0.38, 0.65, 0.16, 0x9DBEAF), to: root, at: (0, 0.35, 0))
            add(box(1.2, 0.58, 0.18, 0.1, 0x9DBEAF), to: root, at: (0, 0.74, -0.26))
            for x: Float in [-0.57, 0.57] { add(box(0.16, 0.38, 0.69, 0.08, 0x89AD9D), to: root, at: (x, 0.56, 0)) }
        } else if id.contains("tv") {
            add(box(1.05, 0.7, 0.15, 0.06, 0x45445F), to: root, at: (0, 1, -0.1))
            add(box(0.88, 0.52, 0.04, 0.04, 0xACBDE4), to: root, at: (0, 1, 0))
            add(box(1.15, 0.4, 0.6, 0.06, 0xD2B596), to: root, at: (0, 0.25, 0))
        } else if id.contains("piano") {
            add(box(1.2, 1.05, 0.5, 0.06, 0x57556B), to: root, at: (0, 0.58, 0))
            add(box(1.15, 0.09, 0.48, 0.02, 0xFFFAE9), to: root, at: (0, 0.65, 0.26))
            for x in stride(from: Float(-0.45), through: 0.45, by: 0.13) { add(box(0.055, 0.04, 0.22, 0.008, 0x353544), to: root, at: (x, 0.72, 0.2)) }
        } else if id.contains("desk") || id.contains("shelf") {
            add(box(1.2, 0.12, 0.66, 0.05, 0xD5AD86), to: root, at: (0, 0.9, 0))
            for x: Float in [-0.47, 0.47] { add(box(0.11, 0.85, 0.5, 0.03, 0xD5AD86), to: root, at: (x, 0.44, 0)) }
            add(box(0.4, 0.06, 0.3, 0.015, 0x91B5CB), to: root, at: (0, 1, 0))
        } else {
            let tall = !id.contains("nightstand")
            let height: CGFloat = tall ? 1.4 : 0.65
            let tint: UInt = id.contains("fridge") ? 0xB9D6CC : 0xCCAB86
            add(box(1.02, height, 0.56, 0.065, tint), to: root, at: (0, Float(height / 2), 0))
            if id.contains("bookshelf") {
                for y: Float in [0.28, 0.76, 1.22] {
                    add(box(0.86, 0.32, 0.035, 0.01, 0x8F7865), to: root, at: (0, y, 0.285))
                    for (i, tint) in [UInt(0x94BCB1), 0xA49FC9, 0xE0B573, 0xD69387].enumerated() {
                        add(box(0.12, 0.25, 0.12, 0.01, tint), to: root, at: (Float(i) * 0.17 - 0.27, y, 0.31))
                    }
                }
            } else {
                add(box(0.015, height * 0.85, 0.015, 0, 0xA18A74), to: root, at: (0, Float(height / 2), 0.29))
                for x: Float in [-0.08, 0.08] { add(sphere(0.033, 0xFFF2DA), to: root, at: (x, Float(height / 2), 0.31)) }
            }
        }
        return root
    }

    private static func wallDecoration(_ id: String) -> SCNNode {
        let root = SCNNode(); root.position = SCNVector3(-1.25, 1.92, -1.76)
        if id.contains("clock") || id.contains("moon") {
            let face = cylinder(0.3, 0.07, id.contains("moon") ? 0xFFE59D : 0xFFF5D9)
            face.eulerAngles.x = .pi / 2; root.addChildNode(face)
            if id.contains("clock") {
                add(box(0.035, 0.19, 0.04, 0.01, 0x56516A), to: root, at: (0, 0.075, 0.07))
                add(box(0.17, 0.035, 0.04, 0.01, 0x56516A), to: root, at: (0.07, 0, 0.07))
            }
        } else if id.contains("garland") {
            add(box(1.15, 0.015, 0.015, 0, 0xFFF4DB), to: root, at: (0.15, 0.2, 0))
            for i in 0..<5 {
                let cone = node(SCNCone(topRadius: 0.1, bottomRadius: 0, height: 0.21), i % 2 == 0 ? 0xD999B4 : 0x9BC9BA)
                add(cone, to: root, at: (Float(i) * 0.22 - 0.29, 0.08, 0))
            }
        } else if id.contains("plant") {
            let plant = floorProp("floorProp.plant"); plant.scale = SCNVector3(0.6, 0.6, 0.6)
            add(plant, to: root, at: (0, -0.35, 0.1))
            for x: Float in [-0.1, 0.1] { add(box(0.012, 0.55, 0.01, 0, 0xFFF3DC), to: root, at: (x, 0.2, 0)) }
        } else {
            add(box(0.7, 0.82, 0.09, 0.04, 0xFFF3DC), to: root, at: (0, 0, 0))
            add(box(0.57, 0.67, 0.03, 0.03, id.contains("mirror") || id.contains("window") ? 0xBBDBE6 : 0xD8BDDD), to: root, at: (0, 0, 0.06))
            if !id.contains("mirror") {
                let motif = star(radius: 0.2, depth: 0.025, tint: 0xFFDB77)
                add(motif, to: root, at: (0, 0.04, 0.09))
            }
            if id.contains("photo") { add(box(0.3, 0.36, 0.09, 0.02, 0xF3BC94), to: root, at: (0.55, -0.19, 0)) }
        }
        return root
    }

    private static func star(radius: CGFloat, depth: CGFloat, tint: UInt) -> SCNNode {
        var points: [CGPoint] = []
        for i in 0..<10 {
            let angle = Double(i) * .pi / 5 + .pi / 2
            let r = i % 2 == 0 ? radius : radius * 0.48
            points.append(CGPoint(x: cos(angle) * r, y: sin(angle) * r))
        }
        return polygon(points, depth: depth, tint: tint)
    }
    private static func heart(size: CGFloat, depth: CGFloat, tint: UInt) -> SCNNode {
        var points: [CGPoint] = []
        for i in 0..<64 {
            let t = Double(i) * .pi * 2 / 64
            let x = 16 * pow(sin(t), 3)
            let y = 13 * cos(t) - 5 * cos(2*t) - 2 * cos(3*t) - cos(4*t)
            points.append(CGPoint(x: x / 32 * size, y: y / 32 * size))
        }
        return polygon(points, depth: depth, tint: tint)
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
        shape.chamferRadius = min(depth / 3, 0.025)
        return node(shape, tint)
    }
    private static func color(_ hex: UInt, alpha: CGFloat = 1) -> ClayColor {
        ClayColor(red: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255,
                  blue: CGFloat(hex & 255) / 255, alpha: alpha)
    }
    private static func node(_ geometry: SCNGeometry, _ tint: UInt) -> SCNNode {
        let material = SCNMaterial()
        material.diffuse.contents = color(tint)
        material.lightingModel = .physicallyBased
        material.roughness.contents = 0.78
        material.metalness.contents = 0.0
        geometry.materials = [material]
        return SCNNode(geometry: geometry)
    }
    private static func sphere(_ radius: CGFloat, _ tint: UInt) -> SCNNode {
        let geometry = SCNSphere(radius: radius); geometry.segmentCount = 32
        return node(geometry, tint)
    }
    private static func ellipsoid(_ x: Float, _ y: Float, _ z: Float, _ tint: UInt) -> SCNNode {
        let result = sphere(1, tint); result.scale = SCNVector3(x, y, z); return result
    }
    private static func box(_ x: CGFloat, _ y: CGFloat, _ z: CGFloat, _ bevel: CGFloat, _ tint: UInt) -> SCNNode {
        node(SCNBox(width: x, height: y, length: z, chamferRadius: bevel), tint)
    }
    private static func cylinder(_ radius: CGFloat, _ height: CGFloat, _ tint: UInt) -> SCNNode {
        node(SCNCylinder(radius: radius, height: height), tint)
    }
    private static func add(_ node: SCNNode, to parent: SCNNode, at position: (Float, Float, Float)) {
        node.position = SCNVector3(position.0, position.1, position.2)
        parent.addChildNode(node)
    }
}
