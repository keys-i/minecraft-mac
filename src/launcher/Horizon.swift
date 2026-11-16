import SceneKit

// Distant columns preserve caves, canopy gaps and island undersides from the original chunks
struct Horizon {
    struct Span: Equatable {
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
            let sections = chunk.sections.values.filter {$0.y*16<=maximum && $0.y*16+15>=minimum}.sorted {$0.y<$1.y}
            for z in stride(from:0,to:16,by:step) {for x in stride(from:0,to:16,by:step) {
                var spans: [Span] = [], solid: Span?, liquid: Span?
                func append(_ block: Block?, bottom: Int, top: Int, to current: inout Span?) {
                    if let old = current {
                        let same = block?.fluid == true ? block?.liquid == old.block.liquid : block == old.block
                        if let block, old.top == bottom, same {
                            current = Span(bottom:old.bottom,top:top,block:block); return
                        }
                        spans.append(old); current = nil
                    }
                    if let block { current = Span(bottom:bottom,top:top,block:block) }
                }
                func sample(_ primary: Block?, _ secondary: Block?, bottom: Int, top: Int) {
                    let block = primary.flatMap { !$0.passable && !$0.fluid ? $0 : nil }
                    let water = primary?.fluid == true ? primary : secondary.flatMap {$0.fluid ? $0 : nil}
                    append(block,bottom:bottom,top:top,to:&solid)
                    append(water,bottom:bottom,top:top,to:&liquid)
                }
                for section in sections {
                    let primary = section.layers.first, secondary = section.layers.count>1 ? section.layers[1] : nil
                    let bottom = max(minimum,section.y*16), top = min(maximum+1,section.y*16+16)
                    if (primary?.blocks.count ?? 0)<=1 && (secondary?.blocks.count ?? 0)<=1 {
                        sample(primary?.blocks.first,secondary?.blocks.first,bottom:bottom,top:top)
                    } else {
                        for y in bottom..<top {
                            let dy = y-section.y*16
                            sample(primary?.block(x+step/2,dy,z+step/2),secondary?.block(x+step/2,dy,z+step/2),bottom:y,top:y+1)
                        }
                    }
                }
                if let solid { spans.append(solid) }; if let liquid { spans.append(liquid) }
                columns.append(spans.sorted { $0.bottom<$1.bottom })
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
        var mesh = Voxels(), liquids = Voxels(), molten = Voxels(), translucent = Voxels()
        func column(_ x: Int,_ z: Int) -> [Span] {
            let key = WorldData.key(x,z)
            guard let tile = tiles[key] else {return []}
            return tile.columns[((z%16+16)%16/tile.step)*(16/tile.step)+(x%16+16)%16/tile.step]
        }
        func top(_ span: Span) -> Double {
            guard span.block.fluid else { return Double(span.top) }
            let level = Int(span.block.properties["level"] ?? "0") ?? 0
            return Double(span.top-1)+Double(8-(level&7))/9
        }
        func covers(_ span: Span, _ neighbour: Span) -> Bool {
            neighbour.block.opaque || span.block.fluid && neighbour.block.liquid == span.block.liquid
                || span.block.render == .blend && neighbour.block == span.block
        }
        for (key,tile) in tiles where Self.page(key) == page && !within(key,of:centre,radius:near) {
            if cancelled() {throw CancellationError()}
            let width = 16/tile.step, step = Double(tile.step)
            for index in tile.columns.indices {
                if cancelled() { throw CancellationError() }
                let x = key.x*16+index%width*tile.step, z = key.z*16+index/width*tile.step
                for span in tile.columns[index] {
                    let low = Double(span.bottom), high = top(span)
                    let world = SCNVector3(Double(x)+step/2,high,Double(z)+step/2)
                    let materials: [SCNMaterial]
                    if span.block.fluid {
                        let lava = span.block.liquid == "lava"
                        let flow = try assets.fluid(lava:lava,biome:tile.biome,flowing:true)
                        let still = try assets.fluid(lava:lava,biome:tile.biome)
                        materials = [flow,flow,flow,flow,(span.block.properties["level"] ?? "0") == "0" ? still : flow,still]
                    } else { materials = try assets.tiles(span.block.model,states:span.block.properties) }
                    func emit(_ size: SCNVector3, at point: SCNVector3, _ index: Int) {
                        if span.block.liquid == "lava" { molten.cube(size,at:point,material:materials[index],faces:1 << index) }
                        else if span.block.fluid { liquids.cube(size,at:point,material:materials[index],faces:1 << index) }
                        else if span.block.render == .blend { translucent.cube(size,at:point,material:materials[index],faces:1 << index) }
                        else { mesh.cube(size,at:point,material:materials[index],faces:1 << index) }
                    }
                    let others = tile.columns[index].filter { $0 != span && covers(span,$0) }
                    if !others.contains(where:{Double($0.bottom)<=high && top($0)>high}) {
                        emit(.init(step,0,step),at:world,4)
                    }
                    if !others.contains(where:{Double($0.bottom)<low && top($0)>=low}) {
                        emit(.init(step,0,step),at:.init(world.x,low,world.z),5)
                    }
                    for (face,dx,dz) in [(0,0,1),(1,1,0),(2,0,-1),(3,-1,0)] {
                        let neighbours = column(x+dx*tile.step,z+dz*tile.step)
                        var exposed = [(low,high)]
                        for neighbour in neighbours where covers(span,neighbour) {
                            let bottom = Double(neighbour.bottom), upper = top(neighbour)
                            exposed = exposed.flatMap { low,high -> [(Double,Double)] in
                                if upper<=low || bottom>=high {return [(low,high)]}
                                var rest: [(Double,Double)] = []
                                if low<bottom {rest.append((low,bottom))}
                                if upper<high {rest.append((upper,high))}
                                return rest
                            }
                        }
                        for (low,high) in exposed {
                            let height = high-low
                            let point = SCNVector3(world.x+Double(dx)*step/2,low+height/2,world.z+Double(dz)*step/2)
                            emit(dx == 0 ? .init(step,height,0) : .init(0,height,step),at:point,face)
                        }
                    }
                }
            }
        }
        let node = mesh.node("distant-\(page.x)-\(page.z)")
        node.categoryBitMask = 0; node.castsShadow = false
        if !translucent.vertices.isEmpty {
            let glass = translucent.node("distant-translucent"); glass.categoryBitMask = 0; glass.castsShadow = false
            node.addChildNode(glass)
        }
        if !liquids.vertices.isEmpty {
            let water = liquids.node("distant-fluids"); water.categoryBitMask = 1; water.castsShadow = false
            node.addChildNode(water)
        }
        if !molten.vertices.isEmpty {
            let lava = molten.node("distant-lava"); lava.categoryBitMask = 1; lava.castsShadow = false
            node.addChildNode(lava)
        }
        return node
    }

    mutating func clear() {
        operation?.cancel()
        for node in pages.values {node.removeFromParentNode()}
        self = Horizon()
    }
}
