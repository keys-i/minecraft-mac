import SceneKit

// Distant columns preserve caves, canopy gaps and island undersides from the original chunks
struct Horizon {
    struct Span {
        let bottom: Int
        let top: Int
        let block: Block
    }
    struct Tile {
        let step: Int
        let columns: [[Span]]
        let biome: Biome

        init(_ chunk: VoxelChunk, near centre: Chunk) {
            step = Horizon.step(chunk.key,near:centre)
            var columns: [[Span]] = []
            let minimum = chunk.dimension == 0 ? -64 : 0, maximum = chunk.dimension == 1 ? 127 : chunk.dimension == 2 ? 255 : 319
            for z in stride(from:0,to:16,by:step) {for x in stride(from:0,to:16,by:step) {
                var spans: [Span] = [], bottom: Int?, material: Block?
                for y in minimum...(maximum+1) {
                    let block = y<=maximum ? chunk.block(x+step/2,y,z+step/2) : nil
                    let occupied = block.map {!$0.passable || $0.fluid} ?? false
                    if let low = bottom, !occupied || block?.fluid != material?.fluid {
                        spans.append(Span(bottom:low,top:y,block:material!)); bottom = nil; material = nil
                    }
                    if occupied {if bottom == nil {bottom = y}; material = block}
                }
                columns.append(spans)
            } }
            self.columns = columns
            biome = Biome.bedrock(chunk.biome(8,64,8),dimension:chunk.dimension)
        }
    }

    var tiles: [Chunk:Tile] = [:]
    var groups: [Chunk:Set<Chunk>] = [:]
    var ring = 0
    var pages: [Chunk:SCNNode] = [:]
    var dirty = Set<Chunk>()
    var operation: Operation?
    var pending: Chunk?
    var revision = 0

    static func step(_ key: Chunk, near centre: Chunk) -> Int {
        let distance = max(abs(key.x-centre.x),abs(key.z-centre.z))
        var step = 1
        while step<16 && distance>=step*32 {step *= 2}
        return step
    }
    static func page(_ key: Chunk) -> Chunk { .init(x:Int(floor(Double(key.x)/16)),z:Int(floor(Double(key.z)/16))) }
    static func within(_ key: Chunk, of centre: Chunk, radius: Int) -> Bool { max(abs(key.x-centre.x),abs(key.z-centre.z))<=radius }
    static func shell(_ centre: Chunk, radius: Int) -> Set<Chunk> {
        guard radius>0 else {return [centre]}
        var keys = Set<Chunk>()
        keys.reserveCapacity(radius*8)
        for dx in -radius...radius {
            keys.insert(.init(x:centre.x+dx,z:centre.z-radius)); keys.insert(.init(x:centre.x+dx,z:centre.z+radius))
        }
        for dz in (-radius+1)..<radius {
            keys.insert(.init(x:centre.x-radius,z:centre.z+dz)); keys.insert(.init(x:centre.x+radius,z:centre.z+dz))
        }
        return keys
    }
    mutating func insert(_ values: [Chunk:Tile]) {
        for (key,tile) in values {
            tiles[key] = tile
            let page = Self.page(key)
            groups[page,default:[]].insert(key)
            dirty.insert(page)
            for (dx,dz) in [(-1,0),(1,0),(0,-1),(0,1)] {
                let neighbour = Self.page(.init(x:key.x+dx,z:key.z+dz))
                if neighbour != page, groups[neighbour] != nil {dirty.insert(neighbour)}
            }
        }
    }
    mutating func cancel() {
        operation?.cancel(); operation = nil
        if let pending {dirty.insert(pending)}
        pending = nil; revision += 1
    }
    mutating func prune(near centre: Chunk, radius: Int) {
        for page in Array(groups.keys) {
            let dx = max(page.x*16-centre.x,centre.x-(page.x*16+15),0)
            let dz = max(page.z*16-centre.z,centre.z-(page.z*16+15),0)
            if max(dx,dz)>radius {
                for key in groups.removeValue(forKey:page) ?? [] {tiles.removeValue(forKey:key)}
                pages.removeValue(forKey:page)?.removeFromParentNode(); dirty.remove(page)
            }
        }
    }
    static func boundary(_ centre: Chunk, radius: Int) -> Set<Chunk> {
        Set(shell(centre,radius:radius).map(page))
    }

    static func node(_ page: Chunk, tiles: [Chunk:Tile], centre: Chunk, near: Int, assets: Assets, cancelled: () -> Bool = {false}) throws -> SCNNode {
        var mesh = Voxels(), liquids = Voxels(), flows: [String:SCNMaterial] = [:]
        func column(_ x: Int,_ z: Int) -> [Span] {
            let key = WorldData.key(x,z)
            guard let tile = tiles[key] else {return []}
            return tile.columns[((z%16+16)%16/tile.step)*(16/tile.step)+(x%16+16)%16/tile.step]
        }
        for (key,tile) in tiles where Self.page(key) == page && !within(key,of:centre,radius:near) {
            if cancelled() {throw CancellationError()}
            let width = 16/tile.step, step = Double(tile.step)
            for index in tile.columns.indices {
                let x = key.x*16+index%width*tile.step, z = key.z*16+index/width*tile.step
                for span in tile.columns[index] {
                    let world = SCNVector3(Double(x)+step/2,Double(span.top)-0.02,Double(z)+step/2)
                    if span.block.fluid {
                        let name = span.block.name+":"+tile.biome.rawValue
                        let material: SCNMaterial
                        if let flow = flows[name] {material = flow}
                        else {material = try Landscape.flow(assets:assets,lava:span.block.name.contains("lava"),biome:tile.biome); flows[name] = material}
                        liquids.cube(.init(step,0,step),at:.init(world.x,world.y-0.125,world.z),material:material,faces:16)
                        continue
                    }
                    let materials = try assets.tiles(span.block.model,states:span.block.properties)
                    mesh.cube(.init(step,0,step),at:world,material:materials[4],faces:16)
                    mesh.cube(.init(step,0,step),at:.init(world.x,Double(span.bottom)+0.02,world.z),material:materials[5],faces:32)
                    for (face,dx,dz) in [(0,0,1),(1,1,0),(2,0,-1),(3,-1,0)] {
                        let neighbours = column(x+dx*tile.step,z+dz*tile.step)
                        var exposed = [(span.bottom,span.top)]
                        for neighbour in neighbours where !neighbour.block.fluid {
                            exposed = exposed.flatMap { low,high -> [(Int,Int)] in
                                if neighbour.top<=low || neighbour.bottom>=high {return [(low,high)]}
                                var rest: [(Int,Int)] = []
                                if low<neighbour.bottom {rest.append((low,neighbour.bottom))}
                                if neighbour.top<high {rest.append((neighbour.top,high))}
                                return rest
                            }
                        }
                        for (low,high) in exposed {
                            let height = Double(high-low)
                            mesh.cube(dx == 0 ? .init(step,height,0) : .init(0,height,step),
                                at:.init(world.x+Double(dx)*(step/2-0.015),Double(low)+height/2,world.z+Double(dz)*(step/2-0.015)),material:materials[face],faces:1 << face)
                        }
                    }
                }
            }
        }
        let node = mesh.node("distant-\(page.x)-\(page.z)")
        node.categoryBitMask = 0; node.castsShadow = false
        if !liquids.vertices.isEmpty {
            let water = liquids.node("distant-fluids"); water.categoryBitMask = 1; water.castsShadow = false
            node.addChildNode(water)
            for material in flows.values {Landscape.animate(water,material:material)}
        }
        return node
    }

    mutating func clear() {
        operation?.cancel()
        for node in pages.values {node.removeFromParentNode()}
        self = Horizon()
    }
}
