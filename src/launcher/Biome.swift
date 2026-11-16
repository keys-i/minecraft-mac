import Foundation

// Areas include structures as well as biomes so the journey can visit both
// Sift names describe original scenery rather than an announced biome list

enum Biome: String, CaseIterable {
    case meadow = "Meadow village", forest = "Oak forest", cherry = "Cherry grove"
    case snow = "Snowy taiga", peaks = "Jagged peaks", desert = "Desert temple"
    case badlands = "Badlands mineshaft", mangrove = "Mangrove swamp", jungle = "Jungle temple"
    case mushroom = "Mushroom fields", pale = "Pale Garden at dusk", coast = "Coast & shipwreck"
    case savanna = "Savanna Outpost", swamp = "Swamp Witch hut", reef = "Warm ocean Coral reef"
    case mansion = "Dark forest Woodland mansion", trial = "Trial Chambers", dripstone = "Dripstone caves"
    case river = "River & birch woods", ice = "Ice spikes Frozen ocean", monument = "Deep ocean Monument"
    case lush = "Lush caves", deep = "Deep Dark Ancient City"
    case mine = "Abandoned mineshaft", stronghold = "Stronghold Portal room"
    case wastes = "Nether Wastes Fortress", crimson = "Crimson Forest Bastion"
    case warped = "Warped Forest", soul = "Soul Sand Valley", basalt = "Basalt Deltas"
    case central = "Central island", highlands = "End highlands", midlands = "End midlands"
    case islands = "Small End islands", barrens = "End barrens", city = "End City & ship"
    case terraces = "Coral terraces", grove = "Luminous grove", valley = "Rift valley"
    case shards = "Floating shards", ruins = "Illager expedition", sculk = "Sculk fissures"
    case sulfur = "Sulfur caves"

    var underground: Bool { [.lush, .deep, .trial, .dripstone, .mine, .stronghold,.sulfur].contains(self) }

    var level: Double { [.lush,.deep,.trial,.dripstone,.sulfur].contains(self) ? -64 : 0 }

    var cover: Biome? {
        switch self {
        case .lush: return .jungle
        case .deep: return .forest
        case .trial: return .savanna
        case .dripstone: return .badlands
        case .sulfur: return .forest
        default: return nil
        }
    }

    var passage: Passage? { self == .mine ? .mine : self == .stronghold ? .stronghold : nil }

    var residents: [Species] {
        switch self {
        case .meadow: return [.cow, .sheep, .chicken, .villager, .golem, .ironGolem, .cat, .pig, .horse, .donkey, .mule, .trader, .traderLlama]
        case .forest: return [.pig, .wolf, .bee, .creeper, .sniffer]
        case .cherry: return [.bee, .sheep, .rabbit]
        case .snow: return [.fox, .wolf, .rabbit]
        case .peaks: return [.goat, .llama]
        case .desert: return [.camel, .rabbit, .villager, .husk, .camelHusk, .parched]
        case .badlands: return [.armadillo, .caveSpider]
        case .mangrove: return [.frog, .slime, .bee, .tadpole]
        case .jungle: return [.panda, .parrot, .ocelot]
        case .mushroom: return [.mooshroom]
        case .pale: return [.creaking, .spider, .zombie]
        case .coast: return [.turtle, .dolphin, .squid, .drowned, .cod, .nautilus]
        case .savanna: return [.horse, .llama, .armadillo, .illager, .ravager, .donkey, .zombieHorse, .phantom]
        case .swamp: return [.witch, .cat, .frog, .slime, .bogged, .tadpole, .zombieVillager]
        case .reef: return [.tropical, .pufferfish, .dolphin, .turtle]
        case .river: return [.salmon, .squid, .drowned, .bee, .cow]
        case .ice: return [.polarBear, .rabbit, .snowGolem, .stray]
        case .monument: return [.guardian, .elderGuardian, .squid, .cod, .zombieNautilus]
        case .mansion: return [.vindicator, .evoker, .allay, .spider]
        case .trial: return [.breeze, .bogged, .skeleton, .spider, .silverfish]
        case .dripstone: return [.bat, .spider, .zombie]
        case .lush: return [.axolotl, .glowsquid, .bat]
        case .deep: return [.warden]
        case .mine: return [.bat, .caveSpider]
        case .stronghold: return [.silverfish]
        case .wastes: return [.piglin, .zombifiedPiglin, .strider, .blaze, .witherSkeleton, .zoglin]
        case .crimson: return [.hoglin, .piglin, .piglinBrute, .strider]
        case .warped: return [.enderman, .strider, .happyGhast]
        case .soul: return [.skeleton, .ghast, .wither]
        case .basalt: return [.magma, .strider]
        case .central: return [.enderman, .endermite]
        case .highlands, .midlands, .islands, .barrens: return [.enderman, .endermite]
        case .city: return [.shulker, .enderman]
        case .terraces, .grove: return [.allay, .illager]
        case .valley, .shards: return [.allay, .vex]
        case .ruins: return [.illager, .vindicator, .allay]
        case .sculk: return [.illager, .vex, .allay]
        case .sulfur: return [.sulfurCube,.bat]
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
        case .sulfur: return "sulfur"
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
        case .sulfur: return 0x33483A
        case .wastes, .crimson, .basalt: return 0x4B2536
        case .warped: return 0x24474B
        case .soul: return 0x40535B
        case .central, .highlands, .midlands, .islands, .barrens, .city: return 0x0F0B16
        case .terraces, .grove, .valley, .shards, .ruins, .sculk: return 0x8BAFBD
        default: return 0x78A7FF
        }
    }
}

extension World {
    var dimension: Int? { self == .overworld ? 0 : self == .nether ? 1 : self == .end ? 2 : nil }
    var biomes: [Biome] {
        switch self {
        case .overworld: return [.meadow, .forest, .cherry, .snow, .peaks, .desert, .badlands,
                                .savanna, .mangrove, .swamp, .jungle, .mushroom, .pale, .mansion, .river, .coast, .reef, .monument, .ice, .lush, .dripstone, .trial, .deep, .mine, .stronghold,.sulfur]
        case .nether: return [.wastes, .crimson, .warped, .soul, .basalt]
        case .end: return [.central, .highlands, .midlands, .islands, .barrens, .city]
        case .sift: return [.terraces, .grove, .valley, .shards, .ruins, .sculk]
        }
    }

    func index(_ biome: Int) -> Int { min(biomes.count - 1, max(0, biome)) }
}

extension Biome {
    static let identifiers: [Int32:String] = [
        0:"ocean",
        10:"legacy_frozen_ocean",
        24:"deep_ocean",
        46:"frozen_ocean",
        47:"deep_frozen_ocean",
        44:"cold_ocean",
        45:"deep_cold_ocean",
        42:"lukewarm_ocean",
        43:"deep_lukewarm_ocean",
        40:"warm_ocean",
        41:"deep_warm_ocean",
        7:"river",
        11:"frozen_river",
        16:"beach",
        25:"stone_beach",
        26:"cold_beach",
        4:"forest",
        18:"forest_hills",
        132:"flower_forest",
        27:"birch_forest",
        28:"birch_forest_hills",
        155:"birch_forest_mutated",
        156:"birch_forest_hills_mutated",
        29:"roofed_forest",
        157:"roofed_forest_mutated",
        193:"pale_garden",
        21:"jungle",
        22:"jungle_hills",
        149:"jungle_mutated",
        23:"jungle_edge",
        151:"jungle_edge_mutated",
        48:"bamboo_jungle",
        49:"bamboo_jungle_hills",
        5:"taiga",
        19:"taiga_hills",
        133:"taiga_mutated",
        30:"cold_taiga",
        31:"cold_taiga_hills",
        158:"cold_taiga_mutated",
        32:"mega_taiga",
        33:"mega_taiga_hills",
        160:"redwood_taiga_mutated",
        161:"redwood_taiga_hills_mutated",
        14:"mushroom_island",
        15:"mushroom_island_shore",
        6:"swampland",
        134:"swampland_mutated",
        191:"mangrove_swamp",
        35:"savanna",
        36:"savanna_plateau",
        163:"savanna_mutated",
        164:"savanna_plateau_mutated",
        1:"plains",
        129:"sunflower_plains",
        2:"desert",
        17:"desert_hills",
        130:"desert_mutated",
        12:"ice_plains",
        13:"ice_mountains",
        140:"ice_plains_spikes",
        3:"extreme_hills",
        34:"extreme_hills_plus_trees",
        131:"extreme_hills_mutated",
        162:"extreme_hills_plus_trees_mutated",
        20:"extreme_hills_edge",
        37:"mesa",
        39:"mesa_plateau",
        167:"mesa_plateau_mutated",
        38:"mesa_plateau_stone",
        166:"mesa_plateau_stone_mutated",
        165:"mesa_bryce",
        186:"meadow",
        192:"cherry_grove",
        185:"grove",
        184:"snowy_slopes",
        182:"jagged_peaks",
        183:"frozen_peaks",
        189:"stony_peaks",
        187:"lush_caves",
        188:"dripstone_caves",
        190:"deep_dark",
        194:"sulfur_caves",
        195:"dappled_forest",
        196:"ice_caves",
        8:"hell",
        179:"crimson_forest",
        180:"warped_forest",
        178:"soulsand_valley",
        181:"basalt_deltas",
        9:"the_end"]

    // Bedrock's stable numeric biome IDs identify the generated cells, not a hand-authored grid
    static func bedrock(_ id: Int32?, dimension: Int) -> Biome {
        switch id {
        case 2,17,130: return .desert
        case 4,18,132: return .forest
        case 5,19,30,31,32,33,133,158,160,161: return .snow
        case 6,134: return .swamp
        case 7,11: return .river
        case 8: return .wastes
        case 9: return .central
        case 10,12,13,46,47,140: return .ice
        case 14,15: return .mushroom
        case 16,25,26: return .coast
        case 21,22,23,48,49,149,151: return .jungle
        case 27,28,155,156: return .river
        case 29,157: return .mansion
        case 35,36,163,164: return .savanna
        case 37,38,39,165,166,167: return .badlands
        case 0,24,40,41,42,43,44,45: return .reef
        case 178: return .soul
        case 179: return .crimson
        case 180: return .warped
        case 181: return .basalt
        case 3,20,34,131,162,182,183,184,185,189: return .peaks
        case 187: return .lush
        case 188: return .dripstone
        case 190: return .deep
        case 191: return .mangrove
        case 194: return .sulfur
        case 192: return .cherry
        case 193: return .pale
        default: return dimension == 1 ? .wastes : dimension == 2 ? .central : .meadow
        }
    }

    var locator: (kind:String,id:String)? {
        let names: [Biome:(String,String)] = [
            .meadow:("structure","village"),.forest:("biome","forest"),.cherry:("biome","cherry_grove"),
            .snow:("biome","taiga"),.peaks:("biome","jagged_peaks"),.desert:("structure","temple"),
            .badlands:("biome","mesa"),.mangrove:("biome","mangrove_swamp"),.jungle:("biome","jungle"),
            .mushroom:("biome","mushroom_island"),.pale:("biome","pale_garden"),.coast:("structure","shipwreck"),
            .savanna:("structure","pillager_outpost"),.swamp:("biome","swampland"),.reef:("biome","warm_ocean"),
            .mansion:("structure","mansion"),.trial:("structure","trial_chambers"),.dripstone:("biome","dripstone_caves"),
            .river:("biome","river"),.ice:("biome","ice_plains_spikes"),.monument:("structure","monument"),
            .lush:("biome","lush_caves"),.deep:("structure","ancient_city"),.mine:("structure","mineshaft"),
            .stronghold:("structure","stronghold"),.wastes:("structure","fortress"),.crimson:("biome","crimson_forest"),
            .warped:("biome","warped_forest"),.soul:("biome","soulsand_valley"),.basalt:("biome","basalt_deltas"),
            .city:("structure","end_city")]
        return names[self].map { ($0.0,"minecraft:"+$0.1) }
    }
}
