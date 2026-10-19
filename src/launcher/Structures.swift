import AppKit
import SceneKit

enum Structures {
    static func build(_ biome: Biome, x: Double, y: Double, assets: Assets) throws -> SCNNode {
        let root = SCNNode(); root.name = "landmark-\(biome)"; root.position = .init(x,y,-18)
        var mesh = Voxels()
        func cube(_ size: SCNVector3, _ p: SCNVector3, _ block: String) throws {
            let tiles = try assets.tiles(block)
            mesh.cube(size,at:p,material:tiles[0],faceMaterials:tiles)
        }
        func place(_ name: String, _ p: SCNVector3 = .init(0,0,0)) throws {
            let wrapper = SCNNode(); wrapper.position = p
            wrapper.addChildNode(try template(name,assets:assets)); root.addChildNode(wrapper)
        }
        switch biome {
        case .meadow:
            try place("village/plains/houses/plains_medium_house_1",.init(-5,0,-4))
            try place("village/plains/houses/plains_small_house_1",.init(8,0,2))
        case .forest, .cherry:
            try place("village/plains/houses/plains_small_house_1")
        case .snow: try place("igloo/igloo_top_no_trapdoor")
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
            for side in [-1.0,1] { try cube(.init(1,3,1),.init(side*3.5,10.5,0),"mossy_cobblestone") }
            try cube(.init(8,1,1),.init(0,12.5,0),"cobblestone")
        case .deep: try place("ancient_city/city_center/city_center_1",.init(0,-7,0))
        case .crimson: try place("bastion/bridge/starting_pieces/entrance",.init(0,-12,-2))
        case .soul:
            try place("nether_fossils/fossil_1",.init(-3,0,1))
            try place("nether_fossils/fossil_2",.init(4,0,-6))
        case .wastes:
            for x in stride(from:-10.0,through:10,by:5) {
                for side in [-1.0,1] { try cube(.init(2,10,2),.init(x,1,side*2),"nether_bricks") }
            }
            try cube(.init(25,2,5),.init(0,6,0),"nether_bricks")
            for side in [-1.0,1] {
                try cube(.init(25,1,0.375),.init(0,7.5,side*2),"nether_brick_fence")
                for x in stride(from:-12.0,through:12,by:2) { try cube(.init(1,1,1),.init(x,8.5,side*2),"nether_bricks") }
            }
        case .central:
            for index in 0..<10 {
                let angle = Double(index)*Double.pi/5, h = Double(8+index%4*2)
                let x = sin(angle)*16, z = cos(angle)*12-5
                try cube(.init(3,h,3),.init(x,h/2,z),"obsidian")
                let crystal = try assets.actor("ender_crystal")
                crystal.position = .init(x,h+1,z); root.addChildNode(crystal)
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
            try place("endcity/ship",.init(21,8,-4))
        case .coast: try place("shipwreck/swrightsideupfronthalf",.init(0,-3,0))
        case .ruins: try place("ruined_portal/portal_3")
        case .valley, .shards, .sculk:
            try portal(root,at:.init(0,2,0),assets:assets,sift:true)
        case .mangrove, .mushroom, .pale, .basalt, .midlands, .islands, .barrens, .terraces, .grove: break
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
        let material = try assets.texture("textures/blocks/portal").copy() as! SCNMaterial
        material.lightingModel = .constant
        if sift { material.multiply.contents = NSColor.cyan }
        let plane = SCNPlane(width:2,height:3); plane.firstMaterial = material
        let surface = SCNNode(geometry:plane); surface.name = "portal-surface"; surface.position = .init(0,2.5,0)
        surface.runAction(.repeatForever(.customAction(duration:32) { node,time in
            var transform = SCNMatrix4MakeScale(1,1,1); transform.m41 = time/12; transform.m42 = time/8
            node.geometry?.firstMaterial?.diffuse.contentsTransform = transform
        }))
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
        root.addChildNode(surface)
    }
}

extension Structures {
    static func template(_ name: String, assets: Assets) throws -> SCNNode {
        let source = try assets.template(name)
        guard let size = source["size"] as? [Int], size.count == 3, size.allSatisfy({ $0 > 0 && $0 <= 128 }),
              let palette = source["palette"] as? [[String: Any]], palette.count < 4096,
              let list = source["blocks"] as? [[String: Any]], list.count <= 250_000 else { throw AssetError.model }
        let names = palette.map { ($0["Name"] as? String ?? "").replacingOccurrences(of:"minecraft:",with:"") }
        func hidden(_ name: String) -> Bool { ["air","cave_air","void_air","jigsaw","structure_block","structure_void"].contains(name) }
        func partial(_ name: String) -> Bool {
            ["stairs","slab","door","pane","fence","wall","torch","bed","plate","flower","glass","leaves","water","carpet","trapdoor","rail","rod","candle","lantern","bars"].contains { name.contains($0) }
        }
        func key(_ p: [Int]) -> Int { p[0]+size[0]*(p[2]+size[2]*p[1]) }
        var blocks: [Int: Int] = [:]
        for block in list {
            guard let position = block["pos"] as? [Int], position.count == 3,
                  (0..<3).allSatisfy({ (0..<size[$0]).contains(position[$0]) }),
                  let state = block["state"] as? Int, palette.indices.contains(state) else { throw AssetError.model }
            if !hidden(names[state]) { blocks[key(position)] = state }
        }
        var mesh = Voxels(), surfaces: [Int: [SCNMaterial]] = [:]
        let fullUV = Array(repeating:CGRect(x:0,y:1,width:1,height:-1),count:6)
        for block in list {
            let p = block["pos"] as! [Int], state = block["state"] as! Int, name = names[state]
            guard !hidden(name) else { continue }
            let properties = palette[state]["Properties"] as? [String: String] ?? [:]
            var faces = 63
            if !partial(name) {
                for (face,d) in [[0,0,1],[1,0,0],[0,0,-1],[-1,0,0],[0,1,0],[0,-1,0]].enumerated() {
                    let neighbour = [p[0]+d[0],p[1]+d[1],p[2]+d[2]]
                    if (0..<3).allSatisfy({ (0..<size[$0]).contains(neighbour[$0]) }),
                       let index = blocks[key(neighbour)], !partial(names[index]) { faces &= ~(1 << face) }
                }
            }
            guard faces != 0 else { continue }
            let materials: [SCNMaterial]
            if let found = surfaces[state] { materials = found }
            else { materials = try assets.tiles(name,states:properties); surfaces[state] = materials }
            func cube(_ dimensions: SCNVector3, _ centre: SCNVector3, mask: Int = 63, sprite: Bool = false) {
                mesh.cube(dimensions,at:.init(Double(p[0])+centre.x,Double(p[1])+centre.y,Double(p[2])+centre.z),
                    material:materials[0],faces:mask,textureUV:sprite ? fullUV : nil,faceMaterials:materials)
            }
            if name.hasSuffix("_stairs") {
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
                if properties["north"] == "true" || properties["south"] == "true" { cube(.init(0.0625,1,1),.init(0.5,0.5,0.5),sprite:true) }
                if properties["east"] == "true" || properties["west"] == "true" { cube(.init(1,1,0.0625),.init(0.5,0.5,0.5),sprite:true) }
            } else if name.hasSuffix("_fence") {
                cube(.init(0.25,1,0.25),.init(0.5,0.5,0.5))
                for y in [0.4,0.8] {
                    for (direction,x,z) in [("north",0.0,-0.25),("south",0.0,0.25),("east",0.25,0.0),("west",-0.25,0.0)] where properties[direction] == "true" {
                        cube(x == 0 ? .init(0.125,0.125,0.5) : .init(0.5,0.125,0.125),.init(0.5+x,y,0.5+z))
                    }
                }
            } else if name.contains("torch") || name.contains("flower") {
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
        root.position = .init(-Double(size[0])/2,0,-Double(size[2])/2)
        return root
    }
}
