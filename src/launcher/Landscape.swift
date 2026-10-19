import AppKit
import SceneKit

private struct Voxels {
    var vertices: [SCNVector3] = []
    var normals: [SCNVector3] = []
    var uv: [CGPoint] = []
    var materials: [SCNMaterial] = []
    var indices: [[Int32]] = []
    private var slots: [ObjectIdentifier: Int] = [:]

    private static let faces: [[SCNVector3]] = [
        [.init(-0.5,-0.5,0.5), .init(0.5,-0.5,0.5), .init(0.5,0.5,0.5), .init(-0.5,0.5,0.5)],
        [.init(0.5,-0.5,0.5), .init(0.5,-0.5,-0.5), .init(0.5,0.5,-0.5), .init(0.5,0.5,0.5)],
        [.init(0.5,-0.5,-0.5), .init(-0.5,-0.5,-0.5), .init(-0.5,0.5,-0.5), .init(0.5,0.5,-0.5)],
        [.init(-0.5,-0.5,-0.5), .init(-0.5,-0.5,0.5), .init(-0.5,0.5,0.5), .init(-0.5,0.5,-0.5)],
        [.init(-0.5,0.5,0.5), .init(0.5,0.5,0.5), .init(0.5,0.5,-0.5), .init(-0.5,0.5,-0.5)],
        [.init(-0.5,-0.5,-0.5), .init(0.5,-0.5,-0.5), .init(0.5,-0.5,0.5), .init(-0.5,-0.5,0.5)]
    ]
    private static let directions: [SCNVector3] = [
        .init(0,0,1), .init(1,0,0), .init(0,0,-1), .init(-1,0,0), .init(0,1,0), .init(0,-1,0)
    ]

    mutating func cube(_ size: SCNVector3, at p: SCNVector3, material: SCNMaterial,
                       top: SCNMaterial? = nil, faces: Int = 63) {
        for face in 0..<6 where faces & (1 << face) != 0 {
            let surface = face == 4 ? (top ?? material) : material
            let key = ObjectIdentifier(surface)
            let slot: Int
            if let existing = slots[key] { slot = existing }
            else {
                slot = materials.count
                slots[key] = slot
                materials.append(surface)
                indices.append([])
            }
            let offset = Int32(vertices.count)
            vertices.append(contentsOf: Self.faces[face].map {
                SCNVector3(p.x + $0.x * size.x, p.y + $0.y * size.y, p.z + $0.z * size.z)
            })
            normals.append(contentsOf: Array(repeating: Self.directions[face], count: 4))
            let width = face == 1 || face == 3 ? size.z : size.x
            let height = face >= 4 ? size.z : size.y
            uv.append(contentsOf: [.init(x:0,y:height), .init(x:width,y:height), .init(x:width,y:0), .init(x:0,y:0)])
            indices[slot].append(contentsOf: [offset, offset+1, offset+2, offset, offset+2, offset+3])
        }
    }

    func node(_ name: String) -> SCNNode {
        let geometry = SCNGeometry(sources: [SCNGeometrySource(vertices: vertices),
            SCNGeometrySource(normals: normals), SCNGeometrySource(textureCoordinates: uv)],
            elements: indices.map { SCNGeometryElement(indices: $0, primitiveType: .triangles) })
        geometry.materials = materials
        let node = SCNNode(geometry: geometry)
        node.name = name
        return node
    }
}

@MainActor
enum Landscape {
    private static func colour(_ rgb: UInt32) -> NSColor {
        NSColor(srgbRed: Double((rgb >> 16) & 255) / 255, green: Double((rgb >> 8) & 255) / 255,
                blue: Double(rgb & 255) / 255, alpha: 1)
    }

    @MainActor private struct Palette {
        let rock: SCNMaterial
        let tops: [SCNMaterial]
        let sides: [SCNMaterial]
        let leaves: [SCNMaterial]
        let stem: SCNMaterial
        let fluid: SCNMaterial
        let sky: NSColor

        init(_ world: World) {
            let stone: [UInt32], soil: [UInt32], top: [[UInt32]], foliage: [[UInt32]], wood: [UInt32]
            let liquid: [UInt32], atmosphere: UInt32
            switch world {
            case .overworld:
                stone = [0x8C9698,0x7C868A,0x9AA1A0]; soil = [0x8C684A,0x795C43,0x9F7854]
                top = [[0x669A45,0x78A84D,0x5C8B3E], [0x80AB53,0x90B861,0x76A14C], [0xE8D5A2,0xDFCA94,0xEFE0B5]]
                foliage = [[0x427547,0x4E8551,0x39683D], [0xE7AAC8,0xF2BBD5,0xD891B5], [0x77994A,0x87A758,0x698C3E]]
                wood = [0x68513D,0x796046,0x574431]; liquid = [0x399EA9,0x48AEB7,0x318C9E]; atmosphere = 0x9EC9DF
            case .nether:
                stone = [0x652C36,0x73313A,0x562530]; soil = stone
                top = [[0xA84047,0xB94D53,0x94313C], [0x50505B,0x41434F,0x5D5B64], [0x318B85,0x3C9C91,0x287B78]]
                foliage = [[0xB63740,0xCD454B,0xA32A37], [0x5D5D69,0x4C4F5C,0x6B6872], [0x30AAA1,0x45BFB1,0x228F8D]]
                wood = [0x693643,0x7B4252,0x552B38]; liquid = [0xEF8434,0xF9AF45,0xD75B27]; atmosphere = 0x4B2536
            case .end:
                stone = [0xC2BB88,0xCEC593,0xB6AE7B]; soil = stone
                top = [[0xD9D09D,0xE4DAAA,0xCFC693], [0xD1C99A,0xDDD4A5,0xC3BB8D], [0xC5ACCB,0xB99DC1,0xD1B9D6]]
                foliage = [[0x584267,0x6B517A,0x4A365B], [0x705782,0x826892,0x5D4670], [0xA287AE,0xB399BD,0x907299]]
                wood = [0x292433,0x342D40,0x201C29]; liquid = [0x473357,0x533F65,0x3C2B4D]; atmosphere = 0x29243E
            case .sift:
                stone = [0xBE758F,0xD18BA0,0xAB647F]; soil = stone
                top = [[0xE5AF9F,0xF1C1AD,0xD99F92], [0x76C5AA,0x8FD9B9,0x64B59C], [0xBEA4D6,0xCFB9E3,0xAC92C8]]
                foliage = [[0xF0B0CB,0xF8C6DC,0xDE95B9], [0x61D3BB,0x86E6CE,0x4ABEA9], [0xC9A6E6,0xDDBFF2,0xB590D5]]
                wood = [0x98677E,0xAD7B94,0x81556F]; liquid = [0x62CCD0,0x8CE2DD,0x4EB9C4]; atmosphere = 0x9AC2D0
            }
            rock = VoxelAdventure.material(stone)
            tops = top.map { VoxelAdventure.material($0) }
            sides = top.map { VoxelAdventure.material(soil, cap: $0) }
            leaves = foliage.map { VoxelAdventure.material($0) }
            stem = VoxelAdventure.material(wood)
            fluid = VoxelAdventure.material(liquid)
            fluid.diffuse.wrapS = .repeat
            fluid.diffuse.wrapT = .repeat
            fluid.transparency = world == .nether ? 1 : 0.78
            fluid.emission.contents = Self.emission(world)
            sky = Landscape.colour(atmosphere)
        }

        private static func emission(_ world: World) -> NSColor {
            switch world {
            case .nether: return Landscape.colour(0x9A3C13)
            case .sift: return Landscape.colour(0x184A53)
            default: return .black
            }
        }
    }

    private static func zone(_ x: Double) -> Int { min(2, max(0, Int(floor((x + 27) / 18)))) }

    static func height(_ world: World, x: Double, z: Double) -> Double {
        let local = x - Double(zone(x) - 1) * 18
        if world == .end && hypot(local / 1.15, z + 4) > 11 { return -10 }
        if world != .end && abs(z + 8 - sin(x * 0.13) * 2.5) < 2.4 { return 0 }
        switch world {
        case .overworld: return floor(max(1, 3 + sin(x * 0.18) * 1.6 + cos(z * 0.24) * 1.4 + max(0, -z - 18) * (0.28 + 0.15 * sin(x * 0.08))))
        case .nether: return floor(max(1, 3 + sin(x * 0.2) * cos(z * 0.18) * 2.5))
        case .end: return floor(max(1, 3 + cos(local * 0.2) + sin(z * 0.3)))
        case .sift: return floor(max(1, 3 + sin(x * 0.17 + z * 0.12) * 2.3 + cos(z * 0.3)))
        }
    }

    static func scene(_ world: World) -> SCNScene {
        let scene = VoxelAdventure.scene(world)
        let palette = Palette(world)
        scene.background.contents = palette.sky
        scene.fogColor = palette.sky
        scene.fogStartDistance = 38
        scene.fogEndDistance = 92
        let camera = scene.rootNode.childNode(withName: "camera", recursively: false)!
        camera.camera?.usesOrthographicProjection = false
        camera.camera?.fieldOfView = 50
        camera.camera?.zFar = 150
        camera.camera?.wantsHDR = true
        camera.camera?.wantsExposureAdaptation = false
        camera.camera?.exposureOffset = -0.2
        camera.camera?.contrast = 1.08
        camera.camera?.saturation = 1.08
        camera.camera?.bloomIntensity = 0.2
        camera.camera?.bloomThreshold = 1.2
        camera.camera?.screenSpaceAmbientOcclusionIntensity = 0.9
        camera.camera?.screenSpaceAmbientOcclusionRadius = 2
        for light in scene.rootNode.childNodes.compactMap(\.light) where light.type == .directional {
            light.castsShadow = true
            light.shadowMode = .deferred
            light.shadowMapSize = CGSize(width: 1024, height: 1024)
            light.shadowSampleCount = 4
            light.shadowColor = NSColor.black.withAlphaComponent(0.28)
            light.maximumShadowDistance = 75
            light.color = colour(world == .nether ? 0xFFE0BF : world == .end ? 0xDED1FF : 0xFFF2DF)
        }

        // Buried faces are omitted and static blocks share one mesh per landscape
        var land = Voxels()
        for x in -70...70 {
            for z in -70...25 {
                let h = height(world, x: Double(x), z: Double(z))
                guard h >= 0 else { continue }
                let biome = zone(Double(x))
                let neighbours = [(0,1),(1,0),(0,-1),(-1,0)].map {
                    height(world, x: Double(x + $0.0), z: Double(z + $0.1))
                }
                var cap = 16, sides = 0
                for face in 0..<4 {
                    if neighbours[face] < h { cap |= 1 << face }
                    if neighbours[face] < h - 1 { sides |= 1 << face }
                }
                let bottom = world == .end ? -max(0.5, 5 - hypot(Double(x) - Double(biome - 1) * 18, Double(z) + 4) * 0.3) : -5
                land.cube(SCNVector3(1, 1, 1), at: SCNVector3(Double(x), h - 0.5, Double(z)),
                          material: palette.sides[biome], top: palette.tops[biome], faces: cap)
                land.cube(SCNVector3(1, max(0.1, h - 1 - bottom), 1),
                          at: SCNVector3(Double(x), (h - 1 + bottom) / 2, Double(z)),
                          material: palette.rock, faces: sides | (world == .end ? 32 : 0))
            }
        }

        for biome in 0..<3 {
            let centre = Double(biome - 1) * 18
            for index in 0..<10 {
                let x = centre + Double(index % 5 - 2) * 3.1
                let z = -17 + Double(index / 5) * 12 + sin(Double(index) * 2.1) * 2
                let y = height(world, x: x.rounded(), z: z.rounded())
                guard y > 0 else { continue }
                if world == .end {
                    let tall = 2.5 + Double(index % 3)
                    land.cube(SCNVector3(0.45, tall, 0.45), at: SCNVector3(x, y + tall / 2, z), material: palette.leaves[biome])
                    land.cube(SCNVector3(1.5, 0.4, 0.4), at: SCNVector3(x + 0.45, y + tall - 0.4, z), material: palette.leaves[biome])
                    land.cube(SCNVector3(0.65, 0.65, 0.65), at: SCNVector3(x + 1, y + tall, z), material: palette.tops[2])
                } else if world == .nether && biome == 1 {
                    let tall = 3 + Double(index % 4) * 1.5
                    land.cube(SCNVector3(1.2, tall, 1.2), at: SCNVector3(x, y + tall / 2, z), material: palette.tops[1])
                } else {
                    let tall = 3.5 + Double(index % 3)
                    land.cube(SCNVector3(0.6, tall, 0.6), at: SCNVector3(x, y + tall / 2, z), material: palette.stem)
                    var crown = Voxels()
                    let wide = world == .sift ? 3.8 : 3.3
                    if world != .sift {
                        crown.cube(SCNVector3(wide, 1.4, wide), at: .init(0,0,0), material: palette.leaves[biome])
                        crown.cube(SCNVector3(wide - 1, 1.0, wide - 1), at: .init(-0.4,1,0.3), material: palette.leaves[biome])
                    }
                    if world == .overworld && biome == 0 {
                        crown.cube(SCNVector3(1.5,1.4,1.5), at: .init(0,2.0,0), material: palette.leaves[biome])
                    }
                    if world == .sift {
                        crown.cube(.init(3.1,0.55,0.65), at:.init(0,-0.5,0), material:palette.stem)
                        for side in [-1.0,1.0] {
                            crown.cube(.init(0.55,2.4,0.55), at:.init(side*1.3,0.5,0), material:palette.stem)
                            crown.cube(.init(1.5,0.8,1.4), at:.init(side*1.3,1.8,0), material:palette.leaves[biome])
                            crown.cube(.init(0.85,0.6,0.85), at:.init(side*1.3,2.4,0), material:palette.leaves[biome])
                        }
                    }
                    let canopy = crown.node("wind-canopy")
                    canopy.position = SCNVector3(x, y + tall, z)
                    VoxelAdventure.sway(canopy, x: 0.012, z: 0.025, period: 7 + Double(index % 3), phase: Double(index))
                    scene.rootNode.addChildNode(canopy)
                }
            }
            if world == .end {
                let tower = biome == 0 ? 14.0 : biome == 2 ? 10.0 : 0
                if tower > 0 {
                    let x = centre + 3, z = -11.0
                    let base = height(world,x:x,z:z)
                    land.cube(SCNVector3(2.2, tower, 2.2), at: SCNVector3(x, base + tower / 2, z),
                              material: biome == 0 ? palette.stem : palette.tops[0])
                    for level in 0..<3 where biome == 2 {
                        let y = base + 4 + Double(level) * 3.7
                        for side in [-1.0,1.0] {
                            land.cube(.init(3.5,2.8,0.3), at:.init(x,y+1.4,z+side*1.6), material:palette.tops[0])
                            for depth in [-1.0,1.0] {
                                land.cube(.init(0.5,3,0.5), at:.init(x+side*1.7,y+1.5,z+depth*1.7), material:palette.leaves[2])
                            }
                        }
                        for roof in 0..<3 {
                            let span = 5.7 - Double(roof) * 1.2
                            land.cube(.init(span,0.45,span), at:.init(x,y+3+Double(roof)*0.45,z), material:palette.leaves[2])
                        }
                    }
                }
            }
            if world == .sift {
                for index in 0..<2 {
                    let x = centre - 7 + Double(index) * 10, z = -22.0 - Double(index) * 3
                    let base = height(world,x:x,z:z)
                    for step in 0..<12 {
                        let width = 3.5 + sin(Double(step)*0.35) * 1.4
                        land.cube(.init(width,1,width), at:.init(x+sin(Double(step)*0.15),base+Double(step)+0.5,z), material:palette.rock)
                    }
                }
            }
        }
        if world == .nether {
            land.cube(.init(142,4,100), at:.init(0,28,-22), material:palette.rock)
            for index in 0..<16 {
                let x = Double(index % 8 - 4) * 11, z = -25 + Double(index / 8) * 23
                land.cube(.init(3,5+Double(index%3),3), at:.init(x,24,z), material:palette.rock)
            }
        }
        scene.rootNode.addChildNode(land.node("terrain"))

        if world == .nether || world == .sift {
            for x in [-16.0,2,20] {
                let glow = SCNNode()
                glow.light = SCNLight()
                glow.light?.type = .omni
                glow.light?.color = colour(world == .nether ? 0xF6A269 : 0x79DCCC)
                glow.light?.intensity = world == .nether ? 320 : 140
                glow.light?.attenuationStartDistance = 2
                glow.light?.attenuationEndDistance = 24
                glow.position = SCNVector3(x,3,-8)
                scene.rootNode.addChildNode(glow)
            }
        }
        let motes = SCNParticleSystem()
        motes.birthRate = world == .end ? 1 : 3
        motes.particleLifeSpan = 8
        motes.particleSize = world == .overworld ? 0.09 : 0.055
        motes.particleColor = colour(world == .nether ? 0xF5AD65 : world == .overworld ? 0xF4C4DA : 0xBCDEF1)
        motes.isLightingEnabled = false
        motes.particleVelocity = world == .overworld ? 0.3 : 0.15
        motes.emittingDirection = SCNVector3(0,world == .overworld ? -1 : 1,0)
        motes.spreadingAngle = 25
        motes.emitterShape = SCNBox(width: world == .overworld ? 12 : 60, height: 1, length: 7, chamferRadius: 0)
        let air = SCNNode()
        air.name = "ambient-motes"
        air.position = SCNVector3(0,world == .overworld ? 8 : 3,-6)
        air.addParticleSystem(motes)
        scene.rootNode.addChildNode(air)

        if world != .end {
            let fluid = palette.fluid
            fluid.diffuse.contentsTransform = SCNMatrix4MakeScale(150, 105, 1)
            let surface = SCNPlane(width: 150, height: 105)
            surface.firstMaterial = fluid
            let water = SCNNode(geometry: surface)
            water.name = "flowing-surface"
            water.position = SCNVector3(0, 0.35, -22)
            water.eulerAngles.x = -.pi / 2
            water.runAction(.repeatForever(.customAction(duration: 128) { node, elapsed in
                var transform = SCNMatrix4MakeScale(150, 105, 1)
                transform.m41 = elapsed / 8
                transform.m42 = elapsed / 16
                node.geometry?.firstMaterial?.diffuse.contentsTransform = transform
            }))
            scene.rootNode.addChildNode(water)
            var falls = Voxels()
            let flow = fluid.copy() as! SCNMaterial
            flow.diffuse.contentsTransform = SCNMatrix4Identity
            for x in [-12.0,6,24] {
                let z = floor(-8 + sin(x*0.13)*2.5 - 2.4)
                let top = world == .nether ? 26.0 : height(world,x:x,z:z)
                guard top > 0.5 else { continue }
                falls.cube(.init(0.9,top-0.35,0.045), at:.init(x,(top+0.35)/2,z+0.51), material:flow)
            }
            let streams = falls.node("waterfalls")
            streams.runAction(.repeatForever(.customAction(duration:128) { node,elapsed in
                var transform = SCNMatrix4Identity
                transform.m42 = -elapsed / 2
                node.geometry?.firstMaterial?.diffuse.contentsTransform = transform
            }))
            scene.rootNode.addChildNode(streams)
        }
        if world == .overworld || world == .sift {
            let cloud = VoxelAdventure.material(world == .overworld ? [0xF2F2EB,0xEBEBE5,0xFAF8F0] : [0xD7D5E6,0xE4DDEC,0xC8C8DD])
            for index in 0..<8 {
                var shape = Voxels()
                shape.cube(.init(6,1.2,3), at: .init(0,0,0), material: cloud)
                shape.cube(.init(3.5,0.8,2.5), at: .init(1.2,0.9,0), material: cloud)
                let node = shape.node("drifting-cloud")
                node.position = SCNVector3(Double(index % 4 - 2) * 17, 15 + Double(index % 3) * 2, -22 + Double(index / 4) * 24)
                node.runAction(.repeatForever(.sequence([.moveBy(x: 9, y: 0, z: 0, duration: 35 + Double(index)),
                                                        .moveBy(x: -9, y: 0, z: 0, duration: 35 + Double(index))])))
                scene.rootNode.addChildNode(node)
            }
        }
        populate(scene, world: world, palette: palette)
        focus(scene, biome: 0, animated: false)
        return scene
    }

    static func focus(_ scene: SCNScene, biome: Int, animated: Bool) {
        let camera = scene.rootNode.childNode(withName: "camera", recursively: false)!
        let x = Double(min(2, max(0, biome)) - 1) * 18
        let position = SCNVector3(x + 15, 13.5, 24)
        let aim = SCNVector3(x + 1, 4, -7)
        let orientation = SCNNode()
        orientation.position = position
        orientation.look(at: aim)
        camera.removeAction(forKey: "journey")
        let pan = SCNAction.repeatForever(.sequence([.moveBy(x: -0.8, y: 0.15, z: -0.4, duration: 8),
                                                    .moveBy(x: 0.8, y: -0.15, z: 0.4, duration: 8)]))
        if animated {
            let turn = SCNAction.rotateTo(x: orientation.eulerAngles.x, y: orientation.eulerAngles.y,
                                          z: orientation.eulerAngles.z, duration: 6, usesShortestUnitArc: true)
            let move = SCNAction.move(to: position, duration: 6)
            move.timingMode = .easeInEaseOut
            turn.timingMode = .easeInEaseOut
            camera.runAction(.sequence([.group([move, turn]), pan]), forKey: "journey")
        } else {
            camera.position = position
            camera.orientation = orientation.orientation
            camera.runAction(pan, forKey: "journey")
        }
    }

    private static func travel(_ actor: SCNNode, points: [SCNVector3], duration: Double, turn: Bool = false) {
        actor.removeAllActions()
        actor.position = points[0]
        let actions = Array(points.dropFirst()) + [points[0]]
        actor.runAction(.repeatForever(.sequence(actions.enumerated().map { index, point in
            let action = SCNAction.move(to: point, duration: duration)
            action.timingMode = turn ? .linear : .easeInEaseOut
            guard turn else { return action }
            let previous = points[index]
            let heading = atan2(point.x - previous.x, point.z - previous.z)
            return .group([action, .rotateTo(x: actor.eulerAngles.x, y: heading, z: actor.eulerAngles.z,
                                            duration: 1.8, usesShortestUnitArc: true)])
        })))
    }

    private static func populate(_ scene: SCNScene, world: World, palette: Palette) {
        let name = world == .overworld ? "happy-ghast" : world == .nether ? "ghast" : world == .end ? "dragon" : "sift-rift"
        let principal = scene.rootNode.childNode(withName: name, recursively: false)!
        principal.removeFromParentNode()
        principal.removeAllActions()
        let ground = world == .overworld ? pig() : world == .nether ? strider() : world == .end ? enderman() : illager()
        let flyer = world == .overworld ? bee() : world == .sift ? allay() : nil
        for biome in 0..<3 {
            let centre = Double(biome - 1) * 18
            let count = world == .overworld ? (biome == 1 ? 0 : 3) : world == .sift ? biome + 1 : (biome == 1 ? 2 : 3)
            let residents = world == .overworld && biome == 2 ? turtle() : ground
            for index in 0..<count {
                let mob = residents.clone()
                mob.name = "resident-\(biome)-\(index)"
                if world == .overworld && index == 2 { mob.scale = SCNVector3(0.65,0.65,0.65) }
                let x = centre + 4 + Double(index) * 1.7
                let z = world == .nether ? -8 + sin(x * 0.13) * 2.5 : 2 + sin(Double(index) * 2.3) * 1.3
                func position(_ x: Double, _ z: Double) -> SCNVector3 {
                    .init(x, world == .nether ? 0.35 : max(0.35, height(world,x:x.rounded(),z:z.rounded())), z)
                }
                mob.eulerAngles.y = index.isMultiple(of: 2) ? -0.4 : 1.4
                travel(mob, points: [position(x,z), position(x+1,z+0.4), position(x-0.5,z+0.7)], duration: 7 + Double(index) * 3, turn: true)
                scene.rootNode.addChildNode(mob)
            }
            if let flyer, world != .overworld || biome == 1 {
                for index in 0..<(biome == 1 ? 3 : 2) {
                    let mob = flyer.clone()
                    mob.name = "forager-\(biome)-\(index)"
                    let x = centre + 4 + Double(index) * 2
                    travel(mob, points: [.init(x,5.8,1), .init(x-1,6.8,-1), .init(x+2,5.9,2)], duration: 4 + Double(index))
                    scene.rootNode.addChildNode(mob)
                }
            }
            if world == .sift && biome == 2 {
                let portal = principal.clone()
                portal.name = "sift-rift-\(biome)"
                portal.scale = SCNVector3(2.3,2.3,2.3)
                portal.position = SCNVector3(centre + 2,6,-9)
                scene.rootNode.addChildNode(portal)
            }
        }
        if world == .overworld || world == .nether {
            for index in 0..<2 {
                let mob = principal.clone()
                mob.name = "sky-resident-\(index)"
                let scale = index == 0 ? 1.5 : 0.85
                mob.scale = SCNVector3(scale,scale,scale)
                let y = index == 0 ? 8.2 : 11
                let z = index == 0 ? 4.0 : -16
                travel(mob, points: [.init(-11,y,z), .init(7,y+1,z-2), .init(25,y,z-1)], duration: index == 0 ? 18 : 23)
                scene.rootNode.addChildNode(mob)
            }
        }
        if world == .end {
            principal.scale = SCNVector3(1.1,1.1,1.1)
            travel(principal, points: [.init(-10,11,4), .init(4,13,-4), .init(25,11,-5)], duration: 18, turn: true)
            scene.rootNode.addChildNode(principal)
        }
    }

    private static func pig() -> SCNNode {
        let mob = SCNNode()
        let skin = VoxelAdventure.material([0xDB9CA0,0xEAAEB0,0xD18D94])
        let nose = VoxelAdventure.material([0xB8747E,0xC7868C,0xAA6874])
        let dark = VoxelAdventure.material([0x41323A,0x503C42])
        VoxelAdventure.block(mob,.init(0.72,0.58,1.15),.init(0,0.78,0),skin)
        let head = VoxelAdventure.block(mob,.init(0.58,0.58,0.58),.init(0,0.85,0.7),skin)
        VoxelAdventure.block(head,.init(0.29,0.18,0.12),.init(0,-0.08,0.34),nose)
        for x in [-0.18,0.18] {
            VoxelAdventure.block(head,.init(0.08,0.08,0.025),.init(x,0.06,0.3),dark)
            VoxelAdventure.block(head,.init(0.13,0.11,0.1),.init(x,0.31,0),skin)
            for z in [-0.38,0.36] {
                let leg = SCNNode()
                leg.position = SCNVector3(x,0.55,z)
                mob.addChildNode(leg)
                VoxelAdventure.block(leg,.init(0.22,0.55,0.22),.init(0,-0.275,0),skin)
                VoxelAdventure.sway(leg,x:0.16,period:1.7,phase:x*z>0 ? 0 : .pi)
            }
        }
        VoxelAdventure.sway(head,y:0.12,period:6)
        return mob
    }

    private static func bee() -> SCNNode {
        let mob = SCNNode()
        let gold = VoxelAdventure.material([0xE8B43B,0xF3C44E,0xDCA32C])
        let dark = VoxelAdventure.material([0x493B2D,0x5A4832])
        let glass = VoxelAdventure.material([0xDDECE9,0xEDF5EF]); glass.transparency = 0.6
        VoxelAdventure.block(mob,.init(0.48,0.45,0.75),.init(0,0,0),gold)
        for z in [-0.22,0.02] { VoxelAdventure.block(mob,.init(0.49,0.46,0.1),.init(0,0,z),dark) }
        for side in [-1.0,1.0] {
            VoxelAdventure.block(mob,.init(0.075,0.08,0.025),.init(side*0.14,0.04,0.39),dark)
            let wing = SCNNode()
            wing.position = SCNVector3(side*0.2,0.22,0)
            mob.addChildNode(wing)
            VoxelAdventure.block(wing,.init(0.42,0.015,0.48),.init(side*0.2,0,0),glass)
            VoxelAdventure.sway(wing,z:side*0.65,period:0.4)
        }
        return mob
    }

    private static func turtle() -> SCNNode {
        let mob = SCNNode()
        let shell = VoxelAdventure.material([0x547852,0x65885C,0x436749])
        let skin = VoxelAdventure.material([0x8CA36D,0xA0B77B,0x7C965E])
        let dark = VoxelAdventure.material([0x303C35,0x3E4D3E])
        VoxelAdventure.block(mob,.init(0.9,0.35,1.15),.init(0,0.28,0),shell)
        VoxelAdventure.block(mob,.init(0.36,0.25,0.4),.init(0,0.2,0.68),skin)
        for side in [-1.0,1.0] {
            VoxelAdventure.block(mob,.init(0.04,0.045,0.025),.init(side*0.12,0.23,0.89),dark)
            for z in [-0.4,0.35] {
                let fin = VoxelAdventure.block(mob,.init(0.38,0.09,0.28),.init(side*0.53,0.06,z),skin)
                VoxelAdventure.sway(fin,y:0.2,period:3,phase:side*z>0 ? 0 : .pi)
            }
        }
        return mob
    }

    private static func strider() -> SCNNode {
        let mob = SCNNode()
        let skin = VoxelAdventure.material([0xA94F59,0xBC6269,0x913E4F])
        let ash = VoxelAdventure.material([0xB8A8A7,0xC6B8B2,0xA6969C])
        let dark = VoxelAdventure.material([0x463642,0x58404B])
        VoxelAdventure.block(mob,.init(1.2,0.95,1.2),.init(0,1.65,0),skin)
        for side in [-1.0,1.0] {
            let leg = VoxelAdventure.block(mob,.init(0.16,1.2,0.18),.init(side*0.29,0.6,0),skin)
            VoxelAdventure.sway(leg,x:0.12,period:2.3,phase:side<0 ? 0 : .pi)
            VoxelAdventure.block(mob,.init(0.12,0.1,0.025),.init(side*0.3,1.72,0.61),dark)
            for index in 0..<3 {
                VoxelAdventure.block(mob,.init(0.4,0.045,0.045),.init(side*0.76,1.4+Double(index)*0.2,0),ash)
            }
        }
        return mob
    }

    private static func enderman() -> SCNNode {
        let mob = SCNNode()
        let skin = VoxelAdventure.material([0x25212C,0x2C2633,0x201C27])
        let eye = VoxelAdventure.material([0xC48AE5,0xDCA6F1]); eye.emission.contents = colour(0x8F43AE)
        VoxelAdventure.block(mob,.init(0.55,0.85,0.3),.init(0,1.8,0),skin)
        VoxelAdventure.block(mob,.init(0.62,0.62,0.62),.init(0,2.55,0),skin)
        for side in [-1.0,1.0] {
            VoxelAdventure.block(mob,.init(0.2,0.055,0.015),.init(side*0.16,2.6,0.32),eye)
            VoxelAdventure.block(mob,.init(0.16,1.7,0.16),.init(side*0.4,1.32,0),skin)
            let leg = VoxelAdventure.block(mob,.init(0.16,1.4,0.16),.init(side*0.16,0.7,0),skin)
            VoxelAdventure.sway(leg,x:0.06,period:3,phase:side<0 ? 0 : .pi)
        }
        return mob
    }

    private static func illager() -> SCNNode {
        let mob = SCNNode()
        let skin = VoxelAdventure.material([0x92938B,0xA1A298,0x83857E])
        let coat = VoxelAdventure.material([0x655968,0x756575,0x594D5F])
        let dark = VoxelAdventure.material([0x333438,0x45434A])
        VoxelAdventure.block(mob,.init(0.65,0.85,0.38),.init(0,1.1,0),coat)
        VoxelAdventure.block(mob,.init(0.58,0.66,0.58),.init(0,1.85,0),skin)
        VoxelAdventure.block(mob,.init(0.17,0.28,0.2),.init(0,1.72,0.38),skin)
        VoxelAdventure.block(mob,.init(0.75,0.18,0.23),.init(0,1.2,0.3),skin)
        for side in [-1.0,1.0] {
            VoxelAdventure.block(mob,.init(0.12,0.08,0.025),.init(side*0.17,1.9,0.3),dark)
            let leg = VoxelAdventure.block(mob,.init(0.25,0.7,0.27),.init(side*0.17,0.35,0),dark)
            VoxelAdventure.sway(leg,x:0.1,period:2.1,phase:side<0 ? 0 : .pi)
        }
        return mob
    }

    private static func allay() -> SCNNode {
        let mob = SCNNode()
        let blue = VoxelAdventure.material([0x6FCBE0,0x83DDEE,0x57B5D1])
        let pale = VoxelAdventure.material([0xDCF5F3,0xEDFDFC])
        let wing = VoxelAdventure.material([0xA6E2E8,0xBDEFF0]); wing.transparency = 0.6
        VoxelAdventure.block(mob,.init(0.42,0.42,0.42),.init(0,0.3,0),blue)
        VoxelAdventure.block(mob,.init(0.22,0.32,0.18),.init(0,-0.07,0),blue)
        for side in [-1.0,1.0] {
            VoxelAdventure.block(mob,.init(0.075,0.1,0.02),.init(side*0.11,0.3,0.22),pale)
            VoxelAdventure.block(mob,.init(0.09,0.3,0.1),.init(side*0.2,-0.03,0.03),blue)
            let fin = SCNNode()
            fin.position = SCNVector3(side*0.1,0,-0.12)
            mob.addChildNode(fin)
            VoxelAdventure.block(fin,.init(0.4,0.5,0.02),.init(side*0.18,0.05,0),wing)
            VoxelAdventure.sway(fin,y:side*0.8,period:0.7)
        }
        return mob
    }
}
