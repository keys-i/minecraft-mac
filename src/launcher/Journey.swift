import AppKit
import SceneKit

enum Passage: String, Sendable {
    case mine, stronghold, rift
    var duration: Int { self == .mine ? 22 : self == .stronghold ? 20 : 16 }
    var title: String {
        switch self {
        case .mine: return "Into the mineshaft · Nether portal"
        case .stronghold: return "Back in the Overworld · Stronghold portal"
        case .rift: return "Through the rift · Sift interpretation"
        }
    }

    // A shared path drives both live animation and deterministic render checks
    func pose(at time: Double) -> (eye: SCNVector3, aim: SCNVector3) {
        let eyes: [SCNVector3], aims: [SCNVector3]
        switch self {
        case .mine:
            eyes = [.init(0,15,42),.init(0,12.62,30),.init(0,7.62,10),.init(0,3.62,-6),.init(0,1.62,-23),.init(0,1.62,-33.8),.init(0,2.2,-36),.init(0,5,-44)]
            aims = [.init(0,12,31),.init(0,6,5),.init(0,2,-10),.init(0,2,-27),.init(0,2.4,-34),.init(0,2.3,-35),.init(0,8,-64),.init(0,11,-75)]
        case .stronghold:
            eyes = [.init(5,16,36),.init(0,10.62,25),.init(0,3.62,6),.init(0,1.62,-4),.init(0,2.6,-11),.init(0,5,-17),.init(0,4.8,-21),.init(0,3.36,-21.5)]
            aims = [.init(0,9,21),.init(0,4,5),.init(-2,3,-5),.init(0,3,-17),.init(0,3.2,-21),.init(0,3.2,-21),.init(0,2,-21.5),.init(0,-2,-21.6)]
        case .rift:
            eyes = [.init(3,12,30),.init(0,9,19),.init(0,6,5),.init(0,5,-8),.init(0,4.8,-13.86),.init(0,4.8,-16)]
            aims = [.init(0,6,-12),.init(0,5,-14),.init(0,4.8,-14),.init(0,4.8,-15),.init(0,4.8,-16),.init(0,5,-22)]
        }
        let segments = eyes.count-1
        let t = min(Double(segments),max(0,time/Double(duration)*Double(segments))), index = min(segments-1,Int(t))
        let fraction = t-Double(index), eased = fraction*fraction*(3-2*fraction)
        func blend(_ a: SCNVector3, _ b: SCNVector3) -> SCNVector3 {
            .init(a.x+(b.x-a.x)*eased,a.y+(b.y-a.y)*eased,a.z+(b.z-a.z)*eased)
        }
        var eye = blend(eyes[index],eyes[index+1])
        if self == .mine, eye.z > -32, eye.z < 31 {
            // Follow the rail slope below the original-height support beams
            eye.y = max(0,(eye.z+12)/4)+1.62
        } else if self == .stronghold, eye.z > 2, eye.z < 27 {
            eye.y = max(0,(eye.z-2)/2.5)+1.62
        }
        return (eye,blend(aims[index],aims[index+1]))
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
        scene.background.contents = Landscape.colour(self == .mine ? 0x9EC9DF : self == .rift ? 0x829EA8 : 0x263039)
        scene.fogColor = Landscape.colour(self == .rift ? 0x829EA8 : 0x263039)
        scene.fogStartDistance = 45; scene.fogEndDistance = 120
        let camera = SCNNode(); camera.name = "camera"; camera.camera = SCNCamera()
        camera.camera?.fieldOfView = 60; camera.camera?.zNear = 0.05; camera.camera?.zFar = 180
        camera.camera?.wantsHDR = true; camera.camera?.wantsExposureAdaptation = false
        camera.camera?.bloomIntensity = 0.15; camera.camera?.bloomThreshold = 1.2
        camera.camera?.screenSpaceAmbientOcclusionIntensity = 0.7
        scene.rootNode.addChildNode(camera)
        let start = pose(at:0); camera.position = start.eye; camera.look(at:start.aim)
        camera.runAction(.customAction(duration:Double(duration)) { node,elapsed in
            let pose = self.pose(at:Double(elapsed)); node.position = pose.eye; node.look(at:pose.aim)
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
            mesh.cube(.init(size,size,0),at:at,material:material,faces:1,textureUV:uv)
            mesh.cube(.init(0,size,size),at:at,material:material,faces:2,textureUV:uv)
        }
        func lamp(_ at: SCNVector3, soul: Bool = false) throws {
            let light = SCNNode(); light.name = "passage-light"; light.light = SCNLight(); light.light?.type = .omni
            light.light?.color = Landscape.colour(soul ? 0x86D7DF : 0xF2BD7D)
            light.light?.intensity = 230; light.light?.attenuationEndDistance = 12
            light.position = at; scene.rootNode.addChildNode(light)
            try sprite(soul ? "soul_torch" : "torch_on",at)
        }
        if self == .rift {
            for index in 0..<70 {
                let x = Double(index%7-3)*5, z = Double(index/7)*6-28
                let height = Double(index%4)+abs(x)*0.25
                try cube(.init(5,3+height,6),.init(x,height/2,z),index%3 == 0 ? "moss_block" : "pink_terracotta")
                if index%5 == 0 {
                    let shard = SCNNode(); var crystals = Voxels(); let tile = try assets.tiles("amethyst_block")
                    crystals.cube(.init(2,5,2),at:.init(0,0,0),material:tile[0],faceMaterials:tile)
                    shard.addChildNode(crystals.node("rift-shard")); shard.position = .init(x,10+Double(index%5),z)
                    shard.runAction(.repeatForever(.sequence([.moveBy(x:0,y:0.6,z:0,duration:5),.moveBy(x:0,y:-0.6,z:0,duration:5)])))
                    scene.rootNode.addChildNode(shard)
                }
            }
            for z in -24...34 { try cube(.init(4,1,1),.init(0,1.5,Double(z)),"moss_block") }
            try Structures.portal(scene.rootNode,at:.init(0,2,-14),assets:assets,sift:true)
            let ruin = try Structures.template("ruined_portal/portal_3",assets:assets); ruin.position = .init(-13,2,-20); scene.rootNode.addChildNode(ruin)
            for index in 0..<6 {
                let mob = try factory.make(index%2 == 0 ? .allay : .illager)
                mob.position = .init(Double(index%2 == 0 ? -5 : 6),Double(index%2 == 0 ? 7 : 3),Double(index)*6-21)
                if index%2 == 0 { mob.runAction(.repeatForever(.sequence([.moveBy(x:0.4,y:0.4,z:0,duration:3),.moveBy(x:-0.4,y:-0.4,z:0,duration:3)]))) }
                scene.rootNode.addChildNode(mob)
            }
        } else {
            let mine = self == .mine
            for side in [-1.0,1] {
                try cube(.init(24,14,20),.init(side*15,6,26),"stone")
                try cube(.init(24,1,20),.init(side*15,13.5,26),"grass_block")
            }
            for z in stride(from:34.0,through:mine ? -34 : -30,by:-1) {
                let index = Int(34-z)
                let floor = mine ? max(0,ceil((z+12)/4)) : max(0,ceil((z-2)/2.5))
                let chamber = mine ? z < -22 : z < -9
                let radius = chamber ? (mine ? 6.0 : 7) : 3.0
                let stone = mine ? (z < -10 ? "deepslate" : "stone") : index%7 == 0 ? "mossy_stone_bricks" : index%5 == 0 ? "cracked_stone_bricks" : "stone_bricks"
                try cube(.init(radius*2+1,1,1),.init(0,floor-0.5,z),stone)
                for side in [-1.0,1] {
                    let opening = mine ? (-15 ... -10).contains(z) : (-4 ... 5).contains(z)
                    if !opening { try cube(.init(2,chamber ? 8 : 5,1),.init(side*(radius+1),floor+(chamber ? 4 : 2.5),z),stone) }
                    if mine && index%5 == 0 { try cube(.init(0.02,1,1),.init(side*(radius-0.01),floor+1.5,z),["coal_ore","iron_ore","copper_ore","gold_ore","diamond_ore"][index/5%5]) }
                }
                if z < 22 { try cube(.init(radius*2+4,1,1),.init(0,floor+(chamber ? 8.5 : 5.5),z),stone) }
                if mine {
                    if index%5 == 0 && !chamber {
                        for side in [-1.0,1] { try cube(.init(0.375,3,0.375),.init(side*2,floor+1.5,z),"oak_fence") }
                        try cube(.init(5,1,1),.init(0,floor+3.5,z),"oak_planks")
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
                        try cube(.init(1,6,1),.init(side*6,3,z),"chiseled_stone_bricks")
                        for bar in -1...1 { try cube(.init(0.125,2,0.125),.init(side*5.9,3.5,z+Double(bar)*0.4),"iron_bars") }
                    }
                }
                if index%9 == 0 { try lamp(.init(radius-0.4,floor+2.3,z)) }
            }
            if mine {
                for x in -14...14 {
                    try cube(.init(1,1,5),.init(Double(x),0,-12),"oak_planks")
                    try cube(.init(1,1,7),.init(Double(x),5,-12),"stone")
                    for side in [-1.0,1] { try cube(.init(1,5,1),.init(Double(x),2,side*3-12),"stone") }
                    if x%4 == 0 { for side in [-1.0,1] { try cube(.init(0.4,3,0.4),.init(Double(x),2,side*2-12),"oak_fence") } }
                }
                for (x,z) in [(-2.0,-13.0),(2,-19)] { try cube(.init(1,1,1),.init(x,0.5,z),"barrel") }
                let cart = try factory.actor("minecart"); cart.position = .init(0,1,-9); scene.rootNode.addChildNode(cart)
                try cube(.init(84,16,68),.init(0,26,-14),"stone")
                try cube(.init(84,1,68),.init(0,34.5,-14),"grass_block")
                try cube(.init(70,18,12),.init(0,3,41),"stone")
                try cube(.init(70,1,12),.init(0,12.5,41),"grass_block")
                for side in [-1.0,1] { try cube(.init(4,8,1),.init(side*4,4,-34),"deepslate") }
                try cube(.init(4,3,1),.init(0,6.5,-34),"deepslate")
                try Structures.portal(scene.rootNode,at:.init(0,0,-34),assets:assets)
                try lamp(.init(-3,3,-32),soul:true)
                try Landscape.liquid(scene,assets:assets,lava:true,at:.init(0,-1,-71),size:.init(width:90,height:72))
                try cube(.init(7,1,40),.init(0,-0.5,-54),"netherrack")
                try cube(.init(92,4,80),.init(0,35,-76),"netherrack")
                try cube(.init(92,36,3),.init(0,16,-110),"netherrack")
                for side in [-1.0,1] {
                    try cube(.init(20,28,75),.init(side*37,13,-75),"netherrack")
                    try Landscape.liquid(scene,assets:assets,lava:true,at:.init(side*22,15,-65),size:.init(width:2,height:32),vertical:true)
                }
                let fortress = try Structures.build(.wastes,x:0,y:2,assets:assets); fortress.position.z -= 62
                scene.rootNode.addChildNode(fortress)
                for index in 0..<4 {
                    let actor = try factory.make(index == 0 ? .ghast : .strider)
                    actor.position = .init(Double(index*9-15),index == 0 ? 16 : 0,-Double(index)*8-60)
                    scene.rootNode.addChildNode(actor)
                }
                for index in 0..<5 {
                    let bat = try factory.make(.bat); bat.position = .init(Double(index%3-1),3.1,-Double(index)*5-8)
                    bat.runAction(.repeatForever(.sequence([.moveBy(x:0.3,y:0.2,z:-1,duration:3),.moveBy(x:-0.3,y:-0.2,z:1,duration:3)])))
                    scene.rootNode.addChildNode(bat)
                }
            } else {
                for side in [-1.0,1] {
                    try cube(.init(8,1,13),.init(side*8,-0.5,0),"oak_planks")
                    try cube(.init(1,7,13),.init(side*12,3,0),"stone_bricks")
                    try cube(.init(8,1,13),.init(side*8,7,0),"stone_bricks")
                    for z in -5...5 where z%3 != 0 { for level in [0.0,1,2,4,5] { try cube(.init(1,1,1),.init(side*10,level+0.5,Double(z)),"bookshelf") } }
                    for z in [-5.0,5] {
                        try cube(.init(8,7,1),.init(side*8,3,z),"oak_planks")
                        try sprite("web",.init(side*9,6,z-0.1),size:2)
                    }
                    try lamp(.init(side*7,3,0))
                    try cube(.init(1,1,1),.init(side*4,-0.1,-21),"lava")
                }
                for step in 0..<5 { try cube(.init(5,0.5,1),.init(0,Double(step)*0.5+0.25,-12-Double(step)),"stone_bricks") }
                for side in [-1.0,1] {
                    try cube(.init(7,1,1),.init(0,2,-21+side*3),"stone_bricks")
                    try cube(.init(1,1,5),.init(side*3,2,-21),"stone_bricks")
                }
                try Structures.endPortal(scene.rootNode,at:.init(0,2.5,-21),assets:assets)
                try cube(.init(1,1,1),.init(0,0.5,-10),"mob_spawner")
                for index in 0..<3 {
                    let silverfish = try factory.make(.silverfish); silverfish.position = .init(Double(index-1),0,-8-Double(index))
                    scene.rootNode.addChildNode(silverfish)
                }
            }
        }
        scene.rootNode.addChildNode(mesh.node("passage-masonry"))
        return scene
    }
}
