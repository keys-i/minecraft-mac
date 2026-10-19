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
            art.icons { [weak self] images in
                guard let self, self.assets === art else { return }
                self.items = images
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

private enum Blocks {
    static let grass = Color(red:0.48,green:0.78,blue:0.22)
    static let ink = Color(red:0.055,green:0.12,blue:0.025)
    static let stone = Color(red:0.20,green:0.21,blue:0.19)
    static let gold = Color(red:1,green:0.83,blue:0.37)

    static func type(_ size: CGFloat) -> Font { .custom("Monocraft",size:size,relativeTo:.body) }
}

private struct BlockButton: ButtonStyle {
    var colour: Color = Blocks.stone
    var selected = false
    @Environment(\.accessibilityReduceMotion) private var reduced
    @Environment(\.isFocused) private var focused
    @Environment(\.isEnabled) private var enabled
    @State private var hovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(colour == Blocks.grass ? Blocks.ink : .white)
            .background(colour.brightness(hovered ? 0.08 : 0))
            .overlay(alignment:.top) { Rectangle().fill(.white.opacity(0.25)).frame(height:2) }
            .overlay(alignment:.bottom) { Rectangle().fill(.black.opacity(0.45)).frame(height:4) }
            .overlay { Rectangle().strokeBorder(selected ? Blocks.gold : .black.opacity(0.7),lineWidth:2) }
            .overlay { Rectangle().strokeBorder(Blocks.gold,lineWidth:2).padding(-4).opacity(focused ? 1 : 0) }
            .shadow(color:.black.opacity(0.4),radius:0,x:0,y:configuration.isPressed ? 0 : 3)
            .offset(y:configuration.isPressed && !reduced ? 2 : 0)
            .opacity(enabled ? 1 : 0.45)
            .contentShape(Rectangle())
            .onHover { hovered = $0 }
            .animation(reduced ? nil : .easeOut(duration:0.08),value:configuration.isPressed)
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
        }.frame(width:30,height:30).accessibilityHidden(true)
    }
}

private struct Scenery: View {
    let journey: Journey
    let moving: Bool
    let exploring: Bool
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
            Adventure(world:journey.world,biome:journey.biome,moving:moving,passage:journey.passage,assets:assets,exploring:exploring) { launcher.sceneryFailed = true }
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

struct LauncherView: View {
    @ObservedObject var launcher: Launcher
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openSettings) private var openSettings
    @AppStorage("animateScenery") private var animateScenery = true
    @AppStorage("rotateScenery") private var rotateScenery = true
    @State private var visible = true
    @State private var lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
    @State private var exploring = false
    @State private var map = false
    @State private var search = ""
    private var fresh: Bool { launcher.status.state == "new" }
    private var available: Bool { launcher.assets != nil && !launcher.sceneryFailed }
    private var moving: Bool {
        available && SceneryMotion.enabled(reduced:reduceMotion,paused:!animateScenery,lowPower:lowPower,
            active:scenePhase == .active,visible:visible,playing:launcher.status.state == "playing")
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
                Scenery(journey:launcher.journey,moving:moving,exploring:exploring,launcher:launcher)
                    .frame(width:geometry.size.width,height:geometry.size.height).clipped().ignoresSafeArea().allowsHitTesting(exploring)
                VStack(spacing:0) {
                    header.padding(.horizontal,28).padding(.top,28)
                    Spacer(minLength:40)
                    if exploring {
                        Button { exploring = false } label: {
                            Label("Drag to look around · Done",systemImage:"viewfinder").font(Blocks.type(13))
                                .padding(.horizontal,18).frame(height:44)
                        }.buttonStyle(BlockButton()).padding(.bottom,24)
                    } else {
                        VStack(spacing:16) {
                            location
                            HStack(alignment:.bottom,spacing:14) {
                                hotbar
                                Spacer(minLength:14)
                                Button { exploring = true } label: {
                                    VStack(spacing:5) {
                                        Image(systemName:"viewfinder").font(.system(size:20))
                                        Text("Look around").font(.system(size:11,weight:.semibold))
                                    }.frame(width:90,height:72)
                                }.buttonStyle(BlockButton()).disabled(!available || launcher.journey.passage != nil)
                                    .help("Drag the world to look around. Escape returns to the trail")
                            }
                            installation
                        }.frame(maxWidth:760).padding(.horizontal,28)
                        HStack {
                            Text(launcher.sceneryFailed ? "Scenery unavailable for this game version" : available ? "Unofficial launcher · Windows Bedrock Edition" : "Install Minecraft to explore the live worlds")
                                .font(.system(size:11)).foregroundStyle(.white.opacity(0.75))
                            Spacer()
                            Text("↵  \(primaryTitle)").font(.system(size:11,weight:.medium)).foregroundStyle(.white.opacity(0.75))
                                .opacity(launcher.running ? 0 : 1)
                        }.frame(maxWidth:760).padding(.horizontal,28).padding(.top,18).padding(.bottom,18)
                    }
                }
            }
        }
        .foregroundStyle(.white).environment(\.colorScheme,.dark)
        .frame(minWidth:760,minHeight:620)
        .onExitCommand { if map { map = false } else if exploring { exploring = false } else if launcher.canCancel { launcher.cancel() } }
        .onReceive(NotificationCenter.default.publisher(for:.NSProcessInfoPowerStateDidChange)) { _ in lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled }
        .onReceive(NotificationCenter.default.publisher(for:NSWindow.didChangeOcclusionStateNotification)) { _ in
            visible = NSApp.windows.contains { $0.title == "Minecraft for MacOS" && $0.occlusionState.contains(.visible) }
        }
        .onChange(of:reduceMotion) { if reduceMotion { launcher.journey.skip() } }
        .onChange(of:lowPower) { if lowPower { launcher.journey.skip() } }
        .onChange(of:launcher.journey.world) { exploring = false }
        .onChange(of:launcher.status.state) { if launcher.status.state == "playing" { exploring = false } }
        .task(id:moving && !exploring && (rotateScenery || launcher.journey.passage != nil)) {
            guard moving, !exploring, rotateScenery || launcher.journey.passage != nil else { return }
            while !Task.isCancelled {
                do { try await Task.sleep(for:.seconds(1)) } catch { return }
                guard !Task.isCancelled else { return }
                launcher.journey.tick(rotate:rotateScenery)
            }
        }
    }

    private var header: some View {
        HStack(alignment:.top) {
            VStack(alignment:.leading,spacing:5) {
                Text("Minecraft").font(Blocks.type(34)).shadow(color:.black,radius:0,x:3,y:3)
                Text("for MacOS").font(Blocks.type(14)).foregroundStyle(Blocks.gold)
                    .shadow(color:.black,radius:0,x:1,y:2)
            }.accessibilityElement(children:.combine).accessibilityAddTraits(.isHeader)
            Spacer()
            HStack(spacing:8) {
                Button { launcher.showHelp() } label: { Image(systemName:"questionmark").frame(width:44,height:44) }
                    .help("Help").accessibilityLabel("Help")
                Button { openSettings() } label: { Image(systemName:"gearshape.fill").frame(width:44,height:44) }
                    .help("Settings").accessibilityLabel("Settings")
                Button { animateScenery.toggle() } label: { Image(systemName:animateScenery ? "pause.fill" : "play.fill").frame(width:44,height:44) }
                    .accessibilityLabel(animateScenery ? "Pause scenery" : "Resume scenery")
                    .help(reduceMotion ? "Reduced Motion is enabled" : lowPower ? "Scenery pauses in Low Power Mode" : "Pause or resume the adventure")
                    .disabled(reduceMotion || lowPower)
            }.buttonStyle(BlockButton())
        }
    }

    private var location: some View {
        HStack(alignment:.bottom) {
            VStack(alignment:.leading,spacing:6) {
                Text(launcher.journey.world.title).font(Blocks.type(14)).foregroundStyle(Blocks.gold)
                Text(launcher.journey.title).font(Blocks.type(20))
                    .shadow(color:.black,radius:0,x:2,y:2).lineLimit(2)
                    .accessibilityAddTraits(.isHeader)
            }
            Spacer(minLength:12)
            if launcher.journey.passage != nil {
                Button { launcher.journey.skip() } label: {
                    Text("Skip journey").font(Blocks.type(12)).padding(.horizontal,14).frame(height:44)
                }.buttonStyle(BlockButton())
            } else {
                Button { search = ""; map = true } label: {
                    Label("Explore biomes",systemImage:"map").font(.system(size:13,weight:.semibold))
                        .padding(.horizontal,14).frame(height:44)
                }.buttonStyle(BlockButton()).disabled(!available)
                    .popover(isPresented:$map) { biomeMap }
            }
        }.frame(maxWidth:.infinity)
    }

    private var hotbar: some View {
        HStack(spacing:6) {
            ForEach(launcher.worlds.indices,id:\.self) { index in
                let world = launcher.worlds[index]
                Button {
                    launcher.journey.select(world,animated:moving)
                } label: {
                    VStack(spacing:5) {
                        Slot(world:world,image:launcher.items[world])
                        Text(world.title).font(.system(size:11,weight:.semibold)).lineLimit(1)
                    }.frame(width:93,height:72)
                        .overlay(alignment:.topLeading) { Text("\(index+1)").font(.system(size:9,weight:.bold)).foregroundStyle(.white.opacity(0.5)).padding(5) }
                }
                .buttonStyle(BlockButton(selected:launcher.selection == index))
                .keyboardShortcut(KeyEquivalent(Character(String(index+1))),modifiers:[])
                .disabled(!available)
                .accessibilityLabel("\(world.title) scenery")
                .accessibilityAddTraits(launcher.selection == index ? .isSelected : [])
                .help(world == .sift ? "Sift interpretation · 4" : "\(world.title) · \(index+1)")
            }
        }.padding(6).background(.black.opacity(0.5))
    }

    private var biomeMap: some View {
        VStack(alignment:.leading,spacing:16) {
            HStack {
                Text("Explore \(launcher.journey.world.title)").font(Blocks.type(18))
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
                        }.buttonStyle(BlockButton(selected:index == launcher.journey.biome))
                    }
                }
            }.frame(maxHeight:330)
            if launcher.journey.world == .sift { Text("An artistic interpretation using existing Minecraft blocks and mobs").font(.caption).foregroundStyle(.secondary) }
        }.padding(20).frame(width:570).background(Blocks.stone)
    }

    private var installation: some View {
        VStack(alignment:.leading,spacing:14) {
            HStack(spacing:24) {
                VStack(alignment:.leading,spacing:7) {
                    Text(fresh ? "Install Minecraft" : launcher.status.title)
                        .font(Blocks.type(18)).fixedSize(horizontal:false,vertical:true).accessibilityAddTraits(.isHeader)
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
                    Button { launcher.start() } label: {
                        Label(primaryTitle,systemImage:"play.fill").font(Blocks.type(18))
                            .frame(width:fresh ? 230 : 188,height:62)
                    }.buttonStyle(BlockButton(colour:Blocks.grass)).keyboardShortcut(.defaultAction)
                } else if launcher.canCancel {
                    Button { launcher.cancel() } label: {
                        Text("Cancel setup").font(Blocks.type(14)).frame(width:160,height:54)
                    }.buttonStyle(BlockButton()).keyboardShortcut(.cancelAction)
                } else {
                    Label(launcher.status.state == "playing" ? "Game running" : "Please wait",systemImage:launcher.status.state == "playing" ? "checkmark" : "hourglass")
                        .font(Blocks.type(13)).frame(width:160,height:54)
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
            if launcher.status.state == "error" {
                Button { launcher.showLog() } label: {
                    Label("Open setup log",systemImage:"doc.text").font(.system(size:12,weight:.semibold))
                        .padding(.horizontal,12).frame(height:36)
                }.buttonStyle(BlockButton())
            }
        }
        .padding(20)
        .background(Blocks.stone.opacity(reduceTransparency ? 1 : 0.97))
        .overlay(alignment:.top) { Rectangle().fill(.white.opacity(0.2)).frame(height:2) }
        .overlay(alignment:.bottom) { Rectangle().fill(.black.opacity(0.6)).frame(height:4) }
        .overlay { Rectangle().strokeBorder(.black.opacity(0.8),lineWidth:2) }
        .shadow(color:.black.opacity(0.4),radius:0,x:0,y:5)
    }
}

private struct Preferences: View {
    @AppStorage("animateScenery") private var animateScenery = true
    @AppStorage("rotateScenery") private var rotateScenery = true
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
