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
    private var timer: Timer?
    private var last = 0.0
    private var loading = false
    private var area: Biome = .meadow
    private var entry: (point: SCNVector3, height: Double, angles: SCNVector3)?
    var exploring = false {
        didSet {
            guard exploring != oldValue else { return }
            stop()
            if exploring { window?.makeFirstResponder(self) }
            else {
                entry = nil
                if window?.firstResponder === self { window?.makeFirstResponder(nil) }
            }
        }
    }

    override var acceptsFirstResponder: Bool { exploring }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        NotificationCenter.default.removeObserver(self,name:NSWindow.didResignKeyNotification,object:nil)
        stop()
        if let window {
            NotificationCenter.default.addObserver(self,selector:#selector(lostFocus),name:NSWindow.didResignKeyNotification,object:window)
        }
    }

    override func resignFirstResponder() -> Bool { stop(); return super.resignFirstResponder() }
    @objc private func lostFocus() { stop() }

    override func mouseDown(with event: NSEvent) {
        if exploring { window?.makeFirstResponder(self) }
        super.mouseDown(with:event)
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
        if descending { start() } else if keys.isEmpty { suspend() }
    }

    override func scrollWheel(with event: NSEvent) {
        guard exploring else { super.scrollWheel(with:event); return }
        speed = min(32,max(2,speed*pow(1.08,Float(max(-10,min(10,event.scrollingDeltaY))))))
    }

    func prepare() { loading = true; suspend() }

    func install(_ camera: SCNNode?, area: Biome) {
        self.area = area
        if let entry, let camera {
            camera.position = Self.arrival(area,point:entry.point,height:entry.height)
            camera.eulerAngles = entry.angles
        }
        entry = nil; loading = false
        controller.pointOfView = camera
        controller.interactionMode = .fly; controller.inertiaEnabled = false
        controller.minimumVerticalAngle = -85; controller.maximumVerticalAngle = 85
        start()
    }

    func stop() { suspend(); keys.removeAll(); descending = false }
    private func suspend() { timer?.invalidate(); timer = nil }

    private func start() {
        guard exploring, !loading, timer == nil, window?.isKeyWindow == true,
              !keys.isEmpty || descending else { return }
        last = ProcessInfo.processInfo.systemUptime
        let timer = Timer(timeInterval:SceneryMotion.interval,target:self,selector:#selector(tick),userInfo:nil,repeats:true)
        self.timer = timer
        RunLoop.main.add(timer,forMode:.common)
    }

    @objc private func tick() {
        guard exploring, window?.isKeyWindow == true, window?.occlusionState.contains(.visible) == true,
              NSApp.isActive, !isHiddenOrHasHiddenAncestor else { stop(); return }
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
        if simd_length_squared(direction)>0 { camera.simdWorldPosition += simd_normalize(direction)*speed*dt }
        camera.position.y = min(90,max(-28,camera.position.y))
        let yaw = key(124)-key(123), pitch = key(126)-key(125)
        if yaw != 0 || pitch != 0 { controller.rotateBy(x:-yaw*70*dt,y:pitch*70*dt) }
        needsDisplay = true
        if let step = Self.crossing(camera.position) { visit(step) }
    }

    func visit(_ step: Int) {
        guard !loading, let camera = pointOfView, travel != nil else { return }
        let p = camera.position, ground = Terrain(biome:area).height(p.x,p.z)
        entry = (p,ground > -90 ? p.y-ground : p.y-4,camera.eulerAngles)
        prepare()
        travel?(step)
    }

    static func crossing(_ p: SCNVector3) -> Int? {
        if p.x>80 || p.z < -112 { return 1 }
        if p.x < -80 || p.z>48 { return -1 }
        return nil
    }

    static func arrival(_ area: Biome, point: SCNVector3, height: Double) -> SCNVector3 {
        var x = point.x>80 ? -76 : point.x < -80 ? 76 : point.x
        var z = point.z < -112 ? 44 : point.z>48 ? -108 : point.z
        let terrain = Terrain(biome:area)
        if terrain.height(x,z) < -90 { let p = Landscape.pose(area,at:0).eye; x = p.x; z = p.z }
        let ground = terrain.height(x,z)
        var y = min(88,ground+max(1.62,height))
        if area.underground || World.nether.biomes.contains(area) { y = min(y,max(ground+9,terrain.ceiling(x,z))-1.62) }
        return .init(x,y,z)
    }

    func dispose() {
        stop(); travel = nil; finish = nil; controller.pointOfView = nil; entry = nil
        NotificationCenter.default.removeObserver(self)
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

        @objc func pan(_ gesture: NSPanGestureRecognizer) {
            guard exploring, let view else { return }
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
        view.preferredFramesPerSecond = 20
        view.antialiasingMode = .multisampling4X
        view.allowsCameraControl = false
        view.addGestureRecognizer(NSPanGestureRecognizer(target:context.coordinator,action:#selector(Coordinator.pan(_:))))
        context.coordinator.view = view
        return view
    }

    func updateNSView(_ view: FlightView, context: Context) {
        let coordinator = context.coordinator
        view.travel = travel; view.finish = finish
        coordinator.moving = moving
        if coordinator.exploring != exploring {
            coordinator.exploring = exploring
            view.exploring = exploring
            if let scene = view.scene, passage == nil {
                if exploring { view.pointOfView?.removeAllActions() }
                else { Landscape.focus(scene,world:coordinator.showing?.0 ?? world,biome:coordinator.showing?.1 ?? biome,animated:moving) }
            }
        }
        if coordinator.world != world || coordinator.passage != passage
            || (passage == nil && coordinator.biome != biome) {
            coordinator.operation?.cancel()
            coordinator.request += 1
            let request = coordinator.request
            coordinator.world = world
            coordinator.biome = biome
            coordinator.passage = passage
            view.prepare()
            coordinator.operation = assets.load(world, biome: biome, passage: passage) { [weak view, weak coordinator] result in
                guard let view, let coordinator, coordinator.request == request else { return }
                switch result {
                case .success(let scene):
                    let camera = scene.rootNode.childNode(withName:"camera",recursively:false)
                    if coordinator.exploring { camera?.removeAllActions() }
                    if coordinator.moving, !coordinator.exploring, view.scene != nil {
                        view.present(scene,with:.crossFade(withDuration:0.65),incomingPointOfView:camera,completionHandler:nil)
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
        view.scene?.isPaused = !enabled
        view.isPlaying = enabled
        view.rendersContinuously = enabled
        view.needsDisplay = true
    }

    static func dismantleNSView(_ view: FlightView, coordinator: Coordinator) {
        coordinator.operation?.cancel()
        coordinator.request += 1
        motion(view, enabled: false)
        view.dispose()
        view.scene = nil
        view.gestureRecognizers.removeAll()
        coordinator.view = nil
    }
}
