import Foundation
import AppKit
import SceneKit
import Darwin

/// Offline geometry and visual QA. This does not boot a simulator or modify app assets.
/// First regenerate assets from the final scene source, then run this script serially,
/// with Xcode builds and simulators stopped:
///
/// xcrun swiftc PiyakBank/Views/PiyakScene.swift scripts/ValidateScene.swift -o /tmp/piyak-scene-qa
/// /tmp/piyak-scene-qa <repository path> <output directory>
///
/// The existing 81 thumbnails are inspected and assembled into a contact sheet.
/// Only nine full room combinations are rendered. Conservative camera bounds are
/// warnings: rounded geometry does not occupy every corner of its bounding box.
/// A passing report still requires looking at both contact sheets for fitting,
/// intersections, recognizable silhouettes and surface quality.
@main
struct ValidateScene {
    struct Finding: Codable {
        let severity: String
        let scene: String
        let detail: String
    }

    struct ImageCheck: Codable {
        let id: String
        let width: Int
        let height: Int
        let occupiedFraction: Double
        let solidBorderPixels: Int
        let alphaBounds: [Int]?
    }

    struct CameraCheck: Codable {
        let id: String
        let normalizedBounds: [Double]
    }

    struct RoomCheck: Codable {
        let image: String
        let equipped: [String: String]
    }

    struct Report: Codable {
        let createdAt: String
        let catalogCount: Int
        let inspectedScenes: Int
        let findings: [Finding]
        let thumbnails: [ImageCheck]
        let cameras: [CameraCheck]
        let rooms: [RoomCheck]
        let reviewInstructions: [String]
    }

    struct SheetEntry {
        let label: String
        let image: NSImage
    }

    final class Audit {
        var findings: [Finding] = []
        var cameras: [CameraCheck] = []
        var sceneCount = 0

        func record(_ severity: String, _ scene: String, _ detail: String) {
            findings.append(Finding(severity: severity, scene: scene, detail: detail))
        }

        func inspect(_ scene: SCNScene, label: String, thumbnail: Bool = false) {
            sceneCount += 1
            var geometryCount = 0
            var nodes = [scene.rootNode]
            while let node = nodes.popLast() {
                nodes.append(contentsOf: node.childNodes)
                let name = node.name ?? "unnamed node"
                let transform = node.simdWorldTransform
                let components = [transform.columns.0, transform.columns.1,
                                  transform.columns.2, transform.columns.3]
                    .flatMap { [$0.x, $0.y, $0.z, $0.w] }
                if components.contains(where: { !$0.isFinite }) {
                    record("error", label, "Non-finite world transform: \(name)")
                }
                if [node.scale.x, node.scale.y, node.scale.z].contains(where: { abs($0) < 0.000001 }) {
                    record("warning", label, "Collapsed scale: \(name). Check whether this is an intentional hidden part.")
                }
                guard let geometry = node.geometry else { continue }
                geometryCount += 1
                let bounds = geometry.boundingBox
                let values = [bounds.min.x, bounds.min.y, bounds.min.z,
                              bounds.max.x, bounds.max.y, bounds.max.z]
                if values.contains(where: { !$0.isFinite }) {
                    record("error", label, "Non-finite geometry bounds: \(name)")
                } else if bounds.min.x > bounds.max.x || bounds.min.y > bounds.max.y || bounds.min.z > bounds.max.z {
                    record("error", label, "Inverted geometry bounds: \(name)")
                } else if bounds.min.x == bounds.max.x && bounds.min.y == bounds.max.y && bounds.min.z == bounds.max.z {
                    record("error", label, "Empty geometry bounds: \(name)")
                }
                if let box = geometry as? SCNBox {
                    let sides = [box.width, box.height, box.length]
                    if sides.contains(where: { !$0.isFinite || $0 <= 0 }) {
                        record("error", label, "SCNBox has a non-positive or non-finite dimension: \(name)")
                    }
                    let limit = (sides.min() ?? 0) / 2
                    if !box.chamferRadius.isFinite || box.chamferRadius < 0 || box.chamferRadius > limit + 0.000001 {
                        record("error", label, "SCNBox chamfer \(box.chamferRadius) exceeds safe half-thickness \(limit): \(name)")
                    }
                }
                for semantic: SCNGeometrySource.Semantic in [.vertex, .normal] {
                    for source in geometry.sources(for: semantic) {
                        inspect(source, label: label, nodeName: name)
                    }
                }
            }
            if geometryCount == 0 { record("error", label, "Scene contains no geometry.") }
            guard let camera = camera(in: scene) else {
                record("error", label, "Scene has no camera.")
                return
            }
            if thumbnail { inspectCamera(scene, camera: camera, label: label) }
        }

        private func inspect(_ source: SCNGeometrySource, label: String, nodeName: String) {
            // SceneKit parametric primitives may expose no CPU geometry source.
            // Custom surface meshes do, and must never contain NaN/Inf positions.
            guard source.vectorCount > 0, source.usesFloatComponents else { return }
            guard [4, 8].contains(source.bytesPerComponent) else {
                record("warning", label, "Uninspected floating point format on \(nodeName): \(source.bytesPerComponent) bytes.")
                return
            }
            let componentCount = min(3, source.componentsPerVector)
            let packedSize = source.componentsPerVector * source.bytesPerComponent
            let stride = source.dataStride == 0 ? packedSize : source.dataStride
            let lastByte = source.dataOffset + (source.vectorCount - 1) * stride + componentCount * source.bytesPerComponent
            guard source.dataOffset >= 0, componentCount > 0, stride > 0, lastByte <= source.data.count else {
                record("error", label, "Geometry source extends beyond its buffer: \(nodeName)")
                return
            }
            let nonFinite = source.data.withUnsafeBytes { buffer -> Bool in
                for index in 0..<source.vectorCount {
                    for component in 0..<componentCount {
                        let offset = source.dataOffset + index * stride + component * source.bytesPerComponent
                        let number: Double = source.bytesPerComponent == 4
                            ? Double(buffer.loadUnaligned(fromByteOffset: offset, as: Float.self))
                            : buffer.loadUnaligned(fromByteOffset: offset, as: Double.self)
                        if !number.isFinite { return true }
                    }
                }
                return false
            }
            if nonFinite { record("error", label, "Non-finite \(source.semantic.rawValue) data: \(nodeName)") }
        }

        private func inspectCamera(_ scene: SCNScene, camera: SCNNode, label: String) {
            guard let lens = camera.camera else { return }
            guard lens.usesOrthographicProjection else {
                record("warning", label, "Perspective thumbnail camera: manually review framing.")
                return
            }
            let extent = lens.orthographicScale
            guard extent.isFinite, extent > 0 else {
                record("error", label, "Invalid orthographic camera scale.")
                return
            }
            // Thumbnails are square, so horizontal/vertical projectionDirection
            // have the same extent. Transform each local corner into camera space.
            var minX = Double.infinity, minY = Double.infinity
            var maxX = -Double.infinity, maxY = -Double.infinity
            scene.rootNode.enumerateChildNodes { node, _ in
                guard let geometry = node.geometry, !node.isHidden, node.opacity > 0 else { return }
                let bounds = geometry.boundingBox
                for x in [bounds.min.x, bounds.max.x] {
                    for y in [bounds.min.y, bounds.max.y] {
                        for z in [bounds.min.z, bounds.max.z] {
                            let point = camera.convertPosition(SCNVector3(x, y, z), from: node)
                            let u = (Double(point.x) / extent + 1) / 2
                            let v = (Double(point.y) / extent + 1) / 2
                            minX = min(minX, u); maxX = max(maxX, u)
                            minY = min(minY, v); maxY = max(maxY, v)
                        }
                    }
                }
            }
            guard [minX, minY, maxX, maxY].allSatisfy(\.isFinite) else {
                record("error", label, "Cannot calculate finite thumbnail camera bounds.")
                return
            }
            cameras.append(CameraCheck(id: label, normalizedBounds: [minX, minY, maxX, maxY]))
            if minX < -0.03 || minY < -0.03 || maxX > 1.03 || maxY > 1.03 {
                record("warning", label, "Conservative projected bounds leave the frame: \([minX, minY, maxX, maxY].map { String(format: "%.3f", $0) }.joined(separator: ", ")). Check actual alpha bounds/contact sheet.")
            }
        }

        func inspectImage(_ image: NSImage, label: String, inspectEdges: Bool) throws -> ImageCheck {
            var rect = CGRect(origin: .zero, size: image.size)
            guard let cgImage = image.cgImage(forProposedRect: &rect, context: nil, hints: nil) else {
                throw QAError("Cannot decode CGImage for \(label)")
            }
            let width = cgImage.width, height = cgImage.height
            var pixels = [UInt8](repeating: 0, count: width * height * 4)
            try pixels.withUnsafeMutableBytes { buffer in
                guard let context = CGContext(data: buffer.baseAddress, width: width, height: height,
                    bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue) else {
                    throw QAError("Cannot allocate pixel buffer for \(label)")
                }
                context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            }
            var occupied = 0, border = 0
            var minX = width, minY = height, maxX = -1, maxY = -1
            var darkest = 255, lightest = 0
            for y in 0..<height {
                for x in 0..<width {
                    let offset = (y * width + x) * 4
                    let alpha = pixels[offset + 3]
                    if alpha >= 40 {
                        occupied += 1
                        minX = min(minX, x); minY = min(minY, y)
                        maxX = max(maxX, x); maxY = max(maxY, y)
                    }
                    if alpha >= 200 {
                        let level = (Int(pixels[offset]) + Int(pixels[offset + 1]) + Int(pixels[offset + 2])) / 3
                        darkest = min(darkest, level); lightest = max(lightest, level)
                        if x < 2 || y < 2 || x >= width - 2 || y >= height - 2 { border += 1 }
                    }
                }
            }
            let fraction = Double(occupied) / Double(width * height)
            if fraction < 0.005 { record("error", label, "Rendered image is blank or nearly blank.") }
            if occupied > 0 && lightest < 12 {
                record("error", label, "Rendered image is almost black; check Metal/rendering availability.")
            } else if lightest - darkest < 4 && fraction > 0.95 {
                record("warning", label, "Rendered image is nearly a flat color.")
            }
            // Ignore translucent shadows and isolated antialiasing specks. A
            // solid run at the border is evidence of actual silhouette clipping.
            if inspectEdges && border > max(12, (width + height) / 16) {
                record("error", label, "\(border) solid border pixels indicate a clipped thumbnail silhouette.")
            } else if inspectEdges && border > 4 {
                record("warning", label, "\(border) solid pixels reach the thumbnail edge; inspect framing.")
            }
            return ImageCheck(id: label, width: width, height: height,
                occupiedFraction: fraction, solidBorderPixels: border,
                alphaBounds: maxX >= 0 ? [minX, minY, maxX, maxY] : nil)
        }
    }

    struct QAError: Error, CustomStringConvertible {
        let description: String
        init(_ description: String) { self.description = description }
    }

    static func camera(in scene: SCNScene) -> SCNNode? {
        var result: SCNNode?
        scene.rootNode.enumerateChildNodes { node, stop in
            if node.camera != nil { result = node; stop.pointee = true }
        }
        return result
    }

    static func main() throws {
        let arguments = Array(CommandLine.arguments.dropFirst())
        let root = URL(fileURLWithPath: arguments.first ?? FileManager.default.currentDirectoryPath)
        let output = URL(fileURLWithPath: arguments.count > 1 ? arguments[1] : "/tmp/piyak-scene-qa")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let source = try String(contentsOf: root.appendingPathComponent("PiyakBank/Shared/Economy.swift"), encoding: .utf8)
        let pattern = try NSRegularExpression(pattern: #"\.init\(id: "([A-Za-z]+\.[a-z_]+)""#)
        let ids = pattern.matches(in: source, range: NSRange(source.startIndex..., in: source)).compactMap {
            Range($0.range(at: 1), in: source).map { String(source[$0]) }
        }
        let audit = Audit()
        guard !ids.isEmpty else { throw QAError("Catalog parser found no item IDs.") }
        if ids.count != 81 || Set(ids).count != 81 {
            audit.record("error", "catalog", "Expected 81 unique IDs, found \(ids.count) entries / \(Set(ids).count) unique.")
        }
        let slots = ["bodyFront", "headTop", "eyes", "neck", "bg", "wallDeco", "bigFurniture", "floorProp", "rug"]
        let grouped = Dictionary(grouping: ids, by: { String($0.split(separator: ".")[0]) })
            .mapValues { $0.sorted() }
        for slot in slots where grouped[slot]?.count != 9 {
            audit.record("error", "catalog", "Expected 9 items in \(slot), found \(grouped[slot]?.count ?? 0).")
        }
        var imageChecks: [ImageCheck] = []
        var thumbEntries: [SheetEntry] = []
        var thumbnailDigests: [Data: [String]] = [:]
        for slot in slots {
            for id in grouped[slot] ?? [] {
                try autoreleasepool {
                    let item = PiyakScene.itemScene(id: id, slot: slot)
                    audit.inspect(item, label: "item/\(id)", thumbnail: slot != "bg")
                    var equipped = PiyakScene.defaultItems
                    equipped[slot] = id
                    audit.inspect(PiyakScene.make(equipped: equipped, animated: false), label: "room/\(id)")
                    let asset = root.appendingPathComponent("PiyakBank/Assets.xcassets/thumb_\(id.replacingOccurrences(of: ".", with: "_")).imageset/image.png")
                    guard let image = NSImage(contentsOf: asset) else {
                        audit.record("error", id, "Missing or undecodable thumbnail: \(asset.path)")
                        return
                    }
                    let data = try Data(contentsOf: asset)
                    thumbnailDigests[data, default: []].append(id)
                    let check = try audit.inspectImage(image, label: id, inspectEdges: slot != "bg")
                    imageChecks.append(check)
                    if check.width != 320 || check.height != 320 {
                        audit.record("warning", id, "Thumbnail is \(check.width)×\(check.height); generator normally emits 320×320.")
                    }
                    thumbEntries.append(SheetEntry(label: id, image: image))
                }
            }
        }
        for duplicateIDs in thumbnailDigests.values where duplicateIDs.count > 1 {
            audit.record("warning", "catalog", "Byte-identical thumbnails: \(duplicateIDs.sorted().joined(separator: ", ")). Check distinct model routing.")
        }
        try contactSheet(thumbEntries, columns: 9, cellSize: CGSize(width: 180, height: 200),
                         title: "Piyak Bank — 81 catalog models", destination: output.appendingPathComponent("catalog-contact-sheet.png"))

        // Across these nine combinations, each catalog item appears once with
        // all eight other slots populated. This complements isolated thumbnails.
        var rooms: [RoomCheck] = []
        var roomEntries: [SheetEntry] = []
        let renderer = SCNRenderer(device: nil, options: nil)
        for index in 0..<9 {
            try autoreleasepool {
                var equipped: [String: String] = [:]
                for slot in slots {
                    if let choices = grouped[slot], choices.indices.contains(index) { equipped[slot] = choices[index] }
                }
                let scene = PiyakScene.make(equipped: equipped, animated: false)
                audit.inspect(scene, label: "combination/\(index + 1)")
                renderer.scene = scene
                renderer.pointOfView = camera(in: scene)
                let image = renderer.snapshot(atTime: 0, with: CGSize(width: 640, height: 480), antialiasingMode: .multisampling4X)
                let filename = String(format: "room-%02d.png", index + 1)
                try png(image).write(to: output.appendingPathComponent(filename))
                _ = try audit.inspectImage(image, label: filename, inspectEdges: false)
                rooms.append(RoomCheck(image: filename, equipped: equipped))
                let outfit = [equipped["bodyFront"], equipped["headTop"], equipped["eyes"], equipped["neck"]]
                    .compactMap { $0?.split(separator: ".").last.map(String.init) }.joined(separator: " · ")
                roomEntries.append(SheetEntry(label: "\(index + 1). \(outfit)", image: image))
                renderer.scene = nil
                renderer.pointOfView = nil
            }
        }
        try contactSheet(roomEntries, columns: 3, cellSize: CGSize(width: 480, height: 390),
                         title: "Piyak Bank — nine fully equipped rooms", destination: output.appendingPathComponent("rooms-contact-sheet.png"))
        let report = Report(createdAt: ISO8601DateFormatter().string(from: Date()), catalogCount: ids.count,
            inspectedScenes: audit.sceneCount, findings: audit.findings, thumbnails: imageChecks,
            cameras: audit.cameras, rooms: rooms, reviewInstructions: [
                "Regenerate app assets from the final PiyakScene source before running this audit. Existing thumbnails are reused to limit GPU work.",
                "Inspect catalog-contact-sheet.png for protruding bars, detached clothing, silhouette cropping and items that look incorrectly alike.",
                "Inspect rooms-contact-sheet.png and room-01…09.png for outfit layering, hat/tuft and glasses/beak collisions, and room-object placement.",
                "Camera bounds are conservative local bounding-box corners; image alpha and visual inspection determine actual clipping.",
                "This script validates static model scenes. Review walking, turning, interaction contact points and start/pause/resume behavior separately.",
                "For future behavior snapshots, drive one SCNRenderer delegate/scene clock through deterministic times, record presentation transforms, and assert floor bounds plus preserved equipment. Do not use wall-clock sleeps or launch additional simulators."
            ])
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(report).write(to: output.appendingPathComponent("report.json"))
        let errors = audit.findings.filter { $0.severity == "error" }
        let warnings = audit.findings.filter { $0.severity == "warning" }
        print("Inspected \(audit.sceneCount) scenes, \(imageChecks.count) existing thumbnails, and rendered \(rooms.count) complete rooms.")
        print("\(errors.count) errors, \(warnings.count) review warnings. Report and contact sheets: \(output.path)")
        for finding in (errors + warnings).prefix(30) {
            print("[\(finding.severity)] \(finding.scene): \(finding.detail)")
        }
        if !errors.isEmpty { exit(1) }
    }

    static func png(_ image: NSImage) throws -> Data {
        guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
              let data = bitmap.representation(using: .png, properties: [:]) else {
            throw QAError("Could not encode PNG image.")
        }
        return data
    }

    static func contactSheet(_ entries: [SheetEntry], columns: Int, cellSize: CGSize,
                             title: String, destination: URL) throws {
        let header: CGFloat = 56
        let rows = max(1, (entries.count + columns - 1) / columns)
        let width = Int(cellSize.width) * columns
        let height = Int(cellSize.height) * rows + Int(header)
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
            throw QAError("Could not allocate contact sheet.")
        }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        NSColor(calibratedWhite: 0.94, alpha: 1).setFill()
        NSRect(x: 0, y: 0, width: width, height: height).fill()
        (title as NSString).draw(at: CGPoint(x: 18, y: CGFloat(height) - 36), withAttributes: [
            .font: NSFont.systemFont(ofSize: 20, weight: .semibold), .foregroundColor: NSColor.darkGray
        ])
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byWordWrapping
        for (index, entry) in entries.enumerated() {
            let x = CGFloat(index % columns) * cellSize.width
            let y = CGFloat(height) - header - CGFloat(index / columns + 1) * cellSize.height
            let cell = CGRect(x: x + 6, y: y + 6, width: cellSize.width - 12, height: cellSize.height - 12)
            NSColor.white.setFill()
            NSBezierPath(roundedRect: cell, xRadius: 9, yRadius: 9).fill()
            let imageArea = CGRect(x: x + 12, y: y + 42, width: cellSize.width - 24, height: cellSize.height - 54)
            let ratio = min(imageArea.width / entry.image.size.width, imageArea.height / entry.image.size.height)
            let size = CGSize(width: entry.image.size.width * ratio, height: entry.image.size.height * ratio)
            let target = CGRect(x: imageArea.midX - size.width / 2, y: imageArea.midY - size.height / 2,
                                width: size.width, height: size.height)
            entry.image.draw(in: target, from: .zero, operation: .sourceOver, fraction: 1)
            (entry.label as NSString).draw(in: CGRect(x: x + 10, y: y + 10, width: cellSize.width - 20, height: 30), withAttributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 10, weight: .regular),
                .foregroundColor: NSColor.darkGray, .paragraphStyle: paragraph
            ])
        }
        context.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()
        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            throw QAError("Could not encode contact sheet.")
        }
        try data.write(to: destination)
    }
}
