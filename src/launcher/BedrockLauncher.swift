import AppKit
import SwiftUI

struct Status: Decodable {
    let state: String
    let title: String
    let detail: String
    let progress: Double?
}

@MainActor
final class Launcher: ObservableObject {
    @Published var status = Status(state: "checking", title: "Minecraft on your Mac", detail: "Checking installation…", progress: nil)
    @Published var running = false
    private var process: Process?
    private var buffer = Data()
    let root: URL
    let artwork = Bundle.main.url(forResource: "poster", withExtension: "webp")
        .flatMap { NSImage(contentsOf: $0) }

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

private enum Blocks {
    static let grass = Color(red: 0.49, green: 0.87, blue: 0.29)
    static let edge = Color(red: 0.20, green: 0.43, blue: 0.10)
    static let ink = Color(red: 0.07, green: 0.13, blue: 0.04)
}

private struct BlockButton: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isFocused) private var focused

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.headline, design: .monospaced).weight(.bold))
            .frame(maxWidth: .infinity, minHeight: 48)
            .foregroundStyle(Blocks.ink)
            .background(Blocks.grass)
            .overlay(alignment: .top) { Rectangle().fill(.white.opacity(0.5)).frame(height: 2) }
            .overlay { Rectangle().strokeBorder(Blocks.ink, lineWidth: 2) }
            .background(alignment: .bottom) {
                Rectangle().fill(Blocks.edge).offset(y: configuration.isPressed ? 1 : 5)
            }
            .overlay {
                Rectangle().strokeBorder(Color.primary, lineWidth: 2)
                    .padding(-5).opacity(focused ? 1 : 0)
            }
            .offset(y: configuration.isPressed ? 4 : 0)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.08), value: configuration.isPressed)
            .contentShape(Rectangle())
    }
}

private struct BlockProgress: ProgressViewStyle {
    @Environment(\.colorScheme) private var scheme

    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Setup progress")
                Spacer()
                if let fraction = configuration.fractionCompleted {
                    Text(fraction, format: .percent.precision(.fractionLength(0)))
                        .monospacedDigit()
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Rectangle().fill(.primary.opacity(0.12))
                    if let fraction = configuration.fractionCompleted {
                        Rectangle().fill(scheme == .dark ? Blocks.grass : Blocks.edge)
                            .frame(width: geometry.size.width * min(max(fraction, 0), 1))
                    }
                }
                .overlay { Rectangle().strokeBorder(.primary.opacity(0.4), lineWidth: 1) }
            }
            .frame(height: 14)
        }
    }
}

struct LauncherView: View {
    @ObservedObject var launcher: Launcher
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var fresh: Bool { launcher.status.state == "new" }
    private var primaryTitle: String {
        switch launcher.status.state {
        case "error": return "Try Again"
        case "new": return "Install & Play"
        case "cancelled": return "Continue"
        default: return "Play"
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                if let artwork = launcher.artwork {
                    Image(nsImage: artwork).resizable().scaledToFit()
                        .accessibilityHidden(true)
                }
                Canvas { context, size in
                    for column in stride(from: 0.0, to: size.width, by: 16) {
                        let height = Int(column / 16).isMultiple(of: 3) ? 8.0 : 5.0
                        context.fill(Path(CGRect(x: column, y: 0, width: 16, height: height)),
                                     with: .color(Blocks.grass))
                    }
                }
                .frame(height: 8)
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 20) {
                    HStack(alignment: .top, spacing: 28) {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(alignment: .firstTextBaseline, spacing: 9) {
                                if launcher.status.state == "error" {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundStyle(.orange).accessibilityHidden(true)
                                }
                                Text(fresh ? "Install Minecraft Bedrock" : launcher.status.title)
                                    .font(.title2.weight(.bold))
                                    .accessibilityAddTraits(.isHeader)
                            }
                            if fresh || !launcher.status.detail.isEmpty {
                                Text(fresh
                                     ? "Sign in with the Microsoft account that owns Minecraft for Windows."
                                     : launcher.status.detail)
                                    .font(.body).foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        VStack(spacing: 12) {
                            if !launcher.running {
                                Button(primaryTitle) { launcher.start() }
                                    .buttonStyle(BlockButton())
                                    .keyboardShortcut(.defaultAction)
                            } else if launcher.canCancel {
                                Button("Cancel Setup") { launcher.cancel() }
                                    .buttonStyle(.bordered).controlSize(.large)
                                    .keyboardShortcut(.cancelAction)
                            } else if launcher.status.state == "playing" {
                                Label("Game running", systemImage: "checkmark.circle.fill")
                                    .font(.headline).foregroundStyle(.primary)
                            } else if reduceMotion {
                                Text("Please wait").foregroundStyle(.secondary)
                            } else {
                                ProgressView().controlSize(.small)
                                    .accessibilityLabel("Waiting for the current step")
                            }
                            if fresh {
                                Text("The game downloads after sign-in")
                                    .font(.caption).foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                        }
                        .frame(width: 208)
                    }

                    if launcher.running, let progress = launcher.status.progress,
                       launcher.status.state != "playing" {
                        ProgressView(value: progress)
                            .progressViewStyle(BlockProgress())
                            .accessibilityLabel("Setup progress")
                    }
                    if launcher.status.state == "error" {
                        Button("Open Setup Log") { launcher.showLog() }.buttonStyle(.link)
                    }

                    Divider()
                    HStack {
                        Text("Minecraft for MacOS")
                            .font(.caption.weight(.medium)).foregroundStyle(.secondary)
                        Spacer()
                        Button("Help") { launcher.showHelp() }
                            .buttonStyle(.link).font(.caption)
                    }
                }
                .padding(28)
            }
        }
        .background(scheme == .dark
                    ? Color(red: 0.075, green: 0.09, blue: 0.08)
                    : Color(red: 0.94, green: 0.95, blue: 0.92))
        .frame(minWidth: 640, minHeight: 540)
    }
}

@main
struct BedrockLauncherApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var launcher = Launcher()
    var body: some Scene {
        Window("Minecraft for MacOS", id: "launcher") {
            LauncherView(launcher: launcher)
                .onAppear { delegate.launcher = launcher; NSApp.activate(ignoringOtherApps: true) }
        }
        .defaultSize(width: 820, height: 680)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .appInfo) {
                Button("Sign Out of Microsoft…") { launcher.signOut() }
                    .disabled(launcher.running || launcher.status.state == "new")
            }
            CommandGroup(replacing: .help) {
                Button("Minecraft for MacOS Help") {
                    launcher.showHelp()
                }
                Button("Open Setup Logs") { launcher.showLog() }
            }
        }
    }
}
