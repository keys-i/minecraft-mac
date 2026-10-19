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

    var biomes: [String] {
        switch self {
        case .overworld: return ["Forest", "Cherry Grove", "Coast"]
        case .nether: return ["Crimson Forest", "Basalt Deltas", "Warped Forest"]
        case .end: return ["Central Island", "Chorus Islands", "End City"]
        case .sift: return ["Coral terraces", "Luminous grove", "Rift valley"]
        }
    }
}

@MainActor
enum VoxelAdventure {
    // Small shared pixel maps keep surface detail out of the scene graph
    static func material(_ palette: [UInt32], face: [String] = [], cap: [UInt32]? = nil) -> SCNMaterial {
        var pixels = [UInt8](repeating: 255, count: 16 * 16 * 4)
        for y in 0..<16 {
            let row = face.isEmpty ? [] : Array(face[y])
            for x in 0..<16 {
                let shade = (x / 2 * 7 + y / 3 * 13 + x * y) % 17
                let colours = y < 3 ? (cap ?? palette) : palette
                let rgb = !row.isEmpty && row[x] == "#" ? 0x625E5C : colours[shade % colours.count]
                let offset = (y * 16 + x) * 4
                pixels[offset] = UInt8((rgb >> 16) & 255)
                pixels[offset + 1] = UInt8((rgb >> 8) & 255)
                pixels[offset + 2] = UInt8(rgb & 255)
            }
        }
        let material = SCNMaterial()
        material.diffuse.contents = CGImage(width: 16, height: 16, bitsPerComponent: 8,
            bitsPerPixel: 32, bytesPerRow: 64, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
            provider: CGDataProvider(data: Data(pixels) as CFData)!, decode: nil,
            shouldInterpolate: false, intent: .defaultIntent)!
        material.diffuse.magnificationFilter = .nearest
        material.diffuse.minificationFilter = .nearest
        material.diffuse.mipFilter = .none
        material.diffuse.wrapS = .repeat
        material.diffuse.wrapT = .repeat
        material.lightingModel = .lambert
        return material
    }

    @discardableResult
    static func block(_ parent: SCNNode, _ size: SCNVector3, _ position: SCNVector3,
                              _ material: SCNMaterial, name: String? = nil) -> SCNNode {
        let geometry = SCNBox(width: CGFloat(size.x), height: CGFloat(size.y),
                              length: CGFloat(size.z), chamferRadius: 0)
        geometry.materials = [material]
        let node = SCNNode(geometry: geometry)
        node.name = name
        node.position = position
        parent.addChildNode(node)
        return node
    }

    static func sway(_ node: SCNNode, x: CGFloat = 0, y: CGFloat = 0,
                             z: CGFloat = 0, period: Double, phase: Double = 0) {
        let base = node.eulerAngles
        node.eulerAngles = SCNVector3(base.x + x * sin(phase), base.y + y * sin(phase), base.z + z * sin(phase))
        node.runAction(.repeatForever(.customAction(duration: period) { node, elapsed in
            let wave = sin(Double(elapsed) / period * .pi * 2 + phase)
            node.eulerAngles = SCNVector3(base.x + x * wave, base.y + y * wave, base.z + z * wave)
        }))
    }

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
        sun.light?.intensity = 800
        sun.eulerAngles = SCNVector3(-0.5, -0.6, 0)
        scene.rootNode.addChildNode(sun)
        let fill = SCNNode()
        fill.light = SCNLight()
        fill.light?.type = .ambient
        fill.light?.intensity = 350
        scene.rootNode.addChildNode(fill)

        func drift(_ node: SCNNode, y: CGFloat, duration: TimeInterval) {
            node.position = SCNVector3(3.5, y, 0)
            let outward = SCNAction.move(to: SCNVector3(4.8, y + 0.25, -0.4), duration: duration)
            let home = SCNAction.move(to: SCNVector3(3.5, y, 0), duration: duration)
            outward.timingMode = .easeInEaseOut
            home.timingMode = .easeInEaseOut
            node.runAction(.repeatForever(.sequence([outward, home])))
            scene.rootNode.addChildNode(node)
        }

        if world == .overworld || world == .nether {
            let happy = world == .overworld
            let ghast = SCNNode()
            ghast.name = happy ? "happy-ghast" : "ghast"
            ghast.eulerAngles = SCNVector3(0.15, -0.4, 0)
            let palette: [UInt32] = happy ? [0xF3F0E8, 0xEAE8E2, 0xE3E1DA, 0xEFEBE5]
                                         : [0xDEDEDA, 0xD2D2D0, 0xE5E4DF, 0xC9CAC8]
            let skin = material(palette)
            let face = material(palette, face: happy ? [
                "................", "................", "................", "................",
                "................", "...###....###...", "...####..####...", "................",
                "................", "................", ".....#....#.....", "......####......",
                "................", "................", "................", "................"
            ] : [
                "................", "................", "................", "................",
                "................", "...###....###...", "....#......#....", "....#......#....",
                "................", "................", "......####......", "......#..#......",
                "......####......", "................", "................", "................"
            ])
            let body = block(ghast, SCNVector3(2.2, 2.2, 2.2), SCNVector3Zero, skin, name: "body")
            body.geometry?.materials = [face, skin, skin, skin, skin, skin]
            let lengths: [Double] = happy ? [0.55, 0.77, 0.44, 0.55, 0.55, 0.77, 0.88, 0.88, 0.55]
                                          : [1.11, 1.36, 0.99, 1.11, 1.61, 1.36, 1.49, 1.11, 1.61]
            for index in 0..<9 {
                let joint = SCNNode()
                joint.name = "tentacle-\(index)"
                let row = index / 3
                joint.position = SCNVector3(Double(index % 3 - 1) * 0.65 + (row == 1 ? -0.2 : 0.1),
                                            -1.04, Double(row - 1) * 0.66)
                ghast.addChildNode(joint)
                block(joint, SCNVector3(0.275, lengths[index], 0.275),
                      SCNVector3(0, -lengths[index] / 2, 0), skin)
                sway(joint, x: 0.16, z: 0.08, period: 3.8 + Double(index % 3) * 0.3,
                     phase: Double(index) * 0.8)
            }
            if happy {
                let blue = material([0x4192AB, 0x367F9C, 0x55A0B7])
                let leather = material([0x755136, 0x86603E, 0x69462E])
                let rim = material([0xBA9870, 0xCFAC7D, 0xA1815B])
                let lens = material([0xBADEE3, 0xCEE9EA, 0xA5CFD9])
                block(ghast, SCNVector3(2.23, 0.25, 2.23), SCNVector3(0, 0.87, 0), blue, name: "harness")
                for x in [-0.77, 0.77] {
                    block(ghast, SCNVector3(0.16, 0.5, 2.25), SCNVector3(x, 0.89, 0), leather)
                }
                for x in [-0.48, 0.48] {
                    block(ghast, SCNVector3(0.77, 0.44, 0.13), SCNVector3(x, 0.9, 1.17), rim)
                    block(ghast, SCNVector3(0.56, 0.25, 0.04), SCNVector3(x, 0.9, 1.255), lens)
                }
                block(ghast, SCNVector3(0.25, 0.1, 0.08), SCNVector3(0, 0.9, 1.2), leather)
            }
            drift(ghast, y: 2.2, duration: 12)
        } else if world == .end {
            let dragon = SCNNode()
            dragon.name = "dragon"
            dragon.eulerAngles = SCNVector3(0.48, 0.72, -0.08)
            let skin = material([0x222226, 0x29292D, 0x1B1B1F, 0x303034])
            let ridge = material([0x5C5C63, 0x727278, 0x505057])
            let membrane = material([0x39363F, 0x423E48, 0x343139])
            membrane.isDoubleSided = true
            block(dragon, SCNVector3(0.75, 0.75, 2), SCNVector3Zero, skin, name: "body")
            for z in [-0.65, 0.0, 0.65] {
                block(dragon, SCNVector3(0.065, 0.2, 0.38), SCNVector3(0, 0.45, z), ridge)
            }
            var neck = dragon
            for index in 0..<5 {
                let segment = block(neck, SCNVector3(0.31, 0.31, 0.36),
                                    SCNVector3(0, index == 0 ? 0.15 : 0.025, index == 0 ? 1.08 : 0.32),
                                    skin, name: "neck-\(index)")
                block(segment, SCNVector3(0.065, 0.13, 0.19), SCNVector3(0, 0.22, 0), ridge)
                sway(segment, y: 0.04, period: 6, phase: Double(index) * 0.4)
                neck = segment
            }
            let head = block(neck, SCNVector3(0.5, 0.5, 0.5), SCNVector3(0, 0.04, 0.36), skin, name: "head")
            block(head, SCNVector3(0.375, 0.156, 0.5), SCNVector3(0, -0.055, 0.43), skin)
            let jaw = SCNNode()
            jaw.name = "jaw"
            jaw.position = SCNVector3(0, -0.17, 0.2)
            jaw.eulerAngles.x = 0.16
            head.addChildNode(jaw)
            block(jaw, SCNVector3(0.375, 0.125, 0.5), SCNVector3(0, 0, 0.23), skin)
            let eye = material([0xE595F5, 0xCC73E5, 0xF0B6FF])
            eye.emission.contents = NSColor(red: 0.45, green: 0.12, blue: 0.6, alpha: 1)
            for side in [-1.0, 1.0] {
                block(head, SCNVector3(0.0625, 0.125, 0.1875), SCNVector3(side * 0.125, 0.31, -0.08), ridge)
                block(head, SCNVector3(0.0625, 0.0625, 0.125), SCNVector3(side * 0.125, 0.055, 0.55), skin)
                block(head, SCNVector3(0.015, 0.065, 0.17), SCNVector3(side * 0.255, 0.045, 0.12), eye)
                let leg = SCNNode()
                leg.position = SCNVector3(side * 0.43, -0.18, -0.65)
                leg.eulerAngles.x = -0.65
                dragon.addChildNode(leg)
                block(leg, SCNVector3(0.38, 0.65, 0.38), SCNVector3(0, -0.3, 0), skin)
                block(leg, SCNVector3(0.27, 0.58, 0.27), SCNVector3(0, -0.7, -0.2), skin)
                block(leg, SCNVector3(0.42, 0.12, 0.58), SCNVector3(0, -0.99, 0), skin)
                let front = SCNNode()
                front.position = SCNVector3(side * 0.34, -0.2, 0.65)
                front.eulerAngles.x = -0.55
                dragon.addChildNode(front)
                block(front, SCNVector3(0.19, 0.6, 0.22), SCNVector3(0, -0.25, 0), skin)
                block(front, SCNVector3(0.17, 0.48, 0.18), SCNVector3(0, -0.6, -0.14), skin)
                block(front, SCNVector3(0.23, 0.1, 0.42), SCNVector3(0, -0.85, 0), skin)

                let wing = SCNNode()
                wing.name = side < 0 ? "left-wing" : "right-wing"
                wing.position = SCNVector3(side * 0.34, 0.28, 0.65)
                wing.eulerAngles.z = side * 0.28
                dragon.addChildNode(wing)
                block(wing, SCNVector3(1.75, 0.17, 0.18), SCNVector3(side * 0.875, 0, 0), skin)
                let tip = SCNNode()
                tip.name = "wingtip"
                tip.position = SCNVector3(side * 1.75, 0, 0)
                wing.addChildNode(tip)
                block(tip, SCNVector3(1.75, 0.09, 0.12), SCNVector3(side * 0.875, 0, 0), skin)
                for (part, depth) in [(wing, 1.65), (tip, 1.5)] {
                    let vertices = [SCNVector3(0, 0, 0), SCNVector3(side * 1.75, 0, 0),
                                    SCNVector3(side * 1.75, 0, -depth), SCNVector3(side * 1.0, 0, -depth * 0.7),
                                    SCNVector3(0, 0, -depth)]
                    let uv = [CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 0), CGPoint(x: 1, y: 1),
                              CGPoint(x: 0.57, y: 0.7), CGPoint(x: 0, y: 1)]
                    let mesh = SCNGeometry(sources: [SCNGeometrySource(vertices: vertices), SCNGeometrySource(textureCoordinates: uv)],
                                           elements: [SCNGeometryElement(indices: [Int32(0), 1, 2, 0, 2, 3, 0, 3, 4], primitiveType: .triangles)])
                    mesh.materials = [membrane]
                    let sail = SCNNode(geometry: mesh)
                    sail.name = "wing-membrane"
                    part.addChildNode(sail)
                    block(part, SCNVector3(0.055, 0.035, depth), SCNVector3(side * 1.72, 0, -depth / 2), skin)
                }
                sway(wing, z: side * 0.48, period: 2.8, phase: .pi / 2)
                sway(tip, z: side * 0.23, period: 2.8, phase: .pi / 2 - 0.55)
            }
            var tail = dragon
            for index in 0..<9 {
                let width = 0.31 - Double(index) * 0.025
                let segment = block(tail, SCNVector3(width, width, 0.38),
                                    SCNVector3(0, 0, index == 0 ? -1.1 : -0.34), skin, name: "tail-\(index)")
                block(segment, SCNVector3(0.05, 0.13, 0.15), SCNVector3(0, width / 2 + 0.05, 0), ridge)
                sway(segment, y: 0.065, period: 6, phase: Double(index) * 0.45)
                tail = segment
            }
            dragon.scale = SCNVector3(0.8, 0.8, 0.8)
            drift(dragon, y: 1.8, duration: 14)
        } else {
            let portal = SCNNode()
            portal.name = "sift-rift"
            portal.position = SCNVector3(5.2, 1.1, -2)
            let stone = material([0x392947, 0x493355, 0x31223D])
            for x in [-0.8, 0.8] {
                block(portal, SCNVector3(0.24, 2.4, 0.35), SCNVector3(x, 0, 0), stone)
            }
            for y in [-1.2, 1.2] {
                block(portal, SCNVector3(1.84, 0.24, 0.35), SCNVector3(0, y, 0), stone)
            }
            let light = material([0x71F4F0, 0x88E6F2, 0x73D7E4])
            light.emission.contents = NSColor.cyan
            let glow = block(portal, SCNVector3(1.4, 2.1, 0.025), SCNVector3Zero, light)
            glow.opacity = 0.3
            glow.runAction(.repeatForever(.sequence([.fadeOpacity(to: 0.65, duration: 1.8),
                                                     .fadeOpacity(to: 0.3, duration: 1.8)])))
            scene.rootNode.addChildNode(portal)
        }
        return scene
    }
}

struct Adventure: NSViewRepresentable {
    let world: World
    let biome: Int
    let moving: Bool

    final class Coordinator {
        var world: World?
        var biome: Int?
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
            view.scene = Landscape.scene(world)
            view.pointOfView = view.scene?.rootNode.childNode(withName: "camera", recursively: false)
            context.coordinator.world = world
            context.coordinator.biome = nil
        }
        if context.coordinator.biome != biome, let scene = view.scene {
            Landscape.focus(scene, biome: biome, animated: moving && context.coordinator.biome != nil)
            context.coordinator.biome = biome
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
