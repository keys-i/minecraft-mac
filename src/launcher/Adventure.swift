import AppKit
import SceneKit
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
    let failed: () -> Void

    final class Coordinator {
        var world: World?
        var biome: Int?
        var page: Int?
        var passage: Passage?
        var focused: Int?
        var moving = false
        var request = 0
        var operation: Operation?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> SCNView {
        let view = SCNView(frame: .zero)
        view.backgroundColor = .clear
        view.preferredFramesPerSecond = 20
        view.antialiasingMode = .multisampling4X
        view.allowsCameraControl = false
        return view
    }

    func updateNSView(_ view: SCNView, context: Context) {
        let coordinator = context.coordinator
        coordinator.moving = moving
        coordinator.biome = biome
        if coordinator.world != world || coordinator.passage != passage
            || (passage == nil && coordinator.page != world.page(biome)) {
            view.scene?.isPaused = true
            view.scene = nil
            coordinator.operation?.cancel()
            coordinator.request += 1
            let request = coordinator.request
            coordinator.world = world
            coordinator.page = world.page(biome)
            coordinator.passage = passage
            coordinator.focused = nil
            coordinator.operation = assets.load(world, biome: biome, passage: passage) { [weak view, weak coordinator] result in
                guard let view, let coordinator, coordinator.request == request else { return }
                switch result {
                case .success(let scene):
                    if passage == nil {
                        let selected = coordinator.biome ?? biome
                        Landscape.focus(scene, world: world, biome: selected, animated: false)
                        coordinator.focused = selected
                    }
                    view.scene = scene
                    view.pointOfView = scene.rootNode.childNode(withName: "camera", recursively: false)
                    Self.motion(view, enabled: coordinator.moving)
                case .failure: failed()
                }
            }
        } else if passage == nil, coordinator.focused != biome, let scene = view.scene {
            Landscape.focus(scene, world: world, biome: biome, animated: moving)
            coordinator.focused = biome
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
    }
}
