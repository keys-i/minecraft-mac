import AppKit
import Carbon
import SwiftUI

struct Controls: Codable, Equatable {
    enum Action: String, Codable, CaseIterable, Identifiable {
        case forward, back, left, right, rise, descend, sprint
        case look, map, previous, next, overworld, nether, end, sift

        var id: Self { self }
        var title: String {
            switch self {
            case .forward: "Move forward"
            case .back: "Move backward"
            case .left: "Move left"
            case .right: "Move right"
            case .rise: "Fly up"
            case .descend: "Fly down"
            case .sprint: "Sprint"
            case .look: "Look around"
            case .map: "Toggle map"
            case .previous: "Previous biome"
            case .next: "Next biome"
            case .overworld: "Overworld"
            case .nether: "Nether"
            case .end: "The End"
            case .sift: "Sift"
            }
        }

        var movement: Bool {
            switch self {
            case .forward, .back, .left, .right, .rise, .descend, .sprint: true
            default: false
            }
        }
    }

    struct Key: Codable, Equatable, Hashable {
        let code: UInt16
        let modifiers: UInt
        static let mask: NSEvent.ModifierFlags = [.command, .option, .control, .shift]

        init(code: UInt16, modifiers: NSEvent.ModifierFlags = []) {
            self.code = Self.canonical(code)
            var flags = modifiers.intersection(Self.mask)
            if let own = Self.modifier(code) { flags.remove(own) }
            self.modifiers = flags.rawValue
        }

        var flags: NSEvent.ModifierFlags { .init(rawValue:modifiers) }
        var allowed: Bool {
            code < 128 && code != 53 && code != 57 && code != 63 && code == Self.canonical(code)
                && modifiers == flags.intersection(Self.mask).rawValue
                && !(code == 12 && flags.contains(.command))
                && Self.modifier(code).map { !flags.contains($0) } != false
        }

        static func canonical(_ code: UInt16) -> UInt16 {
            switch code {
            case 54: 55
            case 60: 56
            case 61: 58
            case 62: 59
            default: code
            }
        }

        static func modifier(_ code: UInt16) -> NSEvent.ModifierFlags? {
            switch canonical(code) {
            case 55: .command
            case 56: .shift
            case 58: .option
            case 59: .control
            default: nil
            }
        }

        static func quit(_ event: NSEvent) -> Bool {
            guard event.type == .keyDown || event.type == .keyUp else { return false }
            return event.modifierFlags.contains(.command)
                && (event.keyCode == 12 || event.charactersIgnoringModifiers?.lowercased() == "q")
        }

        var label: String {
            let prefix = [(NSEvent.ModifierFlags.control,"⌃"),(.option,"⌥"),(.shift,"⇧"),(.command,"⌘")]
                .filter { flags.contains($0.0) }.map(\.1).joined()
            return prefix + (Self.names[code] ?? translated ?? "Key \(code)")
        }

        private static let names: [UInt16:String] = [
                36:"Return",48:"Tab",49:"Space",51:"Delete",53:"Escape",55:"Command",56:"Shift",
                57:"Caps Lock",58:"Option",59:"Control",63:"Fn",64:"F17",65:"Keypad .",67:"Keypad *",
                69:"Keypad +",71:"Clear",75:"Keypad /",76:"Enter",78:"Keypad −",79:"F18",80:"F19",
                81:"Keypad =",82:"Keypad 0",83:"Keypad 1",84:"Keypad 2",85:"Keypad 3",86:"Keypad 4",
                87:"Keypad 5",88:"Keypad 6",89:"Keypad 7",91:"Keypad 8",92:"Keypad 9",96:"F5",
                97:"F6",98:"F7",99:"F3",100:"F8",101:"F9",103:"F11",105:"F13",106:"F16",
                107:"F14",109:"F10",111:"F12",113:"F15",114:"Help",115:"Home",116:"Page Up",
                117:"Forward Delete",118:"F4",119:"End",120:"F2",121:"Page Down",122:"F1",
                123:"←",124:"→",125:"↓",126:"↑"
        ]

        private var translated: String? {
            guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
                  let property = TISGetInputSourceProperty(source,kTISPropertyUnicodeKeyLayoutData) else { return nil }
            let data = Unmanaged<CFData>.fromOpaque(property).takeUnretainedValue()
            guard let bytes = CFDataGetBytePtr(data) else { return nil }
            let layout = UnsafeRawPointer(bytes).assumingMemoryBound(to:UCKeyboardLayout.self)
            var state: UInt32 = 0
            var length = 0
            var characters = [UniChar](repeating:0,count:8)
            let result = withExtendedLifetime(source) {
                UCKeyTranslate(layout,code,UInt16(kUCKeyActionDisplay),0,UInt32(LMGetKbdType()),
                               OptionBits(kUCKeyTranslateNoDeadKeysMask),&state,characters.count,&length,&characters)
            }
            guard result == noErr, length > 0 else { return nil }
            return String(utf16CodeUnits:characters,count:Int(length)).uppercased()
        }
    }

    private var version = 1
    private var bindings: [Action:Key]
    private enum CodingKeys: CodingKey { case version, bindings }

    init() {
        bindings = [.forward:Key(code:13),.back:Key(code:1),.left:Key(code:0),.right:Key(code:2),
                    .rise:Key(code:49),.descend:Key(code:56),.sprint:Key(code:59),
                    .look:Key(code:37,modifiers:.command),.map:Key(code:46),
                    .previous:Key(code:33),.next:Key(code:30),.overworld:Key(code:18),
                    .nether:Key(code:19),.end:Key(code:20),.sift:Key(code:21)]
    }

    init(data: Data) {
        self.init()
        guard !data.isEmpty, data.count <= 16_384,
              let decoded = try? JSONDecoder().decode(Self.self,from:data) else { return }
        self = decoded
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy:CodingKeys.self)
        version = try container.decode(Int.self,forKey:.version)
        bindings = try container.decode([Action:Key].self,forKey:.bindings)
        guard version == 1, bindings.count == Action.allCases.count,
              bindings.values.allSatisfy(\.allowed), Set(bindings.values).count == Action.allCases.count else {
            throw DecodingError.dataCorrupted(.init(codingPath:decoder.codingPath,debugDescription:"Invalid controls"))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy:CodingKeys.self)
        try container.encode(version,forKey:.version)
        var pairs = container.nestedUnkeyedContainer(forKey:.bindings)
        for action in Action.allCases { try pairs.encode(action); try pairs.encode(key(action)) }
    }

    var data: Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return (try? encoder.encode(self)) ?? Data()
    }
    func key(_ action: Action) -> Key { bindings[action]! }
    func label(_ action: Action) -> String { key(action).label }

    func matches(_ action: Action, event: NSEvent) -> Bool {
        guard event.type == .keyDown || event.type == .flagsChanged, !Key.quit(event) else { return false }
        let key = key(action)
        guard Key.canonical(event.keyCode) == key.code else { return false }
        var flags = event.modifierFlags.intersection(Key.mask)
        if let own = Key.modifier(key.code) {
            guard event.type == .flagsChanged, flags.contains(own) else { return false }
            flags.remove(own)
        } else if event.type != .keyDown { return false }
        return flags == key.flags
    }

    func pressed(_ action: Action, keys: Set<UInt16>, modifiers: NSEvent.ModifierFlags) -> Bool {
        let key = key(action)
        var flags = modifiers.intersection(Key.mask)
        if let own = Key.modifier(key.code) {
            guard flags.contains(own) else { return false }
            flags.remove(own)
        } else if !keys.contains(key.code) { return false }
        // A held sprint or flight modifier must not cancel another movement key
        for other in Action.allCases where other.movement {
            if let flag = Key.modifier(self.key(other).code), !key.flags.contains(flag) { flags.remove(flag) }
        }
        return flags == key.flags
    }

    @discardableResult
    mutating func assign(_ key: Key, to action: Action) -> String {
        guard key.allowed else {
            if key.code == 53 { return "Escape cancels changes and can’t be reassigned" }
            if key.code == 12 && key.flags.contains(.command) { return "Command-Q stays available to quit Minecraft" }
            return "That key isn’t available — choose another key"
        }
        guard bindings[action] != key else { return "\(action.title) already uses \(key.label)" }
        let previous = bindings[action]!
        let conflict = Action.allCases.first { $0 != action && bindings[$0] == key }
        if let conflict { bindings[conflict] = previous }
        bindings[action] = key
        if let conflict { return "\(action.title): \(key.label) · Swapped with \(conflict.title)" }
        return "\(action.title): \(key.label)"
    }
}

struct Keymap: View {
    @Binding var data: Data
    var stone: NSImage?
    @StateObject private var recorder = Recorder()

    var body: some View {
        let controls = Controls(data:data)
        VStack(alignment:.leading,spacing:12) {
            HStack {
                Text("Controls").fontWeight(.semibold)
                Spacer()
                Button {
                    recorder.stop()
                    data = Controls().data
                    recorder.message = "Default controls restored"
                } label: {
                    Text("Reset keys").padding(.horizontal,14).frame(minHeight:44)
                }.buttonStyle(BlockButton(texture:stone))
            }
            Text("Choose a control, then press a key or shortcut. Escape cancels.")
                .fixedSize(horizontal:false,vertical:true)
            ForEach(Controls.Action.allCases) { action in
                HStack(spacing:12) {
                    Text(action.title).fixedSize(horizontal:false,vertical:true)
                    Spacer(minLength:8)
                    Button { recorder.begin(action,data:$data) } label: {
                        Text(recorder.action == action ? "Press a key…" : controls.label(action))
                            .lineLimit(1).minimumScaleFactor(0.7)
                            .padding(.horizontal,12).frame(minWidth:140,minHeight:44)
                    }
                    .buttonStyle(BlockButton(selected:recorder.action == action,texture:stone))
                    .accessibilityLabel(action.title)
                    .accessibilityValue(recorder.action == action ? "Waiting for a key" : controls.label(action))
                    .accessibilityHint("Change key binding. Escape cancels.")
                }
            }
            Text(recorder.message).fixedSize(horizontal:false,vertical:true)
        }
        .background(WindowProbe(recorder:recorder).frame(width:0,height:0).allowsHitTesting(false).accessibilityHidden(true))
        .onDisappear { recorder.stop() }
    }

    @MainActor
    private final class Recorder: NSObject, ObservableObject {
        @Published var action: Controls.Action?
        @Published var message = "Changes save automatically"
        weak var window: NSWindow?
        private var monitor: Any?
        private var pending: Controls.Key?

        func begin(_ action: Controls.Action, data: Binding<Data>) {
            stop()
            guard let window, window.isKeyWindow, NSApp.isActive,
                  window.attachedSheet == nil, NSApp.modalWindow == nil else { return }
            self.action = action
            message = "Press a key for \(action.title.lowercased())"
            NotificationCenter.default.addObserver(self,selector:#selector(stop),name:NSWindow.didResignKeyNotification,object:window)
            NotificationCenter.default.addObserver(self,selector:#selector(stop),name:NSApplication.didResignActiveNotification,object:NSApp)
            monitor = NSEvent.addLocalMonitorForEvents(matching:[.keyDown,.flagsChanged]) { [weak self, weak window] event in
                guard let self, let window, self.action != nil else { return event }
                guard NSApp.isActive, window.isKeyWindow, event.window === window,
                      window.attachedSheet == nil, NSApp.modalWindow == nil else { self.stop(); return event }
                if event.keyCode == 53 { self.stop(); self.message = "Key change cancelled"; return nil }
                if Controls.Key.quit(event) { self.stop(); return event }
                if event.type == .flagsChanged {
                    guard let flag = Controls.Key.modifier(event.keyCode) else {
                        self.message = "Choose Shift, Control, Option, Command, or a regular key"
                        return event
                    }
                    if event.modifierFlags.contains(flag) {
                        self.pending = Controls.Key(code:event.keyCode,modifiers:event.modifierFlags)
                        return nil
                    }
                    guard let pending = self.pending, pending.code == Controls.Key.canonical(event.keyCode) else { return nil }
                    self.apply(pending,data:data)
                } else {
                    guard !event.isARepeat else { return nil }
                    self.apply(Controls.Key(code:event.keyCode,modifiers:event.modifierFlags),data:data)
                }
                return nil
            }
        }

        private func apply(_ key: Controls.Key, data: Binding<Data>) {
            guard let action else { return }
            var controls = Controls(data:data.wrappedValue)
            let feedback = controls.assign(key,to:action)
            data.wrappedValue = controls.data
            let window = window
            stop()
            message = feedback
            if let window, window.isKeyWindow {
                NSAccessibility.post(element:window,notification:.announcementRequested,
                    userInfo:[.announcement:feedback,.priority:NSAccessibilityPriorityLevel.medium.rawValue])
            }
        }

        @objc func stop() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            NotificationCenter.default.removeObserver(self)
            monitor = nil
            pending = nil
            action = nil
        }

        deinit {
            if let monitor { NSEvent.removeMonitor(monitor) }
            NotificationCenter.default.removeObserver(self)
        }
    }

    private struct WindowProbe: NSViewRepresentable {
        let recorder: Recorder

        func makeNSView(context: Context) -> Probe {
            let view = Probe()
            view.changed = { [weak recorder] window in
                recorder?.stop()
                recorder?.window = window
            }
            return view
        }

        func updateNSView(_ view: Probe, context: Context) {}
        static func dismantleNSView(_ view: Probe, coordinator: ()) {
            view.changed?(nil)
            view.changed = nil
        }

        final class Probe: NSView {
            var changed: ((NSWindow?) -> Void)?
            override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); changed?(window) }
        }
    }
}
