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

@MainActor
enum VoxelAdventure {
    static func scene(_ world: World) -> SCNScene {
        let scene = SCNScene()
        scene.background.contents = NSColor.clear
        let camera = SCNNode()
        camera.name = "camera"
        camera.camera = SCNCamera()
        camera.camera?.usesOrthographicProjection = true
        camera.camera?.orthographicScale = 10
        camera.position = SCNVector3(0, 0, 22)
        scene.rootNode.addChildNode(camera)
        let sun = SCNNode()
        sun.light = SCNLight()
        sun.light?.type = .directional
        sun.light?.intensity = 1000
        sun.eulerAngles = SCNVector3(-0.4, -0.5, 0)
        scene.rootNode.addChildNode(sun)
        let fill = SCNNode()
        fill.light = SCNLight()
        fill.light?.type = .ambient
        fill.light?.intensity = 450
        scene.rootNode.addChildNode(fill)

        func block(_ parent: SCNNode, _ size: SCNVector3, _ position: SCNVector3,
                   _ colour: NSColor) -> SCNNode {
            let geometry = SCNBox(width: CGFloat(size.x), height: CGFloat(size.y),
                                  length: CGFloat(size.z), chamferRadius: 0)
            geometry.firstMaterial?.diffuse.contents = colour
            geometry.firstMaterial?.lightingModel = .physicallyBased
            geometry.firstMaterial?.roughness.contents = 0.9
            let node = SCNNode(geometry: geometry)
            node.position = position
            parent.addChildNode(node)
            return node
        }

        func drift(_ node: SCNNode, y: CGFloat, duration: TimeInterval) {
            node.position = SCNVector3(3.2, y, 0)
            let outward = SCNAction.move(to: SCNVector3(6.0, y + 0.35, -1), duration: duration)
            let home = SCNAction.move(to: SCNVector3(3.2, y, 0), duration: duration)
            outward.timingMode = .easeInEaseOut
            home.timingMode = .easeInEaseOut
            node.runAction(.repeatForever(.sequence([outward, home])))
            scene.rootNode.addChildNode(node)
        }

        if world == .overworld || world == .nether {
            let ghast = SCNNode()
            ghast.name = world == .overworld ? "happy-ghast-and-rider" : "ghast"
            ghast.eulerAngles = SCNVector3(0.08, -0.35, 0)
            let skin = world == .overworld ? NSColor(white: 0.92, alpha: 1) : NSColor(white: 0.76, alpha: 1)
            _ = block(ghast, SCNVector3(1.5, 1.5, 1.3), SCNVector3(0, 0, 0), skin)
            for x in [-0.3, 0.3] {
                _ = block(ghast, SCNVector3(0.19, 0.12, 0.04), SCNVector3(x, 0.15, 0.67), .darkGray)
            }
            _ = block(ghast, SCNVector3(0.3, world == .overworld ? 0.07 : 0.25, 0.04),
                      SCNVector3(0, -0.2, 0.67), .darkGray)
            for index in 0..<9 {
                let leg = block(ghast, SCNVector3(0.16, 0.7, 0.16),
                                SCNVector3(Double(index % 3 - 1) * 0.5, -1.0,
                                           Double(index / 3 - 1) * 0.45), skin)
                leg.pivot = SCNMatrix4MakeTranslation(0, 0.3, 0)
                let sway = SCNAction.rotateBy(x: 0.25, y: 0, z: index.isMultiple(of: 2) ? 0.12 : -0.12, duration: 1.1)
                leg.runAction(.repeatForever(.sequence([sway, sway.reversed()])))
            }
            if world == .overworld {
                _ = block(ghast, SCNVector3(0.33, 0.4, 0.25), SCNVector3(0, 1.05, 0), .systemTeal)
                _ = block(ghast, SCNVector3(0.3, 0.3, 0.3), SCNVector3(0, 1.4, 0),
                          NSColor(red: 0.67, green: 0.43, blue: 0.28, alpha: 1))
                for x in [-0.23, 0.23] {
                    _ = block(ghast, SCNVector3(0.13, 0.38, 0.13), SCNVector3(x, 1, 0), .systemTeal)
                    _ = block(ghast, SCNVector3(0.15, 0.15, 0.38), SCNVector3(x / 2, 0.82, 0.2), .systemIndigo)
                }
            }
            ghast.scale = SCNVector3(1.05, 1.05, 1.05)
            drift(ghast, y: 1.9, duration: 10)
        } else if world == .end {
            let dragon = SCNNode()
            dragon.name = "dragon"
            dragon.eulerAngles = SCNVector3(0.1, -0.35, 0)
            let skin = NSColor(red: 0.09, green: 0.065, blue: 0.13, alpha: 1)
            _ = block(dragon, SCNVector3(2, 0.45, 0.65), SCNVector3(0, 0, 0), skin)
            _ = block(dragon, SCNVector3(0.75, 0.5, 0.65), SCNVector3(1.15, 0.05, 0), skin)
            _ = block(dragon, SCNVector3(0.16, 0.09, 0.03), SCNVector3(1.2, 0.15, 0.34), .systemPink)
            for side in [-1.0, 1.0] {
                let wing = SCNNode()
                wing.position = SCNVector3(-0.2, 0.1, side * 0.3)
                dragon.addChildNode(wing)
                _ = block(wing, SCNVector3(1.8, 0.06, 1.6), SCNVector3(-0.4, 0, side * 0.75), skin)
                let flap = SCNAction.rotateBy(x: side * 0.45, y: 0, z: 0, duration: 0.8)
                wing.runAction(.repeatForever(.sequence([flap, flap.reversed()])))
            }
            _ = block(dragon, SCNVector3(1.1, 0.22, 0.25), SCNVector3(-1.4, 0, 0), skin)
            drift(dragon, y: 2.0, duration: 12)
        } else {
            let portal = SCNNode()
            portal.name = "sift-rift"
            portal.position = SCNVector3(5.7, 1.1, -2)
            let stone = NSColor(red: 0.18, green: 0.1, blue: 0.25, alpha: 1)
            for x in [-0.8, 0.8] {
                _ = block(portal, SCNVector3(0.24, 2.4, 0.35), SCNVector3(x, 0, 0), stone)
            }
            for y in [-1.2, 1.2] {
                _ = block(portal, SCNVector3(1.84, 0.24, 0.35), SCNVector3(0, y, 0), stone)
            }
            let glow = block(portal, SCNVector3(1.4, 2.1, 0.025), SCNVector3(0, 0, 0), .cyan)
            glow.geometry?.firstMaterial?.emission.contents = NSColor.cyan
            glow.opacity = 0.3
            glow.runAction(.repeatForever(.sequence([.fadeOpacity(to: 0.65, duration: 1.8),
                                                     .fadeOpacity(to: 0.3, duration: 1.8)])))
            scene.rootNode.addChildNode(portal)
            let spirit = SCNNode()
            spirit.name = "imagined-sift-spirit"
            _ = block(spirit, SCNVector3(0.5, 0.6, 0.4), SCNVector3(0, 0, 0), .cyan)
            for x in [-0.12, 0.12] {
                _ = block(spirit, SCNVector3(0.08, 0.09, 0.025), SCNVector3(x, 0.08, 0.21), .white)
            }
            drift(spirit, y: 1.5, duration: 8)
        }
        return scene
    }
}

struct Adventure: NSViewRepresentable {
    let world: World
    let moving: Bool

    final class Coordinator {
        var world: World?
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
        if context.coordinator.world != world {
            view.scene = VoxelAdventure.scene(world)
            view.pointOfView = view.scene?.rootNode.childNode(withName: "camera", recursively: false)
            context.coordinator.world = world
        }
        view.scene?.isPaused = !moving
        view.isPlaying = moving
        view.rendersContinuously = moving
    }

    static func dismantleNSView(_ view: SCNView, coordinator: Coordinator) {
        view.isPlaying = false
        view.rendersContinuously = false
        view.scene?.isPaused = true
        view.scene = nil
    }
}
