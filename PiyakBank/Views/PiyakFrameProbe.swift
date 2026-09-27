#if DEBUG
import SceneKit
import QuartzCore

/// Opt-in render-callback measurements; no timer, UI updates or release code.
/// Long idle gaps start a fresh sample instead of reporting them as dropped frames.
final class PiyakFrameProbe: NSObject, SCNSceneRendererDelegate {
    private let lock = NSLock()
    private var mode = ""
    private var continuous = false
    private var preferredFPS = 0
    private var previousTime: CFTimeInterval?
    private var intervals: [CFTimeInterval] = []

    func configure(mode: String, continuous: Bool, preferredFPS: Int) {
        lock.lock(); defer { lock.unlock() }
        guard self.mode != mode || self.continuous != continuous || self.preferredFPS != preferredFPS else { return }
        if self.continuous, intervals.count >= 3 { report() }
        self.mode = mode
        self.continuous = continuous
        self.preferredFPS = preferredFPS
        previousTime = nil
        intervals.removeAll(keepingCapacity: true)
        print("[PiyakFrames] mode=\(mode) continuous=\(continuous) target=\(preferredFPS)")
    }

    func renderer(_ renderer: SCNSceneRenderer, didRenderScene scene: SCNScene, atTime time: TimeInterval) {
        let now = CACurrentMediaTime()
        lock.lock(); defer { lock.unlock() }
        defer { previousTime = now }
        guard continuous, let previousTime else { return }
        let interval = now - previousTime
        guard interval > 0, interval < 0.25 else {
            intervals.removeAll(keepingCapacity: true)
            return
        }
        intervals.append(interval)
        guard intervals.count >= 120 else { return }
        report()
        intervals.removeAll(keepingCapacity: true)
    }

    private func report() {
        let sorted = intervals.sorted()
        let fps = Double(intervals.count) / intervals.reduce(0, +)
        let p95 = sorted[Int(Double(sorted.count - 1) * 0.95)] * 1000
        let slow = intervals.filter { $0 > 1.5 / Double(preferredFPS) }.count
        print(String(format: "[PiyakFrames] mode=%@ target=%d frames=%d fps=%.1f p95_ms=%.1f slow=%d",
                     mode, preferredFPS, intervals.count, fps, p95, slow))
    }
}
#endif
