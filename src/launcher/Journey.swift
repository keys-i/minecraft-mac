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
            eyes = [.init(0,14,31),.init(0,10,12),.init(0,3,-8),.init(0,2.8,-24),.init(0,2.8,-27.86)]
            aims = [.init(0,7,8),.init(0,4,-3),.init(0,2.8,-28),.init(0,2.8,-29),.init(0,2.8,-30)]
        case .stronghold:
            eyes = [.init(0,3,16),.init(0,3,3),.init(0,4,-8),.init(0,6,-16),.init(0,1.12,-18)]
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
        return (blend(eyes[index],eyes[index+1]),blend(aims[index],aims[index+1]))
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

@MainActor
extension Passage {
    func scene() -> SCNScene {
        let scene = SCNScene(), factory = Mobs()
        scene.background.contents = Landscape.colour(self == .mine ? 0x9EC9DF : self == .rift ? 0x514267 : 0x17202A)
        scene.fogColor = Landscape.colour(self == .rift ? 0x514267 : 0x17202A)
        scene.fogStartDistance = 28; scene.fogEndDistance = 65
        let camera = SCNNode(); camera.name = "camera"; camera.camera = SCNCamera()
        camera.camera?.fieldOfView = 58; camera.camera?.zNear = 0.05; camera.camera?.zFar = 120
        camera.camera?.wantsHDR = true; camera.camera?.wantsExposureAdaptation = false
        camera.camera?.bloomIntensity = 0.3; camera.camera?.bloomThreshold = 1.2
        scene.rootNode.addChildNode(camera)
        let pose = pose(at:0); camera.position = pose.eye; camera.look(at:pose.aim)
        camera.runAction(.customAction(duration:Double(duration)) { node,elapsed in
            let pose = self.pose(at:Double(elapsed))
            node.position = pose.eye; node.look(at:pose.aim)
        },forKey:"passage")
        let fill = SCNNode(); fill.light = SCNLight(); fill.light?.type = .ambient
        fill.light?.intensity = self == .rift ? 420 : 270
        scene.rootNode.addChildNode(fill)
        var mesh = Voxels()
        let rock = factory.paint(self == .stronghold ? 0x626D69 : 0x66676D)
        let wood = factory.paint(0x805D3E), metal = factory.paint(0xA6AAA5)
        func cube(_ size: SCNVector3, _ at: SCNVector3, _ material: SCNMaterial) {
            mesh.cube(size,at:at,material:material)
        }
        if self == .mine {
            cube(.init(42,9,25),.init(0,4.5,31),factory.paint(0x806047))
            cube(.init(42,0.3,25),.init(0,9,31),factory.paint(0x76A449))
            for side in [-1.0,1] {
                cube(.init(25,15,48),.init(side*17.5,7.5,-4),rock)
                cube(.init(25,0.3,48),.init(side*17.5,15,-4),factory.paint(0x76A449))
                cube(.init(1,6,1),.init(side*10,12,24),wood)
                cube(.init(5,2,5),.init(side*10,15,24),factory.paint(0x4D8246))
            }
        }
        for index in 0..<15 {
            let z = 18-Double(index)*3.5
            let floor = self == .mine ? max(0,9-(15-z)*0.28) : self == .rift ? max(2,5-Double(index)*0.2) : 0
            let material = self == .rift ? factory.paint(index%2 == 0 ? 0xA487BA : 0x77AEBD) : rock
            cube(.init(self == .rift ? 5 : 10,1,3.5),.init(0,floor-0.5,z),material)
            if self == .mine {
                for side in [-1.0,1] {
                    cube(.init(3,9,3.5),.init(side*5,floor+4,z),rock)
                    cube(.init(0.3,4.5,0.3),.init(side*2.3,floor+2.2,z),wood)
                    cube(.init(0.1,0.08,3.5),.init(side*0.6,floor+0.08,z),metal)
                }
                cube(.init(5,0.35,0.35),.init(0,floor+4.3,z),wood)
                cube(.init(1.6,0.08,0.25),.init(0,floor+0.06,z),wood)
                if z < 10 { cube(.init(10,2,3.5),.init(0,floor+6,z),rock) }
                if index%3 == 0 {
                    cube(.init(0.8,0.7,0.8),.init(3.6,floor+1,z),factory.paint(index%2 == 0 ? 0x68BEB8 : 0xBC8B50))
                }
            } else if self == .stronghold {
                let chamber = z < -7
                for side in [-1.0,1] {
                    cube(.init(1,6,3.5),.init(side*(chamber ? 7 : 3.5),3,z),rock)
                    cube(.init(0.7,5.5,0.7),.init(side*(chamber ? 5.8 : 3),2.7,z),factory.paint(0x4D6252))
                    if index < 5 {
                        cube(.init(0.3,3,2.5),.init(side*3,2,z),wood)
                        for book in 0..<4 { cube(.init(0.35,0.55,0.28),.init(side*2.8,1.2+Double(book%2),z+Double(book/2)*0.8),factory.paint(book%2 == 0 ? 0x94494B : 0xB7AD70)) }
                    }
                }
                cube(.init(chamber ? 15 : 8,1,3.5),.init(0,6.5,z),rock)
            } else {
                for side in [-1.0,1] {
                    let h = 4+Double(index%4)
                    cube(.init(1.5,h,2),.init(side*(5+Double(index%3)),floor+h/2-2,z),material)
                    cube(.init(2,0.3,2),.init(side*7,floor+h,z),factory.paint(0xC1A9DB))
                }
            }
            if index%3 == 0 {
                let torch = SCNNode(); torch.light = SCNLight(); torch.light?.type = .omni
                torch.light?.color = Landscape.colour(self == .stronghold ? 0xABC4A2 : self == .rift ? 0x8CDADF : 0xF2B775)
                torch.light?.intensity = 350; torch.light?.attenuationEndDistance = 16
                torch.position = .init(2,floor+3,z)
                scene.rootNode.addChildNode(torch)
                cube(.init(0.18,0.6,0.18),.init(2.3,floor+2.5,z),wood)
                cube(.init(0.3,0.3,0.3),.init(2.3,floor+2.9,z),factory.paint(0xE9BF67))
            }
        }
        if self == .stronghold {
            cube(.init(8,0.6,8),.init(0,0.3,-18),rock)
            let green = factory.paint(0x4C8876)
            for side in [-1.0,1] {
                for index in -1...1 {
                    let offset = Double(index)*1.1
                    for p in [SCNVector3(side*2.2,1,-18+offset),SCNVector3(offset,1,-18+side*2.2)] {
                        cube(.init(1.1,0.7,1.1),p,green)
                        cube(.init(0.5,0.18,0.5),.init(p.x,p.y+0.44,p.z),factory.paint(0xA2C4A1))
                    }
                }
            }
            let material = VoxelAdventure.material([0x080C1B,0x111829,0x151F36,0xA5ABCE,0x080C1B,0x080C1B,0x080C1B])
            material.isDoubleSided = true; material.lightingModel = .constant
            material.diffuse.contentsTransform = SCNMatrix4MakeScale(12,12,1)
            let plane = SCNPlane(width:3.3,height:3.3); plane.firstMaterial = material
            let surface = SCNNode(geometry:plane); surface.name = "end-portal"
            surface.position = .init(0,1.05,-18); surface.eulerAngles.x = -.pi/2
            scene.rootNode.addChildNode(surface)
        } else {
            Structures.portal(scene.rootNode,at:.init(0,self == .rift ? 2 : 0,self == .rift ? -14 : -28),factory:factory,sift:self == .rift)
        }
        scene.rootNode.addChildNode(mesh.node("passage-masonry"))
        if self == .mine {
            for index in 0..<3 {
                let bat = factory.make(.bat)
                bat.position = .init(Double(index-1),5,-Double(index)*5)
                bat.runAction(.repeatForever(.sequence([.moveBy(x:1,y:0.3,z:-1,duration:3),.moveBy(x:-1,y:-0.3,z:1,duration:3)])))
                scene.rootNode.addChildNode(bat)
            }
        }
        return scene
    }
}
