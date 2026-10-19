import AppKit
import SceneKit

enum Species: String, CaseIterable {
    case pig, cow, sheep, wolf, fox, rabbit, goat, llama, camel, armadillo, frog, creeper, chicken, zombie, ironGolem
    case panda, parrot, ocelot, mooshroom, creaking, turtle, dolphin, squid, axolotl, glowsquid
    case warden, bat, bee, spider, slime, villager, golem
    case piglin, hoglin, strider, blaze, skeleton, ghast, magma, enderman, endermite, shulker
    case illager, vindicator, allay, vex

    var flying: Bool { [.bee, .parrot, .bat, .blaze, .ghast, .allay, .vex].contains(self) }
    var swimming: Bool { [.dolphin, .squid, .glowsquid, .axolotl].contains(self) }
}

// Prototypes share the installed game's geometry and textures within one scene
final class Mobs {
    let assets: Assets
    private var models: [String: SCNNode] = [:]

    init(assets: Assets) { self.assets = assets }

    func make(_ species: Species, biome: Biome? = nil) throws -> SCNNode {
        let name: String
        switch species {
        case .golem: name = "copper_golem"
        case .ironGolem: name = "iron_golem"
        case .glowsquid: name = "glow_squid"
        case .magma: name = "magma_cube"
        case .illager: name = "pillager"
        default: name = species.rawValue
        }
        let texture: String
        switch species {
        case .wolf: texture = "pale_default"
        case .fox: texture = biome == .snow ? "arctic" : "red"
        case .rabbit: texture = biome == .snow ? "white" : "brown"
        case .llama: texture = "creamy"
        case .frog: texture = "temperate"
        case .parrot: texture = "red_blue"
        case .ocelot: texture = "wild"
        case .axolotl: texture = "lucy"
        case .villager: texture = "farmer"
        case .shulker: texture = "undyed"
        default: texture = "default"
        }
        return try actor(name, texture: texture, label: species.rawValue)
    }

    func actor(_ name: String, texture: String = "default", label: String? = nil) throws -> SCNNode {
        let key = name+"-"+texture
        if let model = models[key] { return model.clone() }
        let model = try assets.actor(name,texture:texture)
        model.name = "mob-"+(label ?? name)
        var index = 0
        model.enumerateChildNodes { node,_ in
            let name = node.name?.lowercased() ?? ""
            if name.contains("leg") && key != "ender_dragon-default" {
                VoxelAdventure.sway(node,x:0.12,period:2.6,phase:index.isMultiple(of:2) ? 0 : .pi)
                index += 1
            } else if name.contains("tentacle") {
                VoxelAdventure.sway(node,x:0.15,z:0.1,period:4,phase:Double(index)*0.7)
                index += 1
            } else if name.contains("wing") && key != "ender_dragon-default" {
                VoxelAdventure.sway(node,z:0.4,period:key.hasPrefix("bee-") ? 0.3 : 1.2)
            } else if name == "head" { VoxelAdventure.sway(node,y:0.07,period:7) }
        }
        models[key] = model
        return model.clone()
    }
}
