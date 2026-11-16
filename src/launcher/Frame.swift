import AppKit
import SceneKit

// Render callbacks supply pacing evidence independently of the input clock
final class Frame: NSObject, SCNSceneRendererDelegate, @unchecked Sendable {
    struct Budget {
        private(set) var scale = 1.0
        private var slow = 0.0
        private var fast = 0.0

        mutating func sample(interval: Double, seconds: Double, target: Double, hot: Bool) -> Double? {
            guard interval.isFinite, seconds.isFinite, target.isFinite, target>0, interval>0, seconds>0 else {return nil}
            let dt = min(0.1,seconds)
            slow = hot || interval>target*1.2 ? slow+dt : 0
            fast = !hot && interval<target*1.07 ? fast+dt : 0
            let next = slow>=2 ? max(0.75,scale-0.05) : fast>=8 ? min(1,scale+0.05) : scale
            guard abs(next-scale)>0.001 else {return nil}
            scale = next; slow = 0; fast = 0
            return scale
        }
    }

    private let lock = NSLock()
    private var last = 0.0
    private var intervals: [Double] = []
    private var cursor = 0
    private var count = 0
    private var total = 0.0
    private var average = 0.0
    private var written = 0.0
    private static let queue = DispatchQueue(label:"minecraft.frames",qos:.utility)

    var interval: Double {lock.lock(); defer {lock.unlock()}; return average}

    func reset() {
        lock.lock(); defer {lock.unlock()}
        last = 0; average = 0; intervals.removeAll(keepingCapacity:true); cursor = 0; count = 0; total = 0
    }

    func renderer(_ renderer: any SCNSceneRenderer, didRenderScene scene: SCNScene, atTime time: TimeInterval) {
        let now = ProcessInfo.processInfo.systemUptime
        lock.lock(); defer {lock.unlock()}
        defer {last = now}
        guard last>0 else {return}
        let dt = now-last
        guard dt>0, dt<10 else {return}
        average = average == 0 ? dt : average+(dt-average)*0.05
        count += 1; total += dt
        if intervals.count<3600 {intervals.append(dt)}
        else {intervals[cursor] = dt; cursor = (cursor+1)%intervals.count}
    }

    // One bounded private diagnostic records submitted frame intervals, not a claim about display presentation
    func write(to file: URL?, mode: String, scale: Double, step: Double) {
        let now = ProcessInfo.processInfo.systemUptime
        guard let file, now-written>=10 else {return}
        written = now
        lock.lock()
        let samples = intervals, count = count, total = total
        lock.unlock()
        guard !samples.isEmpty else {return}
        Self.queue.async {
            let sorted = samples.sorted()
            func percentile(_ p: Double) -> Double {sorted[min(sorted.count-1,Int(Double(sorted.count-1)*p))]*1000}
            let value: [String:Any] = ["mode":mode,"frames":count,"seconds":total,"sample_count":sorted.count,
                "fps":total>0 ? Double(count)/total : 0,"p95_ms":percentile(0.95),"p99_ms":percentile(0.99),
                "max_ms":sorted.last!*1000,"render_scale":scale,"last_step_ms":step*1000,
                "thermal_state":ProcessInfo.processInfo.thermalState.rawValue]
            do {
                try FileManager.default.createDirectory(at:file.deletingLastPathComponent(),withIntermediateDirectories:true,
                    attributes:[.posixPermissions:0o700])
                let bytes = try JSONSerialization.data(withJSONObject:value,options:[.sortedKeys])
                try bytes.write(to:file,options:.atomic)
                try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:file.path)
            } catch {NSLog("Scenery measurement could not be saved: %@",error.localizedDescription)}
        }
    }
}
