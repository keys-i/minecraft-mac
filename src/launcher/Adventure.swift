import AppKit
import SceneKit
import SpriteKit
import SwiftUI

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

struct Adventure: NSViewRepresentable {
    let world: World
    let biome: Int
    let moving: Bool
    let passage: Passage?
    let assets: Assets
    let exploring: Bool
    let failed: () -> Void

    final class Coordinator: NSObject {
        weak var view: SCNView?
        var exploring = false
        var angles = SCNVector3Zero
        var world: World?
        var biome: Int?
        var passage: Passage?
        var moving = false
        var request = 0
        var operation: Operation?

        @objc func pan(_ gesture: NSPanGestureRecognizer) {
            guard exploring, let view, let camera = view.pointOfView else { return }
            if gesture.state == .began { angles = camera.eulerAngles }
            let movement = gesture.translation(in:view)
            camera.eulerAngles = .init(max(-1.1,min(1.1,angles.x+movement.y*0.004)),angles.y+movement.x*0.004,0)
            view.needsDisplay = true
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> SCNView {
        let view = SCNView(frame: .zero)
        view.backgroundColor = .clear
        view.preferredFramesPerSecond = 20
        view.antialiasingMode = .multisampling4X
        view.allowsCameraControl = false
        view.addGestureRecognizer(NSPanGestureRecognizer(target:context.coordinator,action:#selector(Coordinator.pan(_:))))
        context.coordinator.view = view
        return view
    }

    func updateNSView(_ view: SCNView, context: Context) {
        let coordinator = context.coordinator
        coordinator.moving = moving
        if coordinator.exploring != exploring {
            coordinator.exploring = exploring
            if let scene = view.scene, passage == nil {
                if exploring { view.pointOfView?.removeAction(forKey:"journey") }
                else { Landscape.focus(scene,world:world,biome:biome,animated:moving) }
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
            coordinator.operation = assets.load(world, biome: biome, passage: passage) { [weak view, weak coordinator] result in
                guard let view, let coordinator, coordinator.request == request else { return }
                switch result {
                case .success(let scene):
                    let camera = scene.rootNode.childNode(withName:"camera",recursively:false)
                    if coordinator.exploring { camera?.removeAction(forKey:"journey") }
                    if coordinator.moving, view.scene != nil {
                        view.present(scene,with:.crossFade(withDuration:0.65),incomingPointOfView:camera,completionHandler:nil)
                    } else { view.scene = scene; view.pointOfView = camera }
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

    static func dismantleNSView(_ view: SCNView, coordinator: Coordinator) {
        coordinator.operation?.cancel()
        coordinator.request += 1
        motion(view, enabled: false)
        view.scene = nil
        view.gestureRecognizers.removeAll()
        coordinator.view = nil
    }
}
