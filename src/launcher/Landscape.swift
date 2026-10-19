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
    static func colour(_ rgb: UInt32) -> NSColor {
        NSColor(srgbRed:Double((rgb >> 16) & 255)/255,green:Double((rgb >> 8) & 255)/255,
                blue:Double(rgb & 255)/255,alpha:1)
    }

    static func height(_ biome: Biome, x: Double, z: Double, centre: Double = 0) -> Double {
        let x = x-centre, wave = sin(x*0.13)*1.5+cos(z*0.17)*1.2
        switch biome {
        case .central, .highlands, .midlands, .islands, .barrens, .city:
            let radius = biome == .central ? 36.0 : biome == .city ? 43 : biome == .islands ? 14 : biome == .highlands ? 33 : 26
            let distance = hypot(x/1.2,z+13)
            if distance > radius {
                for (cx,cz,r) in [(-39.0,-35.0,12.0),(36,-57,16),(-26,21,8),(43,7,9)] {
                    if hypot(x-cx,z-cz) < r { return floor(2+cos(x*0.3)) }
                }
                return -100
            }
            if biome == .central || biome == .city { return 4 }
            return floor(max(1,4+wave*(biome == .highlands ? 2 : biome == .barrens || biome == .midlands ? 0.3 : 1)))
        case .reef: return floor(-5+sin(x*0.2)*cos(z*0.2))
        case .coast: return z < 5+sin(x*0.08)*3 ? -4 : floor(3+wave*0.35)
        case .lush: return abs(x-4)<11 && abs(z-4)<7 ? -3 : floor(3+wave*0.7)
        case .mangrove, .swamp:
            return abs(sin(x*0.19)+cos(z*0.23)) < 0.9 ? -2 : floor(2+wave*0.4)
        case .deep, .trial: return 4
        case .wastes, .crimson, .warped, .soul, .basalt:
            if abs(z+6-sin(x*0.08)*5) < (biome == .basalt ? 7 : 4) { return -3 }
            return floor(max(2,5+wave*(biome == .basalt ? 2.6 : 1.2)+max(0,-z-45)*0.5))
        case .grove:
            if abs(x+5-sin(z*0.13)*4)<3 { return -2 }
            return floor(4+wave+max(0,-z-25)*0.2)
        case .terraces: return floor(3+wave+max(0,-z-12)*0.24)
        case .valley, .sculk: return floor(2+abs(x)*0.24+wave)
        case .shards:
            if hypot(x,z+12)>23 && sin(x*0.12)*cos(z*0.15)>0 { return -100 }
            return floor(4+wave+max(0,-z-18)*0.2)
        default: break
        }
        if [.meadow,.desert,.jungle,.mansion,.savanna,.snow].contains(biome), abs(x)<23, (-40 ... -6).contains(z) { return 4 }
        switch biome {
        case .peaks: return floor(3+wave+max(0,-z-4)*0.5+max(0,abs(x)-12)*0.28)
        case .badlands: return floor(3+wave+max(0,abs(x)-12)*0.4+max(0,-z-24)*0.24)
        case .dripstone: return floor(2+wave)
        default:
            if abs(z+43-sin(x*0.1)*5)<3 { return -2 }
            return floor(max(1,4+wave+max(0,-z-32)*0.15))
        }
    }

    static func scene(_ world: World, biome: Int = 0, assets: Assets) throws -> SCNScene {
        let area = world.biomes[world.index(biome)], scene = SCNScene()
        let camera = SCNNode(); camera.name = "camera"; camera.camera = SCNCamera()
        camera.camera?.fieldOfView = 48; camera.camera?.zFar = 230; camera.camera?.zNear = 0.1
        camera.camera?.wantsHDR = true; camera.camera?.wantsExposureAdaptation = false
        camera.camera?.exposureOffset = -0.15; camera.camera?.bloomIntensity = 0.12
        camera.camera?.bloomThreshold = 1.2; camera.camera?.screenSpaceAmbientOcclusionIntensity = 0.65
        camera.camera?.screenSpaceAmbientOcclusionRadius = 1.2
        scene.rootNode.addChildNode(camera)
        let sun = SCNNode(); sun.light = SCNLight(); sun.light?.type = .directional
        sun.eulerAngles = .init(-0.8,-0.6,0); sun.light?.castsShadow = true
        sun.light?.shadowMode = .deferred; sun.light?.shadowMapSize = .init(width:1024,height:1024)
        sun.light?.shadowSampleCount = 4; sun.light?.shadowColor = NSColor.black.withAlphaComponent(0.28)
        sun.light?.maximumShadowDistance = 100; scene.rootNode.addChildNode(sun)
        let fill = SCNNode(); fill.light = SCNLight(); fill.light?.type = .ambient
        scene.rootNode.addChildNode(fill)
        var land = Voxels(), detail = Voxels()
        let surface = try assets.tiles(area.surface)
        let stone = try assets.tiles(world == .nether ? "netherrack" : world == .end ? "end_stone" : area == .deep ? "deepslate" : "stone")
        var heights: [Int:Double] = [:]
        func key(_ x: Int, _ z: Int) -> Int { (x+70)*140+z+90 }
        for x in -67...67 { for z in -82...40 { heights[key(x,z)] = height(area,x:Double(x),z:Double(z)) } }
        func h(_ x: Int, _ z: Int) -> Double { heights[key(x,z)] ?? -100 }
        let strata = try (area == .badlands ? ["red_terracotta","orange_terracotta","yellow_terracotta","terracotta"] : []).map { try assets.tiles($0) }
        for x in -66...66 { for z in -81...39 {
            let y = h(x,z); guard y > -90 else { continue }
            var cap = 16
            for (face,d) in [(0,(0,1)),(1,(1,0)),(2,(0,-1)),(3,(-1,0))] {
                if h(x+d.0,z+d.1)<y { cap |= 1 << face }
            }
            land.cube(.init(1,1,1),at:.init(Double(x),y-0.5,Double(z)),material:surface[0],faces:cap,faceMaterials:surface)
            let bottom = world == .end || area == .shards ? -3-max(0,12-hypot(Double(x),Double(z+13))*0.3) : -8
            if !strata.isEmpty {
                for level in Int(bottom)..<Int(y)-1 {
                    var faces = 0
                    for (face,d) in [(0,(0,1)),(1,(1,0)),(2,(0,-1)),(3,(-1,0))] {
                        if h(x+d.0,z+d.1)<=Double(level) { faces |= 1 << face }
                    }
                    let tiles = strata[abs(level/2)%strata.count]
                    if faces != 0 { land.cube(.init(1,1,1),at:.init(Double(x),Double(level)+0.5,Double(z)),material:tiles[0],faces:faces,faceMaterials:tiles) }
                }
            } else {
                var sides = 0
                for (face,d) in [(0,(0,1)),(1,(1,0)),(2,(0,-1)),(3,(-1,0))] { if h(x+d.0,z+d.1)<y-1 { sides |= 1 << face } }
                land.cube(.init(1,max(0.1,y-1-bottom),1),at:.init(Double(x),(y-1+bottom)/2,Double(z)),material:stone[0],faces:sides | (world == .end ? 32 : 0),faceMaterials:stone)
            }
        } }
        func block(_ size: SCNVector3, _ at: SCNVector3, _ name: String) throws {
            let tiles = try assets.tiles(name)
            detail.cube(size,at:at,material:tiles[0],faceMaterials:tiles)
        }
        func sprite(_ name: String, x: Double, y: Double, z: Double, size: Double = 1, tint: UInt32? = nil) throws {
            let material = try assets.texture("textures/blocks/"+name,tint:tint)
            let uv = Array(repeating:CGRect(x:0,y:1,width:1,height:-1),count:6)
            detail.cube(.init(size,size,0),at:.init(x,y+size/2,z),material:material,faces:1,textureUV:uv)
            detail.cube(.init(0,size,size),at:.init(x,y+size/2,z),material:material,faces:2,textureUV:uv)
        }
        let trees = [.jungle,.forest,.mansion,.pale,.mangrove].contains(area) ? 90 : area.tree == nil ? 0 : 55
        for index in 0..<max(90,trees) {
            let x = Double((index*37)%113-56), z = Double((index*53)%105-72)
            let ground = height(area,x:x,z:z)
            let y = area == .mangrove || area == .swamp ? max(0.35,ground) : ground
            let building = [.meadow,.snow,.desert,.savanna,.mansion].contains(area)
            let clearing = abs(x)<(building ? 23 : 11) && (building ? (-42 ... 15) : (-29 ... 12)).contains(z)
            if y <= 0 || y < -90 { continue }
            if index<trees, let selected = area.tree, !clearing {
                let tree = area == .forest && index%4 == 0 ? "birch" : selected
                let bark = try assets.tiles(tree+"_log"), leaves = try assets.tiles(tree+"_leaves")
                let tall = tree == "jungle" ? 10+index%5 : tree == "spruce" ? 7+index%4 : tree == "dark_oak" ? 7 : 5+index%3
                let thick = tree == "jungle" && index%3 == 0 || tree == "dark_oak" ? 2.0 : 1
                detail.cube(.init(thick,Double(tall),thick),at:.init(x,y+Double(tall)/2,z),material:bark[0],faceMaterials:bark)
                var canopy = Voxels()
                func leaf(_ x: Int, _ y: Int, _ z: Int) -> Bool {
                    let levels = tree == "spruce" ? 6 : tree == "acacia" ? 2 : 4
                    guard (0..<levels).contains(y) else { return false }
                    let r = tree == "spruce" ? max(0,3-y/2) : tree == "acacia" ? 3-y : y<2 ? 3 : 2
                    return abs(x)<=r && abs(z)<=r && (r == 0 || abs(x)+abs(z)<r*2)
                }
                for dy in 0..<6 { for dx in -3...3 { for dz in -3...3 where leaf(dx,dy,dz) {
                    let faces = [[0,0,1],[1,0,0],[0,0,-1],[-1,0,0],[0,1,0],[0,-1,0]].enumerated().reduce(0) {
                        $0 | (leaf(dx+$1.element[0],dy+$1.element[1],dz+$1.element[2]) ? 0 : 1 << $1.offset)
                    }
                    canopy.cube(.init(1,1,1),at:.init(Double(dx),Double(dy),Double(dz)),material:leaves[0],faces:faces,faceMaterials:leaves)
                } } }
                let crown = canopy.node("wind-canopy"); crown.position = .init(x,y+Double(tall)-1,z)
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
                case .lush, .dripstone:
                    for level in 0..<(2+index%5) { try sprite("pointed_dripstone_"+(area == .lush ? "down" : "up")+(level == index%5+1 ? "_tip" : "_middle"),x:x,y:area == .lush ? 25-Double(level) : y+Double(level),z:z) }
                    if area == .lush { try sprite("cave_vines_body_berries",x:x+1,y:22-Double(index%7),z:z,size:2) }
                case .terraces:
                    let coral = try assets.texture("textures/blocks/coral_"+["pink","purple","blue"][index%3])
                    let tall = Double(3+index%5)
                    detail.cube(.init(2,tall,2),at:.init(x,y+tall/2,z),material:coral)
                    detail.cube(.init(5,2,4),at:.init(x+1,y+tall,z),material:coral)
                case .valley, .shards: try block(.init(1,Double(3+index%6),1),.init(x,y+Double(3+index%6)/2,z),"amethyst_block")
                default: break
                }
            }
            if world == .overworld && !area.underground && ![.mushroom,.desert,.badlands,.coast,.reef,.peaks,.snow,.pale].contains(area), !(abs(x)<22 && (-40 ... -8).contains(z)) {
                try sprite(index%7 == 0 ? "flower_dandelion" : "tallgrass",x:x,y:y,z:z,tint:index%7 == 0 ? nil : 0x82B653)
            }
        }
        if world == .overworld || area == .grove {
            for index in 0..<360 {
                let x = Double((index*17)%67-33)+0.2, z = Double((index*23)%65-34)+0.1
                let y = height(area,x:x,z:z)
                if y < -1, [.coast,.reef,.mangrove,.swamp,.lush].contains(area) {
                    try sprite(area == .mangrove || area == .swamp ? "reeds" : "seagrass",x:x,y:y,z:z,size:1.3,tint:0x78A73F)
                } else if y>0, !(abs(x)<23 && (-40 ... -7).contains(z)) {
                    switch area {
                    case .meadow,.forest,.cherry,.savanna,.jungle,.swamp,.mansion,.grove:
                        try sprite(index%9 == 0 ? "flower_dandelion" : index%11 == 0 ? "flower_rose" : "tallgrass",x:x,y:y,z:z,tint:index%9 == 0 || index%11 == 0 ? nil : 0x86B85B)
                    case .lush:
                        try sprite("azalea_leaves_flowers",x:x,y:y,z:z)
                    case .pale:
                        try sprite("pale_hanging_moss_tip",x:x,y:y,z:z)
                    default: break
                    }
                }
            }
        }
        if area == .jungle {
            for index in 0..<24 {
                let x = Double(index%2 == 0 ? -20-index%5 : 20+index%5), z = Double(index/2)*3-30
                let y = height(area,x:x,z:z)
                try block(.init(0.125,Double(5+index%4),0.125),.init(x,y+Double(5+index%4)/2,z),"bamboo")
            }
        }
        if area == .reef {
            for index in 0..<90 {
                let x = Double((index*17)%87-43), z = Double((index*31)%87-63), y = height(area,x:x,z:z)
                let coral = try assets.texture("textures/blocks/coral_"+["blue","pink","purple","red","yellow"][index%5])
                detail.cube(.init(2,Double(1+index%3),2),at:.init(x,y+Double(1+index%3)/2,z),material:coral)
                try sprite("seagrass",x:x+2,y:y,z:z)
            }
        }
        if area == .meadow {
            for z in -35...12 {
                try block(.init(3,0.08,1),.init(0,4.04,Double(z)),"dirt_path")
                if z%8 == 0 { try block(.init(13,0.08,2),.init(0,4.04,Double(z)),"dirt_path") }
            }
        }
        if area.underground || world == .nether {
            let roof = area.underground ? 34.0 : 45
            try block(.init(136,5,122),.init(0,roof,-30),world == .nether ? "netherrack" : "stone")
            for index in 0..<24 {
                let x = Double(index%2 == 0 ? -48+index%5 : 45-index%5), z = Double(index/2)*9-78
                try block(.init(5,roof,5),.init(x,roof/2,z),world == .nether ? "netherrack" : "stone")
                try block(.init(7,Double(index%6+3),6),.init(Double(index%7-3)*12,roof-Double(index%6+3)/2-2,-60),world == .nether ? "netherrack" : "stone")
            }
        }
        scene.rootNode.addChildNode(land.node("terrain")); scene.rootNode.addChildNode(detail.node("habitat-detail"))
        let landmark = try Structures.build(area,x:0,y:area == .coast ? 0 : area == .reef ? -5 : 4,assets:assets)
        scene.rootNode.addChildNode(landmark)
        if world == .overworld || world == .nether || area == .grove {
            try liquid(scene,assets:assets,lava:world == .nether,at:.init(0,0.35,-20),size:.init(width:136,height:122))
        }
        if [.jungle,.lush,.terraces,.grove].contains(area) || world == .nether {
            for index in 0..<(world == .nether ? 3 : 2) {
                let x = Double(index*27-26), z = -43.0-Double(index*9)
                try liquid(scene,assets:assets,lava:world == .nether,at:.init(x,12,z),size:.init(width:2,height:24),vertical:true)
            }
        }
        if world == .overworld && !area.underground || world == .sift {
            let white = SCNMaterial(); white.diffuse.contents = NSColor.white; white.lightingModel = .constant
            for index in 0..<9 {
                var shape = Voxels(); shape.cube(.init(13,1,5),at:.init(0,0,0),material:white)
                shape.cube(.init(7,1,5),at:.init(2,0,4),material:white)
                let cloud = shape.node("drifting-cloud"); cloud.position = .init(Double(index%4-2)*30,34+Double(index%2)*3,-60+Double(index/4)*30)
                cloud.runAction(.repeatForever(.sequence([.moveBy(x:16,y:0,z:0,duration:55),.moveBy(x:-16,y:0,z:0,duration:55)])))
                scene.rootNode.addChildNode(cloud)
            }
        }
        if area.underground || world == .nether || world == .sift || area == .cherry || area == .snow || area == .pale {
            let material = SCNMaterial(); material.diffuse.contents = colour(world == .nether ? 0xF4BE8F : area == .cherry ? 0xFFD9E7 : 0xBDDBDB)
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
        for (x,z) in [(-12.0,-12.0),(18,-26)] {
            let glow = SCNNode(); glow.light = SCNLight(); glow.light?.type = .omni
            glow.light?.color = colour(world == .nether ? 0xF5A15D : 0x9DDCD1)
            glow.light?.intensity = area.underground ? 350 : world == .nether ? 250 : 0
            glow.light?.attenuationEndDistance = 34; glow.position = .init(x,12,z); scene.rootNode.addChildNode(glow)
        }
        try populate(scene,world:world,area:area,factory:Mobs(assets:assets))
        focus(scene,world:world,biome:biome,animated:false)
        return scene
    }

    static func liquid(_ scene: SCNScene, assets: Assets, lava: Bool, at point: SCNVector3, size: CGSize, vertical: Bool = false) throws {
        let material = try assets.texture(lava ? "textures/blocks/lava_still" : "textures/blocks/water_still_grey",tint:lava ? nil : 0x3F8FBB).copy() as! SCNMaterial
        material.transparency = lava ? 1 : 0.42
        if lava { material.emission.contents = material.diffuse.contents; material.emission.intensity = 0.4 }
        let plane = SCNPlane(width:size.width,height:size.height); plane.firstMaterial = material
        let surface = SCNNode(geometry:plane); surface.name = vertical ? "waterfall" : "flowing-surface"
        surface.position = point; surface.eulerAngles.x = vertical ? 0 : -.pi/2
        surface.runAction(.repeatForever(.customAction(duration:128) { node,time in
            var transform = SCNMatrix4MakeScale(size.width,size.height,1)
            transform.m41 = vertical ? 0 : time/12; transform.m42 = time/(vertical ? 2 : 18)
            node.geometry?.firstMaterial?.diffuse.contentsTransform = transform
        }))
        scene.rootNode.addChildNode(surface)
    }

    static func focus(_ scene: SCNScene, world: World, biome: Int, animated: Bool) {
        let area = world.biomes[world.index(biome)], camera = scene.rootNode.childNode(withName:"camera",recursively:false)!
        let eye: SCNVector3, aim: SCNVector3
        switch area {
        case .city: eye = .init(48,34,63); aim = .init(6,19,-21)
        case .deep: eye = .init(34,24,40); aim = .init(0,10,-20)
        case .trial: eye = .init(24,22,28); aim = .init(0,8,-17)
        case .lush: eye = .init(23,13,30); aim = .init(0,6,-12)
        case .badlands: eye = .init(24,15,28); aim = .init(0,5,-16)
        case .mangrove,.swamp: eye = .init(25,13,34); aim = .init(0,4,-12)
        case .reef: eye = .init(28,3,30); aim = .init(0,-1,-15)
        case .mansion: eye = .init(37,23,48); aim = .init(0,10,-20)
        case .central: eye = .init(47,32,62); aim = .init(0,13,-20)
        default: eye = .init(29,20,42); aim = .init(0,6,-15)
        }
        scene.background.contents = colour(area.sky); scene.fogColor = colour(area.sky)
        scene.fogStartDistance = area.underground ? 45 : 75; scene.fogEndDistance = area.underground ? 115 : 175
        for light in scene.rootNode.childNodes.compactMap(\.light) {
            if light.type == .ambient { light.intensity = area.underground ? 400 : area == .pale ? 300 : 500 }
            if light.type == .directional { light.intensity = area.underground ? 300 : area == .pale ? 450 : 900 }
        }
        let orientation = SCNNode(); orientation.position = eye; orientation.look(at:aim)
        camera.removeAction(forKey:"journey")
        let drift = SCNAction.repeatForever(.sequence([.moveBy(x:-1.3,y:0.15,z:-0.6,duration:9),.moveBy(x:1.3,y:-0.15,z:0.6,duration:9)]))
        if animated {
            let move = SCNAction.move(to:eye,duration:2), turn = SCNAction.rotateTo(x:orientation.eulerAngles.x,y:orientation.eulerAngles.y,z:orientation.eulerAngles.z,duration:2,usesShortestUnitArc:true)
            camera.runAction(.sequence([.group([move,turn]),drift]),forKey:"journey")
        } else { camera.position = eye; camera.orientation = orientation.orientation; camera.runAction(drift,forKey:"journey") }
    }

    private static func populate(_ scene: SCNScene, world: World, area: Biome, factory: Mobs) throws {
        let spots: [(Double,Double)] = [(-12,9),(-3,5),(10,4),(18,13),(-21,-3),(24,-7),(-7,17),(10,19)]
        for (kind,species) in area.residents.enumerated() {
            let solitary = [.warden,.creaking,.ironGolem,.ravager,.piglinBrute,.witch,.sniffer].contains(species)
            let count = solitary ? 1 : [.cod,.salmon,.enderman,.chicken,.sheep,.cow,.pig,.strider].contains(species) ? 4 : 3
            for index in 0..<count {
                let actor = SCNNode(); actor.name = "resident-\(species.rawValue)-\(index)"
                let model = try factory.make(species,biome:area); actor.addChildNode(model)
                if !species.flying && !species.swimming { model.position.y = max(0,-model.boundingBox.min.y) }
                let spot = spots[kind%spots.count]
                var x = spot.0+cos(Double(index)*2.4+Double(kind))*2, z = spot.1+sin(Double(index)*2.4+Double(kind))*2.5
                if species.swimming {
                    if area == .lush { x = 1+Double(index)*2; z = 2+Double(kind%2)*3 }
                    else if area == .coast || area == .reef { x = -14+Double(kind)*7+Double(index); z = -2-Double(index)*3 }
                }
                if area == .trial { x = -9+Double(kind%3)*8+Double(index)*1.2; z = -21+Double(kind/3)*8+Double(index%2)*2 }
                if species == .strider { z = -6+sin(x*0.08)*5 }
                if [.blaze,.witherSkeleton,.piglinBrute].contains(species) { x = -8+Double(index)*5; z = -19 }
                if species == .warden { x = -4; z = -1 }
                if species == .shulker { x = -8+Double(index)*8; z = -13 }
                if species == .endermite { x = -14+Double(index)*3; z = 12 }
                if height(area,x:x,z:z) < -90 { x *= 0.35; z = -7+Double(index) }
                func point(_ x: Double, _ z: Double) -> SCNVector3 {
                    let ground = height(area,x:x.rounded(),z:z.rounded())
                    let elevation = species.swimming ? -1.3 : species == .strider ? 0.35 : [.blaze,.witherSkeleton].contains(species) ? 12 : max(0.4,ground)
                    return .init(x,elevation+(species.flying ? (species == .breeze ? 1.2 : 3) : 0),z)
                }
                actor.position = point(x,z); actor.eulerAngles.y = Double(kind+index)*1.3
                if species != .shulker && species != .warden {
                    let destination = point(x+0.7,z+0.4)
                    let move = SCNAction.move(to:destination,duration:Double(7+index))
                    let back = SCNAction.move(to:point(x,z),duration:Double(9+kind))
                    actor.runAction(.repeatForever(.sequence([.wait(duration:Double(index)),move,.wait(duration:2),back])))
                }
                scene.rootNode.addChildNode(actor)
            }
        }
        if area == .central || world == .nether {
            let group = SCNNode(); group.name = "sky-resident"
            let model = try factory.actor(world == .end ? "ender_dragon" : "ghast"); group.addChildNode(model)
            group.position = .init(-20,23,-23)
            group.runAction(.repeatForever(.sequence([.move(to:.init(22,25,-37),duration:20),.move(to:.init(-20,23,-23),duration:20)])))
            scene.rootNode.addChildNode(group)
        }
    }
}
