import Foundation

// Areas include structures as well as biomes so the journey can visit both
// Sift names describe original scenery rather than an announced biome list

enum Biome: String, CaseIterable {
    case meadow = "Meadow village", forest = "Oak forest", cherry = "Cherry grove"
    case snow = "Snowy taiga", peaks = "Jagged peaks", desert = "Desert temple"
    case badlands = "Badlands mineshaft", mangrove = "Mangrove swamp", jungle = "Jungle temple"
    case mushroom = "Mushroom fields", pale = "Pale Garden at dusk", coast = "Ocean ruins"
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
        case .meadow: return [.cow, .sheep, .villager, .golem]
        case .forest: return [.pig, .wolf, .fox, .bee]
        case .cherry: return [.bee, .sheep, .rabbit]
        case .snow: return [.fox, .wolf, .rabbit]
        case .peaks: return [.goat, .llama]
        case .desert: return [.camel, .rabbit, .villager]
        case .badlands: return [.armadillo, .rabbit, .spider]
        case .mangrove: return [.frog, .slime, .bee]
        case .jungle: return [.panda, .parrot, .ocelot]
        case .mushroom: return [.mooshroom, .rabbit]
        case .pale: return [.creaking, .spider]
        case .coast: return [.turtle, .dolphin, .squid]
        case .lush: return [.axolotl, .glowsquid, .bat]
        case .deep: return [.warden, .bat]
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

    // Ground, foliage and sky carry habitat identity before any landmark appears
    var ground: UInt32 {
        switch self {
        case .snow, .peaks: return 0xE1E9E6
        case .desert, .coast: return 0xDBC28A
        case .badlands: return 0xBA663E
        case .mangrove: return 0x536747
        case .jungle: return 0x4E993C
        case .mushroom: return 0x8F7B8E
        case .pale: return 0x8A9890
        case .lush: return 0x4C8156
        case .deep: return 0x273D42
        case .wastes: return 0x73343D
        case .crimson: return 0xA23B48
        case .warped: return 0x30988C
        case .soul: return 0x816A5A
        case .basalt: return 0x50515C
        case .central, .highlands, .midlands, .islands, .barrens: return 0xD1CB95
        case .city: return 0xC9BF95
        case .terraces: return 0xE2AD9F
        case .grove: return 0x7CC7AF
        case .valley: return 0xB49ACA
        case .shards: return 0x83B7CF
        case .ruins: return 0xCCAD9F
        case .sculk: return 0x377A83
        default: return 0x76A449
        }
    }

    var foliage: UInt32 {
        switch self {
        case .cherry: return 0xE9AAC9
        case .snow, .peaks: return 0x447463
        case .mangrove: return 0x557749
        case .jungle: return 0x36893B
        case .mushroom: return 0xB93D45
        case .pale: return 0xB6C0B7
        case .lush: return 0x7FA657
        case .deep: return 0x2C7074
        case .crimson: return 0xBC3548
        case .warped: return 0x35B4A8
        case .central, .highlands, .midlands, .islands, .barrens, .city: return 0x795884
        case .terraces, .ruins: return 0xEFA9C8
        case .grove: return 0x65D8BC
        case .valley, .sculk: return 0xBE9BDF
        case .shards: return 0xBDDDEA
        default: return 0x4D8246
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
