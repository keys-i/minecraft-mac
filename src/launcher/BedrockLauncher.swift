import AppKit
import SwiftUI

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
    @Published var selection = 0
    private var process: Process?
    private var buffer = Data()
    let root: URL
    let worlds = World.allCases.compactMap { world -> (world: World, image: NSImage)? in
        guard let url = Bundle.main.url(forResource: world.rawValue, withExtension: "jpg"),
              let image = NSImage(contentsOf: url) else { return nil }
        return (world, image)
    }

    init() {
        let path = Bundle.main.object(forInfoDictionaryKey: "BedrockProjectPath") as? String ?? ""
        root = path.isEmpty ? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Bedrock for Mac") : URL(fileURLWithPath: path)
        start(check: true)
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
    static let grass = Color(red: 0.64, green: 0.94, blue: 0.40)
    static let ink = Color(red: 0.06, green: 0.13, blue: 0.04)
}

private struct LaunchButton: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isFocused) private var focused

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .semibold))
            .frame(maxWidth: .infinity, minHeight: 54)
            .foregroundStyle(Blocks.ink)
            .background(Blocks.grass, in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8).strokeBorder(.white.opacity(0.25))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 12).strokeBorder(.white, lineWidth: 2)
                    .padding(-4).opacity(focused ? 1 : 0)
            }
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.86 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.08), value: configuration.isPressed)
            .contentShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct Scenery: View {
    let worlds: [(world: World, image: NSImage)]
    let selection: Int
    let moving: Bool

    var body: some View {
        GeometryReader { geometry in
            TimelineView(.animation(minimumInterval: SceneryMotion.interval, paused: !moving)) { frame in
                let time = moving ? frame.date.timeIntervalSinceReferenceDate : 0
                ZStack {
                    Color(red: 0.04, green: 0.08, blue: 0.07)
                    ForEach(worlds.indices, id: \.self) { index in
                        Image(nsImage: worlds[index].image).resizable().scaledToFill()
                            .frame(width: geometry.size.width, height: geometry.size.height)
                            .scaleEffect(moving ? 1.065 : 1)
                            .offset(x: moving ? sin(time / 19) * 12 : 0,
                                    y: moving ? cos(time / 23) * 8 : 0)
                            .opacity(index == selection ? 1 : 0)
                    }
                    if moving {
                        Canvas { context, size in
                            guard size.width > 0, size.height > 0 else { return }
                            for index in 0..<18 {
                                let seed = Double(index)
                                let x = (seed * 73.7 + sin(time / 8 + seed) * 20)
                                    .truncatingRemainder(dividingBy: size.width)
                                let y = size.height - (time * (5 + seed / 4) + seed * 47)
                                    .truncatingRemainder(dividingBy: size.height)
                                let side = index.isMultiple(of: 3) ? 3.0 : 2.0
                                let colour = worlds.indices.contains(selection) ? worlds[selection].world.colour : Blocks.grass
                                context.fill(Path(CGRect(x: x, y: y, width: side, height: side)),
                                             with: .color(colour.opacity(0.25 + 0.3 * abs(sin(time / 3 + seed)))))
                            }
                        }
                    }
                    LinearGradient(colors: [.black.opacity(0.08), .clear, .black.opacity(0.82)],
                                   startPoint: .top, endPoint: .bottom)
                    LinearGradient(colors: [.black.opacity(0.42), .clear],
                                   startPoint: .leading, endPoint: .trailing)
                }
                .clipped()
            }
        }
        .overlay {
            if worlds.indices.contains(selection) {
                Adventure(world: worlds[selection].world, moving: moving)
            }
        }
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }
}

private struct WorldProgress: ProgressViewStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 20) {
            Canvas { context, size in
                let fraction = configuration.fractionCompleted ?? 0
                let unit = min(size.width / 25, 9)
                for index in 0..<30 {
                    let column = index % 10
                    let row = index / 10
                    let x = Double(column) * unit * 2.2 + Double(row) * unit
                    let y = size.height - Double(row) * unit * 1.5 - unit * 2
                    let filled = Double(index + 1) / 30 <= fraction
                    var top = Path()
                    top.move(to: CGPoint(x: x, y: y))
                    top.addLines([CGPoint(x: x + unit, y: y - unit / 2),
                                  CGPoint(x: x + 2 * unit, y: y),
                                  CGPoint(x: x + unit, y: y + unit / 2)])
                    top.closeSubpath()
                    context.fill(top, with: .color(filled ? Blocks.grass : .white.opacity(0.12)))
                    var face = Path()
                    face.move(to: CGPoint(x: x, y: y))
                    face.addLines([CGPoint(x: x + unit, y: y + unit / 2),
                                   CGPoint(x: x + 2 * unit, y: y),
                                   CGPoint(x: x + 2 * unit, y: y + unit),
                                   CGPoint(x: x + unit, y: y + unit * 1.5),
                                   CGPoint(x: x, y: y + unit)])
                    face.closeSubpath()
                    context.fill(face, with: .color(filled ? Blocks.grass.opacity(0.5) : .white.opacity(0.06)))
                }
            }
            .frame(width: 220, height: 58)
            .accessibilityHidden(true)
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 0) {
                if let fraction = configuration.fractionCompleted {
                    Text(fraction, format: .percent.precision(.fractionLength(0)))
                        .font(.system(size: 36, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                }
                Text("Overall setup").font(.caption).foregroundStyle(.white.opacity(0.72))
            }
        }
    }
}

private struct Journey: View {
    let stage: Int?
    private let names = ["Sign in", "Download", "Prepare", "Play"]
    private let icons = ["person.crop.circle", "arrow.down", "cube", "play.fill"]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(names.indices, id: \.self) { index in
                let complete = stage.map { index < $0 } ?? false
                let current = stage == index
                HStack(spacing: 8) {
                    Image(systemName: complete ? "checkmark.circle.fill" : icons[index])
                        .foregroundStyle(complete || current ? Blocks.grass : .white.opacity(0.5))
                    Text(names[index]).font(.system(size: 12, weight: current ? .semibold : .regular))
                        .foregroundStyle(.white.opacity(current || complete ? 1 : 0.65))
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(names[index]), \(complete ? "complete" : current ? "current step" : "upcoming")")
                if index != names.count - 1 {
                    Rectangle().fill(.white.opacity(0.16)).frame(height: 1).padding(.horizontal, 14)
                        .accessibilityHidden(true)
                }
            }
        }
    }
}

struct LauncherView: View {
    @ObservedObject var launcher: Launcher
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("animateScenery") private var animateScenery = true
    @AppStorage("rotateScenery") private var rotateScenery = true
    @State private var visible = true
    @State private var lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
    private var fresh: Bool { launcher.status.state == "new" }
    private var moving: Bool {
        SceneryMotion.enabled(reduced: reduceMotion, paused: !animateScenery, lowPower: lowPower,
                              active: scenePhase == .active, visible: visible,
                              playing: launcher.status.state == "playing")
    }
    private var primaryTitle: String {
        switch launcher.status.state {
        case "error": return "Try Again"
        case "new": return "Install & Play"
        case "cancelled": return "Continue"
        default: return "Play"
        }
    }

    private var detail: String {
        if fresh { return "Sign in with the Microsoft account that owns Minecraft for Windows" }
        if !launcher.status.detail.isEmpty { return launcher.status.detail }
        return launcher.status.state == "ready" ? "Your game and worlds stay on this Mac" : ""
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Scenery(worlds: launcher.worlds, selection: launcher.selection, moving: moving)
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.6), value: launcher.selection)
                    .ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 28) {
                        header
                        Spacer(minLength: 30)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Minecraft").font(.system(size: 64, weight: .bold, design: .rounded))
                                .tracking(-2)
                            Text("for MacOS").font(.system(size: 30, weight: .medium))
                                .foregroundStyle(.white.opacity(0.92))
                            Text("Windows Bedrock Edition").font(.system(size: 14, weight: .medium))
                                .foregroundStyle(.white.opacity(0.8)).padding(.top, 12)
                        }
                        .shadow(color: .black.opacity(0.3), radius: 12, y: 3)
                        .accessibilityElement(children: .combine)
                        .accessibilityAddTraits(.isHeader)
                        Spacer(minLength: 20)
                        installation
                        footer
                    }
                    .padding(.horizontal, 36).padding(.top, 34).padding(.bottom, 22)
                    .frame(minHeight: geometry.size.height, alignment: .topLeading)
                }
            }
        }
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
        .frame(minWidth: 760, minHeight: 620)
        .onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)) { _ in
            lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didChangeOcclusionStateNotification)) { _ in
            visible = NSApp.windows.contains { window in
                window.title == "Minecraft for MacOS" && window.occlusionState.contains(.visible)
            }
        }
        .task(id: moving && rotateScenery ? launcher.selection : -1) {
            guard moving, rotateScenery, launcher.worlds.count > 1 else { return }
            do { try await Task.sleep(for: .seconds(24)) } catch { return }
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 1.2)) {
                launcher.selection = (launcher.selection + 1) % launcher.worlds.count
            }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "cube.fill").font(.system(size: 22)).foregroundStyle(Blocks.grass)
                .accessibilityHidden(true)
            Text("Minecraft for MacOS").font(.system(size: 13, weight: .semibold))
            Spacer()
            HStack(spacing: 8) {
                Button { launcher.showHelp() } label: {
                    Label("Help", systemImage: "questionmark.circle").font(.system(size: 13, weight: .medium))
                }
                .buttonStyle(.plain).padding(.horizontal, 8).frame(minHeight: 36)
                Button { animateScenery.toggle() } label: {
                    Image(systemName: animateScenery ? "pause.circle" : "play.circle").font(.system(size: 21))
                        .frame(width: 38, height: 38)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(animateScenery ? "Pause scenery" : "Resume scenery")
                .help(reduceMotion ? "Scenery is still because Reduced Motion is enabled"
                      : lowPower ? "Scenery is still in Low Power Mode" : "Pause or resume animated scenery")
                .disabled(reduceMotion || lowPower)
            }
            .padding(4).padding(.leading, 6)
            .background(.black.opacity(0.7), in: Capsule())
        }
    }

    private var installation: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .center, spacing: 28) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 9) {
                        if launcher.status.state == "error" {
                            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                                .accessibilityHidden(true)
                        }
                        Text(fresh ? "Install Minecraft Bedrock" : launcher.status.title)
                            .font(.system(size: 23, weight: .semibold))
                            .accessibilityAddTraits(.isHeader)
                    }
                    if !detail.isEmpty {
                        Text(detail).font(.system(size: 13)).foregroundStyle(.white.opacity(0.78))
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Group {
                    if !launcher.running {
                        Button { launcher.start() } label: {
                            Label(primaryTitle, systemImage: "play.fill")
                        }
                        .buttonStyle(LaunchButton()).keyboardShortcut(.defaultAction)
                    } else if launcher.canCancel {
                        Button("Cancel Setup") { launcher.cancel() }
                            .buttonStyle(.bordered).controlSize(.large).keyboardShortcut(.cancelAction)
                    } else {
                        Label(launcher.status.state == "playing" ? "Game running" : "Please wait",
                              systemImage: launcher.status.state == "playing" ? "checkmark.circle.fill" : "hourglass")
                            .font(.system(size: 14, weight: .medium))
                    }
                }
                .frame(width: 190)
            }
            if launcher.running, let fraction = launcher.status.fraction,
               launcher.status.state == "busy" {
                ProgressView(value: fraction).progressViewStyle(WorldProgress())
                    .accessibilityLabel("Overall setup")
            }
            if fresh || launcher.status.state == "busy" || launcher.status.state == "cancelled" {
                Divider().overlay(.white.opacity(0.1))
                Journey(stage: launcher.status.stage)
            }
            if launcher.status.state == "error" {
                Button("Open Setup Log") { launcher.showLog() }.buttonStyle(.link)
            }
        }
        .padding(26)
        .background {
            if reduceTransparency {
                RoundedRectangle(cornerRadius: 16).fill(Color(red: 0.045, green: 0.065, blue: 0.055))
            } else {
                RoundedRectangle(cornerRadius: 16).fill(.regularMaterial)
            }
        }
        .overlay { RoundedRectangle(cornerRadius: 16).strokeBorder(.white.opacity(0.18)) }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Text("Unofficial launcher").font(.caption).foregroundStyle(.white.opacity(0.68))
            Spacer()
            ForEach(launcher.worlds.indices, id: \.self) { index in
                Button {
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.6)) { launcher.selection = index }
                } label: {
                    HStack(spacing: 7) {
                        Circle().fill(launcher.worlds[index].world.colour).frame(width: 6, height: 6)
                        Text(launcher.worlds[index].world.title).font(.system(size: 12, weight: .medium))
                    }
                    .padding(.horizontal, 12).frame(height: 32)
                    .background(.white.opacity(launcher.selection == index ? 0.18 : 0.04), in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(launcher.selection == index ? .isSelected : [])
                .accessibilityLabel("\(launcher.worlds[index].world.title) scenery")
                .help(launcher.worlds[index].world == .sift ? "Artistic Sift preview — announced for Java and Bedrock in 2027" : "Choose \(launcher.worlds[index].world.title) scenery")
            }
        }
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
                launcher.selection = (launcher.selection + 1) % launcher.worlds.count
            }
            .keyboardShortcut("]", modifiers: .command)
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
