import AppKit
import SwiftUI
import CoreText

struct Status: Decodable {
    let state: String
    let title: String
    let detail: String
    let progress: Double?

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
    @Published var status = Status(state: "checking", title: "Minecraft on your Mac", detail: "Checking installation…", progress: nil)
    @Published var running = false
    @Published var checkingUpdates = false
    @Published var journey = Journey()
    @Published var assets: Assets?
    @Published var sceneryFailed = false
    @Published var items: [World:NSImage] = [:]
    @Published var frames: [String:NSImage] = [:]
    @Published var stone: NSImage?
    @Published var gameFont: CTFont?
    @Published var splash = ""
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
        running = true
        buffer = Data()
        let task = Process()
        let pipe = Pipe()
        let resources = Bundle.main.resourceURL!
        let worker = resources.appendingPathComponent("worker/BedrockWorker")
        let packaged = FileManager.default.isExecutableFile(atPath: worker.path)
        task.executableURL = packaged ? worker : URL(fileURLWithPath: "/usr/bin/python3")
        task.arguments = (packaged ? [] : [root.appendingPathComponent("src/launcher/setup.py").path]) + (check ? ["--status"] : signOut ? ["--sign-out"] : [])
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

    var canCancel: Bool { running && status.state == "busy" }

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
        NSWorkspace.shared.open(URL(string: "https://github.com/keys-i/minecraft-mac/blob/main/docs/play.md")!)
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
        guard launcher?.running == true else { return .terminateNow }
        let alert = NSAlert()
        if launcher?.canCancel == true {
            alert.messageText = "Stop setup?"
            alert.informativeText = "You can continue later. Your game and saves will be kept."
            alert.addButton(withTitle: "Keep Going")
            alert.addButton(withTitle: "Stop Setup")
            if alert.runModal() == .alertSecondButtonReturn { launcher?.cancel() }
        } else {
            let playing = launcher?.status.state == "playing"
            alert.messageText = playing ? "Minecraft is still running" : "The launcher is finishing up"
            alert.informativeText = playing
                ? "Quit Minecraft first to finish your session safely. You can close the launcher window while you play."
                : "Keep the app open until the current step finishes. Your existing game and saves will be kept."
            alert.addButton(withTitle: "Keep Open")
            alert.runModal()
        }
        return .terminateCancel
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if !hasVisibleWindows { sender.windows.first(where: { $0.canBecomeMain })?.makeKeyAndOrderFront(nil) }
        return true
    }
}

enum SceneryMotion {
    static let interval = 1.0 / 20

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
    static let ink = Color(red:0.055,green:0.12,blue:0.025)
    static let stone = Color(red:0.20,green:0.21,blue:0.19)
    static let gold = Color(red:1,green:0.83,blue:0.37)

    static func type(_ size: CGFloat) -> Font { .custom("Monocraft",size:size,relativeTo:.body) }
    static func action(_ size: CGFloat) -> Font { .system(size:size,weight:.semibold,design:.rounded) }
}

private struct BlockButton: ButtonStyle {
    var colour: Color = Blocks.stone
    var selected = false
    var texture: NSImage?
    @Environment(\.accessibilityReduceMotion) private var reduced
    @Environment(\.isFocused) private var focused
    @Environment(\.isEnabled) private var enabled
    @State private var hovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(colour == Blocks.grass ? Blocks.ink : .white)
            .background {
                colour.brightness(hovered ? 0.08 : 0)
                    .shadow(color:.black.opacity(0.4),radius:0,x:0,y:configuration.isPressed ? 0 : 3)
                if let texture, colour != Blocks.grass {
                    Image(nsImage:texture).resizable(resizingMode:.tile).interpolation(.none).opacity(0.28)
                }
            }
            .overlay(alignment:.top) { Rectangle().fill(.white.opacity(0.25)).frame(height:2) }
            .overlay(alignment:.bottom) { Rectangle().fill(.black.opacity(0.45)).frame(height:4) }
            .overlay { Rectangle().strokeBorder(selected ? Blocks.gold : .black.opacity(0.7),lineWidth:2) }
            .overlay { Rectangle().strokeBorder(Blocks.gold,lineWidth:2).padding(-4).opacity(focused ? 1 : 0) }
            .offset(y:configuration.isPressed && !reduced ? 2 : 0)
            .opacity(enabled ? 1 : 0.45)
            .contentShape(Rectangle())
            .onHover { hovered = $0 }
            .animation(reduced ? nil : .easeOut(duration:0.08),value:configuration.isPressed)
    }
}

private struct InventoryButton: ButtonStyle {
    let selected: Bool
    let slot: NSImage?
    let selection: NSImage?
    @Environment(\.isFocused) private var focused
    @Environment(\.isEnabled) private var enabled
    @State private var hovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label.frame(width:60,height:60)
            .background {
                if let slot { Image(nsImage:slot).resizable().interpolation(.none) }
                else { Rectangle().fill(.black.opacity(0.65)).overlay { Rectangle().strokeBorder(.gray,lineWidth:3) } }
            }
            .overlay {
                if selected {
                    if let selection { Image(nsImage:selection).resizable().interpolation(.none).frame(width:72,height:72) }
                    else { Rectangle().strokeBorder(.white,lineWidth:3).padding(-4) }
                }
            }
            .overlay { Rectangle().strokeBorder(Blocks.gold,lineWidth:2).padding(-6).opacity(focused ? 1 : 0) }
            .brightness(configuration.isPressed ? -0.15 : hovered ? 0.12 : 0)
            .opacity(enabled ? 1 : 0.45).contentShape(Rectangle())
            .onHover { hovered = $0 }
    }
}

private struct Slot: View {
    let world: World
    let image: NSImage?
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
        }.frame(width:48,height:48).accessibilityHidden(true)
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
                travel:travel,finish:finish) { launcher.sceneryFailed = true }
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

private struct GameTitle: View {
    let image: NSImage?
    let font: CTFont?
    let splash: String
    let width: CGFloat
    let moving: Bool

    private var splashText: some View {
        Text(splash).font(Blocks.type(width*0.033)).foregroundStyle(.yellow)
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
            Text("MAC EDITION").font(font.map { Font(CTFontCreateCopyWithAttributes($0,width*0.042,nil,nil)) } ?? Blocks.type(width*0.042))
                .foregroundStyle(.white).shadow(color:.black.opacity(0.85),radius:0,x:1,y:2)
                .padding(.horizontal,20).padding(.vertical,3)
                .background(Color(red:0.22,green:0.21,blue:0.20))
                .overlay(alignment:.top) { Rectangle().fill(.white.opacity(0.18)).frame(height:2) }
                .overlay(alignment:.bottom) { Rectangle().fill(.black.opacity(0.65)).frame(height:3) }
                .overlay { Rectangle().strokeBorder(.black.opacity(0.85),lineWidth:2) }
        }.frame(width:width)
            .overlay(alignment:.bottomTrailing) {
                if !splash.isEmpty {
                    Group {
                        if moving {
                            splashText.phaseAnimator([false,true]) { content,small in
                                content.scaleEffect(small ? 0.94 : 1)
                            } animation: { _ in .easeInOut(duration:0.45) }
                        } else { splashText }
                    }.rotationEffect(.degrees(-20)).offset(x:width*0.19,y:2)
                        .accessibilityHidden(true).allowsHitTesting(false)
                }
            }
            .accessibilityElement(children:.ignore).accessibilityLabel("Minecraft, Mac Edition")
            .accessibilityAddTraits(.isHeader)
    }
}

struct LauncherView: View {
    @ObservedObject var launcher: Launcher
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openSettings) private var openSettings
    @AppStorage("animateScenery") private var animateScenery = true
    @AppStorage("rotateScenery") private var rotateScenery = true
    @AppStorage("musicEnabled") private var musicEnabled = true
    @AppStorage("musicVolume") private var musicVolume = 0.18
    @StateObject private var music = Music()
    @State private var visible = true
    @State private var lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
    @State private var exploring = false
    @State private var map = false
    @State private var search = ""
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
        available && SceneryMotion.enabled(reduced:reduceMotion,paused:!animateScenery,lowPower:lowPower,
            active:scenePhase == .active,visible:visible,playing:launcher.status.state == "playing")
    }
    private var hintActive: Bool {
        hintAvailable && visible && (hint.showing || focused && scenePhase == .active)
    }
    private var hintAvailable: Bool {
        available && launcher.journey.passage == nil && !launcher.running && launcher.status.state != "error"
    }
    private var musicActive: Bool {
        available && Music.enabled(muted:!musicEnabled,active:focused && scenePhase == .active,
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

    var body: some View {
        GeometryReader { geometry in
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
                    header(width:geometry.size.width).padding(.horizontal,28).padding(.top,28)
                    Spacer(minLength:40)
                    VStack(spacing:22) {
                        if !exploring { installation }
                        hotbar
                    }.frame(maxWidth:640).padding(.horizontal,28).padding(.bottom,24)
                }
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        look.padding(24)
                    }
                }
                if hintAvailable && hint.showing {
                    VStack {
                        HStack { Spacer(); achievement }
                        Spacer()
                    }.padding(.trailing,28).padding(.top,exploring ? 96 : min(322,geometry.size.width*0.22+94))
                        .transition(.opacity)
                }
            }
        }
        .foregroundStyle(.white).environment(\.colorScheme,.dark)
        .frame(minWidth:760,minHeight:620)
        .onAppear {
            if let window = NSApp?.keyWindow { focused = window.title == "Minecraft for MacOS" }
        }
        .task(id:musicActive) { music.update(assets:launcher.assets,active:musicActive,volume:musicVolume) }
        .onChange(of:musicVolume) { music.update(assets:launcher.assets,active:musicActive,volume:musicVolume) }
        .onDisappear { music.stop() }
        .onReceive(NotificationCenter.default.publisher(for:NSWindow.didBecomeKeyNotification)) { notification in
            focused = (notification.object as? NSWindow)?.title == "Minecraft for MacOS"
        }
        .onReceive(NotificationCenter.default.publisher(for:NSWindow.didResignKeyNotification)) { notification in
            if (notification.object as? NSWindow)?.title == "Minecraft for MacOS" { focused = false }
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
        .onExitCommand { if map { map = false } else if exploring { explore(false) } else if launcher.canCancel { launcher.cancel() } }
        .onReceive(NotificationCenter.default.publisher(for:.NSProcessInfoPowerStateDidChange)) { _ in lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled }
        .onReceive(NotificationCenter.default.publisher(for:NSWindow.didChangeOcclusionStateNotification)) { _ in
            visible = NSApp.windows.contains { $0.title == "Minecraft for MacOS" && $0.occlusionState.contains(.visible) }
        }
        .onChange(of:reduceMotion) { if reduceMotion { launcher.journey.skip() } }
        .onChange(of:lowPower) { if lowPower { launcher.journey.skip() } }
        .onChange(of:available) { if !available { explore(false) } }
        .onChange(of:launcher.journey.world) { if launcher.journey.passage != nil { explore(false) } }
        .onChange(of:launcher.status.state) { if launcher.status.state == "playing" { explore(false) } }
        .task(id:moving && !exploring && (rotateScenery || launcher.journey.passage != nil)) {
            guard moving, !exploring, rotateScenery || launcher.journey.passage != nil else { return }
            while !Task.isCancelled {
                do { try await Task.sleep(for:.seconds(1)) } catch { return }
                guard !Task.isCancelled else { return }
                launcher.journey.tick(rotate:rotateScenery)
            }
        }
    }

    private func header(width: CGFloat) -> some View {
        VStack(spacing:18) {
            HStack(alignment:.top,spacing:8) {
                location.frame(width:190,alignment:.leading).opacity(available ? 1 : 0).accessibilityHidden(!available)
                Spacer()
                Button { musicEnabled.toggle() } label: {
                    Image(systemName:musicEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill").frame(width:44,height:44)
                }.help(musicEnabled ? "Mute music · \(music.title)" : "Play Minecraft music")
                    .accessibilityLabel(musicEnabled ? "Mute music" : "Play Minecraft music")
                    .disabled(!available)
                Button { launcher.showHelp() } label: { Image(systemName:"questionmark").frame(width:44,height:44) }
                    .help("Help").accessibilityLabel("Help")
                Button { openSettings() } label: { Image(systemName:"gearshape.fill").frame(width:44,height:44) }
                    .help("Settings").accessibilityLabel("Settings")
                Button { animateScenery.toggle() } label: { Image(systemName:animateScenery ? "pause.fill" : "play.fill").frame(width:44,height:44) }
                    .accessibilityLabel(animateScenery ? "Pause scenery" : "Resume scenery")
                    .help(reduceMotion ? "Reduced Motion is enabled" : lowPower ? "Scenery pauses in Low Power Mode" : "Pause or resume the adventure")
                    .disabled(reduceMotion || lowPower)
            }.buttonStyle(BlockButton(texture:launcher.stone))
            if !exploring {
                GameTitle(image:launcher.frames["title"],font:launcher.gameFont,splash:launcher.splash,
                          width:min(700,width*0.67),moving:moving && focused && !map && launcher.status.state != "error")
            }
        }
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
                Button { search = ""; map = true } label: {
                    HStack(spacing:8) {
                        Text(launcher.journey.title).font(Blocks.action(18))
                            .lineLimit(2).multilineTextAlignment(.leading)
                        Image(systemName:"chevron.down").font(.system(size:10,weight:.bold))
                    }.frame(minHeight:44)
                        .shadow(color:.black.opacity(0.25),radius:2,y:1)
                }.buttonStyle(.plain).focused($areaFocused)
                    .overlay { Rectangle().strokeBorder(Blocks.gold,lineWidth:2).padding(-4).opacity(areaFocused ? 1 : 0) }
                    .accessibilityLabel("Choose biome: " + launcher.journey.title)
                    .help(launcher.journey.world == .sift ? "Sift interpretation · Choose biome" : "Choose biome or landmark")
                    .disabled(!available).popover(isPresented:$map) { biomeMap }
            }
        }
    }

    private var hotbar: some View {
        HStack(spacing:0) {
            ForEach(launcher.worlds.indices,id:\.self) { index in
                let world = launcher.worlds[index]
                Button { launcher.journey.select(world,animated:moving && !exploring) } label: {
                    Slot(world:world,image:launcher.items[world])
                }
                .buttonStyle(InventoryButton(selected:launcher.selection == index,
                    slot:launcher.frames["hotbar_0"],selection:launcher.frames["selected_hotbar_slot"]))
                .keyboardShortcut(KeyEquivalent(Character(String(index+1))),modifiers:[])
                .disabled(!available)
                .accessibilityLabel("\(world.title) scenery")
                .accessibilityAddTraits(launcher.selection == index ? .isSelected : [])
                .help(world == .sift ? "Sift interpretation · 4" : "\(world.title) · \(index+1)")
            }
        }.padding(6).background(.black.opacity(0.3))
            .accessibilityElement(children:.contain).accessibilityLabel("Realm hotbar")
    }

    private var look: some View {
        Button { explore(!exploring) } label: {
            VStack(spacing:1) {
                Image(systemName:exploring ? "eye.fill" : "eye").font(.system(size:24,weight:.medium))
                Image(systemName:"arrow.left.and.right").font(.system(size:11,weight:.semibold))
            }.frame(width:56,height:56)
        }.buttonStyle(BlockButton(selected:exploring,texture:launcher.stone))
            .disabled(!available || launcher.journey.passage != nil || launcher.status.state == "playing")
            .keyboardShortcut("l",modifiers:.command)
            .accessibilityLabel(exploring ? "Leave spectator view" : "Look around")
            .accessibilityHint("WASD flies, Space and Shift change height, arrow keys or dragging turn the view, brackets change biomes")
            .help(exploring ? "WASD fly · Space/Shift height · Drag/arrows look · Scroll speed · [ ] biomes · Escape returns" : "Look around (⌘L) · Spectator flight")
    }

    private func explore(_ enabled: Bool) {
        if enabled { hint.show(at:ProcessInfo.processInfo.systemUptime) }
        else { hint.dismiss(at:ProcessInfo.processInfo.systemUptime) }
        exploring = enabled
    }

    private var achievement: some View {
        HStack(spacing:12) {
            Image(systemName:"eye").font(.system(size:25,weight:.medium))
                .frame(width:40,height:40).foregroundStyle(Blocks.gold)
            if exploring {
                VStack(alignment:.leading,spacing:5) {
                    Text("Spectator mode").font(Blocks.type(13)).foregroundStyle(Blocks.gold)
                    Text("WASD fly · Drag to look").font(.system(size:12,weight:.medium))
                    Text("Space/Shift height · [ ] biomes").font(.system(size:11))
                }
            } else {
                Text("\(Text("⌘ + L").font(.system(size:13,weight:.semibold)).foregroundColor(Blocks.gold)) to look around")
                    .font(Blocks.type(13)).lineLimit(1)
            }
        }.padding(.horizontal,14).frame(height:exploring ? 88 : 64)
            .background {
                Rectangle().fill(Color(white:0.12))
                    .shadow(color:.black.opacity(0.3),radius:2,y:3)
            }
            .overlay { Rectangle().strokeBorder(Color(white:0.5),lineWidth:2) }
            .overlay { Rectangle().strokeBorder(.black.opacity(0.75),lineWidth:1).padding(3) }
            .accessibilityElement(children:.combine)
            .accessibilityLabel(exploring ? "Spectator mode: WASD flies, Space and Shift change height, arrow keys or dragging turn the view, brackets change biomes" : "Press Command L to look around")
            .allowsHitTesting(false)
    }

    private var biomeMap: some View {
        VStack(alignment:.leading,spacing:16) {
            HStack {
                Text("Explore \(launcher.journey.world.title)").font(Blocks.action(20))
                Spacer()
                Button { map = false } label: { Image(systemName:"xmark").frame(width:32,height:32) }
                    .buttonStyle(.plain).accessibilityLabel("Close biomes")
            }
            TextField("Find a biome or landmark",text:$search).textFieldStyle(.roundedBorder)
                .accessibilityLabel("Find a biome or landmark")
            ScrollView {
                LazyVGrid(columns:[GridItem(.flexible()),GridItem(.flexible()),GridItem(.flexible())],spacing:8) {
                    ForEach(launcher.journey.world.biomes.indices.filter { search.isEmpty || launcher.journey.world.biomes[$0].rawValue.localizedCaseInsensitiveContains(search) },id:\.self) { index in
                        Button { launcher.journey.area(index); map = false } label: {
                            HStack(spacing:6) {
                                if index == launcher.journey.biome { Image(systemName:"checkmark").foregroundStyle(Blocks.gold) }
                                Text(launcher.journey.world.biomes[index].rawValue).font(.system(size:12,weight:.medium))
                                    .frame(maxWidth:.infinity,alignment:.leading).multilineTextAlignment(.leading)
                            }.padding(10).frame(minHeight:52)
                        }.buttonStyle(BlockButton(selected:index == launcher.journey.biome,texture:launcher.stone))
                    }
                }
            }.frame(maxHeight:330)
            if launcher.journey.world == .sift { Text("An artistic interpretation using existing Minecraft blocks and mobs").font(.caption).foregroundStyle(.secondary) }
        }.padding(20).frame(width:570).background(Blocks.stone)
    }

    @ViewBuilder private var installation: some View {
        if !launcher.running && ["ready","new","cancelled"].contains(launcher.status.state) {
            VStack(spacing:12) {
                playButton(width:320)
                if !detail.isEmpty {
                    Text(detail).font(.system(size:13,weight:.medium)).multilineTextAlignment(.center)
                        .frame(maxWidth:500).shadow(color:.black.opacity(0.25),radius:2,y:1).textSelection(.enabled)
                }
                if fresh || launcher.status.state == "cancelled" { setupSteps }
            }
        } else { panel }
    }

    private func playButton(width: CGFloat) -> some View {
        Button { launcher.start() } label: {
            Label(primaryTitle,systemImage:"play.fill").font(.system(size:width>200 ? 24 : 18,weight:.bold,design:.rounded))
                .frame(width:width,height:62)
        }.buttonStyle(BlockButton(colour:Blocks.grass)).keyboardShortcut(.defaultAction)
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

private struct Preferences: View {
    @AppStorage("animateScenery") private var animateScenery = true
    @AppStorage("rotateScenery") private var rotateScenery = true
    @AppStorage("musicEnabled") private var musicEnabled = true
    @AppStorage("musicVolume") private var musicVolume = 0.18
    @Environment(\.accessibilityReduceMotion) private var reduced

    var body: some View {
        Form {
            Section("Scenery") {
                Toggle("Animate the background adventure", isOn: $animateScenery)
                Toggle("Automatically change scenes", isOn: $rotateScenery)
                    .disabled(!animateScenery)
                Text(reduced ? "Reduced Motion is enabled in macOS, so scenery stays still."
                     : "Animation pauses in Low Power Mode, in the background and while Minecraft runs.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Minecraft") {
                Text("Change game graphics, sound, controls and accessibility inside Minecraft.")
                    .foregroundStyle(.secondary)
            }
            Section("Launcher music") {
                Toggle("Play Minecraft menu and game music",isOn:$musicEnabled)
                Slider(value:$musicVolume,in:0...1) { Text("Volume") }
                    .disabled(!musicEnabled).accessibilityValue("\(Int(musicVolume*100)) percent")
                Text("Uses your installed game’s music. Pauses when you leave the launcher or start Minecraft.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped).padding(16).frame(width: 460)
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
            Button("Minecraft for MacOS Help") {
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
        Window("Minecraft for MacOS", id: "launcher") {
            LauncherView(launcher: launcher)
                .onAppear { delegate.launcher = launcher; NSApp.activate(ignoringOtherApps: true) }
        }
        .defaultSize(width: 1040, height: 760)
        .windowStyle(.hiddenTitleBar)
        .commands { LauncherMenus(launcher: launcher) }
        Settings { Preferences() }
    }
}

#endif
