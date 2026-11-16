import AppKit
import SwiftUI
import CoreText

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
        task.executableURL = packaged ? worker : URL(fileURLWithPath: "/usr/bin/python3")
        task.arguments = (packaged ? [] : [root.appendingPathComponent("src/launcher/setup.py").path]) + (check ? ["--warmup"] : signOut ? ["--sign-out"] : [])
        task.currentDirectoryURL = packaged ? resources : root
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        var env = ProcessInfo.processInfo.environment
        env["PYTHONUNBUFFERED"] = "1"
        if packaged { env["BEDROCK_BUNDLE"] = resources.path }
        task.environment = env
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
                    self.process = nil
                    if task.terminationStatus != 0 && self.status.state != "error" {
                        self.status = Status(state: "error", title: "Couldn’t finish setup", detail: "Try again. If it happens again, open the setup log.", progress: nil)
                    } else if ["busy", "checking", "playing", "cancelling"].contains(self.status.state) {
                        self.status = Status(state: "error", title: "Setup stopped", detail: "Try again to continue.", progress: nil)
                    }
                }
            }
        } catch {
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

    static func gameVisible(_ pid: Int, windows: [[String:Any]]) -> Bool {
        guard pid > 1 && pid <= Int(Int32.max) else { return false }
        return windows.contains { window in
            guard (window[kCGWindowOwnerPID as String] as? NSNumber)?.intValue == pid,
                  (window[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
                  let bounds = window[kCGWindowBounds as String] as? [String:Any],
                  let width = bounds["Width"] as? NSNumber, let height = bounds["Height"] as? NSNumber else { return false }
            return width.doubleValue >= 320 && height.doubleValue >= 200
        }
    }

    private func handoff(_ pid: Int?) {
        windowTask?.cancel(); windowTask = nil
        if let window = hiddenWindow {
            NSApp.unhide(nil); window.makeKeyAndOrderFront(nil); hiddenWindow = nil
        }
        guard let pid, pid > 1 && pid <= Int(Int32.max) else { return }
        windowTask = Task { [weak self] in
            while let self, !Task.isCancelled, self.status.gamePID == pid {
                let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly,.excludeDesktopElements],kCGNullWindowID) as? [[String:Any]] ?? []
                if Self.gameVisible(pid,windows:windows) {
                    let window = NSApp.windows.first { $0.title == launcherName }
                    NSRunningApplication(processIdentifier:pid_t(pid))?.activate(options:[])
                    self.hiddenWindow = window; NSApp.hide(nil)
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
    private(set) var showing = true
    private var deadline: TimeInterval?

    mutating func focus(at time: TimeInterval) {
        if showing {
            if let deadline, time >= deadline { showing = false; self.deadline = time+70 }
            else if deadline == nil { deadline = time+60 }
        } else { deadline = time+70 }
    }

    mutating func advance(at time: TimeInterval) {
        guard let deadline, time >= deadline else { return }
        showing.toggle()
        self.deadline = time+(showing ? 60 : 70)
    }

    mutating func dismiss(at time: TimeInterval) { showing = false; deadline = time+70 }
    mutating func show(at time: TimeInterval) { showing = true; deadline = time+60 }
    func delay(at time: TimeInterval) -> TimeInterval { max(0,(deadline ?? time)-time) }
}

private enum Blocks {
    static let grass = Color(red:0.48,green:0.78,blue:0.22)
    static let play = Color(red:0.12,green:0.47,blue:0.03)
    static let stone = Color(red:0.20,green:0.21,blue:0.19)
    static let gold = Color(red:1,green:0.83,blue:0.37)

    static func type(_ size: CGFloat) -> Font { .custom("Monocraft",size:size,relativeTo:.body) }
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

private struct BlockButton: ButtonStyle {
    var selected = false
    var texture: NSImage?
    var scale: CGFloat = 1
    @Environment(\.accessibilityReduceMotion) private var reduced
    @Environment(\.isFocused) private var focused
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        Hover { hovered in
            configuration.label
                .foregroundStyle(.white)
                .background {
                    (hovered ? Blocks.play : Blocks.stone)
                        .shadow(color:.black.opacity(0.4),radius:0,x:0,y:configuration.isPressed ? 0 : 3*scale)
                    if let texture {
                        Image(nsImage:texture).resizable(resizingMode:.tile).interpolation(.none).opacity(0.28)
                    }
                }
                .overlay(alignment:.top) { Rectangle().fill(.white.opacity(0.25)).frame(height:2*scale) }
                .overlay(alignment:.bottom) { Rectangle().fill(.black.opacity(0.45)).frame(height:4*scale) }
                .overlay { Rectangle().strokeBorder(selected ? Blocks.gold : .black.opacity(0.7),lineWidth:2*scale) }
                .overlay { Rectangle().strokeBorder(Blocks.gold,lineWidth:2).padding(-4).opacity(focused ? 1 : 0) }
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
    let exploring: Bool
    let travel: (Int) -> Void
    let finish: () -> Void
    @ObservedObject var launcher: Launcher

    var body: some View {
        ZStack {
            if let poster = launcher.poster { Image(nsImage:poster).resizable().scaledToFill() }
            #if LAUNCHER_TEST
            if let image = launcher.previewImage { Image(nsImage:image).resizable().scaledToFill() }
            else { world }
            #else
            world
            #endif
            VStack(spacing:0) {
                LinearGradient(colors:[.black.opacity(0.45),.clear],startPoint:.top,endPoint:.bottom).frame(height:130)
                Spacer()
                LinearGradient(colors:[.clear,.black.opacity(0.65)],startPoint:.top,endPoint:.bottom).frame(height:250)
            }.allowsHitTesting(false)
        }.accessibilityHidden(true)
    }

    @ViewBuilder private var world: some View {
        if let assets = launcher.assets, !launcher.sceneryFailed {
            Adventure(world:journey.world,biome:journey.biome,moving:moving,passage:journey.passage,assets:assets,exploring:exploring,
                travel:travel,arrived:{ launcher.journey.area($0) },finish:finish) { launcher.sceneryFailed = true }
        }
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
                            Text(status.detail).font(.system(size:14*scale))
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
        min(size.width*0.7,size.height*1.25)
    }

    private var splashText: some View {
        Text(splash).font(Blocks.type(width*0.033)).foregroundStyle(.yellow)
            .multilineTextAlignment(.center).lineLimit(1).minimumScaleFactor(0.3)
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
    @Environment(\.accessibilityReduceMotion) private var reduced
    @State private var offset: CGFloat = 0
    private var width: CGFloat { (text as NSString).size(withAttributes:[.font:NSFont(name:"Monocraft",size:18) ?? .monospacedSystemFont(ofSize:18,weight:.regular)]).width }

    var body: some View {
        Group {
            if reduced { Text(text).lineLimit(3).fixedSize(horizontal:false,vertical:true) }
            else {
                HStack(spacing:32) {
                    Text(text).fixedSize()
                    if width > 164 { Text(text).fixedSize() }
                }.offset(x:offset).frame(width:164,alignment:.leading).clipped()
                    .task(id:active ? text : "") {
                        var transaction = Transaction(); transaction.disablesAnimations = true
                        withTransaction(transaction) { offset = 0 }
                        guard active, width > 164 else { return }
                        do { try await Task.sleep(for:.seconds(2)) } catch { return }
                        withAnimation(.linear(duration:Double(width+32)/28).repeatForever(autoreverses:false)) { offset = -width-32 }
                    }
            }
        }.font(Blocks.action(18)).accessibilityLabel(text)
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
    @State private var visible = true
    @State private var lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
    @State private var exploring = false
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
    private var available: Bool { launcher.assets != nil && !launcher.sceneryFailed }
    private var moving: Bool {
        available && !launcher.loading && SceneryMotion.enabled(reduced:reduceMotion,paused:!animateScenery || launcher.settings,lowPower:lowPower,
            active:scenePhase == .active,visible:visible,playing:launcher.status.state == "playing")
    }
    private var hintActive: Bool {
        hintAvailable && visible && (hint.showing || focused && scenePhase == .active)
    }
    private var hintAvailable: Bool {
        available && !launcher.settings && launcher.journey.passage == nil && !launcher.running && launcher.status.state != "error"
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
        return max(1,min(CGFloat(5).squareRoot(),(size.width-80)/364,(size.height-title*0.25-reserved-extra)/154))
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
                    Scenery(journey:launcher.journey,moving:moving,exploring:exploring,
                        travel:{ launcher.journey.travel($0) },finish:{ explore(false) },launcher:launcher)
                        .frame(width:geometry.size.width,height:geometry.size.height).clipped().ignoresSafeArea().allowsHitTesting(exploring)
                    if exploring {
                        ZStack {
                            Rectangle().frame(width:13,height:1)
                            Rectangle().frame(width:1,height:13)
                        }.foregroundStyle(.white.opacity(0.7)).shadow(color:.black,radius:1)
                            .allowsHitTesting(false).accessibilityHidden(true)
                    }
                    VStack(spacing:0) {
                        header(in:geometry.size).padding(.horizontal,28).padding(.top,28)
                        if hintAvailable && hint.showing && !map && !sideHint {
                            HStack { Spacer(); achievement }.padding(.trailing,28).padding(.top,16)
                                .transition(reduceMotion ? .identity : .move(edge:.trailing).combined(with:.opacity))
                        }
                        Spacer(minLength:16)
                        VStack(spacing:22) {
                            if !exploring { installation(scale:scale) }
                            hotbar(scale:scale)
                        }.frame(maxWidth:640*scale).padding(.horizontal,28).padding(.bottom,footer)
                    }
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            look(scale:scale).padding(.trailing,24).padding(.bottom,footer)
                        }
                    }
                    VStack {
                        Spacer()
                        HStack {
                            Hover(anchor:.leading) { _ in Link("@Keys-i",destination:URL(string:"https://keysi.dev")!)
                                .buttonStyle(.plain).tint(.white)
                                .accessibilityLabel("Developer Keys-i, open keysi.dev")
                            }
                            Spacer()
                            Hover(anchor:.trailing) { _ in Text("v" + (Bundle.main.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String ?? "0.16.0")) }
                        }.font(Blocks.type(13*scale)).foregroundStyle(.white)
                            .shadow(color:.black.opacity(0.6),radius:0,x:1,y:1)
                            .padding(.horizontal,24).padding(.bottom,16)
                    }
                    if hintAvailable && hint.showing && !map && sideHint {
                        VStack {
                            HStack { Spacer(); achievement }
                            Spacer()
                        }.padding(.trailing,28).padding(.top,104)
                            .transition(reduceMotion ? .identity : .move(edge:.trailing).combined(with:.opacity))
                    }
                }
                }
            }.animation(reduceMotion ? nil : .easeOut(duration:0.18),value:launcher.loading)
        }
        .disabled(map || launcher.settings).accessibilityHidden(map || launcher.settings)
        .overlay {
            if map || launcher.settings {
                GeometryReader { geometry in
                    ZStack {
                        Color.black.opacity(0.65).onTapGesture { map = false; launcher.settings = false }
                        if launcher.settings {
                            Preferences(launcher:launcher,close:{ launcher.settings = false })
                                .frame(width:min(1040,geometry.size.width-48),height:min(800,geometry.size.height-48))
                        } else {
                            Biomes(world:launcher.journey.world,selected:launcher.journey.biome,
                                frames:launcher.frames,stone:launcher.stone,
                                choose:{ launcher.journey.area($0); map = false },close:{ map = false })
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
            if let window = NSApp?.keyWindow { focused = window.title == launcherName }
        }
        .task(id:musicActive) { music.update(assets:launcher.assets,active:musicActive,volume:musicVolume) }
        .onChange(of:musicVolume) { music.update(assets:launcher.assets,active:musicActive,volume:musicVolume) }
        .onDisappear { music.stop() }
        .sheet(isPresented:$launcher.help) { Help(launcher:launcher) }
        .onReceive(NotificationCenter.default.publisher(for:NSWindow.didBecomeKeyNotification)) { notification in
            focused = (notification.object as? NSWindow)?.title == launcherName
        }
        .onReceive(NotificationCenter.default.publisher(for:NSWindow.didResignKeyNotification)) { notification in
            if (notification.object as? NSWindow)?.title == launcherName { focused = false }
        }
        .task(id:[hintActive,exploring]) {
            guard hintActive else { return }
            hint.focus(at:ProcessInfo.processInfo.systemUptime)
            while !Task.isCancelled {
                do { try await Task.sleep(for:.seconds(hint.delay(at:ProcessInfo.processInfo.systemUptime))) } catch { return }
                guard !Task.isCancelled else { return }
                hint.advance(at:ProcessInfo.processInfo.systemUptime)
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration:0.18),value:hint.showing)
        .onExitCommand { if launcher.settings { launcher.settings = false } else if map { map = false } else if exploring { explore(false) } else if launcher.canCancel { launcher.cancel() } }
        .onReceive(NotificationCenter.default.publisher(for:.NSProcessInfoPowerStateDidChange)) { _ in lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled }
        .onReceive(NotificationCenter.default.publisher(for:NSWindow.didChangeOcclusionStateNotification)) { _ in
            visible = NSApp.windows.contains { $0.title == launcherName && $0.occlusionState.contains(.visible) }
        }
        .onChange(of:launcher.settings) {
            if launcher.settings { map = false; explore(false) }
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
                launcher.journey.tick(rotate:rotateScenery)
            }
        }
    }

    private func header(in size: CGSize) -> some View {
        VStack(spacing:18) {
            HStack(alignment:.top,spacing:8) {
                location.frame(width:190,alignment:.leading).opacity(available ? 1 : 0).accessibilityHidden(!available)
                Spacer()
                Button { launcher.showHelp() } label: { Text("?").font(Blocks.type(24)).frame(width:44,height:44) }
                    .help("Help").accessibilityLabel("Help")
                Button { launcher.showSettings() } label: { glyph("icon_setting",fallback:"gearshape.fill").frame(width:44,height:44) }
                    .help("Settings").accessibilityLabel("Settings")
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

    private var location: some View {
        VStack(alignment:.leading,spacing:8) {
            if let passage = launcher.journey.passage {
                Text(passage == .mine ? "Mineshaft" : passage == .stronghold ? "Stronghold" : "Rift valley")
                    .font(Blocks.action(18)).accessibilityAddTraits(.isHeader)
                Button { launcher.journey.skip() } label: {
                    Text("Skip journey").font(Blocks.action(13)).padding(.horizontal,12).frame(height:44)
                }.buttonStyle(BlockButton(texture:launcher.stone))
            } else {
                Button { map = true } label: {
                    HStack(spacing:8) {
                        Marquee(text:launcher.journey.title,active:moving && focused && !map)
                        Image(systemName:"chevron.down").font(.system(size:10,weight:.bold))
                    }.frame(minHeight:44)
                        .shadow(color:.black.opacity(0.25),radius:2,y:1)
                }.buttonStyle(.plain).focused($areaFocused)
                    .overlay { Rectangle().strokeBorder(Blocks.gold,lineWidth:2).padding(-4).opacity(areaFocused ? 1 : 0) }
                    .accessibilityLabel("Choose biome: " + launcher.journey.title)
                    .help(launcher.journey.world == .sift ? "Sift interpretation · Choose biome" : "Choose biome or landmark")
                    .disabled(!available)
            }
        }
    }

    private func hotbar(scale: CGFloat) -> some View {
        HStack(spacing:0) {
            ForEach(launcher.worlds.indices,id:\.self) { index in
                let world = launcher.worlds[index]
                Button { launcher.journey.select(world,animated:moving && !exploring) } label: {
                    Slot(world:world,image:launcher.items[world],scale:scale)
                }
                .buttonStyle(InventoryButton(selected:launcher.selection == index,
                    slot:launcher.frames["hotbar_0"],selection:launcher.frames["selected_hotbar_slot"],scale:scale))
                .keyboardShortcut(KeyEquivalent(Character(String(index+1))),modifiers:[])
                .disabled(!available)
                .accessibilityLabel("\(world.title) scenery")
                .accessibilityAddTraits(launcher.selection == index ? .isSelected : [])
                .help(world == .sift ? "Sift interpretation · 4" : "\(world.title) · \(index+1)")
            }
        }.padding(6*scale)
            .accessibilityElement(children:.contain).accessibilityLabel("Realm hotbar")
    }

    private func look(scale: CGFloat) -> some View {
        Button { explore(!exploring) } label: {
            glyph("spyglass",fallback:exploring ? "eye.fill" : "eye",size:32.4*scale).frame(width:56*scale,height:56*scale)
        }.buttonStyle(BlockButton(selected:exploring,texture:launcher.stone,scale:scale))
            .disabled(!available || launcher.journey.passage != nil || launcher.status.state == "playing")
            .keyboardShortcut("l",modifiers:.command)
            .accessibilityLabel(exploring ? "Leave spectator view" : "Look around")
            .accessibilityHint("WASD flies, mouse movement turns the view, Space and Shift change height, Control sprints, Escape returns")
            .help(exploring ? "WASD fly · Mouse look · Space/Shift height · Control sprint · Scroll speed · Escape returns" : "Look around (⌘L) · Spectator flight")
    }

    private func explore(_ enabled: Bool) {
        if enabled { hint.show(at:ProcessInfo.processInfo.systemUptime) }
        else { hint.dismiss(at:ProcessInfo.processInfo.systemUptime) }
        exploring = enabled
    }

    private var achievement: some View {
        HStack(spacing:12) {
            glyph("spyglass",fallback:"eye").frame(width:40,height:40).foregroundStyle(Blocks.gold)
            if exploring {
                VStack(alignment:.leading,spacing:5) {
                    Text("Spectator mode").font(Blocks.type(13)).foregroundStyle(Blocks.gold)
                    Text("WASD fly · Mouse to look").font(Blocks.type(11))
                    Text("Space/Shift · Esc to return").font(Blocks.type(10))
                }
            } else {
                VStack(alignment:.leading,spacing:5) {
                    Text("Advancement made!").font(Blocks.type(12)).foregroundStyle(Blocks.gold)
                    Text("\(Text("⌘ + L").font(.system(size:13,weight:.semibold))) to look around")
                        .font(Blocks.type(12)).lineLimit(1)
                }
            }
        }.padding(.horizontal,14).frame(height:exploring ? 88 : 64)
            .background {
                Rectangle().fill(Color(white:0.12))
                    .shadow(color:.black.opacity(0.3),radius:2,y:3)
            }
            .overlay { Rectangle().strokeBorder(Color(white:0.5),lineWidth:2) }
            .overlay { Rectangle().strokeBorder(.black.opacity(0.75),lineWidth:1).padding(3) }
            .accessibilityElement(children:.combine)
            .accessibilityLabel(exploring ? "Spectator mode: WASD flies, mouse movement turns the view, Space and Shift change height, Control sprints, Escape returns" : "Press Command L to look around")
            .allowsHitTesting(false)
    }

    @ViewBuilder private func installation(scale: CGFloat) -> some View {
        if !launcher.running && ["ready","new","cancelled"].contains(launcher.status.state) {
            VStack(spacing:12) {
                playButton(width:320,scale:scale)
                if !detail.isEmpty {
                    Text(detail).font(.system(size:13,weight:.medium)).multilineTextAlignment(.center)
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
        }.buttonStyle(BlockButton(scale:scale)).keyboardShortcut(.defaultAction)
    }

    private var setupSteps: some View {
        HStack(spacing:16) {
            ForEach(0..<4,id:\.self) { index in
                HStack(spacing:6) {
                    Image(systemName:launcher.status.stage.map { index < $0 } == true ? "checkmark" : ["person.fill","arrow.down","hammer.fill","play.fill"][index])
                        .foregroundStyle(launcher.status.stage == index ? Blocks.gold : Blocks.grass)
                    Text(["Sign in","Download","Prepare","Play"][index])
                }.font(.system(size:11,weight:.medium))
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
                                Text(detail).font(.system(size:13)).foregroundStyle(.white.opacity(0.83))
                                    .frame(maxWidth:.infinity,alignment:.leading).textSelection(.enabled)
                            }.frame(height:80)
                        } else {
                            Text(detail).font(.system(size:13)).foregroundStyle(.white.opacity(0.83))
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
                }.font(.system(size:12,weight:.medium)).foregroundStyle(.white.opacity(0.85))
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
    @State private var search = ""
    @FocusState private var searching: Bool
    @FocusState private var focused: Int?

    private var matches: [Int] {
        let query = search.trimmingCharacters(in:.whitespacesAndNewlines)
        return world.biomes.indices.filter { query.isEmpty || world.biomes[$0].rawValue.localizedCaseInsensitiveContains(query) }
    }

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
                    .onSubmit { if let first = matches.first { choose(first) } }
                    .onKeyPress(.downArrow) { focused = matches.first; return .handled }
                if !search.isEmpty {
                    Button { search = ""; searching = true } label: { Image(systemName:"xmark").frame(width:28,height:28) }
                        .buttonStyle(.plain).accessibilityLabel("Clear search")
                }
            }.padding(12).background(.black.opacity(0.7))
                .overlay { Rectangle().strokeBorder(searching ? Blocks.gold : .white.opacity(0.35),lineWidth:2) }
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
                                    if selected == index { Image(systemName:"checkmark").foregroundStyle(Blocks.gold) }
                                }.padding(.horizontal,14).frame(minHeight:58)
                            }.buttonStyle(BlockButton(selected:selected == index,texture:stone))
                                .focusable().focused($focused,equals:index).id(index)
                                .accessibilityAddTraits(selected == index ? .isSelected : [])
                                .onKeyPress(.return) { choose(index); return .handled }
                                .onKeyPress(.space) { choose(index); return .handled }
                                .onKeyPress(.downArrow) { move(from:index,by:1); return .handled }
                                .onKeyPress(.upArrow) { move(from:index,by:-1); return .handled }
                        }
                        if matches.isEmpty {
                            Text("No matching biomes").font(Blocks.type(15)).padding(.vertical,32)
                        }
                    }.padding(12)
                }.background(.black.opacity(0.45))
                    .overlay { Rectangle().strokeBorder(.black,lineWidth:2) }
                    .onChange(of:focused) { if let focused { scroll.scrollTo(focused) } }
                    .onAppear { scroll.scrollTo(selected,anchor:.center) }
            }.padding(.horizontal,20)
            HStack {
                Text("\(matches.count) \(matches.count == 1 ? "destination" : "destinations")").font(Blocks.type(11))
                Spacer()
                if world == .sift { Text("Sift interpretation").font(Blocks.type(11)) }
            }.foregroundStyle(.white.opacity(0.8)).padding(20)
        }.foregroundStyle(.white).background(Blocks.stone)
            .overlay { Rectangle().strokeBorder(.black,lineWidth:3) }
            .overlay { Rectangle().strokeBorder(.white.opacity(0.3),lineWidth:2).padding(3) }
            .environment(\.colorScheme,.dark)
            .task { searching = true }
            .onExitCommand(perform:close)
    }

    private func move(from index: Int, by step: Int) {
        guard let position = matches.firstIndex(of:index) else { return }
        let next = position+step
        if matches.indices.contains(next) { focused = matches[next] }
        else if next<0 { searching = true }
    }
}

struct Preferences: View {
    @ObservedObject var launcher: Launcher
    let close: () -> Void
    @AppStorage("animateScenery") private var animateScenery = true
    @AppStorage("rotateScenery") private var rotateScenery = true
    @AppStorage("musicEnabled") private var musicEnabled = true
    @AppStorage("musicVolume") private var musicVolume = 0.18
    @Environment(\.accessibilityReduceMotion) private var reduced
    @FocusState private var volumeFocused: Bool

    static func scale(in size: CGSize) -> CGFloat {
        min(1.5,max(1,min(size.width/700,size.height/560)))
    }

    var body: some View {
        GeometryReader { geometry in
            let scale = Self.scale(in:geometry.size)
            VStack(spacing:0) {
                HStack {
                    Text("Settings").font(Blocks.type(32*scale)).accessibilityAddTraits(.isHeader)
                    Spacer()
                    Button(action:close) { Image(systemName:"xmark").font(.system(size:22*scale,weight:.bold)).frame(width:48*scale,height:48*scale) }
                        .buttonStyle(BlockButton(texture:launcher.stone)).accessibilityLabel("Close settings")
                        .keyboardShortcut(.cancelAction)
                }.padding(24*scale)
                ScrollView {
                    VStack(spacing:24*scale) {
                        VStack(spacing:14*scale) {
                            Toggle(isOn:$animateScenery) {
                                Text("Background animation: \(animateScenery ? "ON" : "OFF")")
                                    .frame(maxWidth:.infinity,minHeight:60*scale)
                            }
                            Toggle(isOn:$rotateScenery) {
                                Text("Travel between biomes: \(rotateScenery ? "ON" : "OFF")")
                                    .frame(maxWidth:.infinity,minHeight:60*scale)
                            }.disabled(!animateScenery)
                        }.toggleStyle(.button).buttonStyle(BlockButton(texture:launcher.stone))
                            .controlSize(.large).font(Blocks.type(20*scale))
                        VStack(spacing:14*scale) {
                            Text("Master volume: \(musicEnabled ? Int(musicVolume*100) : 0)%").font(Blocks.type(22*scale))
                            GeometryReader { geometry in
                                let thumb = 32*scale, travel = max(1,geometry.size.width-thumb)
                                ZStack(alignment:.leading) {
                                    Rectangle().fill(.black.opacity(0.75))
                                    Rectangle().fill(Blocks.grass.opacity(0.65)).frame(width:thumb+travel*(musicEnabled ? musicVolume : 0))
                                    Rectangle().fill(Color(white:0.65)).frame(width:thumb)
                                        .overlay { Rectangle().strokeBorder(.black,lineWidth:2) }
                                        .overlay(alignment:.top) { Rectangle().fill(.white.opacity(0.5)).frame(height:2) }
                                        .offset(x:travel*(musicEnabled ? musicVolume : 0))
                                }.overlay { Rectangle().strokeBorder(volumeFocused ? Blocks.gold : .black,lineWidth:2) }
                                    .contentShape(Rectangle())
                                    .gesture(DragGesture(minimumDistance:0).onChanged { value in
                                        musicVolume = min(1,max(0,(value.location.x-thumb/2)/travel)); musicEnabled = musicVolume>0
                                    })
                            }.frame(height:48*scale).focusable().focused($volumeFocused)
                                .accessibilityElement().accessibilityLabel("Master volume")
                                .accessibilityValue("\(musicEnabled ? Int(musicVolume*100) : 0) percent")
                                .accessibilityAdjustableAction { direction in
                                    musicVolume = min(1,max(0,(musicEnabled ? musicVolume : 0)+(direction == .increment ? 0.05 : -0.05))); musicEnabled = musicVolume>0
                                }
                                .onKeyPress(.leftArrow) { musicVolume = max(0,(musicEnabled ? musicVolume : 0)-0.05); musicEnabled = musicVolume>0; return .handled }
                                .onKeyPress(.rightArrow) { musicVolume = min(1,(musicEnabled ? musicVolume : 0)+0.05); musicEnabled = musicVolume>0; return .handled }
                            Text("Minecraft menu and game music from your installation")
                        }
                        Text(reduced ? "macOS Reduced Motion is on" : "Scenery rests in Low Power Mode, while hidden and while Minecraft runs")
                        Text("Game graphics, sound and controls are in Minecraft’s Settings")
                    }.font(.system(size:16*scale)).foregroundStyle(.white.opacity(0.85))
                        .multilineTextAlignment(.center).fixedSize(horizontal:false,vertical:true)
                        .padding(.horizontal,24*scale).padding(.bottom,24*scale)
                }
            }.foregroundStyle(.white)
                .background {
                    Blocks.stone
                    if let stone = launcher.stone { Image(nsImage:stone).resizable(resizingMode:.tile).interpolation(.none).opacity(0.12) }
                }
                .overlay { Rectangle().strokeBorder(.black,lineWidth:3) }
                .overlay { Rectangle().strokeBorder(.white.opacity(0.3),lineWidth:2).padding(3) }
        }.environment(\.colorScheme,.dark).onExitCommand(perform:close)
    }
}

struct Help: View {
    @ObservedObject var launcher: Launcher
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing:20) {
            Text("How to play").font(Blocks.type(26)).accessibilityAddTraits(.isHeader)
            ScrollView {
                VStack(alignment:.leading,spacing:20) {
                    guide("Start your game", "Choose Install & play, then sign in with the Microsoft account that owns Minecraft for Windows. Your worlds and account stay on this Mac")
                    guide("Look around · ⌘L", "WASD moves · Mouse looks · Space rises · Shift descends · Control sprints · Scroll changes speed · Escape returns")
                    guide("Explore another biome", "Choose the biome name at the top left, or fly towards the edge of an area. The inventory slots choose a realm. Brackets visit neighbouring biomes")
                    guide("Music and motion", "Open Settings to change master volume, background animation and automatic travel. macOS Reduced Motion and Low Power Mode also pause the scenery")
                    guide("Having trouble?", "Use Open setup logs below to inspect a launch failure. Save and quit Minecraft normally before replacing an app or runtime")
                }.padding(.vertical,4)
            }.frame(maxHeight:360)
            HStack(spacing:12) {
                Button { launcher.showLog() } label: { Text("Open setup logs").frame(maxWidth:.infinity,minHeight:44) }
                Button { dismiss() } label: { Text("Done").frame(maxWidth:.infinity,minHeight:44) }.keyboardShortcut(.defaultAction)
            }.font(Blocks.type(14)).buttonStyle(BlockButton(texture:launcher.stone))
        }.padding(28).frame(width:600).foregroundStyle(.white).background(Blocks.stone).environment(\.colorScheme,.dark)
    }

    private func guide(_ title: String, _ text: String) -> some View {
        VStack(alignment:.leading,spacing:8) {
            Text(title).font(Blocks.type(15)).foregroundStyle(Blocks.gold).accessibilityAddTraits(.isHeader)
            Text(text).font(.system(size:14)).lineSpacing(4).fixedSize(horizontal:false,vertical:true)
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
            Button("Skip Portal Journey") { launcher.journey.skip() }
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
