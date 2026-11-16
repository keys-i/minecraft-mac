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
    let controller = SCNCameraController()
    var travel: ((Int) -> Void)?
    var finish: (() -> Void)?
    private(set) var keys: Set<UInt16> = []
    private(set) var speed: Float = 16
    private var descending = false
    private var sprinting = false
    private var mouse: Any?
    private weak var inputWindow: NSWindow?
    private var acceptedMouse = false
    private(set) var captured = false
    private var timer: Timer?
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

    override var acceptsFirstResponder: Bool { exploring }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        NotificationCenter.default.removeObserver(self,name:NSWindow.didResignKeyNotification,object:nil)
        stop(); release()
        if let window {
            NotificationCenter.default.addObserver(self,selector:#selector(lostFocus),name:NSWindow.didResignKeyNotification,object:window)
        }
    }

    override func resignFirstResponder() -> Bool { stop(); release(); return super.resignFirstResponder() }
    @objc private func lostFocus() { stop(); release() }

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
        controller.rotateBy(x:-x*0.15,y:y*0.15)
        needsDisplay = true
    }

    override func keyDown(with event: NSEvent) {
        guard exploring, !event.modifierFlags.contains(.command), !event.modifierFlags.contains(.option) else {
            super.keyDown(with:event); return
        }
        if event.keyCode == 53 { stop(); finish?(); return }
        if event.keyCode == 33 || event.keyCode == 30 {
            if !event.isARepeat { visit(event.keyCode == 33 ? -1 : 1) }
            return
        }
        guard [0,1,2,13,49,123,124,125,126].contains(event.keyCode) else { super.keyDown(with:event); return }
        keys.insert(event.keyCode)
        start()
    }

    override func keyUp(with event: NSEvent) {
        if keys.remove(event.keyCode) != nil { if keys.isEmpty && !descending { suspend() }; return }
        super.keyUp(with:event)
    }

    override func flagsChanged(with event: NSEvent) {
        guard exploring else { super.flagsChanged(with:event); return }
        descending = event.modifierFlags.contains(.shift)
        sprinting = event.modifierFlags.contains(.control)
        if descending { start() } else if keys.isEmpty { suspend() }
    }

    override func scrollWheel(with event: NSEvent) {
        guard exploring else { super.scrollWheel(with:event); return }
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

    func stop() { suspend(); keys.removeAll(); descending = false; sprinting = false }
    private func suspend() { timer?.invalidate(); timer = nil }

    private func start() {
        guard exploring, !loading, timer == nil, window?.isKeyWindow == true,
              !keys.isEmpty || descending else { return }
        last = ProcessInfo.processInfo.systemUptime
        let timer = Timer(timeInterval:1.0/60,target:self,selector:#selector(tick),userInfo:nil,repeats:true)
        self.timer = timer
        RunLoop.main.add(timer,forMode:.common)
    }

    @objc private func tick() {
        guard exploring, window?.isKeyWindow == true, window?.occlusionState.contains(.visible) == true,
              NSApp.isActive, !isHiddenOrHasHiddenAncestor else { stop(); release(); return }
        let now = ProcessInfo.processInfo.systemUptime
        advance(seconds:now-last); last = now
    }

    func advance(seconds: Double) {
        guard !loading, let camera = pointOfView else { return }
        let dt = Float(min(0.1,max(0,seconds)))
        func key(_ code: UInt16) -> Float { keys.contains(code) ? 1 : 0 }
        let local = SIMD4<Float>(key(2)-key(0),0,key(1)-key(13),0)
        let rotated = camera.simdWorldTransform*local
        var direction = SIMD3<Float>(rotated.x,rotated.y,rotated.z)
        direction.y += key(49)-(descending ? 1 : 0)
        if simd_length_squared(direction)>0, let scene {
            let next = camera.simdWorldPosition+simd_normalize(direction)*speed*(sprinting ? 2 : 1)*dt
            atlas?.cancelTravel()
            for door in doors { door.approach(camera.worldPosition) }
            let destination = atlas?.constrain(SCNVector3(next)) ?? SCNVector3(next)
            camera.worldPosition = Collision.move(scene.rootNode,from:camera.worldPosition,to:destination)
        }
        camera.position.y = min(90,max(-28,camera.position.y))
        if atlas == nil, let scene { Landscape.medium(scene,area:area,eye:camera.position) }
        let yaw = key(124)-key(123), pitch = key(126)-key(125)
        if yaw != 0 || pitch != 0 { controller.rotateBy(x:-yaw*70*dt,y:pitch*70*dt) }
        needsDisplay = true
    }

    func visit(_ step: Int) {
        if let atlas { atlas.visit(atlas.active+step); return }
        guard !loading else { return }
        travel?(step)
    }

    func dispose() {
        stop(); release(); atlas = nil; doors = []; travel = nil; finish = nil; controller.pointOfView = nil
        NotificationCenter.default.removeObserver(self)
    }
}

// Authored landmarks share a bounded cache while terrain streams through a floating origin
final class Atlas {
    static let span = Double(Region.span)
    let world: World
    let assets: Assets
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
    private let stream: Stream
    private var destination: Region?
    private var points: [SCNVector3] = []
    private var last: Double?
    private var environment = -1.0
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
         arrived: @escaping (Int) -> Void, failed: @escaping () -> Void, location: @escaping (String?) -> Void = { _ in }) {
        self.world = world; self.assets = assets; self.view = view
        self.arrived = arrived; self.failed = failed; self.location = location; active = index
        region = Region.from(index,count:world.biomes.count)
        stream = Stream(world:world,assets:assets,failed:failed)
        let camera = tile.rootNode.childNode(withName:"camera",recursively:false)!
        let p = region.origin
        stream.update(at:.init(camera.position.x+p.x,camera.position.y,camera.position.z+p.z),build:false)
        scene.rootNode.addChildNode(stream.root)
        let hovering = camera.action(forKey:"journey") != nil, home = camera.position
        camera.removeAllActions()
        attach(tile,region:region)
        scene.rootNode.addChildNode(camera); camera.position = .init(home.x+p.x,home.y,home.z+p.z)
        view.scene = scene; view.pointOfView = camera; view.atlas = self
        view.install(camera,area:world.biomes[index])
        if hovering { Landscape.focus(scene,world:world,biome:active,animated:true,preserving:true) }
        distance(8); update(ProcessInfo.processInfo.systemUptime); prefetch()
    }

    func animate(_ enabled: Bool) {
        guard !disposed else { return }
        paused = !enabled; stream.pause(!enabled)
        if !enabled {
            for operation in operations.values { operation.cancel() }
            operations = [:]; prefetched = nil
        } else { prefetch() }
        guard enabled != (timer != nil) else { return }
        timer?.invalidate(); timer = nil; last = nil
        if enabled {
            let timer = Timer(timeInterval:1.0/30,repeats:true) { [weak self] _ in self?.update(ProcessInfo.processInfo.systemUptime) }
            self.timer = timer; RunLoop.main.add(timer,forMode:.common)
        }
    }

    static func columns(_ count: Int) -> Int { Int(ceil(sqrt(Double(count)))) }
    static func offset(_ index: Int, count: Int) -> SCNVector3 { Region.from(index,count:count).origin }

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
    private func offset(_ region: Region) -> SCNVector3 { local(region.origin) }

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
        let candidates = (-1...1).flatMap { x in (-1...1).map { Region(x:region.x+x,z:region.z+$0) } }
        func distance(_ r: Region) -> Double {
            let p = r.origin
            let x = max(0,max(p.x-96.5-eye.x,eye.x-p.x-95.5))
            let z = max(0,max(p.z-128.5-eye.z,eye.z-p.z-63.5))
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
                let r = Region.from(index,count:world.biomes.count)
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
            let a = Region.from($0,count:world.biomes.count), b = Region.from($1,count:world.biomes.count)
            return abs(a.x-region.x)+abs(a.z-region.z)<abs(b.x-region.x)+abs(b.z-region.z)
        }
        for (index,tile) in tiles {
            for node in tile.rootNode.childNodes where node.light != nil || node is Daylight || node.name == "drifting-cloud" { node.isHidden = index != visible }
        }
        environment = -1
    }

    private func prefetch() {
        guard !paused, !disposed else { return }
        let desired = wanted(), wanted = Set(desired.map { $0.key(world.biomes.count) })
        for index in Array(operations.keys) where !wanted.contains(index) { operations.removeValue(forKey:index)?.cancel() }
        for next in desired {
            let index = next.key(world.biomes.count)
            guard tiles[index] == nil && operations[index] == nil else { continue }
            operations[index] = assets.load(world,biome:next.biome(world),passage:nil) { [weak self] result in
                guard let self else { return }
                self.operations[index] = nil
                switch result {
                case .success(let tile): self.attach(tile,region:next)
                case .failure: self.cancelTravel(); self.failed()
                }
            }
        }
        doors = Door.collect(scene.rootNode)
    }

    func constrain(_ point: SCNVector3) -> SCNVector3 {
        guard let camera = view?.pointOfView else { return point }
        return local(stream.constrain(logical(point),from:logical(camera.worldPosition)))
    }

    func cancelTravel() { destination = nil; points = [] }

    func resume() {
        cancelTravel()
        Landscape.focus(scene,world:world,biome:active,animated:true,preserving:true)
    }

    func visit(_ index: Int) {
        let next = Region.from(world.index(index),count:world.biomes.count)
        if region.historical(world) {
            let p = next.origin, eye = Landscape.pose(world.biomes[world.index(index)],at:0).eye
            relocate(to:.init(p.x+eye.x,eye.y,p.z+eye.z)); return
        }
        destination = next; points = []; view?.pointOfView?.removeAllActions()
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
        guard let next = Region.at(point), let camera = view?.pointOfView else { return }
        cancelTravel(); camera.removeAllActions(); scene.rootNode.addChildNode(camera)
        for operation in operations.values { operation.cancel() }
        operations = [:]
        for index in Array(tiles.keys) {
            let old = Region.from(index,count:world.biomes.count)
            if abs(old.x-next.x)>1 || abs(old.z-next.z)>1 {
                tiles.removeValue(forKey:index)?.rootNode.removeFromParentNode(); homes[index] = nil
            }
        }
        region = next; active = next.biome(world)
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
        for (index,tile) in tiles { tile.rootNode.position = offset(Region.from(index,count:world.biomes.count)) }
        stream.rebase(next)
    }

    private func settle() {
        destination = nil; points = []
        if let view, !view.exploring { Landscape.focus(scene,world:world,biome:active,animated:true,preserving:true) }
    }

    private func route(to next: Region) {
        let index = next.key(world.biomes.count)
        guard let camera = view?.pointOfView, let home = homes[index] else { return }
        let a = camera.worldPosition, p = offset(next), end = SCNVector3(home.x+p.x,home.y,home.z+p.z)
        if Collision.clear(scene.rootNode,from:a,to:end,radius:0.35) { points = [end]; return }
        let underground = world == .nether || world.biomes[active].underground
        func elevation(_ p: SCNVector3) -> Double {
            let global = logical(p), r = Region.at(global) ?? region, start = r.origin
            let terrain = Terrain(biome:world.biomes[r.biome(world)]), ground = terrain.height(global.x-start.x,global.z-start.z)
            return underground ? max(ground+3,8) : max(ground+14,40)
        }
        points = [.init(a.x,elevation(a),a.z)]
        let distance = hypot(end.x-a.x,end.z-a.z), steps = max(1,Int(ceil(distance/4)))
        for step in 1...steps {
            let t = Double(step)/Double(steps)
            var p = SCNVector3(a.x+(end.x-a.x)*t,0,a.z+(end.z-a.z)*t)
            p.y = max(elevation(p),max(a.y,end.y)+3); points.append(p)
        }
        points.append(end)
    }

    func update(_ time: Double) {
        guard !disposed, let view, let camera = view.pointOfView else { return }
        let dt = min(0.1,max(0,time-(last ?? time))); last = time
        if let destination {
            if points.isEmpty {
                if destination == region { settle() }
                else if let next = region.neighbours.min(by:{ abs($0.x-destination.x)+abs($0.z-destination.z)<abs($1.x-destination.x)+abs($1.z-destination.z) }), tiles[next.key(world.biomes.count)] != nil { route(to:next) }
            }
            if let target = points.first {
                let start = camera.worldPosition, delta = SIMD3<Double>(target.x-start.x,target.y-start.y,target.z-start.z), distance = simd_length(delta)
                if distance<0.15 { points.removeFirst() }
                else if dt>0 {
                    for door in doors { door.approach(start) }
                    let p = SIMD3<Double>(start.x,start.y,start.z)+delta/distance*min(distance,32*dt)
                    let candidate = SCNVector3(p.x,p.y,p.z), limited = constrain(candidate)
                    let next = Collision.move(scene.rootNode,from:start,to:limited,radius:0.3)
                    camera.worldPosition = next
                    let ahead = points.first { hypot($0.x-next.x,$0.z-next.z)>4 }
                    let global = logical(next), r = Region.at(global) ?? region, base = offset(r)
                    let landmark = Landscape.pose(world.biomes[r.biome(world)],at:0).aim
                    let aim = ahead.map { SCNVector3($0.x,min(next.y,$0.y)-4,$0.z) } ?? .init(landmark.x+base.x,landmark.y,landmark.z+base.z)
                    camera.look(at:aim,up:.init(0,1,0),localFront:.init(0,0,-1))
                    if hypot(next.x-start.x,next.z-start.z)+abs(next.y-start.y)<0.001 && stream.contains(logical(candidate)) { cancelTravel() }
                }
            }
        }
        let global = logical(camera.worldPosition)
        if let next = Region.at(global), next != region {
            let hovering = camera.action(forKey:"journey") != nil
            region = next; active = next.biome(world)
            if abs(global.x-origin.x)>768 || abs(global.z-origin.z)>768 { rebase(to:next.origin) }
            if hovering { Landscape.focus(scene,world:world,biome:active,animated:true,preserving:true) }
            view.install(camera,area:world.biomes[active]); lighting(); prefetched = nil
            arrived(active)
        }
        let chunk = Chunk(at:logical(camera.worldPosition))
        if prefetched != chunk {
            for (index,tile) in tiles { stream.register(tile,region:Region.from(index,count:world.biomes.count)) }
        }
        stream.update(at:logical(camera.worldPosition))
        if prefetched != chunk { prefetched = chunk; prefetch() }
        publish()
        for door in doors { door.approach(camera.worldPosition) }
        let p = logical(camera.worldPosition), base = region.origin, eye = SCNVector3(p.x-base.x,p.y,p.z-base.z)
        if time-environment >= 0.1 || environment<0, let tile = tiles[key] {
            Daylight.apply(tile,area:world.biomes[active],seconds:ProcessInfo.processInfo.systemUptime-assets.started,eye:eye)
            environment = time; scene.background.contents = tile.background.contents; scene.fogColor = tile.fogColor
        }
        Landscape.medium(scene,area:world.biomes[active],eye:eye)
        if !(eye.y<0.9 && Terrain(biome:world.biomes[active]).height(eye.x.rounded(),eye.z.rounded())<0.9) {
            scene.fogStartDistance = Double(renderDistance*16)*0.6; scene.fogEndDistance = Double(renderDistance*16)
        }
    }

    func dispose() {
        disposed = true; publication += 1
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
    var farLands: Int = 0
    var location: (String?) -> Void = { _ in }
    let failed: () -> Void

    final class Coordinator: NSObject {
        weak var view: FlightView?
        var exploring = false
        var world: World?
        var biome: Int?
        var passage: Passage?
        var showing: (World,Int)?
        var moving = false
        var request = 0
        var operation: Operation?
        var atlas: Atlas?
        var renderDistance = 8
        var command = 0
        var farLands = 0
        var location: (String?) -> Void = { _ in }

        @objc func pan(_ gesture: NSPanGestureRecognizer) {
            guard exploring, let view, !view.captured else { return }
            if gesture.state == .began { view.window?.makeFirstResponder(view) }
            let movement = gesture.translation(in:view)
            view.controller.rotateBy(x:-Float(movement.x)*0.22,y:Float(movement.y)*0.22)
            gesture.setTranslation(.zero,in:view)
            view.needsDisplay = true
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> FlightView {
        let view = FlightView(frame: .zero)
        view.backgroundColor = .clear
        view.preferredFramesPerSecond = 30
        view.antialiasingMode = .multisampling4X
        view.allowsCameraControl = false
        view.addGestureRecognizer(NSPanGestureRecognizer(target:context.coordinator,action:#selector(Coordinator.pan(_:))))
        context.coordinator.view = view
        return view
    }

    func updateNSView(_ view: FlightView, context: Context) {
        let coordinator = context.coordinator
        view.preferredFramesPerSecond = exploring ? 60 : 30
        view.travel = travel; view.finish = finish
        coordinator.moving = moving
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
        if let atlas = coordinator.atlas, coordinator.world == world, passage == nil, coordinator.passage == nil {
            if coordinator.biome != biome { coordinator.biome = biome; atlas.visit(biome) }
            atlas.distance(renderDistance)
            if coordinator.farLands != farLands { coordinator.farLands = farLands; atlas.visitFarLands() }
            Self.motion(view,enabled:moving)
            return
        }
        if coordinator.world != world || coordinator.passage != passage
            || (passage == nil && coordinator.biome != biome) {
            coordinator.operation?.cancel()
            coordinator.atlas?.dispose(); coordinator.atlas = nil
            coordinator.request += 1
            let request = coordinator.request
            let arrival = passage == nil ? coordinator.passage : nil
            coordinator.world = world
            coordinator.biome = biome
            coordinator.passage = passage
            view.prepare()
            coordinator.operation = assets.load(world, biome: biome, passage: passage, arrival:arrival) { [weak view, weak coordinator] result in
                guard let view, let coordinator, coordinator.request == request else { return }
                switch result {
                case .success(let scene):
                    if passage == nil {
                        coordinator.atlas = Atlas(world:world,index:world.index(biome),tile:scene,assets:assets,view:view,
                            arrived:{ [weak coordinator] index in coordinator?.biome = index; coordinator?.showing = (world,index); arrived(index) },failed:failed,
                            location:{ [weak coordinator] title in coordinator?.location(title) })
                        coordinator.atlas?.distance(coordinator.renderDistance)
                        if coordinator.farLands != coordinator.command { coordinator.farLands = coordinator.command; coordinator.atlas?.visitFarLands() }
                        coordinator.showing = (world,biome)
                        if coordinator.exploring { view.pointOfView?.removeAllActions() }
                        Self.motion(view,enabled:coordinator.moving)
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
                    Self.motion(view, enabled: coordinator.moving)
                case .failure: failed()
                }
            }
        }
        Self.motion(view, enabled: moving)
    }

    private static func motion(_ view: SCNView, enabled: Bool) {
        (view as? FlightView)?.atlas?.animate(enabled)
        view.scene?.isPaused = !enabled
        view.isPlaying = enabled
        view.rendersContinuously = enabled
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
