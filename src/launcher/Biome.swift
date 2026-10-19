import Foundation

// Areas include structures as well as biomes so the journey can visit both
// Sift names describe original scenery rather than an announced biome list

enum Biome: String, CaseIterable {
    case meadow = "Meadow village", forest = "Oak forest", cherry = "Cherry grove"
    case snow = "Snowy taiga", peaks = "Jagged peaks", desert = "Desert temple"
    case badlands = "Badlands mineshaft", mangrove = "Mangrove swamp", jungle = "Jungle temple"
    case mushroom = "Mushroom fields", pale = "Pale Garden at dusk", coast = "Coast & shipwreck"
    case savanna = "Savanna · Outpost", swamp = "Swamp · Witch hut", reef = "Warm ocean · Coral reef"
    case mansion = "Dark forest · Woodland mansion", trial = "Trial Chambers", dripstone = "Dripstone caves"
    case river = "River & birch woods", ice = "Ice spikes · Frozen ocean", monument = "Deep ocean · Monument"
    case lush = "Lush caves", deep = "Deep Dark · Ancient City"
    case wastes = "Nether Wastes · Fortress", crimson = "Crimson Forest · Bastion"
    case warped = "Warped Forest", soul = "Soul Sand Valley", basalt = "Basalt Deltas"
    case central = "Central island", highlands = "End highlands", midlands = "End midlands"
    case islands = "Small End islands", barrens = "End barrens", city = "End City & ship"
    case terraces = "Coral terraces", grove = "Luminous grove", valley = "Rift valley"
    case shards = "Floating shards", ruins = "Illager expedition", sculk = "Sculk fissures"

    var underground: Bool { [.lush, .deep, .trial, .dripstone].contains(self) }

    var residents: [Species] {
        switch self {
        case .meadow: return [.cow, .sheep, .chicken, .villager, .golem, .ironGolem, .cat]
        case .forest: return [.pig, .wolf, .bee, .creeper, .sniffer]
        case .cherry: return [.bee, .sheep, .rabbit]
        case .snow: return [.fox, .wolf, .rabbit]
        case .peaks: return [.goat, .llama]
        case .desert: return [.camel, .rabbit, .villager, .husk]
        case .badlands: return [.armadillo, .rabbit, .spider]
        case .mangrove: return [.frog, .slime, .bee]
        case .jungle: return [.panda, .parrot, .ocelot]
        case .mushroom: return [.mooshroom]
        case .pale: return [.creaking, .spider, .zombie]
        case .coast: return [.turtle, .dolphin, .squid, .drowned, .cod]
        case .savanna: return [.horse, .llama, .armadillo, .illager, .ravager]
        case .swamp: return [.witch, .frog, .slime, .bogged]
        case .reef: return [.tropical, .dolphin, .turtle]
        case .river: return [.salmon, .squid, .drowned, .bee, .cow]
        case .ice: return [.polarBear, .rabbit, .snowGolem]
        case .monument: return [.guardian, .squid, .cod]
        case .mansion: return [.vindicator, .illager, .allay, .spider]
        case .trial: return [.breeze, .bogged, .skeleton, .spider, .silverfish]
        case .dripstone: return [.bat, .spider, .zombie]
        case .lush: return [.axolotl, .glowsquid, .bat]
        case .deep: return [.warden]
        case .wastes: return [.piglin, .zombifiedPiglin, .strider, .blaze, .witherSkeleton]
        case .crimson: return [.hoglin, .piglin, .piglinBrute, .strider]
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
        case .snow, .peaks, .ice: return "snow"
        case .desert, .coast, .reef, .monument: return "sand"
        case .trial: return "tuff_bricks"
        case .dripstone: return "dripstone_block"
        case .badlands: return "red_sand"
        case .mangrove: return "mud"
        case .swamp: return "grass_block"
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
        case .river: return "birch"
        case .cherry, .grove: return "cherry"
        case .snow: return "spruce"
        case .savanna: return "acacia"
        case .swamp: return "oak"
        case .mansion: return "dark_oak"
        case .mangrove: return "mangrove"
        case .jungle: return "jungle"
        case .pale: return "pale_oak"
        default: return nil
        }
    }

    var sky: UInt32 {
        switch self {
        case .snow, .peaks, .ice: return 0xAABCC9
        case .desert, .badlands: return 0xD6BF9B
        case .pale: return 0x444B58
        case .lush: return 0x263D42
        case .trial: return 0x263D43
        case .dripstone: return 0x342F2B
        case .swamp, .mansion: return 0x81999A
        case .reef,.monument: return 0x5D9BAF
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
                                .savanna, .mangrove, .swamp, .jungle, .mushroom, .pale, .mansion, .river, .coast, .reef, .monument, .ice, .lush, .dripstone, .trial, .deep]
        case .nether: return [.wastes, .crimson, .warped, .soul, .basalt]
        case .end: return [.central, .highlands, .midlands, .islands, .barrens, .city]
        case .sift: return [.terraces, .grove, .valley, .shards, .ruins, .sculk]
        }
    }

    func index(_ biome: Int) -> Int { min(biomes.count - 1, max(0, biome)) }
}
