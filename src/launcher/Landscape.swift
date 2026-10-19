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
                       top: SCNMaterial? = nil, faces: Int = 63, textureUV: [CGRect]? = nil, faceMaterials: [SCNMaterial]? = nil) {
        for face in 0..<6 where faces & (1 << face) != 0 {
            let surface = faceMaterials?[face] ?? (face == 4 ? (top ?? material) : material)
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
            if let rect = textureUV?[face] {
                uv.append(contentsOf: [.init(x:rect.origin.x,y:rect.origin.y), .init(x:rect.origin.x+rect.size.width,y:rect.origin.y),
                    .init(x:rect.origin.x+rect.size.width,y:rect.origin.y+rect.size.height), .init(x:rect.origin.x,y:rect.origin.y+rect.size.height)])
            } else {
                uv.append(contentsOf: [.init(x:0,y:height), .init(x:width,y:height), .init(x:width,y:0), .init(x:0,y:0)])
            }
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

enum Landscape {
    static let spacing = 32.0

    static func colour(_ rgb: UInt32) -> NSColor {
        NSColor(srgbRed:Double((rgb >> 16) & 255)/255,green:Double((rgb >> 8) & 255)/255,
                blue:Double(rgb & 255)/255,alpha:1)
    }

    private static func zone(_ x: Double) -> Int { min(2,max(0,Int(floor((x+spacing*1.5)/spacing)))) }

    static func height(_ biome: Biome, x: Double, z: Double, centre: Double) -> Double {
        let local = x-centre
        if [.central,.highlands,.midlands,.islands,.barrens,.city].contains(biome) {
            let radius = biome == .islands ? 10.0 : biome == .barrens ? 13.0 : biome == .city ? 22 : 16
            if hypot(local/1.15,z+6) > radius { return -10 }
            return floor(max(1,3+cos(local*0.2)+sin(z*0.3)))
        }
        if biome == .coast && z < 7 { return 0 }
        if biome == .lush && (-5...9).contains(local) && abs(z-4) < 4 { return 0 }
        if biome == .mangrove { return abs(sin(x*0.45)+cos(z*0.5)) < 0.6 ? 0 : 1 }
        if !biome.underground && abs(z+9-sin(x*0.09)*3) < 2.8 { return 0 }
        let wave = sin(x*0.12)*1.6+cos(z*0.16)*1.4
        if biome == .meadow {
            let blend = max(0,min(1,(24-hypot(local,(z+14)*0.9))/6))
            return floor(max(1,(3+wave)*(1-blend)+3*blend))
        }
        switch biome {
        case .peaks, .snow: return floor(max(1,3+wave+max(0,-z-12)*(biome == .peaks ? 0.6 : 0.25)))
        case .desert: return floor(max(1,2+sin(x*0.1+z*0.08)*2))
        case .badlands: return floor(max(1,3+wave+max(0,-z-20)*0.3))
        case .lush, .deep: return floor(max(1,2+sin(x*0.15)*cos(z*0.15)))
        case .wastes, .crimson, .warped, .soul, .basalt: return floor(max(1,3+sin(x*0.12)*cos(z*0.13)*2.5))
        default: return floor(max(1,3+wave+max(0,-z-25)*0.12))
        }
    }

    static func scene(_ world: World, biome: Int = 0, assets: Assets) throws -> SCNScene {
        let scene = SCNScene(), factory = Mobs(assets:assets), areas = world.areas(biome)
        let camera = SCNNode(); camera.name = "camera"; camera.camera = SCNCamera()
        camera.camera?.fieldOfView = 48; camera.camera?.zFar = 220
        camera.camera?.wantsHDR = true; camera.camera?.wantsExposureAdaptation = false
        camera.camera?.exposureOffset = -0.3; camera.camera?.bloomIntensity = 0.15
        camera.camera?.bloomThreshold = 1.2; camera.camera?.screenSpaceAmbientOcclusionIntensity = 0.7
        camera.camera?.screenSpaceAmbientOcclusionRadius = 1.2
        scene.rootNode.addChildNode(camera)
        let sun = SCNNode(); sun.light = SCNLight(); sun.light?.type = .directional
        sun.light?.intensity = 850; sun.eulerAngles = .init(-0.65,-0.6,0)
        sun.light?.castsShadow = true; sun.light?.shadowMode = .deferred
        sun.light?.shadowMapSize = .init(width:1024,height:1024); sun.light?.shadowSampleCount = 4
        sun.light?.shadowColor = NSColor.black.withAlphaComponent(0.28); sun.light?.maximumShadowDistance = 90
        scene.rootNode.addChildNode(sun)
        let fill = SCNNode(); fill.light = SCNLight(); fill.light?.type = .ambient
        scene.rootNode.addChildNode(fill)
        func heightAt(_ x: Double, _ z: Double) -> Double {
            let slot = zone(x)
            return height(areas[slot],x:x,z:z,centre:Double(slot-1)*spacing)
        }
        let terrain = try areas.map { try assets.tiles($0.surface) }
        let rock = try assets.tiles(world == .nether ? "netherrack" : world == .end ? "end_stone" : "stone")
        var land = Voxels()
        for x in -100...100 {
            for z in -85...35 {
                let h = heightAt(Double(x),Double(z))
                guard h >= 0 else { continue }
                let slot = zone(Double(x))
                var cap = 16, sides = 0
                for (face,d) in [(0,(0,1)),(1,(1,0)),(2,(0,-1)),(3,(-1,0))] {
                    let neighbour = heightAt(Double(x+d.0),Double(z+d.1))
                    if neighbour < h { cap |= 1 << face }
                    if neighbour < h-1 { sides |= 1 << face }
                }
                let bottom = world == .end ? -4.0 : -6
                land.cube(.init(1,1,1),at:.init(Double(x),h-0.5,Double(z)),material:terrain[slot][0],faces:cap,faceMaterials:terrain[slot])
                land.cube(.init(1,max(0.1,h-1-bottom),1),at:.init(Double(x),(h-1+bottom)/2,Double(z)),material:rock[0],faces:sides | (world == .end ? 32 : 0),faceMaterials:rock)
            }
        }
        for slot in 0..<3 {
            let area = areas[slot], centre = Double(slot-1)*spacing
            for index in 0..<20 {
                let x = centre+Double(index%5-2)*5
                let z = -42+Double(index/5)*13+sin(Double(index)*2.1)*2
                let y = heightAt(x.rounded(),z.rounded())
                guard y > 0, !(abs(x-centre)<16 && (-36 ... 2).contains(z)) else { continue }
                if let tree = area.tree {
                    let bark = try assets.tiles(tree+"_log"), leaves = try assets.tiles(tree+"_leaves")
                    let tall = tree == "jungle" ? 8 : tree == "spruce" ? 6 : 4+index%2
                    for level in 0..<tall {
                        land.cube(.init(1,1,1),at:.init(x,y+Double(level)+0.5,z),material:bark[0],faceMaterials:bark)
                    }
                    var canopy = Voxels()
                    func leaf(_ x: Int, _ y: Int, _ z: Int) -> Bool {
                        guard (0..<4).contains(y) else { return false }
                        let radius = tree == "spruce" ? max(0,2-y) : y < 2 ? 2 : 1
                        return abs(x) <= radius && abs(z) <= radius && (radius == 0 || !(abs(x)==radius && abs(z)==radius))
                    }
                    for level in 0..<4 {
                        let radius = tree == "spruce" ? max(0,2-level) : level < 2 ? 2 : 1
                        for dx in -radius...radius {
                            for dz in -radius...radius where radius == 0 || !(abs(dx)==radius && abs(dz)==radius) {
                                let faces = [[0,0,1],[1,0,0],[0,0,-1],[-1,0,0],[0,1,0],[0,-1,0]].enumerated().reduce(0) {
                                    $0 | (leaf(dx+$1.element[0],level+$1.element[1],dz+$1.element[2]) ? 0 : 1 << $1.offset)
                                }
                                canopy.cube(.init(1,1,1),at:.init(Double(dx),Double(level)-1.5,Double(dz)),material:leaves[0],faces:faces,faceMaterials:leaves)
                            }
                        }
                    }
                    let crown = canopy.node("wind-canopy")
                    crown.position = .init(x,y+Double(tall),z)
                    VoxelAdventure.sway(crown,x:0.004,z:0.006,period:8+Double(index%3),phase:Double(index))
                    scene.rootNode.addChildNode(crown)
                    if area == .mangrove {
                        for side in [-1.0,1] { land.cube(.init(1,2,1),at:.init(x+side,y,z),material:bark[0],faceMaterials:bark) }
                    }
                } else if world == .end && area != .central && area != .barrens {
                    let chorus = try assets.tiles("chorus_plant"), flower = try assets.tiles("chorus_flower")
                    let tall = 3+index%3
                    for level in 0..<tall { land.cube(.init(0.75,1,0.75),at:.init(x,y+Double(level)+0.5,z),material:chorus[0],faceMaterials:chorus) }
                    land.cube(.init(1,1,1),at:.init(x,y+Double(tall)+0.5,z),material:flower[0],faceMaterials:flower)
                } else if area == .crimson || area == .warped {
                    let stem = try assets.tiles(area == .crimson ? "crimson_stem" : "warped_stem")
                    let cap = try assets.tiles(area == .crimson ? "nether_wart_block" : "warped_wart_block")
                    for level in 0..<5 { land.cube(.init(1,1,1),at:.init(x,y+Double(level)+0.5,z),material:stem[0],faceMaterials:stem) }
                    for dx in -2...2 { for dz in -2...2 {
                        land.cube(.init(1,1,1),at:.init(x+Double(dx),y+5.5,z+Double(dz)),material:cap[0],faceMaterials:cap)
                    } }
                } else if area == .basalt {
                    let basalt = try assets.tiles("basalt"), tall = Double(2+index%6)
                    land.cube(.init(1,tall,1),at:.init(x,y+tall/2,z),material:basalt[0],faceMaterials:basalt)
                } else if area == .desert || area == .badlands {
                    let cactus = try assets.tiles("cactus")
                    land.cube(.init(0.875,2+Double(index%2),0.875),at:.init(x,y+1+Double(index%2)/2,z),material:cactus[0],faceMaterials:cactus)
                } else if area == .mushroom {
                    let stem = try assets.tiles("mushroom_stem"), cap = try assets.tiles(index%2 == 0 ? "red_mushroom_block" : "brown_mushroom_block")
                    let tall = Double(4+index%3)
                    land.cube(.init(1,tall,1),at:.init(x,y+tall/2,z),material:stem[0],faceMaterials:stem)
                    for dx in -2...2 { for dz in -2...2 {
                        land.cube(.init(1,1,1),at:.init(x+Double(dx),y+tall+0.5,z+Double(dz)),material:cap[0],faceMaterials:cap)
                    } }
                } else if area == .terraces {
                    let coral = try assets.texture("textures/blocks/coral_"+["blue","pink","purple","red","yellow"][index%5])
                    land.cube(.init(1,1+Double(index%3),1),at:.init(x,y+Double(1+index%3)/2,z),material:coral)
                } else if area == .valley || area == .shards {
                    let amethyst = try assets.tiles("amethyst_block")
                    let tall = Double(2+index%4)
                    land.cube(.init(1,tall,1),at:.init(x,y+tall/2,z),material:amethyst[0],faceMaterials:amethyst)
                } else if area == .lush {
                    let moss = try assets.tiles("moss_block")
                    land.cube(.init(1,3,1),at:.init(x,14,z),material:rock[0],faceMaterials:rock)
                    land.cube(.init(1,1,1),at:.init(x,12,z),material:moss[0],faceMaterials:moss)
                }
            }
            if world.page(biome)*3+slot < world.biomes.count {
                scene.rootNode.addChildNode(try Structures.build(area,x:centre,y:max(1,heightAt(centre,-18))-1,assets:assets))
            }
        }
        if areas.allSatisfy(\.underground) { land.cube(.init(205,6,125),at:.init(0,42,-25),material:rock[0],faceMaterials:rock) }
        if world == .nether { land.cube(.init(205,4,125),at:.init(0,32,-25),material:rock[0],faceMaterials:rock) }
        scene.rootNode.addChildNode(land.node("terrain"))
        if world == .overworld || world == .nether {
            let material = try assets.texture(world == .nether ? "textures/blocks/lava_still" : "textures/blocks/water_still_grey",tint:world == .nether ? nil : 0x3F76E4).copy() as! SCNMaterial
            material.transparency = world == .nether ? 1 : 0.72
            if world == .nether { material.emission.contents = material.diffuse.contents; material.emission.intensity = 0.4 }
            material.diffuse.contentsTransform = SCNMatrix4MakeScale(210,130,1)
            let plane = SCNPlane(width:210,height:130); plane.firstMaterial = material
            let water = SCNNode(geometry:plane); water.name = "flowing-surface"
            water.position = .init(0,0.35,-25); water.eulerAngles.x = -.pi/2
            water.runAction(.repeatForever(.customAction(duration:128) { node,time in
                var transform = SCNMatrix4MakeScale(210,130,1); transform.m41 = time/12; transform.m42 = time/18
                node.geometry?.firstMaterial?.diffuse.contentsTransform = transform
            }))
            scene.rootNode.addChildNode(water)
        }
        if world == .overworld && !areas[0].underground || world == .sift {
            let white = SCNMaterial(); white.diffuse.contents = NSColor.white; white.lightingModel = .constant
            for index in 0..<7 {
                var shape = Voxels()
                shape.cube(.init(10,1,5),at:.init(0,0,0),material:white)
                shape.cube(.init(6,1,4),at:.init(3,0,3),material:white)
                let cloud = shape.node("drifting-cloud"); cloud.position = .init(Double(index%4-2)*28,27+Double(index%2)*3,-45+Double(index/4)*40)
                cloud.runAction(.repeatForever(.sequence([.moveBy(x:12,y:0,z:0,duration:45),.moveBy(x:-12,y:0,z:0,duration:45)])))
                scene.rootNode.addChildNode(cloud)
            }
        }
        for slot in 0..<3 {
            let glow = SCNNode(); glow.light = SCNLight(); glow.light?.type = .omni
            glow.light?.color = colour(world == .nether ? 0xF5B184 : 0xA2D2C7)
            glow.light?.intensity = areas[slot].underground ? 450 : world == .nether ? 300 : 0
            glow.light?.attenuationEndDistance = 35; glow.position = .init(Double(slot-1)*spacing+5,9,0)
            scene.rootNode.addChildNode(glow)
        }
        try populate(scene,world:world,areas:areas,start:world.page(biome)*3,factory:factory)
        focus(scene,world:world,biome:biome,animated:false)
        return scene
    }

    static func focus(_ scene: SCNScene, world: World, biome: Int, animated: Bool) {
        let safe = world.index(biome), area = world.biomes[safe]
        let camera = scene.rootNode.childNode(withName:"camera",recursively:false)!
        let x = Double(safe%3-1)*spacing
        let eye: SCNVector3, aim: SCNVector3
        if area == .city { eye = .init(x+32,26,58); aim = .init(x+9,14,-18) }
        else if area == .deep { eye = .init(x+22,22,36); aim = .init(x+3,8,-14) }
        else if area == .lush { eye = .init(x+13,10,24); aim = .init(x+1,3,-7) }
        else { eye = .init(x+17,15,32); aim = .init(x+1,4,-8) }
        let orientation = SCNNode(); orientation.position = eye; orientation.look(at:aim)
        scene.background.contents = colour(area.sky); scene.fogColor = colour(area.sky)
        scene.fogStartDistance = 55; scene.fogEndDistance = 150
        for light in scene.rootNode.childNodes.compactMap(\.light) {
            if light.type == .ambient { light.intensity = area.underground ? 320 : area == .pale ? 240 : 450 }
            if light.type == .directional { light.intensity = area.underground ? 350 : area == .pale ? 400 : 850 }
        }
        for resident in scene.rootNode.childNodes where resident.name?.hasPrefix("resident-creaking-") == true { resident.isHidden = area != .pale }
        if world == .end { scene.rootNode.childNode(withName:"sky-resident",recursively:false)?.isHidden = area != .central }
        camera.removeAction(forKey:"journey")
        let drift = SCNAction.repeatForever(.sequence([.moveBy(x:-0.6,y:0.1,z:-0.3,duration:9),.moveBy(x:0.6,y:-0.1,z:0.3,duration:9)]))
        if animated {
            let move = SCNAction.move(to:eye,duration:6)
            let turn = SCNAction.rotateTo(x:orientation.eulerAngles.x,y:orientation.eulerAngles.y,z:orientation.eulerAngles.z,duration:6,usesShortestUnitArc:true)
            move.timingMode = .easeInEaseOut; turn.timingMode = .easeInEaseOut
            camera.runAction(.sequence([.group([move,turn]),drift]),forKey:"journey")
        } else {
            camera.position = eye; camera.orientation = orientation.orientation
            camera.runAction(drift,forKey:"journey")
        }
    }

    private static func populate(_ scene: SCNScene, world: World, areas: [Biome], start: Int, factory: Mobs) throws {
        for slot in 0..<min(3,world.biomes.count-start) {
            let area = areas[slot], centre = Double(slot-1)*spacing
            for (kind,species) in area.residents.enumerated() {
                for index in 0..<(species == .warden || species == .creaking || species == .ghast || species == .ironGolem ? 1 : 2) {
                    let actor = SCNNode(); actor.name = "resident-\(species.rawValue)-\(slot)-\(index)"
                    let model = try factory.make(species,biome:area)
                    actor.addChildNode(model)
                    if !species.flying && !species.swimming { model.position.y = max(0,-model.boundingBox.min.y) }
                    let spots: [(Double,Double)] = [(8,8),(11,10),(1,5),(3,8),(13,2),(15,5),(7,-1),(9,2),(17,8),(19,10),(13,-3),(17,-1)]
                    let spot = spots[(kind*2+index)%spots.count]
                    let x = centre+spot.0
                    let z = species.swimming ? 3+Double(index)*0.6 : species == .strider ? -9+sin(x*0.09)*3 : area == .coast ? 9+Double(index) : spot.1
                    func point(_ x: Double, _ z: Double) -> SCNVector3 {
                        let h = height(area,x:x.rounded(),z:z.rounded(),centre:centre)
                        return .init(x,species.swimming ? 0.1 : species == .strider ? 0.35 : max(0.35,h)+(species.flying ? 4 : 0),z)
                    }
                    if species == .shulker { actor.position = point(x,z) }
                    else { travel(actor,points:[point(x,z),point(x+1,z+0.4),point(x-0.6,z+0.6)],duration:8+Double(kind+index)*2) }
                    scene.rootNode.addChildNode(actor)
                }
            }
        }
        if world == .end && areas.contains(.central) || world == .nether || world == .overworld && !areas[0].underground && !areas.contains(.pale) {
            let group = SCNNode(); group.name = "sky-resident"
            let model = try factory.actor(world == .end ? "ender_dragon" : world == .nether ? "ghast" : "happy_ghast",texture:world == .overworld ? "happy_ghast" : "default")
            group.addChildNode(model)
            travel(group,points:[.init(-25,13,0),.init(7,16,-12),.init(40,13,-5)],duration:24)
            scene.rootNode.addChildNode(group)
        }
    }

    private static func travel(_ actor: SCNNode, points: [SCNVector3], duration: Double) {
        actor.position = points[0]
        let actions = (Array(points.dropFirst())+[points[0]]).enumerated().map { index,point -> SCNAction in
            let previous = points[index], heading = atan2(point.x-previous.x,point.z-previous.z)
            let move = SCNAction.move(to:point,duration:duration); move.timingMode = .easeInEaseOut
            return .group([move,.rotateTo(x:0,y:heading,z:0,duration:2,usesShortestUnitArc:true)])
        }
        actor.runAction(.repeatForever(.sequence(actions)))
    }
}
