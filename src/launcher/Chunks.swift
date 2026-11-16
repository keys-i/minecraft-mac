import Foundation
import SceneKit

enum Seed {
    static func number(_ text: String) -> Int {
        if let value = Int(text) { return value }
        return Int(text.utf16.reduce(Int32(0)) { ($0 &* 31) &+ Int32($1) })
    }
}

enum ChunkError: Error, LocalizedError {
    case database(String), missing, format
    var errorDescription: String? {
        switch self {
        case .database(let message): return "The scenery world couldn’t be read: "+message
        case .missing: return "This part of the world hasn’t finished generating"
        case .format: return "This scenery world uses an unsupported chunk format"
        }
    }
}

// The asset queue owns this handle and closes it before the generator resumes
final class Database {
    private let handle: OpaquePointer
    private let options = leveldb_readoptions_create()!

    init(_ path: URL) throws {
        let configuration = leveldb_options_create()!
        defer { leveldb_options_destroy(configuration) }
        leveldb_options_set_create_if_missing(configuration,0)
        leveldb_options_set_paranoid_checks(configuration,1)
        var error: UnsafeMutablePointer<CChar>?
        let handle = leveldb_open(configuration,path.path,&error)
        if let error {
            defer { leveldb_free(error) }
            if let handle { leveldb_close(handle) }
            leveldb_readoptions_destroy(options)
            throw ChunkError.database(String(cString:error))
        }
        guard let handle else { leveldb_readoptions_destroy(options); throw ChunkError.format }
        self.handle = handle
        leveldb_readoptions_set_verify_checksums(options,1)
        leveldb_readoptions_set_fill_cache(options,0)
    }

    deinit { leveldb_readoptions_destroy(options); leveldb_close(handle) }

    func get(_ key: Data) throws -> Data? {
        var count = 0
        var error: UnsafeMutablePointer<CChar>?
        let pointer = key.withUnsafeBytes { bytes in
            leveldb_get(handle,options,bytes.baseAddress?.assumingMemoryBound(to:CChar.self),key.count,&count,&error)
        }
        defer { if let pointer { leveldb_free(pointer) } }
        if let error { defer { leveldb_free(error) }; throw ChunkError.database(String(cString:error)) }
        guard let pointer else { return nil }
        guard count<=8*1024*1024 else { throw ChunkError.format }
        return Data(bytes:pointer,count:count)
    }

    func chunk(_ key: Chunk, dimension: Int) throws -> VoxelChunk? {
        guard [0,1,2].contains(dimension), abs(key.x)<=1_875_000, abs(key.z)<=1_875_000 else { throw ChunkError.format }
        var prefix = Data()
        for coordinate in [key.x,key.z]+(dimension == 0 ? [] : [dimension]) {
            var value = Int32(coordinate).littleEndian
            withUnsafeBytes(of:&value) { prefix.append(contentsOf:$0) }
        }
        guard try get(prefix+Data([0x2C])) != nil else { return nil }
        var sections: [Int:Subchunk] = [:]
        for y in -4..<20 {
            if let data = try get(prefix+Data([0x2F,UInt8(bitPattern:Int8(y))])) {
                let section = try Subchunk(data)
                guard section.y == y else { throw ChunkError.format }
                sections[y] = section
            }
        }
        let biomeData = try get(prefix+Data([0x2B]))
        return try VoxelChunk(key:key,dimension:dimension,sections:sections,biomeData:biomeData)
    }
}

struct Block: Hashable, Codable {
    enum Render: String { case opaque, cutout, blend, fluid }

    let name: String
    let states: [String:String]

    init(name: String, states: [String:String] = [:]) { self.name = name; self.states = states }

    init(_ value: [String:Any]) throws {
        guard let name = value["name"] as? String, name.hasPrefix("minecraft:"), name.utf8.count<=160,
              let raw = value["states"] as? [String:Any], raw.count<=64 else { throw ChunkError.format }
        var states: [String:String] = [:]
        for (key,value) in raw {
            guard key.utf8.count<=128 else { throw ChunkError.format }
            if let string = value as? String, string.utf8.count<=256 { states[key] = string }
            else if let number = value as? NSNumber { states[key] = number.stringValue }
            else { throw ChunkError.format }
        }
        self.name = String(name.dropFirst(10)); self.states = states
    }

    var air: Bool { ["air","cave_air","void_air","structure_void"].contains(name) }
    var fluid: Bool { ["water","flowing_water","lava","flowing_lava","bubble_column"].contains(name) }
    var liquid: String? { name == "bubble_column" ? "water" : fluid ? name.replacingOccurrences(of:"flowing_",with:"") : nil }
    var snowHeight: Double {Double(min(7,max(0,Int(states["height"] ?? "0") ?? 0))+1)/8}
    var properties: [String:String] {
        var p = states
        if let axis = states["pillar_axis"] { p["axis"] = axis }
        if let axis = states["portal_axis"] {p["axis"] = axis}
        if let eye = states["end_portal_eye_bit"] {p["eye"] = eye == "1" ? "true" : "false"}
        if let facing = states["minecraft:cardinal_direction"] ?? states["cardinal_direction"] { p["facing"] = facing }
        if let facing = states["facing_direction"].flatMap(Int.init), (0..<6).contains(facing) {
            p["facing"] = ["down","up","north","south","west","east"][facing]
        }
        if let facing = states["direction"].flatMap(Int.init), (0..<4).contains(facing) { p["facing"] = ["south","west","north","east"][facing] }
        if let facing = states["weirdo_direction"].flatMap(Int.init), (0..<4).contains(facing) { p["facing"] = ["east","west","south","north"][facing] }
        if let half = states["upside_down_bit"] { p["half"] = half == "1" ? "top" : "bottom" }
        if let top = states["top_slot_bit"] { p["type"] = top == "1" ? "top" : "bottom" }
        if let half = states["upper_block_bit"] { p["half"] = half == "1" ? "upper" : "lower" }
        if let hinge = states["door_hinge_bit"] { p["hinge"] = hinge == "1" ? "right" : "left" }
        if let open = states["open_bit"] { p["open"] = open == "1" ? "true" : "false" }
        if let growth = states["growth"] { p["age"] = growth }
        if let depth = states["liquid_depth"] { p["level"] = depth }
        if let facing = states["torch_facing_direction"] { p["facing"] = facing == "top" ? "up" : facing }
        if let head = states["head_piece_bit"] { p["part"] = head == "1" ? "head" : "foot" }
        if let half = states["vertical_half"] ?? states["minecraft:vertical_half"] { p["half"] = half; p["type"] = half }
        return p
    }

    var model: String {
        if let liquid { return liquid }
        if name == "yellow_flower" { return "dandelion" }
        if name == "red_flower" { return states["flower_type"] ?? "poppy" }
        if name == "double_plant" {
            return ["sunflower":"sunflower","syringa":"lilac","grass":"tall_grass","fern":"large_fern","rose":"rose_bush","paeonia":"peony"][states["double_plant_type"] ?? "sunflower"] ?? name
        }
        if ["torch","soul_torch","redstone_torch","copper_torch"].contains(name), let facing = properties["facing"], facing != "up" {
            return name == "torch" ? "wall_torch" : name.replacingOccurrences(of:"_torch",with:"_wall_torch")
        }
        if name == "wooden_door" { return "oak_door" }
        if name == "iron_chain" { return "chain" }
        if name == "bed" { return "red_bed" }
        return name
    }

    var passable: Bool {
        let name = model
        return air || fluid || Self.plant(name) || ["torch","rail","vine","petals","crop","wheat","carrots","potatoes","beetroot","seagrass","kelp","redstone_wire","door","ladder"].contains(where:name.contains)
            || ["crimson_roots","warped_roots","hanging_roots","portal","nether_portal","end_portal","end_gateway","light_block"].contains(name)
    }

    static func plant(_ name: String) -> Bool {
        ["short_grass","tall_grass","tallgrass","fern","large_fern","dead_bush","deadbush","brown_mushroom","red_mushroom","cobweb","web",
         "dandelion","poppy","blue_orchid","allium","azure_bluet","oxeye_daisy","cornflower","lily_of_the_valley","wither_rose",
         "sunflower","lilac","rose_bush","peony","torchflower","pitcher_plant","open_eyeblossom","closed_eyeblossom"].contains(name)
            || ["reeds","sugar_cane","seagrass","tall_seagrass","kelp","kelp_plant","crimson_roots","warped_roots","nether_sprouts","pink_petals","wildflowers","leaf_litter","short_dry_grass","tall_dry_grass","bush","firefly_bush"].contains(name)
            || ["cave_vines","cave_vines_body_with_berries","cave_vines_head_with_berries","weeping_vines","twisting_vines","glow_lichen"].contains(name)
            || name.hasSuffix("_flower") || name.hasSuffix("_sapling") || name.hasSuffix("_tulip")
    }

    var render: Render {
        let name = model
        if fluid { return .fluid }
        if name.contains("glass") || ["ice","frosted_ice","slime","slime_block","honey_block","portal","nether_portal","end_portal","end_gateway"].contains(name) { return .blend }
        if Self.plant(name) || ["wheat","carrots","potatoes","beetroot"].contains(name)
            || ["leaves","azalea","scaffolding","chain","vine","rail","torch","door","ladder","bars","lantern","candle"].contains(where:name.contains)
            || ["mangrove_roots","hanging_roots","pointed_dripstone","waterlily","lily_pad","redstone_wire"].contains(name) { return .cutout }
        return .opaque
    }

    var opaque: Bool {
        guard !passable, render == .opaque else { return false }
        if model == "snow_layer" {return snowHeight == 1}
        if model.hasSuffix("_slab"), properties["type"] == "double" { return true }
        return !["stairs","slab","pane","fence","wall","bed","plate","carpet","banner","bell","brewing","chest","composter","cauldron","rod"].contains(where:model.contains)
            && !["farmland","grass_path","dirt_path","snow_layer"].contains(model)
    }
}

struct Palette {
    let blocks: [Block]
    let indices: [UInt16]
    let solids: [Bool]

    init(blocks: [Block], indices: [UInt16]) {
        self.blocks = blocks; self.indices = indices
        solids = blocks.map { !$0.fluid && !$0.passable }
    }

    func block(_ x: Int, _ y: Int, _ z: Int) -> Block { blocks[Int(indices[(x*16+z)*16+y])] }
    func solid(_ x: Int, _ y: Int, _ z: Int) -> Bool { solids[Int(indices[(x*16+z)*16+y])] }
}

private struct Storage {
    let data: Data
    var offset = 0
    var uniform = false
    mutating func byte() throws -> UInt8 {
        guard offset<data.count else { throw ChunkError.format }
        defer { offset += 1 }; return data[offset]
    }
    mutating func integer() throws -> UInt32 {
        guard offset<=data.count-4 else { throw ChunkError.format }
        defer { offset += 4 }
        return (0..<4).reduce(0) { $0 | UInt32(data[offset+$1])<<($1*8) }
    }
    mutating func indices(runtime: Bool = false) throws -> [UInt16] {
        let header = try byte(), bits = Int(header>>1)
        uniform = bits == 0
        guard header&1 == (runtime ? 1 : 0), [0,1,2,3,4,5,6,8,16].contains(bits) else { throw ChunkError.format }
        if bits == 0 { return Array(repeating:0,count:4096) }
        let perWord = 32/bits, mask = UInt32((1<<bits)-1)
        var indices: [UInt16] = []; indices.reserveCapacity(4096)
        for _ in 0..<((4096+perWord-1)/perWord) {
            let word = try integer()
            for item in 0..<perWord where indices.count<4096 { indices.append(UInt16((word>>(item*bits))&mask)) }
        }
        return indices
    }
}

struct Subchunk {
    let y: Int
    let layers: [Palette]

    init(_ data: Data) throws {
        guard data.count<=1024*1024 else { throw ChunkError.format }
        var source = Storage(data:data)
        let version = try source.byte()
        guard version == 9 else { throw ChunkError.format }
        let count = Int(try source.byte())
        y = Int(Int8(bitPattern:try source.byte()))
        guard count<=2, (-4..<20).contains(y) else { throw ChunkError.format }
        var layers: [Palette] = []
        for _ in 0..<count {
            let indices = try source.indices(), size = Int(try source.integer())
            guard (1...4096).contains(size) else { throw ChunkError.format }
            var blocks: [Block] = []; blocks.reserveCapacity(size)
            for _ in 0..<size { blocks.append(try Block(NBT.decode(data,offset:&source.offset,littleEndian:true))) }
            guard indices.allSatisfy({ Int($0)<size }) else { throw ChunkError.format }
            layers.append(Palette(blocks:blocks,indices:indices))
        }
        guard source.offset == data.count else { throw ChunkError.format }
        self.layers = layers
    }
}

struct VoxelChunk {
    let key: Chunk
    let dimension: Int
    let sections: [Int:Subchunk]
    let heights: [Int]
    let biomes: [Int:[Int32]]
    let surfaces: [Int]

    init(key: Chunk, dimension: Int, sections: [Int:Subchunk], biomeData: Data?) throws {
        self.key = key; self.dimension = dimension; self.sections = sections
        var surfaces = Array(repeating:dimension == 0 ? -65 : -1,count:256)
        for y in sections.keys.sorted(by:>) {
            guard let section = sections[y] else { continue }
            for x in 0..<16 { for z in 0..<16 where surfaces[x*16+z] == (dimension == 0 ? -65 : -1) {
                for dy in (0..<16).reversed() {
                    if section.layers.contains(where:{ $0.solid(x,dy,z) || $0.block(x,dy,z).fluid }) {
                        surfaces[x*16+z] = y*16+dy; break
                    }
                }
            } }
        }
        self.surfaces = surfaces
        guard let biomeData else { heights = []; biomes = [:]; return }
        guard biomeData.count>=512, biomeData.count<=1024*1024 else { throw ChunkError.format }
        heights = stride(from:0,to:512,by:2).map { Int(biomeData[$0]) | Int(biomeData[$0+1])<<8 }
        var source = Storage(data:biomeData,offset:512), biomes: [Int:[Int32]] = [:]
        var previous: [Int32]?
        let range = dimension == 0 ? -4..<20 : dimension == 1 ? 0..<8 : 0..<16
        for y in range where source.offset<biomeData.count {
            if biomeData[source.offset] == 255 {
                source.offset += 1
                guard let previous else { throw ChunkError.format }
                biomes[y] = previous
            } else {
                let indices = try source.indices(runtime:true)
                let count = source.uniform ? 1 : Int(try source.integer())
                guard (1...4096).contains(count) else { throw ChunkError.format }
                var palette: [Int32] = []
                for _ in 0..<count { palette.append(Int32(bitPattern:try source.integer())) }
                guard indices.allSatisfy({ Int($0)<count }) else { throw ChunkError.format }
                let values = indices.map { palette[Int($0)] }
                biomes[y] = values; previous = values
            }
        }
        guard source.offset == biomeData.count else { throw ChunkError.format }
        self.biomes = biomes
    }

    func block(_ x: Int, _ y: Int, _ z: Int, layer: Int = 0) -> Block? {
        guard (0..<16).contains(x), (0..<16).contains(z), (-64..<320).contains(y),
              let section = sections[Int(floor(Double(y)/16))], section.layers.indices.contains(layer) else { return nil }
        return section.layers[layer].block(x,(y%16+16)%16,z)
    }

    func biome(_ x: Int, _ y: Int, _ z: Int) -> Int32? {
        biomes[Int(floor(Double(y)/16))].map { $0[(x*16+z)*16+(y%16+16)%16] }
    }
}

// Immutable chunk snapshots are shared by rendering, collision and the map
struct WorldData {
    var chunks: [Chunk:VoxelChunk] = [:]
    var edits: [Chunk:[Cell:Block]] = [:]
    var columns: [Cell:Int] = [:]
    let dimension: Int

    static func key(_ x: Int, _ z: Int) -> Chunk {
        Chunk(x:Int(floor(Double(x)/16)),z:Int(floor(Double(z)/16)))
    }

    func block(_ x: Int, _ y: Int, _ z: Int, layer: Int = 0) -> Block? {
        let key = Self.key(x,z)
        if let block = edits[key]?[Cell(x:x,y:y,z:z)] { return layer == 0 ? block : nil }
        return chunks[key]?.block(x-key.x*16,y,z-key.z*16,layer:layer)
    }

    func biome(_ point: SCNVector3) -> Biome {
        let x = Int(floor(point.x)), z = Int(floor(point.z)), key = Self.key(x,z)
        let id = chunks[key]?.biome(x-key.x*16,Int(floor(point.y)),z-key.z*16)
        return Biome.bedrock(id,dimension:dimension)
    }

    func nativeBiome(_ point: SCNVector3) -> String? {
        let x = Int(floor(point.x)), z = Int(floor(point.z)), key = Self.key(x,z)
        guard let id = chunks[key]?.biome(x-key.x*16,Int(floor(point.y)),z-key.z*16) else {return nil}
        return Biome.identifiers[id]
    }

    func surface(_ x: Int, _ z: Int, below: Int = 320) -> Int? {
        let key = Self.key(x,z)
        guard let chunk = chunks[key] else { return nil }
        let edited = columns[Cell(x:x,y:0,z:z)]
        let top = max(chunk.surfaces[(x-key.x*16)*16+z-key.z*16],edited ?? -65)
        if edited == nil && top<below { return top }
        for y in stride(from:min(top,below-1),through:dimension == 0 ? -64 : 0,by:-1) {
            if (0...1).contains(where:{ layer in
                guard let block = self.block(x,y,z,layer:layer) else { return false }
                return !block.air && (!block.passable || block.fluid)
            }) { return y }
        }
        return nil
    }

    mutating func apply(_ changes: [Cell:Block]) {
        for (cell,block) in changes {
            edits[Self.key(cell.x,cell.z),default:[:]][cell] = block
            let column = Cell(x:cell.x,y:0,z:cell.z)
            columns[column] = max(columns[column] ?? -65,cell.y)
        }
    }

    func vacant(_ feet: SCNVector3, radius: Double = 0.3, height: Double = 1.8) -> Bool {
        let epsilon = 0.00001
        for x in Int(floor(feet.x-radius+epsilon))...Int(floor(feet.x+radius-epsilon)) {
            for z in Int(floor(feet.z-radius+epsilon))...Int(floor(feet.z+radius-epsilon)) {
                guard chunks[Self.key(x,z)] != nil else { return false }
                for y in Int(floor(feet.y+epsilon))...Int(floor(feet.y+height-epsilon)) {
                    guard let block = block(x,y,z), !block.passable else { continue }
                    let p = block.properties, name = block.model
                    if name == "pointed_dripstone" {
                        if feet.x+radius<=Double(x)+0.375 || feet.x-radius>=Double(x)+0.625 || feet.z+radius<=Double(z)+0.375 || feet.z-radius>=Double(z)+0.625 {continue}
                        return false
                    }
                    if name == "chain" {
                        let axis = p["axis"] ?? "y"
                        let low = SCNVector3(Double(x)+(axis == "x" ? 0 : 0.40625),Double(y)+(axis == "y" ? 0 : 0.40625),Double(z)+(axis == "z" ? 0 : 0.40625))
                        let high = SCNVector3(Double(x)+(axis == "x" ? 1 : 0.59375),Double(y)+(axis == "y" ? 1 : 0.59375),Double(z)+(axis == "z" ? 1 : 0.59375))
                        if feet.x+radius<=low.x || feet.x-radius>=high.x || feet.z+radius<=low.z || feet.z-radius>=high.z || feet.y+height<=low.y || feet.y>=high.y {continue}
                        return false
                    }
                    var bottom = 0.0, top = name == "snow_layer" ? block.snowHeight : 1.0
                    if name.hasSuffix("_slab"), p["type"] != "double" { bottom = p["type"] == "top" ? 0.5 : 0; top = bottom+0.5 }
                    if name == "farmland" || name.contains("_path") { top = 0.9375 }
                    if name == "end_portal_frame" {
                        top = p["eye"] == "true" && feet.x+radius>Double(x)+0.25 && feet.x-radius<Double(x)+0.75 && feet.z+radius>Double(z)+0.25 && feet.z-radius<Double(z)+0.75 ? 1 : 0.8125
                    }
                    if name.contains("carpet") { top = 0.0625 }
                    if feet.y>=Double(y)+top-epsilon || feet.y+height<=Double(y)+bottom+epsilon { continue }
                    if name.hasSuffix("_stairs"), feet.y>=Double(y)+(p["half"] == "top" ? 1 : 0.5)-epsilon {
                        let facing = p["facing"] ?? "north"
                        if facing == "north" && feet.z-radius>=Double(z)+0.5 || facing == "south" && feet.z+radius<=Double(z)+0.5
                            || facing == "west" && feet.x-radius>=Double(x)+0.5 || facing == "east" && feet.x+radius<=Double(x)+0.5 { continue }
                    }
                    return false
                }
            }
        }
        return true
    }

    func move(from start: SCNVector3, to end: SCNVector3, radius: Double = 0.3, height: Double = 1.8) -> SCNVector3 {
        let distance = hypot(hypot(end.x-start.x,end.z-start.z),end.y-start.y)
        let count = max(1,Int(ceil(distance/0.25)))
        var point = start
        for _ in 0..<count {
            for axis in 0..<3 {
                var next = point
                if axis == 0 { next.x += (end.x-start.x)/Double(count) }
                else if axis == 1 { next.y += (end.y-start.y)/Double(count) }
                else { next.z += (end.z-start.z)/Double(count) }
                if vacant(next,radius:radius,height:height) { point = next }
            }
        }
        return point
    }

    func medium(at point: SCNVector3) -> String? {
        let x = Int(floor(point.x)), y = Int(floor(point.y)), z = Int(floor(point.z))
        for layer in 0...1 {
            if let cell = block(x,y,z,layer:layer), cell.fluid {return cell.name.contains("lava") ? "lava" : "water"}
        }
        return nil
    }

    func immersed(_ feet: SCNVector3, radius: Double, height: Double, in medium: String) -> Bool {
        for x in [-radius*0.85,radius*0.85] {for z in [-radius*0.85,radius*0.85] {for y in [0.05,height*0.8] {
            if self.medium(at:.init(feet.x+x,feet.y+y,feet.z+z)) != medium {return false}
        } } }
        return vacant(feet,radius:radius,height:height)
    }

    // Support is separate from camera occupancy: passable liquids are never generic ground
    func standing(at feet: SCNVector3, radius: Double, height: Double, lava: Bool = false, water: Bool = false) -> SCNVector3? {
        var levels = Set<Double>()
        for x in [feet.x-radius*0.8,feet.x,feet.x+radius*0.8] {for z in [feet.z-radius*0.8,feet.z,feet.z+radius*0.8] {
            for y in stride(from:Int(floor(feet.y+1)),through:Int(floor(feet.y-2)),by:-1) {
                guard let cell = block(Int(floor(x)),y,Int(floor(z))) else {continue}
                if cell.fluid {
                    if lava && cell.name.contains("lava") {levels.insert(Double(y)+0.875)}
                    continue
                }
                guard !cell.passable else {continue}
                let p = cell.properties, name = cell.model
                var top = name == "snow_layer" ? cell.snowHeight : 1.0
                if name == "farmland" || name.contains("_path") {top = 0.9375}
                if name.hasSuffix("_slab"), p["type"] != "double", p["type"] != "top" {top = 0.5}
                if name.hasSuffix("_stairs"), p["half"] != "top" {levels.insert(Double(y)+0.5)}
                if name.contains("carpet") {top = 0.0625}
                levels.insert(Double(y)+top)
            }
        } }
        for y in levels.sorted(by:>) where y<=feet.y+1.001 && y>=feet.y-1.001 {
            let point = SCNVector3(feet.x,y,feet.z)
            guard vacant(point,radius:radius,height:height) else {continue}
            let liquid = medium(at:.init(feet.x,y+0.05,feet.z))
            if liquid == "water" && !water || liquid == "lava" && !lava {continue}
            var supported = true
            for dx in [-radius*0.8,0,radius*0.8] {for dz in [-radius*0.8,0,radius*0.8] {
                let probe = SCNVector3(point.x+dx,point.y-0.03,point.z+dz)
                if let liquid = medium(at:probe) {
                    if !lava || liquid != "lava" {supported = false}
                } else if vacant(probe,radius:0.01,height:0.02) {supported = false}
            } }
            if supported {return point}
        }
        return nil
    }

    func walk(from start: SCNVector3, to end: SCNVector3, radius: Double, height: Double, lava: Bool = false, water: Bool = false) -> SCNVector3 {
        let distance = hypot(end.x-start.x,end.z-start.z), count = max(1,Int(ceil(distance/0.2)))
        var point = start
        for _ in 0..<count {
            let candidate = SCNVector3(point.x+(end.x-start.x)/Double(count),point.y,point.z+(end.z-start.z)/Double(count))
            guard let supported = standing(at:candidate,radius:radius,height:height,lava:lava,water:water),
                  vacant(.init(point.x,max(point.y,supported.y),point.z),radius:radius,height:height) else {break}
            point = supported
        }
        return point
    }

    func node(_ key: Chunk, assets: Assets, cancelled: () -> Bool = {false}) throws -> SCNNode {
        guard chunks[key] != nil else { throw ChunkError.missing }
        var palette: [[String:Any]] = [], indices: [Block:Int] = [:], cells: [Int:Int] = [:], fluids: [Int:Int] = [:], overlays: [Int:Int] = [:]
        var levels: [Chunk:[Int]] = [:]
        for dx in -1...1 { for dz in -1...1 {
            let nearby = Chunk(x:key.x+dx,z:key.z+dz)
            let changed = edits[nearby]?.keys.map {Int(floor(Double($0.y)/16))} ?? []
            levels[nearby] = Set(chunks[nearby]?.sections.keys.map {$0} ?? []).union(changed).sorted()
        } }
        for dx in -1...16 { for dz in -1...16 {
            if cancelled() { throw CancellationError() }
            let x = key.x*16+dx, z = key.z*16+dz
            for sy in levels[Self.key(x,z)] ?? [] {
                for dy in 0..<16 {
                    let y = sy*16+dy
                    for layer in 0...1 {
                        guard let block = block(x,y,z,layer:layer), !block.air else { continue }
                        guard layer == 0 || block.fluid || block.passable else { throw ChunkError.format }
                        let index: Int
                        if let existing = indices[block] { index = existing }
                        else {
                            index = palette.count; indices[block] = index
                            palette.append(["Name":"minecraft:"+block.model,"Properties":block.properties])
                        }
                        let cell = dx+1+18*(dz+1+18*(y+64))
                        if block.fluid { fluids[cell] = index }
                        else if layer == 0 { cells[cell] = index }
                        else {overlays[cell] = index}
                    }
                }
            }
        } }
        let node = try Structures.volume("chunk-\(key.x)-\(key.z)",size:[18,384,18],palette:palette,blocks:cells,fluids:fluids,assets:assets,interior:true,
            biome:{ x,y,z in self.biome(.init(Double(key.x*16+x-1),Double(y-64),Double(key.z*16+z-1))) },
            identity:{ x,y,z in self.nativeBiome(.init(Double(key.x*16+x-1),Double(y-64),Double(key.z*16+z-1))) },cancelled:cancelled)
        if !overlays.isEmpty {
            // Bedrock also stores snow-covered vegetation in its secondary block layer
            let overlay = try Structures.volume("chunk-overlays",size:[18,384,18],palette:palette,blocks:overlays,context:cells,
                assets:assets,interior:true,cancelled:cancelled)
            overlay.name = "chunk-overlays"; overlay.position = SCNVector3Zero; node.addChildNode(overlay)
        }
        node.position = .init(Double(key.x*16)-1,-64,Double(key.z*16)-1)
        return node
    }
}
