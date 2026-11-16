import SceneKit

struct Terrain {
    let biome: Biome
    // Only present landmarks reserve flat plots and village paths
    var authored = true
    var worldSeed = 0

    static func random(_ x: Int, _ z: Int, seed: Int = 0) -> Double {
        var n = UInt64(bitPattern:Int64(x)) &* 0x9E3779B185EBCA87
        n = n &+ UInt64(bitPattern:Int64(z)) &* 0xC2B2AE3D27D4EB4F &+ UInt64(bitPattern:Int64(seed)) &* 0x165667B19E3779F9
        n = (n ^ (n >> 30)) &* 0xBF58476D1CE4E5B9
        n = (n ^ (n >> 27)) &* 0x94D049BB133111EB
        return Double((n ^ (n >> 31)) & 0xFFFFFF)/Double(0xFFFFFF)
    }

    static func noise(_ x: Double, _ z: Double, scale: Double, seed: Int = 0) -> Double {
        let x = x/scale, z = z/scale, ix = Int(floor(x)), iz = Int(floor(z))
        let fx = x-Double(ix), fz = z-Double(iz)
        let sx = fx*fx*(3-2*fx), sz = fz*fz*(3-2*fz)
        let a = random(ix,iz,seed:seed), b = random(ix+1,iz,seed:seed)
        let c = random(ix,iz+1,seed:seed), d = random(ix+1,iz+1,seed:seed)
        return ((a+(b-a)*sx)*(1-sz)+(c+(d-c)*sx)*sz)*2-1
    }

    var seed: Int { (Biome.allCases.firstIndex(of:biome)!+1) &+ worldSeed }
    var end: Bool { [.central,.highlands,.midlands,.islands,.barrens,.city].contains(biome) }

    private static let villagePlots = [CGRect(x:-17,y:-34,width:14,height:12),.init(x:7,y:-33,width:8,height:8),
                .init(x:-16,y:-15,width:8,height:8),.init(x:6,y:-15,width:14,height:10),
                .init(x:-5,y:-21,width:10,height:10),.init(x:-23,y:-23,width:6,height:8),
                .init(x:-20,y:-50,width:10,height:10),.init(x:12,y:-50,width:10,height:14)]
    var plots: [CGRect] { authored && biome == .meadow ? Self.villagePlots : [] }

    func path(_ z: Double) -> Double { biome == .meadow ? sin(z/8)*1.5 : 3 }

    private static let roads: Set<Int> = {
        var cells = Set<Int>()
        func add(_ x: Int, _ z: Int) { cells.insert((x+100)*256+z+132) }
        for z in -48...18 {
            let x = Int((sin(Double(z)/8)*1.5).rounded())
            for dx in -1...1 { add(x+dx,z) }
        }
        for (ex,ez) in [(-5,-28),(8,-29),(-12,-7),(6,-10),(-17,-19),(-11,-45),(16,-42)] {
            for step in 0...abs(ex) {
                let x = ex < 0 ? -step : step, z = ez+Int(sin(Double(step)*0.4))
                add(x,z); add(x,z+1)
            }
        }
        return cells
    }()

    func paved(_ x: Double, _ z: Double) -> Bool {
        authored && biome == .meadow && Self.roads.contains((Int(x.rounded())+100)*256+Int(z.rounded())+132)
    }

    func occupied(_ x: Double, _ z: Double) -> Bool {
        guard authored else { return false }
        if biome == .meadow {
            return paved(x,z) || plots.contains { $0.contains(CGPoint(x:x,y:z)) } || abs(x-path(z))<1.7 && (-48...18).contains(z)
        }
        return reserved(x,z) && z < -2
    }

    func reserved(_ x: Double, _ z: Double) -> Bool {
        guard authored else { return false }
        if biome == .meadow {
            return paved(x,z) || plots.contains { $0.insetBy(dx:-2,dy:-2).contains(CGPoint(x:x,y:z)) } || abs(x-path(z))<3 && (-48...20).contains(z)
        }
        if biome == .city && [CGRect(x:-30,y:-53,width:23,height:38),.init(x:18,y:-40,width:21,height:39)].contains(where: { $0.contains(CGPoint(x:x,y:z)) }) { return true }
        let footprint: (Double,Double,Double)
        switch biome {
        case .meadow,.snow,.savanna: footprint = (26,-39,0)
        case .mansion: footprint = (23,-39,17)
        case .desert: footprint = (13,-33,-7)
        case .jungle: footprint = (9,-29,-6)
        case .trial: footprint = (19,-34,-2)
        case .deep: footprint = (35,-59,5)
        case .crimson: footprint = (23,-52,7)
        case .wastes: return abs(z+18)<6 || abs(x)<6 && (-50 ... -15).contains(z)
        case .city: footprint = (9,-26,-9)
        default: footprint = (7,-26,-10)
        }
        let structure = abs(x)<footprint.0 && (footprint.1...footprint.2).contains(z)
        let route = biome == .mansion ? abs(x-5)<6 && (15...40).contains(z) : biome == .city ? abs(x-8)<5 && (-8...28).contains(z) : abs(x-3)<3 && (-2...25).contains(z)
        return structure || route
    }

    func height(_ x: Double, _ z: Double) -> Double {
        profile(x,z,edges:true)
    }

    private func profile(_ x: Double, _ z: Double, edges: Bool) -> Double {
        var level = shape(x,z)
        for plot in plots {
            let dx = max(0,max(plot.minX-x,x-plot.maxX)), dz = max(0,max(plot.minY-z,z-plot.maxY))
            if dx >= 3 || dz >= 3 { continue }
            let blend = min(1,hypot(dx,dz)/3)
            level = level*blend+shape(plot.midX,plot.midY)*(1-blend)
        }
        if !biome.underground && !end && !reserved(x,z), [.meadow,.forest,.cherry,.snow,.jungle,.mansion,.savanna,.pale,.mushroom].contains(biome) {
            let cx = seed%2 == 0 ? -48.0 : 47, cz = -56+Self.random(seed,3)*72
            let lake = hypot((x-cx)/1.25,z-cz)
            let bank = min(1,max(0,(lake-9)/7))
            let stream = abs(x-(seed%2 == 0 ? 44 : -43)-Self.noise(0,z,scale:38,seed:seed &+ 207)*11)
            let channel = min(1,max(0,(stream-2.5)/4))
            level = min(level,-4*(1-bank)+level*bank,-3*(1-channel)+level*channel)
        }
        if edges && !end && biome.passage == nil {
            let blend = min(1,max(0,(max(abs(x),abs(z+32))-68)/27))
            level = level*(1-blend)+4*blend
        }
        return floor(level)
    }

    private func shape(_ x: Double, _ z: Double) -> Double {
        let broad = Self.noise(x,z,scale:42,seed:seed)
        let fine = Self.noise(x,z,scale:13,seed:seed &+ 43)
        let ridge = Self.noise(x+26,z-14,scale:64,seed:seed &+ 11)
        let wave = broad*3+fine*0.8
        if end {
            let radius = biome == .central ? 46.0 : biome == .city ? 55 : biome == .highlands ? 43 : biome == .islands ? 17 : 36
            let distance = hypot(x/1.15,z+17)
            let boundary = radius+Self.noise(x,z,scale:11,seed:8)*4
            if distance>boundary {
                for (cx,cz,r) in [(-56.0,-49.0,18.0),(51,-72,22),(-28,31,11),(60,13,16)] {
                    let distance = hypot(x-cx,z-cz)
                    if distance<r+Self.noise(x,z,scale:8,seed:42)*3 { return floor(2+Self.noise(x,z,scale:12,seed:4)*2) }
                }
                return -100
            }
            let relief = biome == .highlands ? 2.2 : biome == .midlands || biome == .barrens ? 0.4 : 0.9
            if biome == .central || biome == .city && authored { return floor(4+max(0,distance-30)*0.04) }
            return floor(max(1,4+wave*relief))
        }
        switch biome {
        case .mine: return min(13,max(0,ceil((z+12)/4)))
        case .stronghold: return min(45,max(0,ceil((z-6)/2)))
        case .reef: return floor(-7+broad*2+fine)
        case .monument: return floor(-24+broad*2)
        case .coast:
            let shore = z+Self.noise(x,0,scale:30,seed:7)*6
            return floor(shore<3 ? max(-9,shore*0.45-3) : 3+wave*0.2)
        case .river:
            let channel = abs(x-4-Self.noise(0,z,scale:32,seed:9)*9)
            return floor(channel<6 ? -4+channel*0.25 : 2+wave*0.45)
        case .lush:
            if hypot((x-9)/1.3,z-7)<10+fine*2 { return -4 }
            return floor(3+wave*0.6+max(0,abs(x)-21)*0.32)
        case .mangrove,.swamp:
            let water = Self.noise(x,z,scale:16,seed:4)
            return water < 0.15 ? floor(-3+water) : floor(2+water*2)
        case .wastes,.crimson,.warped,.soul,.basalt:
            if authored && biome == .wastes && abs(z+18)<6 { return 3 }
            let river = z+6-Self.noise(x,0,scale:36,seed:13)*10
            let edge = abs(river)
            if edge < (biome == .basalt ? 12 : 8) { return floor(-5+broad) }
            return floor(max(2,4+wave*1.7+max(0,-z-55)*0.25+max(0,edge-17)*0.12))
        case .trial,.deep: return 4
        case .ice: return z < -25 ? -4 : floor(2+wave*0.5)
        case .peaks:
            return floor(4+wave+pow(max(0,-z-8)*0.16,1.4)+pow(max(0,abs(x)-20)*0.12,1.4))
        case .badlands:
            if authored && abs(x)<3 && (-30 ... -9).contains(z) { return 4 }
            return floor(4+wave*0.5+max(0,abs(x)-9)*0.4+max(0,-z-15)*0.22)
        case .dripstone: return floor(2+wave*0.7+max(0,abs(x)-22)*0.35)
        case .sulfur: return floor(4+wave*0.65)
        case .valley,.sculk: return floor(3+wave+max(0,abs(x)-12)*0.42)
        case .terraces: return floor(4+wave+max(0,-z-15)*0.2)
        case .shards:
            if hypot(x,z+12)>36 && Self.noise(x,z,scale:17,seed:8)>0.12 { return -100 }
            return floor(5+wave+max(0,-z-16)*0.15)
        default: break
        }
        var y = 4+wave+max(0,-z-50)*max(0,ridge+0.3)*0.25
        if authored && [.desert,.jungle,.mansion,.savanna,.snow,.cherry].contains(biome) {
            let radius = biome == .mansion ? 22.0 : biome == .desert ? 15 : 12
            let dx = max(0,abs(x)-radius), dz = max(0,abs(z+(biome == .mansion ? 12 : 19))-(biome == .mansion ? 28 : 19))
            let blend = min(1,hypot(dx,dz)/7)
            y = 4*(1-blend)+y*blend
        }
        if biome == .grove && abs(x+7-Self.noise(0,z,scale:24,seed:4)*5)<4 { return -3 }
        return floor(y)
    }

    func ceiling(_ x: Double, _ z: Double) -> Double {
        let nether = [.wastes,.crimson,.warped,.soul,.basalt].contains(biome)
        let noise = Self.noise(x,z,scale:22,seed:seed &+ 30)
        let arch = max(0,1-pow(x/70,2))*max(0,1-pow((z+22)/110,2))
        let level = floor((nether ? 18 : biome == .deep ? 22 : 11)+(nether || biome == .deep ? 24 : 15)*arch+noise*5)
        let blend = min(1,max(0,(max(abs(x),abs(z+32))-68)/27))
        return floor(level*(1-blend)+32*blend)
    }
}

extension Terrain {

    struct Sample {
        let biome: Biome
        let height: Double
        let surface: String
        let fluid: Bool
    }

    static func entrance(_ x: Double, _ z: Double) -> Bool { hypot(x-36,z-20)<6 }

    /// Shared logical world sample for chunk meshes and the spectator map
    static func sample(world: World, at point: SCNVector3, seed: Int = 0) -> Sample {
        guard let region = Region.at(point,seed:seed) else { return Sample(biome:world.biomes[0],height:-100,surface:"stone",fluid:false) }
        let area = world.biomes[region.biome(world)], base = region.origin
        if area.level<0 && point.y < -16 {
            let terrain = Terrain(biome:area,authored:region.landmark(world),worldSeed:region.landmark(world) ? 0 : seed), h = terrain.height(point.x-base.x,point.z-base.z)
            let surface = area == .sulfur ? (noise(point.x,point.z,scale:11,seed:seed &+ 964)>0 ? "sulfur" : "cinnabar") : area == .lush && h<0.9 ? "clay" : area.surface
            return Sample(biome:area,height:h+area.level,surface:surface,fluid:h<0.9)
        }
        if area.passage != nil || world == .end {
            let x = point.x-base.x, z = point.z-base.z, terrain = Terrain(biome:area,authored:region.landmark(world),worldSeed:region.landmark(world) ? 0 : seed), floor = terrain.height(x,z)
            let roof = area.passage?.height(Int(x.rounded()),Int(z.rounded())) ?? floor
            let top = roof > -90 && point.y>floor+4 ? roof : floor
            return Sample(biome:area,height:top,surface:area.passage != nil && top == floor ? "stone" : area.surface,fluid:false)
        }
        var total = 0.0, level = 0.0, candidates: [(Biome,Double)] = []
        for dx in -1...1 { for dz in -1...1 {
            let cell = Region(x:region.x+dx,z:region.z+dz,seed:seed), origin = cell.origin
            let x = point.x-origin.x, z = point.z-origin.z
            func weight(_ distance: Double) -> Double {
                let t = min(1,max(0,(Double(Region.span*2/3)-abs(distance))/Double(Region.span/3)))
                return t*t*(3-2*t)
            }
            let w = weight(x)*weight(z+32)
            guard w>0 else { continue }
            let original = world.biomes[cell.biome(world)], biome = original.cover ?? (original.passage != nil ? .forest : original)
            let authored = cell.landmark(world), terrain = Terrain(biome:biome,authored:authored && original.cover == nil,worldSeed:authored && original.cover == nil ? 0 : seed)
            var h = terrain.profile(x,z,edges:false)
            if cell.key(world.biomes.count)<0 && !authored { h += noise(point.x,point.z,scale:91,seed:seed &+ 971)*5 }
            level += h*w; total += w; candidates.append((biome,w))
        } }
        let h = floor(level/max(0.001,total))
        var choice = (noise(point.x,point.z,scale:7,seed:seed &+ 877)+1)/2*total
        var selected = area.cover ?? area
        for (biome,weight) in candidates {
            choice -= weight
            if choice<=0 { selected = biome; break }
        }
        let localX = point.x-base.x, localZ = point.z-base.z
        var surface = selected.surface
        if !Terrain(biome:area.cover ?? area,authored:region.landmark(world) && area.cover == nil).reserved(localX,localZ), world == .overworld {
            let patch = noise(point.x,point.z,scale:9,seed:seed &+ 571)
            if h<0.9 && surface == "grass_block" && selected != .swamp {
                surface = patch>0.35 ? "gravel" : patch < -0.35 ? "clay" : patch>0 ? "sand" : "dirt"
            }
        }
        return Sample(biome:selected,height:h,surface:surface,fluid:h > -90 && h<0.9 && selected != .ice && (world == .overworld || world == .nether || selected == .grove))
    }

    /// Chunked surfaces shared by habitat views and the Overworld portal approaches
    func node(assets: Assets, x: Range<Int> = -96..<96, z: Range<Int> = -128..<64, bounded: Bool = true,
              region: Region? = nil, covered: Set<SIMD3<Int>> = [],
              height sample: ((Int,Int) -> Double)? = nil) throws -> SCNNode {
        let area = biome, terrain = self
        let world = World.allCases.first { $0.biomes.contains(area) }!
        let ground = Surface(); ground.name = "terrain"; ground.profile = Profile(terrain:self,sample:sample,covered:covered)
        let surface = try assets.tiles(area.surface)
        let clay = area == .lush ? try assets.tiles("clay") : nil
        let road = area == .meadow ? try assets.tiles("dirt_path") : nil
        let stone = try assets.tiles(world == .nether ? "netherrack" : world == .end ? "end_stone" : area == .deep ? "deepslate" : area == .sulfur ? "cinnabar" : "stone")
        let dirt = try assets.tiles("dirt")
        let fluid = world == .overworld && area != .ice || world == .nether || area == .grove
        let water = fluid ? try Landscape.flow(assets:assets,lava:world == .nether,biome:area) : nil
        let ice = area == .ice ? try assets.tiles("ice") : nil
        let bedrock = region != nil && world == .overworld ? -96-area.level : -28
        var heights: [Int:Double] = [:], columns: [Int:Sample] = [:], cover: [Int:Sample] = [:]
        var palettes = [area.surface:surface]
        func materials(_ name: String) throws -> [SCNMaterial] {
            if let cached = palettes[name] { return cached }
            let value = try assets.tiles(name); palettes[name] = value; return value
        }
        func key(_ px: Int, _ pz: Int) -> Int { (px-x.lowerBound+1)*(z.count+2)+pz-z.lowerBound+1 }
        for px in (x.lowerBound-1)...x.upperBound { for pz in (z.lowerBound-1)...z.upperBound {
            if sample == nil, let region {
                let origin = region.origin, column = Self.sample(world:world,at:.init(origin.x+Double(px),area.level+8,origin.z+Double(pz)),seed:region.seed)
                columns[key(px,pz)] = column; heights[key(px,pz)] = column.height-area.level
                if area.level<0 { cover[key(px,pz)] = Self.sample(world:world,at:.init(origin.x+Double(px),100,origin.z+Double(pz)),seed:region.seed) }
            } else { heights[key(px,pz)] = sample?(px,pz) ?? terrain.height(Double(px),Double(pz)) }
        } }
        func h(_ x: Int, _ z: Int) -> Double { heights[key(x,z)] ?? -100 }
        func edge(_ px: Int, _ pz: Int) -> Bool { bounded && (!x.contains(px) || !z.contains(pz)) }
        let strata = try (area == .badlands ? ["red_terracotta","orange_terracotta","yellow_terracotta","terracotta"] : []).map { try assets.tiles($0) }
        let soil = world == .overworld && !area.underground && ![.desert,.badlands,.reef,.monument,.coast,.peaks,.ice].contains(area)
        let directions = [(0,(0,1)),(1,(1,0)),(2,(0,-1)),(3,(-1,0))]
        for cx in stride(from:x.lowerBound,to:x.upperBound,by:16) { for cz in stride(from:z.lowerBound,to:z.upperBound,by:16) {
            var land = Voxels(), pools = Voxels(), roof = Voxels()
            let endZ = min(cz+16,z.upperBound)
            for x in cx..<min(cx+16,x.upperBound) { for z in cz..<min(cz+16,z.upperBound) {
                let y = h(x,z); guard y > -90 else { continue }
                let paved = terrain.paved(Double(x),Double(z))
                var cap = 16
                if area == .central && x*x+(z+23)*(z+23)<13 { cap = 0 }
                if covered.contains(.init(x,Int(y.rounded()),z)) { cap = 0 }
                for (face,d) in directions {
                    let neighbour = h(x+d.0,z+d.1)-(terrain.paved(Double(x+d.0),Double(z+d.1)) ? 0.0625 : 0)
                    if edge(x+d.0,z+d.1) || neighbour < y-(paved ? 0.0625 : 0) { cap |= 1 << face }
                }
                let tiles = paved ? road! : area == .lush && y<0.9 ? clay! : try materials(columns[key(x,z)]?.surface ?? area.surface)
                let thickness = paved ? 0.9375 : 1.0
                land.cube(.init(1,thickness,1),at:.init(Double(x),y-1+thickness/2,Double(z)),material:tiles[0],faces:cap,faceMaterials:tiles)
                let bottom = terrain.end || area == .shards ? -3-max(0,18-hypot(Double(x),Double(z+17))*0.3) : bedrock
                if !strata.isEmpty || soil {
                    let depth = soil ? 3 : Int(max(1,y-bottom-1))
                    var level = 1
                    while level<=depth {
                        let by = y-Double(level)-0.5
                        var faces = 0
                        for (face,d) in directions { if edge(x+d.0,z+d.1) || h(x+d.0,z+d.1)<=by+0.5 { faces |= 1 << face } }
                        // Lower layers cannot expose a face after every neighbour already covers this one
                        guard faces != 0 else { break }
                        let band = soil ? 0 : abs(Int(by)/2)%strata.count
                        let tiles = soil ? dirt : strata[band]
                        var length = 1
                        if !soil {
                            while level+length<=depth {
                                let lower = by-Double(length)
                                guard abs(Int(lower)/2)%strata.count == band else { break }
                                var next = 0
                                for (face,d) in directions { if edge(x+d.0,z+d.1) || h(x+d.0,z+d.1)<=lower+0.5 { next |= 1 << face } }
                                guard next == faces else { break }
                                length += 1
                            }
                        }
                        land.cube(.init(1,Double(length),1),at:.init(Double(x),by-Double(length-1)/2,Double(z)),
                            material:tiles[0],faces:faces,faceMaterials:tiles)
                        level += length
                    }
                }
                let depth = soil ? 4.0 : 1
                var sides = 0
                for (face,d) in directions { if edge(x+d.0,z+d.1) || h(x+d.0,z+d.1)<y-depth { sides |= 1 << face } }
                if strata.isEmpty {
                    land.cube(.init(1,max(0.1,y-depth-bottom),1),at:.init(Double(x),(y-depth+bottom)/2,Double(z)),material:stone[0],faces:sides | (terrain.end ? 32 : 0),faceMaterials:stone)
                }
                if y<0.9, columns[key(x,z)]?.biome == .ice {
                    let frozen = try materials("ice")
                    land.cube(.init(1,1,1),at:.init(Double(x),0.4,Double(z)),material:frozen[0],faces:16,faceMaterials:frozen)
                } else if y<0.9, let water {
                    pools.cube(.init(1,0,1),at:.init(Double(x),0.9,Double(z)),material:water,faces:16)
                } else if y<0.9, let ice {
                    land.cube(.init(1,1,1),at:.init(Double(x),0.4,Double(z)),material:ice[0],faces:16,faceMaterials:ice)
                }
                if (area.underground || world == .nether) && !(area.level<0 && Self.entrance(Double(x),Double(z))) {
                    let ceiling = max(y+9,terrain.ceiling(Double(x),Double(z)))
                    let top = area.level<0 ? max(ceiling+1,min(64,(cover[key(x,z)]?.height ?? 4)-area.level-4)) : max(64,ceiling+1)
                    func underside(_ z: Int) -> Double { max(h(x,z)+9,terrain.ceiling(Double(x),Double(z))) }
                    let previous = z>cz && !(area.level<0 && Self.entrance(Double(x),Double(z-1))) && underside(z-1) == ceiling
                    if !previous {
                        var length = 1
                        while z+length<endZ && !(area.level<0 && Self.entrance(Double(x),Double(z+length))) && underside(z+length) == ceiling { length += 1 }
                        roof.cube(.init(1,0,Double(length)),at:.init(Double(x),ceiling,Double(z)+Double(length-1)/2),material:stone[0],faces:32)
                    }
                    for (face,d) in directions {
                        let neighbour = max(h(x+d.0,z+d.1)+9,terrain.ceiling(Double(x+d.0),Double(z+d.1)))
                        let neighbourTop = area.level<0 ? max(neighbour+1,min(64,(cover[key(x+d.0,z+d.1)]?.height ?? 4)-area.level-4)) : max(64,neighbour+1)
                        let open = edge(x+d.0,z+d.1) || area.level<0 && Self.entrance(Double(x+d.0),Double(z+d.1))
                        let exposed = open ? [(ceiling,top)] : [(ceiling,min(top,neighbour)),(max(ceiling,neighbourTop),top)]
                        for (lower,upper) in exposed where upper>lower {
                            roof.cube(.init(1,upper-lower,1),at:.init(Double(x),(lower+upper)/2,Double(z)),material:stone[0],faces:1 << face,faceMaterials:stone)
                        }
                    }
                    if area.level<0, let region {
                        for (face,d) in directions where !Region.xRange.contains(x+d.0) || !Region.zRange.contains(z+d.1) {
                            let global = SCNVector3(region.origin.x+Double(x+d.0),0,region.origin.z+Double(z+d.1))
                            guard let other = Region.at(global,seed:region.seed), world.biomes[other.biome(world)].level == 0 else { continue }
                            let size = SCNVector3(d.0 == 0 ? 1 : 0,ceiling-y,d.1 == 0 ? 1 : 0)
                            roof.cube(size,at:.init(Double(x)+Double(d.0)*0.5,(ceiling+y)/2,Double(z)+Double(d.1)*0.5),material:stone[0],faces:1 << ((face+2)%4),faceMaterials:stone)
                        }
                    }
                }
                if area.level<0, let column = cover[key(x,z)], !Self.entrance(Double(x),Double(z)) {
                    let top = column.height-area.level, palette = try materials(column.surface)
                    var faces = 0
                    for (face,d) in directions {
                        if Self.entrance(Double(x+d.0),Double(z+d.1)) || (cover[key(x+d.0,z+d.1)]?.height ?? column.height)<column.height { faces |= 1 << face }
                    }
                    land.cube(.init(1,1,1),at:.init(Double(x),top-0.5,Double(z)),material:palette[0],faces:16,faceMaterials:palette)
                    let bottom = min(64,top-4)
                    if faces != 0 { land.cube(.init(1,top-bottom,1),at:.init(Double(x),(top+bottom)/2,Double(z)),material:stone[0],faces:faces,faceMaterials:stone) }
                    if column.fluid, let water { pools.cube(.init(1,0,1),at:.init(Double(x),0.9-area.level,Double(z)),material:water,faces:16) }
                }
            } }
            if !terrain.end && area != .shards {
                let width = Double(min(16,x.upperBound-cx)), depth = Double(min(16,z.upperBound-cz))
                land.cube(.init(width,0,depth),at:.init(Double(cx)+(width-1)/2,bedrock,Double(cz)+(depth-1)/2),material:stone[0],faces:32)
                if (area.underground || world == .nether) && area.level == 0 {
                    roof.cube(.init(width,0,depth),at:.init(Double(cx)+(width-1)/2,64,Double(cz)+(depth-1)/2),material:stone[0],faces:16)
                }
            }
            let section = Section(); section.x = cx; section.z = cz; section.position = .init(Double(cx),0,Double(cz))
            for (name,source) in [("chunk",land),("pool",pools),("ceiling",roof)] where !source.vertices.isEmpty {
                var mesh = source
                mesh.vertices = mesh.vertices.map { .init($0.x-Double(cx),$0.y,$0.z-Double(cz)) }
                section.addChildNode(mesh.node("\(name)-\(cx)-\(cz)"))
            }
            ground.addChildNode(section)
        } }
        if let water {
            let controller = SCNNode(); controller.name = "flowing-surface"
            Landscape.animate(controller,material:water); ground.addChildNode(controller)
        }
        return ground
    }
}

enum Collision {
    static func nearby(_ root: SCNNode, at point: SCNVector3, toward target: SCNVector3? = nil) -> SCNVector3? {
        func usable(_ candidate: SCNVector3) -> Bool {
            guard vacant(root,at:candidate) else { return false }
            guard let target else { return true }
            let length = sqrt(pow(target.x-candidate.x,2)+pow(target.y-candidate.y,2)+pow(target.z-candidate.z,2))
            let scale = min(1,5/max(0.001,length))
            return clear(root,from:candidate,to:.init(candidate.x+(target.x-candidate.x)*scale,
                candidate.y+(target.y-candidate.y)*scale,candidate.z+(target.z-candidate.z)*scale),radius:0.35)
        }
        if usable(point) { return point }
        for distance in 1...12 {
            for (x,y,z) in [(0.0,0.0,1.0),(1.0,0.0,0.0),(-1.0,0.0,0.0),(0.0,0.0,-1.0),(0.0,1.0,0.0),(0.0,-1.0,0.0)] {
                let candidate = SCNVector3(point.x+x*Double(distance),point.y+y*Double(distance),point.z+z*Double(distance))
                if usable(candidate) { return candidate }
            }
        }
        return nil
    }

    private static func solid(_ hit: SCNHitTestResult) -> Bool {
        let ignored = ["water","lava","tallgrass","wheat","carrots","potatoes","beetroots","flower","sapling","fern","rail","web","clouds","bamboo_leaf","torch"]
        let materials = hit.node.geometry?.materials ?? []
        let name = materials.indices.contains(hit.geometryIndex) ? materials[hit.geometryIndex].name ?? "" : ""
        return !ignored.contains(where:name.contains)
    }

    static func clearance(_ root: SCNNode, from a: SCNVector3, to b: SCNVector3, ground: Double) -> Double {
        let dx = b.x-a.x, dz = b.z-a.z, length = max(0.001,hypot(dx,dz))
        let offsets = [(0.0,0.0,0.0),(-dz/length*0.35,0,dx/length*0.35),
            (dz/length*0.35,0,-dx/length*0.35),(0,0.35,0),(0,-0.35,0)]
        var level = ground
        for (x,y,z) in offsets {
            let hits = root.hitTestWithSegment(from:.init(a.x+x,a.y+y,a.z+z),to:.init(b.x+x,b.y+y,b.z+z),
                options:[SCNHitTestOption.categoryBitMask.rawValue:2,SCNHitTestOption.backFaceCulling.rawValue:false,
                    SCNHitTestOption.ignoreHiddenNodes.rawValue:true])
            for hit in hits where solid(hit) {
                let p = root.convertPosition(hit.worldCoordinates,from:nil), normal = root.convertVector(hit.worldNormal,from:nil)
                level = max(level,surface(root,at:.init(p.x-normal.x*0.05,p.y,p.z-normal.z*0.05),ground:ground))
            }
        }
        return level
    }

    static func surface(_ root: SCNNode, at point: SCNVector3, ground: Double) -> Double {
        let hits = root.hitTestWithSegment(from:.init(point.x,max(ground+64,point.y+32),point.z),
            to:.init(point.x,ground-1,point.z),options:[SCNHitTestOption.categoryBitMask.rawValue:2,
                SCNHitTestOption.backFaceCulling.rawValue:false,SCNHitTestOption.ignoreHiddenNodes.rawValue:true])
        guard let hit = hits.first(where:solid) else { return ground }
        return max(ground,root.convertPosition(hit.worldCoordinates,from:nil).y)
    }

    // An outward first face means the eye starts inside solid geometry
    static func vacant(_ root: SCNNode, at point: SCNVector3, radius: Double = 0.35) -> Bool {
        for axis in 0..<3 {
            var end = point
            if axis == 0 { end.x += 256 } else if axis == 1 { end.y += 256 } else { end.z += 256 }
            let hits = root.hitTestWithSegment(from:point,to:end,options:[SCNHitTestOption.categoryBitMask.rawValue:2,
                SCNHitTestOption.backFaceCulling.rawValue:false,SCNHitTestOption.ignoreHiddenNodes.rawValue:true])
            if let hit = hits.first(where:solid) {
                let normal = axis == 0 ? hit.worldNormal.x : axis == 1 ? hit.worldNormal.y : hit.worldNormal.z
                let p = root.convertPosition(hit.worldCoordinates,from:nil)
                if normal > 0.01 || sqrt(pow(p.x-point.x,2)+pow(p.y-point.y,2)+pow(p.z-point.z,2)) < radius { return false }
            }
        }
        return true
    }

    // Native mesh queries keep camera and resident paths aligned with placed structure faces
    static func clear(_ root: SCNNode, from a: SCNVector3, to b: SCNVector3,
                      radius: Double = 0.25, height: Double = 0) -> Bool {
        guard a.x != b.x || a.y != b.y || a.z != b.z else { return true }
        let levels = height > 0 ? [0.15,height*0.5,height-0.1] : [-radius,0,radius]
        for y in levels {
            let offsets: [(Double,Double)] = height == 0 && y != 0 ? [(0.0,0.0)] : [(0.0,0.0),(radius,0),(-radius,0),(0,radius),(0,-radius)]
            for (x,z) in offsets {
                let start = SCNVector3(a.x+x,a.y+y,a.z+z), end = SCNVector3(b.x+x,b.y+y,b.z+z)
                let hits = root.hitTestWithSegment(from:start,to:end,options:[SCNHitTestOption.categoryBitMask.rawValue:2,SCNHitTestOption.backFaceCulling.rawValue:false,SCNHitTestOption.ignoreHiddenNodes.rawValue:true])
                if hits.contains(where:solid) { return false }
            }
        }
        return true
    }

    static func move(_ root: SCNNode, from start: SCNVector3, to end: SCNVector3, radius: Double = 0.25, height: Double = 0) -> SCNVector3 {
        if clear(root,from:start,to:end,radius:radius,height:height) { return end }
        let distance = sqrt(pow(end.x-start.x,2)+pow(end.y-start.y,2)+pow(end.z-start.z,2))
        let count = max(1,Int(ceil(distance/0.25)))
        var p = start
        for _ in 0..<count {
            for axis in 0..<3 {
                var next = p
                if axis == 0 { next.x += (end.x-start.x)/Double(count) }
                else if axis == 1 { next.y += (end.y-start.y)/Double(count) }
                else { next.z += (end.z-start.z)/Double(count) }
                if clear(root,from:p,to:next,radius:radius,height:height) { p = next }
            }
        }
        return p
    }
}

struct Region: Hashable {
    static let span = 384
    static let xRange = (-span/2)..<(span/2)
    static let zRange = (-span/2-32)..<(span/2-32)
    static let limit = 30_000_000.0
    static let farLands = 12_550_824
    let x: Int
    let z: Int
    var seed = 0

    static func at(_ p: SCNVector3, seed: Int = 0) -> Region? {
        guard p.x.isFinite, p.z.isFinite, abs(p.x)<=limit, abs(p.z)<=limit else { return nil }
        return Region(x:Int(floor((p.x+Double(span/2)+0.5)/Double(span))),z:Int(floor((p.z+Double(span/2)+32.5)/Double(span))),seed:seed)
    }

    var origin: SCNVector3 { .init(Double(x*Self.span),0,Double(z*Self.span)) }

    func key(_ count: Int) -> Int {
        let width = Atlas.columns(count), index = z*width+x
        if x>=0 && x<width && z>=0 && index<count { return index }
        let a = x>=0 ? x*2 : -x*2-1, b = z>=0 ? z*2 : -z*2-1, sum = a+b
        return -1-(sum*(sum+1)/2+b)
    }

    static func from(_ key: Int, count: Int, seed: Int = 0) -> Region {
        if key>=0 { let width = Atlas.columns(count); return Region(x:key%width,z:key/width,seed:seed) }
        let n = -1-key
        var diagonal = Int((sqrt(Double(n)*8+1)-1)/2)
        if diagonal*(diagonal+1)/2>n { diagonal -= 1 }
        let b = n-diagonal*(diagonal+1)/2, a = diagonal-b
        return Region(x:a%2 == 0 ? a/2 : -(a+1)/2,z:b%2 == 0 ? b/2 : -(b+1)/2,seed:seed)
    }

    func historical(_ world: World) -> Bool {
        world == .overworld && max(abs(x*Self.span),abs(z*Self.span))>=Self.farLands-Self.span
    }

    func landmark(_ world: World) -> Bool {
        if historical(world) { return false }
        return key(world.biomes.count)>=0 || Terrain.random(x,z,seed:seed &+ 731 &+ (World.allCases.firstIndex(of:world) ?? 0))<0.18
    }

    func biome(_ world: World) -> Int {
        let key = key(world.biomes.count)
        if key>=0 { return key }
        if historical(world) { return world.biomes.firstIndex(of:.forest) ?? 0 }
        let temperature = Terrain.noise(Double(x),Double(z),scale:4.3,seed:seed &+ 431)
        let humidity = Terrain.noise(Double(x),Double(z),scale:3.7,seed:seed &+ 432)
        let continent = Terrain.noise(Double(x),Double(z),scale:6.1,seed:seed &+ 433)
        let erosion = Terrain.noise(Double(x),Double(z),scale:2.9,seed:seed &+ 434)
        let biome: Biome
        switch world {
        case .overworld:
            if continent < -0.4 { biome = continent < -0.62 ? .monument : temperature>0.2 ? .reef : .coast }
            else if erosion>0.5 { biome = temperature < -0.1 ? .peaks : .badlands }
            else if temperature < -0.35 { biome = humidity < -0.2 ? .ice : .snow }
            else if temperature>0.3 { biome = humidity < -0.25 ? .desert : humidity>0.3 ? .jungle : .savanna }
            else if humidity>0.38 { biome = temperature>0.1 ? .mangrove : .swamp }
            else if humidity < -0.42 { biome = erosion < -0.3 ? .mushroom : .meadow }
            else if erosion < -0.45 { biome = humidity>0 ? .mansion : .pale }
            else { biome = humidity>0.1 ? .forest : temperature>0.05 ? .cherry : .river }
        case .nether: biome = erosion>0.35 ? .basalt : humidity>0.2 ? .crimson : humidity < -0.2 ? .warped : temperature < -0.25 ? .soul : .wastes
        case .end: biome = continent < -0.2 ? .islands : erosion>0.25 ? .highlands : humidity>0.25 ? .city : temperature < -0.2 ? .barrens : .midlands
        case .sift: biome = continent < -0.2 ? .shards : humidity>0.25 ? .grove : erosion>0.2 ? .valley : temperature < -0.25 ? .sculk : humidity < -0.2 ? .ruins : .terraces
        }
        return world.biomes.firstIndex(of:biome) ?? 0
    }

    var neighbours: [Region] { [.init(x:x-1,z:z,seed:seed),.init(x:x+1,z:z,seed:seed),.init(x:x,z:z-1,seed:seed),.init(x:x,z:z+1,seed:seed)] }
}

struct Chunk: Hashable {
    static let size = 16
    let x: Int
    let z: Int
    init(x: Int, z: Int) { self.x = x; self.z = z }
    init(at p: SCNVector3) { x = Int(floor((p.x+0.5)/16)); z = Int(floor((p.z+0.5)/16)) }
    var origin: SCNVector3 { .init(Double(x*16),0,Double(z*16)) }
    var region: Region {
        region(seed:0)
    }
    func region(seed: Int) -> Region {
        Region(x:Int(floor((Double(x*16)+Double(Region.span/2)+8)/Double(Region.span))),z:Int(floor((Double(z*16)+Double(Region.span/2)+40)/Double(Region.span))),seed:seed)
    }
}

final class Section: SCNNode {
    var x = 0
    var z = 0
}

final class Surface: SCNNode {
    var profile: Terrain.Profile?
    var registered = false
}

extension Terrain {
    struct Profile {
        let terrain: Terrain
        let sample: ((Int,Int) -> Double)?
        var covered: Set<SIMD3<Int>> = []
    }

    // This bounded wall-and-tunnel study evokes historical Far Lands without emulating the old generator
    static func farLands(assets: Assets, chunk: Chunk) throws -> Section {
        let stone = try assets.tiles("stone"), grass = try assets.tiles("grass_block"), bedrock = try assets.tiles("bedrock")
        let low = -28, high = 128, height = high-low+2, width = 18
        var solid = Array(repeating:false,count:width*width*height)
        func key(_ x: Int, _ y: Int, _ z: Int) -> Int { ((x+1)*width+z+1)*height+y-low+1 }
        let gx = chunk.x*16, gz = chunk.z*16
        for x in -1...16 { for z in -1...16 { for y in (low-1)...high {
            let px = gx+x, pz = gz+z, axis = max(abs(px),abs(pz))
            let across = abs(px)>=abs(pz) ? pz : px, depth = axis-Region.farLands
            let density = noise(Double(across),Double(y)*1.7,scale:17,seed:911) +
                noise(Double(depth),Double(y),scale:11,seed:912)*0.28 +
                sin(Double(y)*0.35+Double(across)*0.06)*0.22
            solid[key(x,y,z)] = y<4 || y<high && axis>=Region.farLands && density>(-0.08)
        } } }
        var mesh = Voxels()
        for x in 0..<16 { for z in 0..<16 { for y in low..<high where solid[key(x,y,z)] {
            var mask = 0
            for (face,d) in [(0,0,1),(1,0,0),(0,0,-1),(-1,0,0),(0,1,0),(0,-1,0)].enumerated() {
                if !solid[key(x+d.0,y+d.1,z+d.2)] { mask |= 1 << face }
            }
            guard mask != 0 else { continue }
            let materials = y == low ? bedrock : mask&16 != 0 && y>40 ? grass : stone
            mesh.cube(.init(1,1,1),at:.init(Double(x),Double(y)+0.5,Double(z)),material:materials[0],faces:mask,faceMaterials:materials)
        } } }
        let section = Section(); section.addChildNode(mesh.node("historical-far-lands"))
        return section
    }
}

// One asset queue builds only the nearest missing terrain, independently of the five landmark graphs
final class Stream {
    let root = SCNNode()
    private(set) var chunks: [Chunk:Section] = [:]
    private let assets: Assets
    private let world: World
    private let seed: Int
    private let failed: () -> Void
    private var profiles: [Region:Terrain.Profile] = [:]
    private var requests: [Chunk:Operation] = [:]
    private var wanted = Set<Chunk>()
    private var pending: [Chunk] = []
    private var centre: Chunk?
    private var radius = 8
    private var origin = SCNVector3Zero
    private var fluids: [ObjectIdentifier:(SCNMaterial,SCNNode,Int)] = [:]
    private var surfaces: [Chunk:[ObjectIdentifier]] = [:]
    private var disposed = false
    private var paused = false
    private var eye: SCNVector3?
    private var illumination = 1.0
    var limit: Int { (radius*2+1)*(radius*2+1) }
    var outstanding: Int { requests.count+pending.count }

    init(world: World, assets: Assets, seed: Int = 0, failed: @escaping () -> Void) {
        self.world = world; self.assets = assets; self.seed = seed; self.failed = failed; root.name = "streamed-terrain"
    }

    func distance(_ chunks: Int) { radius = min(16,max(4,chunks)); centre = nil }

    func pause(_ enabled: Bool) {
        guard !disposed, enabled != paused else { return }
        paused = enabled
        for operation in requests.values { operation.cancel() }
        requests = [:]; pending = []; centre = nil
        if !paused, let eye { update(at:eye) }
    }

    func rebase(_ point: SCNVector3) {
        origin = point
        for (key,node) in chunks {
            let p = key.origin; node.position = .init(p.x-origin.x,world.biomes[key.region(seed:seed).biome(world)].level,p.z-origin.z)
        }
    }

    func update(at eye: SCNVector3, build: Bool = true) {
        guard !disposed, Region.at(eye,seed:seed) != nil else { return }
        self.eye = eye
        let next = Chunk(at:eye)
        if next != centre {
            centre = next
            wanted = Set((-radius...radius).flatMap { x in (-radius...radius).map { Chunk(x:next.x+x,z:next.z+$0) } })
            for key in Array(chunks.keys) where !wanted.contains(key) { remove(key) }
            for key in Array(requests.keys) where !wanted.contains(key) { requests.removeValue(forKey:key)?.cancel() }
            let regions = Set(wanted.map { $0.region(seed:seed) })
            profiles = profiles.filter { regions.contains($0.key) }
            pending = paused ? [] : wanted.filter { chunks[$0] == nil && requests[$0] == nil }.sorted {
                let a = ($0.x-next.x)*($0.x-next.x)+($0.z-next.z)*($0.z-next.z)
                let b = ($1.x-next.x)*($1.x-next.x)+($1.z-next.z)*($1.z-next.z)
                return a == b ? ($0.x == $1.x ? $0.z<$1.z : $0.x<$1.x) : a<b
            }
        }
        if build { pump() }
    }

    func register(_ scene: SCNScene, region: Region) {
        var foundations: Set<SIMD3<Int>>?
        for surface in scene.rootNode.childNodes.compactMap({ $0 as? Surface }) {
            if var profile = surface.profile {
                if !surface.registered {
                    if foundations == nil { foundations = Structures.foundations(scene.rootNode) }
                    profile.covered.formUnion(foundations!); surface.profile = profile; surface.registered = true
                }
                profiles[region] = profile
            }
        }
    }

    func adopt(_ scene: SCNScene, region: Region) {
        register(scene,region:region)
        for surface in scene.rootNode.childNodes.compactMap({ $0 as? Surface }) {
            for section in surface.childNodes.compactMap({ $0 as? Section }) {
                let key = Chunk(x:region.x*(Region.span/16)+section.x/16,z:region.z*(Region.span/16)+section.z/16)
                section.removeFromParentNode()
                guard wanted.contains(key), !region.historical(world) else { continue }
                requests.removeValue(forKey:key)?.cancel()
                remove(key); attach(section,at:key)
            }
            for child in surface.childNodes { child.removeFromParentNode() }
        }
        centre = nil
        if let eye { update(at:eye,build:false) }
        pump()
    }

    private func attach(_ node: Section, at key: Chunk) {
        chunks[key] = node
        let p = key.origin; node.position = .init(p.x-origin.x,world.biomes[key.region(seed:seed).biome(world)].level,p.z-origin.z); root.addChildNode(node)
        var ids = Set<ObjectIdentifier>()
        node.enumerateChildNodes { child,_ in
            for material in child.geometry?.materials ?? [] where material.name?.contains("water") == true || material.name?.contains("lava") == true {
                let id = ObjectIdentifier(material)
                guard ids.insert(id).inserted else { continue }
                if material.name?.contains("water") == true { material.diffuse.intensity = illumination }
                if let old = fluids[id] { fluids[id] = (old.0,old.1,old.2+1) }
                else {
                    let controller = SCNNode(); controller.name = "fluid-atlas"
                    Landscape.animate(controller,material:material); root.addChildNode(controller); fluids[id] = (material,controller,1)
                }
            }
        }
        surfaces[key] = Array(ids)
    }

    private func remove(_ key: Chunk) {
        chunks.removeValue(forKey:key)?.removeFromParentNode()
        for id in surfaces.removeValue(forKey:key) ?? [] {
            guard let old = fluids[id] else { continue }
            if old.2 == 1 { old.1.removeFromParentNode(); fluids[id] = nil }
            else { fluids[id] = (old.0,old.1,old.2-1) }
        }
    }

    private func pump() {
        guard !disposed, !paused else { return }
        while requests.count<4 && !pending.isEmpty {
            let key = pending.removeFirst()
            guard wanted.contains(key), chunks[key] == nil, requests[key] == nil else { continue }
            let region = key.region(seed:seed), index = region.biome(world)
            let profile = profiles[region] ?? Terrain.Profile(terrain:Terrain(biome:world.biomes[index],authored:region.landmark(world),worldSeed:region.landmark(world) ? 0 : seed),sample:nil)
            let operation = BlockOperation()
            operation.addExecutionBlock { [weak self,weak operation] in
                guard let self, let operation, !operation.isCancelled else { return }
                let result = Result { () -> Section in
                    if region.historical(self.world) { return try Terrain.farLands(assets:self.assets,chunk:key) }
                    let x = key.x*16-region.x*Region.span, z = key.z*16-region.z*Region.span
                    let node = try profile.terrain.node(assets:self.assets,x:x..<(x+16),z:z..<(z+16),bounded:false,region:region,covered:profile.covered,height:profile.sample)
                    guard let section = node.childNodes.first(where:{ $0 is Section }) as? Section else { throw AssetError.model }
                    section.removeFromParentNode(); return section
                }
                SCNTransaction.flush()
                DispatchQueue.main.async { [weak self,weak operation] in
                    guard let self, let operation, !operation.isCancelled, !self.disposed, self.requests[key] === operation else { return }
                    self.requests[key] = nil
                    switch result {
                    case .success(let node): if self.wanted.contains(key) { self.attach(node,at:key) }
                    case .failure: self.failed()
                    }
                    self.pump()
                }
            }
            requests[key] = operation; assets.queue.addOperation(operation)
        }
    }

    func illuminate(_ daylight: Double) {
        illumination = 0.2+0.8*min(1,max(0,daylight))
        for (material,_,_) in fluids.values where material.name?.contains("water") == true { material.diffuse.intensity = illumination }
    }

    func contains(_ point: SCNVector3) -> Bool { chunks[Chunk(at:point)] != nil }

    func constrain(_ point: SCNVector3, from start: SCNVector3) -> SCNVector3 {
        if Region.at(point,seed:seed) != nil && contains(point) { return point }
        let p = Chunk(at:start).origin
        return .init(min(p.x+15.49,max(p.x-0.49,point.x)),point.y,min(p.z+15.49,max(p.z-0.49,point.z)))
    }

    func dispose() {
        disposed = true
        for operation in requests.values { operation.cancel() }
        requests = [:]; pending = []; wanted = []; profiles = [:]
        for key in Array(chunks.keys) { remove(key) }
        root.removeFromParentNode()
    }
}
