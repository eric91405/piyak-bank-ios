import Foundation
import AppKit
import SceneKit
import CryptoKit

/// Regenerate original artwork from the same geometry used by the app.
/// xcrun swiftc PiyakBank/Views/PiyakScene.swift scripts/GenerateAssets.swift -o /tmp/piyak-assets
/// /tmp/piyak-assets <repository path>
@main
struct GenerateAssets {
    static func main() throws {
        let root = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? FileManager.default.currentDirectoryPath)
        let mainAssets = root.appendingPathComponent("PiyakBank/Assets.xcassets")
        let watchAssets = root.appendingPathComponent("PiyakWatch Watch App/Assets.xcassets")
        func render(_ scene: SCNScene, size: Int) -> Data {
            let renderer = SCNRenderer(device: nil, options: nil)
            renderer.scene = scene
            renderer.pointOfView = scene.rootNode.childNodes.first { $0.camera != nil }
            let image = renderer.snapshot(atTime: 0, with: CGSize(width: size, height: size), antialiasingMode: .multisampling4X)
            return NSBitmapImageRep(data: image.tiffRepresentation!)!.representation(using: .png, properties: [:])!
        }
        func imageSet(_ name: String, data: Data, assets: URL) throws {
            let folder = assets.appendingPathComponent(name + ".imageset")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try data.write(to: folder.appendingPathComponent("image.png"))
            let json: [String: Any] = ["images": [["filename": "image.png", "idiom": "universal"]], "info": ["author": "xcode", "version": 1]]
            try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]).write(to: folder.appendingPathComponent("Contents.json"))
        }
        let mascot = render(PiyakScene.make(animated: false, icon: true), size: 512)
        try imageSet("AppMascot", data: mascot, assets: mainAssets)
        try imageSet("WatchMascot", data: mascot, assets: watchAssets)
        // App icons (iOS default/dark/tinted and watchOS) are rendered from the same model by
        // scripts/app_icon (Blender Cycles) and are intentionally not overwritten here.
        let source = try String(contentsOf: root.appendingPathComponent("PiyakBank/Shared/Economy.swift"), encoding: .utf8)
        let regex = try NSRegularExpression(pattern: #"\.init\(id: "([A-Za-z]+\.[a-z_]+)""#)
        let ids = regex.matches(in: source, range: NSRange(source.startIndex..., in: source)).compactMap {
            Range($0.range(at: 1), in: source).map { String(source[$0]) }
        }
        for id in ids {
            try autoreleasepool {
                let slot = String(id.split(separator: ".")[0])
                let scene = PiyakScene.itemScene(id: id, slot: slot)
                try imageSet("thumb_" + id.replacingOccurrences(of: ".", with: "_"), data: render(scene, size: 320), assets: mainAssets)
            }
        }
        var sourceHashes: [String: String] = [:]
        for path in ["PiyakBank/Views/PiyakScene.swift", "scripts/GenerateAssets.swift"] {
            let bytes = try Data(contentsOf: root.appendingPathComponent(path))
            sourceHashes[path] = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        }
        let manifest: [String: Any] = ["sources": sourceHashes, "catalogIds": ids.sorted()]
        try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
            .write(to: root.appendingPathComponent("scripts/generated_assets.json"))
        print("Generated mascots and \(ids.count) item previews; source fingerprint saved.")
    }
}
