import AppKit
import SceneKit

enum Species: String, CaseIterable {
    case pig, cow, sheep, wolf, fox, rabbit, goat, llama, camel, armadillo, frog
    case panda, parrot, ocelot, mooshroom, creaking, turtle, dolphin, squid, axolotl, glowsquid
    case warden, bat, bee, spider, slime, villager, golem
    case piglin, hoglin, strider, blaze, skeleton, ghast, magma, enderman, endermite, shulker
    case illager, vindicator, allay, vex

    var flying: Bool { [.bee, .parrot, .bat, .blaze, .ghast, .allay, .vex].contains(self) }
    var swimming: Bool { [.dolphin, .squid, .glowsquid, .axolotl].contains(self) }
}

// One factory per landscape shares palettes and prototypes without a global model cache
@MainActor
final class Mobs {
    private var colours: [UInt32: SCNMaterial] = [:]
    private var models: [Species: SCNNode] = [:]

    func paint(_ rgb: UInt32) -> SCNMaterial {
        if let material = colours[rgb] { return material }
        func tint(_ amount: Int) -> UInt32 {
            [16, 8, 0].reduce(UInt32(0)) { result, shift in
                result | (UInt32(min(255, max(0, Int((rgb >> shift) & 255) + amount))) << shift)
            }
        }
        let material = VoxelAdventure.material([rgb, tint(12), tint(-10)])
        if [0x6FD5D8, 0xE8C76E, 0xC58EEB, 0xE5A137, 0xF2A335, 0x56B9AF].contains(rgb) {
            material.emission.contents = Landscape.colour(rgb).withAlphaComponent(0.5)
        }
        colours[rgb] = material
        return material
    }

    func make(_ species: Species) -> SCNNode {
        if let model = models[species] { return model.clone() }
        let model: SCNNode
        switch species {
        case .pig, .cow, .sheep, .wolf, .fox, .rabbit, .goat, .llama, .camel, .armadillo,
             .panda, .ocelot, .mooshroom, .hoglin: model = animal(species)
        case .villager, .golem, .piglin, .skeleton, .enderman, .illager, .vindicator,
             .warden, .creaking: model = person(species)
        case .bee, .parrot, .bat, .allay, .vex: model = flyer(species)
        case .turtle, .frog, .axolotl, .dolphin, .squid, .glowsquid: model = aquatic(species)
        case .ghast:
            model = VoxelAdventure.scene(.nether).rootNode.childNode(withName: "ghast", recursively: false)!.clone()
            model.removeAllActions()
        case .strider, .slime, .magma, .blaze, .spider, .endermite, .shulker: model = hostile(species)
        }
        if species == .rabbit || species == .frog {
            model.runAction(.repeatForever(.sequence([.moveBy(x:0,y:0.3,z:0,duration:0.4),
                .moveBy(x:0,y:-0.3,z:0,duration:0.4),.wait(duration:2.5)])))
        }
        model.name = "mob-\(species.rawValue)"
        models[species] = model
        return model.clone()
    }

    private func part(_ mesh: inout Voxels, _ size: SCNVector3, _ at: SCNVector3, _ rgb: UInt32) {
        mesh.cube(size, at: at, material: paint(rgb))
    }

    private func eyes(_ mesh: inout Voxels, width: Double, y: Double, z: Double,
                      colour: UInt32 = 0x28272C, size: Double = 0.09) {
        for side in [-1.0, 1] {
            part(&mesh, .init(size, size, 0.025), .init(side * width, y, z), colour)
        }
    }

    private func joint(_ parent: SCNNode, _ mesh: Voxels, at: SCNVector3,
                       x: CGFloat = 0, y: CGFloat = 0, z: CGFloat = 0,
                       period: Double = 2, phase: Double = 0) {
        let node = mesh.node("joint")
        node.position = at
        VoxelAdventure.sway(node, x: x, y: y, z: z, period: period, phase: phase)
        parent.addChildNode(node)
    }

    private func animal(_ species: Species) -> SCNNode {
        let mob = SCNNode()
        let coat: UInt32, width: Double, length: Double, leg: Double, neck: Double
        switch species {
        case .pig: (coat,width,length,leg,neck) = (0xDEA0A5,0.8,1.25,0.5,0)
        case .cow, .mooshroom: (coat,width,length,leg,neck) = (species == .cow ? 0x684D3D : 0xB83E3C,0.9,1.35,0.7,0)
        case .sheep: (coat,width,length,leg,neck) = (0xE2DECD,1,1.35,0.55,0)
        case .wolf: (coat,width,length,leg,neck) = (0xB8BCB7,0.55,1.05,0.65,0)
        case .fox: (coat,width,length,leg,neck) = (0xCF7436,0.55,1.05,0.35,0)
        case .rabbit: (coat,width,length,leg,neck) = (0xB59D81,0.36,0.6,0.2,0)
        case .goat: (coat,width,length,leg,neck) = (0xDEDCCE,0.6,1,0.8,0)
        case .llama: (coat,width,length,leg,neck) = (0xC5A983,0.8,1.3,1.0,0.9)
        case .camel: (coat,width,length,leg,neck) = (0xC6A16A,1.1,1.9,1.3,0.65)
        case .armadillo: (coat,width,length,leg,neck) = (0x9D736B,0.65,0.9,0.22,0)
        case .panda: (coat,width,length,leg,neck) = (0xE2E2D5,1.3,1.6,0.55,0)
        case .ocelot: (coat,width,length,leg,neck) = (0xD9B34F,0.45,1.1,0.4,0)
        default: (coat,width,length,leg,neck) = (0x9B6656,1.4,1.8,0.65,0)
        }
        var body = Voxels(), head = Voxels()
        let tall = width * 0.75, front = length / 2 + 0.12
        part(&body, .init(width,tall,length), .init(0,leg+tall/2,0), coat)
        if neck > 0 {
            part(&body,.init(width*0.5,neck+0.4,width*0.55),.init(0,leg+tall+neck/2,front-0.2),coat)
        }
        if species == .camel {
            part(&body,.init(0.7,0.45,0.7),.init(0,leg+tall+0.2,-0.25),coat)
        }
        if [.cow,.mooshroom,.ocelot,.panda].contains(species) {
            for side in [-1.0,1] {
                for index in 0..<3 {
                    part(&body,.init(0.025,tall*0.5,length*0.19),.init(side*(width/2+0.01),leg+tall*0.6,Double(index-1)*length*0.3),species == .panda ? 0x28272C : 0xDCD9C9)
                }
            }
        }
        if species == .mooshroom {
            for z in [-0.4,0.3] {
                part(&body,.init(0.08,0.25,0.08),.init(0,leg+tall+0.12,z),0xDCD9C9)
                part(&body,.init(0.38,0.15,0.38),.init(0,leg+tall+0.3,z),0xB83E3C)
            }
        }
        if [.wolf,.fox,.ocelot].contains(species) {
            part(&body,.init(width*0.45,width*0.5,length*0.65),.init(0,leg+tall*0.65,-length*0.75),coat)
            part(&body,.init(width*0.46,width*0.51,0.2),.init(0,leg+tall*0.65,-length*1.08),0xE2DECD)
        }
        if species == .armadillo {
            for z in [-0.3,0,0.3] { part(&body,.init(width+0.05,tall+0.07,0.08),.init(0,leg+tall/2,z),0x79584F) }
        }
        let hw = species == .panda ? 0.8 : width * 0.72
        part(&head,.init(hw,hw,hw*0.85),.init(0,0,0),coat)
        part(&head,.init(hw*0.55,hw*0.3,hw*0.3),.init(0,-hw*0.15,hw*0.5),species == .pig ? 0xBB7A87 : 0xD6C6AD)
        eyes(&head,width:hw*0.31,y:hw*0.13,z:hw*0.44,size:hw*0.13)
        if species == .pig { eyes(&head,width:hw*0.13,y:-hw*0.15,z:hw*0.66,colour:0x80505B,size:0.055) }
        if species == .goat { part(&head,.init(0.12,0.25,0.15),.init(0,-hw*0.6,hw*0.25),0xC8BD9E) }
        for side in [-1.0,1] {
            let ears = species == .rabbit ? 0.5 : 0.18
            part(&head,.init(hw*0.22,ears,0.12),.init(side*hw*0.37,hw/2+ears/2,0),species == .panda ? 0x28272C : coat)
            if [.cow,.mooshroom,.goat,.hoglin].contains(species) {
                part(&head,.init(0.11,0.33,0.1),.init(side*hw*0.44,hw/2+0.12,-0.08),0xDCD9C9)
            }
            if species == .panda {
                part(&head,.init(0.2,0.19,0.025),.init(side*0.25,0.1,hw*0.45),0x28272C)
            }
            if species == .hoglin {
                part(&head,.init(0.15,0.35,0.15),.init(side*0.45,-0.1,hw*0.6),0xDCD9C9)
            }
        }
        mob.addChildNode(body.node("body"))
        joint(mob,head,at:.init(0,leg+tall+neck,front),x:0.1,y:0.12,period:5)
        for side in [-1.0,1] {
            for z in [-length*0.33,length*0.33] {
                var limb = Voxels()
                let colour: UInt32 = species == .panda ? 0x28272C : coat
                part(&limb,.init(width*0.22,leg,width*0.24),.init(0,-leg/2,0),colour)
                part(&limb,.init(width*0.24,0.1,width*0.26),.init(0,-leg+0.05,0),0x584A42)
                joint(mob,limb,at:.init(side*width*0.32,leg,z),x:0.13,period:2.6,phase:side*z>0 ? 0 : .pi)
            }
        }
        return mob
    }

    private func person(_ species: Species) -> SCNNode {
        let mob = SCNNode()
        let skin: UInt32, coat: UInt32, width: Double, height: Double
        switch species {
        case .villager: (skin,coat,width,height) = (0xB58A6B,0x805B3E,0.65,2)
        case .golem: (skin,coat,width,height) = (0xC2D5CF,0xBA7650,0.85,1.35)
        case .piglin: (skin,coat,width,height) = (0xCF9D8D,0x72513E,0.7,2)
        case .skeleton: (skin,coat,width,height) = (0xB7B6AA,0xB7B6AA,0.48,2.1)
        case .enderman: (skin,coat,width,height) = (0x25212C,0x25212C,0.55,3)
        case .warden: (skin,coat,width,height) = (0x27434C,0x17545C,1.2,2.7)
        case .creaking: (skin,coat,width,height) = (0x736858,0x5E594F,0.65,2.7)
        case .vindicator: (skin,coat,width,height) = (0x92938B,0x76524D,0.65,2)
        default: (skin,coat,width,height) = (0x92938B,0x655968,0.65,2)
        }
        var body = Voxels(), head = Voxels()
        let legs = height * 0.36, torso = height * 0.36, hw = min(0.78,width)
        part(&body,.init(width,torso,width*0.55),.init(0,legs+torso/2,0),coat)
        part(&head,.init(hw,height*0.25,hw),.init(0,0,0),skin)
        if [.villager,.illager,.vindicator,.piglin,.golem].contains(species) {
            part(&head,.init(0.16,0.29,0.2),.init(0,-0.1,hw/2+0.08),skin)
            part(&head,.init(hw*0.8,0.06,0.025),.init(0,0.15,hw/2+0.01),0x48443C)
        }
        let glow: UInt32 = species == .enderman ? 0xC58EEB : species == .creaking ? 0xE5A137 : 0x28272C
        if species != .warden { eyes(&head,width:hw*0.26,y:0.07,z:hw/2+0.02,colour:glow) }
        if species == .warden {
            for side in [-1.0,1] {
                part(&head,.init(0.2,0.6,0.22),.init(side*0.55,0.23,0),0x6ABBB3)
                part(&head,.init(0.3,0.18,0.2),.init(side*0.5,0.56,0),0xC9CFBA)
                for index in 0..<3 { part(&body,.init(0.38,0.07,0.03),.init(side*0.28,legs+0.35+Double(index)*0.13,width*0.28),0x92B6AE) }
            }
        }
        if species == .creaking {
            part(&head,.init(0.16,0.5,0.17),.init(-0.22,0.5,0),skin)
            part(&body,.init(0.16,0.8,0.15),.init(0.52,legs+torso+0.2,0),skin)
        }
        if species == .piglin {
            for side in [-1.0,1] { part(&head,.init(0.28,0.23,0.1),.init(side*0.43,0.04,0),skin) }
        }
        if species == .skeleton {
            for rib in 0..<3 { part(&body,.init(width,0.07,0.025),.init(0,legs+0.2+Double(rib)*0.16,width*0.28),0x433D4B) }
        }
        if species == .creaking { part(&head,.init(0.08,0.07,0.025),.init(0.04,-0.12,hw/2+0.02),0xE5A137) }
        mob.addChildNode(body.node("body"))
        joint(mob,head,at:.init(0,height-height*0.125,0),y:0.12,period:7)
        for side in [-1.0,1] {
            var leg = Voxels(), arm = Voxels()
            let thin = species == .enderman || species == .skeleton ? 0.14 : width*0.32
            part(&leg,.init(thin,legs,thin),.init(0,-legs/2,0),skin)
            joint(mob,leg,at:.init(side*width*0.25,legs,0),x:0.09,phase:side<0 ? 0 : .pi)
            part(&arm,.init(thin,torso*1.1,thin),.init(0,-torso*0.45,0),skin)
            if species == .vindicator && side > 0 {
                part(&arm,.init(0.07,0.6,0.08),.init(0,-torso*0.6,0.2),0x805B3E)
                part(&arm,.init(0.35,0.25,0.09),.init(0.1,-torso*0.4,0.2),0xB7B6AA)
            }
            joint(mob,arm,at:.init(side*(width/2+thin/2),legs+torso-0.06,0),x:0.08,phase:side>0 ? 0 : .pi)
        }
        return mob
    }

    private func flyer(_ species: Species) -> SCNNode {
        let mob = SCNNode()
        var body = Voxels()
        let colour: UInt32 = species == .bee ? 0xE5B53E : species == .parrot ? 0xC43D43 : species == .bat ? 0x584A42 : species == .vex ? 0x9FAEBE : 0x65C9E3
        let fae = species == .allay || species == .vex
        part(&body,.init(0.5,0.45,fae ? 0.45 : 0.65),.init(0,0,0),colour)
        eyes(&body,width:0.15,y:0.08,z:fae ? 0.24 : 0.34,colour:fae ? 0xDCEAE4 : 0x28272C)
        if species == .bee {
            for z in [-0.2,0.04] { part(&body,.init(0.51,0.46,0.09),.init(0,0,z),0x584A42) }
            for side in [-1.0,1] {
                part(&body,.init(0.04,0.23,0.04),.init(side*0.16,0.3,0.23),0x584A42)
                for z in [-0.2,0,0.2] { part(&body,.init(0.04,0.15,0.04),.init(side*0.18,-0.27,z),0x584A42) }
            }
        } else {
            part(&body,.init(0.28,0.4,0.25),.init(0,-0.35,0),colour)
            if species == .parrot {
                part(&body,.init(0.16,0.18,0.18),.init(0,0,0.4),0xD8B854)
                part(&body,.init(0.22,0.6,0.12),.init(0,-0.6,-0.2),0x3E8AB4)
            }
            if species == .bat {
                for side in [-1.0,1] { part(&body,.init(0.17,0.3,0.1),.init(side*0.17,0.35,0),colour) }
            }
        }
        mob.addChildNode(body.node("body"))
        for side in [-1.0,1] {
            var wing = Voxels()
            part(&wing,fae ? .init(0.4,0.5,0.03) : .init(species == .bat ? 0.65 : 0.45,0.04,0.5),.init(side*0.23,0,0),species == .bee ? 0xDCEAE4 : species == .parrot ? 0x3E8AB4 : fae ? 0xB6D7DF : colour)
            joint(mob,wing,at:.init(side*0.2,0.15,-0.05),y:fae ? side*0.7 : 0,z:fae ? 0 : side*0.65,period:species == .bee ? 0.35 : 0.8)
        }
        return mob
    }

    private func aquatic(_ species: Species) -> SCNNode {
        let mob = SCNNode()
        var body = Voxels()
        let colour: UInt32 = species == .turtle ? 0x6F955B : species == .frog ? 0xAD7956 : species == .axolotl ? 0xDDA3C5 : species == .dolphin ? 0x7AABBC : species == .glowsquid ? 0x56B9AF : 0x566C80
        if species == .squid || species == .glowsquid {
            part(&body,.init(0.65,0.8,0.65),.init(0,0,0),colour)
            eyes(&body,width:0.23,y:0,z:0.34,colour:0xDCEAE4)
            mob.addChildNode(body.node("body"))
            for index in 0..<8 {
                let angle = Double(index) * .pi/4
                var tentacle = Voxels()
                part(&tentacle,.init(0.09,0.8,0.09),.init(0,-0.4,0),colour)
                joint(mob,tentacle,at:.init(sin(angle)*0.3,-0.4,cos(angle)*0.3),x:0.3,z:0.3,period:3,phase:angle)
            }
        } else {
            let length = species == .dolphin ? 1.65 : species == .axolotl ? 0.85 : 0.95
            part(&body,.init(0.75,0.35,length),.init(0,0.25,0),colour)
            part(&body,.init(0.4,0.28,0.4),.init(0,0.22,length/2+0.1),colour)
            eyes(&body,width:0.15,y:0.29,z:length/2+0.31)
            if species == .turtle { part(&body,.init(0.85,0.25,0.95),.init(0,0.47,-0.1),0x456B4C) }
            if species == .frog {
                for side in [-1.0,1] { part(&body,.init(0.2,0.22,0.2),.init(side*0.25,0.52,0.32),colour) }
                eyes(&body,width:0.25,y:0.56,z:0.43,colour:0xDCEAE4)
            }
            if species == .axolotl {
                for side in [-1.0,1] {
                    for index in 0..<3 { part(&body,.init(0.3,0.07,0.07),.init(side*0.3,0.25+Double(index)*0.11,0.48),0xBA548F) }
                }
            }
            if species == .dolphin {
                part(&body,.init(0.12,0.4,0.4),.init(0,0.6,-0.25),colour)
                part(&body,.init(0.9,0.09,0.4),.init(0,0.2,-length/2-0.25),colour)
            }
            mob.addChildNode(body.node("body"))
            for side in [-1.0,1] {
                for z in [-0.3,0.3] {
                    var fin = Voxels()
                    part(&fin,.init(0.35,0.09,0.3),.init(side*0.15,0,0),colour)
                    joint(mob,fin,at:.init(side*0.35,0.1,z),y:0.25,period:2.7,phase:side*z>0 ? 0 : .pi)
                }
            }
        }
        return mob
    }

    private func hostile(_ species: Species) -> SCNNode {
        let mob = SCNNode()
        var body = Voxels()
        let colour: UInt32 = species == .magma ? 0x532E2C : species == .slime ? 0x78AE65 : species == .shulker ? 0x956DA1 : species == .blaze ? 0xD7A543 : species == .strider ? 0xA94F59 : 0x433D4B
        if species == .slime || species == .magma {
            for layer in 0..<4 { part(&body,.init(1.15,0.23,1.15),.init(0,0.2+Double(layer)*0.26,0),colour) }
            eyes(&body,width:0.3,y:0.75,z:0.59,colour:species == .magma ? 0xF2A335 : 0x304D32,size:0.18)
            part(&body,.init(0.3,0.08,0.03),.init(0,0.4,0.59),0x304D32)
        } else if species == .shulker {
            part(&body,.init(0.95,0.45,0.95),.init(0,0.23,0),colour)
            part(&body,.init(0.5,0.5,0.5),.init(0,0.55,0),0xD5CE99)
            eyes(&body,width:0.15,y:0.63,z:0.27)
            var lid = Voxels()
            part(&lid,.init(0.98,0.5,0.98),.init(0,0.25,0),colour)
            joint(mob,lid,at:.init(0,0.85,0),x:0.12,period:5)
        } else if species == .blaze {
            part(&body,.init(0.5,0.5,0.5),.init(0,0,0),colour)
            eyes(&body,width:0.15,y:0.05,z:0.26)
            for index in 0..<8 {
                let angle = Double(index) * .pi/4
                part(&body,.init(0.13,0.65,0.13),.init(sin(angle)*0.7,Double(index%2)*0.6-0.5,cos(angle)*0.7),colour)
            }
            mob.runAction(.repeatForever(.rotateBy(x:0,y:.pi*2,z:0,duration:12)))
        } else if species == .strider {
            part(&body,.init(1.2,0.95,1.2),.init(0,1.65,0),colour)
            eyes(&body,width:0.3,y:1.75,z:0.61)
            for side in [-1.0,1] {
                var leg = Voxels()
                part(&leg,.init(0.16,1.2,0.18),.init(0,-0.6,0),colour)
                joint(mob,leg,at:.init(side*0.3,1.2,0),x:0.12,period:2.3,phase:side<0 ? 0 : .pi)
                for index in 0..<3 { part(&body,.init(0.4,0.045,0.045),.init(side*0.76,1.4+Double(index)*0.2,0),0xB7B6AA) }
            }
        } else {
            let small = species == .endermite
            part(&body,.init(small ? 0.4 : 0.85,small ? 0.3 : 0.5,small ? 0.7 : 1.3),.init(0,0.35,0),colour)
            eyes(&body,width:small ? 0.11 : 0.24,y:0.43,z:small ? 0.36 : 0.66,colour:0xC55262)
            if !small {
                for side in [-1.0,1] {
                    for index in 0..<4 {
                        var leg = Voxels()
                        part(&leg,.init(0.85,0.07,0.09),.init(side*0.4,0,0),colour)
                        joint(mob,leg,at:.init(side*0.4,0.3,Double(index)*0.3-0.5),y:0.15,z:side*0.3,period:2,phase:Double(index) * .pi/2)
                    }
                }
            }
        }
        mob.addChildNode(body.node("body"))
        if species == .slime || species == .magma {
            mob.childNodes.forEach { $0.runAction(.repeatForever(.sequence([.moveBy(x:0,y:0.65,z:0,duration:0.7),.moveBy(x:0,y:-0.65,z:0,duration:0.7),.wait(duration:1)]))) }
        }
        return mob
    }
}
