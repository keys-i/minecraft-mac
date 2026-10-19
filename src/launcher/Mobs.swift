import AppKit
import SceneKit

enum Species: String, CaseIterable {
    case pig, cow, sheep, wolf, fox, rabbit, goat, llama, camel, armadillo, frog, creeper, chicken, zombie, ironGolem
    case panda, parrot, ocelot, mooshroom, creaking, turtle, dolphin, squid, axolotl, glowsquid
    case warden, bat, bee, spider, slime, villager, golem
    case piglin, hoglin, strider, blaze, skeleton, ghast, magma, enderman, endermite, shulker
    case illager, vindicator, allay, vex
    case horse, polarBear, witch, guardian, drowned, breeze, bogged, witherSkeleton, piglinBrute, zombifiedPiglin
    case cod, salmon, sniffer, husk, ravager, silverfish, tropical, snowGolem, cat
    case camelHusk, parched, nautilus, zombieNautilus, happyGhast

    var flying: Bool { [.bee, .parrot, .bat, .blaze, .ghast, .allay, .vex, .breeze, .happyGhast].contains(self) }
    var swimming: Bool { [.dolphin, .squid, .glowsquid, .axolotl, .guardian, .drowned, .cod, .salmon, .tropical, .nautilus, .zombieNautilus].contains(self) }
}

// Prototypes share the installed game's geometry and textures within one scene
final class Mobs {
    let assets: Assets
    private var models: [String: SCNNode] = [:]
    private var locomotions: [Species:(speed:Double,width:Double,height:Double)] = [:]
    private var classics: [Species:SCNNode] = [:]

    init(assets: Assets) { self.assets = assets }

    func make(_ species: Species, biome: Biome? = nil, variant: Int = 0, classic: Bool = false) throws -> SCNNode {
        if classic && [.pig,.cow,.chicken,.wolf].contains(species) {
            if let model = classics[species] { return model.clone() }
            let data = assets.resources[0].deletingLastPathComponent().deletingLastPathComponent()
            let old = try Assets(data:data,classic:true)
            let model = try old.actor(species.rawValue)
            model.name = "mob-"+species.rawValue
            old.releaseArchives(); classics[species] = model
            return model.clone()
        }
        let name: String
        switch species {
        case .camelHusk: name = "camel_husk"
        case .zombieNautilus: name = "zombie_nautilus"
        case .happyGhast: name = "happy_ghast"
        case .snowGolem: name = "snow_golem"
        case .tropical: name = "tropicalfish"
        case .horse: name = "horse_v3"
        case .polarBear: name = "polar_bear"
        case .witherSkeleton: name = "wither_skeleton"
        case .piglinBrute: name = "piglin_brute"
        case .zombifiedPiglin: name = "zombie_pigman"
        case .golem: name = "copper_golem"
        case .ironGolem: name = "iron_golem"
        case .glowsquid: name = "glow_squid"
        case .magma: name = "magma_cube"
        case .illager: name = "pillager"
        default: name = species.rawValue
        }
        let texture: String
        switch species {
        case .happyGhast: texture = "happy_ghast"
        case .horse: texture = ["base_brown","base_chestnut","base_white","base_black"][variant%4]
        case .cat: texture = ["tabby","calico","jellie"][variant%3]
        case .tropical: texture = variant%2 == 0 ? "typeA" : "typeB"
        case .wolf: texture = biome == .snow ? "snowy_default" : ["woods_default","pale_default","ashen_default"][variant%3]
        case .fox: texture = biome == .snow ? "arctic" : "red"
        case .rabbit: texture = biome == .snow ? "white" : "brown"
        case .llama: texture = "creamy"
        case .frog: texture = biome == .mangrove ? "warm" : "temperate"
        case .parrot: texture = ["red_blue","green","blue","yellow_blue","grey"][variant%5]
        case .ocelot: texture = "wild"
        case .axolotl: texture = ["lucy","wild","gold","cyan"][variant%4]
        case .pig,.cow,.chicken: texture = [.desert,.savanna,.jungle,.badlands].contains(biome) ? "warm" : [.snow,.peaks,.ice].contains(biome) ? "cold" : "default"
        case .villager: texture = "farmer"
        case .shulker: texture = "undyed"
        default: texture = "default"
        }
        return try actor(name, texture: texture, label: species.rawValue,variant:variant)
    }

    func actor(_ name: String, texture: String = "default", label: String? = nil, variant: Int = 0) throws -> SCNNode {
        let key = name+"-"+texture+(name == "tropicalfish" ? "-\(variant)" : "")
        if let model = models[key] { return model.clone() }
        let model = try assets.actor(name,texture:texture,variant:variant)
        model.name = "mob-"+(label ?? name)
        var index = 0
        model.enumerateChildNodes { node,_ in
            let name = node.name?.lowercased() ?? ""
            if name.contains("tentacle") {
                VoxelAdventure.sway(node,x:0.15,z:0.1,period:4,phase:Double(index)*0.7)
                index += 1
            } else if name.contains("wing") && key != "ender_dragon-default" {
                VoxelAdventure.sway(node,z:0.4,period:key.hasPrefix("bee-") ? 0.3 : 1.2)
            } else if name.contains("tail") && key != "ender_dragon-default" {
                VoxelAdventure.sway(node,y:0.13,period:2.8)
            } else if name == "head" { VoxelAdventure.sway(node,y:0.07,period:7) }
        }
        models[key] = model
        return model.clone()
    }

    func locomotion(_ species: Species) throws -> (speed:Double,width:Double,height:Double) {
        if let found = locomotions[species] { return found }
        let aliases: [Species:String] = [.ironGolem:"iron_golem",.glowsquid:"glow_squid",.magma:"magma_cube",
            .illager:"pillager",.polarBear:"polar_bear",.witherSkeleton:"wither_skeleton",.piglinBrute:"piglin_brute",
            .zombifiedPiglin:"zombie_pigman",.golem:"copper_golem",.tropical:"tropicalfish",.villager:"villager_v2",
            .snowGolem:"snow_golem",.camelHusk:"camel_husk",.zombieNautilus:"zombie_nautilus",.happyGhast:"happy_ghast"]
        let path = "entities/"+(aliases[species] ?? species.rawValue)+".json"
        let data: Data
        do { data = try assets.file(path,behaviour:true) }
        catch AssetError.missing {
            let fallback = (speed:0.8,width:0.6,height:1.8)
            locomotions[species] = fallback
            return fallback
        }
        guard data.count <= 2*1024*1024,
              let object = try JSONSerialization.jsonObject(with:data,options:.json5Allowed) as? [String:Any],
              let entity = object["minecraft:entity"] as? [String:Any],
              var components = entity["components"] as? [String:Any] else { throw AssetError.model }
        if let raw = entity["component_groups"] {
            guard let groups = raw as? [String:Any] else { throw AssetError.model }
            let active: [Species:String] = [.enderman:"minecraft:enderman_calm",.armadillo:"minecraft:unrolled",.happyGhast:"minecraft:adult_mobile"]
            for name in ["adult","minecraft:adult",active[species]].compactMap({ $0 }) {
                if let raw = groups[name] {
                    guard let group = raw as? [String:Any] else { throw AssetError.model }
                    components.merge(group) { _,new in new }
                }
            }
        }
        func number(_ component: String, _ field: String, fallback: Double) throws -> Double {
            guard let raw = components[component] else { return fallback }
            guard let attributes = raw as? [String:Any] else { throw AssetError.model }
            guard let value = attributes[field] else { return fallback }
            if component == "minecraft:movement", let range = value as? [String:Any] {
                guard let lower = range["range_min"] as? NSNumber, let upper = range["range_max"] as? NSNumber,
                      CFGetTypeID(lower) != CFBooleanGetTypeID(), CFGetTypeID(upper) != CFBooleanGetTypeID(),
                      lower.doubleValue.isFinite, upper.doubleValue.isFinite,
                      (0...16).contains(lower.doubleValue), (lower.doubleValue...16).contains(upper.doubleValue) else { throw AssetError.model }
                return (lower.doubleValue+upper.doubleValue)/2
            }
            guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(), number.doubleValue.isFinite else { throw AssetError.model }
            return number.doubleValue
        }
        let movement = try number("minecraft:movement","value",fallback:0.25)
        let multiplier = try number("minecraft:behavior.random_stroll","speed_multiplier",fallback:1)
        let width = try number("minecraft:collision_box","width",fallback:0.6)
        let height = try number("minecraft:collision_box","height",fallback:1.8)
        guard (0...16).contains(movement), (0...16).contains(multiplier),
              (0.01...16).contains(width), (0.01...16).contains(height) else { throw AssetError.model }
        let result = (speed:min(2,movement*multiplier*4),width:width,height:height)
        locomotions[species] = result
        return result
    }

    // shortcut: original dimensions and calm speed guide scenery routes, use the game engine for full behaviour
    func wander(_ actor: SCNNode, model: SCNNode, species: Species, area: Biome, seed: Int,
                root: SCNNode, point: (Double,Double) -> SCNVector3) throws {
        let terrain = Terrain(biome:area), origin = actor.position, motion = try locomotion(species)
        guard motion.speed > 0 else { return }
        var legs: [(SCNNode,SCNVector3,Double)] = []
        model.enumerateChildNodes { node,_ in
            let name = node.name?.lowercased() ?? ""
            if name.contains("leg") {
                let sign: Double
                if let number = name.last?.wholeNumberValue { sign = [0,3].contains(number%4) ? 1 : -1 }
                else {
                    let side = name.contains("left") ? 1.0 : -1
                    sign = side * (["hind","back","rear"].contains(where:name.contains) ? -1 : 1)
                }
                legs.append((node,node.eulerAngles,sign))
            }
            if name == "head" {
                node.removeAllActions()
                VoxelAdventure.sway(node,y:0.16,period:7+Double(seed%7),phase:Double(seed)*1.7)
            }
        }
        var steps: [SCNAction] = [], start = origin, visited = [origin]
        for index in 0..<12 {
            var end = index >= 6 ? visited[11-index] : start
            for attempt in 0..<(index < 6 ? 12 : 0) {
                let angle = Terrain.random(seed,index*12+attempt,seed:85)*2 * .pi
                let distance = 1+Terrain.random(seed,index*12+attempt,seed:86)*4
                let candidate = point(origin.x+cos(angle)*distance,origin.z+sin(angle)*distance)
                if Self.walkable(from:start,to:candidate,species:species,terrain:terrain)
                    && Collision.clear(root,from:start,to:candidate,radius:motion.width/2,height:motion.height) { end = candidate; break }
            }
            if index < 6 { visited.append(end) }
            let length = hypot(end.x-start.x,end.z-start.z)
            steps.append(.wait(duration:1.5+Terrain.random(seed,index,seed:87)*4))
            if length>0.1 {
                let heading = atan2(end.x-start.x,end.z-start.z)
                steps.append(.rotateTo(x:0,y:heading,z:0,duration:0.35,usesShortestUnitArc:true))
                let a = start, b = end, duration = length/motion.speed
                let hopping = [.rabbit,.frog,.slime,.magma].contains(species)
                steps.append(.customAction(duration:duration) { node,time in
                    let t = min(1,Double(time)/duration)
                    node.position = .init(a.x+(b.x-a.x)*t,a.y+(b.y-a.y)*t,a.z+(b.z-a.z)*t)
                    let stride = sin(Double(time)*7)
                    for (leg,base,sign) in legs { leg.eulerAngles.x = base.x+stride*(species == .enderman ? 0.35 : 0.5)*sign }
                    if hopping { node.position.y += abs(stride)*(species == .slime || species == .magma ? 0.65 : 0.3) }
                    if species.swimming || species.flying { node.position.y += sin(Double(time)*2+Double(seed))*0.12 }
                })
                steps.append(.run { _ in for (leg,base,_) in legs { leg.eulerAngles = base } })
            }
            if species == .sheep, let head = model.childNode(withName:"head",recursively:true) {
                let base = head.eulerAngles.x
                steps.append(.customAction(duration:3) { _,time in head.eulerAngles.x = base+sin(Double(time)/3 * .pi)*0.8 })
            }
            if length <= 0.1 {
                steps.append(.rotateBy(x:0,y:0.3,z:0,duration:1.2))
                steps.append(.rotateBy(x:0,y:-0.3,z:0,duration:1.2))
            }
            start = end
        }
        actor.runAction(.repeatForever(.sequence(steps)))
    }

    static func classicChance(daylight: Double) -> Double { 0.10+0.05*(1-min(1,max(0,daylight))) }

    static func walkable(from start: SCNVector3, to end: SCNVector3, species: Species, terrain: Terrain) -> Bool {
        for index in 1...8 {
            let t = Double(index)/8, x = start.x+(end.x-start.x)*t, z = start.z+(end.z-start.z)*t
            let ground = terrain.height(x.rounded(),z.rounded())
            if species.swimming {
                if ground >= min(start.y,end.y)-0.5 { return false }
            } else if !species.flying && species != .strider {
                let bridge = [.witherSkeleton].contains(species)
                if terrain.biome.passage == nil && ground < 0.9 || !bridge && abs(ground-start.y)>1 { return false }
            }
        }
        return true
    }
}
