import AppKit
import SceneKit

private final class Footprint: SCNNode {
    var points: [SCNVector3] = []

    override func clone() -> Self {
        let copy = super.clone(); copy.points = points
        return copy
    }
}

final class Door: SCNNode {
    var swing = Double.pi/2
    var axis = SCNVector3(0,1,0)
    private var open = false
    private var visitors = NSHashTable<SCNNode>.weakObjects()

    override func clone() -> Self {
        let copy = super.clone()
        copy.swing = swing; copy.axis = axis; copy.open = open; copy.visitors = .weakObjects()
        return copy
    }

    func approach(_ eye: SCNVector3) {
        let p = convertPosition(.init(0,0,0),to:nil)
        func nearby(_ eye: SCNVector3) -> Bool { hypot(p.x-eye.x,p.z-eye.z) < (open ? 3.4 : 2.7) && abs(p.y-eye.y)<3 }
        let near = nearby(eye) || visitors.allObjects.contains { nearby($0.worldPosition) }
        guard near != open else { return }
        open = near
        removeAction(forKey:"door")
        let angle = near ? swing : 0
        runAction(.rotateTo(x:axis.x*angle,y:axis.y*angle,z:axis.z*angle,duration:0.18),forKey:"door")
    }

    func register(_ resident: SCNNode) { visitors.add(resident) }

    // Route checks treat only the moving leaves as passable, without altering their visible pose
    static func clearance<T>(_ root: SCNNode, _ check: () throws -> T) rethrows -> T {
        let leaves = collect(root).filter { $0.categoryBitMask != 0 }.map { ($0,$0.categoryBitMask) }
        guard !leaves.isEmpty else { return try check() }
        for (leaf,_) in leaves { leaf.categoryBitMask = 0 }
        SCNTransaction.flush()
        defer {
            for (leaf,mask) in leaves { leaf.categoryBitMask = mask }
            SCNTransaction.flush()
        }
        return try check()
    }

    static func collect(_ root: SCNNode) -> [Door] {
        var doors: [Door] = []
        root.enumerateChildNodes { node,_ in if let door = node as? Door { doors.append(door) } }
        return doors
    }
}

enum Structures {
    static func foundations(_ root: SCNNode) -> Set<SIMD3<Int>> {
        var cells = Set<SIMD3<Int>>()
        func collect(_ node: SCNNode) {
            for point in (node as? Footprint)?.points ?? [] {
                let p = root.convertPosition(point,from:node)
                cells.insert(.init(Int(p.x.rounded()),Int(p.y.rounded()),Int(p.z.rounded())))
            }
        }
        collect(root); root.enumerateChildNodes { node,_ in collect(node) }
        return cells
    }

    static func build(_ biome: Biome, x: Double, y: Double, assets: Assets) throws -> SCNNode {
        let root = SCNNode(); root.name = "landmark-\(biome)"; root.position = .init(x,y,-18)
        var mesh = Voxels(), templates: [String:SCNNode] = [:]
        func cube(_ size: SCNVector3, _ p: SCNVector3, _ block: String) throws {
            let tiles = try assets.tiles(block)
            mesh.cube(size,at:p,material:tiles[0],faceMaterials:tiles)
        }
        func ring(_ size: SCNVector3, _ p: SCNVector3, _ block: String, opening: Double = 0) throws {
            for side in [-1.0,1] {
                try cube(.init(1,size.y,size.z),.init(p.x+side*(size.x-1)/2,p.y,p.z),block)
                let width = (size.x-2-opening)/2
                if width>0 { try cube(.init(width,size.y,1),.init(p.x+side*(opening+width)/2,p.y,p.z+(size.z-1)/2),block) }
            }
            try cube(.init(size.x-2,size.y,1),.init(p.x,p.y,p.z-(size.z-1)/2),block)
        }
        func place(_ name: String, _ p: SCNVector3 = .init(0,0,0), turn: Double = 0) throws {
            let wrapper = SCNNode(); wrapper.position = p; wrapper.eulerAngles.y = turn
            if biome == .meadow { wrapper.position.y += Terrain(biome:biome).height(p.x,p.z-18)-y-1 }
            if templates[name] == nil { templates[name] = try template(name,assets:assets) }
            wrapper.addChildNode(templates[name]!.clone()); root.addChildNode(wrapper)
        }
        switch biome {
        case .meadow:
            try place("village/plains/houses/plains_medium_house_1",.init(-10,0,-10),turn:.pi)
            try place("village/plains/houses/plains_small_house_1",.init(11,0,-11))
            try place("village/plains/houses/plains_small_house_2",.init(-12,0,7),turn:.pi/2)
            try place("village/plains/houses/plains_large_farm_1",.init(13,0,8))
            try place("village/plains/town_centers/plains_fountain_01",.init(0,0,2))
            try place("village/plains/houses/plains_animal_pen_1",.init(-20,0,-1))
            try place("village/plains/houses/plains_temple_4",.init(-15,0,-27),turn:.pi)
            try place("village/plains/houses/plains_weaponsmith_1",.init(17,0,-25))
        case .forest:
            try place("ruined_portal/portal_4",.init(-5,-2,-3))
            for z in -4...4 { try cube(.init(1,1,1),.init(8,0.5,Double(z)),"oak_log") }
        case .cherry:
            try place("village/plains/houses/plains_small_house_1",.init(-6,0,-5))
            try place("village/plains/town_centers/plains_meeting_point_2",.init(7,0,2))
        case .snow:
            try place("igloo/igloo_top_no_trapdoor",.init(11,0,4))
            try place("village/taiga/houses/taiga_medium_house_1",.init(-10,0,-6))
            try place("village/taiga/houses/taiga_small_house_1",.init(2,0,-12))
        case .peaks, .warped: try place("ruined_portal/portal_1")
        case .badlands, .lush:
            // Mineshafts are generated in code rather than saved as templates
            let wood = biome == .badlands ? "dark_oak" : "oak"
            for z in stride(from:-8.0,through:8,by:4) {
                for side in [-1.0,1] { try cube(.init(0.375,2,0.375),.init(side*1.3,1,z),wood+"_fence") }
                try cube(.init(3,1,1),.init(0,2.5,z),wood+"_planks")
            }
            let rail = try assets.texture("textures/blocks/rail_normal")
            mesh.cube(.init(1,0,20),at:.init(0,0.03,0),material:rail,faces:16)
        case .savanna:
            try place("pillageroutpost/watchtower",.init(0,0,-5))
            try place("pillageroutpost/feature_cage_with_allays",.init(-12,0,8))
            try place("pillageroutpost/feature_tent1",.init(13,0,6))
            try place("pillageroutpost/feature_targets",.init(-9,0,-12))
            try place("pillageroutpost/feature_logs",.init(12,0,-10))
        case .mansion:
            try cube(.init(34,2,48),.init(0,-1,7),"cobblestone")
            for floor in [0.0,8] {
                for z in stride(from:-12.0,through:12,by:8) {
                    try place("mansion/wall_window",.init(-16,floor,z))
                    try place("mansion/wall_window",.init(16,floor,z),turn:.pi)
                }
                for x in stride(from:-12.0,through:12,by:8) {
                    try place("mansion/wall_window",.init(x,floor,-16),turn:-.pi/2)
                    if abs(x)>4 { try place("mansion/wall_flat",.init(x,floor,16),turn:.pi/2) }
                }
                for x in [-8.0,0,8] { for z in [-8.0,0,8] { try place("mansion/1x1_a1",.init(x,floor,z)) } }
            }
            for x in stride(from:-12.0,through:12,by:8) { for z in stride(from:-12.0,through:12,by:8) { try place("mansion/roof",.init(x,16,z)) } }
            try place("mansion/entrance",.init(0,0,20),turn:-.pi/2)
        case .trial:
            // Bury the template's six-block foundation beneath the interior camera
            root.position.y -= 6
            let chamber = try template("trial_chambers/chamber/assembly",assets:assets)
            root.addChildNode(chamber)
            for x in [-11.0,11] {
                try place("trial_chambers/chamber/assembly/full_column",.init(x,7,-8))
                try place("trial_chambers/chamber/assembly/platform_1",.init(x,12,0))
            }
            try place("trial_chambers/chamber/assembly/spawner_1",.init(0,7,-7))
        case .dripstone:
            for index in 0..<7 {
                let x = Double(index-3)*5, tall = Double(4+index%4)
                try cube(.init(2,tall,2),.init(x,tall/2,-8),"dripstone_block")
                try cube(.init(1,3,1),.init(x,tall+1.5,-8),"dripstone_block")
            }
        case .swamp:
            try cube(.init(7,1,9),.init(0,3,0),"spruce_planks")
            for x in [-3.0,3] { for z in [-4.0,4] { try cube(.init(1,5,1),.init(x,0.5,z),"oak_log") } }
            for z in -3...3 { for side in [-1.0,1] { if z != 0 { try cube(.init(1,3,1),.init(side*3,5,Double(z)),"spruce_planks") } } }
            try cube(.init(7,3,1),.init(0,5,-4),"spruce_planks")
            for tier in 0..<3 { try cube(.init(Double(9-tier*2),1,11),.init(0,7+Double(tier),0),"spruce_planks") }
            try cube(.init(1,1,1),.init(-2,4,-2),"crafting_table")
            try cube(.init(1,1,1),.init(2,4,-2),"cauldron")
            for z in stride(from:4.0,through:10,by:1) { try cube(.init(3,0.5,1),.init(0,3-(z-4)*0.5,z),"spruce_planks") }
        case .reef:
            for level in 0..<4 { try cube(.init(Double(17-level*4),1,Double(17-level*4)),.init(-13,Double(level)-1,-8),level%2 == 0 ? "prismarine" : "prismarine_bricks") }
            for side in [-1.0,1] {
                try cube(.init(3,6,3),.init(-13+side*9,1,-8),"dark_prismarine")
                try cube(.init(2,1,2),.init(-13+side*9,4.5,-8),"sea_lantern")
            }
            try place("shipwreck/swrightsideupbackhalfdegraded",.init(15,0,3))
        case .river: break
        case .ice:
            try place("igloo/igloo_top_no_trapdoor",.init(-9,0,-4))
            for index in 0..<18 {
                let x = Terrain.random(index,4,seed:8)*55-28, z = Terrain.random(index,9,seed:9)*55-35
                let h = Double(8+index%13)
                for level in 0..<Int(h) {
                    let width = level < 3 ? 3.0 : level<Int(h)-3 ? 2 : 1
                    try cube(.init(width,1,width),.init(x,Double(level)+0.5,z),"packed_ice")
                }
            }
        case .monument:
            try cube(.init(58,1,58),.init(0,0.5,0),"prismarine")
            for tier in 0..<9 {
                let width = Double(56-tier*4)
                try ring(.init(width,1,width),.init(0,Double(tier)+1.5,-2),tier%3 == 0 ? "prismarine_bricks" : "prismarine",opening:tier<4 ? 5 : 0)
            }
            for side in [-1.0,1] {
                for x in stride(from:7.0,through:27,by:4) {
                    try cube(.init(2,6,2),.init(side*x,5,22),"prismarine_bricks")
                    try cube(.init(1,1,1),.init(side*x,8.5,23),"sea_lantern")
                }
                try cube(.init(21,2,6),.init(side*17,8,19),"prismarine_bricks")
                try cube(.init(2,9,4),.init(side*5,5.5,20),"dark_prismarine")
                try cube(.init(3,3,3),.init(side*17,10,17),"prismarine_bricks")
                try cube(.init(2,1,2),.init(side*17,12,17),"sea_lantern")
                for z in stride(from:-23.0,through:22,by:7) {
                    try cube(.init(4,7,4),.init(side*25,-2,z),"prismarine_bricks")
                }
            }
            try cube(.init(12,2,4),.init(0,10.5,20),"dark_prismarine")
            for tier in 0..<7 {
                let width = Double(20-tier*2)
                try ring(.init(width,1,width),.init(0,Double(tier)+10.5,-9),"prismarine_bricks")
                for side in [-1.0,1] { try cube(.init(1,1,width),.init(side*(width/2-1),Double(tier)+10.5,-9),"dark_prismarine") }
            }
            try cube(.init(6,1,6),.init(0,16.5,-9),"prismarine_bricks")
            for side in [-1.0,1] { try cube(.init(2,3,2),.init(side*5,18,-9),"sea_lantern") }
        case .desert:
            for tier in 0..<10 {
                let span = Double(21-tier*2)
                try ring(.init(span,1,span),.init(0,Double(tier)+0.5,-4),"sandstone",opening:tier<3 ? 3 : 0)
            }
            try cube(.init(1,1,1),.init(0,9.5,-4),"sandstone")
            for side in [-1.0,1] {
                try ring(.init(5,8,5),.init(side*8,4,5),"sandstone",opening:3)
                try cube(.init(3,5,1),.init(side*8,5.5,7),"sandstone")
                try cube(.init(3,1,3),.init(side*8,8.5,5),"chiseled_sandstone")
                for p in [SCNVector3(side*8,4,7.51),.init(side*8,5,7.51),.init(side*8,3,7.51),.init(side*8-1,4,7.51),.init(side*8+1,4,7.51)] {
                    try cube(.init(1,1,0.02),p,"orange_terracotta")
                }
            }
        case .jungle:
            try cube(.init(12,1,15),.init(0,-0.5,0),"mossy_cobblestone")
            for tier in 0..<3 {
                try ring(.init(Double(12-tier*2),3,Double(15-tier*2)),.init(0,Double(tier*3)+1.5,0),tier%2 == 0 ? "mossy_cobblestone" : "cobblestone",opening:3)
            }
            try cube(.init(8,1,11),.init(0,9.5,0),"mossy_cobblestone")
            for step in 0..<7 {
                try cube(.init(4,1,1),.init(0,Double(step)+0.5,9-Double(step)),"mossy_cobblestone")
            }
            for side in [-1.0,1] {
                try cube(.init(1,4,1),.init(side*4,10,4),"chiseled_stone_bricks")
                try cube(.init(1,3,1),.init(side*3.5,10.5,0),"mossy_cobblestone")
            }
            try cube(.init(8,1,1),.init(0,12.5,0),"cobblestone")
        case .deep:
            try place("ancient_city/city_center/city_center_1",.init(0,-7,-8))
            try place("ancient_city/structures/barracks",.init(-25,0,5))
            try place("ancient_city/structures/camp_1",.init(23,0,9))
            try place("ancient_city/structures/large_pillar_1",.init(-19,0,-20))
            try place("ancient_city/structures/large_pillar_1",.init(19,0,-20))
        case .crimson:
            try place("bastion/bridge/starting_pieces/entrance",.init(0,-12,-11))
            try place("bastion/bridge/bridge_pieces/bridge",.init(8,-8,13))
            try place("bastion/bridge/ramparts/rampart_0",.init(-13,-4,-10))
        case .soul:
            try place("nether_fossils/fossil_1",.init(-3,0,1))
            try place("nether_fossils/fossil_2",.init(4,0,-6))
        case .wastes:
            for x in stride(from:-25.0,through:25,by:6) {
                for side in [-1.0,1] { try cube(.init(3,18,3),.init(x,-1,side*3),"nether_bricks") }
            }
            try cube(.init(56,2,7),.init(0,7,0),"nether_bricks")
            try cube(.init(7,2,32),.init(0,7,-13),"nether_bricks")
            for side in [-1.0,1] {
                try cube(.init(56,1,0.375),.init(0,8.5,side*3),"nether_brick_fence")
                for x in stride(from:-27.0,through:27,by:2) { try cube(.init(1,1,1),.init(x,9.5,side*3),"nether_bricks") }
                try cube(.init(11,1,11),.init(side*22,7,-12),"nether_bricks")
                for edge in [-5.0,5] {
                    try cube(.init(1,4,11),.init(side*22+edge,9.5,-12),"nether_bricks")
                    if edge < 0 { try cube(.init(11,4,1),.init(side*22,9.5,-12+edge),"nether_bricks") }
                    else {
                        for jamb in [-1.0,1] { try cube(.init(4,4,1),.init(side*22+jamb*3.5,9.5,-7),"nether_bricks") }
                        try cube(.init(3,1,1),.init(side*22,11,-7),"nether_bricks")
                    }
                }
                try cube(.init(5,2,8),.init(side*22,7,-5),"nether_bricks")
                try cube(.init(13,1,13),.init(side*22,12,-12),"nether_bricks")
            }
            try cube(.init(5,1,9),.init(0,8.5,-20),"soul_sand")
            try cube(.init(11,1,11),.init(0,12,0),"nether_bricks")
            for side in [-1.0,1] {
                for z in [-5.0,5] { try cube(.init(2,4,2),.init(side*4.5,10,z),"nether_bricks") }
                try cube(.init(1,1,11),.init(side*3.5,11,0),"nether_bricks")
            }
            for x in -2...2 { for z in -3...3 { try cube(.init(0.6,0.6,0.6),.init(Double(x),9.3,Double(z)-20),"nether_wart") } }
            try cube(.init(1,1,1),.init(22,8.5,-12),"mob_spawner")
        case .central:
            for index in 0..<10 {
                let angle = Double(index)*Double.pi/5, h = Double(14+index%4*4)
                let x = sin(angle)*27, z = cos(angle)*23-5
                try cube(.init(3,h,3),.init(x,h/2,z),"obsidian")
                let crystal = try assets.actor("ender_crystal")
                crystal.position = .init(x,h+1,z); root.addChildNode(crystal)
                if index%4 == 0 {
                    for dx in -2...2 { for dz in -2...2 { for level in 0..<4 where abs(dx)==2 || abs(dz)==2 || level == 3 {
                        var states: [String:String] = [:]
                        for (edge,ex,ez) in [("east",1,0),("west",-1,0),("south",0,1),("north",0,-1)] {
                            let nx = dx+ex, nz = dz+ez
                            if abs(nx)<=2 && abs(nz)<=2 && (level == 3 || abs(nx)==2 || abs(nz)==2) { states[edge] = "true" }
                        }
                        try fixture("iron_bars",states:states,at:.init(x+Double(dx)-0.5,h+Double(level),z+Double(dz)-0.5),assets:assets,mesh:&mesh)
                    } } }
                }
            }
            // The dragon's active fight has a dry seven-block bowl, not an active exit portal
            for x in -3...3 { for z in -3...3 {
                let distance = x*x+z*z
                guard distance<13 else { continue }
                try cube(.init(1,1,1),.init(Double(x),-0.5,Double(z)-5),distance<7 ? "bedrock" : "end_stone")
                if distance>=7 { try cube(.init(1,1,1),.init(Double(x),0.5,Double(z)-5),"bedrock") }
            } }
            try cube(.init(1,4,1),.init(0,2,-5),"bedrock")
            for (x,z,facing) in [(1.0,0.0,"east"),(-1,0,"west"),(0,1,"south"),(0,-1,"north")] {
                try fixture("wall_torch",states:["facing":facing],at:.init(x-0.5,2,z-5.5),assets:assets,mesh:&mesh)
            }
        case .highlands:
            for h in [0.0,4] { try cube(.init(3,1,3),.init(0,h+3,0),"bedrock") }
            for side in [-1.0,1] { try cube(.init(1,3,1),.init(side,5,0),"bedrock") }
            try cube(.init(1,1,1),.init(0,5,0),"obsidian")
        case .city:
            try place("endcity/base_floor")
            try place("endcity/second_floor",.init(0,0,0))
            try place("endcity/third_floor",.init(0,4,0))
            try place("endcity/third_roof",.init(0,12,0))
            try place("endcity/tower_base",.init(0,13,-1))
            for level in 0..<3 { try place("endcity/tower_piece",.init(0,19+Double(level)*4,-1)) }
            try place("endcity/tower_top",.init(0,31,-1))
            try place("endcity/fat_tower_base",.init(-19,8,-15))
            for level in 0..<2 { try place("endcity/fat_tower_middle",.init(-19,12+Double(level)*8,-15)) }
            try place("endcity/fat_tower_top",.init(-19,28,-15))
            for index in 0..<5 { try place("endcity/bridge_piece",.init(-Double(index)*4,19,-1),turn:.pi/2) }
            for index in 0..<3 { try place("endcity/bridge_piece",.init(-19,19,-5-Double(index)*4)) }
            for index in 0..<6 { try place("endcity/bridge_piece",.init(Double(index)*4+5,23,-1),turn:.pi/2) }
            try place("endcity/ship",.init(28,15,-3))
        case .coast:
            try place("shipwreck/swwithmast",.init(-7,-3,0))
            try place("ruined_portal/portal_2",.init(22,1,15))
        case .ruins: try place("ruined_portal/portal_3")
        case .valley, .shards, .sculk:
            try portal(root,at:.init(0,2,0),assets:assets,sift:true)
        case .pale:
            try cube(.init(1,1,1),.init(-7,5,-4),"creaking_heart")
        case .basalt:
            for index in 0..<9 { try cube(.init(2,Double(8+index%4*3),2),.init(Double(index-4)*4,Double(8+index%4*3)/2,-19),"polished_basalt") }
        case .mangrove, .mushroom, .midlands, .islands, .barrens, .terraces, .grove, .mine, .stronghold, .sulfur: break
        }
        root.addChildNode(mesh.node("masonry")); return root
    }

    static func portal(_ root: SCNNode, at p: SCNVector3, assets: Assets, sift: Bool = false) throws {
        var mesh = Voxels()
        let tiles = try assets.tiles("obsidian")
        for x in -2..<2 { for y in 0..<5 where x == -2 || x == 1 || y == 0 || y == 4 {
            mesh.cube(.init(1,1,1),at:.init(Double(x)+0.5,Double(y)+0.5,0),material:tiles[0],faceMaterials:tiles)
        } }
        let frame = mesh.node(sift ? "artistic-rift" : "nether-portal"); frame.position = p; root.addChildNode(frame)
        let material = try assets.texture("textures/blocks/portal",animated:true).copy() as! SCNMaterial
        material.lightingModel = .constant
        if sift { material.multiply.contents = NSColor.cyan }
        let plane = SCNPlane(width:2,height:3); plane.firstMaterial = material
        let surface = SCNNode(geometry:plane); surface.name = "portal-surface"; surface.position = .init(0,2.5,0)
        Landscape.animate(surface,material:material)
        frame.addChildNode(surface)
    }

    static func endPortal(_ root: SCNNode, at p: SCNVector3, assets: Assets) throws {
        var mesh = Voxels()
        let side = try assets.texture("textures/blocks/endframe_side"), top = try assets.texture("textures/blocks/endframe_top")
        let eye = try assets.texture("textures/blocks/endframe_eye")
        for edge in [-2.0,2] { for index in -1...1 {
            for centre in [SCNVector3(edge,0.40625,Double(index)),.init(Double(index),0.40625,edge)] {
                mesh.cube(.init(1,0.8125,1),at:centre,material:side,top:top)
                mesh.cube(.init(0.5,0.1875,0.5),at:.init(centre.x,0.90625,centre.z),material:eye,textureUV:Array(repeating:CGRect(x:0,y:1,width:1,height:-1),count:6))
            }
        } }
        let frame = mesh.node("end-frames"); frame.position = p; root.addChildNode(frame)
        let stars = try assets.texture("textures/entity/end_portal").copy() as! SCNMaterial
        stars.lightingModel = .constant
        let plane = SCNPlane(width:3,height:3); plane.firstMaterial = stars
        let surface = SCNNode(geometry:plane); surface.name = "end-portal"
        surface.position = .init(p.x,p.y+0.75,p.z); surface.eulerAngles.x = -.pi/2
        stars.diffuse.contentsTransform = SCNMatrix4MakeScale(4,4,1)
        surface.runAction(.repeatForever(.customAction(duration:96) { node,time in
            var transform = SCNMatrix4MakeScale(4,4,1); transform.m41 = time/96; transform.m42 = time/128
            node.geometry?.firstMaterial?.diffuse.contentsTransform = transform
        }))
        root.addChildNode(surface)
    }
}

extension Structures {
    // Shared by imported villages and the mine's placed lights
    @discardableResult
    static func fixture(_ name: String, states: [String:String] = [:], data: [String:Any] = [:], at p: SCNVector3,
                        assets: Assets, mesh: inout Voxels) throws -> Bool {
        let torch = ["torch","wall_torch","soul_torch","soul_wall_torch","redstone_torch","redstone_wall_torch","copper_torch","copper_wall_torch"].contains(name)
        let crop = ["wheat","carrots","potatoes","beetroots"].contains(name)
        let banner = name == "wall_banner" || name == "standing_banner" || name.hasSuffix("_banner")
        let panel = name.hasSuffix("_door") || name.hasSuffix("trapdoor") || name == "ladder"
        let chest = ["chest","trapped_chest","ender_chest"].contains(name)
        let bed = name.hasSuffix("_bed")
        guard torch || crop || banner || panel || chest || bed || name == "iron_bars" || name == "brewing_stand" || name == "bell" || name == "lantern" || name == "soul_lantern" else { return false }
        let first = mesh.vertices.count
        if torch {
            let path = name.contains("soul") ? "soul_torch" : name.contains("redstone") ? "redstone_torch_on" : name.contains("copper") ? "copper_torch" : "torch_on"
            let material = try assets.texture("textures/blocks/"+path)
            var uv = Array(repeating:CGRect(x:7.0/16,y:1,width:2.0/16,height:-10.0/16),count:6)
            uv[4] = CGRect(x:7.0/16,y:8.0/16,width:2.0/16,height:-2.0/16)
            uv[5] = CGRect(x:7.0/16,y:15.0/16,width:2.0/16,height:-2.0/16)
            let wall = name.contains("wall")
            mesh.cube(.init(0.125,0.625,0.125),at:.init(p.x+(wall ? 0 : 0.5),p.y+0.3125+(wall ? 0.21875 : 0),p.z+0.5),material:material,textureUV:uv)
            if wall {
                // The foot pivots on the backing face rather than floating at the cell centre
                let lean = SCNNode(); lean.position = .init(p.x,p.y+0.21875,p.z+0.5); lean.eulerAngles.z = -.pi/8
                mesh.transform(from:first,origin:lean.position,by:lean)
                let turn = SCNNode(); turn.position = .init(p.x+0.5,p.y,p.z+0.5)
                let facing = states["facing"] ?? "east"
                turn.eulerAngles.y = facing == "south" ? -.pi/2 : facing == "west" ? .pi : facing == "north" ? .pi/2 : 0
                mesh.transform(from:first,origin:turn.position,by:turn)
            }
        } else if chest || bed {
            let colour = name.replacingOccurrences(of:"_bed",with:"")
            let path = bed ? "bed/"+(colour == "light_gray" ? "silver" : colour)
                : "chest/"+(name == "ender_chest" ? "ender" : name == "trapped_chest" ? "trapped" : "normal")
            let material = try assets.texture("textures/entity/"+path)
            func part(_ size: SCNVector3, _ centre: SCNVector3, _ u: Double, _ v: Double) {
                let w = size.x, h = size.y, d = size.z
                let uv = [CGRect(x:u+d+w+d,y:v+d,width:w,height:h),CGRect(x:u,y:v+d,width:d,height:h),
                          CGRect(x:u+d,y:v+d,width:w,height:h),CGRect(x:u+d+w,y:v+d,width:d,height:h),
                          CGRect(x:u+d,y:v,width:w,height:d),CGRect(x:u+d+w,y:v,width:w,height:d)]
                    .map { CGRect(x:$0.minX/64,y:$0.maxY/64,width:$0.width/64,height:-$0.height/64) }
                mesh.cube(.init(w/16,h/16,d/16),at:.init(p.x+centre.x/16,p.y+centre.y/16,p.z+centre.z/16),material:material,textureUV:uv)
            }
            if bed {
                let head = states["part"] == "head"
                let v = head ? 0.0 : 16
                let uv = [CGRect(x:22,y:0,width:16,height:6),CGRect(x:0,y:v+6,width:6,height:16),
                          CGRect(x:6,y:0,width:16,height:6),CGRect(x:22,y:v+6,width:6,height:16),
                          CGRect(x:6,y:v+6,width:16,height:16),CGRect(x:28,y:v+6,width:16,height:16)]
                    .map { CGRect(x:$0.minX/64,y:$0.maxY/64,width:$0.width/64,height:-$0.height/64) }
                let first = mesh.uv.count
                mesh.cube(.init(1,0.375,1),at:.init(p.x+0.5,p.y+0.375,p.z+0.5),material:material,textureUV:uv)
                // Bedrock unwraps one 16 × 32 panel, split here at the two source cells
                for (face,shift) in [(1,1),(3,3)] {
                    let corners = Array(mesh.uv[(first+face*4)..<(first+face*4+4)])
                    for index in 0..<4 { mesh.uv[first+face*4+index] = corners[(index+shift)%4] }
                }
                for (index,x) in [1.5,14.5].enumerated() {
                    part(.init(3,3,3),.init(x,1.5,head ? 1.5 : 14.5),Double(index)*12,head ? 38 : 44)
                }
            } else {
                part(.init(14,10,14),.init(8,5,8),0,19)
                part(.init(14,5,14),.init(8,11.5,8),0,0)
                part(.init(2,4,1),.init(8,9,15.5),0,0)
            }
            let turn = SCNNode(); turn.position = .init(p.x+0.5,p.y,p.z+0.5)
            let facing = states["facing"] ?? "north"
            turn.eulerAngles.y = bed ? (facing == "east" ? -.pi/2 : facing == "south" ? .pi : facing == "west" ? .pi/2 : 0)
                : facing == "east" ? .pi/2 : facing == "north" ? .pi : facing == "west" ? -.pi/2 : 0
            mesh.transform(from:first,origin:turn.position,by:turn)
        } else if name == "iron_bars" {
            let material = try assets.texture("textures/blocks/iron_bars")
            func bar(_ size: SCNVector3, _ centre: SCNVector3, _ faces: Int) {
                let x = centre.x-size.x/2, z = centre.z-size.z/2
                let uv = [CGRect(x:x,y:1,width:size.x,height:-1),CGRect(x:1-z-size.z,y:1,width:size.z,height:-1),
                          CGRect(x:1-x-size.x,y:1,width:size.x,height:-1),CGRect(x:z,y:1,width:size.z,height:-1),
                          CGRect(x:x,y:1-z,width:size.x,height:-size.z),CGRect(x:x,y:1-z,width:size.x,height:-size.z)]
                mesh.cube(size,at:.init(p.x+centre.x,p.y+centre.y,p.z+centre.z),material:material,faces:faces,textureUV:uv)
            }
            bar(.init(0.125,1,0),.init(0.5,0.5,0.5),1)
            bar(.init(0,1,0.125),.init(0.5,0.5,0.5),2)
            bar(.init(0.125,1,0.125),.init(0.5,0.5,0.5),48)
            for (edge,dx,dz) in [("north",0,-1),("south",0,1),("west",-1,0),("east",1,0)] where states[edge] == "true" {
                bar(dx == 0 ? .init(0,1,0.5) : .init(0.5,1,0),.init(0.5+Double(dx)*0.25,0.5,0.5+Double(dz)*0.25),dx == 0 ? 2 : 1)
                bar(dx == 0 ? .init(0.125,1,0.4375) : .init(0.4375,1,0.125),.init(0.5+Double(dx)*0.28125,0.5,0.5+Double(dz)*0.28125),48)
            }
        } else if name == "brewing_stand" {
            let stand = try assets.texture("textures/blocks/brewing_stand"), base = try assets.texture("textures/blocks/brewing_stand_base")
            var uv = Array(repeating:CGRect(x:7.0/16,y:1,width:2.0/16,height:-14.0/16),count:6)
            uv[4] = CGRect(x:7.0/16,y:9.0/16,width:2.0/16,height:-2.0/16); uv[5] = uv[4]
            mesh.cube(.init(0.125,0.875,0.125),at:.init(p.x+0.5,p.y+0.4375,p.z+0.5),material:stand,textureUV:uv)
            for (x,z) in [(9.0,5.0),(1,1),(1,9)] {
                var foot = Array(repeating:CGRect(x:x/16,y:1,width:6.0/16,height:-2.0/16),count:6)
                foot[1] = CGRect(x:z/16,y:1,width:6.0/16,height:-2.0/16); foot[3] = foot[1]
                foot[4] = CGRect(x:x/16,y:(z+6)/16,width:6.0/16,height:-6.0/16); foot[5] = foot[4]
                mesh.cube(.init(0.375,0.125,0.375),at:.init(p.x+(x+3)/16,p.y+0.0625,p.z+(z+3)/16),material:base,textureUV:foot)
            }
            for slot in 0..<3 {
                let first = mesh.vertices.count, filled = states["has_bottle_\(slot)"] == "true"
                let uv = Array(repeating:slot == 0 ? CGRect(x:0.5,y:1,width:filled ? -0.5 : 0.5,height:-1)
                    : CGRect(x:filled ? 0 : 1,y:1,width:filled ? 0.5 : -0.5,height:-1),count:6)
                mesh.cube(.init(0.5,1,0),at:.init(p.x+(slot == 0 ? 0.75 : 3.59/16),p.y+0.5,p.z+0.5),material:stand,faces:1,textureUV:uv)
                let turn = SCNNode(); turn.position = .init(p.x+0.5,p.y,p.z+0.5)
                turn.eulerAngles.y = slot == 1 ? -.pi/4 : slot == 2 ? .pi/4 : 0
                mesh.transform(from:first,origin:turn.position,by:turn)
            }
        } else if banner {
            let wall = name.contains("wall_banner"), material = try assets.banner(name,data:data)
            let support = try assets.texture("textures/entity/banner/banner_base")
            let base = wall ? -23.0/48 : 0.5, z = wall ? 1.0/16 : 0.5
            var cloth = Array(repeating:CGRect(x:0,y:41.0/64,width:1.0/64,height:-40.0/64),count:6)
            cloth[0] = CGRect(x:1.0/64,y:41.0/64,width:20.0/64,height:-40.0/64)
            cloth[2] = CGRect(x:22.0/64,y:41.0/64,width:20.0/64,height:-40.0/64)
            mesh.cube(.init(20.0/24,40.0/24,1.0/24),at:.init(p.x+0.5,p.y+base+12.0/24,p.z+z+1.5/24),material:material,textureUV:cloth)
            var bar = Array(repeating:CGRect(x:2.0/64,y:46.0/64,width:20.0/64,height:-2.0/64),count:6)
            bar[4] = CGRect(x:2.0/64,y:44.0/64,width:20.0/64,height:-2.0/64); bar[5] = bar[4]
            mesh.cube(.init(20.0/24,2.0/24,2.0/24),at:.init(p.x+0.5,p.y+base+31.0/24,p.z+z),material:support,textureUV:bar)
            if !wall {
                let pole = Array(repeating:CGRect(x:46.0/64,y:44.0/64,width:2.0/64,height:-42.0/64),count:6)
                mesh.cube(.init(2.0/24,42.0/24,2.0/24),at:.init(p.x+0.5,p.y+0.875,p.z+0.5),material:support,textureUV:pole)
            }
            let turn = SCNNode(); turn.position = .init(p.x+0.5,p.y,p.z+0.5)
            if wall {
                turn.eulerAngles.y = states["facing"] == "north" ? .pi : states["facing"] == "east" ? .pi/2 : states["facing"] == "west" ? -.pi/2 : 0
            } else { turn.eulerAngles.y = -Double(Int(states["rotation"] ?? "0") ?? 0) * .pi/8 }
            mesh.transform(from:first,origin:turn.position,by:turn)
        } else if panel {
            let materials = try assets.tiles(name,states:states)
            var uv = Array(repeating:CGRect(x:0,y:1,width:1,height:-1),count:6)
            if name.hasSuffix("_door") {
                let right = states["hinge"] == "right"
                uv[0] = CGRect(x:right ? 1 : 0,y:1,width:right ? -1 : 1,height:-1)
                uv[2] = CGRect(x:right ? 0 : 1,y:1,width:right ? 1 : -1,height:-1)
                uv[1] = CGRect(x:0,y:1,width:0.1875,height:-1); uv[3] = uv[1]
                uv[4] = CGRect(x:0,y:1,width:1,height:-0.1875); uv[5] = uv[4]
            }
            let trapdoor = name.hasSuffix("trapdoor"), vertical = !trapdoor || states["open"] == "true"
            mesh.cube(vertical ? .init(1,1,name == "ladder" ? 0 : 0.1875) : .init(1,0.1875,1),
                at:.init(p.x+0.5,p.y+(vertical ? 0.5 : states["half"] == "top" ? 0.90625 : 0.09375),p.z+(vertical ? name == "ladder" ? 0.9375 : 0.90625 : 0.5)),
                material:materials[0],faces:name == "ladder" ? 1 : 63,textureUV:uv,faceMaterials:materials)
        } else if crop {
            let material = try assets.tiles(name,states:states)[0]
            let uv = Array(repeating:CGRect(x:0,y:1,width:1,height:-1),count:6)
            for offset in [0.25,0.75] {
                mesh.cube(.init(1,1,0),at:.init(p.x+0.5,p.y+0.4375,p.z+offset),material:material,faces:1,textureUV:uv)
                mesh.cube(.init(0,1,1),at:.init(p.x+offset,p.y+0.4375,p.z+0.5),material:material,faces:2,textureUV:uv)
            }
        } else if name == "bell" {
            let gold = try assets.texture("textures/entity/bell/bell")
            func bell(_ width: Double, _ height: Double, _ y: Double, _ v: Double) {
                let d = width
                let uv = [CGRect(x:d+width+d,y:v+d,width:width,height:height),CGRect(x:0,y:v+d,width:d,height:height),
                          CGRect(x:d,y:v+d,width:width,height:height),CGRect(x:d+width,y:v+d,width:d,height:height),
                          CGRect(x:d,y:v,width:width,height:d),CGRect(x:d+width,y:v,width:width,height:d)]
                    .map { CGRect(x:$0.minX/32,y:$0.maxY/32,width:$0.width/32,height:-$0.height/32) }
                mesh.cube(.init(width/16,height/16,width/16),at:.init(p.x+0.5,p.y+y/16,p.z+0.5),material:gold,textureUV:uv)
            }
            bell(6,7,6.5,0)
            bell(8,2,2,13)
            let wood = try assets.tiles("oak_planks")[0], stone = try assets.tiles("stone")[0]
            mesh.cube(.init(0.125,0.125,0.125),at:.init(p.x+0.5,p.y+0.6875,p.z+0.5),material:wood)
            if states["attachment"] == "ceiling" {
                mesh.cube(.init(0.125,0.3125,0.125),at:.init(p.x+0.5,p.y+0.84375,p.z+0.5),material:wood)
            } else if states["attachment"]?.contains("wall") == true {
                mesh.cube(.init(0.125,0.125,0.5),at:.init(p.x+0.5,p.y+0.75,p.z+0.75),material:wood)
            } else {
                for x in [0.125,0.875] { mesh.cube(.init(0.25,0.75,0.25),at:.init(p.x+x,p.y+0.375,p.z+0.5),material:stone) }
                mesh.cube(.init(1,0.125,0.25),at:.init(p.x+0.5,p.y+0.8125,p.z+0.5),material:wood)
            }
        } else {
            let material = try assets.texture("textures/blocks/"+name)
            let hanging = states["hanging"] == "true" ? 0.25 : 0.0
            var uv = Array(repeating:CGRect(x:0,y:9.0/16,width:6.0/16,height:-7.0/16),count:6)
            uv[4] = CGRect(x:0,y:15.0/16,width:6.0/16,height:-6.0/16); uv[5] = uv[4]
            mesh.cube(.init(0.375,0.4375,0.375),at:.init(p.x+0.5,p.y+hanging+0.21875,p.z+0.5),material:material,textureUV:uv)
            let cap = Array(repeating:CGRect(x:1.0/16,y:2.0/16,width:4.0/16,height:-2.0/16),count:6)
            mesh.cube(.init(0.25,0.125,0.25),at:.init(p.x+0.5,p.y+hanging+0.5,p.z+0.5),material:material,textureUV:cap)
            for x in [-0.0625,0.0625] { mesh.cube(.init(0.0625,0.1875,0.0625),at:.init(p.x+0.5+x,p.y+hanging+0.65625,p.z+0.5),material:material,textureUV:cap) }
        }
        if name == "bell" || panel {
            let transform = SCNNode(); transform.position = .init(p.x+0.5,p.y,p.z+0.5)
            let facing = states["facing"] ?? "north"
            transform.eulerAngles.y = facing == "east" ? -.pi/2 : facing == "south" ? .pi : facing == "west" ? .pi/2 : 0
            mesh.transform(from:first,origin:transform.position,by:transform)
            if name.hasSuffix("_door") && states["open"] == "true" {
                let right = states["hinge"] == "right", swing = SCNNode()
                swing.position = transform.convertPosition(.init(right ? 0.40625 : -0.40625,0,0.40625),to:nil)
                swing.eulerAngles.y = right ? -.pi/2 : .pi/2
                mesh.transform(from:first,origin:swing.position,by:swing)
            }
        }
        return true
    }

    static func template(_ name: String, assets: Assets, cutaway: Bool = false) throws -> SCNNode {
        let source = try assets.template(name)
        guard let size = source["size"] as? [Int], size.count == 3, size.allSatisfy({ $0 > 0 && $0 <= 128 }),
              let originalPalette = source["palette"] as? [[String: Any]], originalPalette.count < 4096,
              let list = source["blocks"] as? [[String: Any]], list.count <= 250_000 else { throw AssetError.model }
        var palette = originalPalette
        var pathState: Int?
        if list.contains(where: {
            guard let state = $0["state"] as? Int, originalPalette.indices.contains(state),
                  originalPalette[state]["Name"] as? String == "minecraft:jigsaw" else { return false }
            return ($0["nbt"] as? [String:Any])?["final_state"] as? String == "minecraft:grass_path"
        }) {
            pathState = palette.firstIndex { $0["Name"] as? String == "minecraft:grass_path" }
            if pathState == nil {
                guard palette.count < 4095 else { throw AssetError.model }
                pathState = palette.count; palette.append(["Name":"minecraft:grass_path"])
            }
        }
        let names = palette.map { ($0["Name"] as? String ?? "").replacingOccurrences(of:"minecraft:",with:"") }
        func hidden(_ name: String) -> Bool { ["air","cave_air","void_air","jigsaw","structure_block","structure_void"].contains(name) }
        func partial(_ name: String) -> Bool {
            ["stairs","slab","door","pane","fence","wall","torch","bed","plate","flower","glass","leaves","water","lava","carpet","trapdoor","rail","rod","candle","lantern","bars","banner","bell","brewing","wheat","carrots","potatoes","beetroots","grass","fern","sapling","mushroom","vine","ladder","composter","chest"].contains { name.contains($0) }
        }
        let visible = names.map { !hidden($0) }, opaque = names.map { !partial($0) }
        func key(_ p: [Int]) -> Int { p[0]+size[0]*(p[2]+size[2]*p[1]) }
        var blocks: [Int: Int] = [:], positions = Set<Int>()
        for block in list {
            guard let position = block["pos"] as? [Int], position.count == 3,
                  (0..<3).allSatisfy({ (0..<size[$0]).contains(position[$0]) }),
                  let original = block["state"] as? Int, originalPalette.indices.contains(original),
                  positions.insert(key(position)).inserted else { throw AssetError.model }
            let state = names[original] == "jigsaw" && (block["nbt"] as? [String:Any])?["final_state"] as? String == "minecraft:grass_path" ? pathState! : original
            if visible[state], !(cutaway && position[1] > 1 && (position[1] >= size[1]-2 || position[2] >= size[2]-5 || position[0] >= size[0]-4)) { blocks[key(position)] = state }
        }
        var mesh = Voxels(), liquid = Voxels(), surfaces: [Int: [SCNMaterial]] = [:]
        var fluids: [String:[SCNMaterial]] = [:], doors: [Door] = []
        var sites: [SCNNode] = [], beds = Set<Int>()
        func lookup(_ p: [Int]) -> Int? {
            (0..<3).allSatisfy { (0..<size[$0]).contains(p[$0]) } ? blocks[key(p)] : nil
        }
        func direction(_ facing: String?) -> (Int,Int) {
            facing == "east" ? (1,0) : facing == "west" ? (-1,0) : facing == "south" ? (0,1) : (0,-1)
        }
        func standing(_ cell: [Int]) -> SCNVector3? {
            func free(_ p: [Int]) -> Bool {
                guard let state = lookup(p) else { return true }
                let name = names[state]
                return name.hasSuffix("_door") && name != "iron_door" || ["torch","carpet","flower","grass","rail","wheat","carrots","potatoes","beetroots"].contains(where:name.contains)
            }
            for y in [cell[1],cell[1]-1,cell[1]+1,cell[1]-2] where y>=0 && y<size[1] {
                guard free([cell[0],y,cell[2]]), free([cell[0],y+1,cell[2]]) else { continue }
                if let floor = lookup([cell[0],y-1,cell[2]]), opaque[floor] || names[floor].hasSuffix("_stairs") || names[floor].hasSuffix("_slab") {
                    let carpet = lookup([cell[0],y,cell[2]]).map { names[$0].contains("carpet") } ?? false
                    let name = names[floor], states = palette[floor]["Properties"] as? [String:String] ?? [:]
                    let inset = ["farmland","grass_path","dirt_path"].contains(name) ? 0.0625 : name.hasSuffix("_slab") && states["type"] == "bottom" ? 0.5 : 0
                    return .init(Double(cell[0])+0.5,Double(y)-inset+(carpet ? 0.0625 : 0),Double(cell[2])+0.5)
                }
            }
            return nil
        }
        func site(_ kind: Site.Kind, _ block: String, at point: SCNVector3, facing: (Int,Int), cells: [[Int]]) -> SCNNode {
            let node = SCNNode(); node.name = "site-"+kind.rawValue+":"+block; node.position = point; node.categoryBitMask = 0
            node.eulerAngles.y = atan2(Double(facing.0),Double(facing.1))
            var added = Set<Int>()
            for cell in cells where added.insert(key(cell)).inserted {
                guard let p = standing(cell) else { continue }
                let stand = SCNNode(); stand.name = "stand"; stand.categoryBitMask = 0
                stand.position = node.convertPosition(p,from:nil); node.addChildNode(stand)
            }
            sites.append(node)
            return node
        }
        let fullUV = Array(repeating:CGRect(x:0,y:1,width:1,height:-1),count:6)
        for block in list {
            let p = block["pos"] as! [Int]
            guard let state = blocks[key(p)] else { continue }
            let name = names[state]
            let properties = palette[state]["Properties"] as? [String: String] ?? [:]
            let facing = direction(properties["facing"])
            if name.hasSuffix("_bed") {
                guard beds.insert(key(p)).inserted else { continue }
                let head = properties["part"] == "head", sign = head ? -1 : 1
                let mate = [p[0]+facing.0*sign,p[1],p[2]+facing.1*sign]
                var cells = [p]
                if let other = lookup(mate), names[other] == name { cells.append(mate); beds.insert(key(mate)) }
                let foot = head && cells.count == 2 ? mate : p
                let centre = SCNVector3(cells.reduce(0) { $0+Double($1[0])+0.5 }/Double(cells.count),Double(p[1])+0.5625,
                    cells.reduce(0) { $0+Double($1[2])+0.5 }/Double(cells.count))
                let neighbours = cells.flatMap { cell in [(1,0),(-1,0),(0,1),(0,-1)].map { [cell[0]+$0.0,cell[1],cell[2]+$0.1] } }
                let marker = site(.bed,name,at:centre,facing:facing,cells:[[foot[0]-facing.0,foot[1],foot[2]-facing.1]]+neighbours)
                var shape = Voxels()
                for cell in cells {
                    let index = lookup(cell)!, states = palette[index]["Properties"] as? [String:String] ?? [:]
                    try fixture(name,states:states,at:.init(Double(cell[0]),Double(cell[1]),Double(cell[2])),assets:assets,mesh:&shape)
                }
                shape.vertices = shape.vertices.map { marker.convertPosition($0,from:nil) }
                shape.normals = shape.normals.map { marker.convertVector($0,from:nil) }
                marker.addChildNode(shape.node("bed-shape"))
                continue
            }
            if workstations[name] != nil || name == "bell" {
                let offsets = [(1,0),(-1,0),(0,1),(0,-1)]+(name == "bell" ? [] : [(2,0),(-2,0),(0,2),(0,-2),(1,1),(1,-1),(-1,1),(-1,-1)])
                let neighbours = offsets.map { [p[0]+$0.0,p[1],p[2]+$0.1] }
                _ = site(name == "bell" ? .gather : .work,name,at:.init(Double(p[0])+0.5,Double(p[1]),Double(p[2])+0.5),facing:facing,cells:neighbours)
            }
            let trapdoor = name.hasSuffix("trapdoor")
            if (name.hasSuffix("_door") || trapdoor) && name != "iron_door" && name != "iron_trapdoor" {
                if !trapdoor && properties["half"] == "upper",
                   let below = blocks[key([p[0],p[1]-1,p[2]])], names[below] == name { continue }
                if !trapdoor {
                    _ = site(.entrance,name,at:.init(Double(p[0])+0.5,Double(p[1]),Double(p[2])+0.5),facing:facing,
                        cells:[p,[p[0]-facing.0,p[1],p[2]-facing.1],[p[0]+facing.0,p[1],p[2]+facing.1]])
                }
                var panel = Voxels(), closed = properties
                closed["open"] = "false"
                try fixture(name,states:closed,at:.init(Double(p[0]),Double(p[1]),Double(p[2])),assets:assets,mesh:&panel)
                if !trapdoor, p[1]+1<size[1], let above = blocks[key([p[0],p[1]+1,p[2]])], names[above] == name {
                    var upper = palette[above]["Properties"] as? [String:String] ?? [:]; upper["open"] = "false"
                    try fixture(name,states:upper,at:.init(Double(p[0]),Double(p[1]+1),Double(p[2])),assets:assets,mesh:&panel)
                }
                let hinge = SCNNode(); hinge.position = .init(Double(p[0])+0.5,Double(p[1]),Double(p[2])+0.5)
                let facing = properties["facing"] ?? "north", top = properties["half"] == "top", right = properties["hinge"] == "right"
                hinge.eulerAngles.y = facing == "east" ? -.pi/2 : facing == "south" ? .pi : facing == "west" ? .pi/2 : 0
                let pivot = hinge.convertPosition(.init(trapdoor ? 0 : right ? 0.40625 : -0.40625,trapdoor ? top ? 0.90625 : 0.09375 : 0,0.40625),to:nil)
                panel.vertices = panel.vertices.map { .init($0.x-pivot.x,$0.y-pivot.y,$0.z-pivot.z) }
                let door = Door(); door.geometry = panel.node("panel").geometry
                door.name = trapdoor ? "trapdoor" : "door"; door.categoryBitMask = 2; door.position = pivot
                door.swing = trapdoor ? top ? -.pi/2 : .pi/2 : right ? -.pi/2 : .pi/2
                if trapdoor { door.axis = hinge.convertVector(.init(1,0,0),to:nil) }
                doors.append(door)
                continue
            }
            var resolved = properties
            if name == "iron_bars" {
                // Structure templates acquire their bar connections after neighbouring blocks are placed
                for (edge,dx,dz) in [("north",0,-1),("south",0,1),("west",-1,0),("east",1,0)] {
                    if let other = lookup([p[0]+dx,p[1],p[2]+dz]), opaque[other] || names[other] == name { resolved[edge] = "true" }
                }
            }
            if try fixture(name,states:resolved,data:block["nbt"] as? [String:Any] ?? [:],at:.init(Double(p[0]),Double(p[1]),Double(p[2])),assets:assets,mesh:&mesh) { continue }
            var faces = 63
            if opaque[state] || name == "glass" || name == "tinted_glass" || name.contains("stained_glass") && !name.contains("pane") {
                for (face,d) in [[0,0,1],[1,0,0],[0,0,-1],[-1,0,0],[0,1,0],[0,-1,0]].enumerated() {
                    let neighbour = [p[0]+d[0],p[1]+d[1],p[2]+d[2]]
                    if (0..<3).allSatisfy({ (0..<size[$0]).contains(neighbour[$0]) }),
                       let index = blocks[key(neighbour)], opaque[index] || names[index] == name && (palette[index]["Properties"] as? [String:String] ?? [:]) == properties { faces &= ~(1 << face) }
                }
            }
            guard faces != 0 else { continue }
            let materials: [SCNMaterial]
            if let found = surfaces[state] { materials = found }
            else {
                if name == "water" || name == "lava" {
                    if fluids[name] == nil {
                        let still = try Landscape.flow(assets:assets,lava:name == "lava",biome:.meadow)
                        let path = "textures/blocks/"+(name == "lava" ? "lava_flow" : "water_flow_grey")
                        let flow = still.copy() as! SCNMaterial
                        flow.name = path
                        flow.diffuse.contents = try assets.texture(path,tint:name == "water" ? assets.water(.meadow).colour : nil,animated:true).diffuse.contents
                        if flow.emission.contents != nil { flow.emission.contents = flow.diffuse.contents }
                        fluids[name] = [flow,flow,flow,flow,still,still]
                    }
                    var tiles = fluids[name]!
                    if properties["level"] != "0" { tiles[4] = tiles[0] }
                    materials = tiles
                } else { materials = try assets.tiles(name,states:properties) }
                surfaces[state] = materials
            }
            func cube(_ dimensions: SCNVector3, _ centre: SCNVector3, mask: Int = 63, sprite: Bool = false) {
                mesh.cube(dimensions,at:.init(Double(p[0])+centre.x,Double(p[1])+centre.y,Double(p[2])+centre.z),
                    material:materials[0],faces:mask,textureUV:sprite ? fullUV : nil,faceMaterials:materials)
            }
            if name == "water" || name == "lava" {
                var mask = 63
                for (face,d) in [[0,0,1],[1,0,0],[0,0,-1],[-1,0,0],[0,1,0],[0,-1,0]].enumerated() {
                    if let other = lookup([p[0]+d[0],p[1]+d[1],p[2]+d[2]]), names[other] == name || opaque[other] { mask &= ~(1 << face) }
                }
                func height(_ x: Int, _ z: Int) -> Double {
                    guard let other = lookup([x,p[1],z]) else { return 0 }
                    guard names[other] == name else { return opaque[other] ? -1 : 0 }
                    if let above = lookup([x,p[1]+1,z]), names[above] == name { return 1 }
                    let properties = palette[other]["Properties"] as? [String:String] ?? [:]
                    let level = Int(properties["level"] ?? "0") ?? 0
                    return Double(8-(level&7))/9
                }
                func corner(_ x: Int, _ z: Int) -> Double {
                    var sum = 0.0, weight = 0.0
                    for dx in [0,x] { for dz in [0,z] {
                        let h = height(p[0]+dx,p[2]+dz)
                        if h == 1 { return 1 }
                        if h >= 0 { let w = h>=0.8 ? 10.0 : 1; sum += h*w; weight += w }
                    } }
                    return weight>0 ? sum/weight : 0
                }
                let first = liquid.vertices.count
                liquid.cube(.init(1,1,1),at:.init(Double(p[0])+0.5,Double(p[1])+0.5,Double(p[2])+0.5),
                    material:materials[0],faces:mask,faceMaterials:materials)
                for index in first..<liquid.vertices.count where liquid.vertices[index].y>Double(p[1])+0.5 {
                    let point = liquid.vertices[index]
                    liquid.vertices[index].y = Double(p[1])+corner(point.x>Double(p[0])+0.5 ? 1 : -1,point.z>Double(p[2])+0.5 ? 1 : -1)
                }
            } else if name == "farmland" || name == "grass_path" || name == "dirt_path" {
                cube(.init(1,0.9375,1),.init(0.5,0.46875,0.5))
            } else if name.hasSuffix("_stairs") {
                let upper = properties["half"] == "top"
                cube(.init(1,0.5,1),.init(0.5,upper ? 0.75 : 0.25,0.5))
                let facing = properties["facing"] ?? "north", inner = properties["shape"]?.hasPrefix("inner") == true
                let outer = properties["shape"]?.hasPrefix("outer") == true
                let left = properties["shape"]?.hasSuffix("left") == true
                let first = mesh.vertices.count
                cube(.init(outer ? 0.5 : 1,0.5,0.5),.init(outer ? (left ? 0.25 : 0.75) : 0.5,upper ? 0.25 : 0.75,0.25))
                if inner { cube(.init(0.5,0.5,0.5),.init(left ? 0.25 : 0.75,upper ? 0.25 : 0.75,0.75)) }
                let transform = SCNNode()
                transform.position = .init(Double(p[0])+0.5,Double(p[1])+0.5,Double(p[2])+0.5)
                transform.eulerAngles.y = facing == "east" ? -.pi/2 : facing == "south" ? .pi : facing == "west" ? .pi/2 : 0
                mesh.transform(from:first,origin:transform.position,by:transform)
            } else if name.hasSuffix("_slab") {
                cube(.init(1,properties["type"] == "double" ? 1 : 0.5,1),.init(0.5,properties["type"] == "top" ? 0.75 : 0.25,0.5))
            } else if name.contains("glass_pane") {
                // Arms share block-space UVs and meet the two-pixel post without overlap
                let directions = [("south",[0,0,1],0),("east",[1,0,0],1),("north",[0,0,-1],2),("west",[-1,0,0],3)]
                func connected(_ origin: [Int], _ edge: String, _ d: [Int]) -> Bool {
                    guard let current = lookup(origin) else { return false }
                    let states = palette[current]["Properties"] as? [String:String] ?? [:]
                    if states[edge] == "true" || states["minecraft:connection_"+edge] == "true" { return true }
                    guard let other = lookup([origin[0]+d[0],origin[1],origin[2]+d[2]]) else { return false }
                    return opaque[other] || names[other].contains("glass") || names[other] == "iron_bars"
                }
                let connections = directions.filter { connected(p,$0.0,$0.1) }
                func pane(_ dimensions: SCNVector3, _ centre: SCNVector3, mask: Int, arm: (String,[Int])? = nil) {
                    let x = centre.x-dimensions.x/2, z = centre.z-dimensions.z/2
                    var mask = mask
                    for (dy,face) in [(1,4),(-1,5)] {
                        let neighbour = [p[0],p[1]+dy,p[2]]
                        if let other = lookup(neighbour), names[other].contains("glass_pane"), arm.map({ connected(neighbour,$0.0,$0.1) }) ?? true { mask &= ~(1 << face) }
                    }
                    let uv: [CGRect] = [.init(x:x,y:1,width:dimensions.x,height:-1),.init(x:1-z-dimensions.z,y:1,width:dimensions.z,height:-1),
                        .init(x:1-x-dimensions.x,y:1,width:dimensions.x,height:-1),.init(x:z,y:1,width:dimensions.z,height:-1),
                        .init(x:x,y:1-z,width:dimensions.x,height:-dimensions.z),.init(x:x,y:1-z,width:dimensions.x,height:-dimensions.z)]
                    let broad = dimensions.x>0.125 ? [0,2] : dimensions.z>0.125 ? [1,3] : [0,1,2,3]
                    let palette = (0..<6).map { broad.contains($0) ? materials[0] : materials[1] }
                    mesh.cube(dimensions,at:.init(Double(p[0])+centre.x,Double(p[1])+centre.y,Double(p[2])+centre.z),material:materials[0],faces:mask,textureUV:uv,faceMaterials:palette)
                }
                let post = connections.reduce(63) { $0 & ~(1 << $1.2) }
                pane(.init(0.125,1,0.125),.init(0.5,0.5,0.5),mask:post)
                for (edge,d,face) in connections {
                    let neighbour = lookup([p[0]+d[0],p[1],p[2]+d[2]])
                    let mask = 63 & ~(1 << ((face+2)%4)) & (neighbour == nil ? 63 : ~(1 << face))
                    pane(d[0] == 0 ? .init(0.125,1,0.4375) : .init(0.4375,1,0.125),
                         .init(0.5+Double(d[0])*0.28125,0.5,0.5+Double(d[2])*0.28125),mask:mask,arm:(edge,d))
                }
            } else if name.hasSuffix("_fence") {
                cube(.init(0.25,1,0.25),.init(0.5,0.5,0.5))
                for y in [0.4,0.8] {
                    for (direction,x,z) in [("north",0.0,-0.25),("south",0.0,0.25),("east",0.25,0.0),("west",-0.25,0.0)] where properties[direction] == "true" {
                        cube(x == 0 ? .init(0.125,0.125,0.5) : .init(0.5,0.125,0.125),.init(0.5+x,y,0.5+z))
                    }
                }
            } else if ["flower","sapling","grass","fern","mushroom"].contains(where:name.contains) {
                cube(.init(1,1,0),.init(0.5,0.5,0.5),mask:1,sprite:true)
                cube(.init(0,1,1),.init(0.5,0.5,0.5),mask:2,sprite:true)
            } else if name.contains("carpet") || name == "redstone_wire" {
                cube(.init(1,0.0625,1),.init(0.5,0.03125,0.5))
            } else if name == "end_rod" || name == "chain" {
                cube(.init(0.125,1,0.125),.init(0.5,0.5,0.5))
            } else if name.contains("candle") || name.contains("lantern") {
                cube(.init(0.375,0.625,0.375),.init(0.5,0.3125,0.5),sprite:true)
            } else if name.hasSuffix("_wall") {
                cube(.init(0.5,1,0.5),.init(0.5,0.5,0.5))
            } else if name.hasSuffix("_pressure_plate") { cube(.init(0.875,0.0625,0.875),.init(0.5,0.03,0.5)) }
            else { cube(.init(1,1,1),.init(0.5,0.5,0.5),mask:faces) }
        }
        // A resident must clear each stair edge before lowering its full collision box
        for block in list {
            let p = block["pos"] as! [Int], index = block["state"] as! Int, name = names[index]
            guard name.hasSuffix("_stairs"), blocks[key(p)] != nil else { continue }
            let states = palette[index]["Properties"] as? [String:String] ?? [:]
            guard states["half"] != "top", states["shape"] == nil || states["shape"] == "straight",
                  standing([p[0],p[1]+1,p[2]]) != nil,
                  sites.contains(where:{ node in
                      guard node.name?.hasPrefix("site-work:") == true || node.name?.hasPrefix("site-bed:") == true else { return false }
                      return hypot(node.position.x-Double(p[0])-0.5,node.position.z-Double(p[2])-0.5)<4
                          && (0...2.6).contains(node.position.y-Double(p[1]))
                  }) else { continue }
            let direction = direction(states["facing"]), marker = SCNNode()
            marker.name = "site-path:"+name; marker.position = .init(Double(p[0])+0.5,Double(p[1]),Double(p[2])+0.5); marker.categoryBitMask = 0
            for (distance,y) in [(-0.82,0.0),(-0.82,0.5),(-0.32,0.5),(-0.32,1.0),(0.82,1.0)] {
                let stand = SCNNode(); stand.name = "stand"; stand.categoryBitMask = 0
                stand.position = .init(Double(direction.0)*distance,y,Double(direction.1)*distance)
                marker.addChildNode(stand)
            }
            sites.append(marker)
        }
        let geometry = mesh.node("template-"+name), root = Footprint()
        root.geometry = geometry.geometry; root.name = geometry.name; root.categoryBitMask = geometry.categoryBitMask
        let foundations = list.compactMap { block -> SCNVector3? in
            let p = block["pos"] as! [Int]
            guard p[1] == 0, let state = blocks[key(p)] else { return nil }
            let name = names[state]
            guard opaque[state] || ["farmland","grass_path","dirt_path"].contains(name) || name.hasSuffix("_slab") || name.hasSuffix("_stairs") else { return nil }
            return .init(Double(p[0])+0.5,1,Double(p[2])+0.5)
        }
        root.points = foundations
        for door in doors { root.addChildNode(door) }
        for site in sites { root.addChildNode(site) }
        if !liquid.vertices.isEmpty {
            let node = liquid.node("template-fluids"); node.categoryBitMask = 1; root.addChildNode(node)
            for materials in fluids.values { for index in [0,4] { Landscape.animate(node,material:materials[index]) } }
        }
        root.position = .init(-Double(size[0]/2)-0.5,0,-Double(size[2]/2)-0.5)
        return root
    }
}

extension Structures {
    private static let workstations = ["blast_furnace":"armorer","smoker":"butcher","cartography_table":"cartographer",
        "brewing_stand":"cleric","composter":"farmer","barrel":"fisherman","fletching_table":"fletcher",
        "cauldron":"leatherworker","water_cauldron":"leatherworker","lectern":"librarian","stonecutter":"mason",
        "loom":"shepherd","smithing_table":"toolsmith","grindstone":"weaponsmith"]

    struct Site {
        enum Kind: String { case bed, work, gather, entrance, path }
        let kind: Kind
        let block: String
        let point: SCNVector3
        let facing: Double
        let standing: [SCNVector3]
        fileprivate let marker: SCNNode
        var profession: String? { workstations[block] }

        // Only the destination bed becomes passable while validating the lying transfer
        func clearance<T>(_ check: () throws -> T) rethrows -> T {
            guard let shape = marker.childNode(withName:"bed-shape",recursively:false) else { return try check() }
            let mask = shape.categoryBitMask
            guard mask != 0 else { return try check() }
            shape.categoryBitMask = 0; SCNTransaction.flush()
            defer { shape.categoryBitMask = mask; SCNTransaction.flush() }
            return try check()
        }
    }

    static func sites(in root: SCNNode) -> [Site] {
        var sites: [Site] = []
        root.enumerateChildNodes { node,_ in
            guard let name = node.name, name.hasPrefix("site-") else { return }
            let parts = name.dropFirst(5).split(separator:":",maxSplits:1)
            guard parts.count == 2, let kind = Site.Kind(rawValue:String(parts[0])) else { return }
            let forward = node.convertVector(.init(0,0,1),to:root)
            sites.append(Site(kind:kind,block:String(parts[1]),point:node.convertPosition(.init(0,0,0),to:root),
                facing:atan2(forward.x,forward.z),standing:node.childNodes.filter { $0.name == "stand" }
                    .map { $0.convertPosition(.init(0,0,0),to:root) },marker:node))
        }
        return sites
    }

    // The caller supplies grounded street and doorway points; this never invents a path through a building
    static func route(from start: SCNVector3, to end: SCNVector3, via waypoints: [SCNVector3], in root: SCNNode) -> [SCNVector3]? {
        func finite(_ p: SCNVector3) -> Bool { [p.x,p.y,p.z].allSatisfy { $0.isFinite && abs($0)<=4096 } }
        guard waypoints.count<=256, [start,end].allSatisfy(finite), waypoints.allSatisfy(finite) else { return nil }
        func distance(_ a: SCNVector3, _ b: SCNVector3) -> Double { hypot(hypot(a.x-b.x,a.z-b.z),a.y-b.y) }
        return Door.clearance(root) {
            func clear(_ a: SCNVector3, _ b: SCNVector3) -> Bool { Collision.clear(root,from:a,to:b,radius:0.3,height:1.9) }
            if clear(start,end) { return [start,end] }
            var points = [start]
            for point in waypoints where !points.contains(where:{ distance($0,point)<0.01 }) { points.append(point) }
            points.append(end)
            let last = points.count-1
            var cost = Array(repeating:Double.infinity,count:points.count), parent = Array(repeating:-1,count:points.count)
            var pending: Set<Int> = [0], closed = Set<Int>()
            cost[0] = 0
            while let current = pending.min(by:{ cost[$0]+distance(points[$0],end)<cost[$1]+distance(points[$1],end) }) {
                pending.remove(current)
                if current == last {
                    var path = [end], index = current
                    while parent[index]>=0 { index = parent[index]; path.append(points[index]) }
                    guard path.count<=64 else { return nil }
                    return path.reversed()
                }
                closed.insert(current)
                for next in points.indices where next != current && !closed.contains(next) {
                    let length = distance(points[current],points[next])
                    guard length<=12 || next == last else { continue }
                    let score = cost[current]+length
                    guard score<cost[next], clear(points[current],points[next]) else { continue }
                    cost[next] = score; parent[next] = current; pending.insert(next)
                }
            }
            return nil
        }
    }
}
