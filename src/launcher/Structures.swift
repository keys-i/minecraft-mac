import AppKit
import SceneKit

enum Structures {
    static func build(_ biome: Biome, x: Double, y: Double, assets: Assets) throws -> SCNNode {
        let root = SCNNode(); root.name = "landmark-\(biome)"; root.position = .init(x,y,-18)
        var mesh = Voxels(), templates: [String:SCNNode] = [:]
        func cube(_ size: SCNVector3, _ p: SCNVector3, _ block: String) throws {
            let tiles = try assets.tiles(block)
            mesh.cube(size,at:p,material:tiles[0],faceMaterials:tiles)
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
            try place("village/plains/houses/plains_small_house_2",.init(-15,0,-27),turn:.pi)
            try place("village/plains/houses/plains_small_house_1",.init(17,0,-25))
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
                try cube(.init(width,1,width),.init(0,Double(tier)+1.5,-2),tier%3 == 0 ? "prismarine_bricks" : "prismarine")
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
                try cube(.init(width,1,width),.init(0,Double(tier)+10.5,-9),"prismarine_bricks")
                for side in [-1.0,1] { try cube(.init(1,1,width),.init(side*(width/2-1),Double(tier)+10.5,-9),"dark_prismarine") }
            }
            for side in [-1.0,1] { try cube(.init(2,3,2),.init(side*5,18,-9),"sea_lantern") }
        case .desert:
            for tier in 0..<10 {
                let span = Double(21-tier*2)
                if tier < 3 {
                    for side in [-1.0,1] {
                        try cube(.init(1,1,span),.init(side*(span-1)/2,Double(tier)+0.5,-4),"sandstone")
                        try cube(.init((span-3)/2,1,1),.init(side*(span+3)/4,Double(tier)+0.5,-4+(span-1)/2),"sandstone")
                    }
                    try cube(.init(span,1,1),.init(0,Double(tier)+0.5,-4-(span-1)/2),"sandstone")
                } else { try cube(.init(span,1,span),.init(0,Double(tier)+0.5,-4),"sandstone") }
            }
            for side in [-1.0,1] {
                try cube(.init(5,8,5),.init(side*8,4,5),"sandstone")
                try cube(.init(3,1,3),.init(side*8,8.5,5),"chiseled_sandstone")
                for p in [SCNVector3(side*8,4,7.51),.init(side*8,5,7.51),.init(side*8,3,7.51),.init(side*8-1,4,7.51),.init(side*8+1,4,7.51)] {
                    try cube(.init(1,1,0.02),p,"orange_terracotta")
                }
            }
        case .jungle:
            for tier in 0..<3 {
                try cube(.init(Double(12-tier*2),3,Double(15-tier*2)),.init(0,Double(tier*3)+1.5,0),tier%2 == 0 ? "mossy_cobblestone" : "cobblestone")
            }
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
                    for dx in -2...2 { for dz in -2...2 where abs(dx)==2 || abs(dz)==2 { try cube(.init(0.125,4,0.125),.init(x+Double(dx),h+2,z+Double(dz)),"iron_bars") } }
                    try cube(.init(5,0.125,5),.init(x,h+4,z),"iron_bars")
                }
            }
            try cube(.init(5,1,5),.init(0,0.5,4),"bedrock")
            try cube(.init(1,4,1),.init(0,2,4),"bedrock")
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
        case .mangrove, .mushroom, .midlands, .islands, .barrens, .terraces, .grove: break
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
    static func fixture(_ name: String, states: [String:String] = [:], at p: SCNVector3,
                        assets: Assets, mesh: inout Voxels) throws -> Bool {
        let torch = ["torch","wall_torch","soul_torch","soul_wall_torch","redstone_torch","redstone_wall_torch","copper_torch","copper_wall_torch"].contains(name)
        let crop = ["wheat","carrots","potatoes","beetroots"].contains(name)
        guard torch || crop || name == "bell" || name == "lantern" || name == "soul_lantern" else { return false }
        let first = mesh.vertices.count
        if torch {
            let path = name.contains("soul") ? "soul_torch" : name.contains("redstone") ? "redstone_torch_on" : name.contains("copper") ? "copper_torch" : "torch_on"
            let material = try assets.texture("textures/blocks/"+path)
            var uv = Array(repeating:CGRect(x:7.0/16,y:1,width:2.0/16,height:-10.0/16),count:6)
            uv[4] = CGRect(x:7.0/16,y:10.0/16,width:2.0/16,height:-2.0/16)
            uv[5] = CGRect(x:7.0/16,y:1,width:2.0/16,height:-2.0/16)
            mesh.cube(.init(0.125,0.625,0.125),at:.init(p.x+0.5,p.y+0.3125,p.z+0.5),material:material,textureUV:uv)
        } else if crop {
            let material = try assets.tiles(name,states:states)[0]
            let uv = Array(repeating:CGRect(x:0,y:1,width:1,height:-1),count:6)
            for offset in [0.25,0.75] {
                mesh.cube(.init(1,1,0),at:.init(p.x+0.5,p.y+0.4375,p.z+offset),material:material,faces:1,textureUV:uv)
                mesh.cube(.init(0,1,1),at:.init(p.x+offset,p.y+0.4375,p.z+0.5),material:material,faces:2,textureUV:uv)
            }
        } else if name == "bell" {
            let tiles = try assets.tiles("bell")
            mesh.cube(.init(0.375,0.4375,0.375),at:.init(p.x+0.5,p.y+0.46875,p.z+0.5),material:tiles[0],faceMaterials:tiles)
            mesh.cube(.init(0.5,0.125,0.5),at:.init(p.x+0.5,p.y+0.1875,p.z+0.5),material:tiles[0],faceMaterials:tiles)
            let wood = try assets.tiles("oak_planks")[0], stone = try assets.tiles("stone")[0]
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
        if name.contains("wall") || name == "bell" {
            let transform = SCNNode(); transform.position = .init(p.x+0.5,p.y,p.z+0.5)
            let facing = states["facing"] ?? "north"
            transform.eulerAngles.y = facing == "east" ? -.pi/2 : facing == "south" ? .pi : facing == "west" ? .pi/2 : 0
            let lean = SCNNode()
            if torch { lean.eulerAngles.x = -.pi/8; lean.position = .init(0,0.2,0.25) }
            transform.addChildNode(lean)
            for index in first..<mesh.vertices.count {
                let v = mesh.vertices[index]
                mesh.vertices[index] = lean.convertPosition(.init(v.x-p.x-0.5,v.y-p.y,v.z-p.z-0.5),to:nil)
                mesh.normals[index] = lean.convertVector(mesh.normals[index],to:nil)
            }
        }
        return true
    }

    static func template(_ name: String, assets: Assets, cutaway: Bool = false) throws -> SCNNode {
        let source = try assets.template(name)
        guard let size = source["size"] as? [Int], size.count == 3, size.allSatisfy({ $0 > 0 && $0 <= 128 }),
              let palette = source["palette"] as? [[String: Any]], palette.count < 4096,
              let list = source["blocks"] as? [[String: Any]], list.count <= 250_000 else { throw AssetError.model }
        let names = palette.map { ($0["Name"] as? String ?? "").replacingOccurrences(of:"minecraft:",with:"") }
        func hidden(_ name: String) -> Bool { ["air","cave_air","void_air","jigsaw","structure_block","structure_void"].contains(name) }
        func partial(_ name: String) -> Bool {
            ["stairs","slab","door","pane","fence","wall","torch","bed","plate","flower","glass","leaves","water","carpet","trapdoor","rail","rod","candle","lantern","bars","banner","bell","wheat","carrots","potatoes","beetroots","grass","fern","sapling","mushroom","vine","ladder","composter"].contains { name.contains($0) }
        }
        let visible = names.map { !hidden($0) }, opaque = names.map { !partial($0) }
        func key(_ p: [Int]) -> Int { p[0]+size[0]*(p[2]+size[2]*p[1]) }
        var blocks: [Int: Int] = [:]
        for block in list {
            guard let position = block["pos"] as? [Int], position.count == 3,
                  (0..<3).allSatisfy({ (0..<size[$0]).contains(position[$0]) }),
                  let state = block["state"] as? Int, palette.indices.contains(state) else { throw AssetError.model }
            if visible[state], !(cutaway && position[1] > 1 && (position[1] >= size[1]-2 || position[2] >= size[2]-5 || position[0] >= size[0]-4)) { blocks[key(position)] = state }
        }
        var mesh = Voxels(), surfaces: [Int: [SCNMaterial]] = [:]
        let fullUV = Array(repeating:CGRect(x:0,y:1,width:1,height:-1),count:6)
        for block in list {
            let p = block["pos"] as! [Int], state = block["state"] as! Int, name = names[state]
            guard visible[state], blocks[key(p)] != nil else { continue }
            let properties = palette[state]["Properties"] as? [String: String] ?? [:]
            if try fixture(name,states:properties,at:.init(Double(p[0]),Double(p[1]),Double(p[2])),assets:assets,mesh:&mesh) { continue }
            var faces = 63
            if opaque[state] {
                for (face,d) in [[0,0,1],[1,0,0],[0,0,-1],[-1,0,0],[0,1,0],[0,-1,0]].enumerated() {
                    let neighbour = [p[0]+d[0],p[1]+d[1],p[2]+d[2]]
                    if (0..<3).allSatisfy({ (0..<size[$0]).contains(neighbour[$0]) }),
                       let index = blocks[key(neighbour)], opaque[index] { faces &= ~(1 << face) }
                }
            }
            guard faces != 0 else { continue }
            let materials: [SCNMaterial]
            if let found = surfaces[state] { materials = found }
            else {
                materials = name == "water" ? Array(repeating:try Landscape.flow(assets:assets,lava:false,biome:.meadow),count:6) : try assets.tiles(name,states:properties)
                surfaces[state] = materials
            }
            func cube(_ dimensions: SCNVector3, _ centre: SCNVector3, mask: Int = 63, sprite: Bool = false) {
                mesh.cube(dimensions,at:.init(Double(p[0])+centre.x,Double(p[1])+centre.y,Double(p[2])+centre.z),
                    material:materials[0],faces:mask,textureUV:sprite ? fullUV : nil,faceMaterials:materials)
            }
            if name == "water" {
                var mask = 63
                for (face,d) in [[0,0,1],[1,0,0],[0,0,-1],[-1,0,0],[0,1,0],[0,-1,0]].enumerated() {
                    let neighbour = [p[0]+d[0],p[1]+d[1],p[2]+d[2]]
                    if (0..<3).allSatisfy({ (0..<size[$0]).contains(neighbour[$0]) }), let other = blocks[key(neighbour)], names[other] == "water" || opaque[other] { mask &= ~(1 << face) }
                }
                let above = [p[0],p[1]+1,p[2]]
                let covered = p[1]+1<size[1] && blocks[key(above)].map { names[$0] == "water" } == true
                let level = Int(properties["level"] ?? "0") ?? 0
                let height = covered || level>=8 ? 1.0 : Double(8-min(7,level))/9
                cube(.init(1,height,1),.init(0.5,height/2,0.5),mask:mask)
            } else if name == "farmland" || name == "grass_path" || name == "dirt_path" {
                cube(.init(1,0.9375,1),.init(0.5,0.46875,0.5))
            } else if name.contains("banner") {
                let uv = Array(repeating:CGRect(x:1.0/64,y:41.0/64,width:20.0/64,height:-40.0/64),count:6)
                mesh.cube(.init(1.25,2.5,0.02),at:.init(Double(p[0])+0.5,Double(p[1])-0.25,Double(p[2])+0.1),material:materials[0],textureUV:uv)
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
                for index in first..<mesh.vertices.count {
                    let point = mesh.vertices[index], c = transform.position
                    mesh.vertices[index] = transform.convertPosition(.init(point.x-c.x,point.y-c.y,point.z-c.z),to:nil)
                    mesh.normals[index] = transform.convertVector(mesh.normals[index],to:nil)
                }
            } else if name.hasSuffix("_slab") {
                cube(.init(1,properties["type"] == "double" ? 1 : 0.5,1),.init(0.5,properties["type"] == "top" ? 0.75 : 0.25,0.5))
            } else if name.hasSuffix("_door") {
                let axis = ["east","west"].contains(properties["facing"] ?? "")
                cube(axis ? .init(0.1875,1,1) : .init(1,1,0.1875),axis ? .init(0.09,0.5,0.5) : .init(0.5,0.5,0.09),sprite:true)
            } else if name.contains("glass_pane") || name == "iron_bars" {
                // Saved templates defer pane connections until their neighbours are placed
                cube(.init(0.125,1,0.125),.init(0.5,0.5,0.5),sprite:true)
                for (edge,d) in [("north",[0,0,-1]),("south",[0,0,1]),("west",[-1,0,0]),("east",[1,0,0])] {
                    let neighbour = [p[0]+d[0],p[1],p[2]+d[2]]
                    let inside = (0..<3).allSatisfy { (0..<size[$0]).contains(neighbour[$0]) }
                    let other = inside ? blocks[key(neighbour)] : nil
                    let connects = other.map { opaque[$0] || names[$0] == name } ?? false
                    if properties[edge] == "true" || connects {
                        cube(d[0] == 0 ? .init(0.125,1,0.5) : .init(0.5,1,0.125),
                             .init(0.5+Double(d[0])*0.25,0.5,0.5+Double(d[2])*0.25),sprite:true)
                    }
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
            } else if name.contains("trapdoor") {
                cube(.init(1,0.1875,1),.init(0.5,properties["half"] == "top" ? 0.90625 : 0.09375,0.5))
            } else if name == "end_rod" || name == "chain" {
                cube(.init(0.125,1,0.125),.init(0.5,0.5,0.5))
            } else if name.contains("candle") || name.contains("lantern") {
                cube(.init(0.375,0.625,0.375),.init(0.5,0.3125,0.5),sprite:true)
            } else if name.hasSuffix("_wall") {
                cube(.init(0.5,1,0.5),.init(0.5,0.5,0.5))
            } else if name == "ladder" {
                cube(.init(1,1,0),.init(0.5,0.5,0.06),mask:1,sprite:true)
            } else if name.hasSuffix("_bed") { cube(.init(1,0.56,1),.init(0.5,0.28,0.5)) }
            else if name.hasSuffix("_pressure_plate") { cube(.init(0.875,0.0625,0.875),.init(0.5,0.03,0.5)) }
            else { cube(.init(1,1,1),.init(0.5,0.5,0.5),mask:faces) }
        }
        let root = mesh.node("template-"+name)
        if let water = surfaces.values.first(where: { $0[0].name?.contains("water") == true })?.first { Landscape.animate(root,material:water) }
        root.position = .init(-Double(size[0])/2,0,-Double(size[2])/2)
        return root
    }
}
