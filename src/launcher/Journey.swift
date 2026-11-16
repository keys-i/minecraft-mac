import AppKit
import SceneKit

enum Passage: String, Sendable {
    case mine, stronghold, rift
    var duration: Int { self == .mine ? 26 : self == .stronghold ? 28 : 16 }
    var title: String {
        switch self {
        case .mine: return "Nether portal mineshaft"
        case .stronghold: return "Stronghold portal"
        case .rift: return "Rift valley"
        }
    }

    // Cover the authored corridors without generating a second floor through them
    func height(_ x: Int, _ z: Int) -> Double {
        let terrain = Terrain(biome:self == .rift ? .valley : .forest)
        if self == .rift { return abs(x)<3 ? 2 : terrain.height(Double(x),Double(z)) }
        let mine = self == .mine
        let width = z < (mine ? -22 : -9) ? (mine ? 8 : 7) : mine ? 4 : 5
        if abs(x)<width && z<=(mine ? 42 : 100) { return -100 }
        if mine && abs(x)<16 && abs(z+16)<4 { return -100 }
        if !mine && abs(x)<14 && abs(z)<7 { return -100 }
        let level = max(mine ? 13 : 45,terrain.height(Double(x),Double(z))+9)
        let edge = min(1,max(0,(Double(abs(x))-55)/40))
        return floor(level*(1-edge)+4*edge)
    }

    // Distance-weighted progress avoids stopping at every camera keyframe
    func pose(at time: Double) -> (eye: SCNVector3, aim: SCNVector3) {
        let route: [SCNVector3]
        switch self {
        case .mine:
            route = [.init(0,14.62,42),.init(0,1.62,-12),.init(0,1.62,-33.92)]
        case .stronghold:
            route = [.init(0,46.62,100),.init(0,1.62,6),.init(0,1.62,-11.5),
                     .init(0,4.62,-17.5),.init(0,4.62,-18.25),.init(0,4.9325,-18.75),
                     .init(0,4.9325,-19.4),.init(0,4.85,-19.7)]
        case .rift:
            route = [.init(0,3.62,30),.init(0,3.62,-13.9)]
        }
        let lengths = zip(route,route.dropFirst()).map { a,b in
            sqrt(pow(b.x-a.x,2)+pow(b.y-a.y,2)+pow(b.z-a.z,2))
        }
        let length = lengths.reduce(0,+), travel = Double(duration)-(self == .mine ? 4 : 0)
        let distance = min(1,max(0,time/travel))*length
        func point(_ distance: Double) -> SCNVector3 {
            var remaining = distance
            for index in lengths.indices {
                if remaining <= lengths[index] {
                    let t = remaining/lengths[index], a = route[index], b = route[index+1]
                    return .init(a.x+(b.x-a.x)*t,a.y+(b.y-a.y)*t,a.z+(b.z-a.z)*t)
                }
                remaining -= lengths[index]
            }
            let last = route.last!
            return .init(last.x,last.y,last.z-remaining)
        }
        func approach(_ point: SCNVector3) -> SCNVector3 {
            var point = point
            if self == .mine, point.z > -12 { point.y = min(13,max(0,(point.z+12)/4))+1.62 }
            if self == .stronghold, point.z > 6 { point.y = min(45,max(0,(point.z-6)/2))+1.62 }
            return point
        }
        return (approach(point(distance)),approach(point(distance+5)))
    }

}

struct Journey {
    private(set) var world: World = .overworld
    private(set) var biome = 0
    private(set) var passage: Passage?
    private(set) var elapsed = 0

    var title: String { passage?.title ?? world.biomes[biome].rawValue }

    mutating func select(_ destination: World, animated: Bool) {
        guard destination != world || passage != nil else { return }
        world = destination; biome = 0; elapsed = 0
        passage = animated ? (destination == .nether ? .mine : destination == .end ? .stronghold : destination == .sift ? .rift : nil) : nil
    }

    mutating func area(_ index: Int) {
        biome = world.index(index); passage = nil; elapsed = 0
    }

    mutating func skip() { passage = nil; elapsed = 0 }

    mutating func travel(_ step: Int) {
        let count = world.biomes.count
        area(((biome+step)%count+count)%count)
    }

    mutating func tick(rotate: Bool) {
        guard passage != nil || rotate else { return }
        elapsed += 1
        if let passage {
            if elapsed >= passage.duration { skip() }
        } else if elapsed >= 18 {
            if biome+1 < world.biomes.count { area(biome+1) }
            else {
                let next = (World.allCases.firstIndex(of:world)!+1)%World.allCases.count
                select(World.allCases[next],animated:true)
            }
        }
    }
}

extension Passage {
    func scene(assets: Assets) throws -> SCNScene {
        let scene = SCNScene(), factory = Mobs(assets:assets)
        var residents: [(SCNNode,SCNNode,Species)] = []
        func resident(_ species: Species, at point: SCNVector3) throws {
            let actor = SCNNode(), model = try factory.make(species)
            actor.name = "passage-resident-\(residents.count)"; actor.position = point
            model.position.y = -model.boundingBox.min.y
            actor.addChildNode(model); scene.rootNode.addChildNode(actor)
            residents.append((actor,model,species))
        }
        scene.background.contents = Landscape.colour(self == .mine ? 0x9EC9DF : self == .rift ? 0x829EA8 : 0x263039)
        scene.fogColor = Landscape.colour(self == .rift ? 0x829EA8 : 0x263039)
        scene.fogStartDistance = 45; scene.fogEndDistance = 120
        let camera = SCNNode(); camera.name = "camera"; camera.camera = SCNCamera()
        camera.camera?.fieldOfView = 60; camera.camera?.zNear = 0.05; camera.camera?.zFar = 180
        camera.camera?.wantsHDR = true; camera.camera?.wantsExposureAdaptation = false
        camera.camera?.bloomIntensity = 0.15; camera.camera?.bloomThreshold = 1.2
        camera.camera?.screenSpaceAmbientOcclusionIntensity = 0.7
        scene.rootNode.addChildNode(camera)
        let start = pose(at:0); camera.position = start.eye; camera.look(at:start.aim,up:.init(0,1,0),localFront:.init(0,0,-1))
        camera.runAction(.customAction(duration:Double(duration)) { node,elapsed in
            let pose = self.pose(at:Double(elapsed)); node.position = pose.eye; node.look(at:node.parent!.convertPosition(pose.aim,to:nil),up:.init(0,1,0),localFront:.init(0,0,-1))
        },forKey:"passage")
        let fill = SCNNode(); fill.light = SCNLight(); fill.light?.type = .ambient
        fill.light?.intensity = self == .rift ? 500 : 380; scene.rootNode.addChildNode(fill)
        var mesh = Voxels()
        func cube(_ size: SCNVector3, _ at: SCNVector3, _ name: String) throws {
            let tiles = try assets.tiles(name); mesh.cube(size,at:at,material:tiles[0],faceMaterials:tiles)
        }
        func sprite(_ name: String, _ at: SCNVector3, size: Double = 1) throws {
            let material = try assets.texture("textures/blocks/"+name)
            let uv = Array(repeating:CGRect(x:0,y:1,width:1,height:-1),count:6)
            let first = mesh.vertices.count
            mesh.cube(.init(size,size,0),at:at,material:material,faces:1,textureUV:uv)
            mesh.cube(.init(0,size,size),at:at,material:material,faces:2,textureUV:uv)
            let turn = SCNNode(); turn.position = at; turn.eulerAngles.y = .pi/4
            mesh.transform(from:first,origin:at,by:turn)
        }
        func lamp(_ at: SCNVector3, soul: Bool = false, facing: String = "west") throws {
            let light = SCNNode(); light.name = "passage-light"; light.light = SCNLight(); light.light?.type = .omni
            light.light?.color = Landscape.colour(soul ? 0x86D7DF : 0xF2BD7D)
            light.light?.intensity = 230; light.light?.attenuationEndDistance = 12
            light.position = at; scene.rootNode.addChildNode(light)
            try Structures.fixture(soul ? "soul_wall_torch" : "wall_torch",states:["facing":facing],at:.init(at.x-0.5,at.y-0.5,at.z-0.5),assets:assets,mesh:&mesh)
        }
        if self == .rift {
            let terrain = Terrain(biome:.valley)
            scene.rootNode.addChildNode(try terrain.node(assets:assets,height:height))
            for index in 0..<28 {
                let x = Terrain.random(index,7,seed:4)*64-32, z = Terrain.random(index,9,seed:5)*90-45
                if abs(x)>5 {
                    let shard = SCNNode(); var crystals = Voxels(); let tile = try assets.tiles("amethyst_block")
                    crystals.cube(.init(2,5,2),at:.init(0,0,0),material:tile[0],faceMaterials:tile)
                    shard.addChildNode(crystals.node("rift-shard")); shard.position = .init(x,10+Double(index%5),z)
                    shard.runAction(.repeatForever(.sequence([.moveBy(x:0,y:0.6,z:0,duration:5),.moveBy(x:0,y:-0.6,z:0,duration:5)])))
                    scene.rootNode.addChildNode(shard)
                }
            }
            for index in 0..<180 {
                let x = (Terrain.random(index,19)*60-30).rounded(), z = (Terrain.random(index,23)*80-30).rounded()
                guard abs(x)>4 else { continue }
                let y = terrain.height(x,z)
                try sprite(index%5 == 0 ? "coral_fan_purple" : "nether_sprouts",.init(x,y+0.5,z))
                if index%13 == 0 {
                    try cube(.init(2,1,2),.init(x,y+0.5,z),"calcite")
                    try cube(.init(1,1,1),.init(x,y+1.5,z),"amethyst_block")
                }
            }
            try Structures.portal(scene.rootNode,at:.init(0,2,-14),assets:assets,sift:true)
            let ruin = try Structures.template("ruined_portal/portal_3",assets:assets); ruin.position = .init(-13,2,-20); scene.rootNode.addChildNode(ruin)
            for index in 0..<6 {
                let x = Double(index%2 == 0 ? -5 : 6), z = Double(index)*6-21
                try resident(index%2 == 0 ? .allay : .illager,at:.init(x,index%2 == 0 ? 7 : terrain.height(x,z),z))
            }
        } else {
            let mine = self == .mine
            let terrain = Terrain(biome:.forest)
            let approach = try terrain.node(assets:assets,x:-96..<96,z:-128..<128,height:height)
            scene.rootNode.addChildNode(approach)
            for z in (mine ? 35 : 95)...(mine ? 42 : 100) {
                let floor = min(mine ? 13 : 45,max(0,ceil(mine ? (Double(z)+12)/4 : (Double(z)-6)/2)))
                try cube(.init(7,1,1),.init(0,floor-0.5,Double(z)),"stone")
            }
            for index in 0..<65 {
                let x = (Terrain.random(index,4,seed:9)*116-58).rounded()
                let z = (Terrain.random(index,12,seed:6)*94).rounded()
                guard abs(x)>8 else { continue }
                let y = max(mine ? 13 : 45,terrain.height(x,z)+9), tall = Double(4+index%3)
                try cube(.init(1,tall,1),.init(x,y+tall/2,z),"oak_log")
                try cube(.init(5,2,5),.init(x,y+tall-1,z),"oak_leaves")
                try cube(.init(3,1,3),.init(x,y+tall+0.5,z),"oak_leaves")
            }
            for z in stride(from:mine ? 34.0 : 94,through:mine ? -34 : -30,by:-1) {
                let index = Int((mine ? 34 : 94)-z)
                let floor = mine ? max(0,ceil((z+12)/4)) : max(0,ceil((z-6)/2))
                let chamber = mine ? z < -22 : z < -9
                let radius = chamber ? (mine ? 6.0 : 5) : mine ? 2 : 3
                let stone = mine ? (z < -10 ? "deepslate" : "stone") : z>8 ? "stone" : index%7 == 0 ? "mossy_stone_bricks" : index%5 == 0 ? "cracked_stone_bricks" : "stone_bricks"
                let bridge = !mine && (-6...6).contains(z)
                if !bridge { try cube(.init(radius*2+1,1,1),.init(0,floor-0.5,z),stone) }
                for side in [-1.0,1] {
                    let opening = mine ? (-19 ... -13).contains(z) : (-4 ... 5).contains(z)
                    if !opening {
                        if !mine && chamber && index%3 == 0 {
                            try cube(.init(1,2.5,1),.init(side*(radius+1),floor+1.25,z),stone)
                            try cube(.init(1,3.5,1),.init(side*(radius+1),floor+6.25,z),stone)
                            try cube(.init(1,8,3),.init(side*(radius+4),floor+4,z),stone)
                        } else if mine {
                            for level in 0..<(chamber ? 8 : 5) {
                                let vein = Terrain.noise(z,Double(level),scale:2.5,seed:24)>0.35
                                let ore = z < -20 ? "diamond_ore" : z < -10 ? "gold_ore" : z < 10 ? "iron_ore" : "coal_ore"
                                let block = vein ? (z < -10 ? "deepslate_" : "")+ore : stone
                                try cube(.init(1,1,1),.init(side*(radius+1),floor+Double(level)+0.5,z),block)
                            }
                        } else { try cube(.init(1,chamber ? 8 : 5,1),.init(side*(radius+1),floor+(chamber ? 4 : 2.5),z),stone) }
                    }
                }
                if z < (mine ? 22 : 86) && !(mine && (-19 ... -13).contains(z)) {
                    let ceiling = bridge ? 7 : floor+(chamber ? 8 : 5)
                    let roof = max(mine ? 13 : 45,ceiling+1)
                    try cube(.init(bridge ? 7 : radius*2+3,roof-ceiling,1),.init(0,(ceiling+roof)/2,z),stone)
                }
                if mine {
                    if index%5 == 0 && !chamber && !(-19 ... -13).contains(z) {
                        for side in [-1.0,1] { try cube(.init(0.375,3,0.375),.init(side*1.5,floor+1.5,z),"oak_fence") }
                        try cube(.init(3.375,1,1),.init(0,floor+3.5,z),"oak_planks")
                        if index%10 == 0 { try sprite("web",.init(1.5,floor+2.8,z),size:1.5) }
                    }
                    if z > -29 {
                        let rail = try assets.texture("textures/blocks/rail_normal"), first = mesh.vertices.count
                        mesh.cube(.init(1,0,1),at:.init(0,floor+0.02,z),material:rail,faces:16)
                        let rise = max(0,ceil((z+13)/4))-floor
                        for vertex in first..<mesh.vertices.count {
                            if mesh.vertices[vertex].z > z { mesh.vertices[vertex].y += rise }
                            mesh.normals[vertex] = .init(0,1/sqrt(1+rise*rise),-rise/sqrt(1+rise*rise))
                        }
                    }
                } else if chamber && index%3 == 0 {
                    for side in [-1.0,1] {
                        for level in 0..<2 {
                            try Structures.fixture("iron_bars",states:["north":"true","south":"true"],
                                at:.init(side*6-0.5,2.5+Double(level),z-0.5),assets:assets,mesh:&mesh)
                        }
                    }
                }
                if index%9 == 0 && !(mine && (-19 ... -13).contains(z)) && !bridge { try lamp(.init(radius,floor+2.3,z)) }
            }
            if mine {
                for x in -14...14 {
                    if abs(x)>2 { try cube(.init(1,1,5),.init(Double(x),-0.5,-16),"oak_planks") }
                    try cube(.init(1,8,7),.init(Double(x),9,-16),"stone")
                    if abs(x)>3 { for side in [-1.0,1] { try cube(.init(1,5,1),.init(Double(x),2.5,side*3-16),"stone") } }
                    if abs(x)>2 {
                        let rail = try assets.texture("textures/blocks/rail_normal"), first = mesh.vertices.count
                        mesh.cube(.init(1,0,1),at:.init(Double(x),0.02,-16),material:rail,faces:16)
                        let turn = SCNNode(); turn.position = .init(Double(x),0.02,-16); turn.eulerAngles.y = .pi/2
                        mesh.transform(from:first,origin:turn.position,by:turn)
                    }
                    if x%4 == 0 && abs(x)>3 {
                        for side in [-1.0,1] { try cube(.init(0.375,3,0.375),.init(Double(x),1.5,side*2-16),"oak_fence") }
                        try cube(.init(1,1,4.375),.init(Double(x),3.5,-16),"oak_planks")
                    }
                }
                for side in [-1.0,1] { try cube(.init(1,14,7),.init(side*15,6,-16),"stone") }
                for (x,z) in [(-2.0,-13.0),(1,-19)] { try cube(.init(1,1,1),.init(x,0.5,z),"barrel") }
                let cart = try factory.actor("minecart"); cart.position = .init(5,0.02-cart.boundingBox.min.y,-16); cart.eulerAngles.y = .pi/2; scene.rootNode.addChildNode(cart)
                try sprite("web",.init(13,3.5,-14),size:1.5)
                try sprite("web",.init(-13,3.5,-18),size:1.5)
                for side in [-1.0,1] { try cube(.init(4,8,1),.init(side*4,4,-34),"deepslate") }
                try cube(.init(4,4,1),.init(0,6,-34),"deepslate")
                try Structures.portal(scene.rootNode,at:.init(0,-1,-34),assets:assets)
                try lamp(.init(-6,3,-32),facing:"east")
                for index in 0..<5 {
                    try resident(.bat,at:.init(Double(index%3-1),3.1,-Double(index)*5-8))
                }
            } else {
                try cube(.init(13,9,2),.init(0,4,-31),"stone_bricks")
                try Landscape.liquid(scene,assets:assets,lava:true,at:.init(0,0.15,-21),size:.init(width:3,height:3))
                try cube(.init(7,1,13),.init(0,-0.5,0),"stone_bricks")
                for side in [-1.0,1] {
                    try cube(.init(9,1,11),.init(side*8,-0.5,0),"oak_planks")
                    try cube(.init(1,7,13),.init(side*13,3.5,0),"stone_bricks")
                    try cube(.init(10,38,13),.init(side*8.5,26,0),"stone_bricks")
                    for z in -5...5 where z%3 != 0 { for level in [0.0,1,2,4,5] { try cube(.init(1,1,1),.init(side*10,level+0.5,Double(z)),"bookshelf") } }
                    for z in [-6.0,6] {
                        try cube(.init(10,7,1),.init(side*8.5,3.5,z),"oak_planks")
                        try sprite("web",.init(side*9,6,z-0.1),size:2)
                    }
                    try lamp(.init(side*12,3,0),facing:side>0 ? "west" : "east")
                    try Landscape.liquid(scene,assets:assets,lava:true,at:.init(side*4,0.02,-21),size:.init(width:1,height:1))
                }
                for step in 0..<6 {
                    let height = Double(step+1)*0.5
                    try cube(.init(3,height,1),.init(0,height/2,-12-Double(step)),"stone_bricks")
                }
                try cube(.init(5,3,1),.init(0,1.5,-18),"stone_bricks")
                for side in [-1.0,1] {
                    try cube(.init(7,1,1),.init(0,2,-21+side*3),"stone_bricks")
                    try cube(.init(1,1,5),.init(side*3,2,-21),"stone_bricks")
                }
                try Structures.endPortal(scene.rootNode,at:.init(0,2.5,-21),assets:assets)
                try cube(.init(1,1,1),.init(0,0.5,-10),"mob_spawner")
                for index in 0..<3 {
                    try resident(.silverfish,at:.init(Double(index-1),0,-8-Double(index)))
                }
            }
        }
        scene.rootNode.addChildNode(mesh.node("passage-masonry"))
        let renderer = SCNRenderer(device:nil,options:nil); renderer.scene = scene
        guard renderer.prepare(scene,shouldAbortBlock:nil) else { throw AssetError.model }
        let area: Biome = self == .mine ? .mine : self == .stronghold ? .stronghold : .valley
        for (index,resident) in residents.enumerated() {
            let (actor,model,species) = resident, y = actor.position.y
            try factory.wander(actor,model:model,species:species,area:area,seed:1700+index,root:scene.rootNode) { x,z in
                .init(x,species.flying || species == .strider ? y : Terrain(biome:area).height(x,z),z)
            }
        }
        return scene
    }
}
