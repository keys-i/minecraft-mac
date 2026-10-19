import AppKit
import SceneKit

enum Passage: String, Sendable {
    case mine, stronghold, rift
    var duration: Int { 14 }
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
            eyes = [.init(0,17,30),.init(0,9.4,14),.init(0,4.6,-3),.init(0,1.62,-24),.init(0,1.62,-27.98)]
            aims = [.init(0,8,14),.init(0,4,-3),.init(0,2.5,-28),.init(0,2.5,-29),.init(0,2.5,-30)]
        case .stronghold:
            eyes = [.init(0,3,16),.init(0,3,3),.init(0,4,-8),.init(0,5.2,-16),.init(0,1.27,-18)]
            aims = [.init(0,2,-6),.init(0,2,-13),.init(0,1,-18),.init(0,1,-18),.init(0,-2,-18.1)]
        case .rift:
            eyes = [.init(0,9,22),.init(0,7,10),.init(0,5,-2),.init(0,4.8,-10),.init(0,4.8,-13.86)]
            aims = [.init(0,5,-14),.init(0,4.8,-14),.init(0,4.8,-14),.init(0,4.8,-15),.init(0,4.8,-16)]
        }
        let t = min(4,max(0,time/Double(duration)*4)), index = min(3,Int(t))
        let fraction = t-Double(index), eased = fraction*fraction*(3-2*fraction)
        func blend(_ a: SCNVector3, _ b: SCNVector3) -> SCNVector3 {
            .init(a.x+(b.x-a.x)*eased,a.y+(b.y-a.y)*eased,a.z+(b.z-a.z)*eased)
        }
        var eye = blend(eyes[index],eyes[index+1])
        if self == .mine {
            // Stay below support beams while following the stepped rail bed
            eye.y = max(0,(eye.z+12)/4)+1.62+max(0,eye.z-18)/12*3.88
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
        let scene = SCNScene(), factory = Mobs(assets: assets)
        scene.background.contents = Landscape.colour(self == .mine ? 0x9EC9DF : self == .rift ? 0x514267 : 0x17202A)
        scene.fogColor = Landscape.colour(self == .rift ? 0x514267 : 0x17202A)
        scene.fogStartDistance = 30; scene.fogEndDistance = 75
        let camera = SCNNode(); camera.name = "camera"; camera.camera = SCNCamera()
        camera.camera?.fieldOfView = 58; camera.camera?.zNear = 0.05; camera.camera?.zFar = 120
        camera.camera?.wantsHDR = true; camera.camera?.wantsExposureAdaptation = false
        scene.rootNode.addChildNode(camera)
        let pose = pose(at: 0); camera.position = pose.eye; camera.look(at: pose.aim)
        camera.runAction(.customAction(duration: Double(duration)) { node, elapsed in
            let pose = self.pose(at: Double(elapsed))
            node.position = pose.eye; node.look(at: pose.aim)
        }, forKey: "passage")
        let fill = SCNNode(); fill.light = SCNLight(); fill.light?.type = .ambient
        fill.light?.intensity = self == .rift ? 500 : 370
        scene.rootNode.addChildNode(fill)
        var mesh = Voxels()
        func cube(_ size: SCNVector3, _ at: SCNVector3, _ block: String) throws {
            let tiles = try assets.tiles(block)
            mesh.cube(size, at: at, material: tiles[0], faceMaterials: tiles)
        }
        if self == .mine {
            for side in [-1.0,1] {
                try cube(.init(25,14,70),.init(side*15,5,-4),"stone")
                try cube(.init(25,1,70),.init(side*15,12.5,-4),"grass_block")
            }
        }
        for index in 0..<65 {
            let z = 34-Double(index)
            let floor = self == .mine ? max(0,ceil((z+12)/4)) : self == .rift ? 2 : 0
            try cube(.init(self == .rift ? 5 : self == .stronghold ? 15 : 5,1,1),.init(0,floor-0.5,z),self == .stronghold ? "stone_bricks" : self == .rift ? "purple_terracotta" : "stone")
            if self == .mine {
                for side in [-1.0,1] { try cube(.init(2,5,1),.init(side*(z < -20 ? 4.5 : 2.5),floor+2.5,z),"stone") }
                if z < 12 { try cube(.init(z < -20 ? 11 : 7,1,1),.init(0,floor+(z < -20 ? 6.5 : 4.5),z),"stone") }
                if index%4 == 0 && z >= -20 {
                    for side in [-1.0,1] { try cube(.init(0.375,2,0.375),.init(side*1.3,floor+1,z),"oak_fence") }
                    try cube(.init(3,1,1),.init(0,floor+2.5,z),"oak_planks")
                }
                let rail = try assets.texture("textures/blocks/rail_normal")
                let first = mesh.vertices.count
                mesh.cube(.init(1,0,1),at:.init(0,floor+0.02,z),material:rail,faces:16)
                let rise = max(0,ceil((z+13)/4))-floor
                for vertex in first..<mesh.vertices.count {
                    if mesh.vertices[vertex].z > z { mesh.vertices[vertex].y += rise }
                    mesh.normals[vertex] = .init(0,1/sqrt(1+rise*rise),-rise/sqrt(1+rise*rise))
                }
            } else if self == .stronghold {
                let chamber = z < -7
                for side in [-1.0,1] {
                    try cube(.init(1,6,1),.init(side*(chamber ? 6 : 3),3,z),index%7 == 0 ? "mossy_stone_bricks" : index%5 == 0 ? "cracked_stone_bricks" : "stone_bricks")
                    if !chamber && index%4 != 0 { try cube(.init(1,4,1),.init(side*2.5,2,z),"bookshelf") }
                }
                try cube(.init(chamber ? 13 : 7,1,1),.init(0,6.5,z),"stone_bricks")
            } else if index%4 == 0 {
                for side in [-1.0,1] { try cube(.init(2,5+Double(index%3),2),.init(side*6,3,z),"amethyst_block") }
            }
            if index%8 == 0 {
                let light = SCNNode(); light.light = SCNLight(); light.light?.type = .omni
                light.light?.color = Landscape.colour(self == .rift ? 0x8CDADF : 0xF2C080)
                light.light?.intensity = 280; light.light?.attenuationEndDistance = 12
                light.position = .init(0,floor+2.6,z); scene.rootNode.addChildNode(light)
                let torch = try assets.texture("textures/blocks/torch_on")
                mesh.cube(.init(1,1,0),at:.init(1.48,floor+1.8,z),material:torch,faces:1)
            }
        }
        if self == .stronghold {
            try cube(.init(7,1,7),.init(0,0,-18),"stone_bricks")
            for side in [-1.0,1] {
                try cube(.init(1,2,5),.init(side*4,1,-18),"lava")
                for index in -2...2 { try cube(.init(0.125,3,0.125),.init(side*5.5,2,Double(index)-18),"iron_bars") }
            }
            try Structures.endPortal(scene.rootNode,at:.init(0,0.5,-18),assets:assets)
        } else {
            try Structures.portal(scene.rootNode,at:.init(0,self == .rift ? 2 : 0,self == .rift ? -14 : -28),assets:assets,sift:self == .rift)
        }
        scene.rootNode.addChildNode(mesh.node("passage-masonry"))
        if self == .mine {
            for index in 0..<3 {
                let bat = try factory.make(.bat)
                bat.position = .init(Double(index-1),3.4,-Double(index)*5-10)
                bat.runAction(.repeatForever(.sequence([.moveBy(x:0.3,y:0.2,z:-1,duration:3),.moveBy(x:-0.3,y:-0.2,z:1,duration:3)])))
                scene.rootNode.addChildNode(bat)
            }
        }
        return scene
    }
}
