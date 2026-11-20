#if DEBUG
import Foundation
import QuartzCore

/// Debug-only frame cost log, started by the `-hitchLog` launch argument.
///
/// Measures main-thread CPU time per frame rather than wall-clock frame intervals,
/// so the numbers reflect the app's own work even when the machine running the
/// simulator is busy. `mark()` (called when a card is thrown) prints the costliest
/// frame of the next 300 ms; every 2 s it prints the costliest frame overall.
final class HitchMonitor: NSObject {
    static let shared = HitchMonitor()
    private var link: CADisplayLink?
    private var lastCPU: Double = 0
    private var windowStart: CFTimeInterval = 0
    private var windowWorst: Double = 0
    private var markStart: CFTimeInterval?
    private var markWorst: Double = 0
    private var markTotal: Double = 0

    func start() {
        guard link == nil else { return }
        let link = CADisplayLink(target: self, selector: #selector(tick))
        link.add(to: .main, forMode: .common)
        self.link = link
        lastCPU = Self.threadCPU()
    }

    /// Measures the 300 ms after this call (a card throw).
    func mark() {
        guard link != nil else { return }
        markStart = CACurrentMediaTime()
        markWorst = 0
        markTotal = 0
    }

    /// Main-thread CPU spent since the previous tick is charged to the frame that just ended.
    @objc private func tick(_ link: CADisplayLink) {
        let cpu = Self.threadCPU()
        let frame = (cpu - lastCPU) * 1000
        lastCPU = cpu
        let now = link.timestamp
        if windowStart == 0 { windowStart = now }
        windowWorst = max(windowWorst, frame)
        if let start = markStart {
            markWorst = max(markWorst, frame)
            markTotal += frame
            if now - start >= 0.3 {
                print(String(format: "THROW worst=%.2fms total=%.2fms", markWorst, markTotal))
                fflush(stdout)
                markStart = nil
            }
        }
        if now - windowStart >= 2 {
            print(String(format: "WINDOW worst=%.2fms", windowWorst))
            fflush(stdout)
            windowStart = now
            windowWorst = 0
        }
    }

    private static func threadCPU() -> Double {
        var ts = timespec()
        clock_gettime(CLOCK_THREAD_CPUTIME_ID, &ts)
        return Double(ts.tv_sec) + Double(ts.tv_nsec) / 1e9
    }
}
#endif

#if DEBUG
import UIKit

/// Debug-only census of the key window's Core Animation layers, started by the
/// `-layerDump` launch argument: every 0.3 s it prints how many layers carry a
/// filter (blur), a mask, or group opacity over sublayers, the things that cost
/// offscreen render passes, so effect changes can be checked without Instruments.
enum LayerCensus {
    static func start() {
        Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { _ in
            MainActor.assumeIsolated { dump() }
        }
    }

    @MainActor static func dump() {
        guard let window = UIApplication.shared.connectedScenes
            .compactMap({ ($0 as? UIWindowScene)?.keyWindow }).first else { return }
        var total = 0, filters: [String] = [], masks = 0, groupOpacity = 0
        func walk(_ layer: CALayer) {
            total += 1
            if let f = layer.filters, !f.isEmpty {
                let names = f.map { "\(($0 as AnyObject).value(forKey: "name") ?? "?")=\(($0 as AnyObject).value(forKey: "inputRadius") ?? "")" }
                filters.append("\(Int(layer.bounds.width))x\(Int(layer.bounds.height)) op=\(String(format: "%.2f", layer.opacity)) [\(names.joined(separator: ","))]")
            }
            if layer.mask != nil { masks += 1 }
            if layer.opacity < 1, layer.opacity > 0, layer.allowsGroupOpacity, (layer.sublayers?.count ?? 0) > 0 { groupOpacity += 1 }
            layer.sublayers?.forEach(walk)
        }
        walk(window.layer)
        print("LAYERS total=\(total) filters=\(filters.count) masks=\(masks) groupOpacity=\(groupOpacity) :: \(filters.joined(separator: " | "))")
        fflush(stdout)
    }
}
#endif
