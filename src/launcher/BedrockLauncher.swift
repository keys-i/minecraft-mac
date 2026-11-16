import AppKit
import SwiftUI
import CoreText
import SceneKit
import notify
import UniformTypeIdentifiers

private let launcherName = "Minecraft Launcher"

struct Status: Decodable {
    let state: String
    let title: String
    let detail: String
    let progress: Double?
    var gamePID: Int? = nil

    enum CodingKeys: String, CodingKey {
        case state, title, detail, progress
        case gamePID = "game_pid"
    }

    var fraction: Double? {
        guard let progress, progress.isFinite else { return nil }
        return min(max(progress, 0), 1)
    }

    var stage: Int? {
        if state == "playing" { return 3 }
        guard state == "busy", let fraction else { return nil }
        return fraction < 0.35 ? 0 : fraction < 0.9 ? 1 : 2
    }
}

struct AppRelease: Decodable {
    struct Asset: Decodable { let name: String }
    let tag_name: String
    let html_url: URL
    let assets: [Asset]

    var hasInstaller: Bool {
        html_url.scheme == "https" && html_url.host == "github.com"
            && html_url.path.hasPrefix("/keys-i/minecraft-mac/releases/tag/")
            && assets.contains { $0.name.lowercased().hasSuffix(".dmg") }
    }
}

@MainActor
final class Launcher: ObservableObject {
    @Published var status = Status(state: "checking", title: "Getting Minecraft ready", detail: "Checking installation…", progress: nil) {
        didSet { if status.gamePID != oldValue.gamePID { handoff(status.gamePID) } }
    }
    @Published var running = false
    @Published var opening = false
    @Published var checkingUpdates = false
    @Published var journey = Journey()
    @Published var assets: Assets?
    @Published var sceneryFailed = false
    let chart = Chart()
    let simulated = Bundle.main.url(forResource:"preview",withExtension:"json") != nil
    @Published var items: [World:NSImage] = [:]
    @Published var frames: [String:NSImage] = [:]
    @Published var stone: NSImage?
    @Published var gameFont: CTFont?
    @Published var splash = ""
    @Published var help = false
    @Published var settings = false
    #if LAUNCHER_TEST
    var previewImage: NSImage?
    init(status: Status, background: NSImage, assets: Assets) {
        self.root = URL(fileURLWithPath:"/nonexistent-minecraft-preview")
        self.status = status; self.previewImage = background; self.assets = assets
    }
    #endif
    let poster = Bundle.main.url(forResource: "poster", withExtension: "webp").flatMap { NSImage(contentsOf: $0) }
    var selection: Int { worlds.firstIndex(of: journey.world)! }
    private var process: Process?
    private var buffer = Data()
    private var windowTask: Task<Void,Never>?
    private weak var hiddenWindow: NSWindow?
    private var presentationToken: Int32 = -1
    let root: URL
    let worlds = World.allCases

    init() {
        if let url = Bundle.main.url(forResource:"Monocraft",withExtension:"ttf") { CTFontManagerRegisterFontsForURL(url as CFURL,.process,nil) }
        let path = Bundle.main.object(forInfoDictionaryKey: "BedrockProjectPath") as? String ?? ""
        root = path.isEmpty ? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Bedrock for Mac") : URL(fileURLWithPath: path)
        refreshAssets()
        start(check: true)
    }

    private func refreshAssets() {
        guard assets == nil else { return }
        let installed = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Bedrock for Mac/game/data")
        let data = root.appendingPathComponent("game/data")
        let development = Bundle.main.object(forInfoDictionaryKey: "BedrockProjectPath") as? String ?? ""
        assets = try? Assets(data: !development.isEmpty && !FileManager.default.fileExists(atPath: data.path) ? installed : data)
        if let art = assets {
            art.icons { [weak self] images,stone,frames,font,splash in
                guard let self, self.assets === art else { return }
                self.items = images; self.stone = stone; self.frames = frames
                self.gameFont = font; self.splash = splash
            }
        }
    }

    func start(check: Bool = false, signOut: Bool = false) {
        guard !running else { return }
        opening = !check && !signOut
        running = true
        buffer = Data()
        let task = Process()
        let pipe = Pipe()
        let resources = Bundle.main.resourceURL!
        let worker = resources.appendingPathComponent("worker/BedrockWorker")
        let packaged = FileManager.default.isExecutableFile(atPath: worker.path)
        task.executableURL = packaged ? worker : root.appendingPathComponent("target/release/MinecraftWorker")
        task.arguments = check ? ["--warmup"] : signOut ? ["--sign-out"] : []
        task.currentDirectoryURL = packaged ? resources : root
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        var env = Self.environment()
        env["BEDROCK_HOME"] = root.path
        if packaged { env["BEDROCK_BUNDLE"] = resources.path }
        task.environment = env
        if opening { preparePresentation(task,resources:resources) }
        do {
            process = task
            if !check { status = Status(state: "busy", title: "Getting ready", detail: "Checking your Mac…", progress: nil) }
            try task.run()
            // Drain stdout before finishing the run. A timed delay can lose the
            // last status or let a previous worker overwrite a new attempt.
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                let reader = pipe.fileHandleForReading
                while true {
                    let data = reader.availableData
                    if data.isEmpty { break }
                    DispatchQueue.main.async { [weak self] in
                        guard let self, self.process === task else { return }
                        self.receive(data)
                    }
                }
                try? reader.close()
                task.waitUntilExit()
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.process === task else { return }
                    if !self.buffer.isEmpty { self.receive(Data([10])) }
                    self.running = false
                    self.opening = false
                    self.clearPresentation()
                    self.process = nil
                    if task.terminationStatus != 0 && self.status.state != "error" {
                        self.status = Status(state: "error", title: "Couldn’t finish setup", detail: "Try again. If it happens again, open the setup log.", progress: nil)
                    } else if ["busy", "checking", "playing", "cancelling"].contains(self.status.state) {
                        self.status = Status(state: "error", title: "Setup stopped", detail: "Try again to continue.", progress: nil)
                    }
                }
            }
        } catch {
            clearPresentation()
            running = false
            opening = false
            process = nil
            status = Status(state: "error", title: "Couldn’t start setup", detail: error.localizedDescription, progress: nil)
        }
    }

    private func receive(_ data: Data) {
        buffer.append(data)
        while let end = buffer.firstIndex(of: 10) {
            let line = buffer[..<end]
            if let next = try? JSONDecoder().decode(Status.self, from: line) {
                let announce = next.title != status.title || next.state != status.state
                status = next
                if ["ready", "playing"].contains(next.state), assets == nil || sceneryFailed {
                    assets = nil
                    sceneryFailed = false
                    refreshAssets()
                }
                if announce {
                    NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested,
                        userInfo: [.announcement: next.title, .priority: NSAccessibilityPriorityLevel.medium.rawValue])
                }
            }
            buffer.removeSubrange(...end)
        }
    }

    static func environment(_ inherited: [String:String] = ProcessInfo.processInfo.environment) -> [String:String] {
        inherited.filter { key, _ in !["CX_", "WINE", "DYLD_"].contains(where:key.hasPrefix) }
    }

    static func gameWindow(_ pid: Int, windows: [[String:Any]]) -> Bool {
        guard pid > 1 && pid <= Int(Int32.max) else { return false }
        return windows.contains { window in
            guard (window[kCGWindowOwnerPID as String] as? NSNumber)?.intValue == pid,
                  (window[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
                  let bounds = window[kCGWindowBounds as String] as? [String:Any],
                  let width = bounds["Width"] as? NSNumber, let height = bounds["Height"] as? NSNumber else { return false }
            return width.doubleValue >= 320 && height.doubleValue >= 200
        }
    }

    static func frameReady(_ pid: Int, state: UInt64) -> Bool {
        pid>1 && pid<=Int(Int32.max) && state == UInt64(pid)
    }

    private func clearPresentation() {
        if presentationToken >= 0 { notify_cancel(presentationToken); presentationToken = -1 }
    }

    func preparePresentation(_ task: Process, resources: URL) {
        clearPresentation()
        let path = resources.appendingPathComponent("runtime/wine/dxmt-unix-bridge.json")
        guard let data = try? Data(contentsOf:path), data.count<64*1024,
              let metadata = try? JSONSerialization.jsonObject(with:data) as? [String:Any],
              let digest = metadata["handoff_patch_sha256"] as? String,
              digest.count == 64, digest.allSatisfy({ $0.isHexDigit && $0.isASCII }) else { return }
        let nonce = UUID().uuidString
        guard notify_register_check("local.keys-i.minecraft.present."+nonce,&presentationToken) == NOTIFY_STATUS_OK else {
            presentationToken = -1; return
        }
        var environment = Self.environment(task.environment ?? ProcessInfo.processInfo.environment)
        environment["BEDROCK_LAUNCH_TOKEN"] = nonce
        if let window = NSApplication.shared.windows.first(where:{ $0.title == launcherName }) {
            let frame = window.frame
            environment["BEDROCK_WINDOW_FRAME"] = String(format:"%.6f %.6f %.6f %.6f",locale:Locale(identifier:"en_US_POSIX"),
                Double(frame.origin.x),Double(frame.origin.y),Double(frame.width),Double(frame.height))
            environment["BEDROCK_WINDOW_FULLSCREEN"] = window.styleMask.contains(.fullScreen) ? "1" : "0"
        }
        task.environment = environment
    }

    private func handoff(_ pid: Int?) {
        windowTask?.cancel(); windowTask = nil
        if let window = hiddenWindow {
            NSApp.unhide(nil); window.makeKeyAndOrderFront(nil); hiddenWindow = nil
        }
        guard let pid, pid > 1 && pid <= Int(Int32.max) else { clearPresentation(); return }
        windowTask = Task { [weak self] in
            let started = ProcessInfo.processInfo.systemUptime
            while let self, !Task.isCancelled, self.status.gamePID == pid {
                var state: UInt64 = 0
                let observed = self.presentationToken>=0 && notify_get_state(self.presentationToken,&state) == NOTIFY_STATUS_OK && Self.frameReady(pid,state:state)
                // A failed runtime notification must not trap an already visible game behind the loader
                let expired = ProcessInfo.processInfo.systemUptime-started>=20
                let options: CGWindowListOption = observed || expired ? [.optionAll,.excludeDesktopElements] : [.optionOnScreenOnly,.excludeDesktopElements]
                let windows = CGWindowListCopyWindowInfo(options,kCGNullWindowID) as? [[String:Any]] ?? []
                if Self.gameWindow(pid,windows:windows) && (self.presentationToken<0 || observed || expired) {
                    let window = NSApp.windows.first { $0.title == launcherName }
                    NSRunningApplication(processIdentifier:pid_t(pid))?.activate(options:[.activateAllWindows])
                    self.hiddenWindow = window; NSApp.hide(nil)
                    self.clearPresentation()
                    return
                }
                do { try await Task.sleep(for:.milliseconds(150)) } catch { return }
            }
        }
    }

    var canCancel: Bool { running && status.state == "busy" }
    var loading: Bool { opening && running && ["busy","checking","playing","cancelling"].contains(status.state) }

    func cancel() {
        guard canCancel else { return }
        status = Status(state: "cancelling", title: "Stopping setup", detail: "Keeping your existing game and saves.", progress: nil)
        process?.terminate()
    }

    func signOut() {
        guard !running else { return }
        let alert = NSAlert()
        alert.messageText = "Sign out of Microsoft?"
        alert.informativeText = "Your game and worlds will stay on this Mac. You can sign in with another account next time you play."
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Sign Out")
        if alert.runModal() == .alertSecondButtonReturn { start(signOut: true) }
    }

    func showHelp() {
        settings = false
        help = true
    }

    func showSettings() {
        help = false
        settings = true
    }

    func checkUpdates() {
        guard !checkingUpdates else { return }
        checkingUpdates = true
        Task {
            defer { checkingUpdates = false }
            let alert = NSAlert()
            do {
                var request = URLRequest(url: URL(string: "https://api.github.com/repos/keys-i/minecraft-mac/releases?per_page=10")!)
                request.timeoutInterval = 15
                request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let response = response as? HTTPURLResponse, response.statusCode == 200,
                      data.count <= 2 * 1024 * 1024 else { throw URLError(.badServerResponse) }
                let releases = try JSONDecoder().decode([AppRelease].self, from: data)
                if let release = releases.first(where: \.hasInstaller) {
                    alert.messageText = "Latest app release: \(release.tag_name)"
                    alert.informativeText = "This app is version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown"). Review the release notes before replacing it. Your worlds stay outside the app."
                } else {
                    alert.messageText = "No app installer has been published yet"
                    alert.informativeText = "The repository currently offers source previews. You can review the latest source releases and build instructions."
                }
                alert.addButton(withTitle: "View Releases")
                alert.addButton(withTitle: "Close")
                if alert.runModal() == .alertFirstButtonReturn {
                    NSWorkspace.shared.open(URL(string: "https://github.com/keys-i/minecraft-mac/releases")!)
                }
            } catch {
                alert.messageText = "Couldn’t check for updates"
                alert.informativeText = "Check your connection and try again, or open the project’s Releases page in your browser. Your installation hasn’t changed."
                alert.addButton(withTitle: "Close")
                alert.runModal()
            }
        }
    }

    func showLog() {
        NSWorkspace.shared.open(root.appendingPathComponent("logs/standalone"))
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var launcher: Launcher?
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard launcher?.canCancel == true else { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = "Stop setup?"
        alert.informativeText = "You can continue later. Your game and saves will be kept."
        alert.addButton(withTitle: "Keep Going")
        alert.addButton(withTitle: "Stop Setup")
        if alert.runModal() == .alertSecondButtonReturn { launcher?.cancel() }
        return .terminateCancel
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if !hasVisibleWindows { sender.windows.first(where: { $0.canBecomeMain })?.makeKeyAndOrderFront(nil) }
        return true
    }
}

enum SceneryMotion {
    static func enabled(reduced: Bool, paused: Bool, lowPower: Bool,
                        active: Bool, visible: Bool, playing: Bool) -> Bool {
        !reduced && !paused && !lowPower && active && visible && !playing
    }
}

struct ShortcutHint {
    private(set) var showing = false
    private(set) var occupied = false
    private(set) var generation = 0
    private var deadline = Double.infinity

    mutating func advance(at time: TimeInterval) {
        guard time >= deadline else { return }
        if showing { showing = false; deadline = time+0.4 }
        else { occupied = false; deadline = .infinity }
    }

    mutating func dismiss(at time: TimeInterval) { showing = false; deadline = time+0.4 }
    mutating func show(at time: TimeInterval) { showing = true; occupied = true; generation += 1; deadline = time+4 }
    func delay(at time: TimeInterval) -> TimeInterval { max(0,deadline-time) }
}

private enum Blocks {
    static let grass = Color(red:0.48,green:0.78,blue:0.22)
    static let play = Color(red:0.12,green:0.47,blue:0.03)
    static let stone = Color(white:0.72)
    static let ink = Color(white:0.12)
    static let gold = Color(red:1,green:0.83,blue:0.37)

    static func type(_ size: CGFloat) -> Font { .custom(NSFont(name:"Mojangles",size:size) == nil ? "Monocraft" : "Mojangles",size:size,relativeTo:.body) }
    static func action(_ size: CGFloat) -> Font { type(size) }
}

private struct Hover<Content:View>: View {
    let anchor: UnitPoint
    let content: (Bool) -> Content
    @Environment(\.accessibilityReduceMotion) private var reduced
    @Environment(\.isEnabled) private var enabled
    @State private var hovered = false

    init(anchor: UnitPoint = .center, @ViewBuilder content: @escaping (Bool) -> Content) {
        self.anchor = anchor; self.content = content
    }

    var body: some View {
        content(hovered && enabled)
            .scaleEffect(hovered && enabled && !reduced ? 1.035 : 1,anchor:anchor)
            .brightness(hovered && enabled ? 0.08 : 0)
            .contentShape(Rectangle())
            .onHover { hovered = $0 }
            .animation(reduced ? nil : .easeOut(duration:0.12),value:hovered)
    }
}

struct BlockButton: ButtonStyle {
    var selected = false
    var texture: NSImage?
    var scale: CGFloat = 1
    @Environment(\.accessibilityReduceMotion) private var reduced
    @Environment(\.isFocused) private var focused
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        Hover { hovered in
            configuration.label
                .foregroundStyle(hovered || focused ? .white : Blocks.ink)
                .background {
                    (hovered || focused ? Blocks.play : Blocks.stone)
                        .shadow(color:.black.opacity(0.4),radius:0,x:0,y:configuration.isPressed ? 0 : 3*scale)
                    if let texture {
                        Image(nsImage:texture).resizable(resizingMode:.tile).interpolation(.none).opacity(0.14)
                    }
                }
                .overlay(alignment:.top) { Rectangle().fill(.white.opacity(0.25)).frame(height:2*scale) }
                .overlay(alignment:.bottom) { Rectangle().fill(.black.opacity(0.45)).frame(height:4*scale) }
                .overlay { Rectangle().strokeBorder(.black.opacity(0.85),lineWidth:2*scale) }
                .overlay { Rectangle().strokeBorder(.white,lineWidth:2*scale).padding(3*scale).opacity(hovered || focused || selected ? 1 : 0) }
                .offset(y:configuration.isPressed && !reduced ? 2*scale : 0)
                .opacity(enabled ? 1 : 0.45)
                .contentShape(Rectangle())
                .animation(reduced ? nil : .easeOut(duration:0.08),value:configuration.isPressed)
        }
    }
}

private struct InventoryButton: ButtonStyle {
    let selected: Bool
    let slot: NSImage?
    let selection: NSImage?
    let scale: CGFloat
    @Environment(\.isFocused) private var focused
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        Hover { hovered in
            configuration.label.frame(width:60*scale,height:60*scale)
                .background {
                    if let slot { Image(nsImage:slot).resizable().interpolation(.none) }
                    else { Rectangle().fill(.black.opacity(0.65)).overlay { Rectangle().strokeBorder(.gray,lineWidth:3) } }
                }
                .overlay {
                    if selected {
                        if let selection { Image(nsImage:selection).resizable().interpolation(.none).frame(width:72*scale,height:72*scale) }
                        else { Rectangle().strokeBorder(.white,lineWidth:3*scale).padding(-4*scale) }
                    }
                }
                .overlay { Rectangle().strokeBorder(Blocks.gold,lineWidth:2).padding(-6*scale).opacity(focused ? 1 : 0) }
                .brightness(configuration.isPressed ? -0.15 : 0)
                .opacity(enabled ? 1 : 0.45).contentShape(Rectangle())
        }
    }
}

private struct Slot: View {
    let world: World
    let image: NSImage?
    let scale: CGFloat
    var body: some View {
        Group {
            if let image { Image(nsImage:image).resizable().interpolation(.none).scaledToFit() }
            else {
                Canvas { context,size in
                    let colour = world.colour
                    let top = Path { p in
                        p.move(to:.init(x:3,y:size.height*0.3)); p.addLines([.init(x:size.width/2,y:1),.init(x:size.width-3,y:size.height*0.3),.init(x:size.width/2,y:size.height*0.59)]); p.closeSubpath()
                    }
                    let left = Path { p in
                        p.move(to:.init(x:3,y:size.height*0.3));p.addLines([.init(x:size.width/2,y:size.height*0.59),.init(x:size.width/2,y:size.height-2),.init(x:3,y:size.height*0.7)]);p.closeSubpath()
                    }
                    let right = Path { p in
                        p.move(to:.init(x:size.width/2,y:size.height*0.59));p.addLines([.init(x:size.width-3,y:size.height*0.3),.init(x:size.width-3,y:size.height*0.7),.init(x:size.width/2,y:size.height-2)]);p.closeSubpath()
                    }
                    context.fill(top,with:.color(colour));context.fill(left,with:.color(colour.opacity(0.65)));context.fill(right,with:.color(colour.opacity(0.85)))
                }
            }
        }.frame(width:48*scale,height:48*scale).accessibilityHidden(true)
    }
}

private struct Scenery: View {
    let journey: Journey
    let moving: Bool
    let active: Bool
    let exploring: Bool
    let travel: (Int) -> Void
    let finish: () -> Void
    let renderDistance: Int
    let seed: String
    let farLands: Int
    let location: (String?) -> Void
    let report: ((SCNVector3,Double) -> Void)?
    let sensitivity: Double
    let inverted: Bool
    let controls: Controls
    let activity: (Bool) -> Void
    @ObservedObject var launcher: Launcher
    @State private var resolution = 1.0

    var body: some View {
        ZStack {
            if let poster = launcher.frames["panorama"] ?? launcher.poster { Image(nsImage:poster).resizable().scaledToFill() }
            #if LAUNCHER_TEST
            if let image = launcher.previewImage { Image(nsImage:image).resizable().scaledToFill() }
            else { viewport }
            #else
            viewport
            #endif
            VStack(spacing:0) {
                LinearGradient(colors:[.black.opacity(0.45),.clear],startPoint:.top,endPoint:.bottom).frame(height:130)
                Spacer()
                LinearGradient(colors:[.clear,.black.opacity(0.65)],startPoint:.top,endPoint:.bottom).frame(height:250)
            }.allowsHitTesting(false)
        }.accessibilityHidden(true)
    }

    private var viewport: some View {
        GeometryReader { geometry in
            world.frame(width:geometry.size.width*resolution,height:geometry.size.height*resolution)
                .scaleEffect(1/resolution,anchor:.topLeading)
                .frame(width:geometry.size.width,height:geometry.size.height,alignment:.topLeading).clipped()
        }
    }

    @ViewBuilder private var world: some View {
        if let assets = launcher.assets, !launcher.sceneryFailed, !launcher.simulated {
            if journey.world.dimension != nil && !(journey.world == .overworld && farLands != 0) {
                Expedition(world:journey.world,biome:journey.biome,seed:seed,assets:assets,root:launcher.root,chart:launcher.chart,
                    exploring:exploring,moving:moving,active:active,distance:renderDistance,sensitivity:sensitivity,
                    inverted:inverted,controls:controls,finish:finish,location:location,report:report,activity:activity,
                    cinematic:journey.passage != nil,arrived:{ world in
                        if launcher.journey.world != world { launcher.journey.select(world,animated:false) }
                        launcher.journey.skip()
                    },resolution:{ resolution = $0 })
            } else { Adventure(world:journey.world,biome:journey.biome,moving:moving,passage:journey.passage,assets:assets,exploring:exploring,
                travel:travel,arrived:{ launcher.journey.area($0) },finish:finish,
                renderDistance:renderDistance,seed:Seed.number(seed),farLands:farLands,location:location,activity:activity,report:report,
                sensitivity:sensitivity,inverted:inverted,controls:controls,active:active,resolution:{resolution = $0}) { launcher.sceneryFailed = true } }
        }
    }
}

struct GenerationStatus: View {
    @ObservedObject var chart: Chart
    var body: some View {
        if let text = chart.error {
            GeometryReader { geometry in
                let scale = min(1.5,max(1,geometry.size.width/1040))
                VStack(spacing:16*scale) {
                    Text("Scenery couldn’t load")
                        .font(Blocks.type(24*scale)).foregroundStyle(Blocks.ink)
                    Text(text).font(Blocks.type(18*scale)).foregroundStyle(Blocks.ink)
                        .multilineTextAlignment(.center).fixedSize(horizontal:false,vertical:true)
                    Button("Try again") {chart.retry?()}.buttonStyle(BlockButton()).font(Blocks.type(18*scale))
                }.padding(24*scale).frame(width:min(520*scale,geometry.size.width-48))
                    .background(Blocks.stone).border(.black,width:2)
                    .frame(maxWidth:.infinity,maxHeight:.infinity)
            }.allowsHitTesting(chart.error != nil)
        }
    }
}

struct Scrolling {
    private var input = -Double.infinity
    private var changed = -Double.infinity
    private var delta = 0.0

    mutating func step(_ amount: Double, precise: Bool, at time: Double) -> Int {
        guard amount.isFinite, time.isFinite, amount != 0 else { return 0 }
        if time-input>0.25 || time<input { delta = 0 }
        input = time
        guard time-changed>=0.12 || time<changed else { return 0 }
        delta += precise ? amount : (amount>0 ? 12 : -12)
        guard abs(delta)>=12 else { return 0 }
        let step = delta>0 ? -1 : 1
        delta = 0; changed = time
        return step
    }
}

private struct Input: NSViewRepresentable {
    let enabled: Bool
    var controls = Controls()
    let changed: (Int) -> Void
    var action: (Controls.Action) -> Void = { _ in }
    var skip: (() -> Void)? = nil
    var debug: (() -> Void)? = nil

    final class Coordinator {
        weak var view: NSView?
        var enabled = false
        var changed: ((Int) -> Void)?
        var controls = Controls()
        var action: ((Controls.Action) -> Void)?
        var scrolling = Scrolling()
        var monitor: Any?
        var skip: (() -> Void)?
        var debug: (() -> Void)?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> NSView {
        let view = NSView(); context.coordinator.view = view
        context.coordinator.monitor = NSEvent.addLocalMonitorForEvents(matching:[.scrollWheel,.keyDown,.flagsChanged]) { [weak coordinator = context.coordinator] event in
            guard let coordinator, coordinator.enabled, let window = coordinator.view?.window,
                  event.window === window, window.isKeyWindow else { return event }
            if event.type == .keyDown || event.type == .flagsChanged {
                if Controls.Key.quit(event) { return event }
                if Controls.Key.debug(event), let debug = coordinator.debug {debug(); return nil}
                if event.type == .keyDown, event.keyCode == 49,
                   event.modifierFlags.intersection([.command,.control,.option,.shift]).isEmpty,
                   let skip = coordinator.skip {
                    if !event.isARepeat {skip()}
                    return nil
                }
                let actions: [Controls.Action] = [.look,.map,.previous,.next,.overworld,.nether,.end,.sift]
                if let action = actions.first(where:{ coordinator.controls.matches($0,event:event) }) {
                    if event.type != .keyDown || !event.isARepeat { coordinator.action?(action) }
                    return nil
                }
                if event.type == .keyDown, let flight = window.firstResponder as? FlightView, flight.exploring,
                   Controls.Action.allCases.contains(where:{ $0.movement && coordinator.controls.key($0).code == Controls.Key.canonical(event.keyCode)
                       && coordinator.controls.pressed($0,keys:flight.keys.union([Controls.Key.canonical(event.keyCode)]),modifiers:event.modifierFlags) }) {
                    flight.keyDown(with:event)
                    return nil
                }
                return event
            }
            guard
                  event.modifierFlags.intersection([.command,.option,.control]).isEmpty,
                  event.momentumPhase.isEmpty else { return event }
            let amount = Double(event.scrollingDeltaY)*(event.isDirectionInvertedFromDevice ? -1 : 1)
            let step = coordinator.scrolling.step(amount,precise:event.hasPreciseScrollingDeltas,at:event.timestamp)
            if step != 0 { coordinator.changed?(step) }
            return nil
        }
        return view
    }
    func updateNSView(_ view: NSView, context: Context) {
        if context.coordinator.enabled != enabled { context.coordinator.scrolling = Scrolling() }
        context.coordinator.enabled = enabled; context.coordinator.changed = changed
        context.coordinator.controls = controls; context.coordinator.action = action
        context.coordinator.skip = skip; context.coordinator.debug = debug
    }
    static func dismantleNSView(_ view: NSView, coordinator: Coordinator) {
        if let monitor = coordinator.monitor { NSEvent.removeMonitor(monitor) }
        coordinator.monitor = nil; coordinator.changed = nil; coordinator.action = nil; coordinator.skip = nil; coordinator.debug = nil; coordinator.view = nil
    }
}

final class Position: ObservableObject {
    @Published var sample = (point:SCNVector3Zero,yaw:0.0)
}

private struct Disc: Shape {
    func path(in rect: CGRect) -> Path {
        let cell = min(rect.width,rect.height)/32
        var path = Path()
        for row in 0..<32 {
            let half = floor(sqrt(256-pow(Double(row)-15.5,2)))
            let left = CGFloat(16-half)*cell, right = CGFloat(16+half)*cell
            if row == 0 { path.move(to:.init(x:left,y:0)) }
            path.addLine(to:.init(x:left,y:CGFloat(row)*cell))
            path.addLine(to:.init(x:left,y:CGFloat(row+1)*cell))
            if row == 31 { path.addLine(to:.init(x:right,y:32*cell)) }
        }
        for row in (0..<32).reversed() {
            let half = floor(sqrt(256-pow(Double(row)-15.5,2)))
            let right = CGFloat(16+half)*cell
            path.addLine(to:.init(x:right,y:CGFloat(row+1)*cell))
            path.addLine(to:.init(x:right,y:CGFloat(row)*cell))
        }
        path.closeSubpath()
        return path
    }
}

private struct ToastFrame: Shape {
    func path(in rect: CGRect) -> Path {
        let x = rect.minX, y = rect.minY, w = rect.width, h = rect.height, c = 3.0
        var path = Path()
        path.addLines([.init(x:x+c,y:y),.init(x:x+w-c,y:y),.init(x:x+w-c,y:y+c),
            .init(x:x+w,y:y+c),.init(x:x+w,y:y+h-c),.init(x:x+w-c,y:y+h-c),
            .init(x:x+w-c,y:y+h),.init(x:x+c,y:y+h),.init(x:x+c,y:y+h-c),
            .init(x:x,y:y+h-c),.init(x:x,y:y+c),.init(x:x+c,y:y+c)])
        path.closeSubpath()
        return path
    }
}

struct Minimap: View {
    struct Render {
        let image: CGImage
        let structures: [MapMarker]
    }

    let world: World
    @ObservedObject var position: Position
    @ObservedObject var chart: Chart
    var seed: Int = 0
    var size: CGFloat = 160
    var shortcut = "M"
    @State private var image: CGImage?
    @State private var structures: [MapMarker] = []

    private var point: SCNVector3 { position.sample.point }
    private var yaw: Double { position.sample.yaw }
    private var x: Int { Int(floor(point.x/8)) }
    private var z: Int { Int(floor(point.z/8)) }
    private var historical: Bool { Region.at(point)?.historical(world) == true }
    private var key: String { "\(world.rawValue):\(seed):\(x):\(z):\(Int(floor((point.y+16)/32))):\(chart.revision)" }

    nonisolated static func render(data: WorldData, at point: SCNVector3) -> Render? {
        guard point.x.isFinite, point.y.isFinite, point.z.isFinite, [point.x,point.y,point.z].allSatisfy({abs($0)<30_000_000}) else { return nil }
        let covered = data.surface(Int(floor(point.x)),Int(floor(point.z))).map {Double($0)>point.y+6} ?? false
        let ceiling = data.dimension == 1 || covered ? Int(floor(point.y)) : 320
        let side = 128, cx = Int(floor(point.x/8))*8, cz = Int(floor(point.z/8))*8
        var pixels = [UInt8](); pixels.reserveCapacity(side*side*4)
        var structures: [MapMarker] = [], marked = Set<Chunk>()
        func mark(_ x: Int, _ z: Int) {
            guard abs(x-cx)<=side/2, abs(z-cz)<=side/2 else {return}
            let bucket = Chunk(x:Int(floor(Double(x)/8)),z:Int(floor(Double(z)/8)))
            if marked.insert(bucket).inserted {structures.append(.init(x:Double(x)+0.5,z:Double(z)+0.5,kind:.structure))}
        }
        for chunk in data.chunks.values where abs(chunk.key.x*16+8-cx)<=side/2+8 && abs(chunk.key.z*16+8-cz)<=side/2+8 {
            if Task.isCancelled {return nil}
            for section in chunk.sections.values {
                for layer in section.layers where layer.blocks.contains(where:{Self.structure($0.name)}) {
                    for x in 0..<16 {for z in 0..<16 {for y in 0..<16 where Self.structure(layer.block(x,y,z).name) {
                        mark(chunk.key.x*16+x,chunk.key.z*16+z)
                    }}}
                }
            }
        }
        for edits in data.edits.values {for (cell,block) in edits where Self.structure(block.name) {mark(cell.x,cell.z)}}
        var previous = (0..<side).map {data.surface(cx+$0-side/2,cz-side/2-1,below:ceiling)}
        for row in 0..<side {
            guard !Task.isCancelled else {return nil}
            for column in 0..<side {
            let x = cx+column-side/2, z = cz+row-side/2
            let height = data.surface(x,z,below:ceiling)
            let block = height.flatMap { data.block(x,$0,z) }
            let name = block?.name ?? ""
            let colour: UInt32
            if block == nil { colour = 0x181B1B }
            else if name.contains("water") { colour = 0x376CC4 }
            else if name.contains("lava") { colour = 0xF37117 }
            else if name.contains("snow") || name.contains("ice") { colour = 0xD8E8EC }
            else if name.contains("leaves") { colour = name.contains("cherry") ? 0xDF9FC4 : 0x356A2D }
            else if name.contains("sand") && !name.contains("soul") || name == "end_stone" { colour = 0xD9CA8E }
            else if name.contains("planks") || name.contains("log") { colour = 0x99754D }
            else if name.contains("path") { colour = 0xAF965F }
            else if name.contains("grass") || name.contains("moss") { colour = 0x7EAF49 }
            else if name.contains("dirt") { colour = 0x8B6545 }
            else if name.contains("nylium") { colour = name.contains("warped") ? 0x228A80 : 0x9B3448 }
            else if name.contains("netherrack") { colour = 0x793C3B }
            else if name.contains("terracotta") { colour = 0xA97548 }
            else if name.contains("deepslate") || name.contains("blackstone") { colour = 0x42434C }
            else { colour = 0x999B90 }
            let neighbour = previous[column] ?? height ?? 0
            previous[column] = height
            let shade = max(0.65,min(1.18,0.94+Double((height ?? 0)-neighbour)*0.08))
            pixels += [UInt8(min(255,Double((colour>>16)&255)*shade)),UInt8(min(255,Double((colour>>8)&255)*shade)),UInt8(min(255,Double(colour&255)*shade)),255]
        } }
        guard let provider = CGDataProvider(data:Data(pixels) as CFData) else { return nil }
        guard let image = CGImage(width:side,height:side,bitsPerComponent:8,bitsPerPixel:32,bytesPerRow:side*4,
            space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGBitmapInfo(rawValue:CGImageAlphaInfo.premultipliedLast.rawValue),
            provider:provider,decode:nil,shouldInterpolate:false,intent:.defaultIntent) else {return nil}
        return Render(image:image,structures:structures)
    }

    nonisolated static func image(data: WorldData, at point: SCNVector3) -> CGImage? {
        render(data:data,at:point)?.image
    }

    nonisolated static func structure(_ name: String) -> Bool {
        name == "bell" || name.contains("chest") || name.contains("spawner") || name == "end_portal_frame"
            || ["lodestone","reinforced_deepslate","vault","beacon","conduit"].contains(name)
    }

    nonisolated static func image(world: World, at point: SCNVector3, seed: Int = 0) -> CGImage? {
        guard point.x.isFinite, point.y.isFinite, point.z.isFinite,
              abs(point.x)<=30_000_000, abs(point.z)<=30_000_000,
              Region.at(point)?.historical(world) != true else { return nil }
        let x = floor(point.x/8)*8, z = floor(point.z/8)*8
        var pixels = [UInt8](); pixels.reserveCapacity(33*33*4)
        for row in -16...16 { for column in -16...16 {
            let sample = Terrain.sample(world:world,at:.init(x+Double(column*8),point.y,z+Double(row*8)),seed:seed)
            let name = sample.surface
            let colour: UInt32
            if sample.height <= -90 { colour = 0x12121D }
            else if sample.fluid { colour = world == .nether ? 0xE85B18 : 0x387BC4 }
            else if name.contains("snow") || name == "ice" { colour = 0xDAE7EA }
            else if name.contains("sand") && !name.contains("soul") { colour = 0xDACE8C }
            else if name.contains("soul") { colour = 0x685144 }
            else if name.contains("gravel") || name.contains("stone") && world == .overworld { colour = 0x858780 }
            else if name.contains("deepslate") { colour = 0x42454A }
            else if name.contains("netherrack") { colour = 0x813E3A }
            else if name.contains("nylium") { colour = name.contains("warped") ? 0x218979 : 0x9E314E }
            else if world == .end { colour = 0xC6C58B }
            else if name.contains("terracotta") { colour = 0xBC733F }
            else if name.contains("mycelium") { colour = 0x877C88 }
            else if sample.biome.underground { colour = 0x6C7361 }
            else { colour = 0x76A448 }
            let shade = min(1.15,max(0.65,0.85+sample.height*0.006))
            pixels += [UInt8(min(255,Double((colour>>16)&255)*shade)),
                       UInt8(min(255,Double((colour>>8)&255)*shade)),
                       UInt8(min(255,Double(colour&255)*shade)),255]
        } }
        guard let provider = CGDataProvider(data:Data(pixels) as CFData) else { return nil }
        return CGImage(width:33,height:33,bitsPerComponent:8,bitsPerPixel:32,bytesPerRow:33*4,
            space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGBitmapInfo(rawValue:CGImageAlphaInfo.premultipliedLast.rawValue),
            provider:provider,decode:nil,shouldInterpolate:false,intent:.defaultIntent)
    }

    var body: some View {
        VStack(spacing:0) {
            ZStack {
                if let image { Image(decorative:image,scale:1).resizable().interpolation(.none) }
                else { Color(white:0.2) }
                if historical {
                    Text("Far Lands\nHistorical terrain\nMap unavailable").font(Blocks.type(12)).multilineTextAlignment(.center).foregroundStyle(.white)
                }
                ForEach(Array((chart.mobs+structures).indices),id:\.self) { index in
                    let marker = (chart.mobs+structures)[index]
                    let dx = marker.x-Double(x*8), dz = marker.z-Double(z*8)
                    if abs(dx)<=64 && abs(dz)<=64 {
                        Group {
                            if marker.kind == .mob {Circle().fill(.red).frame(width:5,height:5)}
                            else {Rectangle().fill(Blocks.gold).frame(width:6,height:6).rotationEffect(.degrees(45))}
                        }
                        .shadow(color:.black,radius:0,x:1,y:1)
                        .offset(x:CGFloat(dx)*size/128,y:CGFloat(dz)*size/128)
                    }
                }
                Path { path in
                    path.move(to:.init(x:8,y:0)); path.addLine(to:.init(x:13,y:14))
                    path.addLine(to:.init(x:8,y:11)); path.addLine(to:.init(x:3,y:14)); path.closeSubpath()
                }.fill(.white).shadow(color:.black,radius:0,x:1,y:1)
                    .frame(width:16,height:16).rotationEffect(.radians(-yaw))
                    .offset(x:(point.x-Double(x*8))*Double(size/128),y:(point.z-Double(z*8))*Double(size/128))
            }.frame(width:size,height:size).clipShape(Disc())
                .padding(4).background(Disc().fill(Blocks.stone))
                .padding(3).background(Disc().fill(.black))
                .overlay(alignment:.top) {
                    Text("N").font(Blocks.type(15)).foregroundStyle(.white).shadow(color:.black,radius:0,x:1,y:1).padding(.top,10)
                }
            Text("\(Int(point.x))  \(Int(point.y))  \(Int(point.z))").font(Blocks.type(13))
                .foregroundStyle(.white).shadow(color:.black,radius:0,x:1,y:1).padding(.top,10)
        }
            .task(id:key) {
                let data = chart.data, point = point, world = world, seed = seed
                let worker = Task.detached(priority:.utility) { () -> Render? in
                    if world.dimension == nil, let image = Self.image(world:world,at:point,seed:seed) {
                        return Render(image:image,structures:[])
                    }
                    return Self.render(data:data,at:point)
                }
                let result = await withTaskCancellationHandler(operation:{await worker.value},onCancel:{worker.cancel()})
                if !Task.isCancelled {image = result?.image; structures = result?.structures ?? []}
            }
            .accessibilityElement(children:.ignore)
            .accessibilityLabel("Minimap, north up, position \(Int(point.x)), \(Int(point.y)), \(Int(point.z)), \(chart.mobs.count) mobs, \(structures.count) structures")
    }
}

private struct DebugOverlay: View {
    @ObservedObject var position: Position
    @ObservedObject var chart: Chart

    private var text: String {
        let point = position.sample.point, yaw = position.sample.yaw, debug = chart.debug
        let x = Int(floor(point.x)), y = Int(floor(point.y)), z = Int(floor(point.z))
        let chunk = WorldData.key(x,z)
        let dx = sin(yaw), dz = -cos(yaw)
        let facing = abs(dx)>abs(dz) ? (dx>0 ? "east" : "west") : (dz>0 ? "south" : "north")
        let version = Bundle.main.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String ?? "0.17.0"
        let build = Bundle.main.object(forInfoDictionaryKey:"CFBundleVersion") as? String ?? "38"
        return """
        Minecraft Launcher \(version) (\(build))
        XYZ \(String(format:"%.2f",point.x)) / \(String(format:"%.2f",point.y)) / \(String(format:"%.2f",point.z))
        Block \(x) \(y) \(z) · Chunk \(chunk.x) \(chunk.z)
        Facing \(facing) · \(Int((yaw*180/Double.pi).rounded()))°
        Biome \(debug.biome)
        Chunks \(debug.rendered) rendered / \(debug.loaded) loaded · distance \(debug.distance)
        Light \(debug.daylight) sky · night vision \(debug.nightVision ? "on" : "off")
        \(Int(debug.fps.rounded())) FPS · \(Int((debug.scale*100).rounded()))% scale · \(debug.device)
        """
    }

    var body: some View {
        Text(text).font(.system(size:12,weight:.medium,design:.monospaced)).lineSpacing(3)
            .foregroundStyle(.white).shadow(color:.black,radius:0,x:1,y:1)
            .padding(10).background(.black.opacity(0.68)).overlay {Rectangle().stroke(.white.opacity(0.28),lineWidth:1)}
            .accessibilityElement(children:.ignore).accessibilityLabel(text)
    }
}

private struct Experience: ProgressViewStyle {
    func makeBody(configuration: Configuration) -> some View {
        GeometryReader { geometry in
            HStack(spacing:2) {
                ForEach(0..<40,id:\.self) { index in
                    Rectangle()
                        .fill(Double(index+1)/40 <= (configuration.fractionCompleted ?? 0) ? Blocks.grass : Color.black.opacity(0.55))
                        .overlay(alignment:.top) { Rectangle().fill(.white.opacity(0.18)).frame(height:2) }
                }
            }.padding(3).background(.black.opacity(0.7))
                .overlay { Rectangle().strokeBorder(.white.opacity(0.2),lineWidth:1) }
                .frame(width:geometry.size.width,height:14)
        }.frame(height:14)
    }
}

struct Loading: View {
    let status: Status
    let frames: [String:NSImage]
    let font: CTFont?
    let stone: NSImage?
    let animated: Bool
    let cancel: (() -> Void)?

    // Bedrock reverses ten 64×8 frames at 10 fps in its installed progress screen
    static func frame(at time: TimeInterval) -> Int {
        guard time.isFinite, time > 0 else { return 0 }
        let step = min(17,Int(time.truncatingRemainder(dividingBy:1.8)*10))
        return step < 10 ? step : 18-step
    }

    var body: some View {
        GeometryReader { geometry in
            let scale = max(1,min(1.6,min(geometry.size.width/760,geometry.size.height/620)))
            ZStack {
                if let dirt = frames["loading-dirt"] {
                    Image(nsImage:dirt).resizable(resizingMode:.tile).interpolation(.none)
                } else { Color(red:0.24,green:0.17,blue:0.12) }
                Color.black.opacity(0.65)
                VStack(spacing:0) {
                    GameTitle(image:frames["title"],font:font,splash:"",
                        width:GameTitle.width(in:geometry.size),moving:false)
                        .padding(.top,36)
                    Spacer(minLength:24)
                    VStack(spacing:22*scale) {
                        Text(status.state == "cancelling" ? "Stopping setup" : "Loading Minecraft")
                            .font(Blocks.type(24*scale)).accessibilityAddTraits(.isHeader)
                        Text(status.state == "playing" ? "Starting game…" : status.title)
                            .font(Blocks.type(16*scale)).multilineTextAlignment(.center)
                        if !status.detail.isEmpty && status.state != "playing" {
                            Text(status.detail).font(Blocks.type(14*scale))
                                .multilineTextAlignment(.center).fixedSize(horizontal:false,vertical:true)
                        }
                        TimelineView(.animation(minimumInterval:0.1,paused:!animated)) { tick in
                            Canvas { context,size in
                                let frame = Self.frame(at:animated ? tick.date.timeIntervalSinceReferenceDate : 0)
                                if let atlas = frames["loading_bar"] {
                                    context.draw(Image(nsImage:atlas).interpolation(.none),in:CGRect(x:-CGFloat(frame)*size.width,y:0,width:size.width*10,height:size.height))
                                } else {
                                    for index in 0..<8 {
                                        let rect = CGRect(x:CGFloat(index)*size.width/8,y:0,width:size.width/10,height:size.height)
                                        context.fill(Path(rect),with:.color(.white.opacity(index == frame%8 ? 1 : 0.35)))
                                    }
                                }
                            }.frame(width:256*scale,height:32*scale).clipped()
                        }.accessibilityHidden(true)
                        if let cancel {
                            Button(action:cancel) { Text("Cancel").font(Blocks.type(16*scale)).frame(maxWidth:.infinity,minHeight:44*scale) }
                                .buttonStyle(BlockButton(texture:stone)).keyboardShortcut(.cancelAction)
                        }
                    }.padding(28*scale).frame(width:min(580*scale,geometry.size.width-64))
                        .background(Color(white:0.09))
                        .overlay { Rectangle().strokeBorder(Color(white:0.4),lineWidth:3) }
                        .overlay { Rectangle().strokeBorder(.black,lineWidth:3).padding(-3) }
                    Spacer(minLength:36)
                }.padding(.horizontal,24)
            }.frame(width:geometry.size.width,height:geometry.size.height)
        }.foregroundStyle(.white)
    }
}

struct GameTitle: View {
    let image: NSImage?
    let font: CTFont?
    let splash: String
    let width: CGFloat
    let moving: Bool

    static func width(in size: CGSize) -> CGFloat {
        min(size.width*0.58,size.height*0.95)
    }

    static func formatted(_ text: String) -> AttributedString {
        let palette: [UInt32] = [0x000000,0x0000AA,0x00AA00,0x00AAAA,0xAA0000,0xAA00AA,0xFFAA00,0xAAAAAA,
                                 0x555555,0x5555FF,0x55FF55,0x55FFFF,0xFF5555,0xFF55FF,0xFFFF55,0xFFFFFF]
        var characters = text.makeIterator()
        var colour = Color.yellow
        var result = AttributedString()
        while let character = characters.next() {
            var text = String(character)
            if character == "§", let code = characters.next() {
                if code == "r" || code == "R" { colour = .yellow; continue }
                if let index = Int(String(code),radix:16), palette.indices.contains(index) {
                    let rgb = palette[index]
                    colour = Color(red:Double((rgb>>16)&255)/255,green:Double((rgb>>8)&255)/255,blue:Double(rgb&255)/255)
                    continue
                }
                text.append(code)
            }
            var run = AttributedString(text); run.foregroundColor = colour
            result.append(run)
        }
        return result
    }

    private var splashText: some View {
        Text(Self.formatted(splash)).font(Blocks.type(width*0.033))
            .multilineTextAlignment(.center).lineLimit(2).minimumScaleFactor(0.5)
            .frame(width:width*0.48).shadow(color:.black.opacity(0.65),radius:0,x:1,y:1)
    }

    var body: some View {
        VStack(spacing:-2) {
            Group {
                if let image { Image(nsImage:image).resizable().interpolation(.none).scaledToFit() }
                else {
                    Text("MINECRAFT").font(Blocks.type(width*0.082)).minimumScaleFactor(0.5)
                        .lineLimit(1).shadow(color:.black.opacity(0.6),radius:0,y:3)
                }
            }.frame(width:width,height:width/5.52)
            .overlay(alignment:.bottomTrailing) {
                if !splash.isEmpty {
                    Group {
                        if moving {
                            splashText.phaseAnimator([false,true]) { content,small in
                                content.scaleEffect(small ? 0.94 : 1)
                            } animation: { _ in .easeInOut(duration:0.25) }
                        } else { splashText }
                    }.rotationEffect(.degrees(-20)).offset(x:width*0.16,y:width*0.025)
                        .accessibilityHidden(true).allowsHitTesting(false)
                }
            }
            ZStack {
                ForEach((1...6).reversed(),id:\.self) { depth in
                    Text("MAC EDITION").foregroundStyle(Color(white:0.08))
                        .offset(x:CGFloat(depth)*0.3,y:CGFloat(depth)*0.65)
                }
                Text("MAC EDITION").foregroundStyle(LinearGradient(colors:[.white,Color(white:0.8)],startPoint:.top,endPoint:.bottom))
            }.font(font.map { Font(CTFontCreateCopyWithAttributes($0,width*0.042,nil,nil)) } ?? Blocks.type(width*0.042))
                .padding(.horizontal,22).padding(.top,3).padding(.bottom,8)
                .background {
                    GeometryReader { geometry in
                        let w = geometry.size.width, h = geometry.size.height
                        Path { path in
                            path.move(to:.init(x:5,y:0)); path.addLine(to:.init(x:w-5,y:0))
                            path.addLine(to:.init(x:w,y:h)); path.addLine(to:.init(x:0,y:h)); path.closeSubpath()
                        }.fill(Color(white:0.22)).shadow(color:.black,radius:0,y:4)
                            .overlay(alignment:.top) { Rectangle().fill(.white.opacity(0.25)).frame(height:2).padding(.horizontal,5) }
                    }
                }
        }.frame(width:width)
            .accessibilityElement(children:.ignore).accessibilityLabel("Minecraft Mac Edition")
            .accessibilityAddTraits(.isHeader)
    }
}

private struct Marquee: View {
    let text: String
    let active: Bool
    var size: CGFloat = 18
    var available: CGFloat = 164
    @Environment(\.accessibilityReduceMotion) private var reduced
    @State private var offset: CGFloat = 0
    private var width: CGFloat { (text as NSString).size(withAttributes:[.font:NSFont(name:"Mojangles",size:size) ?? NSFont(name:"Monocraft",size:size) ?? .monospacedSystemFont(ofSize:size,weight:.regular)]).width }

    var body: some View {
        Group {
            if reduced { Text(text).lineLimit(3).fixedSize(horizontal:false,vertical:true) }
            else {
                HStack(spacing:32) {
                    Text(text).fixedSize()
                    if width > available { Text(text).fixedSize() }
                }.offset(x:offset).frame(width:available,alignment:.leading).clipped()
                    .task(id:active ? "\(text):\(size):\(available)" : "") {
                        var transaction = Transaction(); transaction.disablesAnimations = true
                        withTransaction(transaction) { offset = 0 }
                        guard active, width > available else { return }
                        do { try await Task.sleep(for:.seconds(2)) } catch { return }
                        withAnimation(.linear(duration:Double(width+32)/28).repeatForever(autoreverses:false)) { offset = -width-32 }
                    }
            }
        }.font(Blocks.action(size)).accessibilityElement(children:.ignore).accessibilityLabel(text)
    }
}

struct LauncherView: View {
    @ObservedObject var launcher: Launcher
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("animateScenery") private var animateScenery = true
    @AppStorage("rotateScenery") private var rotateScenery = true
    @AppStorage("musicEnabled") private var musicEnabled = true
    @AppStorage("musicVolume") private var musicVolume = 0.18
    @StateObject private var music = Music()
    @AppStorage("renderDistance") private var renderDistance = 16
    @AppStorage("generationSeed") private var worldSeed = "0"
    @AppStorage("controls") private var controlData = Data()
    @AppStorage("skinPath") private var skinPath = ""
    @AppStorage("capePath") private var capePath = ""
    @AppStorage("slimSkin") private var slimSkin = false
    @AppStorage("lookSensitivity") private var lookSensitivity = 50.0
    @AppStorage("invertLook") private var invertLook = false
    @State private var farLands = 0
    @State private var position = Position()
    @State private var sceneryTitle: String?
    @State private var visible = true
    @State private var lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
    @State private var exploring = false
    @State private var mapVisible = true
    @State private var debugVisible = false
    @State private var navigating = false
    @State private var sceneryReady = false
    @State private var avatarError = ""
    @State private var map = false
    @State private var focused = false
    @State private var hint = ShortcutHint()
    @FocusState private var areaFocused: Bool
    #if LAUNCHER_TEST
    init(launcher: Launcher, exploring: Bool = false, hint: ShortcutHint = ShortcutHint()) {
        _launcher = ObservedObject(wrappedValue:launcher)
        _exploring = State(initialValue:exploring)
        _hint = State(initialValue:hint)
    }
    #endif
    private var fresh: Bool { launcher.status.state == "new" }
    private var controls: Controls { Controls(data:controlData) }
    private var available: Bool { launcher.assets != nil && !launcher.sceneryFailed }
    private var canExplore: Bool {available && (sceneryReady || launcher.journey.world.dimension == nil || launcher.journey.world == .overworld && farLands != 0)}
    private var moving: Bool {
        available && !launcher.loading && SceneryMotion.enabled(reduced:reduceMotion,paused:!animateScenery || launcher.settings || launcher.help,lowPower:lowPower,
            active:scenePhase == .active,visible:visible,playing:launcher.status.state == "playing")
    }
    private var hintAvailable: Bool {
        available && !launcher.settings && !launcher.help && launcher.journey.passage == nil && !launcher.running && launcher.status.state != "error"
    }
    private var musicActive: Bool {
        available && !launcher.loading && Music.enabled(muted:!musicEnabled,active:focused && scenePhase == .active,
                                   visible:visible,playing:launcher.status.state == "playing")
    }
    private var primaryTitle: String {
        switch launcher.status.state {
        case "error": return "Try again"
        case "new": return "Install & play"
        case "cancelled": return "Continue"
        default: return "Play"
        }
    }
    private var detail: String {
        if fresh { return "Use the Microsoft account that owns Minecraft for Windows" }
        return launcher.status.detail
    }

    static func scale(in size: CGSize, extra: CGFloat = 0) -> CGFloat {
        let title = GameTitle.width(in:size)
        let reserved: CGFloat = size.width-title >= 560 ? 168 : 248
        return max(1,min(CGFloat(5).squareRoot(),(size.width-80)/364,(size.height-title*0.25-reserved-extra)/270))
    }

    var body: some View {
        GeometryReader { geometry in
            let scale = Self.scale(in:geometry.size,extra:(detail.isEmpty ? 0 : 48)+(fresh ? 24 : 0))
            let footer = 24+20*scale
            let sideHint = geometry.size.width-GameTitle.width(in:geometry.size) >= 560
            ZStack {
                if launcher.loading {
                    Loading(status:launcher.status,frames:launcher.frames,font:launcher.gameFont,stone:launcher.stone,
                        animated:scenePhase == .active && visible && !reduceMotion && !lowPower,
                        cancel:launcher.canCancel ? { launcher.cancel() } : nil)
                        .transition(.opacity)
                } else {
                ZStack {
                    Scenery(journey:launcher.journey,moving:moving,
                        active:scenePhase == .active && visible && !launcher.settings && !launcher.help && launcher.status.state != "playing",exploring:exploring,
                        travel:{ launcher.journey.travel($0) },finish:{ explore(false) },
                        renderDistance:renderDistance,seed:worldSeed,farLands:farLands,location:{ sceneryTitle = $0 },
                        report:exploring ? { point,yaw in position.sample = (point,yaw) } : nil,
                        sensitivity:lookSensitivity,inverted:invertLook,controls:controls,activity:{ navigating = $0 },launcher:launcher)
                        .frame(width:geometry.size.width,height:geometry.size.height).clipped().ignoresSafeArea().allowsHitTesting(exploring)
                    if exploring {
                        ZStack {
                            Rectangle().frame(width:13,height:1)
                            Rectangle().frame(width:1,height:13)
                        }.foregroundStyle(.white.opacity(0.7)).shadow(color:.black,radius:1)
                            .allowsHitTesting(false).accessibilityHidden(true)
                    }
                    if exploring && debugVisible {
                        VStack {HStack {DebugOverlay(position:position,chart:launcher.chart); Spacer()}; Spacer()}
                            .padding(.leading,28).padding(.top,108).allowsHitTesting(false)
                    }
                    VStack(spacing:0) {
                        header(in:geometry.size).padding(.horizontal,28).padding(.top,28)
                        if hintAvailable && hint.showing && !map && !sideHint {
                            HStack { Spacer(); achievement }.padding(.trailing,exploring ? 140 : 28).padding(.top,16)
                                .transition(reduceMotion ? .identity : .move(edge:.trailing).combined(with:.opacity))
                        }
                        Spacer(minLength:16)
                        VStack(spacing:22) {
                            if !exploring { installation(scale:scale) }
                            hotbar(scale:scale)
                        }.frame(maxWidth:640*scale).padding(.horizontal,28).padding(.bottom,footer)
                    }
                    if exploring && mapVisible {
                        VStack { HStack { Minimap(world:launcher.journey.world,position:position,chart:launcher.chart,seed:Seed.number(worldSeed),size:min(160,max(128,geometry.size.width*0.11)),shortcut:controls.label(.map)); Spacer() }; Spacer() }
                            .padding(.leading,28).padding(.top,debugVisible ? 312 : 108).allowsHitTesting(false)
                    }
                    if exploring, let assets = launcher.assets, !skinPath.isEmpty {
                        VStack { HStack { Spacer();
                            Skin(assets:assets,skin:skinPath,cape:capePath,slim:slimSkin,active:scenePhase == .active && visible && !hint.occupied,position:position,failed:{ avatarError = $0 })
                                .frame(width:96,height:144).accessibilityLabel("Your Minecraft character")
                                .overlay {
                                    if !avatarError.isEmpty { Text(avatarError).font(Blocks.type(12)).multilineTextAlignment(.center).foregroundStyle(.white).shadow(color:.black,radius:0,x:1,y:1) }
                                }
                        }; Spacer() }
                            .padding(.trailing,28).padding(.top,108).opacity(hint.occupied ? 0 : 1).allowsHitTesting(false)
                    }
                    if !exploring { VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            look(scale:scale).padding(.trailing,24).padding(.bottom,footer)
                        }
                    } }
                    if !exploring { VStack {
                        Spacer()
                        HStack {
                            Hover(anchor:.leading) { _ in Link("@Keys-i",destination:URL(string:"https://keysi.dev")!)
                                .buttonStyle(.plain).tint(.white)
                                .accessibilityLabel("Developer Keys-i, open keysi.dev")
                            }
                            Spacer()
                            Hover(anchor:.trailing) { _ in Text("v" + (Bundle.main.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String ?? "0.17.0")) }
                        }.font(Blocks.type(max(24,20*scale))).foregroundStyle(.white)
                            .shadow(color:.black.opacity(0.6),radius:0,x:1,y:1)
                            .padding(.horizontal,24).padding(.bottom,16)
                    } }
                    if hintAvailable && hint.showing && !map && sideHint {
                        VStack {
                            HStack { Spacer(); achievement }
                            Spacer()
                        }.padding(.trailing,28).padding(.top,104)
                            .transition(reduceMotion ? .identity : .move(edge:.trailing).combined(with:.opacity))
                    }
                    GenerationStatus(chart:launcher.chart)
                }
                }
            }.animation(reduceMotion ? nil : .easeOut(duration:0.18),value:launcher.loading)
        }
        .disabled(map || launcher.settings || launcher.help).accessibilityHidden(map || launcher.settings || launcher.help)
        .background(Input(enabled:available && !map && !launcher.settings && !launcher.help && !launcher.loading && launcher.status.state != "playing",controls:controls,changed:{ step in
            let index = (launcher.selection+step+launcher.worlds.count)%launcher.worlds.count
            launcher.journey.select(launcher.worlds[index],animated:moving)
        },action:{ action in
            switch action {
            case .look: explore(!exploring)
            case .map:
                if exploring { mapVisible.toggle() }
                else { mapVisible = true; explore(true) }
            case .previous: launcher.journey.travel(-1)
            case .next: launcher.journey.travel(1)
            case .overworld,.nether,.end,.sift:
                let world: World = action == .overworld ? .overworld : action == .nether ? .nether : action == .end ? .end : .sift
                launcher.journey.select(world,animated:moving)
            default: break
            }
        },skip:launcher.journey.passage != nil && !exploring ? {
            if let skip = launcher.chart.skip {skip()} else {launcher.journey.skip()}
        } : nil,debug:exploring ? {debugVisible.toggle()} : nil))
        .overlay {
            if map || launcher.settings || launcher.help {
                GeometryReader { geometry in
                    ZStack {
                        Color.black.opacity(0.65).onTapGesture { map = false; launcher.settings = false; launcher.help = false }
                        if launcher.help {
                            Help(launcher:launcher,close:{ launcher.help = false })
                        } else if launcher.settings {
                            Preferences(launcher:launcher,close:{ launcher.settings = false })
                                .frame(width:min(1040,geometry.size.width-48),height:min(800,geometry.size.height-48))
                        } else {
                            Biomes(world:launcher.journey.world,selected:launcher.journey.biome,
                                frames:launcher.frames,stone:launcher.stone,
                                choose:{ launcher.journey.area($0); map = false },close:{ map = false },
                                farLands:{ farLands += 1; map = false; explore(true) })
                                .frame(width:min(600,geometry.size.width-56),height:min(580,geometry.size.height-56))
                        }
                    }.frame(maxWidth:.infinity,maxHeight:.infinity)
                }
            }
        }
        .ignoresSafeArea(.container).background(.black)
        .foregroundStyle(.white).environment(\.colorScheme,.dark)
        .frame(minWidth:760,minHeight:620)
        .onAppear {
            if UserDefaults.standard.object(forKey:"generationSeed") == nil, let previous = UserDefaults.standard.object(forKey:"worldSeed") as? Int { worldSeed = String(previous) }
            if let window = NSApp?.keyWindow { focused = window.title == launcherName }
        }
        .task(id:musicActive) { music.update(assets:launcher.assets,active:musicActive,volume:musicVolume) }
        .onChange(of:musicVolume) { music.update(assets:launcher.assets,active:musicActive,volume:musicVolume) }
        .onDisappear { music.stop() }
        .onReceive(launcher.chart.$error) { if $0 != nil { explore(false) } }
        .onReceive(launcher.chart.$visible) { ready in sceneryReady = ready; if !ready && !canExplore {explore(false)} }
        .onReceive(NotificationCenter.default.publisher(for:NSWindow.didBecomeKeyNotification)) { notification in
            focused = (notification.object as? NSWindow)?.title == launcherName
        }
        .onReceive(NotificationCenter.default.publisher(for:NSWindow.didResignKeyNotification)) { notification in
            if (notification.object as? NSWindow)?.title == launcherName { focused = false }
        }
        .onReceive(launcher.chart.$arrival) { arrival in
            if arrival != nil { hint.show(at:ProcessInfo.processInfo.systemUptime) }
        }
        .task(id:hint.generation) {
            while hint.occupied && !Task.isCancelled {
                do { try await Task.sleep(for:.seconds(hint.delay(at:ProcessInfo.processInfo.systemUptime))) } catch { return }
                guard !Task.isCancelled else { return }
                hint.advance(at:ProcessInfo.processInfo.systemUptime)
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration:0.4),value:hint.showing)
        .onExitCommand { if launcher.help { launcher.help = false } else if launcher.settings { launcher.settings = false } else if map { map = false } else if exploring { explore(false) } else if launcher.canCancel { launcher.cancel() } }
        .onReceive(NotificationCenter.default.publisher(for:.NSProcessInfoPowerStateDidChange)) { _ in lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled }
        .onReceive(NotificationCenter.default.publisher(for:NSWindow.didChangeOcclusionStateNotification)) { _ in
            visible = NSApp.windows.contains { $0.title == launcherName && $0.occlusionState.contains(.visible) }
        }
        .onChange(of:launcher.settings) {
            if launcher.settings { map = false; explore(false) }
        }
        .onChange(of:launcher.help) {
            if launcher.help { map = false; explore(false) }
        }
        .onChange(of:reduceMotion) { if reduceMotion { launcher.journey.skip() } }
        .onChange(of:lowPower) { if lowPower { launcher.journey.skip() } }
        .onChange(of:available) { if !available { explore(false) } }
        .onChange(of:launcher.journey.world) { if launcher.journey.passage != nil { explore(false) } }
        .onChange(of:launcher.loading) { if launcher.loading { explore(false); map = false; launcher.settings = false } }
        .task(id:moving && !exploring && !map && (rotateScenery || launcher.journey.passage != nil)) {
            guard moving, !exploring, !map, rotateScenery || launcher.journey.passage != nil else { return }
            while !Task.isCancelled {
                do { try await Task.sleep(for:.seconds(1)) } catch { return }
                guard !Task.isCancelled else { return }
                if !navigating { launcher.journey.tick(rotate:rotateScenery) }
            }
        }
    }

    private func header(in size: CGSize) -> some View {
        VStack(spacing:18) {
            HStack(alignment:.top,spacing:8) {
                location(in:size).opacity(available ? 1 : 0).accessibilityHidden(!available)
                Spacer()
                if !exploring {
                    Button { launcher.showHelp() } label: { Text("?").font(Blocks.type(24)).frame(width:44,height:44) }
                        .help("Help").accessibilityLabel("Help")
                }
            }.buttonStyle(BlockButton(texture:launcher.stone))
            if !exploring {
                GameTitle(image:launcher.frames["title"],font:launcher.gameFont,splash:launcher.splash,
                          width:GameTitle.width(in:size),moving:moving && focused && !map && launcher.status.state != "error")
            }
        }
    }

    @ViewBuilder private func glyph(_ name: String, fallback: String, size: CGFloat = 24) -> some View {
        if let image = launcher.frames[name] { Image(nsImage:image).resizable().interpolation(.none).scaledToFit().frame(width:size,height:size) }
        else { Image(systemName:fallback).font(.system(size:size*22/24,weight:.medium)) }
    }

    private func location(in size: CGSize) -> some View {
        let type = max(24,20*Self.scale(in:size))*1.25
        let width = min(size.width*0.46,max(230,type*9))
        return VStack(alignment:.leading,spacing:8) {
            if let passage = launcher.journey.passage {
                Marquee(text:sceneryTitle ?? (passage == .mine ? "Mineshaft" : passage == .stronghold ? "Stronghold" : "Rift valley"),active:focused,size:type,available:width)
                    .accessibilityAddTraits(.isHeader)
                Button { if let skip = launcher.chart.skip {skip()} else {launcher.journey.skip()} } label: {
                    Text("Skip journey").font(Blocks.action(13)).padding(.horizontal,12).frame(height:44)
                }.buttonStyle(BlockButton(texture:launcher.stone))
            } else if exploring {
                Marquee(text:sceneryTitle ?? launcher.journey.title,active:focused,size:type,available:width)
                    .frame(minHeight:44).shadow(color:.black.opacity(0.6),radius:0,x:1,y:1)
            } else {
                Button { map = true } label: {
                    HStack(spacing:8) {
                        Marquee(text:sceneryTitle ?? launcher.journey.title,active:focused && !map,size:type,available:width-22)
                        Image(systemName:"chevron.down").font(.system(size:10,weight:.bold))
                    }.frame(minHeight:44)
                        .shadow(color:.black.opacity(0.25),radius:2,y:1)
                }.buttonStyle(.plain).focused($areaFocused)
                    .overlay { Rectangle().strokeBorder(Blocks.gold,lineWidth:2).padding(-4).opacity(areaFocused ? 1 : 0) }
                    .accessibilityLabel("Choose biome: " + (sceneryTitle ?? launcher.journey.title))
                    .help("Choose biome")
                    .disabled(!available)
            }
        }.frame(width:width,alignment:.leading)
    }

    private func hotbar(scale: CGFloat) -> some View {
        HStack(spacing:0) {
            ForEach(launcher.worlds.indices,id:\.self) { index in
                let world = launcher.worlds[index]
                Button { launcher.journey.select(world,animated:moving) } label: {
                    Slot(world:world,image:launcher.items[world],scale:scale)
                }
                .buttonStyle(InventoryButton(selected:launcher.selection == index,
                    slot:launcher.frames["hotbar_0"],selection:launcher.frames["selected_hotbar_slot"],scale:scale))
                .disabled(!available)
                .accessibilityLabel("\(world.title) scenery")
                .accessibilityAddTraits(launcher.selection == index ? .isSelected : [])
                .help(world.title)
            }
        }.padding(6*scale)
            .accessibilityElement(children:.contain).accessibilityLabel("Realm hotbar")
    }

    private func look(scale: CGFloat) -> some View {
        Button { explore(!exploring) } label: {
            glyph("spyglass",fallback:exploring ? "eye.fill" : "eye",size:32.4*scale).frame(width:56*scale,height:56*scale)
        }.buttonStyle(BlockButton(selected:exploring,texture:launcher.stone,scale:scale))
            .disabled(!canExplore || launcher.journey.passage == .rift || launcher.status.state == "playing")
            .accessibilityLabel(exploring ? "Leave spectator view" : "Look around")
            .accessibilityHint("WASD flies, mouse movement turns the view, Space and Shift change height, Control sprints, Escape returns")
            .help(exploring ? "Return · Esc" : "Look around · \(controls.label(.look))")
    }

    private func explore(_ enabled: Bool) {
        if enabled && (!canExplore || launcher.loading || launcher.status.state == "playing" || launcher.journey.passage == .rift) { return }
        exploring = enabled
        if !enabled {debugVisible = false}
    }

    private var achievement: some View {
        HStack(spacing:12) {
            ZStack {
                glyph("map",fallback:"map",size:32).offset(x:-3,y:-3)
                glyph("compass",fallback:"location.north.circle",size:23).offset(x:8,y:8)
            }.frame(width:40,height:40)
            VStack(alignment:.leading,spacing:5) {
                Text("Achievement made").font(Blocks.type(15)).foregroundStyle(Blocks.gold)
                Text("Exploring the world").font(Blocks.type(16)).lineLimit(1)
            }
        }.padding(.horizontal,12).frame(width:304,height:64,alignment:.leading)
            .background {
                Rectangle().fill(Color(white:0.13))
            }
            .clipShape(ToastFrame())
            .overlay { ToastFrame().stroke(.black,lineWidth:2) }
            .overlay { ToastFrame().stroke(Color(white:0.35),lineWidth:3).padding(3) }
            .accessibilityElement(children:.combine)
            .accessibilityLabel("Achievement made. Exploring the world. \(launcher.chart.arrival ?? "")")
            .allowsHitTesting(false)
    }

    @ViewBuilder private func installation(scale: CGFloat) -> some View {
        if !launcher.running && ["ready","new","cancelled"].contains(launcher.status.state) {
            VStack(spacing:9*scale) {
                playButton(width:320,scale:scale)
                Button { launcher.showSettings() } label: {
                    Text("Settings").font(Blocks.type(20*scale)).frame(width:320*scale,height:54*scale)
                }.buttonStyle(BlockButton(texture:launcher.stone,scale:scale))
                if !detail.isEmpty {
                    Text(detail).font(Blocks.type(14*scale)).multilineTextAlignment(.center)
                        .frame(maxWidth:500).shadow(color:.black.opacity(0.25),radius:2,y:1).textSelection(.enabled)
                }
                if fresh || launcher.status.state == "cancelled" { setupSteps }
            }
        } else { panel }
    }

    private func playButton(width: CGFloat, scale: CGFloat = 1) -> some View {
        Button { launcher.start() } label: {
            Text(primaryTitle).font(Blocks.type((width>200 ? 24 : 18)*scale))
                .frame(width:width*scale,height:62*scale)
        }.buttonStyle(BlockButton(scale:scale)).keyboardShortcut(.defaultAction).help(primaryTitle)
    }

    private var setupSteps: some View {
        HStack(spacing:16) {
            ForEach(0..<4,id:\.self) { index in
                HStack(spacing:6) {
                    Image(systemName:launcher.status.stage.map { index < $0 } == true ? "checkmark" : ["person.fill","arrow.down","hammer.fill","play.fill"][index])
                        .foregroundStyle(launcher.status.stage == index ? Blocks.gold : Blocks.grass)
                    Text(["Sign in","Download","Prepare","Play"][index])
                }.font(Blocks.type(12))
                    .accessibilityLabel("\(["Sign in","Download","Prepare","Play"][index]), \(launcher.status.stage.map { index < $0 ? "complete" : index == $0 ? "current" : "upcoming" } ?? "upcoming")")
            }
        }
    }

    private var panel: some View {
        VStack(alignment:.leading,spacing:14) {
            HStack(spacing:24) {
                VStack(alignment:.leading,spacing:7) {
                    Text(fresh ? "Install Minecraft" : launcher.status.title)
                        .font(Blocks.action(20)).fixedSize(horizontal:false,vertical:true).accessibilityAddTraits(.isHeader)
                    if !detail.isEmpty {
                        if detail.count > 240 {
                            ScrollView {
                                Text(detail).font(Blocks.type(14)).foregroundStyle(Blocks.ink)
                                    .frame(maxWidth:.infinity,alignment:.leading).textSelection(.enabled)
                            }.frame(height:80)
                        } else {
                            Text(detail).font(Blocks.type(14)).foregroundStyle(Blocks.ink)
                                .fixedSize(horizontal:false,vertical:true).textSelection(.enabled)
                        }
                    }
                }.frame(maxWidth:.infinity,alignment:.leading)
                if !launcher.running {
                    playButton(width:188)
                } else if launcher.canCancel {
                    Button { launcher.cancel() } label: {
                        Text("Cancel setup").font(Blocks.action(14)).frame(width:160,height:54)
                    }.buttonStyle(BlockButton(texture:launcher.stone)).keyboardShortcut(.cancelAction)
                } else {
                    Label(launcher.status.state == "playing" ? "Game running" : "Please wait",systemImage:launcher.status.state == "playing" ? "checkmark" : "hourglass")
                        .font(Blocks.action(13)).frame(width:160,height:54)
                }
            }
            if launcher.status.state == "busy", let fraction = launcher.status.fraction {
                HStack {
                    Text(launcher.status.stage.map { ["Microsoft sign-in","Downloading your game","Preparing Minecraft","Ready"][min(3,$0)] } ?? "Getting ready")
                    Spacer()
                    Text(fraction,format:.percent.precision(.fractionLength(0))).monospacedDigit()
                }.font(Blocks.type(12)).foregroundStyle(Blocks.ink)
                ProgressView(value:fraction).progressViewStyle(Experience()).accessibilityLabel("Overall setup")
            }
            if fresh || launcher.status.state == "busy" || launcher.status.state == "cancelled" {
                setupSteps
            }
            if launcher.status.state == "error" {
                Button { launcher.showLog() } label: {
                    Label("Open setup log",systemImage:"doc.text").font(Blocks.action(12))
                        .padding(.horizontal,12).frame(height:36)
                }.buttonStyle(BlockButton(texture:launcher.stone))
            }
        }
        .padding(20)
        .background {
            Rectangle().fill(Blocks.stone.opacity(reduceTransparency ? 1 : 0.97))
                .shadow(color:.black.opacity(0.4),radius:0,x:0,y:5)
        }
        .overlay(alignment:.top) { Rectangle().fill(.white.opacity(0.2)).frame(height:2) }
        .overlay(alignment:.bottom) { Rectangle().fill(.black.opacity(0.6)).frame(height:4) }
        .overlay { Rectangle().strokeBorder(.black.opacity(0.8),lineWidth:2) }
    }
}

struct Biomes: View {
    let world: World
    let selected: Int
    let frames: [String:NSImage]
    let stone: NSImage?
    let choose: (Int) -> Void
    let close: () -> Void
    var farLands: () -> Void = {}
    @State private var search = ""
    @FocusState private var searching: Bool
    @FocusState private var focused: Int?

    private var query: String { search.trimmingCharacters(in:.whitespacesAndNewlines) }
    private var matches: [Int] { world.biomes.indices.filter { query.isEmpty || world.biomes[$0].rawValue.localizedCaseInsensitiveContains(query) } }
    private var farLandsMatch: Bool { world == .overworld && (query.isEmpty || "Far Lands historical recreation".localizedCaseInsensitiveContains(query)) }

    var body: some View {
        VStack(spacing:0) {
            HStack {
                Text("Explore \(world.title)").font(Blocks.type(22)).accessibilityAddTraits(.isHeader)
                Spacer()
                Button(action:close) { Image(systemName:"xmark").frame(width:40,height:40) }
                    .buttonStyle(BlockButton(texture:stone)).accessibilityLabel("Close biomes")
            }.padding(20)
            HStack(spacing:12) {
                Image(systemName:"magnifyingglass").accessibilityHidden(true)
                TextField("Find a biome or landmark",text:$search).textFieldStyle(.plain)
                    .font(Blocks.type(13)).focused($searching)
                    .accessibilityLabel("Find a biome or landmark")
                    .onSubmit { if let first = matches.first { choose(first) } else if farLandsMatch { farLands() } }
                    .onKeyPress(.downArrow) { focused = matches.first ?? (farLandsMatch ? -1 : nil); return .handled }
                if !search.isEmpty {
                    Button { search = ""; searching = true } label: { Image(systemName:"xmark").frame(width:28,height:28) }
                        .buttonStyle(.plain).accessibilityLabel("Clear search")
                }
            }.padding(12).background(.white.opacity(0.32))
                .overlay { Rectangle().strokeBorder(searching ? Blocks.ink : .black.opacity(0.35),lineWidth:2) }
                .padding(.horizontal,20).padding(.bottom,16)
            ScrollViewReader { scroll in
                ScrollView {
                    LazyVStack(spacing:6) {
                        ForEach(matches,id:\.self) { index in
                            let area = world.biomes[index]
                            Button { choose(index) } label: {
                                HStack(spacing:14) {
                                    if let image = frames["biome-"+area.surface] {
                                        Image(nsImage:image).resizable().interpolation(.none)
                                            .frame(width:36,height:36).accessibilityHidden(true)
                                    }
                                    Text(area.rawValue).font(Blocks.type(14))
                                        .frame(maxWidth:.infinity,alignment:.leading).multilineTextAlignment(.leading)
                                        .fixedSize(horizontal:false,vertical:true)
                                    if selected == index { Image(systemName:"checkmark").foregroundStyle(Blocks.ink) }
                                }.padding(.horizontal,14).frame(minHeight:58)
                            }.buttonStyle(BlockButton(selected:selected == index,texture:stone))
                                .focusable().focused($focused,equals:index).id(index)
                                .accessibilityAddTraits(selected == index ? .isSelected : [])
                                .onKeyPress(.return) { choose(index); return .handled }
                                .onKeyPress(.space) { choose(index); return .handled }
                                .onKeyPress(.downArrow) { move(from:index,by:1); return .handled }
                                .onKeyPress(.upArrow) { move(from:index,by:-1); return .handled }
                        }
                        if farLandsMatch {
                            Button(action:farLands) {
                                VStack(alignment:.leading,spacing:6) {
                                    Text("Far Lands").font(Blocks.type(18))
                                    Text("Historical recreation").font(Blocks.type(12))
                                }.frame(maxWidth:.infinity,alignment:.leading).padding(14)
                            }.buttonStyle(BlockButton(texture:stone)).focusable().focused($focused,equals:-1).id(-1)
                                .onKeyPress(.return) { farLands(); return .handled }
                                .onKeyPress(.upArrow) { move(from:-1,by:-1); return .handled }
                                .help("Visit Far Lands")
                        }
                        if matches.isEmpty && !farLandsMatch {
                            Text("No matching biomes").font(Blocks.type(15)).padding(.vertical,32)
                        }
                    }.padding(12)
                }.background(.black.opacity(0.06))
                    .overlay { Rectangle().strokeBorder(.black,lineWidth:2) }
                    .onChange(of:focused) { if let focused { scroll.scrollTo(focused) } }
                    .onAppear { scroll.scrollTo(selected,anchor:.center) }
            }.padding(.horizontal,20)
            if world == .sift {
                Text("Sift interpretation").font(Blocks.type(11)).foregroundStyle(Blocks.ink).padding(20)
            } else { Color.clear.frame(height:20) }
        }.foregroundStyle(Blocks.ink).background(Blocks.stone)
            .overlay { Rectangle().strokeBorder(.black,lineWidth:3) }
            .overlay { Rectangle().strokeBorder(.white.opacity(0.3),lineWidth:2).padding(3) }
            .environment(\.colorScheme,.light)
            .task { searching = true }
            .onExitCommand(perform:close)
    }

    private func move(from index: Int, by step: Int) {
        if index == -1 { focused = matches.last; if focused == nil { searching = true }; return }
        guard let position = matches.firstIndex(of:index) else { return }
        let next = position+step
        if matches.indices.contains(next) { focused = matches[next] }
        else if farLandsMatch && next == matches.count { focused = -1 }
        else if next<0 { searching = true }
    }
}

private struct Switch: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            HStack(spacing:20) {
                configuration.label.frame(maxWidth:.infinity,alignment:.leading)
                ZStack(alignment:configuration.isOn ? .trailing : .leading) {
                    Rectangle().fill(configuration.isOn ? Blocks.play : Color(white:0.5))
                        .frame(width:64,height:30).overlay { Rectangle().strokeBorder(.black,lineWidth:2) }
                    Text(configuration.isOn ? "I" : "O").font(Blocks.type(14)).foregroundStyle(.black)
                        .offset(x:configuration.isOn ? -39 : 39)
                    Rectangle().fill(Blocks.stone).frame(width:34,height:36)
                        .overlay { Rectangle().strokeBorder(.black,lineWidth:2) }
                        .overlay { Rectangle().strokeBorder(.white.opacity(0.55),lineWidth:2).padding(4) }
                }.frame(width:68,height:40)
            }.contentShape(Rectangle())
        }.buttonStyle(.plain)
            .accessibilityRepresentation { Toggle(isOn:configuration.$isOn) { configuration.label } }
    }
}

private struct SettingSlider: View {
    let title: String
    let detail: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double = 1
    let scale: CGFloat
    let format: (Double) -> String
    @FocusState private var focused: Bool

    private var fraction: Double { min(1,max(0,(value-range.lowerBound)/(range.upperBound-range.lowerBound))) }
    private func set(_ next: Double) { value = min(range.upperBound,max(range.lowerBound,(next/step).rounded()*step)) }

    var body: some View {
        VStack(alignment:.leading,spacing:12*scale) {
            HStack(alignment:.firstTextBaseline) {
                Text(title).font(Blocks.type(18*scale))
                Spacer(minLength:12)
                Text(format(value)).font(Blocks.type(18*scale)).monospacedDigit()
            }
            Text(detail).font(Blocks.type(13*scale)).foregroundStyle(Color(white:0.78))
                .fixedSize(horizontal:false,vertical:true).lineSpacing(4)
            GeometryReader { geometry in
                let thumb = 30*scale, travel = max(1,geometry.size.width-thumb)
                ZStack(alignment:.leading) {
                    Rectangle().fill(.black).frame(height:12*scale)
                    Rectangle().fill(Color(white:0.58)).frame(height:6*scale).padding(.horizontal,3*scale)
                    Rectangle().fill(Blocks.grass).frame(width:thumb/2+travel*fraction,height:6*scale).padding(.leading,3*scale)
                    Rectangle().fill(Blocks.stone).frame(width:thumb,height:34*scale)
                        .overlay { Rectangle().strokeBorder(.black,lineWidth:2*scale) }
                        .overlay { Rectangle().strokeBorder(focused ? .white : .white.opacity(0.45),lineWidth:2*scale).padding(4*scale) }
                        .offset(x:travel*fraction)
                }.frame(height:44*scale).contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance:0).onChanged { drag in
                        focused = true
                        set(range.lowerBound+Double((drag.location.x-thumb/2)/travel)*(range.upperBound-range.lowerBound))
                    })
            }.frame(height:44*scale).focusable().focused($focused)
                .accessibilityElement().accessibilityLabel(title).accessibilityValue(format(value))
                .accessibilityAdjustableAction { set(value+($0 == .increment ? step : -step)) }
                .onKeyPress(.leftArrow) { set(value-step); return .handled }
                .onKeyPress(.rightArrow) { set(value+step); return .handled }
        }.padding(22*scale)
    }
}

struct Preferences: View {
    @ObservedObject var launcher: Launcher
    let close: () -> Void
    @AppStorage("animateScenery") private var animateScenery = true
    @AppStorage("rotateScenery") private var rotateScenery = true
    @AppStorage("musicEnabled") private var musicEnabled = true
    @AppStorage("musicVolume") private var musicVolume = 0.18
    @AppStorage("renderDistance") private var renderDistance = 16
    @AppStorage("generationSeed") private var worldSeed = "0"
    @AppStorage("controls") private var controlData = Data()
    @AppStorage("skinPath") private var skinPath = ""
    @AppStorage("capePath") private var capePath = ""
    @AppStorage("slimSkin") private var slimSkin = false
    @AppStorage("lookSensitivity") private var lookSensitivity = 50.0
    @AppStorage("invertLook") private var invertLook = false
    @Environment(\.accessibilityReduceMotion) private var reduced
    @State private var page: Page = .video
    @State private var seedText = ""
    @State private var seedError = false
    @State private var skinError: String?
    @FocusState private var focused: Page?

    private enum Page: String, CaseIterable {
        case accessibility = "Accessibility", input = "Keyboard & Mouse", video = "Video", audio = "Audio", character = "Character"
        var symbol: String {
            switch self {
            case .accessibility: return "figure.stand"
            case .input: return "keyboard"
            case .video: return "photo"
            case .audio: return "speaker.wave.2.fill"
            case .character: return "person.crop.square"
            }
        }
        var glyph: String {
            switch self {
            case .accessibility: return "accessibility_glyph_color"
            case .input: return "keyboard_and_mouse_glyph_color"
            case .video: return "video_glyph_color"
            case .audio: return "sound_glyph_color"
            case .character: return "character_glyph"
            }
        }
        var detail: String {
            switch self {
            case .accessibility: return "Make the launcher comfortable for you"
            case .input: return "Adjust the Look around controls"
            case .video: return "Choose how the launcher world moves and renders"
            case .audio: return "Music from your Minecraft installation"
            case .character: return "Your skin and cape in Look around"
            }
        }
    }

    static func scale(in size: CGSize) -> CGFloat { min(1.5,max(1,min(size.width/700,size.height/560))) }

    var body: some View {
        GeometryReader { geometry in
            let scale = Self.scale(in:geometry.size)
            VStack(spacing:0) {
                HStack {
                    Text("Settings").font(heading(26*scale)).accessibilityAddTraits(.isHeader)
                    Spacer()
                    Button(action:close) { Image(systemName:"xmark").font(.system(size:20*scale,weight:.bold)).frame(width:44*scale,height:44*scale) }
                        .buttonStyle(BlockButton()).accessibilityLabel("Close settings").keyboardShortcut(.cancelAction)
                }.padding(.horizontal,20*scale).padding(.vertical,12*scale)
                    .foregroundStyle(Blocks.ink).background(Blocks.stone)
                HStack(spacing:0) {
                    ScrollView {
                        VStack(spacing:0) {
                            category(.accessibility,scale:scale)
                            group("Controls",scale:scale)
                            category(.input,scale:scale)
                            group("General",scale:scale)
                            category(.video,scale:scale)
                            category(.audio,scale:scale)
                            category(.character,scale:scale)
                        }.padding(.top,12*scale)
                    }.frame(width:geometry.size.width*0.31).background(Color(white:0.19))
                    Rectangle().fill(.black.opacity(0.65)).frame(width:4*scale)
                    ScrollView {
                        VStack(alignment:.leading,spacing:0) {
                            VStack(alignment:.leading,spacing:10*scale) {
                                Text(page.rawValue).font(heading(23*scale)).accessibilityAddTraits(.isHeader)
                                Text(page.detail).font(Blocks.type(14*scale)).foregroundStyle(Color(white:0.8))
                                    .fixedSize(horizontal:false,vertical:true)
                            }.padding(22*scale)
                            rule
                            content(scale:scale)
                            rule
                            Button(action:reset) { Text("Reset defaults").font(Blocks.type(16*scale)).frame(maxWidth:.infinity,minHeight:46*scale) }
                                .buttonStyle(BlockButton(scale:scale)).padding(22*scale)
                            Text("These settings apply to the launcher\nChange game settings inside Minecraft")
                                .font(Blocks.type(12*scale)).foregroundStyle(Color(white:0.8))
                                .fixedSize(horizontal:false,vertical:true).padding(.horizontal,22*scale).padding(.bottom,22*scale)
                        }.frame(maxWidth:.infinity,alignment:.leading)
                    }.id(page).background(Color(white:0.28))
                }
            }.foregroundStyle(.white).background(Color(white:0.19))
                .overlay { Rectangle().strokeBorder(.black,lineWidth:3) }
        }.environment(\.colorScheme,.dark).onExitCommand(perform:close)
            .onAppear {
                renderDistance = min(512,max(8,renderDistance))
                lookSensitivity = lookSensitivity.isFinite ? min(100,max(1,lookSensitivity)) : 50
                musicVolume = musicVolume.isFinite ? min(1,max(0,musicVolume)) : 0.18
                seedText = worldSeed
            }
    }

    private var rule: some View { Rectangle().fill(.black.opacity(0.35)).frame(height:2).overlay(alignment:.bottom) { Rectangle().fill(.white.opacity(0.1)).frame(height:1) } }
    private func heading(_ size: CGFloat) -> Font { launcher.gameFont.map { Font(CTFontCreateCopyWithAttributes($0,size,nil,nil)) } ?? Blocks.type(size) }
    private func group(_ title: String, scale: CGFloat) -> some View {
        Text(title).font(Blocks.type(14*scale)).foregroundStyle(Color(white:0.75))
            .frame(maxWidth:.infinity,alignment:.leading).padding(.horizontal,16*scale).padding(.top,28*scale).padding(.bottom,12*scale)
    }
    private func category(_ item: Page, scale: CGFloat) -> some View {
        Hover { hovered in
            Button { page = item } label: {
                HStack(spacing:12*scale) {
                    if let image = launcher.frames[item.glyph] {
                        Image(nsImage:image).resizable().interpolation(.none).scaledToFit().frame(width:28*scale,height:28*scale).accessibilityHidden(true)
                    } else { Image(systemName:item.symbol).font(.system(size:20*scale)).frame(width:28*scale).accessibilityHidden(true) }
                    Text(item.rawValue).font(Blocks.type(15*scale)).fixedSize(horizontal:false,vertical:true)
                    Spacer(minLength:0)
                }.padding(.horizontal,16*scale).frame(minHeight:68*scale)
                    .background(hovered ? Blocks.play : Color(white:page == item ? 0.3 : 0.19))
                    .overlay { Rectangle().strokeBorder(.white,lineWidth:2).opacity(focused == item ? 1 : 0) }
            }.buttonStyle(.plain).focused($focused,equals:item)
                .accessibilityAddTraits(page == item ? .isSelected : [])
        }
    }
    private func toggle(_ title: String, detail: String, value: Binding<Bool>, scale: CGFloat) -> some View {
        Toggle(isOn:value) {
            VStack(alignment:.leading,spacing:8*scale) {
                Text(title).font(Blocks.type(18*scale))
                Text(detail).font(Blocks.type(13*scale)).foregroundStyle(Color(white:0.8))
                    .fixedSize(horizontal:false,vertical:true).lineSpacing(4)
            }
        }.toggleStyle(Switch()).padding(22*scale)
    }
    @ViewBuilder private func content(scale: CGFloat) -> some View {
        switch page {
        case .video:
            toggle("Background animation",detail:"Let the world, weather and mobs move",value:$animateScenery,scale:scale)
            rule
            toggle("Automatic travel",detail:"Tour the biomes while the menu is open",value:$rotateScenery,scale:scale).disabled(!animateScenery)
            rule
            SettingSlider(title:"Render distance",detail:"Nearby detail first · 16 blocks per chunk",value:Binding(get:{Double(renderDistance)},set:{renderDistance = Int($0)}),range:8...512,scale:scale,format:{"\(Int($0)) chunks"})
            rule
            VStack(alignment:.leading,spacing:12*scale) {
                Text("World seed").font(Blocks.type(18*scale))
                Text("Grow a different launcher landscape").font(Blocks.type(13*scale)).foregroundStyle(Color(white:0.8))
                HStack(spacing:12*scale) {
                    TextField("Seed",text:$seedText).textFieldStyle(.plain).font(Blocks.type(16*scale))
                        .padding(12*scale).background(.black.opacity(0.5))
                        .overlay { Rectangle().strokeBorder(seedError ? .red : .white.opacity(0.4),lineWidth:2) }
                        .accessibilityLabel("World seed").onSubmit(applySeed)
                    Button(action:applySeed) { Text("Generate").font(Blocks.type(15*scale)).padding(.horizontal,16*scale).frame(minHeight:44*scale) }
                        .buttonStyle(BlockButton(scale:scale))
                }
                if seedError { Text("Use up to 256 characters, without control characters").font(Blocks.type(13*scale)).foregroundStyle(.white) }
            }.padding(22*scale)
        case .audio:
            SettingSlider(title:"Master volume",detail:"Adjust menu and game music in the launcher",value:Binding(get:{musicEnabled ? musicVolume : 0},set:{musicVolume = $0; musicEnabled = $0>0}),range:0...1,step:0.01,scale:scale,format:{"\(Int(($0*100).rounded()))%"})
        case .input:
            let controls = Controls(data:controlData)
            SettingSlider(title:"Camera sensitivity",detail:"Adjust the speed of mouse look",value:$lookSensitivity,range:1...100,scale:scale,format:{"\(Int($0))"})
            rule
            toggle("Invert camera Y-axis",detail:"Reverse up and down when looking around",value:$invertLook,scale:scale)
            rule
            Text("\(controls.label(.forward)) \(controls.label(.left)) \(controls.label(.back)) \(controls.label(.right)) · Fly\n\(controls.label(.rise)) / \(controls.label(.descend)) · Up / Down\n\(controls.label(.sprint)) · Sprint\n\(controls.label(.map)) · Map\nF3 · Debug screen\nScroll · Select a realm\nControl + Scroll · Flight speed\nEscape · Return to menu")
                .font(Blocks.type(14*scale)).lineSpacing(10*scale).padding(22*scale)
            rule
            Keymap(data:$controlData,stone:launcher.stone).font(Blocks.type(15*scale)).padding(22*scale)
        case .character:
            VStack(alignment:.leading,spacing:18*scale) {
                Text("Paper doll").font(Blocks.type(18*scale))
                Text("Choose your exported PNG files\nYour images stay on this Mac").font(Blocks.type(14*scale)).lineSpacing(6*scale)
                character("Skin",path:skinPath,scale:scale,cape:false)
                character("Cape",path:capePath,scale:scale,cape:true)
                if let skinError { Text(skinError).font(Blocks.type(14*scale)).fixedSize(horizontal:false,vertical:true) }
            }.padding(22*scale)
            rule
            toggle("Slim arms",detail:"Use the three-pixel arm skin model",value:$slimSkin,scale:scale)
        case .accessibility:
            toggle("Background animation",detail:"Turn off moving scenery and splash animation",value:$animateScenery,scale:scale)
            rule
            Text(reduced ? "macOS Reduced Motion is on" : "The launcher follows macOS Reduced Motion")
                .font(Blocks.type(16*scale)).fixedSize(horizontal:false,vertical:true).padding(22*scale)
            rule
            Text("Use Tab to move between controls\nSpace activates a button or switch\nArrow keys adjust sliders\nEscape closes this menu")
                .font(Blocks.type(14*scale)).lineSpacing(10*scale).padding(22*scale)
        }
    }
    private func applySeed() {
        let seed = seedText.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !seed.isEmpty, seed.utf8.count<=256, seed.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) else { seedError = true; return }
        seedError = false; worldSeed = seed
    }
    private func character(_ title: String, path: String, scale: CGFloat, cape: Bool) -> some View {
        VStack(alignment:.leading,spacing:8*scale) {
            Text(title).font(Blocks.type(16*scale))
            Text(path.isEmpty ? "Not selected" : URL(fileURLWithPath:path).lastPathComponent)
                .font(Blocks.type(13*scale)).lineLimit(1).truncationMode(.middle)
            HStack(spacing:10*scale) {
                Button { chooseSkin(cape:cape) } label: { Text("Choose \(title.lowercased())").font(Blocks.type(14*scale)).padding(.horizontal,14*scale).frame(minHeight:44*scale) }
                    .buttonStyle(BlockButton(scale:scale))
                if !path.isEmpty {
                    Button { if cape { capePath = "" } else { skinPath = "" }; skinError = nil } label: { Text("Clear").font(Blocks.type(14*scale)).padding(.horizontal,14*scale).frame(minHeight:44*scale) }
                        .buttonStyle(BlockButton(scale:scale))
                }
            }
        }
    }
    private func chooseSkin(cape: Bool) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png]; panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
        panel.title = cape ? "Choose your Minecraft cape" : "Choose your Minecraft skin"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            _ = try Skin.image(at:url,cape:cape)
            if cape { capePath = url.path } else { skinPath = url.path }
            skinError = nil
        } catch { skinError = error.localizedDescription }
    }
    private func reset() {
        switch page {
        case .video: animateScenery = true; rotateScenery = true; renderDistance = 16; worldSeed = "0"; seedText = "0"; seedError = false
        case .audio: musicEnabled = true; musicVolume = 0.18
        case .input: lookSensitivity = 50; invertLook = false; controlData = Controls().data
        case .character: skinPath = ""; capePath = ""; slimSkin = false; skinError = nil
        case .accessibility: animateScenery = true
        }
    }
}

struct Help: View {
    @ObservedObject var launcher: Launcher
    let close: () -> Void
    @AppStorage("controls") private var controlData = Data()

    var body: some View {
        let controls = Controls(data:controlData)
        VStack(spacing:20) {
            HStack {
                Text("How to play").font(Blocks.type(26)).accessibilityAddTraits(.isHeader)
                Spacer()
                Button(action:close) { Image(systemName:"xmark").frame(width:44,height:44) }
                    .buttonStyle(BlockButton()).accessibilityLabel("Close help").keyboardShortcut(.cancelAction)
            }
            ScrollView {
                VStack(alignment:.leading,spacing:20) {
                    guide("Start your game", "Choose Install & play, then sign in with the Microsoft account that owns Minecraft for Windows. Your worlds and account stay on this Mac")
                    guide("Look around · \(controls.label(.look))", "\(controls.label(.forward)) \(controls.label(.left)) \(controls.label(.back)) \(controls.label(.right)) flies · Mouse looks · \(controls.label(.rise)) rises · \(controls.label(.descend)) descends · \(controls.label(.sprint)) sprints · \(controls.label(.map)) shows the map · F3 shows debug details · Escape returns")
                    guide("Explore another biome", "Choose the biome name in the menu, or fly there. Scroll chooses a realm. \(controls.label(.previous)) and \(controls.label(.next)) start a flight to a neighbouring biome")
                    guide("Your character", "Choose your skin and cape PNGs in Settings → Character. Your paper doll appears in Look around")
                    guide("Music and motion", "Open Settings to change master volume, background animation and automatic travel. macOS Reduced Motion and Low Power Mode also pause the scenery")
                    guide("Having trouble?", "Use Open setup logs below to inspect a launch failure. Save and quit Minecraft normally before replacing an app or runtime")
                }.padding(.vertical,4)
            }.frame(maxHeight:360)
            HStack(spacing:12) {
                Button { launcher.showLog() } label: { Text("Open setup logs").frame(maxWidth:.infinity,minHeight:44) }
                Button(action:close) { Text("Done").frame(maxWidth:.infinity,minHeight:44) }.keyboardShortcut(.defaultAction)
            }.font(Blocks.type(14)).buttonStyle(BlockButton(texture:launcher.stone))
        }.padding(28).frame(width:600).foregroundStyle(Blocks.ink).background(Blocks.stone)
            .overlay { Rectangle().strokeBorder(.black,lineWidth:3) }
            .environment(\.colorScheme,.light).onExitCommand(perform:close)
    }

    private func guide(_ title: String, _ text: String) -> some View {
        VStack(alignment:.leading,spacing:8) {
            Text(title).font(Blocks.type(15)).foregroundStyle(Blocks.ink).accessibilityAddTraits(.isHeader)
            Text(text).font(Blocks.type(15)).lineSpacing(6).fixedSize(horizontal:false,vertical:true)
        }
    }
}

private struct LauncherMenus: Commands {
    @ObservedObject var launcher: Launcher
    @AppStorage("animateScenery") private var animateScenery = true
    @AppStorage("rotateScenery") private var rotateScenery = true
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        TextEditingCommands()
        CommandGroup(replacing: .newItem) {}
        CommandGroup(replacing:.appSettings) {
            Button("Settings…") { openWindow(id:"launcher"); launcher.showSettings() }
                .keyboardShortcut(",",modifiers:.command)
        }
        CommandGroup(after: .appInfo) {
            Button(launcher.checkingUpdates ? "Checking for Updates…" : "Check for Updates…") {
                launcher.checkUpdates()
            }
            .disabled(launcher.checkingUpdates)
            Divider()
            Button("Sign Out of Microsoft…") { launcher.signOut() }
                .disabled(launcher.running || launcher.status.state == "new")
        }
        CommandGroup(after: .toolbar) {
            Toggle("Animate Scenery", isOn: $animateScenery)
            Toggle("Automatically Change Scenes", isOn: $rotateScenery)
            Button("Next Scene") {
                guard !launcher.worlds.isEmpty else { return }
                let animate = SceneryMotion.enabled(reduced: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
                    paused: !animateScenery, lowPower: ProcessInfo.processInfo.isLowPowerModeEnabled,
                    active: NSApp.isActive, visible: true, playing: launcher.status.state == "playing")
                launcher.journey.select(launcher.worlds[(launcher.selection + 1) % launcher.worlds.count], animated: animate)
            }
            .keyboardShortcut("]", modifiers: .command)
            .disabled(launcher.assets == nil || launcher.sceneryFailed)
            Menu("Choose Biome or Landmark") {
                ForEach(launcher.journey.world.biomes.indices, id: \.self) { index in
                    Button(launcher.journey.world.biomes[index].rawValue) { launcher.journey.area(index) }
                }
            }
            .disabled(launcher.assets == nil || launcher.sceneryFailed)
            Button("Skip Portal Journey") { if let skip = launcher.chart.skip {skip()} else {launcher.journey.skip()} }
                .disabled(launcher.journey.passage == nil)
        }
        CommandGroup(before: .windowList) {
            Button("Show Launcher") { openWindow(id: "launcher") }
                .keyboardShortcut("0", modifiers: .command)
        }
        CommandGroup(replacing: .help) {
            Button("Minecraft Launcher Help") {
                openWindow(id:"launcher")
                launcher.showHelp()
            }
            Button("Open Setup Logs") { launcher.showLog() }
            Button("Report a Problem…") {
                NSWorkspace.shared.open(URL(string: "https://github.com/keys-i/minecraft-mac/issues/new?template=bug_report.yml")!)
            }
        }
    }
}

#if !LAUNCHER_TEST
@main
struct BedrockLauncherApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var launcher = Launcher()
    var body: some Scene {
        Window(launcherName, id: "launcher") {
            LauncherView(launcher: launcher)
                .onAppear { delegate.launcher = launcher; NSApp.activate(ignoringOtherApps: true) }
                .containerBackground(.black,for:.window)
        }
        .defaultSize(width: 1040, height: 760)
        .windowStyle(.hiddenTitleBar)
        .commands { LauncherMenus(launcher: launcher) }
    }
}

#endif
