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
    private(set) var speed: Float = 8
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
        speed = min(32,max(2,speed*pow(1.08,Float(max(-10,min(10,event.scrollingDeltaY))))))
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
        if let scene { Landscape.medium(scene,area:area,eye:camera.position) }
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

// A bounded neighbourhood shares one coordinate space and one moving camera
final class Atlas {
    static let span = 192.0
    let world: World
    let assets: Assets
    let scene = SCNScene()
    private(set) var active: Int
    private(set) var tiles: [Int:SCNScene] = [:]
    private var operations: [Int:Operation] = [:]
    private var homes: [Int:(SCNVector3,SCNVector3)] = [:]
    private weak var view: FlightView?
    private let arrived: (Int) -> Void
    private let failed: () -> Void
    private var destination: Int?
    private var points: [SCNVector3] = []
    private var last: Double?
    private var environment = -1.0
    private var timer: Timer?
    private var doors: [Door] = []

    init(world: World, index: Int, tile: SCNScene, assets: Assets, view: FlightView,
         arrived: @escaping (Int) -> Void, failed: @escaping () -> Void) {
        self.world = world; self.assets = assets; self.view = view
        self.arrived = arrived; self.failed = failed; active = index
        attach(tile,index:index)
        let camera = tile.rootNode.childNode(withName:"camera",recursively:false)!
        view.scene = scene; view.pointOfView = camera; view.atlas = self
        view.install(camera,area:world.biomes[index])
        update(ProcessInfo.processInfo.systemUptime)
        prefetch()
    }

    func animate(_ enabled: Bool) {
        guard enabled != (timer != nil) else { return }
        timer?.invalidate(); timer = nil; last = nil
        if enabled {
            let timer = Timer(timeInterval:1.0/30,repeats:true) { [weak self] _ in self?.update(ProcessInfo.processInfo.systemUptime) }
            self.timer = timer; RunLoop.main.add(timer,forMode:.common)
        }
    }

    static func index(at x: Double, count: Int) -> Int {
        min(count-1,max(0,Int(floor((x+96.5)/span))))
    }

    private func attach(_ tile: SCNScene, index: Int) {
        let root = tile.rootNode
        if let camera = root.childNode(withName:"camera",recursively:false) {
            homes[index] = (camera.position,camera.eulerAngles)
            if index != active { camera.removeFromParentNode() }
        }
        root.position.x = Double(index)*Self.span
        tiles[index] = tile; scene.rootNode.addChildNode(root)
        doors = Door.collect(scene.rootNode)
        lighting()
    }

    private func lighting() {
        for (index,tile) in tiles {
            for node in tile.rootNode.childNodes where node.light != nil || node is Daylight {
                node.isHidden = index != active
            }
        }
        environment = -1
    }

    private func prefetch() {
        let wanted = Set(max(0,active-1)...min(world.biomes.count-1,active+1))
        for index in Array(tiles.keys) where !wanted.contains(index) {
            tiles.removeValue(forKey:index)?.rootNode.removeFromParentNode(); homes[index] = nil
        }
        for index in Array(operations.keys) where !wanted.contains(index) { operations.removeValue(forKey:index)?.cancel() }
        for index in wanted.sorted() where tiles[index] == nil && operations[index] == nil {
            operations[index] = assets.load(world,biome:index,passage:nil) { [weak self] result in
                guard let self else { return }
                self.operations[index] = nil
                switch result {
                case .success(let tile): self.attach(tile,index:index)
                case .failure: self.cancelTravel(); self.failed()
                }
            }
        }
        doors = Door.collect(scene.rootNode)
    }

    func constrain(_ point: SCNVector3) -> SCNVector3 {
        var p = point
        let lower = tiles[active-1] == nil ? Double(active)*Self.span-95.5 : Double(active-1)*Self.span-95.5
        let upper = tiles[active+1] == nil ? Double(active)*Self.span+94.5 : Double(active+1)*Self.span+94.5
        p.x = min(upper,max(lower,p.x)); p.z = min(60,max(-124,p.z))
        return p
    }

    func cancelTravel() { destination = nil; points = [] }

    func visit(_ index: Int) {
        destination = world.index(index); points = []
        view?.pointOfView?.removeAllActions()
        if destination == active { route(to:active) }
    }

    private func settle() {
        guard let view, let tile = tiles[active] else { return }
        destination = nil; points = []
        if !view.exploring { Landscape.focus(tile,world:world,biome:active,animated:true) }
    }

    private func route(to next: Int) {
        guard let camera = view?.pointOfView, let home = homes[next] else { return }
        let a = camera.worldPosition
        let end = SCNVector3(home.0.x+Double(next)*Self.span,home.0.y,home.0.z)
        let underground = world == .nether || world.biomes[active].underground
        func elevation(_ x: Double) -> Double {
            let index = Self.index(at:x,count:world.biomes.count)
            let terrain = Terrain(biome:world.biomes[index]), ground = terrain.height(x-Double(index)*Self.span,44)
            return underground ? max(ground+3,8) : max(ground+14,40)
        }
        points = [.init(a.x,elevation(a.x),a.z),.init(a.x,elevation(a.x),44)]
        let distance = end.x-a.x, steps = max(1,Int(ceil(abs(distance)/4)))
        for step in 1...steps {
            let x = a.x+distance*Double(step)/Double(steps)
            points.append(.init(x,elevation(x),44))
        }
        points.append(.init(end.x,elevation(end.x),end.z)); points.append(end)
    }

    func update(_ time: Double) {
        guard let view, let camera = view.pointOfView else { return }
        let dt = min(0.1,max(0,time-(last ?? time))); last = time
        if let destination {
            if points.isEmpty {
                if destination == active { settle() }
                else {
                    let next = active+(destination>active ? 1 : -1)
                    if tiles[next] != nil { route(to:next) }
                }
            }
            if let target = points.first {
                let start = camera.worldPosition
                let delta = SIMD3<Double>(target.x-start.x,target.y-start.y,target.z-start.z)
                let distance = simd_length(delta)
                if distance<0.15 { points.removeFirst() }
                else if dt>0 {
                    for door in doors { door.approach(start) }
                    let p = SIMD3<Double>(start.x,start.y,start.z)+delta/distance*min(distance,32*dt)
                    let next = Collision.move(scene.rootNode,from:start,to:.init(p.x,p.y,p.z),radius:0.3)
                    camera.worldPosition = next
                    // Keep terrain in view while climbing or descending between habitats
                    let ahead = points.first { hypot($0.x-next.x,$0.z-next.z)>4 }
                    let index = Self.index(at:next.x,count:world.biomes.count)
                    let landmark = Landscape.pose(world.biomes[index],at:0).aim
                    let aim = ahead.map { SCNVector3($0.x,min(next.y,$0.y)-4,$0.z) }
                        ?? SCNVector3(landmark.x+Double(index)*Self.span,landmark.y,landmark.z)
                    camera.look(at:aim,up:.init(0,1,0),localFront:.init(0,0,-1))
                    if hypot(next.x-start.x,next.z-start.z)+abs(next.y-start.y)<0.001 { cancelTravel() }
                }
            }
        }
        let index = Self.index(at:camera.worldPosition.x,count:world.biomes.count)
        if index != active, let tile = tiles[index] {
            let transform = camera.simdWorldTransform
            tile.rootNode.addChildNode(camera)
            camera.simdWorldTransform = transform
            active = index
            view.install(camera,area:world.biomes[index])
            lighting(); prefetch(); arrived(index)
        }
        for door in doors { door.approach(camera.worldPosition) }
        if time-environment >= 1 || environment < 0, let tile = tiles[active] {
            environment = time
            scene.background.contents = tile.background.contents
            scene.fogColor = tile.fogColor
            scene.fogStartDistance = tile.fogStartDistance; scene.fogEndDistance = tile.fogEndDistance
        }
        Landscape.medium(scene,area:world.biomes[active],eye:camera.position)
    }

    func dispose() {
        for operation in operations.values { operation.cancel() }
        timer?.invalidate(); timer = nil
        operations = [:]; tiles = [:]; homes = [:]; doors = []
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
        if coordinator.exploring != exploring {
            coordinator.exploring = exploring
            view.exploring = exploring
            if let scene = view.scene, passage == nil {
                if exploring { view.pointOfView?.removeAllActions(); coordinator.atlas?.cancelTravel() }
                else if let atlas = coordinator.atlas { atlas.visit(atlas.active) }
                else { Landscape.focus(scene,world:coordinator.showing?.0 ?? world,biome:coordinator.showing?.1 ?? biome,animated:moving) }
            }
        }
        if let atlas = coordinator.atlas, coordinator.world == world, passage == nil, coordinator.passage == nil {
            if coordinator.biome != biome { coordinator.biome = biome; atlas.visit(biome) }
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
                            arrived:{ [weak coordinator] index in coordinator?.biome = index; coordinator?.showing = (world,index); arrived(index) },failed:failed)
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
