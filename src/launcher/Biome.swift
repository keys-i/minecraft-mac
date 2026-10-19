import Foundation

// Areas include structures as well as biomes so the journey can visit both
// Sift names describe original scenery rather than an announced biome list

enum Biome: String, CaseIterable {
    case meadow = "Meadow village", forest = "Oak forest", cherry = "Cherry grove"
    case snow = "Snowy taiga", peaks = "Jagged peaks", desert = "Desert temple"
    case badlands = "Badlands mineshaft", mangrove = "Mangrove swamp", jungle = "Jungle temple"
    case mushroom = "Mushroom fields", pale = "Pale Garden at dusk", coast = "Coast & shipwreck"
    case lush = "Lush caves", deep = "Deep Dark · Ancient City"
    case wastes = "Nether Wastes · Fortress", crimson = "Crimson Forest · Bastion"
    case warped = "Warped Forest", soul = "Soul Sand Valley", basalt = "Basalt Deltas"
    case central = "Central island", highlands = "End highlands", midlands = "End midlands"
    case islands = "Small End islands", barrens = "End barrens", city = "End City & ship"
    case terraces = "Coral terraces", grove = "Luminous grove", valley = "Rift valley"
    case shards = "Floating shards", ruins = "Illager expedition", sculk = "Sculk fissures"

    var underground: Bool { self == .lush || self == .deep }

    var residents: [Species] {
        switch self {
        case .meadow: return [.cow, .sheep, .chicken, .villager, .golem, .ironGolem]
        case .forest: return [.pig, .wolf, .bee, .creeper]
        case .cherry: return [.bee, .sheep, .rabbit]
        case .snow: return [.fox, .wolf, .rabbit]
        case .peaks: return [.goat, .llama]
        case .desert: return [.camel, .rabbit, .villager]
        case .badlands: return [.armadillo, .rabbit, .spider]
        case .mangrove: return [.frog, .slime, .bee]
        case .jungle: return [.panda, .parrot, .ocelot]
        case .mushroom: return [.mooshroom]
        case .pale: return [.creaking, .spider, .zombie]
        case .coast: return [.turtle, .dolphin, .squid]
        case .lush: return [.axolotl, .glowsquid, .bat]
        case .deep: return [.warden]
        case .wastes: return [.piglin, .strider, .blaze]
        case .crimson: return [.hoglin, .piglin, .strider]
        case .warped: return [.enderman, .strider]
        case .soul: return [.skeleton, .ghast]
        case .basalt: return [.magma, .strider]
        case .central: return [.enderman, .endermite]
        case .highlands, .midlands, .islands, .barrens: return [.enderman, .endermite]
        case .city: return [.shulker, .enderman]
        case .terraces, .grove: return [.allay, .illager]
        case .valley, .shards: return [.allay, .vex]
        case .ruins: return [.illager, .vindicator, .allay]
        case .sculk: return [.illager, .vex, .allay]
        }
    }

    var surface: String {
        switch self {
        case .snow, .peaks: return "snow"
        case .desert, .coast: return "sand"
        case .badlands: return "red_sand"
        case .mangrove: return "mud"
        case .mushroom: return "mycelium"
        case .lush: return "moss_block"
        case .deep: return "sculk"
        case .wastes: return "netherrack"
        case .crimson: return "crimson_nylium"
        case .warped: return "warped_nylium"
        case .soul: return "soul_sand"
        case .basalt: return "basalt"
        case .central, .highlands, .midlands, .islands, .barrens, .city: return "end_stone"
        case .terraces, .ruins: return "pink_terracotta"
        case .grove: return "moss_block"
        case .valley, .shards: return "purple_terracotta"
        case .sculk: return "sculk"
        default: return "grass_block"
        }
    }

    var tree: String? {
        switch self {
        case .meadow, .forest: return "oak"
        case .cherry, .grove: return "cherry"
        case .snow: return "spruce"
        case .mangrove: return "mangrove"
        case .jungle: return "jungle"
        case .pale: return "pale_oak"
        default: return nil
        }
    }

    var sky: UInt32 {
        switch self {
        case .snow, .peaks: return 0xAABCC9
        case .desert, .badlands: return 0xD6BF9B
        case .pale: return 0x444B58
        case .lush: return 0x263D42
        case .deep: return 0x101E2C
        case .wastes, .crimson, .basalt: return 0x4B2536
        case .warped: return 0x24474B
        case .soul: return 0x40535B
        case .central, .highlands, .midlands, .islands, .barrens, .city: return 0x29243E
        case .terraces, .grove, .valley, .shards, .ruins, .sculk: return 0x8BAFBD
        default: return 0x9EC9DF
        }
    }
}

extension World {
    var biomes: [Biome] {
        switch self {
        case .overworld: return [.meadow, .forest, .cherry, .snow, .peaks, .desert, .badlands,
                                .mangrove, .jungle, .mushroom, .pale, .coast, .lush, .deep]
        case .nether: return [.wastes, .crimson, .warped, .soul, .basalt]
        case .end: return [.central, .highlands, .midlands, .islands, .barrens, .city]
        case .sift: return [.terraces, .grove, .valley, .shards, .ruins, .sculk]
        }
    }

    func index(_ biome: Int) -> Int { min(biomes.count - 1, max(0, biome)) }
    func page(_ biome: Int) -> Int { index(biome) / 3 }
    func areas(_ biome: Int) -> [Biome] { (0..<3).map { biomes[index(page(biome) * 3 + $0)] } }
}
