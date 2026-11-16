import AppKit
import SceneKit
import simd

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

    mutating func transform(from first: Int, origin: SCNVector3, by node: SCNNode) {
        for index in first..<vertices.count {
            let point = vertices[index]
            vertices[index] = node.convertPosition(.init(point.x-origin.x,point.y-origin.y,point.z-origin.z),to:nil)
            normals[index] = node.convertVector(normals[index],to:nil)
        }
    }

    func node(_ name: String) -> SCNNode {
        let geometry = SCNGeometry(sources: [SCNGeometrySource(vertices: vertices),
            SCNGeometrySource(normals: normals), SCNGeometrySource(textureCoordinates: uv)],
            elements: indices.map { SCNGeometryElement(indices: $0, primitiveType: .triangles) })
        geometry.materials = materials
        let node = SCNNode(geometry: geometry)
        node.name = name
        node.categoryBitMask = 2
        return node
    }

    // Render partitions keep only the vertices they draw, including their matching UVs and normals
    func node(_ name: String, slots: [Int]) -> SCNNode {
        if slots.elementsEqual(materials.indices) {return node(name)}
        var compact = Voxels(), remap = [Int32](repeating:-1,count:vertices.count)
        for slot in slots {
            compact.materials.append(materials[slot])
            var triangles: [Int32] = []; triangles.reserveCapacity(indices[slot].count)
            for old in indices[slot] {
                let index = Int(old)
                if remap[index]<0 {
                    remap[index] = Int32(compact.vertices.count)
                    compact.vertices.append(vertices[index]); compact.normals.append(normals[index]); compact.uv.append(uv[index])
                }
                triangles.append(remap[index])
            }
            compact.indices.append(triangles)
        }
        return compact.node(name)
    }
}

enum Landscape {
    static func colour(_ rgb: UInt32) -> NSColor {
        NSColor(srgbRed:Double((rgb >> 16) & 255)/255,green:Double((rgb >> 8) & 255)/255,
                blue:Double(rgb & 255)/255,alpha:1)
    }

    static func height(_ biome: Biome, x: Double, z: Double, centre: Double = 0) -> Double {
        Terrain(biome:biome).height(x-centre,z)
    }

    static func stage() -> SCNScene {
        let scene = SCNScene()
        let camera = SCNNode(); camera.name = "camera"; camera.camera = SCNCamera()
        camera.camera?.fieldOfView = 67; camera.camera?.zFar = 230; camera.camera?.zNear = 0.1
        camera.camera?.wantsHDR = true; camera.camera?.wantsExposureAdaptation = false
        camera.camera?.exposureOffset = -0.15; camera.camera?.bloomIntensity = 0
        camera.camera?.screenSpaceAmbientOcclusionIntensity = 0
        scene.rootNode.addChildNode(camera)
        let sun = SCNNode(); sun.light = SCNLight(); sun.light?.type = .directional
        sun.name = "sunlight"
        sun.eulerAngles = .init(-0.8,-0.6,0); sun.light?.castsShadow = true
        sun.light?.shadowMode = .deferred; sun.light?.shadowMapSize = .init(width:2048,height:2048)
        sun.light?.shadowSampleCount = 4; sun.light?.shadowColor = NSColor.black.withAlphaComponent(0.28)
        sun.light?.maximumShadowDistance = 55; scene.rootNode.addChildNode(sun)
        let fill = SCNNode(); fill.name = "skylight"; fill.light = SCNLight(); fill.light?.type = .ambient
        scene.rootNode.addChildNode(fill)
        return scene
    }

    static func scene(_ world: World, biome: Int = 0, region destination: Region? = nil, terrain buildTerrain: Bool = true, assets: Assets) throws -> SCNScene {
        let area = world.biomes[world.index(biome)], scene = stage()
        if let passage = area.passage {
            let visit = try passage.scene(assets:assets)
            focus(visit,world:world,biome:biome,animated:true)
            return visit
        }
        let region = destination ?? Region.from(world.index(biome),count:world.biomes.count), origin = region.origin
        let terrain = Terrain(biome:area,authored:region.landmark(world),worldSeed:region.landmark(world) ? 0 : region.seed)
        func sample(_ x: Double, _ z: Double, surface: Bool = false) -> Terrain.Sample {
            Terrain.sample(world:world,at:.init(origin.x+x,surface ? 100 : area.level+8,origin.z+z),seed:region.seed)
        }
        func surface(_ x: Double, _ z: Double) -> Double { sample(x,z).height-area.level }
        var detail = Voxels()
        var crowns: [String:SCNGeometry] = [:]
        if terrain.authored {
            let landmark = try Structures.build(area,x:0,y:area == .coast ? 0 : area == .reef ? -7 : area == .monument ? -22 : area == .ice ? 2 : area == .swamp ? 0 : 4,assets:assets)
            scene.rootNode.addChildNode(landmark)
        }
        let foundations = Structures.foundations(scene.rootNode)
        if buildTerrain { scene.rootNode.addChildNode(try terrain.node(assets:assets,region:region,covered:foundations)) }
        else {
            let ground = Surface(); ground.name = "terrain"
            ground.profile = .init(terrain:terrain,sample:nil,covered:foundations); ground.registered = true
            scene.rootNode.addChildNode(ground)
        }
        func block(_ size: SCNVector3, _ at: SCNVector3, _ name: String) throws {
            let tiles = try assets.tiles(name)
            detail.cube(size,at:at,material:tiles[0],faceMaterials:tiles)
        }
        func sprite(_ name: String, x: Double, y: Double, z: Double, size: Double = 1, tint: UInt32? = nil) throws {
            let material = try assets.texture("textures/blocks/"+name,tint:tint)
            let uv = Array(repeating:CGRect(x:0,y:1,width:1,height:-1),count:6)
            let first = detail.vertices.count
            detail.cube(.init(size,size,0),at:.init(x,y+size/2,z),material:material,faces:1,textureUV:uv)
            detail.cube(.init(0,size,size),at:.init(x,y+size/2,z),material:material,faces:2,textureUV:uv)
            for index in first..<detail.vertices.count {
                let p = detail.vertices[index], n = detail.normals[index], c = sqrt(0.5)
                detail.vertices[index] = .init(x+(p.x-x)*c-(p.z-z)*c,p.y,z+(p.x-x)*c+(p.z-z)*c)
                detail.normals[index] = .init(n.x*c-n.z*c,n.y,n.x*c+n.z*c)
            }
        }
        let treeBiome = area.cover ?? area
        let trees = area.cover != nil ? 64 : [.jungle,.forest,.mansion,.pale,.mangrove].contains(treeBiome) ? 320 : treeBiome.tree == nil ? 0 : 170
        for index in 0..<max(180,trees) {
            let nearby = index < max(180,trees)/2
            let width = nearby ? 96.0 : Double(Region.span)*0.9
            let depth = nearby ? 104.0 : Double(Region.span)*0.9
            let x = (Terrain.random(index,3,seed:terrain.seed &+ region.seed)*width-width/2).rounded()
            let z = (Terrain.random(index,19,seed:terrain.seed &+ region.seed)*depth-depth/2-14).rounded()
            let ground = area.cover == nil ? surface(x,z) : sample(x,z,surface:true).height-area.level
            let y = area == .mangrove || area == .swamp ? max(0.35,ground) : ground
            let clearing = Terrain(biome:treeBiome,authored:terrain.authored && area.cover == nil).reserved(x,z) || area.level<0 && Terrain.entrance(x,z)
            if y <= 0 || y < -90 || area.cover != nil && sample(x,z,surface:true).fluid { continue }
            if index<trees, let selected = sample(x,z,surface:area.cover != nil).biome.tree, !clearing {
                let tree = area == .forest && index%4 == 0 ? "birch" : selected
                let bark = try assets.tiles(tree+"_log"), leaves = try assets.tiles(tree+"_leaves")
                let tall = tree == "jungle" ? 11+index%9 : tree == "spruce" ? 7+index%4 : tree == "dark_oak" ? 7 : 4+index%3
                let thick = tree == "jungle" && index%3 == 0 || tree == "dark_oak" ? 2.0 : 1
                let fork = tree == "acacia" || tree == "cherry"
                let trunk = Double(tall-(fork ? 2 : 0))
                detail.cube(.init(thick,trunk,thick),at:.init(x,y+trunk/2,z),material:bark[0],faceMaterials:bark)
                if fork {
                    for side in (tree == "cherry" ? [-1.0,1] : [index%2 == 0 ? -1.0 : 1]) {
                        for level in 0..<3 {
                            detail.cube(.init(1,1,1),at:.init(x+side*Double(level),y+trunk+Double(level)*0.5,z),material:bark[0],faceMaterials:bark)
                        }
                    }
                }
                if crowns[tree] == nil {
                    var canopy = Voxels()
                    func leaf(_ x: Int, _ y: Int, _ z: Int) -> Bool {
                        let levels = tree == "spruce" ? 6 : tree == "acacia" ? 2 : 4
                        guard (0..<levels).contains(y) else { return false }
                        let r = tree == "spruce" ? max(0,3-y/2-(y%2)) : tree == "acacia" ? 3-y : tree == "jungle" || tree == "dark_oak" || tree == "mangrove" || tree == "cherry" ? (y<2 ? 3 : 2) : (y<2 ? 2 : 1)
                        return abs(x)<=r && abs(z)<=r && (r == 0 || abs(x)+abs(z)<r*2)
                    }
                    for dy in 0..<6 { for dx in -3...3 { for dz in -3...3 where leaf(dx,dy,dz) {
                        let faces = [[0,0,1],[1,0,0],[0,0,-1],[-1,0,0],[0,1,0],[0,-1,0]].enumerated().reduce(0) {
                            $0 | (leaf(dx+$1.element[0],dy+$1.element[1],dz+$1.element[2]) ? 0 : 1 << $1.offset)
                        }
                        canopy.cube(.init(1,1,1),at:.init(Double(dx),Double(dy),Double(dz)),material:leaves[0],faces:faces,faceMaterials:leaves)
                    } } }
                    crowns[tree] = canopy.node("canopy").geometry
                }
                let crown = SCNNode(geometry:crowns[tree]); crown.name = "wind-canopy"; crown.categoryBitMask = 2
                crown.position = .init(x+(tree == "acacia" ? (index%2 == 0 ? -2 : 2) : 0),y+Double(tall)-(tree == "spruce" ? 4 : 1),z)
                VoxelAdventure.sway(crown,x:0.003,z:0.005,period:8+Double(index%4),phase:Double(index))
                scene.rootNode.addChildNode(crown)
                if area == .mangrove {
                    for side in [-1.0,1] {
                        try block(.init(1,3,1),.init(x+side,y,z),"mangrove_roots")
                        try block(.init(1,2,1),.init(x+side*2,y-1,z),"mangrove_roots")
                        try block(.init(1,2,1),.init(x,y-1,z+side*2),"mangrove_roots")
                    }
                }
                if area == .jungle || area == .swamp || area == .pale {
                    for level in 0..<3 { try sprite(area == .pale ? "pale_hanging_moss_middle" : "vine",x:x+thick/2+0.05,y:y+Double(tall-level)-1,z:z,size:2) }
                }
            }
            if area.cover != nil { continue }
            if !clearing {
                switch area {
                case .wastes, .crimson, .warped:
                    if area != .wastes && index%2 == 0 {
                        let warped = area == .warped, tall = Double(6+index%5)
                        try block(.init(1,tall,1),.init(x,y+tall/2,z),warped ? "warped_stem" : "crimson_stem")
                        for dx in -2...2 { for dz in -2...2 {
                            try block(.init(1,2,1),.init(x+Double(dx),y+tall,z+Double(dz)),warped ? "warped_wart_block" : "nether_wart_block")
                        } }
                        try block(.init(1,1,1),.init(x+1,y+tall-1,z+1),"shroomlight")
                        for level in 0..<3 { try sprite(warped ? "twisting_vines_base" : "weeping_vines",x:x+2,y:y+tall-Double(level)-2,z:z) }
                    } else { try sprite(area == .warped ? "warped_roots" : "crimson_roots",x:x,y:y,z:z) }
                case .basalt:
                    try block(.init(1,Double(3+index%12),1),.init(x,y+Double(3+index%12)/2,z),index%3 == 0 ? "blackstone" : "basalt")
                case .desert, .badlands:
                    if index%3 == 0 { try block(.init(0.875,Double(2+index%3),0.875),.init(x,y+Double(2+index%3)/2,z),"cactus") }
                    else { try sprite("deadbush",x:x,y:y,z:z) }
                case .mushroom:
                    let tall = Double(4+index%4)
                    if index%3 == 0 {
                        try block(.init(1,tall,1),.init(x,y+tall/2,z),"mushroom_stem")
                        try block(.init(5,1,5),.init(x,y+tall+0.5,z),index%2 == 0 ? "red_mushroom_block" : "brown_mushroom_block")
                        if index%2 == 0 { for side in [-2.0,2] { try block(.init(1,2,5),.init(x+side,y+tall-0.5,z),"red_mushroom_block") } }
                    } else { try sprite(index%2 == 0 ? "mushroom_red" : "mushroom_brown",x:x,y:y,z:z) }
                case .highlands, .midlands, .islands, .city:
                    let tall = Double(3+index%5)
                    try block(.init(0.75,tall,0.75),.init(x,y+tall/2,z),"chorus_plant")
                    try block(.init(1,1,1),.init(x,y+tall+0.5,z),"chorus_flower")
                    if index%2 == 0 {
                        try block(.init(2,0.75,0.75),.init(x+0.75,y+tall-1.5,z),"chorus_plant")
                        try block(.init(0.75,2,0.75),.init(x+1.5,y+tall-0.5,z),"chorus_plant")
                        try block(.init(1,1,1),.init(x+1.5,y+tall+0.5,z),"chorus_flower")
                    }
                case .terraces:
                    let coral = try assets.texture("textures/blocks/coral_"+["pink","purple","blue"][index%3])
                    let tall = Double(3+index%5)
                    detail.cube(.init(2,tall,2),at:.init(x,y+tall/2,z),material:coral)
                    detail.cube(.init(5,2,4),at:.init(x+1,y+tall,z),material:coral)
                case .valley, .shards: try block(.init(1,Double(3+index%6),1),.init(x,y+Double(3+index%6)/2,z),"amethyst_block")
                default: break
                }
            }
            if world == .overworld && !area.underground && !terrain.occupied(x,z) && ![.mushroom,.desert,.badlands,.coast,.reef,.peaks,.snow,.pale].contains(area), !(abs(x)<22 && (-40 ... -8).contains(z)) {
                try sprite(index%7 == 0 ? "flower_dandelion" : "tallgrass",x:x,y:y,z:z,tint:index%7 == 0 ? nil : 0x82B653)
            }
        }
        if world == .overworld || area == .grove {
            var plants: Set<Int> = []
            for index in 0..<2400 {
                let nearby = index < 1800
                let x = (Terrain.random(index,27,seed:5)*(nearby ? 72 : 104)-(nearby ? 36 : 52)).rounded()
                let z = (Terrain.random(index,37,seed:9)*(nearby ? 80 : 104)-(nearby ? 45 : 55)).rounded()
                let y = surface(x,z)
                guard plants.insert((Int(x)+100)*256+Int(z)+132).inserted else { continue }
                if y < -1, [.coast,.reef,.mangrove,.swamp,.lush].contains(area) {
                    try sprite(area == .mangrove || area == .swamp ? "reeds" : "seagrass",x:x,y:y,z:z,size:1.3,tint:0x78A73F)
                } else if y>0, !terrain.occupied(x,z), Terrain.noise(x,z,scale:7,seed:2) > -0.5 {
                    switch area {
                    case .meadow,.forest,.cherry,.savanna,.jungle,.swamp,.mansion,.grove:
                        try sprite(index%9 == 0 ? "flower_dandelion" : index%11 == 0 ? "flower_rose" : "tallgrass",x:x,y:y,z:z,tint:index%9 == 0 || index%11 == 0 ? nil : 0x86B85B)
                    case .lush:
                        if index%23 == 0 { try block(.init(1,1,1),.init(x,y+0.5,z),"azalea_leaves_flowers") }
                        else { try sprite("tallgrass",x:x,y:y,z:z,tint:0x86B85B) }
                    case .pale:
                        try sprite("pale_hanging_moss_tip",x:x,y:y,z:z)
                    default: break
                    }
                }
            }
        }
        if treeBiome == .jungle {
            let stalk = try assets.texture("textures/blocks/bamboo_stem")
            let uv = Array(repeating:CGRect(x:0,y:1,width:3.0/16,height:-1),count:6)
            for index in 0..<144 {
                let x = (Terrain.random(index,24)*144-72).rounded(), z = (Terrain.random(index,29)*144-104).rounded()
                let y = area.cover == nil ? surface(x,z) : sample(x,z,surface:true).height-area.level
                guard y>0, !Terrain(biome:treeBiome,authored:terrain.authored && area.cover == nil).reserved(x,z), !Terrain.entrance(x,z),
                      !sample(x,z,surface:area.cover != nil).fluid,
                      sample(x,z,surface:area.cover != nil).biome == .jungle,
                      Terrain.noise(origin.x+x,origin.z+z,scale:18,seed:995)>0 else { continue }
                let tall = 5+index%8
                for level in 0..<tall {
                    detail.cube(.init(0.1875,1,0.1875),at:.init(x,y+Double(level)+0.5,z),material:stalk,textureUV:uv)
                    if level>=tall-3 { try sprite("bamboo_leaf",x:x,y:y+Double(level),z:z) }
                }
            }
        }
        if [.forest,.jungle,.mansion,.pale,.snow,.cherry,.river,.mangrove,.swamp,.grove].contains(area) {
            for index in 0..<100 {
                let x = (Terrain.random(index,41)*76-38).rounded(), z = (Terrain.random(index,43)*86-48).rounded()
                let y = surface(x,z)
                guard y>0, !terrain.reserved(x,z) else { continue }
                if index%7 == 0 {
                    let bark = area == .snow ? "spruce" : area == .river ? "birch" : "oak"
                    let tiles = try assets.tiles(bark+"_log",states:["axis":"x"])
                    detail.cube(.init(3,1,1),at:.init(x,y+0.5,z),material:tiles[0],faceMaterials:tiles)
                    try sprite("mushroom_red",x:x-1,y:y+1,z:z)
                } else if index%3 == 0 {
                    try block(.init(2,1,2),.init(x,y+0.35,z),"mossy_cobblestone")
                } else if area != .snow && area != .pale {
                    let tiles = try assets.tiles((area == .jungle ? "jungle" : "oak")+"_leaves")
                    detail.cube(.init(2,1,2),at:.init(x,y+0.5,z),material:tiles[0],faceMaterials:tiles)
                }
            }
        }
        if area == .swamp || area == .mangrove {
            let lily = try assets.texture("textures/blocks/waterlily")
            for index in 0..<150 {
                let x = (Terrain.random(index,53)*78-39).rounded(), z = (Terrain.random(index,59)*82-43).rounded()
                if surface(x,z) < 0 { detail.cube(.init(1,0,1),at:.init(x,0.93,z),material:lily,faces:16) }
            }
        }
        if area == .lush || area == .dripstone {
            for index in 0..<110 {
                let x = (Terrain.random(index,61)*76-38).rounded(), z = (Terrain.random(index,67)*90-50).rounded()
                guard abs(x-3)>4 else { continue }
                let y = surface(x,z), ceiling = max(y+9,terrain.ceiling(x,z))
                for level in 0..<(3+index%6) {
                    try sprite(area == .lush ? "cave_vines_body_berries" : "pointed_dripstone_down_middle",x:x,y:ceiling-1-Double(level),z:z)
                }
                if area == .lush && index%9 == 0 {
                    let material = try assets.texture("textures/blocks/spore_blossom")
                    detail.cube(.init(1,0,1),at:.init(x,ceiling-0.03,z),material:material,faces:32)
                }
                if area == .dripstone {
                    for level in 0..<(2+index%5) { try sprite(level == 1+index%5 ? "pointed_dripstone_up_tip" : "pointed_dripstone_up_middle",x:x,y:y+Double(level),z:z) }
                }
            }
        }
        if area == .reef {
            for index in 0..<90 {
                let x = Double((index*17)%87-43), z = Double((index*31)%87-63), y = surface(x,z)
                let coral = try assets.texture("textures/blocks/coral_"+["blue","pink","purple","red","yellow"][index%5])
                let tall = Double(1+index%4)
                detail.cube(.init(2,tall,2),at:.init(x,y+tall/2,z),material:coral)
                detail.cube(.init(3,1,2),at:.init(x+1,y+tall+0.5,z),material:coral)
                try sprite("coral_fan_"+["blue","pink","purple","red","yellow"][index%5],x:x-1,y:y,z:z,size:1.5)
                try sprite("seagrass",x:x+2,y:y,z:z)
            }
        }
        if world == .nether {
            for index in 0..<130 {
                let x = (Terrain.random(index,71)*90-45).rounded(), z = (Terrain.random(index,73)*110-60).rounded()
                let y = surface(x,z), ceiling = max(y+9,terrain.ceiling(x,z))
                if abs(x)>8 {
                    let tall = Double(4+index%9)
                    for level in 0..<Int(tall) {
                        let width = Double(max(1,3-level/4))
                        try block(.init(width,1,width),.init(x,ceiling-Double(level)-0.5,z),area == .basalt ? "basalt" : "netherrack")
                    }
                    if index%9 == 0 { try block(.init(3,2,3),.init(x+1,ceiling-2,z),"glowstone") }
                }
                if y>1, !terrain.reserved(x,z) {
                    if area == .warped || area == .crimson {
                        try sprite(area == .warped ? "warped_fungus" : "crimson_fungus",x:x,y:y,z:z)
                        if area == .warped { try sprite("nether_sprouts",x:x+1,y:y,z:z) }
                    } else if index%5 == 0 {
                        try block(.init(2,1,2),.init(x,y+0.4,z),area == .soul ? "bone_block" : "magma")
                    }
                }
            }
        }
        if world == .sift {
            for index in 0..<360 {
                let x = (Terrain.random(index,79)*78-39).rounded(), z = (Terrain.random(index,83)*90-50).rounded()
                let y = surface(x,z)
                guard y > -90, !terrain.occupied(x,z) else { continue }
                try sprite(index%7 == 0 ? "coral_fan_"+["pink","purple","blue"][index%3] : "tallgrass",x:x,y:y,z:z,tint:index%7 == 0 ? nil : 0x71C9C1)
                if index%17 == 0 && !terrain.reserved(x,z) {
                    try block(.init(2,1,2),.init(x,y+0.5,z),"calcite")
                    try block(.init(1,1,1),.init(x,y+1.5,z),"amethyst_block")
                }
            }
        }
        if area == .meadow && terrain.authored {
            for (x,z) in [(-18.0,-7.0),(20,-15),(9,-40)] {
                let y = surface(x,z)
                for (dx,dz,dy) in [(0.0,0.0,0.5),(1,0,0.5),(0,1,0.5),(0,0,1.5)] {
                    try block(.init(1,1,1),.init(x+dx,y+dy,z+dz),"hay_block")
                }
            }
        }
        scene.rootNode.addChildNode(detail.node("habitat-detail"))
        if [.jungle,.lush,.terraces,.grove].contains(area) || world == .nether {
            for index in 0..<(world == .nether ? 3 : 2) {
                let x = Double(index*27-26), z = -43.0-Double(index*9)
                try liquid(scene,assets:assets,lava:world == .nether,at:.init(x,12,z),size:.init(width:2,height:24),vertical:true)
            }
        }
        if world == .overworld && (!area.underground || area.cover != nil) || world == .sift {
            try clouds(scene,assets:assets,origin:origin)
            scene.rootNode.childNode(withName:"drifting-cloud",recursively:false)?.position.y -= area.level
        }
        if area.underground || world == .nether || world == .sift || area == .pale {
            let tint: UInt32 = area == .warped ? 0x36B8AD : area == .crimson ? 0xB83B46 : area == .soul || area == .basalt ? 0xB0AAA3 : world == .nether ? 0xF4BE8F : area == .lush ? 0xA6C75D : 0xBDDBDB
            let material = SCNMaterial(); material.diffuse.contents = colour(tint)
            material.lightingModel = .constant
            let geometry = SCNBox(width:0.04,height:0.04,length:0.04,chamferRadius:0); geometry.firstMaterial = material
            for index in 0..<24 {
                let particle = SCNNode(geometry:geometry); particle.name = "ambient-particle"
                particle.position = .init(Double((index*13)%50-25),Double(index%10+4),Double((index*17)%65-48))
                let fall = area == .snow || area == .cherry ? -3.0 : 2
                particle.runAction(.repeatForever(.sequence([.moveBy(x:1,y:fall,z:0.4,duration:8),.moveBy(x:-1,y:-fall,z:-0.4,duration:8)])))
                scene.rootNode.addChildNode(particle)
            }
        }
        if area == .cherry || area == .grove {
            let material = try assets.texture("textures/particle/cherry_petal_atlas").copy() as! SCNMaterial
            let atlas = material.diffuse.contents as! CGImage
            material.diffuse.contents = atlas.cropping(to:CGRect(x:0,y:0,width:8,height:8))
            material.lightingModel = .constant; material.writesToDepthBuffer = false
            let plane = SCNPlane(width:0.18,height:0.18); plane.firstMaterial = material
            for (index,tree) in scene.rootNode.childNodes.filter({ $0.name == "wind-canopy" }).prefix(64).enumerated() {
                let petal = SCNNode(geometry:plane); petal.name = "falling-cherry-petal"
                let start = SCNVector3(tree.position.x+Double(index%3)-1,tree.position.y,tree.position.z)
                let ground = surface(start.x,start.z)+0.05, duration = 5+Double(index%4)
                petal.position = start
                petal.runAction(.repeatForever(.customAction(duration:duration) { node,time in
                    let phase = (Double(time)/duration+Double(index%7)/7).truncatingRemainder(dividingBy:1)
                    node.position = .init(start.x+sin(phase*6+Double(index))*0.8,start.y+(ground-start.y)*phase,start.z+phase*1.2)
                    node.eulerAngles = .init(phase*3,phase*5,phase*4)
                }))
                scene.rootNode.addChildNode(petal)
            }
        }
        for (x,z) in [(-12.0,-12.0),(18,-26)] {
            let glow = SCNNode(); glow.light = SCNLight(); glow.light?.type = .omni
            glow.light?.color = colour(world == .nether ? 0xF5A15D : 0x9DDCD1)
            glow.light?.intensity = area.underground ? 350 : world == .nether ? 250 : 0
            glow.light?.attenuationEndDistance = 34; glow.position = .init(x,12,z); scene.rootNode.addChildNode(glow)
        }
        // SceneKit needs prepared geometry before offscreen segment queries can hit it
        let collision = SCNRenderer(device:nil,options:nil)
        collision.scene = scene
        guard collision.prepare(scene,shouldAbortBlock:nil) else { throw AssetError.model }
        try withExtendedLifetime(collision) {
            try populate(scene,world:world,area:area,terrain:terrain,height:surface,showcase:region.key(world.biomes.count)>=0,factory:Mobs(assets:assets))
            focus(scene,world:world,biome:biome,animated:false)
        }
        if world == .overworld && (!area.underground || area.cover != nil) { try Daylight.install(scene,area:area.cover ?? area,assets:assets) }
        if world == .end {
            // The original sky is greyscale and receives a dark purple tint in game
            let source = try assets.texture("textures/environment/end_sky").diffuse.contents as! CGImage
            guard let context = CGContext(data:nil,width:source.width,height:source.height,bitsPerComponent:8,bytesPerRow:0,
                space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue) else { throw AssetError.image }
            let rect = CGRect(x:0,y:0,width:source.width,height:source.height)
            context.draw(source,in:rect); context.setBlendMode(.multiply)
            context.setFillColor(colour(0x24182E).cgColor); context.fill(rect)
            guard let sky = context.makeImage() else { throw AssetError.image }
            scene.background.contents = Array(repeating:sky,count:6)
        }
        return scene
    }

    static func clouds(_ scene: SCNScene, assets: Assets, origin: SCNVector3) throws {
        let source = try assets.texture("textures/environment/clouds").diffuse.contents as! CGImage
        let bitmap = NSBitmapImageRep(cgImage:source)
        let startX = Int(origin.x/16), startZ = Int(origin.z/16)
        func filled(_ x: Int, _ z: Int) -> Bool {
            let px = ((x+startX+128)%bitmap.pixelsWide+bitmap.pixelsWide)%bitmap.pixelsWide
            let pz = ((z+startZ+128)%bitmap.pixelsHigh+bitmap.pixelsHigh)%bitmap.pixelsHigh
            return (bitmap.colorAt(x:px,y:pz)?.alphaComponent ?? 0)>0.5
        }
        let material = SCNMaterial(); material.name = "cloud-volume"
        material.diffuse.contents = NSColor.white; material.lightingModel = .lambert
        material.transparency = 0.65; material.blendMode = .alpha
        material.transparencyMode = .singleLayer; material.writesToDepthBuffer = false
        var mesh = Voxels()
        for x in -18..<18 { for z in -18..<18 where filled(x,z) {
            var faces = 48
            for (face,dx,dz) in [(0,0,1),(1,1,0),(2,0,-1),(3,-1,0)] where !filled(x+dx,z+dz) { faces |= 1 << face }
            mesh.cube(.init(16,4,16),at:.init(Double(x)*16,0,Double(z)*16),material:material,faces:faces)
        } }
        let cloud = mesh.node("drifting-cloud"); cloud.castsShadow = false; cloud.categoryBitMask = 1
        for x in [-576.0,576.0] {
            let repeatCloud = SCNNode(geometry:cloud.geometry); repeatCloud.position.x = x
            repeatCloud.castsShadow = false; repeatCloud.categoryBitMask = 1
            cloud.addChildNode(repeatCloud)
        }
        cloud.position = .init(0,96,0)
        let epoch = assets.started
        cloud.runAction(.repeatForever(.customAction(duration:240) { node,_ in
            node.position.x = -max(0,ProcessInfo.processInfo.systemUptime-epoch).truncatingRemainder(dividingBy:1152)*0.5
        }))
        scene.rootNode.addChildNode(cloud)
    }

    static func flow(assets: Assets, lava: Bool, biome: Biome = .meadow) throws -> SCNMaterial {
        try assets.fluid(lava:lava,biome:biome,flowing:false)
    }

    static func animate(_ node: SCNNode, material: SCNMaterial) {
        let image = material.diffuse.contents as! CGImage, frames = max(1,image.height/image.width)
        guard frames>1 else {return}
        material.diffuse.contentsTransform = SCNMatrix4MakeScale(1,1/CGFloat(frames),1)
        material.emission.contentsTransform = material.diffuse.contentsTransform
        let interval = material.name?.contains("lava") == true ? 0.1 : 0.05
        node.runAction(.repeatForever(.customAction(duration:Double(frames)*interval) { _,time in
            var transform = SCNMatrix4MakeScale(1,1/CGFloat(frames),1)
            transform.m42 = CGFloat(min(frames-1,Int(Double(time)/interval)))/CGFloat(frames)
            material.diffuse.contentsTransform = transform
            if material.emission.contents != nil { material.emission.contentsTransform = transform }
        }))
    }

    static func liquid(_ scene: SCNScene, assets: Assets, lava: Bool, at point: SCNVector3, size: CGSize, vertical: Bool = false) throws {
        let material = try flow(assets:assets,lava:lava)
        var mesh = Voxels()
        for x in 0..<Int(ceil(size.width)) { for y in 0..<Int(ceil(size.height)) {
            let dx = Double(x)+0.5-size.width/2, dy = Double(y)+0.5-size.height/2
            mesh.cube(vertical ? .init(1,1,0) : .init(1,0,1),at:vertical ? .init(dx,dy,0) : .init(dx,0,dy),material:material,faces:vertical ? 1 : 16)
        } }
        let surface = mesh.node(vertical ? "waterfall" : "flowing-surface"); surface.position = point
        animate(surface,material:material); scene.rootNode.addChildNode(surface)
    }

    static func pose(_ area: Biome, at time: Double) -> (eye: SCNVector3, aim: SCNVector3) {
        let angle = max(0,time)/8*2 * .pi
        let phase = (1-cos(angle))/2
        if let passage = area.passage { return passage.pose(at:(area == .mine ? 8 : 15)+phase*7) }
        let x: Double, z: Double, target: SCNVector3, elevation: Double?
        switch area {
        case .meadow: x = 3-phase; z = 8-phase*6; target = .init(-1,5,-23); elevation = nil
        case .wastes: x = 24-phase*6; z = -18; target = .init(-7,14,-34); elevation = 13.62
        case .trial: x = 9-phase*2; z = -9-phase*2; target = .init(-7,7,-24); elevation = 5.62
        case .reef: x = -8+phase*3; z = 18-phase*3; target = .init(1,-5,-18); elevation = -3.5
        case .monument: x = 7-phase*3; z = 34-phase*4; target = .init(-3,-6,-20); elevation = -3.5
        case .city: x = 9-phase*3; z = 17-phase*3; target = .init(-1,19,-23); elevation = nil
        case .central: x = 5-phase*2; z = 24-phase*3; target = .init(-3,16,-23); elevation = nil
        case .islands: x = 5-phase*2; z = -8-phase*2; target = .init(28,5,-55); elevation = nil
        case .mansion: x = 7-phase*3; z = 35-phase*3; target = .init(0,12,-7); elevation = nil
        case .deep: x = 8-phase*3; z = 9-phase*3; target = .init(-1,12,-27); elevation = nil
        case .lush: x = 1+phase*2; z = 15-phase*2; target = .init(9,1,-6); elevation = 2.2
        case .badlands: x = 1+phase; z = 5-phase*2; target = .init(0,7,-23); elevation = nil
        case .river: x = 11-phase*2; z = 20-phase*3; target = .init(-6,4,-25); elevation = nil
        case .mangrove,.swamp: x = 3+phase*2; z = 20-phase*3; target = .init(-2,5,-20); elevation = nil
        case .peaks: x = 9-phase*2; z = 17-phase*2; target = .init(-9,18,-37); elevation = nil
        default: x = 4-phase*3; z = 12-phase*4; target = .init(-2,6,-25); elevation = nil
        }
        let ground = height(area,x:x.rounded(),z:z.rounded())
        let travel = phase*2-1
        let glide = area == .islands ? 1.0 : area == .wastes || area == .trial ? 1.5 : 3.5
        var px = x+sin(angle)*min(1.25,glide), pz = z-travel*glide
        if min(height(area,x:px,z:pz),height(area,x:px.rounded(),z:pz.rounded())) < -90 { px = x; pz = z }
        if min(height(area,x:px,z:pz),height(area,x:px.rounded(),z:pz.rounded())) < -90 { px = 0; pz = -17 }
        let surface = height(area,x:px.rounded(),z:pz.rounded())
        let level = max(elevation ?? max(max(0.9,ground),surface)+1.62,surface+1.62)
        return (.init(px,level+sin(phase * .pi)*0.35,pz),target)
    }

    static func focus(_ scene: SCNScene, world: World, biome: Int, animated: Bool, preserving: Bool = false) {
        let area = world.biomes[world.index(biome)], camera = scene.rootNode.childNode(withName:"camera",recursively:false)!
        let underwater = area == .reef || area == .monument
        if area.passage == nil && world != .end { scene.background.contents = colour(underwater ? 0x245A78 : area.sky) }
        if area.passage == nil { scene.fogColor = colour(underwater ? 0x245A78 : area.sky) }
        scene.fogStartDistance = underwater ? 12 : area.underground || world == .nether ? 38 : 90
        scene.fogEndDistance = underwater ? 62 : area.underground || world == .nether ? 100 : 155
        for light in scene.rootNode.childNodes.compactMap(\.light) {
            if light.type == .ambient { light.intensity = area.underground ? 350 : area == .pale ? 300 : 450 }
            if light.type == .directional { light.intensity = area.underground ? 300 : area == .pale ? 450 : 900 }
        }
        camera.removeAction(forKey:"passage"); camera.removeAction(forKey:"journey")
        let initial = preserving ? (eye:camera.position,aim:camera.convertPosition(.init(0,0,-24),to:scene.rootNode)) : pose(area,at:0)
        let eye = preserving ? initial.eye : Collision.nearby(scene.rootNode,at:initial.eye,toward:initial.aim)
            ?? Collision.nearby(scene.rootNode,at:initial.eye) ?? initial.eye
        camera.position = eye; camera.look(at:scene.rootNode.convertPosition(initial.aim,to:nil),up:.init(0,1,0),localFront:.init(0,0,-1))
        let offset = SCNVector3(eye.x-initial.eye.x,eye.y-initial.eye.y,eye.z-initial.eye.z)
        let doors = Door.collect(scene.rootNode)
        var route = [eye]
        for index in 1...32 {
            let angle = Double(index)/32*2 * .pi
            let target = preserving ? SCNVector3(eye.x+sin(angle)*0.9,eye.y+(1-cos(angle))*0.15,eye.z+(1-cos(angle))*0.5) : pose(area,at:Double(index)/4).eye
            let start = route.last!, next = Collision.move(scene.rootNode,from:route.last!,to:.init(target.x+offset.x,target.y+offset.y,target.z+offset.z),radius:0.35)
            route.append(Collision.vacant(scene.rootNode,at:next) && Collision.clear(scene.rootNode,from:start,to:next,radius:0.35) ? next : start)
        }
        camera.runAction(.repeatForever(.customAction(duration:8) { node,time in
            let t = min(32,max(0,Double(time)*4)), index = min(31,Int(t)), fraction = t-Double(index)
            let a = route[index], b = route[index+1]
            node.position = .init(a.x+(b.x-a.x)*fraction,a.y+(b.y-a.y)*fraction,a.z+(b.z-a.z)*fraction)
            for door in doors { door.approach() }
            node.look(at:node.parent!.convertPosition(preserving ? initial.aim : pose(area,at:Double(time)).aim,to:nil),up:.init(0,1,0),localFront:.init(0,0,-1))
        }),forKey:"journey")
        if let sky = scene.rootNode.childNode(withName:"daylight",recursively:false) as? Daylight {
            Daylight.apply(scene,area:area,seconds:ProcessInfo.processInfo.systemUptime-sky.epoch)
        }
    }

    static func medium(_ scene: SCNScene, area: Biome, eye: SCNVector3, submerged override: Bool? = nil) {
        let submerged = override ?? (eye.y < 0.9 && Terrain(biome:area).height(eye.x.rounded(),eye.z.rounded()) < 0.9)
        let lava = submerged && World.nether.biomes.contains(area)
        if submerged {
            scene.fogColor = colour(lava ? 0xA73D08 : 0x125C9C)
            scene.fogStartDistance = 0; scene.fogEndDistance = lava ? 1.5 : 18
        } else {
            scene.fogColor = scene.background.contents as? NSColor ?? colour(area.sky)
            let underground = area.underground || World.nether.biomes.contains(area)
            scene.fogStartDistance = underground ? 38 : 90
            scene.fogEndDistance = underground ? 100 : 155
        }
    }

    static func arrive(_ scene: SCNScene, world: World, biome: Int, passage: Passage, assets: Assets) throws {
        guard let camera = scene.rootNode.childNode(withName:"camera",recursively:false), let idle = camera.action(forKey:"journey") else { return }
        let end = camera.position, aim = pose(world.biomes[world.index(biome)],at:0).aim
        let length = max(1,hypot(aim.x-end.x,aim.z-end.z))
        let proposed = SCNVector3(end.x-(aim.x-end.x)/length*3,end.y,end.z-(aim.z-end.z)/length*3)
        let candidate = Collision.move(scene.rootNode,from:end,to:proposed,radius:0.35)
        let start = Collision.clear(scene.rootNode,from:end,to:candidate,radius:0.35) ? candidate : end
        let gateway = SCNNode(); gateway.name = "arrival"; gateway.position = start
        gateway.eulerAngles.y = atan2(aim.x-end.x,aim.z-end.z)
        if passage == .stronghold {
            var platform = Voxels()
            let tile = try assets.tiles("obsidian")
            platform.cube(.init(5,1,5),at:.init(0,-2.12,0),material:tile[0],faceMaterials:tile)
            gateway.addChildNode(platform.node("end-spawn-platform"))
        } else { try Structures.portal(gateway,at:.init(0,-2.5,0),assets:assets,sift:passage == .rift) }
        scene.rootNode.addChildNode(gateway)
        camera.removeAction(forKey:"journey"); camera.position = start; camera.look(at:scene.rootNode.convertPosition(aim,to:nil),up:.init(0,1,0),localFront:.init(0,0,-1))
        let exit = SCNAction.customAction(duration:4) { node,time in
            let t = min(1,Double(time)/4)
            node.position = .init(start.x+(end.x-start.x)*t,start.y+(end.y-start.y)*t,start.z+(end.z-start.z)*t)
            node.look(at:node.parent!.convertPosition(aim,to:nil),up:.init(0,1,0),localFront:.init(0,0,-1))
        }
        camera.runAction(.sequence([exit,idle]),forKey:"journey")
    }

    private static func populate(_ scene: SCNScene, world: World, area: Biome, terrain: Terrain, height: @escaping (Double,Double) -> Double, showcase: Bool, factory: Mobs) throws {
        let jobs = Structures.sites(in:scene.rootNode).filter { $0.kind == .work && !$0.standing.isEmpty }
        for (kind,species) in area.residents.enumerated() {
            if !showcase && [.wither,.zoglin].contains(species) { continue }
            if !terrain.authored && [.villager,.golem,.cat,.ironGolem,.trader,.traderLlama,.mule,.shulker,.piglinBrute,.blaze,.witherSkeleton,.elderGuardian,.evoker,.vindicator,.warden,.breeze,.silverfish,.allay,.wither].contains(species) { continue }
            let solitary = [.warden,.creaking,.ironGolem,.ravager,.witch,.sniffer,.endermite,.snowGolem,.wither,.trader,.traderLlama,.mule,.zoglin,.zombieHorse].contains(species)
            let fallback = solitary || species == .cat && area == .swamp ? 1 : species == .villager ? (area == .meadow ? 8 : 5) : species == .tropical || species == .salmon ? 7 : [.cow,.pig,.sheep,.chicken,.strider,.enderman].contains(species) ? 4 : 3
            let count = try factory.group(species,biome:area,seed:(terrain.seed &+ kind) & Int.max) ?? fallback
            let coat = min(6,Int(Terrain.random(kind,0,seed:terrain.seed)*7))
            for index in 0..<count {
                let baby = count>2 && index>=max(2,count-1) && [.cow,.pig,.sheep,.chicken,.wolf,.horse,.cat,.axolotl,.villager,.rabbit,.polarBear].contains(species)
                let actor = SCNNode(); actor.name = "resident-\(species.rawValue)-\(index)"+(baby ? "-baby" : "")
                let daylight = Daylight.light(at:ProcessInfo.processInfo.systemUptime-factory.assets.started)
                let classic = Terrain.random(kind,index,seed:terrain.seed &+ 227) < Mobs.classicChance(daylight:daylight)
                let profession = area == .meadow && species == .villager && jobs.indices.contains(index)
                    ? ["farmer":0,"librarian":1,"cleric":2,"weaponsmith":3,"butcher":4][jobs[index].profession ?? ""] ?? index : index
                let named: String? = !showcase ? nil : area == .cherry && species == .rabbit && index == 0 ? "Toast"
                    : area == .cherry && species == .sheep && index == 1 ? "jeb_"
                    : area == .meadow && species == .chicken && index == 1 ? "Dinnerbone" : nil
                let model: SCNNode
                do {
                    model = showcase && area == .forest && species == .creeper && index == 0 ? try factory.charged()
                        : try factory.make(species,biome:area,variant:species == .horse ? coat+7*index : profession,classic:classic,baby:baby,named:named)
                }
                catch AssetError.missing where [.camelHusk,.parched,.nautilus,.zombieNautilus,.happyGhast,.donkey,.mule,.phantom,.tadpole,.traderLlama,.trader,.wither,.zoglin,.zombieHorse,.zombieVillager,.sulfurCube].contains(species) { continue }
                if showcase && area == .meadow && species == .pig && index == 0 { try factory.crown(model) }
                if showcase && area == .cherry && species == .sheep && index == 0 { try factory.pink(model,baby:baby) }
                if let aura = model.childNode(withName:"charged-aura",recursively:false) {
                    aura.isHidden = true
                    let epoch = factory.assets.started
                    aura.runAction(.repeatForever(.sequence([.run { node in
                        if ProcessInfo.processInfo.systemUptime-epoch>=205 { node.isHidden = false; node.removeAllActions() }
                    },.wait(duration:1)])))
                }
                actor.addChildNode(model)
                if [.phantom,.zombieHorse].contains(species) {
                    let epoch = factory.assets.started
                    actor.runAction(.repeatForever(.sequence([.run { node in
                        node.isHidden = Daylight.light(at:ProcessInfo.processInfo.systemUptime-epoch)>0.15
                    },.wait(duration:1)])),forKey:"night-spawn")
                }
                if !species.flying && !species.swimming { model.position.y = max(0,-model.boundingBox.min.y*model.scale.y) }
                let a = Terrain.random(kind,index,seed:3)*Double.pi*2
                let radius = sqrt(Terrain.random(index,kind,seed:2))*3
                var x = Double(kind%3-1)*11+cos(a)*radius, z = Double(kind/3)*9-5+sin(a)*radius
                if area == .meadow {
                    let patches: [(Double,Double)] = [(-9,6),(12,6),(-5,-1),(0,-7),(10,-12),(-5,-8),(4,-6)]
                    let patch = patches[kind%patches.count]; x = patch.0+cos(a)*radius; z = patch.1+sin(a)*radius
                }
                if area == .trial { x = -9+Double(kind%3)*7+cos(a)*1.5; z = -21+Double(kind/3)*7+sin(a)*2 }
                if species.swimming {
                    if area == .lush { x = 4+Double(index%3)*2; z = 6+Double(index/3)*3 }
                    else if area == .river {
                        z = -5+Double(index)*3
                        x = 4+Terrain.noise(0,z,scale:32,seed:9)*9+cos(a)*2
                    }
                    else if area == .monument { x = -17+Double(index)*7; z = 13+sin(a)*4 }
                    else { x = -13+Double(kind)*6+cos(a)*3; z = -2-Double(index)*3 }
                }
                if species == .strider { z = -6-Terrain.noise(x,0,scale:36,seed:13)*10 }
                if [.blaze,.witherSkeleton].contains(species) { x = 3+Double(index)*4; z = -18+sin(a) }
                if species == .piglinBrute { x = -3+Double(index)*4; z = -17 }
                if species == .warden { x = -4; z = -1 }
                if species == .shulker { x = 5+Double(index)*3; z = -13 }
                if species == .endermite { x = -10; z = 10 }
                if species == .turtle { x = 3+Double(index)*4; z = 11+sin(a)*2 }
                if height(x,z) < -90 { x *= 0.3; z = -7+Double(index) }
                if species.swimming {
                    let centre = (x,z)
                    for step in 0..<96 where height(x.rounded(),z.rounded()) >= -1.2 {
                        let radius = sqrt(Double(step+1))*3
                        x = centre.0+cos(Double(step)*2.4)*radius
                        z = centre.1+sin(Double(step)*2.4)*radius
                    }
                    guard height(x.rounded(),z.rounded()) < -1.2 else { continue }
                }
                if !species.flying && !species.swimming && species != .strider {
                    for step in 0..<24 where height(x.rounded(),z.rounded()) < 1 {
                        x += cos(Double(step)*2.4)*3
                        z += sin(Double(step)*2.4)*3+2
                    }
                }
                func point(_ x: Double, _ z: Double) -> SCNVector3 {
                    let h = height(x.rounded(),z.rounded())
                    let y = species.swimming ? min(0.3,max(h+0.6,species == .axolotl ? 0.15 : area == .monument ? -5 : -1.8)) : species == .strider ? 0.9 : [.blaze,.witherSkeleton].contains(species) ? 12 : species == .shulker ? 8+Double(index)*3 : max(0.9,h)
                    return .init(x,y+(species.flying ? (species == .breeze ? 1.2 : 3) : 0),z)
                }
                let start = point(x,z)
                actor.position = start; actor.eulerAngles.y = a
                if species != .shulker && species != .warden && species != .snowGolem {
                    try factory.wander(actor,model:model,species:species,area:area,seed:kind*17+index,baby:baby,root:scene.rootNode,ground:height,point:point)
                }
                if species == .golem { try factory.oxidation(actor,model:model,stage:index%3,seed:kind*17+index) }
                scene.rootNode.addChildNode(actor)
            }
        }
        if area == .meadow && terrain.authored { try village(scene,factory:factory) }
        if showcase && (area == .pale || area == .ice) {
            let actor = SCNNode(), model = area == .pale ? try factory.herobrine() : try factory.skeletonHorse()
            actor.name = area == .pale ? "cameo-herobrine" : "cameo-skeleton-horse"
            actor.position = .init(8,height(8,10),10); actor.addChildNode(model); scene.rootNode.addChildNode(actor)
            if area == .pale {
                actor.isHidden = true
                let epoch = factory.assets.started
                actor.runAction(.repeatForever(.sequence([.run { node in
                    let phase = (ProcessInfo.processInfo.systemUptime-epoch).truncatingRemainder(dividingBy:180)
                    node.isHidden = phase<150 || phase>158
                },.wait(duration:1)])))
            } else {
                try factory.wander(actor,model:model,species:.horse,area:area,seed:512,root:scene.rootNode) { x,z in
                    .init(x,height(x.rounded(),z.rounded()),z)
                }
            }
        }
        if showcase && area == .mansion && terrain.authored {
            let actor = SCNNode(), model = try factory.jockey()
            actor.name = "resident-chicken-jockey"; actor.addChildNode(model)
            actor.position = .init(1,5,-17)
            try factory.wander(actor,model:model,species:.chicken,area:area,seed:301,root:scene.rootNode) { x,z in .init(x,5,z) }
            scene.rootNode.addChildNode(actor)
        }
        if area == .central || world == .nether {
            let group = SCNNode(); group.name = "sky-resident"
            group.addChildNode(try factory.actor(world == .end ? "ender_dragon" : "ghast"))
            let duration = world == .end ? 48.0 : 64
            let radius = world == .end ? 34.0 : 20
            var route = [SCNVector3(radius,25,-25)]
            for index in 1...32 {
                let angle = Double(index)/32*2 * .pi
                let next = SCNVector3(cos(angle)*radius,25+sin(angle*2)*3,-25+sin(angle)*radius)
                let start = route.last!, body = world == .end ? 3.5 : 2.0
                let candidate = Collision.move(scene.rootNode,from:start,to:next,radius:body)
                route.append(Collision.clear(scene.rootNode,from:start,to:candidate,radius:body) ? candidate : start)
            }
            group.position = route[0]
            scene.rootNode.addChildNode(group)
            Mobs.face(group)
            let healing: (@Sendable (CGFloat) -> Void)?
            if area == .central { healing = try heal(group,root:scene.rootNode,assets:factory.assets) }
            else { healing = nil }
            group.runAction(.repeatForever(.customAction(duration:duration) { node,time in
                let t = min(32,Double(time)/duration*32)
                let index = min(31,max(0,Int(t))), fraction = min(1,max(0,t-Double(index)))
                let a = route[index], b = route[index+1]
                node.position = .init(a.x+(b.x-a.x)*fraction,a.y+(b.y-a.y)*fraction,a.z+(b.z-a.z)*fraction)
                node.eulerAngles = .init(0,atan2(b.x-a.x,b.z-a.z),0)
                healing?(time)
            }))
        }
    }

    private static func village(_ scene: SCNScene, factory: Mobs) throws {
        let root = scene.rootNode, sites = Structures.sites(in:root), terrain = Terrain(biome:.meadow)
        let jobs = sites.filter { $0.kind == .work && !$0.standing.isEmpty }
        let beds = sites.filter { $0.kind == .bed && !$0.standing.isEmpty }
        var streets = [SCNVector3]()
        for x in stride(from:-24.0,through:24,by:3) { for z in stride(from:-51.0,through:9,by:3) where terrain.paved(x,z) {
            streets.append(.init(x,terrain.height(x,z)+0.02,z))
        } }
        let bell = sites.first { $0.kind == .gather }
        let meeting = bell.flatMap { site in streets.min { hypot($0.x-site.point.x,$0.z-site.point.z)<hypot($1.x-site.point.x,$1.z-site.point.z) } }
        let waypoints = streets+sites.flatMap(\.standing)
        let doors = Door.collect(root)
        var occupied = Set<Int>()
        for (index,job) in jobs.enumerated() {
            guard let actor = root.childNode(withName:"resident-villager-\(index)",recursively:false), let model = actor.childNodes.first else { continue }
            let original = actor.position
            var installed = false
            for start in job.standing where !installed {
                let first: [SCNVector3]
                if let meeting {
                    guard let route = Structures.route(from:start,to:meeting,via:waypoints,in:root) else { continue }
                    first = route
                } else { first = [start] }
                let gather = first.count-1
                for bedIndex in beds.indices where !occupied.contains(bedIndex) && !installed {
                    let bed = beds[bedIndex]
                    for end in bed.standing where !installed {
                        guard let second = Structures.route(from:first.last!,to:end,via:waypoints,in:root) else { continue }
                        let route = first+second.dropFirst()
                        actor.position = start
                        actor.eulerAngles = .init(0,atan2(job.point.x-start.x,job.point.z-start.z),0)
                        installed = try Door.clearance(root) {
                            try bed.clearance {
                                try factory.routine(actor,model:model,route:route,bed:bed.point,facing:bed.facing,
                                    gather:gather,root:root,seed:index)
                            }
                        }
                        if installed {
                            occupied.insert(bedIndex)
                            for door in doors { door.register(actor) }
                        }
                    }
                }
            }
            if !installed { actor.position = original }
        }
        let residents = root.childNodes.filter { $0.name?.hasPrefix("resident-villager-") == true }
            .sorted { ($0.name ?? "") < ($1.name ?? "") }
        for (index,actor) in residents.enumerated() where actor.action(forKey:"routine") == nil {
            guard let model = actor.childNodes.first else { continue }
            let start = streets.indices.lazy.map { streets[($0+index*7)%streets.count] }
                .first { point in Collision.vacant(root,at:.init(point.x,point.y+1,point.z),radius:0.3) }
            guard let start else { continue }
            actor.position = start
            try factory.wander(actor,model:model,species:.villager,area:.meadow,seed:index+317,root:root,
                ground:{ terrain.height($0,$1) }) { x,z in .init(x,terrain.height(x.rounded(),z.rounded())+0.02,z) }
            for door in doors { door.register(actor) }
        }
    }

    static func heal(_ dragon: SCNNode, root: SCNNode, assets: Assets) throws -> @Sendable (CGFloat) -> Void {
        var crystals = [SCNNode]()
        root.enumerateChildNodes { node,_ in
            if node.name == "ender_crystal", let shell = node.childNode(withName:"outerglass",recursively:true) { crystals.append(shell) }
        }
        let material = try assets.texture("textures/entity/endercrystal/endercrystal_beam").copy() as! SCNMaterial
        material.lightingModel = .constant; material.blendMode = .add; material.writesToDepthBuffer = false
        material.diffuse.wrapT = .repeat
        let geometry = SCNCone(topRadius:0.12,bottomRadius:0.65,height:1)
        geometry.radialSegmentCount = 8; geometry.firstMaterial = material
        let beam = SCNNode(geometry:geometry); beam.name = "crystal-healing-beam"
        beam.isHidden = true; root.addChildNode(beam)
        let update: @Sendable (CGFloat) -> Void = { [weak root,weak dragon,weak beam,crystals] time in
            guard let root, let dragon, let beam else { return }
            let target = dragon.convertPosition(.init(0,0.6,0),to:root)
            var source: SCNVector3?, nearest = 32.0*32
            for crystal in crystals where !crystal.isHidden {
                let point = crystal.convertPosition(SCNVector3Zero,to:root)
                let distance = pow(target.x-point.x,2)+pow(target.y-point.y,2)+pow(target.z-point.z,2)
                if distance < nearest { source = point; nearest = distance }
            }
            guard let source, nearest > 0.001 else { beam.isHidden = true; return }
            beam.isHidden = false
            let from = SIMD3<Float>(Float(source.x),Float(source.y),Float(source.z))
            let to = SIMD3<Float>(Float(target.x),Float(target.y),Float(target.z))
            beam.simdPosition = (from+to)/2
            beam.simdScale = .init(1,sqrt(Float(nearest)),1)
            beam.simdOrientation = simd_quatf(from:.init(0,1,0),to:simd_normalize(to-from))
            material.diffuse.contentsTransform = SCNMatrix4MakeTranslation(0,-CGFloat(time)/2,0)
        }
        update(0)
        return update
    }
}

final class Daylight: SCNNode {
    var epoch = 0.0
    var water: [SCNMaterial] = []
    var weather: SCNParticleSystem?
    static let period = 1200.0

    static func light(at seconds: Double) -> Double {
        let height = sin((seconds/period+0.25)*2 * .pi)
        return min(1,max(0,(height+0.12)/0.35))
    }

    static func rain(at seconds: Double) -> Double {
        guard seconds.isFinite else { return 0 }
        let phase = seconds.truncatingRemainder(dividingBy:period)
        return min(1,max(0,(phase-180)/25))*min(1,max(0,(360-phase)/25))
    }

    static func install(_ scene: SCNScene, area: Biome, assets: Assets) throws {
        let rig = Daylight(); rig.name = "daylight"
        for (name,width) in [("sun",11.2),("moon_phases",7.5)] {
            let material = try assets.texture("textures/environment/"+name).copy() as! SCNMaterial
            material.lightingModel = .constant; material.writesToDepthBuffer = false
            if name == "moon_phases" {
                let atlas = material.diffuse.contents as! CGImage
                material.diffuse.contents = atlas.cropping(to:CGRect(x:0,y:0,width:atlas.width/4,height:atlas.height/2))
            }
            let plane = SCNPlane(width:width,height:width); plane.firstMaterial = material
            let body = SCNNode(geometry:plane); body.name = name; body.castsShadow = false
            body.constraints = [SCNBillboardConstraint()]; rig.addChildNode(body)
        }
        var stars = Voxels()
        let white = SCNMaterial(); white.lightingModel = .constant; white.diffuse.contents = NSColor.white
        for i in 0..<96 {
            let azimuth = Terrain.random(i,0,seed:91)*2 * .pi
            let altitude = 0.15+Terrain.random(i,1,seed:91)*1.3
            let r = 100.0
            stars.cube(.init(0.15,0.15,0.15),at:.init(cos(azimuth)*cos(altitude)*r,sin(altitude)*r,sin(azimuth)*cos(altitude)*r),material:white)
        }
        let field = stars.node("stars"); field.castsShadow = false; rig.addChildNode(field)
        if ![Biome.desert,.badlands,.savanna].contains(area) {
            let snow = [Biome.snow,.ice,.peaks].contains(area)
            let image = try assets.texture("textures/environment/weather").diffuse.contents as! CGImage
            guard image.width>=3 && image.height>=19,
                  let particle = image.cropping(to:snow ? CGRect(x:0,y:0,width:3,height:3) : CGRect(x:1,y:5,width:1,height:14)) else { throw AssetError.image }
            let system = SCNParticleSystem()
            system.particleImage = particle; system.birthRate = 0
            system.particleLifeSpan = snow ? 5 : 1.5
            system.particleSize = snow ? 0.12 : 0.04
            system.particleVelocity = snow ? 2.5 : 14
            system.particleVelocityVariation = snow ? 0.8 : 2
            system.emittingDirection = .init(0,-1,0)
            system.spreadingAngle = snow ? 12 : 2
            system.stretchFactor = snow ? 0 : 0.06
            system.orientationMode = .billboardYAligned; system.blendMode = .alpha
            system.isLocal = false; system.isLightingEnabled = false
            system.emitterShape = SCNBox(width:30,height:1,length:30,chamferRadius:0)
            let emitter = SCNNode(); emitter.name = snow ? "snowfall" : "rainfall"
            emitter.position.y = 12; emitter.addParticleSystem(system); rig.addChildNode(emitter)
            rig.weather = system
        }
        scene.rootNode.addChildNode(rig)
        scene.rootNode.enumerateChildNodes { node,_ in
            for material in node.geometry?.materials ?? [] where material.name?.contains("water_still") == true {
                if !rig.water.contains(where: { $0 === material }) { rig.water.append(material) }
            }
        }
        let epoch = assets.started
        rig.epoch = epoch
        apply(scene,area:area,seconds:ProcessInfo.processInfo.systemUptime-epoch)
        var last = -1
        rig.runAction(.repeatForever(.customAction(duration:period) { [weak scene] _,_ in
            guard let scene else { return }
            let seconds = ProcessInfo.processInfo.systemUptime-epoch
            guard Int(seconds) != last else { return }
            last = Int(seconds)
            apply(scene,area:area,seconds:seconds)
        }))
    }

    static func apply(_ scene: SCNScene, area: Biome, seconds: Double, eye: SCNVector3? = nil) {
        guard let rig = scene.rootNode.childNode(withName:"daylight",recursively:false) as? Daylight else { return }
        let camera = scene.rootNode.childNode(withName:"camera",recursively:false)
            ?? scene.rootNode.parent?.childNode(withName:"camera",recursively:false)
        let eye = eye ?? camera.map { scene.rootNode.convertPosition($0.worldPosition,from:nil) }
        let daylight = light(at:seconds), angle = (seconds/period+0.25)*2 * .pi
        let rain = rain(at:seconds)
        let underwater = area == .reef || area == .monument
        let day = Landscape.colour(underwater ? 0x245A78 : area.sky)
        let night = Landscape.colour(underwater ? 0x07182E : 0x050B23)
        var sky = night.blended(withFraction:daylight,of:day)!
        let dusk = max(0,1-abs(sin(angle))/0.20)
        if !underwater { sky = sky.blended(withFraction:dusk*0.6,of:Landscape.colour(0xC46751))! }
        if !underwater { sky = sky.blended(withFraction:rain*0.65,of:Landscape.colour(0x626D80))! }
        scene.background.contents = sky; scene.fogColor = sky
        let sun = scene.rootNode.childNode(withName:"sunlight",recursively:false)!
        sun.eulerAngles = .init(-(daylight>0.05 ? angle : angle + .pi),-0.6,0)
        sun.light?.intensity = (55+845*daylight)*(1-rain*0.45)
        sun.light?.color = Landscape.colour(daylight>0.1 ? 0xFFF2DD : 0x9AAFE8)
        scene.rootNode.childNode(withName:"skylight",recursively:false)?.light?.intensity = 120+330*daylight
        rig.position = eye ?? .init(0,0,0)
        rig.childNode(withName:"sun",recursively:false)?.position = .init(cos(angle)*90,sin(angle)*90,-28)
        rig.childNode(withName:"sun",recursively:false)?.opacity = daylight*(1-rain)
        rig.childNode(withName:"moon_phases",recursively:false)?.position = .init(-cos(angle)*90,-sin(angle)*90,-28)
        rig.childNode(withName:"moon_phases",recursively:false)?.opacity = (1-daylight)*(1-rain)
        rig.childNode(withName:"stars",recursively:false)?.opacity = 1-daylight
        for material in rig.water { material.diffuse.intensity = 0.2+0.8*daylight }
        scene.rootNode.childNode(withName:"drifting-cloud",recursively:false)?.geometry?.firstMaterial?.diffuse.intensity = (0.25+0.75*daylight)*(1-rain*0.25)
        if let weather = rig.weather {
            if let eye, !rig.isHidden {
                let outside = rain>0 && !underwater && eye.y>0.9 && Collision.clear(scene.rootNode,from:eye,to:.init(eye.x,eye.y+50,eye.z),radius:0.02)
                weather.birthRate = outside ? rain*([Biome.snow,.ice,.peaks].contains(area) ? 160 : 700) : 0
            } else { weather.birthRate = 0 }
        }
        if let eye { Landscape.medium(scene,area:area,eye:eye) }
    }
}
