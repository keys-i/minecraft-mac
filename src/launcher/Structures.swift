import AppKit
import SceneKit

@MainActor
enum Structures {
    static func build(_ biome: Biome, x: Double, y: Double, factory: Mobs) -> SCNNode {
        let root = SCNNode()
        root.name = "landmark-\(biome)"
        root.position = .init(x,y,-14)
        var mesh = Voxels()
        let stone = factory.paint(0x7F8580), dark = factory.paint(0x3D3845)
        let wood = factory.paint(0x805D3E), sand = factory.paint(0xD7C28D)
        let purpur = factory.paint(0xA27DB0), white = factory.paint(0xDAD6BB)
        func cube(_ size: SCNVector3, _ p: SCNVector3, _ material: SCNMaterial) {
            mesh.cube(size,at:p,material:material)
        }
        func steps(_ x: Double, _ z: Double, _ width: Double, _ levels: Int, _ material: SCNMaterial) {
            for level in 0..<levels {
                let span = width - Double(level)*1.25
                cube(.init(span,0.65,span),.init(x,Double(level)*0.65+0.32,z),material)
            }
        }
        func house(_ x: Double, _ z: Double) {
            cube(.init(4,0.6,4),.init(x,0.3,z),stone)
            for side in [-1.0,1] {
                cube(.init(0.3,3,4),.init(x+side*1.8,1.8,z),wood)
                cube(.init(1.2,3,0.3),.init(x+side*1.3,1.8,z+1.8),wood)
            }
            cube(.init(4,3,0.3),.init(x,1.8,z-1.8),wood)
            cube(.init(0.8,1.7,0.15),.init(x,1.15,z+1.85),dark)
            for tier in 0..<4 { cube(.init(5-Double(tier),0.6,5),.init(x,3.3+Double(tier)*0.6,z),stone) }
        }
        switch biome {
        case .meadow, .cherry, .forest:
            house(-3,-2)
            if biome == .meadow { house(4,-4) }
            for index in 0..<8 {
                cube(.init(0.2,0.5,3),.init(Double(index)*0.5-2,0.4,5),factory.paint(0xBFA54F))
            }
            cube(.init(2,0.5,2),.init(4,0.3,3),stone)
            for side in [-1.0,1] { cube(.init(0.2,2,0.2),.init(4+side*0.8,1.4,3),wood) }
            cube(.init(2.5,0.3,2.5),.init(4,2.4,3),wood)
        case .snow:
            for level in 0..<4 {
                let span = 5-Double(level)
                cube(.init(span,0.7,span),.init(-2,Double(level)*0.7+0.35,0),white)
            }
            cube(.init(1,1.5,1.8),.init(-2,0.75,2.5),white)
            cube(.init(0.65,1.1,0.05),.init(-2,0.55,3.43),dark)
            cube(.init(6,0.08,4),.init(5,0.05,2),factory.paint(0xA2D0DC))
        case .peaks:
            portal(root,at:.init(2,1,0),factory:factory,active:false)
            for step in 0..<8 { cube(.init(5-Double(step)*0.4,1,3),.init(-4,Double(step)*0.8,-1-Double(step)*0.6),stone) }
        case .desert:
            steps(0,-3,12,7,sand)
            for side in [-1.0,1] {
                cube(.init(3,7,3),.init(side*5,3.5,2),sand)
                cube(.init(3.5,0.5,3.5),.init(side*5,7.2,2),sand)
                let orange = factory.paint(0xBC713F)
                cube(.init(0.55,3,0.08),.init(side*5,3.7,3.55),orange)
                cube(.init(1.7,0.55,0.08),.init(side*5,3.7,3.55),orange)
            }
            cube(.init(1.5,2.4,0.1),.init(0,1.2,2.8),dark)
        case .badlands, .lush:
            for depth in 0..<5 {
                let z = Double(depth)*2.2
                for side in [-1.0,1] { cube(.init(0.35,2.5,0.35),.init(side*1.5,1.25,z),wood) }
                cube(.init(3.4,0.35,0.35),.init(0,2.6,z),wood)
                for side in [-1.0,1] { cube(.init(0.1,0.08,2.2),.init(side*0.5,0.1,z),stone) }
                cube(.init(1.4,0.08,0.25),.init(0,0.06,z),wood)
            }
            cube(.init(1.1,0.6,1.5),.init(0,0.5,5),dark)
            if biome == .lush {
                for i in 0..<8 { cube(.init(0.12,2+Double(i%3),0.12),.init(Double(i-4),5,-Double(i%4)),factory.paint(0xD5B85F)) }
            }
        case .mangrove:
            house(0,0)
            for side in [-1.0,1] {
                cube(.init(0.5,3,0.5),.init(side*1.8,-1.2,1.5),wood)
                cube(.init(0.5,3,0.5),.init(side*1.8,-1.2,-1.5),wood)
            }
            root.position.y += 2
            for i in 0..<6 { cube(.init(0.8,0.08,0.65),.init(Double(i-3)*1.4,-y-1.5,8+Double(i%2)),factory.paint(0x557749)) }
        case .jungle:
            let moss = factory.paint(0x657951)
            steps(0,-2,10,6,moss)
            cube(.init(4,3,4),.init(0,5,-2),stone)
            cube(.init(1.5,2.3,0.1),.init(0,4.6,0.05),dark)
            for side in [-1.0,1] { cube(.init(0.2,6,0.15),.init(side*3,3,0),moss) }
        case .mushroom:
            for i in 0..<4 {
                let x = Double(i%2)*7-3, z = Double(i/2)*6-3, h = 4+Double(i%2)*2
                cube(.init(0.8,h,0.8),.init(x,h/2,z),white)
                cube(.init(5,0.8,5),.init(x,h,z),factory.paint(i%2 == 0 ? 0xB83E3C : 0xAC936F))
                for side in [-1.0,1] { cube(.init(0.6,0.1,0.6),.init(x+side*1.2,h+0.45,z+0.8),white) }
            }
        case .pale:
            cube(.init(12,6,6),.init(0,3,-6),wood)
            for tier in 0..<3 { cube(.init(14-Double(tier),0.6,8),.init(0,6.2+Double(tier)*0.6,-6),dark) }
            for i in 0..<6 { cube(.init(0.7,1.3,0.08),.init(Double(i)*1.8-4.5,4.6,-2.95),white) }
        case .coast:
            let prism = factory.paint(0x6FA69C)
            steps(1,-3,11,5,prism)
            for side in [-1.0,1] { cube(.init(2,6,2),.init(side*4,3,-3),prism) }
            for tier in 0..<3 { cube(.init(4-Double(tier),0.5,8-Double(tier)),.init(-6,Double(tier)*0.5,5),wood) }
            cube(.init(0.2,4,0.2),.init(-6,2,5),wood)
        case .deep:
            let sculk = factory.paint(0x1B5559)
            steps(0,-3,12,4,dark)
            for side in [-1.0,1] { cube(.init(2,7,2),.init(side*4,5,-3),stone) }
            cube(.init(10,2,2),.init(0,8.5,-3),stone)
            for i in 0..<12 {
                cube(.init(0.6,0.2,0.6),.init(Double(i%6)*1.6-4,0.2,Double(i/6)*8+3),sculk)
            }
        case .wastes:
            let brick = factory.paint(0x4B2931)
            cube(.init(18,1,3),.init(0,5,0),brick)
            for i in 0..<5 {
                let x = Double(i)*4-8
                for side in [-1.0,1] { cube(.init(0.6,8,0.6),.init(x,1,side*1.4),brick) }
            }
            for side in [-1.0,1] {
                cube(.init(4,7,4),.init(side*7,7,-4),brick)
                cube(.init(4.8,0.8,4.8),.init(side*7,11,-4),brick)
                for i in 0..<4 { cube(.init(0.5,1,0.5),.init(side*7+Double(i%2)*3-1.5,12,-4+Double(i/2)*3-1.5),brick) }
            }
        case .crimson:
            let blackstone = factory.paint(0x403A40), gold = factory.paint(0xD9B043)
            for i in 0..<7 { cube(.init(3,Double(4+i%3),3),.init(Double(i%4)*3-5,Double(4+i%3)/2,-Double(i/4)*4),blackstone) }
            cube(.init(4,3,0.3),.init(0,6,1.7),blackstone)
            for side in [-1.0,1] { cube(.init(0.5,0.8,0.1),.init(side,6.2,1.9),gold) }
            cube(.init(0.8,0.5,0.1),.init(0,5.4,1.9),gold)
            for i in 0..<5 { cube(.init(0.9,0.9,0.9),.init(Double(i%3)-1,0.5,4+Double(i/3)),gold) }
        case .warped:
            portal(root,at:.init(3,0,1),factory:factory,active:false)
        case .soul:
            for i in 0..<6 {
                let z = Double(i)*1.4-3
                cube(.init(5,0.5,0.5),.init(0,0.6,z),white)
                for side in [-1.0,1] {
                    cube(.init(0.5,2.3,0.5),.init(side*2,1.6,z),white)
                    cube(.init(1,0.5,0.5),.init(side*1.8,2.9,z),white)
                }
            }
            for side in [-1.0,1] { cube(.init(0.7,0.5,0.7),.init(side*5,0.3,4),factory.paint(0x6FD5D8)) }
        case .basalt:
            for i in 0..<16 {
                let h = 2+Double(i%5)*1.3
                cube(.init(1.4,h,1.4),.init(Double(i%4)*2.5-4,h/2,Double(i/4)*2.5-4),stone)
            }
        case .central:
            for i in 0..<6 {
                let angle = Double(i) * .pi / 3, h = 7+Double(i%3)*2
                let x = sin(angle)*9, z = cos(angle)*6-5
                cube(.init(1.5,h,1.5),.init(x,h/2,z),dark)
                let crystal = crystal(factory)
                crystal.position = .init(x,h+1,z)
                root.addChildNode(crystal)
            }
            cube(.init(3.5,0.4,3.5),.init(0,0.2,1),dark)
            cube(.init(0.6,2.5,0.6),.init(0,1.5,1),dark)
        case .highlands:
            cube(.init(1.5,0.4,1.5),.init(0,4,0),dark)
            cube(.init(1.5,0.4,1.5),.init(0,6,0),dark)
            for side in [-1.0,1] { cube(.init(0.3,2,0.3),.init(side*0.6,5,0),dark) }
            cube(.init(0.5,0.5,0.5),.init(0,5,0),purpur)
        case .midlands, .islands, .barrens: break
        case .city:
            for tower in 0..<3 {
                let x = Double(tower-1)*5, levels = tower == 1 ? 4 : 2
                cube(.init(1.5,Double(levels)*3.5,1.5),.init(x,Double(levels)*1.75,-Double(tower%2)*4),sand)
                for level in 0..<levels {
                    let y = Double(level)*3.5+2, z = -Double(tower%2)*4
                    cube(.init(3,2.3,3),.init(x,y,z),sand)
                    for side in [-1.0,1] { cube(.init(0.8,1.2,0.1),.init(x+side*0.8,y+0.1,z+1.51),purpur) }
                    for tier in 0..<3 { cube(.init(4.5-Double(tier),0.35,4.5-Double(tier)),.init(x,y+1.3+Double(tier)*0.35,z),purpur) }
                }
            }
            cube(.init(10,0.3,1.3),.init(0,6,0),purpur)
            for tier in 0..<3 { cube(.init(2+Double(tier),0.4,6+Double(tier)),.init(9,9+Double(tier)*0.4,-5),purpur) }
            cube(.init(0.2,4,0.2),.init(9,12,-5),dark)
            cube(.init(3,2,0.1),.init(10.2,12.5,-5),sand)
        case .terraces, .grove, .valley, .shards, .ruins, .sculk:
            let tinted = factory.paint(biome.ground), glow = factory.paint(biome.foliage)
            for i in 0..<6 {
                let x = Double(i%3)*5-5, z = -Double(i/3)*7
                let base = biome == .shards ? 5+Double(i%3) : 0
                for step in 0..<6 {
                    let width = 3.5-Double(step)*0.35
                    cube(.init(width,0.8,width),.init(x,base+Double(step)*0.8,z),step%3 == 0 ? glow : tinted)
                }
            }
            if biome == .ruins {
                for side in [-1.0,1] { cube(.init(1,5,1),.init(side*3,2.5,3),stone) }
                cube(.init(7,1,1),.init(0,5,3),stone)
                cube(.init(2,1,2),.init(-4,0.5,6),wood)
            }
            if [.valley,.sculk,.shards].contains(biome) {
                portal(root,at:.init(0,2,0),factory:factory,active:true,sift:true)
            }
        }
        root.addChildNode(mesh.node("masonry"))
        return root
    }

    static func portal(_ root: SCNNode, at p: SCNVector3, factory: Mobs,
                       active: Bool = true, sift: Bool = false) {
        var mesh = Voxels()
        let dark = factory.paint(sift ? 0x6B597E : 0x30263E)
        for side in [-1.0,1] { mesh.cube(.init(0.8,5.6,0.8),at:.init(side*1.8,2.8,0),material:dark) }
        for y in [0.4,5.2] { mesh.cube(.init(4.4,0.8,0.8),at:.init(0,y,0),material:dark) }
        let frame = mesh.node(sift ? "artistic-rift" : "nether-portal")
        frame.position = p
        root.addChildNode(frame)
        guard active else { return }
        let material = VoxelAdventure.material(sift ? [0x70C6D6,0xB4A8E8,0x688ECC] : [0x6828A1,0xAD54C7,0x853CB8])
        material.emission.contents = NSColor(srgbRed:sift ? 0.25 : 0.4,green:sift ? 0.5 : 0.1,blue:0.6,alpha:1)
        material.isDoubleSided = true
        let plane = SCNPlane(width:2.8,height:4)
        plane.firstMaterial = material
        let surface = SCNNode(geometry:plane)
        surface.name = "portal-surface"
        surface.position = .init(0,2.8,0)
        surface.runAction(.repeatForever(.customAction(duration:64) { node,elapsed in
            var transform = SCNMatrix4MakeScale(3,4,1)
            transform.m41 = elapsed/5
            transform.m42 = elapsed/9
            node.geometry?.firstMaterial?.diffuse.contentsTransform = transform
        }))
        frame.addChildNode(surface)
    }

    static func crystal(_ factory: Mobs) -> SCNNode {
        var mesh = Voxels()
        mesh.cube(.init(0.8,0.8,0.8),at:.init(0,0,0),material:factory.paint(0xD790D1))
        let crystal = mesh.node("end-crystal")
        crystal.eulerAngles.z = .pi/4
        crystal.runAction(.repeatForever(.rotateBy(x:0,y:.pi*2,z:0,duration:8)))
        return crystal
    }
}
