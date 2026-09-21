import AppKit
import CryptoKit
import Foundation
import SceneKit
import simd

// Compiled alongside the original iOS scene and behavior sources. No GPU, window,
// downloaded models or parallel workers are needed to export their actual meshes.
@main
enum ExportScene {
    struct Instance: Codable {
        var key: String
        var mesh: Int
        var rig: String
        var matrix: [Float]
        var color: [Float]
        var label: String
    }
    struct Rig: Codable { var name: String; var parent: String; var matrix: [Float] }
    struct Delta: Codable { var add: [Instance]; var remove: [String] }
    struct Preview: Codable { var instances: [Instance]; var camera: [Float]; var target: [Float]; var scale: Float }
    struct MeshBounds: Codable { var kind: String; var sourceMin: [Float]; var sourceMax: [Float]; var exportedMin: [Float]; var exportedMax: [Float] }
    struct Manifest: Codable {
        var version = 1
        var sourceSHA256: String
        var rigs: [Rig]
        var base: [Instance]
        var rooms: [String: [Instance]]
        var items: [String: Delta]
        var previews: [String: Preview]
        var effects: [String: [Instance]]
        var meshCount: Int
        var triangleCount: Int
        var meshBounds: [MeshBounds]
    }
    struct Failure: Error, CustomStringConvertible { var message: String; var description: String { message } }
    static let rigNames: Set<String> = ["piyak", "bodyRig", "headRig", "eyes", "wing.left", "wing.right", "foot.left", "foot.right"]
    static var meshIDs: [String: Int] = [:]
    static var meshData = Data()
    static var triangleCount = 0
    static var meshBounds: [MeshBounds] = []

    static func floats(_ m: simd_float4x4) -> [Float] {
        (0..<4).flatMap { c in (0..<4).map { r in abs(m[c][r]) < 0.0000001 ? 0 : m[c][r] } }
    }
    static func hash(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    static func append<T>(_ value: T, to data: inout Data) { var v = value; withUnsafeBytes(of: &v) { data.append(contentsOf: $0) } }

    static func vectors(_ source: SCNGeometrySource) throws -> [SIMD3<Float>] {
        guard source.usesFloatComponents, [4, 8].contains(source.bytesPerComponent), source.componentsPerVector >= 3 else {
            throw Failure(message: "Unsupported vertex format")
        }
        let stride = source.dataStride > 0 ? source.dataStride : source.componentsPerVector * source.bytesPerComponent
        return try source.data.withUnsafeBytes { bytes in
            try (0..<source.vectorCount).map { i in
                var v = SIMD3<Float>.zero
                for c in 0..<3 {
                    let offset = source.dataOffset + i * stride + c * source.bytesPerComponent
                    guard offset >= 0, offset + source.bytesPerComponent <= bytes.count else { throw Failure(message: "Vertex buffer bounds") }
                    v[c] = source.bytesPerComponent == 4 ? bytes.loadUnaligned(fromByteOffset: offset, as: Float.self) : Float(bytes.loadUnaligned(fromByteOffset: offset, as: Double.self))
                    guard v[c].isFinite else { throw Failure(message: "Nonfinite mesh value") }
                }
                return v
            }
        }
    }

    static func mesh(_ original: SCNGeometry) throws -> Int {
        // SceneKit's Model I/O bridge can return UNIT primitives, losing the
        // original dimensions (including every rounded box). Tessellate the
        // original primitive parameters explicitly and verify source bounds.
        let geometry: SCNGeometry
        if let shape = original as? SCNShape {
            // Model I/O leaves SCNShape with empty CPU sources. The original
            // shapes are closed straight-line stars/hearts, so triangulate the
            // original path (including concave vertices) and its bevel directly.
            geometry = try extrude(shape)
        } else { geometry = try primitive(original) ?? original }
        guard let source = geometry.sources(for: .vertex).first else { throw Failure(message: "No vertices: \(type(of: original))") }
        let positions = try vectors(source)
        guard !positions.isEmpty, positions.count < 65_536 else { throw Failure(message: "Invalid or oversized \(type(of: original)) mesh: \(positions.count) vertices / \(geometry.elements.count) elements") }
        // This checks meaningful model shape fidelity, not merely finite bytes.
        // The original floor, millimetre-wide trim and eye highlights must never
        // silently become identically sized meshes again.
        let expected = original.boundingBox
        let low = (0..<3).map { axis in positions.map { $0[axis] }.min()! }
        let high = (0..<3).map { axis in positions.map { $0[axis] }.max()! }
        let wantedLow = [Float(expected.min.x), Float(expected.min.y), Float(expected.min.z)]
        let wantedHigh = [Float(expected.max.x), Float(expected.max.y), Float(expected.max.z)]
        for axis in 0..<3 {
            let tolerance = max(0.00001, (wantedHigh[axis] - wantedLow[axis]) * 0.0002)
            guard abs(low[axis] - wantedLow[axis]) <= tolerance, abs(high[axis] - wantedHigh[axis]) <= tolerance else {
                throw Failure(message: "\(type(of: original)) bounds differ on axis \(axis): \(low[axis])...\(high[axis]), expected \(wantedLow[axis])...\(wantedHigh[axis])")
            }
        }
        var indices: [UInt16] = []
        for element in geometry.elements {
            let width = element.bytesPerIndex
            guard [1, 2, 4].contains(width) else { throw Failure(message: "Unsupported index width") }
            let raw: [UInt32] = element.data.withUnsafeBytes { bytes in
                (0..<(bytes.count / width)).map { i in
                    switch width {
                    case 1: UInt32(bytes.loadUnaligned(fromByteOffset: i, as: UInt8.self))
                    case 2: UInt32(bytes.loadUnaligned(fromByteOffset: i * 2, as: UInt16.self))
                    default: bytes.loadUnaligned(fromByteOffset: i * 4, as: UInt32.self)
                    }
                }
            }
            var triangles: [UInt32] = []
            switch element.primitiveType {
            case .triangles: triangles = Array(raw.prefix(element.primitiveCount * 3))
            case .triangleStrip:
                for i in 0..<element.primitiveCount where i + 2 < raw.count {
                    triangles += i.isMultiple(of: 2) ? [raw[i], raw[i+1], raw[i+2]] : [raw[i+1], raw[i], raw[i+2]]
                }
            case .polygon:
                let polygonCount = element.primitiveCount
                var cursor = polygonCount
                for count in raw.prefix(polygonCount) {
                    guard count >= 3, cursor + Int(count) <= raw.count else { throw Failure(message: "Invalid polygon") }
                    for j in 1..<(Int(count)-1) { triangles += [raw[cursor], raw[cursor+j], raw[cursor+j+1]] }
                    cursor += Int(count)
                }
            default: throw Failure(message: "Nontriangle geometry")
            }
            for i in triangles {
                guard Int(i) < positions.count else { throw Failure(message: "Index out of bounds") }
                indices.append(UInt16(i))
            }
        }
        guard !indices.isEmpty, indices.count.isMultiple(of: 3) else { throw Failure(message: "Empty triangle mesh") }
        var normals = try geometry.sources(for: .normal).first.map(vectors) ?? []
        if normals.count != positions.count {
            normals = Array(repeating: .zero, count: positions.count)
            for i in stride(from: 0, to: indices.count, by: 3) {
                let a = Int(indices[i]), b = Int(indices[i+1]), c = Int(indices[i+2])
                let n = simd_cross(positions[b] - positions[a], positions[c] - positions[a])
                normals[a] += n; normals[b] += n; normals[c] += n
            }
        }
        var data = Data()
        append(UInt32(positions.count).littleEndian, to: &data)
        append(UInt32(indices.count).littleEndian, to: &data)
        for i in positions.indices {
            let n = simd_length_squared(normals[i]) > 0.0000001 ? simd_normalize(normals[i]) : SIMD3<Float>(0, 1, 0)
            for value in [positions[i].x, positions[i].y, positions[i].z, n.x, n.y, n.z] { append(value.bitPattern.littleEndian, to: &data) }
        }
        for i in indices { append(i.littleEndian, to: &data) }
        let key = hash(data)
        if let id = meshIDs[key] { return id }
        let id = meshIDs.count; meshIDs[key] = id; meshData.append(data); triangleCount += indices.count / 3
        meshBounds.append(MeshBounds(kind: String(describing: type(of: original)), sourceMin: wantedLow, sourceMax: wantedHigh, exportedMin: low, exportedMax: high))
        return id
    }

    struct Surface {
        var vertices: [SCNVector3] = []
        var normals: [SCNVector3] = []
        var indices: [Int32] = []
        mutating func vertex(_ p: SIMD3<Float>, _ n: SIMD3<Float>) -> Int32 {
            let index = Int32(vertices.count)
            vertices.append(SCNVector3(p.x,p.y,p.z)); normals.append(SCNVector3(n.x,n.y,n.z)); return index
        }
        mutating func triangle(_ a: Int32, _ b: Int32, _ c: Int32) {
            func v(_ index: Int32) -> SIMD3<Float> { let p = vertices[Int(index)]; return SIMD3(Float(p.x),Float(p.y),Float(p.z)) }
            let normal = normals[Int(a)], n = SIMD3<Float>(Float(normal.x),Float(normal.y),Float(normal.z))
            let direction = simd_dot(simd_cross(v(b)-v(a), v(c)-v(a)), n)
            indices += direction >= 0 ? [a,b,c] : [a,c,b]
        }
        mutating func grid(u: Int, v: Int, sample: (Int,Int) -> (SIMD3<Float>,SIMD3<Float>)) {
            let start = Int32(vertices.count)
            for j in 0...v { for i in 0...u { let (p,n) = sample(i,j); _ = vertex(p,n) } }
            for j in 0..<v { for i in 0..<u {
                let a = start+Int32(j*(u+1)+i), b = a+1, c = a+Int32(u+1), d = c+1
                triangle(a,b,d); triangle(a,d,c)
            } }
        }
        mutating func disk(radius: Float, y: Float, upward: Bool, segments: Int) {
            guard radius > 0 else { return }
            let n = SIMD3<Float>(0,upward ? 1 : -1,0), center = vertex(SIMD3(0,y,0),n)
            var rim: [Int32] = []
            for i in 0...segments { let a = Float(i)*2*Float.pi/Float(segments); rim.append(vertex(SIMD3(sin(a)*radius,y,cos(a)*radius),n)) }
            for i in 0..<segments { triangle(center,rim[i],rim[i+1]) }
        }
        func geometry() -> SCNGeometry {
            SCNGeometry(sources: [SCNGeometrySource(vertices: vertices),SCNGeometrySource(normals: normals)], elements: [SCNGeometryElement(indices: indices,primitiveType: .triangles)])
        }
    }

    static func primitive(_ original: SCNGeometry) throws -> SCNGeometry? {
        var mesh = Surface()
        if let shape = original as? SCNSphere {
            let radius = Float(shape.radius), longitude = max(12,shape.segmentCount), latitude = max(8,longitude/2)
            mesh.grid(u: longitude,v: latitude) { i,j in
                let a = Float(i)*2*Float.pi/Float(longitude), b = Float(j)*Float.pi/Float(latitude)-Float.pi/2
                let n = SIMD3<Float>(sin(a)*cos(b),sin(b),cos(a)*cos(b)); return (n*radius,n)
            }
        } else if let shape = original as? SCNBox {
            let half = SIMD3<Float>(Float(shape.width),Float(shape.height),Float(shape.length))*0.5
            let radius = min(Float(shape.chamferRadius),min(half.x,min(half.y,half.z)))
            let inner = half-SIMD3<Float>(repeating: radius), subdivisions = max(1,shape.chamferSegmentCount)
            func coordinates(_ axis: Int) -> [Float] {
                guard radius > 0 else { return [-half[axis],half[axis]] }
                let negative = (0...subdivisions).map { -half[axis]+Float($0)/Float(subdivisions)*radius }
                let positive = (0...subdivisions).map { inner[axis]+Float($0)/Float(subdivisions)*radius }
                return negative+positive
            }
            for axis in 0..<3 { for side: Float in [-1,1] {
                let u = (axis+1)%3, v = (axis+2)%3, us = coordinates(u), vs = coordinates(v)
                mesh.grid(u: us.count-1,v: vs.count-1) { i,j in
                    var p = SIMD3<Float>.zero; p[axis] = side*half[axis]; p[u] = us[i]; p[v] = vs[j]
                    if radius == 0 { var n = SIMD3<Float>.zero; n[axis] = side; return (p,n) }
                    let core = simd_clamp(p,-inner,inner), n = simd_normalize(p-core)
                    return (core+n*radius,n)
                }
            } }
        } else if let shape = original as? SCNTorus {
            let ring = Float(shape.ringRadius), pipe = Float(shape.pipeRadius), radial = max(16,shape.ringSegmentCount), tube = max(12,shape.pipeSegmentCount)
            mesh.grid(u: radial,v: tube) { i,j in
                let a = Float(i)*2*Float.pi/Float(radial), b = Float(j)*2*Float.pi/Float(tube)
                let n = SIMD3<Float>(sin(a)*cos(b),sin(b),cos(a)*cos(b))
                return (SIMD3(sin(a)*(ring+pipe*cos(b)),pipe*sin(b),cos(a)*(ring+pipe*cos(b))),n)
            }
        } else if let shape = original as? SCNCapsule {
            let radius = Float(shape.capRadius), center = max(0,Float(shape.height)*0.5-radius), radial = max(12,shape.radialSegmentCount), cap = max(6,shape.capSegmentCount)
            let profile = (0...cap).map { i -> (Float,Float,Float,Float) in
                let a = -Float.pi/2+Float(i)*Float.pi/2/Float(cap); return (cos(a)*radius,-center+sin(a)*radius,cos(a),sin(a))
            } + (0...cap).map { i -> (Float,Float,Float,Float) in
                let a = Float(i)*Float.pi/2/Float(cap); return (cos(a)*radius,center+sin(a)*radius,cos(a),sin(a))
            }
            mesh.grid(u: radial,v: profile.count-1) { i,j in
                let a = Float(i)*2*Float.pi/Float(radial), p = profile[j]
                return (SIMD3(sin(a)*p.0,p.1,cos(a)*p.0),SIMD3(sin(a)*p.2,p.3,cos(a)*p.2))
            }
        } else if let shape = original as? SCNTube {
            let outer = Float(shape.outerRadius), inner = Float(shape.innerRadius), half = Float(shape.height)*0.5, radial = max(16,shape.radialSegmentCount)
            for (radius,direction): (Float,Float) in [(outer,1),(inner,-1)] {
                mesh.grid(u: radial,v: 1) { i,j in
                    let a = Float(i)*2*Float.pi/Float(radial)
                    return (SIMD3(sin(a)*radius,j == 0 ? -half : half,cos(a)*radius),SIMD3(sin(a)*direction,0,cos(a)*direction))
                }
            }
            for side: Float in [-1,1] {
                mesh.grid(u: radial,v: 1) { i,j in
                    let a = Float(i)*2*Float.pi/Float(radial), r = j == 0 ? inner : outer
                    return (SIMD3(sin(a)*r,side*half,cos(a)*r),SIMD3(0,side,0))
                }
            }
        } else if original is SCNCylinder || original is SCNCone {
            let top: Float, bottom: Float, height: Float, radial: Int
            if let cylinder = original as? SCNCylinder {
                top = Float(cylinder.radius); bottom = top; height = Float(cylinder.height); radial = max(16,cylinder.radialSegmentCount)
            } else {
                let cone = original as! SCNCone
                top = Float(cone.topRadius); bottom = Float(cone.bottomRadius); height = Float(cone.height); radial = max(16,cone.radialSegmentCount)
            }
            let normal = simd_normalize(SIMD2<Float>(height,bottom-top))
            mesh.grid(u: radial,v: 1) { i,j in
                let a = Float(i)*2*Float.pi/Float(radial), r = j == 0 ? bottom : top
                return (SIMD3(sin(a)*r,(Float(j)-0.5)*height,cos(a)*r),SIMD3(sin(a)*normal.x,normal.y,cos(a)*normal.x))
            }
            mesh.disk(radius: top,y: height*0.5,upward: true,segments: radial)
            mesh.disk(radius: bottom,y: -height*0.5,upward: false,segments: radial)
        } else { return nil }
        return mesh.geometry()
    }

    static func extrude(_ shape: SCNShape) throws -> SCNGeometry {
        guard let path = shape.path else { throw Failure(message: "Missing original shape path") }
        var points: [SIMD2<Float>] = []
        var associated = [NSPoint](repeating: .zero, count: 3)
        for i in 0..<path.elementCount {
            let type = path.element(at: i, associatedPoints: &associated)
            switch type {
            case .moveTo, .lineTo: points.append(SIMD2(Float(associated[0].x), Float(associated[0].y)))
            case .closePath: break
            default: throw Failure(message: "Unexpected curved or compound shape: update CPU tessellator")
            }
        }
        if points.first == points.last { points.removeLast() }
        guard points.count >= 3 else { throw Failure(message: "Empty shape contour") }
        func cross(_ a: SIMD2<Float>, _ b: SIMD2<Float>, _ c: SIMD2<Float>) -> Float { (b.x-a.x)*(c.y-a.y) - (b.y-a.y)*(c.x-a.x) }
        let signedArea = points.indices.reduce(Float(0)) { sum, i in let n = (i+1) % points.count; return sum + points[i].x * points[n].y - points[n].x * points[i].y }
        if signedArea < 0 { points.reverse() }
        var contour = Array(points.indices), faces: [Int32] = []
        while contour.count > 3 {
            var clipped = false
            for i in contour.indices {
                let a = contour[(i+contour.count-1)%contour.count], b = contour[i], c = contour[(i+1)%contour.count]
                guard cross(points[a], points[b], points[c]) > 0.00000000001 else { continue }
                let contains = contour.contains { j in
                    guard j != a && j != b && j != c else { return false }
                    return cross(points[a], points[b], points[j]) >= 0 && cross(points[b], points[c], points[j]) >= 0 && cross(points[c], points[a], points[j]) >= 0
                }
                if !contains {
                    faces += [Int32(a), Int32(b), Int32(c)]; contour.remove(at: i); clipped = true; break
                }
            }
            guard clipped else { throw Failure(message: "Cannot triangulate original concave shape") }
        }
        faces += contour.map(Int32.init)
        let depth = Float(shape.extrusionDepth), bevel = min(Float(shape.chamferRadius), depth * 0.45)
        let center = points.reduce(SIMD2<Float>.zero, +) / Float(points.count)
        let radius = points.map { simd_length($0-center) }.max()!
        let inset = max(0.80, 1 - bevel / max(radius, 0.0001))
        var vertices: [SCNVector3] = [], normals: [SCNVector3] = [], indices: [Int32] = []
        for side: Float in [1, -1] {
            let offset = Int32(vertices.count)
            for p in points {
                let q = center + (p-center) * inset
                vertices.append(SCNVector3(q.x, q.y, side * depth * 0.5)); normals.append(SCNVector3(0, 0, side))
            }
            for i in stride(from: 0, to: faces.count, by: 3) {
                indices += side > 0 ? [offset+faces[i], offset+faces[i+1], offset+faces[i+2]] : [offset+faces[i+2], offset+faces[i+1], offset+faces[i]]
            }
        }
        func quad(_ values: [SIMD3<Float>], _ normal: SIMD3<Float>) {
            let start = Int32(vertices.count)
            for p in values { vertices.append(SCNVector3(p.x, p.y, p.z)); normals.append(SCNVector3(normal.x, normal.y, normal.z)) }
            indices += [start, start+1, start+2, start, start+2, start+3]
        }
        for i in points.indices {
            let a = points[i], b = points[(i+1)%points.count]
            let ia = center + (a-center)*inset, ib = center + (b-center)*inset
            let edge = simd_normalize(SIMD3(b.y-a.y, a.x-b.x, 0))
            let outerZ = depth * 0.5 - bevel
            quad([SIMD3(a.x,a.y,-outerZ), SIMD3(b.x,b.y,-outerZ), SIMD3(b.x,b.y,outerZ), SIMD3(a.x,a.y,outerZ)], edge)
            quad([SIMD3(a.x,a.y,outerZ), SIMD3(b.x,b.y,outerZ), SIMD3(ib.x,ib.y,depth*0.5), SIMD3(ia.x,ia.y,depth*0.5)], simd_normalize(edge+SIMD3(0,0,1)))
            quad([SIMD3(ia.x,ia.y,-depth*0.5), SIMD3(ib.x,ib.y,-depth*0.5), SIMD3(b.x,b.y,-outerZ), SIMD3(a.x,a.y,-outerZ)], simd_normalize(edge+SIMD3(0,0,-1)))
        }
        // SceneKit's bevel clips sharp contour extrema slightly. Match its
        // evaluated shape bounds while retaining the original concave contour.
        let bounds = shape.boundingBox
        let desiredLow = SIMD3<Float>(Float(bounds.min.x),Float(bounds.min.y),Float(bounds.min.z))
        let desiredHigh = SIMD3<Float>(Float(bounds.max.x),Float(bounds.max.y),Float(bounds.max.z))
        var actualLow = SIMD3<Float>(repeating: .infinity), actualHigh = SIMD3<Float>(repeating: -.infinity)
        for vertex in vertices {
            let p = SIMD3<Float>(Float(vertex.x),Float(vertex.y),Float(vertex.z))
            actualLow = simd_min(actualLow,p); actualHigh = simd_max(actualHigh,p)
        }
        let scale = (desiredHigh-desiredLow)/(actualHigh-actualLow)
        for i in vertices.indices {
            let p = SIMD3<Float>(Float(vertices[i].x),Float(vertices[i].y),Float(vertices[i].z))
            let q = desiredLow+(p-actualLow)*scale
            vertices[i] = SCNVector3(q.x,q.y,q.z)
            let n = simd_normalize(SIMD3<Float>(Float(normals[i].x),Float(normals[i].y),Float(normals[i].z))/scale)
            normals[i] = SCNVector3(n.x,n.y,n.z)
        }
        return SCNGeometry(sources: [SCNGeometrySource(vertices: vertices), SCNGeometrySource(normals: normals)], elements: [SCNGeometryElement(indices: indices, primitiveType: .triangles)])
    }

    static func export(_ root: SCNNode, relativeTo reference: SCNNode, useRigs: Bool = true, fixedRig: String = "", ignoreHidden: Bool = false) throws -> [Instance] {
        var result: [Instance] = []
        func visit(_ node: SCNNode, owner: SCNNode?, label: String) throws {
            guard ignoreHidden || !node.isHidden else { return }
            let nextOwner = useRigs && rigNames.contains(node.name ?? "") ? node : owner
            let nextLabel = node.name ?? label
            if let geometry = node.geometry {
                let id = try mesh(geometry)
                let local = node.simdConvertTransform(matrix_identity_float4x4, to: nextOwner ?? reference)
                let color = (geometry.firstMaterial?.diffuse.contents as? NSColor)?.usingColorSpace(.sRGB) ?? .white
                let rgba = [Float(color.redComponent), Float(color.greenComponent), Float(color.blueComponent), Float(color.alphaComponent)]
                let matrix = floats(local)
                let rig = nextOwner?.name ?? fixedRig
                var signature = Data("\(id)/\(rig)".utf8)
                for f in matrix + rgba { append(f.bitPattern, to: &signature) }
                result.append(Instance(key: hash(signature), mesh: id, rig: rig, matrix: matrix, color: rgba, label: nextLabel))
            }
            for child in node.childNodes { try visit(child, owner: nextOwner, label: nextLabel) }
        }
        try visit(root, owner: nil, label: "")
        return result
    }

    static func main() throws {
        let root = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? FileManager.default.currentDirectoryPath)
        let output = root.appendingPathComponent("android/app/src/main/assets/scene")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let economy = try String(contentsOf: root.appendingPathComponent("PiyakBank/Shared/Economy.swift"), encoding: .utf8)
        let regex = try NSRegularExpression(pattern: #"\.init\(id: "([A-Za-z]+\.[a-z_]+)""#)
        let ids = regex.matches(in: economy, range: NSRange(economy.startIndex..., in: economy)).map { String(economy[Range($0.range(at: 1), in: economy)!]) }
        guard ids.count == 81, Set(ids).count == 81 else { throw Failure(message: "Expected all 81 catalog models") }
        let baseScene = PiyakScene.make(equipped: [:], animated: false)
        let chick = baseScene.rootNode.childNode(withName: "piyak", recursively: false)!
        let base = try export(chick, relativeTo: baseScene.rootNode)
        var rigs: [Rig] = []
        func recordRigs(_ node: SCNNode, parent: String) {
            let named = rigNames.contains(node.name ?? "")
            if named { rigs.append(Rig(name: node.name!, parent: parent, matrix: floats(node.simdTransform))) }
            for child in node.childNodes { recordRigs(child, parent: named ? node.name! : parent) }
        }
        recordRigs(chick, parent: "")
        let baseKeys = Set(base.map(\.key))
        var rooms: [String: [Instance]] = [:], items: [String: Delta] = [:], previews: [String: Preview] = [:]
        for id in ids {
            try autoreleasepool {
                let slot = String(id.split(separator: ".")[0])
                let scene = PiyakScene.make(equipped: [slot: id], animated: false)
                let rootNode = scene.rootNode
                if slot == "bg" {
                    var room: [Instance] = []
                    for child in rootNode.childNodes where child.name != "piyak" && child.camera == nil && child.light == nil {
                        room += try export(child, relativeTo: rootNode, useRigs: false)
                    }
                    rooms[id] = room
                    items[id] = Delta(add: [], remove: [])
                } else if ["bodyFront", "headTop", "eyes", "neck"].contains(slot) {
                    let character = rootNode.childNode(withName: "piyak", recursively: false)!
                    let instances = try export(character, relativeTo: rootNode)
                    let keys = Set(instances.map(\.key))
                    items[id] = Delta(add: instances.filter { !baseKeys.contains($0.key) }, remove: base.filter { !keys.contains($0.key) }.map(\.key))
                } else {
                    let names = ["floorProp": "room.prop", "bigFurniture": "room.furniture", "rug": "room.rug", "wallDeco": "room.wall"]
                    guard let name = names[slot], let child = rootNode.childNode(withName: name, recursively: false) else { throw Failure(message: "Missing \(id)") }
                    items[id] = Delta(add: try export(child, relativeTo: rootNode, useRigs: false), remove: [])
                }
                let preview = PiyakScene.itemScene(id: id, slot: slot)
                let camera = preview.rootNode.childNodes.first { $0.camera != nil }!
                let eye = camera.simdWorldPosition
                let direction = camera.simdWorldFront
                let target = eye + direction * 7
                previews[id] = Preview(instances: try export(preview.rootNode, relativeTo: preview.rootNode, useRigs: false), camera: [eye.x, eye.y, eye.z], target: [target.x, target.y, target.z], scale: Float(camera.camera!.orthographicScale))
            }
        }
        var effects: [String: [Instance]] = [:]
        let priorChickCount = chick.childNodes.count
        let behavior = PiyakBehavior(scene: baseScene, equipped: [:], announce: { _ in })
        _ = behavior // Retain while exporting its original book, watering can and drops.
        let added = Array(chick.childNodes.dropFirst(priorChickCount))
        for (i, child) in added.enumerated() {
            let name = i == 0 ? "book" : i == 1 ? "wateringCan" : "drop.\(i-2)"
            effects[name] = try export(child, relativeTo: chick, useRigs: false, fixedRig: "piyak", ignoreHidden: true)
        }
        let sceneSource = try Data(contentsOf: root.appendingPathComponent("PiyakBank/Views/PiyakScene.swift"))
        let manifest = Manifest(sourceSHA256: hash(sceneSource), rigs: rigs, base: base, rooms: rooms, items: items, previews: previews, effects: effects, meshCount: meshIDs.count, triangleCount: triangleCount, meshBounds: meshBounds)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(manifest).write(to: output.appendingPathComponent("scene.json"), options: .atomic)
        try meshData.write(to: output.appendingPathComponent("meshes.bin"), options: .atomic)
        print("Exported \(ids.count) catalog items; \(meshIDs.count) shared meshes, \(triangleCount) triangles; \(meshData.count) mesh bytes")
    }
}
