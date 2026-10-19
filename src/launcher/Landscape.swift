import AppKit
import SceneKit

struct Voxels {
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
    static func colour(_ rgb: UInt32) -> NSColor {
        NSColor(srgbRed:Double((rgb >> 16) & 255)/255,green:Double((rgb >> 8) & 255)/255,
                blue:Double(rgb & 255)/255,alpha:1)
    }

    private static func zone(_ x: Double) -> Int { min(2,max(0,Int(floor((x+27)/18)))) }

    static func height(_ biome: Biome, x: Double, z: Double, centre: Double) -> Double {
        let local = x-centre
        if [.central,.highlands,.midlands,.islands,.barrens,.city].contains(biome) {
            let radius = biome == .islands ? 7.5 : biome == .barrens ? 9.0 : 12.0
            if hypot(local/1.15,z+4) > radius { return -10 }
            return floor(max(1,3+cos(local*0.2)+sin(z*0.3)))
        }
        if biome == .coast && z < 6 { return 0 }
        if biome == .lush && (-4...7).contains(local) && abs(z-4) < 3 { return 0 }
        if biome == .mangrove { return abs(sin(x*0.45)+cos(z*0.5)) < 0.5 ? 0 : 1 }
        if abs(z+8-sin(x*0.13)*2.5) < 2.4 { return 0 }
        let wave = sin(x*0.18)*1.6+cos(z*0.24)*1.4
        switch biome {
        case .peaks, .snow: return floor(max(1,3+wave+max(0,-z-8)*(biome == .peaks ? 0.8 : 0.3)))
        case .desert: return floor(max(1,2+sin(x*0.16+z*0.1)*2))
        case .badlands: return floor(max(1,3+wave+max(0,-z-15)*0.45))
        case .lush, .deep: return floor(max(1,2+sin(x*0.2)*cos(z*0.2)))
        case .wastes, .crimson, .warped, .soul, .basalt: return floor(max(1,3+sin(x*0.2)*cos(z*0.18)*2.5))
        default: return floor(max(1,3+wave+max(0,-z-20)*0.18))
        }
    }

    static func scene(_ world: World, biome: Int = 0) -> SCNScene {
        let scene = VoxelAdventure.scene(world), factory = Mobs()
        let areas = world.areas(biome)
        func heightAt(_ x: Double, _ z: Double) -> Double {
            let slot = zone(x)
            return height(areas[slot],x:x,z:z,centre:Double(slot-1)*18)
        }
        let camera = scene.rootNode.childNode(withName:"camera",recursively:false)!
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
            light.shadowMapSize = CGSize(width:1024,height:1024)
            light.shadowSampleCount = 4
            light.shadowColor = NSColor.black.withAlphaComponent(0.28)
            light.maximumShadowDistance = 75
        }
        let rock = factory.paint(world == .nether ? 0x652C36 : world == .end ? 0xC2BB88 : world == .sift ? 0xBE758F : areas[0].underground ? 0x484C54 : 0x858D8F)
        let tops = areas.map { factory.paint($0.ground) }
        let leaves = areas.map { factory.paint($0.foliage) }
        let soil = areas.map { VoxelAdventure.material([world == .nether ? 0x652C36 : world == .end ? 0xC2BB88 : 0x806047],cap:[$0.ground]) }
        var land = Voxels()
        // Buried faces are omitted and static terrain shares a single mesh
        for x in -65...65 {
            for z in -60...25 {
                let h = heightAt(Double(x),Double(z))
                guard h >= 0 else { continue }
                let slot = zone(Double(x))
                var cap = 16, sides = 0
                for (face,offset) in [(0,(0,1)),(1,(1,0)),(2,(0,-1)),(3,(-1,0))] {
                    let neighbour = heightAt(Double(x+offset.0),Double(z+offset.1))
                    if neighbour < h { cap |= 1 << face }
                    if neighbour < h-1 { sides |= 1 << face }
                }
                let bottom = world == .end ? -3.0 : -5
                land.cube(.init(1,1,1),at:.init(Double(x),h-0.5,Double(z)),material:soil[slot],top:tops[slot],faces:cap)
                land.cube(.init(1,max(0.1,h-1-bottom),1),at:.init(Double(x),(h-1+bottom)/2,Double(z)),material:rock,faces:sides | (world == .end ? 32 : 0))
            }
        }
        for slot in 0..<3 {
            let area = areas[slot], centre = Double(slot-1)*18
            let wood = factory.paint(area == .pale ? 0xA5A89A : world == .nether ? 0x693643 : 0x68513D)
            for index in 0..<12 {
                let x = centre+Double(index%6-3)*3.4
                let z = -23+Double(index/6)*18+sin(Double(index)*2.1)*2
                let y = heightAt(x.rounded(),z.rounded())
                guard y > 0 else { continue }
                if world == .end {
                    guard area != .central && area != .barrens else { continue }
                    let tall = 2.5+Double(index%3)
                    land.cube(.init(0.45,tall,0.45),at:.init(x,y+tall/2,z),material:leaves[slot])
                    for side in [-1.0,1] {
                        land.cube(.init(1,0.4,0.4),at:.init(x+side*0.45,y+tall-0.7,z),material:leaves[slot])
                        land.cube(.init(0.45,0.9,0.45),at:.init(x+side*0.8,y+tall-0.25,z),material:leaves[slot])
                    }
                } else if area == .basalt {
                    let tall = 3+Double(index%4)*1.5
                    land.cube(.init(1.2,tall,1.2),at:.init(x,y+tall/2,z),material:tops[slot])
                } else if area == .desert || area == .badlands {
                    let green = factory.paint(0x61894C)
                    land.cube(.init(0.6,2.2,0.6),at:.init(x,y+1.1,z),material:green)
                    land.cube(.init(1.4,0.4,0.4),at:.init(x,y+1.3,z),material:green)
                } else if area == .soul || area == .wastes {
                    land.cube(.init(0.8,0.6,0.8),at:.init(x,y+0.3,z),material:factory.paint(area == .soul ? 0x6FD5D8 : 0xDB7E3A))
                } else if area.underground {
                    land.cube(.init(0.5,2+Double(index%3),0.5),at:.init(x,12,z),material:rock)
                    if area == .lush {
                        land.cube(.init(0.15,3,0.15),at:.init(x,10,z),material:leaves[slot])
                        land.cube(.init(0.3,0.3,0.3),at:.init(x,8.4,z),material:factory.paint(0xE8C76E))
                    }
                } else if area == .mushroom { continue }
                else {
                    let tall = area == .jungle ? 8.0 : area == .snow ? 5.5 : 3.5+Double(index%3)
                    land.cube(.init(0.6,tall,0.6),at:.init(x,y+tall/2,z),material:wood)
                    var crown = Voxels()
                    if area == .snow || area == .peaks {
                        for level in 0..<4 {
                            let span = 4.5-Double(level)
                            crown.cube(.init(span,0.7,span),at:.init(0,Double(level)*0.9-1.2,0),material:leaves[slot])
                            crown.cube(.init(span,0.1,span),at:.init(0,Double(level)*0.9-0.8,0),material:tops[slot])
                        }
                    } else if world == .sift {
                        for side in [-1.0,1] {
                            crown.cube(.init(0.5,2.4,0.5),at:.init(side*1.2,0.5,0),material:wood)
                            crown.cube(.init(2,0.8,1.5),at:.init(side*1.2,1.8,0),material:leaves[slot])
                        }
                    } else {
                        let wide = area == .jungle ? 5.5 : world == .nether ? 4.2 : 3.6
                        crown.cube(.init(wide,1.4,wide),at:.init(0,0,0),material:leaves[slot])
                        crown.cube(.init(wide-1,1,wide-1),at:.init(-0.4,1,0.3),material:leaves[slot])
                        if area == .jungle || area == .mangrove {
                            for side in [-1.0,1] { crown.cube(.init(0.15,3,0.15),at:.init(side*1.6,-1.2,1),material:leaves[slot]) }
                        }
                    }
                    let canopy = crown.node("wind-canopy")
                    canopy.position = .init(x,y+tall,z)
                    VoxelAdventure.sway(canopy,x:0.012,z:0.025,period:7+Double(index%3),phase:Double(index))
                    scene.rootNode.addChildNode(canopy)
                    if area == .mangrove {
                        for side in [-1.0,1] { land.cube(.init(0.3,2,0.3),at:.init(x+side*0.8,y+0.7,z),material:wood) }
                    }
                }
            }
            let landmark = Structures.build(area,x:centre,y:max(1,heightAt(centre,-14)),factory:factory)
            scene.rootNode.addChildNode(landmark)
            if area.underground {
                land.cube(.init(21,4,85),at:.init(centre,16,-17),material:rock)
            }
        }
        if world == .nether {
            land.cube(.init(132,4,88),at:.init(0,28,-18),material:rock)
            for i in 0..<16 { land.cube(.init(3,5+Double(i%3),3),at:.init(Double(i%8-4)*11,24,-25+Double(i/8)*23),material:rock) }
        }
        scene.rootNode.addChildNode(land.node("terrain"))
        if world != .end {
            let fluid = VoxelAdventure.material(world == .nether ? [0xEF8434,0xF9AF45,0xD75B27] : [0x399EA9,0x48AEB7,0x318C9E])
            fluid.transparency = world == .nether ? 1 : 0.82
            fluid.emission.contents = colour(world == .nether ? 0x9A3C13 : 0x082128)
            fluid.diffuse.contentsTransform = SCNMatrix4MakeScale(140,95,1)
            let surface = SCNPlane(width:140,height:95)
            surface.firstMaterial = fluid
            let water = SCNNode(geometry:surface)
            water.name = "flowing-surface"
            water.position = .init(0,0.35,-17)
            water.eulerAngles.x = -.pi/2
            water.runAction(.repeatForever(.customAction(duration:128) { node,elapsed in
                var transform = SCNMatrix4MakeScale(140,95,1)
                transform.m41 = elapsed/8; transform.m42 = elapsed/16
                node.geometry?.firstMaterial?.diffuse.contentsTransform = transform
            }))
            scene.rootNode.addChildNode(water)
            var falls = Voxels()
            let flow = fluid.copy() as! SCNMaterial
            flow.diffuse.contentsTransform = SCNMatrix4Identity
            for x in [-12.0,6,24] {
                let z = floor(-8+sin(x*0.13)*2.5-2.4), top = world == .nether ? 26 : heightAt(x,z)
                guard top > 0.5 else { continue }
                falls.cube(.init(0.9,top-0.35,0.045),at:.init(x,(top+0.35)/2,z+0.51),material:flow)
            }
            let streams = falls.node("waterfalls")
            streams.runAction(.repeatForever(.customAction(duration:128) { node,elapsed in
                var transform = SCNMatrix4Identity
                transform.m42 = -elapsed/2
                node.geometry?.firstMaterial?.diffuse.contentsTransform = transform
            }))
            scene.rootNode.addChildNode(streams)
        }
        let motes = SCNParticleSystem()
        motes.birthRate = 3; motes.particleLifeSpan = 8; motes.particleSize = 0.055
        motes.particleColor = colour(world == .nether ? 0xF5AD65 : 0xBCDEF1)
        motes.isLightingEnabled = false; motes.particleVelocity = 0.15
        motes.emitterShape = SCNBox(width:60,height:1,length:7,chamferRadius:0)
        let air = SCNNode(); air.name = "ambient-motes"; air.position = .init(0,5,-6)
        air.addParticleSystem(motes); scene.rootNode.addChildNode(air)
        for slot in 0..<3 {
            let light = SCNNode(); light.name = "habitat-light-\(slot)"; light.light = SCNLight()
            light.light?.type = .omni
            light.light?.color = colour(world == .nether ? 0xF6A269 : 0x96CDC8)
            light.light?.intensity = areas[slot].underground ? 400 : world == .nether ? 220 : 0
            light.light?.attenuationStartDistance = 2; light.light?.attenuationEndDistance = 23
            light.position = .init(Double(slot-1)*18+4,7,0); scene.rootNode.addChildNode(light)
        }
        if (world == .overworld && !areas[0].underground) || world == .sift {
            for index in 0..<6 {
                var shape = Voxels()
                shape.cube(.init(7,1.1,4),at:.init(0,0,0),material:factory.paint(0xF2F2EB))
                shape.cube(.init(4,0.9,3),at:.init(1,0.9,0),material:factory.paint(0xF2F2EB))
                let cloud = shape.node("drifting-cloud")
                cloud.position = .init(Double(index%3-1)*23,20+Double(index%3)*2,-30+Double(index/3)*22)
                cloud.runAction(.repeatForever(.sequence([.moveBy(x:9,y:0,z:0,duration:35),.moveBy(x:-9,y:0,z:0,duration:35)])))
                scene.rootNode.addChildNode(cloud)
            }
        }
        populate(scene,world:world,areas:areas,factory:factory)
        focus(scene,world:world,biome:biome,animated:false)
        return scene
    }

    static func focus(_ scene: SCNScene, world: World, biome: Int, animated: Bool) {
        let safe = world.index(biome), area = world.biomes[safe]
        let camera = scene.rootNode.childNode(withName:"camera",recursively:false)!
        let x = Double(safe%3-1)*18
        let position = SCNVector3(x+15,area.underground ? 9 : 13.5,24)
        let aim = SCNVector3(x+1,area.underground ? 3 : 4,-7)
        let orientation = SCNNode(); orientation.position = position; orientation.look(at:aim)
        scene.background.contents = colour(area.sky); scene.fogColor = colour(area.sky)
        scene.fogStartDistance = 38; scene.fogEndDistance = 92
        for light in scene.rootNode.childNodes.compactMap(\.light) {
            if light.type == .ambient { light.intensity = area.underground ? 300 : area == .pale ? 230 : 350 }
            if light.type == .directional {
                light.intensity = area.underground ? 450 : area == .pale ? 450 : 800
                light.color = colour(world == .nether ? 0xFFE0BF : world == .end ? 0xDED1FF : area == .pale ? 0xB4C4DB : 0xFFF2DF)
            }
        }
        // The Creaking appears only while its dusk habitat is in focus
        for resident in scene.rootNode.childNodes where resident.name?.hasPrefix("resident-creaking-") == true {
            resident.isHidden = area != .pale
        }
        camera.removeAction(forKey:"journey")
        let pan = SCNAction.repeatForever(.sequence([.moveBy(x:-0.8,y:0.15,z:-0.4,duration:8),.moveBy(x:0.8,y:-0.15,z:0.4,duration:8)]))
        if animated {
            let move = SCNAction.move(to:position,duration:6)
            let turn = SCNAction.rotateTo(x:orientation.eulerAngles.x,y:orientation.eulerAngles.y,z:orientation.eulerAngles.z,duration:6,usesShortestUnitArc:true)
            move.timingMode = .easeInEaseOut; turn.timingMode = .easeInEaseOut
            camera.runAction(.sequence([.group([move,turn]),pan]),forKey:"journey")
        } else {
            camera.position = position; camera.orientation = orientation.orientation
            camera.runAction(pan,forKey:"journey")
        }
    }

    private static func populate(_ scene: SCNScene, world: World, areas: [Biome], factory: Mobs) {
        let name = world == .overworld ? "happy-ghast" : world == .nether ? "ghast" : world == .end ? "dragon" : "sift-rift"
        let principal = scene.rootNode.childNode(withName:name,recursively:false)!
        principal.removeFromParentNode(); principal.removeAllActions()
        for slot in 0..<3 {
            let area = areas[slot], centre = Double(slot-1)*18
            for (kind,species) in area.residents.enumerated() {
                for index in 0..<(species == .warden || species == .creaking || species == .ghast ? 1 : 2) {
                    let group = SCNNode(); group.name = "resident-\(species.rawValue)-\(slot)-\(index)"
                    let model = factory.make(species)
                    let scale = species == .ghast ? 0.7 : species == .warden ? 1.35 : 1.6
                    model.scale = .init(scale,scale,scale)
                    if index == 1 && [.pig, .cow, .sheep, .turtle, .strider].contains(species) { model.scale = .init(scale*0.7,scale*0.7,scale*0.7) }
                    group.addChildNode(model)
                    let x = centre+Double(kind)*2.6-1+Double(index)*1.1
                    let z: Double
                    if species.swimming { z = 3+Double(index)*0.6 }
                    else if species == .strider { z = -8+sin(x*0.13)*2.5 }
                    else if area == .coast { z = 8+Double(index) }
                    else { z = 3+Double(index)*1.4-Double(kind%2)*2 }
                    func point(_ x: Double, _ z: Double) -> SCNVector3 {
                        let h = height(area,x:x.rounded(),z:z.rounded(),centre:centre)
                        let y = species.swimming ? 0.15 : species == .strider ? 0.35 : max(0.35,h)+(species.flying ? 4.5 : 0)
                        return .init(x,y,z)
                    }
                    travel(group,points:[point(x,z),point(x+0.8,z+0.3),point(x-0.5,z+0.6)],duration:6+Double(kind+index)*2)
                    scene.rootNode.addChildNode(group)
                }
            }
        }
        if world == .end || (world == .overworld && !areas[0].underground && !areas.contains(.pale)) || world == .nether {
            principal.name = world == .end ? "dragon" : "sky-resident"
            principal.scale = .init(world == .end ? 1.1 : 1.2,world == .end ? 1.1 : 1.2,world == .end ? 1.1 : 1.2)
            travel(principal,points:[.init(-11,11,1),.init(7,13,-8),.init(25,11,-5)],duration:18)
            scene.rootNode.addChildNode(principal)
        }
    }

    private static func travel(_ actor: SCNNode, points: [SCNVector3], duration: Double) {
        actor.position = points[0]
        let actions = (Array(points.dropFirst())+[points[0]]).enumerated().map { index,point -> SCNAction in
            let previous = points[index], heading = atan2(point.x-previous.x,point.z-previous.z)
            let move = SCNAction.move(to:point,duration:duration)
            move.timingMode = .easeInEaseOut
            return .group([move,.rotateTo(x:0,y:heading,z:0,duration:1.8,usesShortestUnitArc:true)])
        }
        actor.runAction(.repeatForever(.sequence(actions)))
    }
}
