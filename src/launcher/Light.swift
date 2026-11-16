import AppKit
import SceneKit
import simd

// One immutable light field is baked on the asset queue and released after its chunk mesh
struct Light {
    struct Metrics {
        let cells: Int
        let visits: Int
        let seconds: Double
        var residentBytes: Int { cells }
        var workingBytes: Int { cells * 6 }
    }

    enum Failure: Error { case budget, geometry }

    private static let halo = 15
    private static let width = 16 + halo * 2
    private static let plane = width * width
    private static let curve: [Float] = (0...15).map {
        let black = pow(0.8,15.0)
        return Float((pow(0.8,Double(15-$0))-black)/(1-black))
    }

    private let x: Int
    private let y: Int
    private let z: Int
    private let height: Int
    private let values: [UInt8]
    private let ambient: Float
    let metrics: Metrics

    init(data: WorldData, key: Chunk, cancelled: () -> Bool = { false }) throws {
        let started = ProcessInfo.processInfo.systemUptime
        guard [0,1,2].contains(data.dimension), (-1_875_000...1_875_000).contains(key.x),
              (-1_875_000...1_875_000).contains(key.z) else { throw ChunkError.format }
        guard data.chunks[key] != nil else { throw ChunkError.missing }
        if cancelled() { throw CancellationError() }
        x = key.x * 16 - Self.halo; z = key.z * 16 - Self.halo
        y = data.dimension == 0 ? -64 : 0
        height = data.dimension == 0 ? 384 : data.dimension == 1 ? 128 : 256
        ambient = data.dimension == 0 ? 0.012 : data.dimension == 1 ? 0.10 : 0.14
        var grid = Grid(x:x,y:y,z:z,height:height)
        try grid.load(data,key:key,cancelled:cancelled)
        try grid.propagate(sky:false,cancelled:cancelled)
        if data.dimension == 0 {
            try grid.sunlight(cancelled:cancelled)
            try grid.propagate(sky:true,cancelled:cancelled)
        }
        values = grid.values
        metrics = Metrics(cells:values.count,visits:grid.visits,seconds:ProcessInfo.processInfo.systemUptime-started)
    }

    // Raw levels make occlusion and attenuation verifiable without a renderer
    func levels(x: Int, y: Int, z: Int) -> (sky: UInt8, block: UInt8) {
        guard (self.x..<self.x+Self.width).contains(x), (self.z..<self.z+Self.width).contains(z),
              (self.y..<self.y+height).contains(y) else { return (0,0) }
        let value = values[x-self.x+Self.width*(z-self.z)+Self.plane*(y-self.y)]
        return (value >> 4,value & 15)
    }

    // Four face-adjacent cells smooth corners without rays leaking through solid walls
    func levels(at point: SCNVector3, normal: SCNVector3) -> SIMD4<Float> {
        guard point.x.isFinite, point.y.isFinite, point.z.isFinite,
              normal.x.isFinite, normal.y.isFinite, normal.z.isFinite,
              abs(point.x) < 31_000_000, abs(point.y) < 1_024, abs(point.z) < 31_000_000 else {
            return .init(0,0,1,ambient)
        }
        let length = sqrt(normal.x*normal.x+normal.y*normal.y+normal.z*normal.z)
        let n = length > 0 ? SCNVector3(normal.x/length,normal.y/length,normal.z/length) : SCNVector3(0,1,0)
        let probe = SCNVector3(point.x+n.x*0.025,point.y+n.y*0.025,point.z+n.z*0.025)
        let axis = abs(n.x)>abs(n.y) && abs(n.x)>abs(n.z) ? 0 : abs(n.z)>abs(n.y) ? 2 : 1
        var sky: Float = 0, block: Float = 0
        for first in 0..<2 { for second in 0..<2 {
            let a = first == 0 ? -0.01 : 0.01, b = second == 0 ? -0.01 : 0.01
            let p = SCNVector3(probe.x+(axis == 0 ? 0 : a),probe.y+(axis == 1 ? 0 : axis == 0 ? a : b),probe.z+(axis == 2 ? 0 : b))
            let value = levels(x:Int(floor(p.x)),y:Int(floor(p.y)),z:Int(floor(p.z)))
            sky += Self.curve[Int(value.sky)]; block += Self.curve[Int(value.block)]
        } }
        let shade = Float(0.6*abs(n.x)+0.8*abs(n.z)+(n.y>=0 ? 1.0 : 0.5)*abs(n.y))
        return .init(sky*0.25,block*0.25,min(1,max(0.5,shade)),ambient)
    }

    // Only detached chunk meshes belong here, never actors or a live scene root
    @discardableResult
    func apply(to node: SCNNode, material: (SCNMaterial) -> SCNMaterial = { $0 },
               cancelled: () -> Bool = { false }) throws -> [SCNMaterial] {
        var pending = [node], bindings: [SCNMaterial] = [], seen = Set<ObjectIdentifier>(), vertices = 0
        while let node = pending.popLast() {
            if cancelled() { throw CancellationError() }
            pending.append(contentsOf:node.childNodes)
            guard let source = node.geometry, !source.sources(for:.vertex).isEmpty else { continue }
            guard let positions = source.sources(for:.vertex).first, positions.vectorCount > 0 else { continue }
            guard let normals = source.sources(for:.normal).first,
                  positions.vectorCount == normals.vectorCount, positions.vectorCount <= 4_000_000 else { throw Failure.geometry }
            let points = try Vectors(positions), directions = try Vectors(normals)
            vertices += positions.vectorCount
            guard vertices <= 8_000_000 else { throw Failure.budget }
            var colours = [SIMD4<Float>](); colours.reserveCapacity(positions.vectorCount)
            let transform = node.worldTransform
            let inverse = SCNMatrix4Invert(transform)
            try positions.data.withUnsafeBytes { pointBytes in
                try normals.data.withUnsafeBytes { directionBytes in
                    for index in 0..<positions.vectorCount {
                        if index & 2_047 == 0, cancelled() { throw CancellationError() }
                        let p = points.vector(pointBytes,index:index)
                        let n = directions.vector(directionBytes,index:index)
                        let point = SCNVector3(p.x*transform.m11+p.y*transform.m21+p.z*transform.m31+transform.m41,
                                              p.x*transform.m12+p.y*transform.m22+p.z*transform.m32+transform.m42,
                                              p.x*transform.m13+p.y*transform.m23+p.z*transform.m33+transform.m43)
                        let normal = SCNVector3(n.x*inverse.m11+n.y*inverse.m12+n.z*inverse.m13,
                                               n.x*inverse.m21+n.y*inverse.m22+n.z*inverse.m23,
                                               n.x*inverse.m31+n.y*inverse.m32+n.z*inverse.m33)
                        colours.append(levels(at:point,normal:normal))
                    }
                }
            }
            let bytes = colours.withUnsafeBytes { Data($0) }
            let colour = SCNGeometrySource(data:bytes,semantic:.color,vectorCount:colours.count,usesFloatComponents:true,
                componentsPerVector:4,bytesPerComponent:MemoryLayout<Float>.size,dataOffset:0,dataStride:MemoryLayout<SIMD4<Float>>.stride)
            let geometry = SCNGeometry(sources:source.sources.filter { $0.semantic != .color }+[colour],elements:source.elements)
            geometry.name = source.name
            geometry.materials = source.materials.map(material)
            node.geometry = geometry
            node.castsShadow = false
            for material in geometry.materials where seen.insert(ObjectIdentifier(material)).inserted { bindings.append(material) }
        }
        return bindings
    }

    // Configure an owned cached lit variant, leaving shared actor materials untouched
    static func configure(material: SCNMaterial) {
        var modifiers = material.shaderModifiers ?? [:]
        guard modifiers[.geometry]?.contains("out.minecraftLight") != true else { return }
        modifiers[.geometry] = merge(modifiers[.geometry],declarations:"#pragma varyings\nhalf4 minecraftLight;",body:"""
        out.minecraftLight = half4(_geometry.color);
        _geometry.color = float4(1.0);
        """)
        modifiers[.surface] = merge(modifiers[.surface],declarations:"#pragma arguments\nfloat minecraftDay;",body:"""
        float minecraftSun = clamp(minecraftDay, 0.0, 1.0);
        float3 minecraftSky = float(in.minecraftLight.r) * (0.06 + 0.94 * minecraftSun)
            * mix(float3(0.58, 0.67, 1.0), float3(1.0, 0.98, 0.94), minecraftSun);
        float3 minecraftLamp = float(in.minecraftLight.g) * float3(1.0, 0.85, 0.65);
        _surface.diffuse.rgb *= max(float3(in.minecraftLight.a), max(minecraftSky, minecraftLamp)) * float(in.minecraftLight.b);
        """)
        material.lightingModel = .constant
        material.shaderModifiers = modifiers
        material.setValue(NSNumber(value:1.0),forKey:"minecraftDay")
    }

    // The caller keeps this small material list, so day changes never walk the scene
    static func illuminate(materials: [SCNMaterial], daylight: Double) {
        let value = NSNumber(value:daylight.isFinite ? min(1,max(0,daylight)) : 1)
        for material in materials { material.setValue(value,forKey:"minecraftDay") }
    }

    private static func merge(_ original: String?, declarations: String, body: String) -> String {
        let source = original ?? ""
        if let range = source.range(of:"#pragma body") {
            return declarations+"\n"+String(source[..<range.lowerBound])+"\n#pragma body\n"+String(source[range.upperBound...])+"\n"+body
        }
        return declarations+"\n#pragma body\n"+source+"\n"+body
    }

    private struct Vectors {
        let size: Int
        let stride: Int
        let offset: Int

        init(_ source: SCNGeometrySource) throws {
            size = source.bytesPerComponent; offset = source.dataOffset
            guard source.usesFloatComponents, (3...4).contains(source.componentsPerVector), [4,8].contains(size),
                  offset >= 0, source.vectorCount >= 0 else { throw Failure.geometry }
            stride = source.dataStride == 0 ? source.componentsPerVector*size : source.dataStride
            guard stride >= 3*size, source.data.count >= 3*size,
                  offset <= source.data.count-3*size,
                  source.vectorCount == 0 || source.vectorCount-1 <= (source.data.count-offset-3*size)/stride else { throw Failure.geometry }
        }

        func vector(_ bytes: UnsafeRawBufferPointer, index: Int) -> SCNVector3 {
            let offset = offset+index*stride
            if size == 4 {
                return .init(Double(bytes.loadUnaligned(fromByteOffset:offset,as:Float.self)),
                             Double(bytes.loadUnaligned(fromByteOffset:offset+size,as:Float.self)),
                             Double(bytes.loadUnaligned(fromByteOffset:offset+size*2,as:Float.self)))
            }
            return .init(bytes.loadUnaligned(fromByteOffset:offset,as:Double.self),
                         bytes.loadUnaligned(fromByteOffset:offset+size,as:Double.self),
                         bytes.loadUnaligned(fromByteOffset:offset+size*2,as:Double.self))
        }
    }

    // Numeric palette entries pack attenuation below emission, avoiding block lookups in the flood
    private static func traits(_ block: Block) -> UInt8 {
        let name = block.name, states = block.states
        func on(_ key: String) -> Bool { states[key] == "1" || states[key] == "true" }
        var emission: UInt8 = 0
        switch name {
        case "lava","flowing_lava","fire","glowstone","sea_lantern","shroomlight","jack_o_lantern","lit_pumpkin",
             "beacon","end_portal","end_gateway","conduit","lantern","ochre_froglight","verdant_froglight","pearlescent_froglight","lit_redstone_lamp": emission = 15
        case "torch","wall_torch","copper_torch","copper_wall_torch","end_rod": emission = 14
        case "soul_torch","soul_wall_torch","soul_lantern","soul_campfire","soul_fire": emission = 10
        case "lit_furnace","lit_blast_furnace","lit_smoker": emission = 13
        case "campfire": emission = 15
        case "portal","nether_portal": emission = 11
        case "redstone_torch","redstone_wall_torch": emission = 7
        case "glow_lichen","ender_chest","enchanting_table": emission = 7
        case "sculk_catalyst": emission = 6
        case "crying_obsidian": emission = 10
        case "lit_redstone_ore","lit_deepslate_redstone_ore": emission = 9
        case "small_amethyst_bud": emission = 1
        case "medium_amethyst_bud": emission = 2
        case "large_amethyst_bud": emission = 4
        case "amethyst_cluster": emission = 5
        case "magma": emission = 3
        case "brown_mushroom","brewing_stand","dragon_egg","end_portal_frame": emission = 1
        case "sea_pickle": emission = UInt8(6+3*min(3,max(0,Int(states["cluster_count"] ?? "0") ?? 0)))
        case "cave_vines_body_with_berries","cave_vines_head_with_berries": emission = 14
        case "light_block": emission = UInt8(min(15,max(0,Int(states["block_light_level"] ?? "15") ?? 15)))
        case "respawn_anchor": emission = [0,3,7,11,15][min(4,max(0,Int(states["respawn_anchor_charge"] ?? "0") ?? 0))]
        default:
            if name.contains("candle"), on("lit") { emission = UInt8(3*(min(3,max(0,Int(states["candles"] ?? "0") ?? 0))+1)) }
            else if name.hasSuffix("copper_bulb"), on("lit") {
                emission = name.contains("oxidized") ? 4 : name.contains("weathered") ? 8 : name.contains("exposed") ? 12 : 15
            } else if name.hasSuffix("copper_lantern") { emission = 15
            } else if name == "glow_berries" || name == "cave_vines" && on("berries") { emission = 14 }
            else if name == "redstone_ore" || name == "deepslate_redstone_ore", on("lit") { emission = 9 }
        }
        if name.contains("campfire"), on("extinguished") { emission = 0 }
        if name.contains("sea_pickle"), on("dead_bit") { emission = 0 }
        let loss: UInt8
        if name == "tinted_glass" { loss = 15 }
        else if name == "water" || name == "flowing_water" || name == "ice" || name == "frosted_ice" { loss = 3 }
        else if name.contains("leaves") { loss = 1 }
        else { loss = block.opaque ? 15 : 0 }
        // shortcut: partial shapes transmit through their cell, refine when sub-voxel lighting is introduced
        return loss | emission << 4
    }

    private struct Grid {
        let x: Int
        let y: Int
        let z: Int
        let height: Int
        var costs: [UInt8]
        var values: [UInt8]
        var queue: [Int32]
        var head = 0
        var tail = 0
        var count = 0
        var visits = 0

        init(x: Int, y: Int, z: Int, height: Int) {
            self.x = x; self.y = y; self.z = z; self.height = height
            let size = Light.plane*height
            costs = Array(repeating:15,count:size); values = Array(repeating:0,count:size)
            queue = Array(repeating:0,count:size)
        }

        mutating func load(_ data: WorldData, key: Chunk, cancelled: () -> Bool) throws {
            for dx in -1...1 { for dz in -1...1 {
                if cancelled() { throw CancellationError() }
                let key = Chunk(x:key.x+dx,z:key.z+dz)
                guard let chunk = data.chunks[key] else { continue }
                let lowX = max(0,x-key.x*16), highX = min(16,x+Light.width-key.x*16)
                let lowZ = max(0,z-key.z*16), highZ = min(16,z+Light.width-key.z*16)
                for py in 0..<height {
                    if py & 7 == 0, cancelled() { throw CancellationError() }
                    for px in lowX..<highX { for pz in lowZ..<highZ {
                        costs[key.x*16+px-x+Light.width*(key.z*16+pz-z)+Light.plane*py] = 0
                    } }
                }
                for section in chunk.sections.values where section.y*16 >= y && section.y*16 < y+height {
                    if cancelled() { throw CancellationError() }
                    let tables = try section.layers.map { layer -> [UInt8] in
                        try layer.blocks.enumerated().map { index,block in
                            if index & 2_047 == 0, cancelled() { throw CancellationError() }
                            return Light.traits(block)
                        }
                    }
                    for px in lowX..<highX {
                        if cancelled() { throw CancellationError() }
                        for pz in lowZ..<highZ { for py in 0..<16 {
                            let source = (px*16+pz)*16+py
                            var loss: UInt8 = 0, emission: UInt8 = 0
                            for layer in section.layers.indices {
                                let entry = tables[layer][Int(section.layers[layer].indices[source])]
                                loss = max(loss,entry & 15); emission = max(emission,entry >> 4)
                            }
                            let target = key.x*16+px-x+Light.width*(key.z*16+pz-z)+Light.plane*(section.y*16+py-y)
                            costs[target] = loss; values[target] = emission
                        } }
                    }
                }
                var edited = 0
                for (cell,block) in data.edits[key] ?? [:] {
                    if edited & 2_047 == 0, cancelled() { throw CancellationError() }
                    edited += 1
                    guard (x..<x+Light.width).contains(cell.x), (z..<z+Light.width).contains(cell.z),
                          (y..<y+height).contains(cell.y) else { continue }
                    let primary = Light.traits(block)
                    let secondary = data.block(cell.x,cell.y,cell.z,layer:1).map(Light.traits) ?? 0
                    let index = cell.x-x+Light.width*(cell.z-z)+Light.plane*(cell.y-y)
                    costs[index] = max(primary & 15,secondary & 15)
                    values[index] = max(primary >> 4,secondary >> 4)
                }
            } }
        }

        mutating func sunlight(cancelled: () -> Bool) throws {
            for pz in 0..<Light.width {
                for px in 0..<Light.width {
                    if px & 3 == 0, cancelled() { throw CancellationError() }
                    var level: UInt8 = 15
                    for py in (0..<height).reversed() {
                        let index = px+Light.width*pz+Light.plane*py, loss = costs[index] & 15
                        level = loss >= level ? 0 : level-loss
                        values[index] = (values[index] & 15) | level << 4
                    }
                }
            }
        }

        mutating func enqueue(_ index: Int) {
            guard costs[index] & 16 == 0 else { return }
            costs[index] |= 16
            queue[tail] = Int32(index); tail = tail+1 == queue.count ? 0 : tail+1
            count += 1
        }

        mutating func propagate(sky: Bool, cancelled: () -> Bool) throws {
            let shift: UInt8 = sky ? 4 : 0
            for index in values.indices {
                if index & 2_047 == 0, cancelled() { throw CancellationError() }
                let level = values[index] >> shift & 15
                guard level > 1 else { continue }
                if !sky { enqueue(index); continue }
                // Open columns need no queue entry until they meet a darker horizontal neighbour
                let px = index % Light.width, pz = index / Light.width % Light.width
                for face in 0..<4 {
                    let neighbour: Int
                    switch face {
                    case 0: neighbour = px>0 ? index-1 : -1
                    case 1: neighbour = px+1<Light.width ? index+1 : -1
                    case 2: neighbour = pz>0 ? index-Light.width : -1
                    default: neighbour = pz+1<Light.width ? index+Light.width : -1
                    }
                    guard neighbour >= 0 else { continue }
                    let loss = max(1,costs[neighbour] & 15)
                    if level > loss, level-loss > values[neighbour] >> 4 { enqueue(index); break }
                }
            }
            while count > 0 {
                if visits & 2_047 == 0 {
                    if cancelled() { throw CancellationError() }
                    guard visits <= values.count*32 else { throw Failure.budget }
                }
                let index = Int(queue[head]); head = head+1 == queue.count ? 0 : head+1; count -= 1
                costs[index] &= 15; visits += 1
                let level = values[index] >> shift & 15
                let px = index % Light.width, pz = index / Light.width % Light.width
                for face in 0..<6 {
                    let neighbour: Int
                    switch face {
                    case 0: neighbour = px>0 ? index-1 : -1
                    case 1: neighbour = px+1<Light.width ? index+1 : -1
                    case 2: neighbour = pz>0 ? index-Light.width : -1
                    case 3: neighbour = pz+1<Light.width ? index+Light.width : -1
                    case 4: neighbour = index>=Light.plane ? index-Light.plane : -1
                    default: neighbour = index+Light.plane<values.count ? index+Light.plane : -1
                    }
                    guard neighbour >= 0 else { continue }
                    let loss = max(1,costs[neighbour] & 15)
                    guard level > loss else { continue }
                    let next = level-loss, old = values[neighbour] >> shift & 15
                    if next > old {
                        values[neighbour] = (values[neighbour] & (sky ? 15 : 240)) | next << shift
                        enqueue(neighbour)
                    }
                }
            }
        }
    }
}
