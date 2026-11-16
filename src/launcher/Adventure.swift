import AppKit
import SceneKit
import SpriteKit
import SwiftUI
import simd

enum World: String, CaseIterable {
    case overworld, nether, end, sift

    var title: String {
        switch self {
        case .overworld: return "Overworld"
        case .nether: return "Nether"
        case .end: return "The End"
        case .sift: return "The Sift"
        }
    }

    var colour: Color {
        switch self {
        case .overworld: return Color(red: 0.64, green: 0.94, blue: 0.40)
        case .nether: return .orange
        case .end: return .purple
        case .sift: return .cyan
        }
    }
}

enum VoxelAdventure {
    static func sway(_ node: SCNNode, x: CGFloat = 0, y: CGFloat = 0,
                             z: CGFloat = 0, period: Double, phase: Double = 0) {
        let base = node.eulerAngles
        node.eulerAngles = SCNVector3(base.x + x * sin(phase), base.y + y * sin(phase), base.z + z * sin(phase))
        node.runAction(.repeatForever(.customAction(duration: period) { node, elapsed in
            let wave = sin(Double(elapsed) / period * .pi * 2 + phase)
            node.eulerAngles = SCNVector3(base.x + x * wave, base.y + y * wave, base.z + z * wave)
        }))
    }
}

final class FlightView: SCNView {
    static let eyeHeight = 1.62
    let controller = SCNCameraController()
    var travel: ((Int) -> Void)?
    var finish: (() -> Void)?
    var report: ((SCNVector3,Double) -> Void)?
    var step: ((Double) -> Void)?
    var materials: ((Double) -> Void)?
    var sweep: ((SCNVector3,SCNVector3) -> SCNVector3)?
    var resolution: (Double) -> Void = { _ in }
    var metrics: URL?
    private let frames = Frame()
    private var budget = Frame.Budget()
    private var heartbeat = false
    var sensitivity: Float = 0.15
    var inverted = false
    var controls = Controls() { didSet { if controls != oldValue { stop() } } }
    private(set) var keys: Set<UInt16> = []
    private(set) var speed: Float = 16
    private var modifiers: NSEvent.ModifierFlags = []
    private var descending: Bool { controls.pressed(.descend,keys:keys,modifiers:modifiers) }
    private var sprinting: Bool { controls.pressed(.sprint,keys:keys,modifiers:modifiers) }
    private var moving: Bool { Controls.Action.allCases.contains { $0.movement && $0 != .sprint && controls.pressed($0,keys:keys,modifiers:modifiers) } }
    private var mouse: Any?
    private weak var inputWindow: NSWindow?
    private var acceptedMouse = false
    private(set) var captured = false
    private var timer: CADisplayLink?
    private var clockRate = 0
    private var last = 0.0
    private var loading = false
    private var area: Biome = .meadow
    weak var atlas: Atlas?
    private var doors: [Door] = []
    var exploring = false {
        didSet {
            guard exploring != oldValue else { return }
            stop()
            if exploring { capture() }
            else {
                release()
                if window?.firstResponder === self { window?.makeFirstResponder(nil) }
            }
        }
    }

    var diagnostics: (fps:Double,scale:Double,device:String) {
        (frames.rate,budget.scale,device?.name ?? "Metal")
    }

    override var acceptsFirstResponder: Bool { exploring }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        NotificationCenter.default.removeObserver(self,name:NSWindow.didResignKeyNotification,object:nil)
        NotificationCenter.default.removeObserver(self,name:NSWindow.didBecomeKeyNotification,object:nil)
        NotificationCenter.default.removeObserver(self,name:NSApplication.didBecomeActiveNotification,object:nil)
        stop(); release()
        if let window {
            NotificationCenter.default.addObserver(self,selector:#selector(lostFocus),name:NSWindow.didResignKeyNotification,object:window)
            NotificationCenter.default.addObserver(self,selector:#selector(gainedFocus),name:NSWindow.didBecomeKeyNotification,object:window)
            NotificationCenter.default.addObserver(self,selector:#selector(gainedFocus),name:NSApplication.didBecomeActiveNotification,object:nil)
        }
    }

    override func resignFirstResponder() -> Bool { stop(); release(); return super.resignFirstResponder() }
    @objc private func lostFocus() { stop(); release() }
    @objc private func gainedFocus() { if heartbeat { start() } }

    override func mouseDown(with event: NSEvent) {
        if exploring { capture(); return }
        super.mouseDown(with:event)
    }

    private func capture() {
        guard exploring, !captured, let window, window.isKeyWindow else { return }
        window.makeFirstResponder(self)
        guard CGAssociateMouseAndMouseCursorPosition(0) == .success else { return }
        inputWindow = window; acceptedMouse = window.acceptsMouseMovedEvents; window.acceptsMouseMovedEvents = true
        captured = true; NSCursor.hide()
        mouse = NSEvent.addLocalMonitorForEvents(matching:[.mouseMoved,.leftMouseDragged,.rightMouseDragged]) { [weak self] event in
            guard let self, self.captured else { return event }
            self.aim(x:Float(event.deltaX),y:Float(-event.deltaY))
            return nil
        }
    }

    private func release() {
        if let mouse { NSEvent.removeMonitor(mouse); self.mouse = nil }
        inputWindow?.acceptsMouseMovedEvents = acceptedMouse; inputWindow = nil
        if captured { CGAssociateMouseAndMouseCursorPosition(1); NSCursor.unhide(); captured = false }
    }

    func aim(x: Float, y: Float) {
        guard exploring, !loading else { return }
        controller.rotateBy(x:-x*sensitivity,y:y*sensitivity*(inverted ? -1 : 1))
        needsDisplay = true
    }

    override func keyDown(with event: NSEvent) {
        guard exploring, !Controls.Key.quit(event) else {
            super.keyDown(with:event); return
        }
        if event.keyCode == 53 { stop(); finish?(); return }
        let code = Controls.Key.canonical(event.keyCode)
        let candidate = keys.union([code])
        let bound = Controls.Action.allCases.contains { $0.movement && controls.key($0).code == code && controls.pressed($0,keys:candidate,modifiers:event.modifierFlags) }
        let physical = Controls.Action.allCases.contains { $0.movement && controls.key($0).code == code }
        let arrow = [123,124,125,126].contains(code) && event.modifierFlags.intersection([.command,.option]).isEmpty
        guard physical || arrow else { super.keyDown(with:event); return }
        modifiers = event.modifierFlags
        keys.insert(code)
        if bound || arrow { start() }
        else if !event.modifierFlags.intersection([.command,.option]).isEmpty { super.keyDown(with:event) }
    }

    override func keyUp(with event: NSEvent) {
        modifiers = event.modifierFlags
        if keys.remove(Controls.Key.canonical(event.keyCode)) != nil { if keys.isEmpty && !moving && !heartbeat { suspend() }; return }
        super.keyUp(with:event)
    }

    override func flagsChanged(with event: NSEvent) {
        guard exploring else { super.flagsChanged(with:event); return }
        modifiers = event.modifierFlags
        if heartbeat || moving || !keys.isEmpty { start() } else { suspend() }
    }

    override func scrollWheel(with event: NSEvent) {
        guard exploring, event.modifierFlags.contains(.control) else { super.scrollWheel(with:event); return }
        speed = min(64,max(4,speed*pow(1.08,Float(max(-10,min(10,event.scrollingDeltaY))))))
    }

    func prepare() { loading = true; suspend() }

    func install(_ camera: SCNNode?, area: Biome) {
        self.area = area
        doors = scene.map { Door.collect($0.rootNode) } ?? []
        loading = false
        controller.pointOfView = camera
        controller.interactionMode = .fly; controller.inertiaEnabled = false
        controller.minimumVerticalAngle = -85; controller.maximumVerticalAngle = 85
        start()
    }

    func stop() { suspend(); keys.removeAll(); modifiers = []; isPlaying = false; rendersContinuously = false }
    func clock(_ enabled: Bool) {
        heartbeat = enabled
        if enabled { start() } else { stop() }
    }
    private func suspend() { timer?.invalidate(); timer = nil; frames.reset() }

    private func start() {
        guard !loading, window?.isKeyWindow == true, NSApp.isActive,
              window?.occlusionState.contains(.visible) == true, !isHiddenOrHasHiddenAncestor,
              heartbeat || exploring && (!keys.isEmpty || moving) else {
            isPlaying = false; rendersContinuously = false; return
        }
        isPlaying = true; rendersContinuously = true
        delegate = frames
        if timer != nil && clockRate != preferredFramesPerSecond {suspend()}
        guard timer == nil else { return }
        clockRate = preferredFramesPerSecond
        last = ProcessInfo.processInfo.systemUptime
        let timer = displayLink(target:self,selector:#selector(tick(_:)))
        let rate = Float(max(1,preferredFramesPerSecond))
        timer.preferredFrameRateRange = CAFrameRateRange(minimum:rate,maximum:rate,preferred:rate)
        self.timer = timer
        timer.add(to:.main,forMode:.common)
    }

    @objc private func tick(_ link: CADisplayLink) {
        guard heartbeat || exploring, window?.isKeyWindow == true, window?.occlusionState.contains(.visible) == true,
              NSApp.isActive, !isHiddenOrHasHiddenAncestor else { stop(); release(); return }
        let now = ProcessInfo.processInfo.systemUptime
        let seconds = min(0.1,max(0,now-last)); last = now
        let state = ProcessInfo.processInfo.thermalState
        if let scale = budget.sample(interval:frames.interval,seconds:seconds,target:1/Double(max(1,preferredFramesPerSecond)),
                                     hot:state == .serious || state == .critical) {resolution(scale)}
        materials?(now)
        step?(seconds)
        if exploring { advance(seconds:seconds) }
        frames.write(to:metrics,mode:exploring ? "look" : preferredFramesPerSecond>30 ? "journey" : "menu",scale:budget.scale,
                     step:ProcessInfo.processInfo.systemUptime-now)
    }

    func advance(seconds: Double) {
        guard !loading, let camera = pointOfView else { return }
        let dt = Float(min(0.1,max(0,seconds)))
        func key(_ code: UInt16) -> Float {
            keys.contains(code) && !Controls.Action.allCases.contains(where:{ $0.movement && controls.key($0).code == code }) ? 1 : 0
        }
        func held(_ action: Controls.Action) -> Float { controls.pressed(action,keys:keys,modifiers:modifiers) ? 1 : 0 }
        let local = SIMD4<Float>(held(.right)-held(.left),0,held(.back)-held(.forward),0)
        let rotated = camera.simdWorldTransform*local
        var direction = SIMD3<Float>(rotated.x,rotated.y,rotated.z)
        direction.y += held(.rise)-(descending ? 1 : 0)
        if simd_length_squared(direction)>0, let scene {
            let next = camera.simdWorldPosition+simd_normalize(direction)*speed*(sprinting ? 2 : 1)*dt
            atlas?.cancelTravel()
            for door in doors { door.approach(camera.worldPosition) }
            var feet = camera.worldPosition
            feet.y -= Self.eyeHeight
            var destination = atlas?.constrain(SCNVector3(next)) ?? SCNVector3(next)
            destination.y -= Self.eyeHeight
            let moved = sweep?(feet,destination) ?? Collision.move(scene.rootNode,from:feet,to:destination,radius:0.3,height:1.8)
            camera.worldPosition = .init(moved.x,moved.y+Self.eyeHeight,moved.z)
        }
        camera.position.y = min(320,max(-96,camera.position.y))
        if atlas == nil, sweep == nil, let scene { Landscape.medium(scene,area:area,eye:camera.position) }
        let yaw = key(124)-key(123), pitch = key(126)-key(125)
        if yaw != 0 || pitch != 0 { controller.rotateBy(x:-yaw*70*dt,y:pitch*70*dt) }
        needsDisplay = true
    }

    // Derive yaw and pitch from the forward vector so vertical turns never select an inverted Euler branch
    static func face(_ camera: SCNNode, toward point: SCNVector3, seconds: Double) {
        let forward = camera.convertVector(.init(0,0,-1),to:nil)
        var yaw = atan2(-forward.x,-forward.z)
        var pitch = atan2(forward.y,hypot(forward.x,forward.z))
        let eye = camera.worldPosition, dx = point.x-eye.x, dy = point.y-eye.y, dz = point.z-eye.z
        let horizontal = hypot(dx,dz)
        guard hypot(horizontal,dy)>0.00001 else {return}
        let targetYaw = horizontal>0.0001 ? atan2(-dx,-dz) : yaw
        let targetPitch = min(Double.pi*0.47,max(-Double.pi*0.47,atan2(dy,horizontal)))
        let dt = max(0,min(0.1,seconds)), blend = 1-exp(-dt*5), limit = dt*Double.pi/2
        let turn = atan2(sin(targetYaw-yaw),cos(targetYaw-yaw))
        yaw += max(-limit,min(limit,turn*blend))
        pitch += max(-limit,min(limit,(targetPitch-pitch)*blend))
        camera.simdOrientation = simd_quatf(angle:Float(yaw),axis:.init(0,1,0))*simd_quatf(angle:Float(pitch),axis:.init(1,0,0))
    }

    func visit(_ step: Int) {
        if let atlas { atlas.visit(atlas.active+step); return }
        guard !loading else { return }
        travel?(step)
    }

    func dispose() {
        stop(); release(); delegate = nil; atlas = nil; doors = []; travel = nil; finish = nil; report = nil; step = nil; materials = nil; sweep = nil; resolution = {_ in}; controller.pointOfView = nil
        NotificationCenter.default.removeObserver(self)
    }
}

// Authored landmarks share a bounded cache while terrain streams through a floating origin
final class Atlas {
    static let span = Double(Region.span)
    let world: World
    let assets: Assets
    let seed: Int
    let scene = SCNScene()
    private(set) var active: Int
    private(set) var tiles: [Int:SCNScene] = [:]
    private var region: Region
    private var origin = SCNVector3Zero
    private var operations: [Int:Operation] = [:]
    private var homes: [Int:SCNVector3] = [:]
    private weak var view: FlightView?
    private let arrived: (Int) -> Void
    private let failed: () -> Void
    private let location: (String?) -> Void
    private let activity: (Bool) -> Void
    private let stream: Stream
    private var destination: Region?
    private var points: [SCNVector3] = []
    private var speed = 0.0
    private var blocked = 0.0
    private var emergence: Double?
    private var travelling = false
    private var navigation = 0
    private var last: Double?
    private var environment = -1.0
    private var reported = -1.0
    private var timer: Timer?
    private var doors: [Door] = []
    private var prefetched: Chunk?
    private var renderDistance = 8
    private var paused = false
    private var disposed = false
    private var published: String?
    private var hasPublished = false
    private var publication = 0
    private var key: Int { region.key(world.biomes.count) }
    var chunkCount: Int { stream.chunks.count }
    var chunkLimit: Int { stream.limit }
    var pendingChunks: Int { stream.outstanding }
    var logicalPosition: SCNVector3? { view?.pointOfView.map { logical($0.worldPosition) } }
    func ready(at point: SCNVector3) -> Bool { stream.contains(logical(point)) }

    init(world: World, index: Int, tile: SCNScene, assets: Assets, view: FlightView,
         arrived: @escaping (Int) -> Void, failed: @escaping () -> Void, seed: Int = 0,
         activity: @escaping (Bool) -> Void = { _ in }, location: @escaping (String?) -> Void = { _ in }) {
        self.world = world; self.assets = assets; self.view = view; self.seed = seed; self.activity = activity
        self.arrived = arrived; self.failed = failed; self.location = location; active = index
        region = Region.from(index,count:world.biomes.count,seed:seed)
        stream = Stream(world:world,assets:assets,seed:seed,failed:failed)
        let camera = tile.rootNode.childNode(withName:"camera",recursively:false)!
        let p = region.origin
        stream.update(at:.init(camera.position.x+p.x,camera.position.y,camera.position.z+p.z),build:false)
        scene.rootNode.addChildNode(stream.root)
        let hovering = camera.action(forKey:"journey") != nil, home = camera.position
        camera.removeAllActions()
        attach(tile,region:region)
        scene.rootNode.addChildNode(camera); camera.position = .init(home.x+p.x,home.y+world.biomes[index].level,home.z+p.z)
        view.scene = scene; view.pointOfView = camera; view.atlas = self
        view.install(camera,area:world.biomes[index])
        if hovering { Landscape.focus(scene,world:world,biome:active,animated:true,preserving:true) }
        distance(8); update(ProcessInfo.processInfo.systemUptime); prefetch()
    }

    func animate(_ enabled: Bool) {
        guard !disposed, paused != !enabled || enabled != (timer != nil) else { return }
        paused = !enabled; stream.pause(!enabled)
        if !enabled {
            for operation in operations.values { operation.cancel() }
            operations = [:]; prefetched = nil
        } else { prefetch() }
        timer?.invalidate(); timer = nil; last = nil
        if enabled {
            let timer = Timer(timeInterval:1.0/30,repeats:true) { [weak self] _ in self?.update(ProcessInfo.processInfo.systemUptime) }
            self.timer = timer; RunLoop.main.add(timer,forMode:.common)
        }
    }

    static func columns(_ count: Int) -> Int { min(5,Int(ceil(sqrt(Double(count))))) }
    static func offset(_ index: Int, count: Int) -> SCNVector3 { Region.from(index,count:count).origin }

    static func habitat(at point: SCNVector3, world: World, seed: Int = 0) -> Int {
        guard let region = Region.at(point,seed:seed) else { return 0 }
        let index = region.biome(world), area = world.biomes[index]
        if point.y >= -16, let cover = area.cover { return world.biomes.firstIndex(of:cover) ?? index }
        return index
    }

    static func elevation(_ index: Int, world: World) -> Double { world.biomes[world.index(index)].level }

    static func index(at point: SCNVector3, count: Int) -> Int? {
        guard let region = Region.at(point) else { return nil }
        let key = region.key(count)
        return key>=0 ? key : nil
    }

    static func neighbours(_ index: Int, count: Int) -> [Int] {
        Region.from(index,count:count).neighbours.map { $0.key(count) }.filter { $0>=0 }
    }

    private func logical(_ point: SCNVector3) -> SCNVector3 { .init(point.x+origin.x,point.y,point.z+origin.z) }
    private func local(_ point: SCNVector3) -> SCNVector3 { .init(point.x-origin.x,point.y,point.z-origin.z) }
    private func offset(_ region: Region) -> SCNVector3 {
        let p = local(region.origin)
        return .init(p.x,world.biomes[region.biome(world)].level,p.z)
    }

    private func publish() {
        let title = region.historical(world) ? (logicalPosition.map(stream.contains) == true
            ? "Far Lands — historical recreation" : "Far Lands — loading terrain") : nil
        guard !hasPublished || title != published else { return }
        published = title; hasPublished = true; publication += 1
        let request = publication
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.disposed, self.publication == request else { return }
            self.location(title)
        }
    }

    func distance(_ chunks: Int) {
        let next = min(16,max(4,chunks))
        if next != renderDistance { renderDistance = next; stream.distance(next) }
        view?.pointOfView?.camera?.zFar = Double(next*16+32)
        if let camera = view?.pointOfView { stream.update(at:logical(camera.worldPosition)) }
    }

    private func wanted() -> [Region] {
        let eye = view?.pointOfView.map { logical($0.worldPosition) } ?? region.origin
        var result = [region]
        if let destination, destination != region,
           let next = region.neighbours.min(by:{ abs($0.x-destination.x)+abs($0.z-destination.z)<abs($1.x-destination.x)+abs($1.z-destination.z) }) {
            result.append(next)
        }
        let candidates = (-1...1).flatMap { x in (-1...1).map { Region(x:region.x+x,z:region.z+$0,seed:seed) } }
        func distance(_ r: Region) -> Double {
            let p = r.origin
            let x = max(0,max(p.x+Double(Region.xRange.lowerBound)-0.5-eye.x,eye.x-p.x-Double(Region.xRange.upperBound)+0.5))
            let z = max(0,max(p.z+Double(Region.zRange.lowerBound)-0.5-eye.z,eye.z-p.z-Double(Region.zRange.upperBound)+0.5))
            return x*x+z*z
        }
        for next in candidates.sorted(by:{ distance($0) == distance($1) ? $0.key(world.biomes.count)<$1.key(world.biomes.count) : distance($0)<distance($1) }) {
            if !result.contains(next) { result.append(next) }
            if result.count == 5 { break }
        }
        return result
    }

    private func attach(_ tile: SCNScene, region next: Region) {
        let index = next.key(world.biomes.count)
        if tiles[index] == nil && tiles.count>=5 {
            let desired = Set(wanted().map { $0.key(world.biomes.count) })
            func distance(_ index: Int) -> Int {
                let r = Region.from(index,count:world.biomes.count,seed:seed)
                return abs(r.x-region.x)+abs(r.z-region.z)
            }
            guard let obsolete = tiles.keys.filter({ !desired.contains($0) }).max(by:{ distance($0)<distance($1) }) else { return }
            tiles.removeValue(forKey:obsolete)?.rootNode.removeFromParentNode(); homes[obsolete] = nil
        }
        let root = tile.rootNode
        if let camera = root.childNode(withName:"camera",recursively:false) {
            homes[index] = camera.position
            camera.removeFromParentNode()
        }
        stream.adopt(tile,region:next)
        if next.historical(world) {
            for child in root.childNodes where child.light == nil && !(child is Daylight) && child.name != "drifting-cloud" && child.camera == nil {
                child.removeFromParentNode()
            }
        }
        root.position = offset(next); tiles[index] = tile; scene.rootNode.addChildNode(root)
        doors = Door.collect(scene.rootNode); lighting()
    }

    private func lighting() {
        let visible = tiles[key] != nil ? key : tiles.keys.min {
            let a = Region.from($0,count:world.biomes.count,seed:seed), b = Region.from($1,count:world.biomes.count,seed:seed)
            return abs(a.x-region.x)+abs(a.z-region.z)<abs(b.x-region.x)+abs(b.z-region.z)
        }
        for (index,tile) in tiles {
            for node in tile.rootNode.childNodes where node.light != nil || node is Daylight || node.name == "drifting-cloud" { node.isHidden = index != visible }
        }
    }

    private func prefetch() {
        guard !paused, !disposed else { return }
        let desired = wanted(), wanted = Set(desired.map { $0.key(world.biomes.count) })
        for index in Array(operations.keys) where !wanted.contains(index) { operations.removeValue(forKey:index)?.cancel() }
        for next in desired {
            let index = next.key(world.biomes.count)
            guard tiles[index] == nil && operations[index] == nil else { continue }
            operations[index] = assets.load(world,biome:next.biome(world),passage:nil,region:next,terrain:false) { [weak self] result in
                guard let self else { return }
                self.operations[index] = nil
                switch result {
                case .success(let tile): self.attach(tile,region:next)
                case .failure: self.cancelTravel(); self.failed()
                }
            }
        }
    }

    func constrain(_ point: SCNVector3) -> SCNVector3 {
        guard let camera = view?.pointOfView else { return point }
        return local(stream.constrain(logical(point),from:logical(camera.worldPosition)))
    }

    private func navigate(_ enabled: Bool) {
        guard enabled != travelling else { return }
        travelling = enabled; navigation += 1
        let request = navigation, callback = activity
        DispatchQueue.main.async { [self] in
            guard navigation == request else { return }
            callback(enabled)
        }
    }

    func cancelTravel() {
        destination = nil; points = []; speed = 0; blocked = 0; emergence = nil
        navigate(false)
    }

    func resume() {
        cancelTravel()
        Landscape.focus(scene,world:world,biome:active,animated:true,preserving:true)
    }

    func visit(_ index: Int) {
        let next = Region.from(world.index(index),count:world.biomes.count,seed:seed)
        if region.historical(world) {
            let p = next.origin, eye = Landscape.pose(world.biomes[world.index(index)],at:0).eye
            relocate(to:.init(p.x+eye.x,eye.y+world.biomes[world.index(index)].level,p.z+eye.z)); return
        }
        destination = next; points = []; blocked = 0; emergence = nil
        if let eye = view?.pointOfView?.worldPosition, world == .overworld,
           !world.biomes[active].underground, world.biomes[active].passage == nil {
            let floor = Terrain.sample(world:world,at:logical(eye),seed:seed).height
            if eye.y<floor+0.3 { emergence = floor+0.31 }
        }
        navigate(true); view?.pointOfView?.removeAllActions()
        prefetch()
        if next == region { route(to:next) }
    }

    func visitFarLands() {
        guard world == .overworld else { return }
        relocate(to:.init(Double(Region.farLands-32),80,0))
        if let camera = view?.pointOfView { camera.look(at:local(.init(Double(Region.farLands+64),75,0)),up:.init(0,1,0),localFront:.init(0,0,-1)) }
        if view?.exploring == false { Landscape.focus(scene,world:world,biome:active,animated:true,preserving:true) }
    }

    private func relocate(to point: SCNVector3) {
        guard let next = Region.at(point,seed:seed), let camera = view?.pointOfView else { return }
        cancelTravel(); camera.removeAllActions(); scene.rootNode.addChildNode(camera)
        for operation in operations.values { operation.cancel() }
        operations = [:]
        for index in Array(tiles.keys) {
            let old = Region.from(index,count:world.biomes.count,seed:seed)
            if abs(old.x-next.x)>1 || abs(old.z-next.z)>1 {
                tiles.removeValue(forKey:index)?.rootNode.removeFromParentNode(); homes[index] = nil
            }
        }
        region = next; active = Self.habitat(at:point,world:world,seed:seed)
        rebase(to:next.origin); camera.position = local(point)
        stream.update(at:point); prefetched = nil; lighting(); prefetch()
        view?.install(camera,area:world.biomes[active]); arrived(active)
        publish()
    }

    private func rebase(to next: SCNVector3) {
        guard next.x != origin.x || next.z != origin.z else { return }
        let delta = SCNVector3(next.x-origin.x,0,next.z-origin.z)
        if let camera = view?.pointOfView {
            var transform = camera.simdWorldTransform
            scene.rootNode.addChildNode(camera)
            transform.columns.3.x -= Float(delta.x); transform.columns.3.z -= Float(delta.z)
            camera.simdWorldTransform = transform
        }
        points = points.map { .init($0.x-delta.x,$0.y,$0.z-delta.z) }
        origin = next
        for (index,tile) in tiles { tile.rootNode.position = offset(Region.from(index,count:world.biomes.count,seed:seed)) }
        stream.rebase(next)
    }

    private func settle() {
        cancelTravel()
        if let view {
            view.install(view.pointOfView,area:world.biomes[active])
            if !view.exploring { Landscape.focus(scene,world:world,biome:active,animated:true,preserving:true) }
        }
    }

    private func route(to next: Region) {
        let index = next.key(world.biomes.count)
        guard let camera = view?.pointOfView, let home = homes[index] else { return }
        let a = camera.worldPosition, p = offset(next), end = SCNVector3(home.x+p.x,home.y+p.y,home.z+p.z)
        func shaft(_ region: Region) -> (above: SCNVector3, below: SCNVector3) {
            let p = region.origin, x = p.x+36, z = p.z+20
            let cover = Terrain.sample(world:world,at:.init(x,100,z),seed:seed).height
            let floor = Terrain.sample(world:world,at:.init(x,-56,z),seed:seed).height
            return (local(.init(x,cover+3,z)),local(.init(x,floor+3,z)))
        }
        if world.biomes[next.biome(world)].level<0 || world.biomes[region.biome(world)].level<0 && a.y < -16 {
            var route: [SCNVector3] = []
            if world.biomes[region.biome(world)].level<0 && a.y < -16 {
                let exit = shaft(region); route += [exit.below,exit.above]
            }
            let start = route.last ?? a, height = max(40,start.y)
            route.append(.init(start.x,height,start.z))
            if world.biomes[next.biome(world)].level<0 {
                let entrance = shaft(next)
                route += [.init(entrance.above.x,height,entrance.above.z),entrance.above,entrance.below,end]
            } else { route += [.init(end.x,height,end.z),end] }
            points = route; return
        }
        if hypot(end.x-a.x,end.z-a.z)<12 && Collision.clear(scene.rootNode,from:a,to:end,radius:0.35) { points = [end]; return }
        let underground = world == .nether || world.biomes[active].underground
        func elevation(_ p: SCNVector3) -> Double {
            let ground = Terrain.sample(world:world,at:logical(p),seed:seed).height
            return underground ? max(ground+3,8) : Collision.surface(scene.rootNode,at:p,ground:ground)+3
        }
        var launch = a, landing = end
        if !underground {
            func column(_ eye: SCNVector3) -> SCNVector3 {
                let top = SCNVector3(eye.x,max(eye.y,elevation(eye)),eye.z)
                if Collision.clear(scene.rootNode,from:eye,to:top,radius:0.35) { return eye }
                for step in 1...32 {
                    let angle = Double(step)*2.4, radius = sqrt(Double(step))*2
                    let candidate = SCNVector3(eye.x+cos(angle)*radius,eye.y,eye.z+sin(angle)*radius)
                    let above = SCNVector3(candidate.x,max(eye.y,elevation(candidate)),candidate.z)
                    if Collision.clear(scene.rootNode,from:eye,to:candidate,radius:0.35)
                        && Collision.clear(scene.rootNode,from:candidate,to:above,radius:0.35) { return candidate }
                }
                return eye
            }
            launch = emergence == nil ? column(a) : a; landing = column(end)
        }
        var cruise = [SCNVector3(launch.x,max(launch.y,elevation(launch)),launch.z)]
        let distance = hypot(landing.x-launch.x,landing.z-launch.z), steps = max(1,Int(ceil(distance/8)))
        for step in 1...steps {
            let t = Double(step)/Double(steps)
            var p = SCNVector3(launch.x+(landing.x-launch.x)*t,0,launch.z+(landing.z-launch.z)*t)
            p.y = max(elevation(p),max(a.y,end.y)+1); cruise.append(p)
        }
        if !underground {
            for index in 1..<cruise.count {
                let a = cruise[index-1], b = cruise[index]
                let top = Collision.clearance(scene.rootNode,from:a,to:b,ground:max(a.y,b.y)-3)+3
                cruise[index-1].y = max(a.y,top); cruise[index].y = max(b.y,top)
            }
        }
        for index in stride(from:cruise.count-2,through:0,by:-1) {
            let p = cruise[index], next = cruise[index+1]
            cruise[index].y = max(p.y,next.y-hypot(p.x-next.x,p.z-next.z)*0.3)
        }
        for index in 1..<cruise.count {
            let p = cruise[index], previous = cruise[index-1]
            cruise[index].y = max(p.y,previous.y-hypot(p.x-previous.x,p.z-previous.z)*0.3)
        }
        points = (SCNVector3EqualToVector3(launch,a) ? [] : [launch])+cruise
        if !SCNVector3EqualToVector3(landing,end) { points.append(landing) }
        points.append(end)
    }

    func update(_ time: Double) {
        guard !disposed, let view, let camera = view.pointOfView else { return }
        let dt = min(0.1,max(0,time-(last ?? time))); last = time
        if let destination, stream.contains(logical(camera.worldPosition)) {
            if points.isEmpty {
                if destination == region && active == destination.biome(world) { settle() }
                else if destination == region { route(to:destination) }
                else if let next = region.neighbours.min(by:{ abs($0.x-destination.x)+abs($0.z-destination.z)<abs($1.x-destination.x)+abs($1.z-destination.z) }), tiles[next.key(world.biomes.count)] != nil { route(to:next) }
            }
            if let target = points.first {
                let start = camera.worldPosition, delta = SIMD3<Double>(target.x-start.x,target.y-start.y,target.z-start.z), distance = simd_length(delta)
                if distance<0.15 { points.removeFirst() }
                else if dt>0 {
                    for door in doors { door.approach(start) }
                    let targetSpeed = points.count == 1 ? min(12,max(1.5,sqrt(distance*8))) : 12
                    speed += max(-8*dt,min(5*dt,targetSpeed-speed))
                    let p = SIMD3<Double>(start.x,start.y,start.z)+delta/distance*min(distance,speed*dt)
                    let candidate = SCNVector3(p.x,p.y,p.z), limited = constrain(candidate)
                    let next: SCNVector3
                    if let ceiling = emergence, start.y<ceiling, limited.y>start.y,
                       abs(limited.x-start.x)<0.0001, abs(limited.z-start.z)<0.0001 {
                        let rising = SCNVector3(start.x,min(ceiling,limited.y),start.z)
                        // Landmark graphs retain every structure while streamed sections own the terrain being exited
                        let clear = tiles.values.allSatisfy { tile in
                            let root = tile.rootNode, from = root.convertPosition(start,from:scene.rootNode)
                            return Collision.vacant(root,at:from,radius:0.3) && Collision.clear(root,from:from,
                                to:root.convertPosition(rising,from:scene.rootNode),radius:0.3)
                        }
                        if clear {
                            if rising.y>=ceiling {
                                emergence = nil
                                next = Collision.move(scene.rootNode,from:rising,to:limited,radius:0.3)
                            } else { next = rising }
                        } else { next = start }
                    } else {
                        emergence = nil
                        next = Collision.move(scene.rootNode,from:start,to:limited,radius:0.3)
                    }
                    camera.worldPosition = next
                    let ahead = points.first { hypot($0.x-next.x,$0.z-next.z)>4 }
                    let global = logical(next), r = Region.at(global,seed:seed) ?? region, base = offset(r)
                    let landmark = Landscape.pose(world.biomes[r.biome(world)],at:0).aim
                    let aim = ahead ?? .init(landmark.x+base.x,landmark.y+base.y,landmark.z+base.z)
                    let orientation = camera.simdOrientation
                    camera.look(at:aim,up:.init(0,1,0),localFront:.init(0,0,-1))
                    let target = camera.simdOrientation
                    let angle = 2*acos(min(1,abs(simd_dot(orientation.vector,target.vector))))
                    camera.simdOrientation = simd_slerp(orientation,target,min(1,Float(dt * .pi/4)/max(0.0001,angle)))
                    if hypot(next.x-start.x,next.z-start.z)+abs(next.y-start.y)<0.001 && stream.contains(logical(candidate)) { blocked += dt }
                    else { blocked = 0 }
                    if blocked>=1.5 { cancelTravel() }
                }
            }
        }
        let global = logical(camera.worldPosition)
        if let next = Region.at(global,seed:seed), next != region || Self.habitat(at:global,world:world,seed:seed) != active {
            let hovering = camera.action(forKey:"journey") != nil
            region = next; active = Self.habitat(at:global,world:world,seed:seed)
            if abs(global.x-origin.x)>Self.span*2 || abs(global.z-origin.z)>Self.span*2 { rebase(to:next.origin) }
            if hovering { Landscape.focus(scene,world:world,biome:active,animated:true,preserving:true) }
            if destination == nil { view.install(camera,area:world.biomes[active]) }
            lighting(); prefetched = nil
            arrived(active)
        }
        let chunk = Chunk(at:logical(camera.worldPosition))
        if prefetched != chunk {
            for (index,tile) in tiles { stream.register(tile,region:Region.from(index,count:world.biomes.count,seed:seed)) }
        }
        stream.update(at:logical(camera.worldPosition))
        if prefetched != chunk { prefetched = chunk; prefetch() }
        publish()
        for door in doors { door.approach(camera.worldPosition) }
        let p = logical(camera.worldPosition), base = region.origin, eye = SCNVector3(p.x-base.x,p.y-world.biomes[region.biome(world)].level,p.z-base.z)
        if time-environment >= 0.1 || environment<0 || time<environment, let tile = tiles[key] {
            let seconds = ProcessInfo.processInfo.systemUptime-assets.started
            Daylight.apply(tile,area:world.biomes[active],seconds:seconds,eye:eye)
            stream.illuminate(world == .overworld && !world.biomes[active].underground ? Daylight.light(at:seconds) : 1)
            let target = world.biomes[active].underground ? Landscape.colour(world.biomes[active].sky) : tile.background.contents as? NSColor
            if let target, let current = scene.background.contents as? NSColor, environment>=0 {
                scene.background.contents = current.blended(withFraction:min(1,max(0,time-environment)*1.5),of:target) ?? target
            } else if let target { scene.background.contents = target }
            else { scene.background.contents = tile.background.contents }
            environment = time; scene.fogColor = scene.background.contents as? NSColor ?? Landscape.colour(world.biomes[active].sky)
            if world.biomes[active].underground {
                tile.rootNode.childNode(withName:"sunlight",recursively:false)?.light?.intensity = 300
                tile.rootNode.childNode(withName:"skylight",recursively:false)?.light?.intensity = 250
            }
        }
        let medium = SCNVector3(eye.x,p.y-world.biomes[active].level,eye.z)
        let submerged = medium.y<0.9 && Terrain.sample(world:world,at:p,seed:seed).fluid
        Landscape.medium(scene,area:world.biomes[active],eye:medium,submerged:submerged)
        if !submerged {
            scene.fogStartDistance = Double(renderDistance*16)*0.6; scene.fogEndDistance = Double(renderDistance*16)
        }
        if time-reported >= 0.1 || reported<0 || time<reported {
            reported = time; view.report?(logical(camera.worldPosition),Double(camera.eulerAngles.y))
        }
    }

    func dispose() {
        cancelTravel(); disposed = true; publication += 1
        for operation in operations.values { operation.cancel() }
        timer?.invalidate(); timer = nil; operations = [:]; tiles = [:]; homes = [:]; doors = []; stream.dispose()
        for node in scene.rootNode.childNodes { node.removeFromParentNode() }
        view?.atlas = nil; view = nil
    }
}

struct Adventure: NSViewRepresentable {
    let world: World
    let biome: Int
    let moving: Bool
    let passage: Passage?
    let assets: Assets
    let exploring: Bool
    let travel: (Int) -> Void
    let arrived: (Int) -> Void
    let finish: () -> Void
    var renderDistance: Int = 8
    var seed: Int = 0
    var farLands: Int = 0
    var location: (String?) -> Void = { _ in }
    var activity: (Bool) -> Void = { _ in }
    var report: ((SCNVector3,Double) -> Void)?
    var sensitivity: Double = 50
    var inverted = false
    var controls = Controls()
    var active = true
    var resolution: (Double) -> Void = { _ in }
    let failed: () -> Void

    final class Coordinator: NSObject {
        weak var view: FlightView?
        var exploring = false
        var world: World?
        var biome: Int?
        var passage: Passage?
        var showing: (World,Int)?
        var moving = false
        var active = true
        var request = 0
        var operation: Operation?
        var atlas: Atlas?
        var renderDistance = 8
        var seed: Int?
        var command = 0
        var farLands = 0
        var location: (String?) -> Void = { _ in }

        @objc func pan(_ gesture: NSPanGestureRecognizer) {
            guard exploring, let view, !view.captured else { return }
            if gesture.state == .began { view.window?.makeFirstResponder(view) }
            let movement = gesture.translation(in:view)
            view.aim(x:Float(movement.x),y:Float(movement.y))
            gesture.setTranslation(.zero,in:view)
            view.needsDisplay = true
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> FlightView {
        let view = FlightView(frame: .zero)
        view.backgroundColor = .clear
        view.preferredFramesPerSecond = 30
        view.antialiasingMode = .none
        view.allowsCameraControl = false
        view.addGestureRecognizer(NSPanGestureRecognizer(target:context.coordinator,action:#selector(Coordinator.pan(_:))))
        context.coordinator.view = view
        return view
    }

    func updateNSView(_ view: FlightView, context: Context) {
        let coordinator = context.coordinator
        view.resolution = resolution
        view.materials = moving ? { [weak assets] time in if let assets {assets.animate(at:time-assets.started)} } : nil
        view.preferredFramesPerSecond = exploring ? 60 : 30
        view.travel = travel; view.finish = finish
        view.report = exploring ? report : nil
        view.sensitivity = Float(min(100,max(1,sensitivity)))*0.003
        view.inverted = inverted
        view.controls = controls
        coordinator.moving = moving
        coordinator.active = active
        coordinator.renderDistance = renderDistance; coordinator.command = farLands; coordinator.location = location
        if coordinator.exploring != exploring {
            coordinator.exploring = exploring
            view.exploring = exploring
            if let scene = view.scene, passage == nil {
                if exploring { view.pointOfView?.removeAllActions(); coordinator.atlas?.cancelTravel() }
                else if let atlas = coordinator.atlas { atlas.resume() }
                else { Landscape.focus(scene,world:coordinator.showing?.0 ?? world,biome:coordinator.showing?.1 ?? biome,animated:moving,preserving:true) }
            }
        }
        if let atlas = coordinator.atlas, coordinator.world == world, coordinator.seed == seed, passage == nil, coordinator.passage == nil {
            if coordinator.biome != biome { coordinator.biome = biome; atlas.visit(biome) }
            atlas.distance(renderDistance)
            if coordinator.farLands != farLands { coordinator.farLands = farLands; atlas.visitFarLands() }
            Self.motion(view,enabled:moving,active:active)
            return
        }
        if coordinator.world != world || coordinator.seed != seed || coordinator.passage != passage
            || (passage == nil && coordinator.biome != biome) {
            coordinator.operation?.cancel()
            coordinator.atlas?.dispose(); coordinator.atlas = nil
            coordinator.request += 1
            let request = coordinator.request
            let arrival = passage == nil ? coordinator.passage : nil
            coordinator.world = world
            coordinator.seed = seed
            coordinator.biome = biome
            coordinator.passage = passage
            view.prepare()
            let region = Region.from(world.index(biome),count:world.biomes.count,seed:seed)
            coordinator.operation = assets.load(world, biome: biome, passage: passage, arrival:arrival,region:region) { [weak view, weak coordinator] result in
                guard let view, let coordinator, coordinator.request == request else { return }
                switch result {
                case .success(let scene):
                    if passage == nil {
                        coordinator.atlas = Atlas(world:world,index:world.index(biome),tile:scene,assets:assets,view:view,
                            arrived:{ [weak coordinator] index in coordinator?.biome = index; coordinator?.showing = (world,index); arrived(index) },failed:failed,seed:seed,activity:activity,
                            location:{ [weak coordinator] title in coordinator?.location(title) })
                        coordinator.atlas?.distance(coordinator.renderDistance)
                        if coordinator.farLands != coordinator.command { coordinator.farLands = coordinator.command; coordinator.atlas?.visitFarLands() }
                        coordinator.showing = (world,biome)
                        if coordinator.exploring { view.pointOfView?.removeAllActions() }
                        Self.motion(view,enabled:coordinator.moving,active:coordinator.active)
                        return
                    }
                    let camera = scene.rootNode.childNode(withName:"camera",recursively:false)
                    if coordinator.exploring { camera?.removeAllActions() }
                    if coordinator.moving, !coordinator.exploring, view.scene != nil {
                        let transition = arrival == nil ? SKTransition.fade(withDuration:0.3)
                            : SKTransition.fade(with:Landscape.colour(arrival == .stronghold ? 0x080810 : 0x7024B8),duration:0.9)
                        view.present(scene,with:transition,incomingPointOfView:camera,completionHandler:nil)
                    } else { view.scene = scene; view.pointOfView = camera }
                    coordinator.showing = (world,biome)
                    view.install(camera,area:world.biomes[world.index(biome)])
                    Self.motion(view,enabled:coordinator.moving,active:coordinator.active)
                case .failure: failed()
                }
            }
        }
        Self.motion(view,enabled:moving,active:active)
    }

    static func motion(_ view: SCNView, enabled: Bool, active: Bool = false) {
        // Deliberate flight still streams terrain when ambient motion is disabled
        (view as? FlightView)?.atlas?.animate(enabled || active && (view as? FlightView)?.exploring == true)
        view.scene?.isPaused = !enabled
        if let flight = view as? FlightView {flight.clock(enabled || active && flight.exploring)}
        else {view.isPlaying = enabled; view.rendersContinuously = enabled}
        view.needsDisplay = true
    }

    static func dismantleNSView(_ view: FlightView, coordinator: Coordinator) {
        coordinator.operation?.cancel()
        coordinator.atlas?.dispose(); coordinator.atlas = nil
        coordinator.request += 1
        motion(view, enabled: false)
        view.dispose()
        view.scene = nil
        view.gestureRecognizers.removeAll()
        coordinator.view = nil
    }
}
