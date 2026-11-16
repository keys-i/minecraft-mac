import AppKit
import SceneKit
import SpriteKit
import SwiftUI

struct MapMarker: Equatable {
    enum Kind: Equatable { case mob, structure }
    let x: Double
    let z: Double
    let kind: Kind
}

struct DebugSnapshot: Equatable {
    var biome = "Unknown"
    var loaded = 0
    var rendered = 0
    var distance = 0
    var daylight = 0
    var nightVision = false
    var fps = 0.0
    var scale = 1.0
    var device = "Metal"
}

@MainActor
final class Chart: ObservableObject {
    var data = WorldData(dimension:0)
    @Published var revision = 0
    @Published var message: String?
    @Published var error: String?
    @Published var progress: Double?
    @Published var visible = false
    @Published var arrival: String?
    @Published var mobs: [MapMarker] = []
    @Published var debug = DebugSnapshot()
    var retry: (() -> Void)?
    var skip: (() -> Void)?
    var owner = UUID()

    func install(_ data: WorldData) { self.data = data; revision += 1 }
}

struct Expedition: NSViewRepresentable {
    let world: World
    let biome: Int
    let seed: String
    let assets: Assets
    let root: URL
    @ObservedObject var chart: Chart
    let exploring: Bool
    let moving: Bool
    let active: Bool
    let distance: Int
    let sensitivity: Double
    let inverted: Bool
    let controls: Controls
    let finish: () -> Void
    let location: (String?) -> Void
    let report: ((SCNVector3,Double) -> Void)?
    let activity: (Bool) -> Void
    let cinematic: Bool
    let arrived: (World) -> Void
    var resolution: (Double) -> Void = { _ in }

    @MainActor final class Coordinator {
        enum Preparation {
            case chunks(Trail.Record,Set<Chunk>)
            case ready(Trail,[Trail.Stop],SCNNode?,SCNNode,SCNNode,WorldData,[Chunk:Horizon.Tile])
        }
        weak var view: FlightView?
        let chart: Chart
        let assets: Assets
        let root: URL
        var world: World?
        var seed = ""
        var biome = -1
        var data = WorldData(dimension:0)
        var nodes: [Chunk:SCNNode] = [:]
        var mesh: Operation?
        var generation: Generation?
        var wanted = Set<Chunk>()
        var region: Chunk?
        var radius = 16
        var halo = Set<Chunk>()
        var dirty = Set<Chunk>()
        var blocked = 0.0
        var reroutes = 0
        var litMaterials: [ObjectIdentifier:SCNMaterial] = [:]
        var database: URL?
        var destinations: [[String:Any]] = []
        var target: SCNVector3?
        var landing: SCNVector3?
        var speed = 0.0
        var request = 0
        var elapsed = 0.0
        var reported = 0.0
        var lighting = -1
        var nightVision = false
        var home = SCNVector3Zero
        var initial = true
        var disposed = false
        var location: (String?) -> Void = { _ in }
        var report: ((SCNVector3,Double) -> Void)?
        var onReady: (() -> Void)?
        var crowd: Crowd?
        var population: Operation?
        var populated = SCNVector3Zero
        var reader: Operation?
        var reading: Bool { reader != nil }
        var installing = false
        var transitions = true
        var activity: (Bool) -> Void = { _ in }
        var arrived: (World) -> Void = { _ in }
        var plans: [Trail.Record] = []
        var restored = false
        var route: [Trail.Stop] = []
        var waypoint = 0
        var pending: (World,Int)?
        var passage: Operation?
        var planning: Trail.Record?
        var geometryRevision = 0
        var doors: [Door] = []
        var guide: SCNNode?
        var revisit = false
        var prefetch = Set<Chunk>()
        var veil: SCNNode?
        var environmentFog: NSColor = .black
        var horizon = 16.0
        var doorGroups: [Chunk:[Door]] = [:]
        var continuation: (World,Int)?
        let identity = UUID()
        var dragon: SCNNode?
        var healing: (@Sendable (CGFloat) -> Void)?
        var crystals = Set<Cell>()
        var greeting = false
        var wasExploring = false
        var idleAim = SCNVector3(12,1,-22)
        var lastBiome: String?
        var repairs: [Chunk:Int] = [:]
        var horizonMap = Horizon()
        var coverage = 0
        var cruise = 3.0
        var portalCover: SCNNode?
        var streaming = true {
            didSet {
                if streaming && !oldValue {
                    if let pending, route.isEmpty {begin(pending.0)}
                    else if initial {visit()}
                    else if let eye = view?.pointOfView?.position {updateRegion(at:eye,force:true)}
                } else if !streaming && oldValue {
                    generation?.cancel(); generation = nil
                    reader?.cancel(); reader = nil
                    mesh?.cancel(); mesh = nil
                    passage?.cancel(); passage = nil
                    horizonMap.cancel()
                }
            }
        }
        var near: Int { min(16,radius) }
        var entry: Set<Chunk> {
            guard let region else {return []}
            return Set((-2...2).flatMap {dx in (-2...2).map {Chunk(x:region.x+dx,z:region.z+$0)}})
        }
        var entryHalo: Set<Chunk> {
            guard let region else {return []}
            return Set((-3...3).flatMap {dx in (-3...3).map {Chunk(x:region.x+dx,z:region.z+$0)}})
        }
        var entryReady: Bool {
            !entry.isEmpty && entry.allSatisfy {nodes[$0] != nil} && entryHalo.allSatisfy {data.chunks[$0] != nil}
        }
        func nearby(_ key: Chunk) -> Bool { region.map {Horizon.within(key,of:$0,radius:near)} ?? true }
        func retained(_ key: Chunk) -> Bool {prefetch.contains(key) || (region.map {Horizon.within(key,of:$0,radius:near+1)} ?? true)}
        func missing(_ key: Chunk) -> Bool {
            if retained(key) || prefetch.contains(key) {return data.chunks[key] == nil}
            guard let tile = horizonMap.tiles[key], let region else {return true}
            return tile.step>Horizon.step(key,near:region)
        }

        init(chart: Chart, assets: Assets, root: URL) { self.chart = chart; self.assets = assets; self.root = root; chart.owner = identity }

        func configure(world: World, seed: String, biome: Int, cinematic: Bool = false) {
            if let continuation, continuation.0 == world, self.seed == seed {
                if !cinematic {reset(world:world,seed:seed,biome:biome)}
                return
            }
            if let pending, pending.0 == world, self.seed == seed {
                if !cinematic { reset(world:world,seed:seed,biome:biome) }
                return
            }
            if self.world != world, self.seed == seed, !initial, cinematic, transitions, world == .nether || world == .end {
                if self.world != .overworld {
                    reset(world:.overworld,seed:seed,biome:0); continuation = (world,biome); return
                }
                pending = (world,biome); begin(world); return
            }
            if pending != nil { passage?.cancel(); passage = nil; pending = nil; planning = nil; prefetch = []; route = []; guide?.removeFromParentNode(); guide = nil; veil?.removeFromParentNode(); veil = nil; activity(false) }
            guard self.world != world || self.seed != seed else {
                if self.biome != biome { self.biome = biome; visit() }
                return
            }
            reset(world:world,seed:seed,biome:biome)
        }

        private func reset(world: World, seed: String, biome: Int) {
            request += 1; generation?.cancel(); generation = nil; mesh?.cancel(); mesh = nil
            reader?.cancel(); reader = nil
            horizonMap.clear(); coverage = 0
            halo = []; dirty = []; litMaterials = [:]; blocked = 0; reroutes = 0; nightVision = false
            continuation = nil; doorGroups = [:]; repairs = [:]
            dragon = nil; healing = nil; crystals = []; greeting = false
            wasExploring = false; idleAim = .init(12,1,-22)
            passage?.cancel(); passage = nil; pending = nil; route = []; guide = nil; veil = nil; doors = []; plans = []; restored = false; prefetch = []; revisit = false
            planning = nil
            population?.cancel(); population = nil; crowd = nil
            self.world = world; self.seed = seed; self.biome = biome
            data = WorldData(dimension:world.dimension!); nodes = [:]; wanted = []; region = nil
            database = nil; destinations = []; initial = true; installing = false; target = nil; landing = nil; speed = 0
            chart.error = nil; chart.visible = false; chart.mobs = []; chart.debug = DebugSnapshot()
            visit()
        }

        func begin(_ destination: World) {
            guard passage == nil, let eye = view?.pointOfView?.position, let database else { return }
            target = nil; speed = 0; blocked = 0; reroutes = 0; activity(true); chart.error = nil; chart.message = "Finding a path beneath your world"
            let snapshot = data, seed = seed, token = request, saved = plans, centre = region ?? .init(x:0,z:0), prepared = planning
            let operation = BlockOperation(), file = database.deletingLastPathComponent().appendingPathComponent("journeys-\(data.dimension).json")
            operation.addExecutionBlock { [weak self,weak operation] in
                guard let self, let operation, !operation.isCancelled else { return }
                let result = Result { () -> Preparation in
                    let kind = destination == .nether ? "nether" : "end"
                    guard let record = prepared ?? saved.first(where:{$0.kind == kind}) ?? Trail.anchor(data:snapshot,eye:eye,destination:destination,seed:seed) else { throw ChunkError.database("Explore a little farther before entering this portal") }
                    let required = Trail.coverage(record)
                    if required.contains(where:{snapshot.chunks[$0] == nil}) {return .chunks(record,required)}
                    let trail = try Trail.plan(record,data:snapshot,cancelled:{operation.isCancelled})
                    var plans = saved.filter { $0.kind != kind }; plans.append(trail.record)
                    // Replace owned overrides so a migrated route cannot retain its old excavations
                    var rebuilt = snapshot; rebuilt.edits = [:]; rebuilt.columns = [:]
                    for plan in plans {rebuilt.apply(plan.kind == kind ? trail.blocks : Trail(plan).blocks)}
                    var approach = trail.approach(data:rebuilt,eye:eye,chest:destination == .end)
                    approach += trail.route
                    let changed = Set(snapshot.edits.keys).union(rebuilt.edits.keys)
                    let tiles = snapshot.chunks.filter {changed.contains($0.key)}.mapValues {Horizon.Tile($0,near:centre,data:rebuilt)}
                    guard !operation.isCancelled else {throw CancellationError()}
                    if (try? file.resourceValues(forKeys:[.isSymbolicLinkKey]).isSymbolicLink) == true { throw ChunkError.format }
                    let backup = file.appendingPathExtension("v\(record.version ?? 1)")
                    if record != trail.record, FileManager.default.fileExists(atPath:file.path), !FileManager.default.fileExists(atPath:backup.path) {
                        try FileManager.default.copyItem(at:file,to:backup)
                    }
                    let bytes = try JSONEncoder().encode(plans)
                    guard bytes.count<=2*1024*1024 else {throw ChunkError.format}
                    guard !operation.isCancelled else {throw CancellationError()}
                    try bytes.write(to:file,options:[.atomic,.completeFileProtectionUnlessOpen])
                    let guide: SCNNode?
                    if destination == .end {
                        let plane = SCNPlane(width:0.28,height:0.28); plane.firstMaterial = try self.assets.texture("textures/items/ender_eye")
                        guide = SCNNode(geometry:plane); guide?.constraints = [SCNBillboardConstraint()]; guide?.name = "eye-of-ender"
                    } else { guide = nil }
                    let material = try self.assets.overlay(end:destination == .end)
                    let plane = SCNPlane(width:1.2,height:0.8); plane.firstMaterial = material
                    let veil = SCNNode(geometry:plane); veil.name = "portal-distortion"; veil.position.z = -0.3; veil.opacity = 0; veil.renderingOrder = 1000
                    Landscape.animate(veil,material:material)
                    return .ready(trail,approach,guide,try trail.decoration(assets:self.assets),veil,rebuilt,tiles)
                }
                DispatchQueue.main.async {
                    guard !operation.isCancelled, self.request == token, !self.disposed else { return }
                    self.passage = nil
                    switch result {
                    case .failure(let error): self.chart.error = error.localizedDescription; self.chart.message = nil
                    case .success(.chunks(let record,let required)):
                        self.planning = record; self.prefetch = required
                        self.generate(Array(required.filter {self.data.chunks[$0] == nil}))
                    case .success(.ready(let trail,let route,let guide,let decoration,let veil,let rebuilt,let tiles)):
                        self.planning = nil
                        self.plans.removeAll { $0.kind == trail.record.kind }; self.plans.append(trail.record)
                        let changed = Set(self.data.edits.keys).union(rebuilt.edits.keys)
                        self.data.edits = rebuilt.edits; self.data.columns = rebuilt.columns
                        self.chart.install(self.data)
                        for key in changed {self.horizonMap.tiles.removeValue(forKey:key)}
                        self.horizonMap.insert(tiles)
                        self.prefetch.formUnion(changed)
                        self.invalidate(changed)
                        self.route = route; self.waypoint = 0; self.guide = guide
                        let length = zip(route,route.dropFirst()).reduce(0.0) { sum,pair in
                            let a = pair.0.point, b = pair.1.point
                            return sum+hypot(hypot(b.x-a.x,b.z-a.z),b.y-a.y)
                        }
                        self.cruise = max(1,min(8,length/165))
                        self.veil = veil; self.view?.pointOfView?.addChildNode(veil)
                        self.view?.scene?.rootNode.childNode(withName:decoration.name!,recursively:false)?.removeFromParentNode()
                        self.view?.scene?.rootNode.addChildNode(decoration)
                        if let guide { self.view?.scene?.rootNode.addChildNode(guide) }
                        self.pump()
                        self.generate(Array(changed.filter { self.data.chunks[$0] == nil }))
                    }
                }
            }
            passage = operation; assets.queue.addOperation(operation)
        }

        func visit() {
            guard let world else { return }
            if generation != nil || reading { revisit = true; return }
            if let locator = world.biomes[world.index(biome)].locator {
                if let point = destinations.first(where:{ $0["id"] as? String == locator.id }) { travel(point); return }
                generate([],locators:[["kind":locator.kind,"id":locator.id]])
            } else {
                travel(["x":world == .end ? 0 : 8,"z":world == .end ? 0 : 8])
            }
        }

        func travel(_ value: [String:Any]) {
            guard let x = value["x"] as? Int, let z = value["z"] as? Int else { return }
            landing = .init(Double(x)+0.5,Double(value["y"] as? Int ?? 320),Double(z)+0.5)
            if initial { home = landing!; region = nil; updateRegion(at:home) }
            else { target = landing; speed = 0 }
        }

        func updateRegion(at point: SCNVector3, force: Bool = false) {
            let next = WorldData.key(Int(floor(point.x)),Int(floor(point.z)))
            guard force || next != region || coverage != radius else { return }
            let moved = next != region || coverage != radius
            let previous = region
            let resized = coverage != radius
            let oldNear = min(16,coverage)
            region = next
            coverage = radius
            if moved {
                horizonMap.ring = near+1
                var affected = Horizon.boundary(next,radius:near)
                if let previous {affected.formUnion(Horizon.boundary(previous,radius:oldNear))}
                if let pending = horizonMap.pending {
                    let dx = max(pending.x*16-next.x,next.x-(pending.x*16+15),0)
                    let dz = max(pending.z*16-next.z,next.z-(pending.z*16+15),0)
                    if oldNear != near || affected.contains(pending) || max(dx,dz)>radius {horizonMap.cancel()}
                }
                horizonMap.dirty.formUnion(affected)
                if previous.map(Horizon.page) != Horizon.page(next) || resized {horizonMap.prune(near:next,radius:radius)}
            }
            wanted = Set((-near...near).flatMap { dx in (-near...near).map { Chunk(x:next.x+dx,z:next.z+$0) } })
            halo = Set(((-near-1)...(near+1)).flatMap {dx in ((-near-1)...(near+1)).map {Chunk(x:next.x+dx,z:next.z+$0)}})
            while horizonMap.ring<=radius {
                let ring = Horizon.shell(next,radius:horizonMap.ring)
                if ring.allSatisfy({!missing($0) && !horizonMap.dirty.contains(Horizon.page($0)) && horizonMap.pending != Horizon.page($0)}) {horizonMap.ring += 1}
                else {wanted.formUnion(ring); break}
            }
            for key in Array(nodes.keys) where !nearby(key) {
                nodes.removeValue(forKey:key)?.removeFromParentNode(); doorGroups.removeValue(forKey:key); dirty.remove(key)
            }
            doors = doorGroups.values.flatMap {$0}
            data.chunks = data.chunks.filter { retained($0.key) }
            let missing = wanted.union(halo).filter { self.missing($0) }
            if !missing.isEmpty {
                let first = initial ? missing.intersection(entryHalo) : []
                let ordered = (first.isEmpty ? missing : first).sorted {
                    hypot(Double($0.x-next.x),Double($0.z-next.z))<hypot(Double($1.x-next.x),Double($1.z-next.z))
                }
                generate(ordered)
            }
            pump()
            distant()
        }

        static func batch(_ chunks: Set<Chunk>, near centre: Chunk) -> [Chunk] {
            Array(chunks.sorted {
                let a = hypot(Double($0.x)-Double(centre.x),Double($0.z)-Double(centre.z))
                let b = hypot(Double($1.x)-Double(centre.x),Double($1.z)-Double(centre.z))
                return a == b ? ($0.x == $1.x ? $0.z<$1.z : $0.x<$1.x) : a<b
            }.prefix(1225))
        }

        func invalidate(_ changed: Set<Chunk>) {
            guard !changed.isEmpty else { return }
            geometryRevision += 1; mesh?.cancel(); mesh = nil
            horizonMap.cancel()
            for key in changed {for dx in -1...1 {for dz in -1...1 {
                let neighbour = Chunk(x:key.x+dx,z:key.z+dz)
                if nodes[neighbour] != nil {dirty.insert(neighbour)}
                horizonMap.dirty.insert(Horizon.page(neighbour))
            } } }
        }

        func visibleDistance(at eye: SCNVector3) -> Double {
            Double(min(radius,max(near,horizonMap.ring-1))*16)
        }

        func generate(_ chunks: [Chunk], locators: [[String:String]] = [], refresh: Set<Chunk> = []) {
            guard generation == nil, !reading, !disposed, streaming,
                  !chunks.isEmpty || !locators.isEmpty else { return }
            let chunks = Self.batch(Set(chunks),near:region ?? .init(x:0,z:0))
            let token = request
            var ready: [String:Any]?
            chart.error = nil
            chart.message = locators.isEmpty ? "Preparing the next chunks" : "Finding your destination"
            chart.progress = nil
            let operation = Generation(root:root,request:["seed":seed,"dimension":data.dimension,
                "chunks":chunks.map { [$0.x,$0.z] },"refresh":chunks.filter {refresh.contains($0)}.map {[$0.x,$0.z]},"locate":locators],receive:{ [weak self] value in
                guard let self, self.request == token, !self.disposed else { return }
                if value["state"] as? String == "world_ready" { ready = value }
                else if value["state"] as? String == "progress" {
                    self.chart.message = value["detail"] as? String; self.chart.progress = value["progress"] as? Double
                }
            },complete:{ [weak self] error in
                guard let self, self.request == token, !self.disposed else { return }
                self.generation = nil
                if let error { self.chart.error = error.localizedDescription; self.chart.message = nil; return }
                guard let ready, let path = ready["database"] as? String, let manifest = ready["manifest"] as? String,
                      URL(fileURLWithPath:path).standardizedFileURL.path.hasPrefix(self.root.appendingPathComponent("scenery/worlds").standardizedFileURL.path+"/") else {
                    self.chart.error = "The world wasn’t saved; choose the destination again"; self.chart.message = nil; return
                }
                self.database = URL(fileURLWithPath:path)
                self.load(chunks,manifest:URL(fileURLWithPath:manifest),token:token,discovered:!locators.isEmpty)
            })
            generation = operation; Generation.queue.addOperation(operation)
            activity(true)
        }

        func load(_ chunks: [Chunk], manifest: URL, token: Int, discovered: Bool) {
            guard let database else { return }
            let operation = BlockOperation(), dimension = data.dimension, restore = !restored, centre = region ?? .init(x:0,z:0), snapshot = data
            operation.addExecutionBlock { [weak self,weak operation] in
                guard let self, let operation, !operation.isCancelled else { return }
                let result = Result { () -> ([Chunk:VoxelChunk],[[String:Any]],[Trail],Set<Chunk>,[Chunk:Horizon.Tile]) in
                    let database = try Database(database)
                    var loaded: [Chunk:VoxelChunk] = [:]
                    var missing = Set<Chunk>()
                    for key in chunks {
                        guard !operation.isCancelled else { throw CancellationError() }
                        if let value = try database.chunk(key,dimension:dimension) { loaded[key] = value }
                        else { missing.insert(key) }
                    }
                    let metadata = try Data(contentsOf:manifest)
                    guard metadata.count<=4*1024*1024, let value = try JSONSerialization.jsonObject(with:metadata) as? [String:Any] else { throw ChunkError.format }
                    var trails: [Trail] = []
                    let file = manifest.deletingLastPathComponent().appendingPathComponent("journeys-\(dimension).json")
                    if restore, FileManager.default.fileExists(atPath:file.path) {
                        let bytes = try Data(contentsOf:file)
                        guard bytes.count<=2*1024*1024 else { throw ChunkError.format }
                        let records = try JSONDecoder().decode([Trail.Record].self,from:bytes)
                        guard records.count<=2, Set(records.map(\.kind)).count == records.count, records.allSatisfy(\.valid) else { throw ChunkError.format }
                        trails = records.map(Trail.init)
                    }
                    var terrain = snapshot; terrain.chunks.merge(loaded) {_,new in new}
                    for trail in trails {terrain.apply(trail.blocks)}
                    return (loaded,(value["destinations"] as? [[String:Any]] ?? []).filter { $0["dimension"] as? Int == dimension },trails,missing,loaded.mapValues {Horizon.Tile($0,near:centre,data:terrain)})
                }
                DispatchQueue.main.async {
                    guard !operation.isCancelled, !self.disposed, self.request == token else { return }
                    self.reader = nil
                    switch result {
                    case .failure(let error): self.chart.error = error.localizedDescription; self.chart.message = nil
                    case .success(let (loaded,destinations,trails,missing,tiles)):
                        let changed = Set(loaded.keys.filter {self.data.chunks[$0] == nil})
                        self.data.chunks.merge(loaded.filter {self.retained($0.key)}) { _,new in new }; self.destinations = destinations
                        self.invalidate(changed)
                        self.horizonMap.insert(tiles)
                        if restore {
                            self.restored = true; self.plans = trails.map(\.record)
                            for trail in trails { self.data.apply(trail.blocks) }
                        }
                        self.chart.install(self.data)
                        if !missing.isEmpty {
                            for key in missing {self.repairs[key,default:0] += 1}
                            guard missing.allSatisfy({self.repairs[$0,default:0]<=2}) else {
                                self.chart.error = "Some chunks couldn’t be saved; try again"; self.chart.message = nil; return
                            }
                            self.generate(Array(missing),refresh:missing); self.pump(); return
                        }
                        if self.planning != nil, let pending = self.pending {
                            let missing = self.prefetch.filter {self.data.chunks[$0] == nil}
                            if missing.isEmpty {self.begin(pending.0)}
                            else {self.generate(Array(missing))}
                            self.pump(); return
                        }
                        if !self.initial {self.greet()}
                        if discovered {
                            if let locator = self.world?.biomes[self.world!.index(self.biome)].locator,
                               !destinations.contains(where:{$0["id"] as? String == locator.id}) {
                                self.chart.error = "This destination wasn’t found nearby; choose another biome or try again"
                                self.chart.message = nil; self.activity(false)
                            } else { self.visit() }
                        }
                        else if self.revisit { self.revisit = false; self.visit() }
                        else {
                            self.updateRegion(at:self.initial ? self.home : self.view?.pointOfView?.position ?? self.home,force:true)
                            let missing = self.wanted.union(self.halo).union(self.prefetch).filter { self.missing($0) }
                            if !missing.isEmpty { self.generate(Array(missing)) }
                            self.pump()
                        }
                    }
                }
            }
            reader = operation; Generation.queue.addOperation(operation)
        }

        private func spawn(near point: SCNVector3) -> SCNVector3? {
            let px = Int(floor(point.x)), pz = Int(floor(point.z))
            for ring in 0...16 { for dx in -ring...ring { for dz in -ring...ring where ring == 0 || abs(dx) == ring || abs(dz) == ring {
                let x = px+dx, z = pz+dz
                if data.dimension == 1 || point.y<128 {
                    for y in stride(from:min(118,Int(point.y)),through:data.dimension == 0 ? -63 : 1,by:-1) {
                        let feet = SCNVector3(Double(x)+0.5,Double(y),Double(z)+0.5)
                        if let block = data.block(x,y-1,z), (!block.passable || block.fluid), data.vacant(feet) { return feet }
                    }
                } else if let y = data.surface(x,z), let block = data.block(x,y,z), !block.air {
                    let feet = SCNVector3(Double(x)+0.5,Double(y)+1,Double(z)+0.5)
                    if data.vacant(feet) { return feet }
                }
            } } }
            return nil
        }

        func pump() {
            guard mesh == nil, !disposed, streaming, let view else { return }
            let centre = region ?? .init(x:0,z:0)
            guard let key = wanted.filter({nearby($0) && (nodes[$0] == nil || dirty.contains($0)) && data.chunks[$0] != nil}).min(by:{
                hypot(Double($0.x-centre.x),Double($0.z-centre.z)) < hypot(Double($1.x-centre.x),Double($1.z-centre.z))
            }) else {
                if initial && !installing && entryReady {
                    if let feet = spawn(near:home) {install(at:feet)}
                    else {chart.error = "No safe place was found here; choose another biome"}
                }
                if generation == nil { chart.message = nil; chart.progress = nil }
                if generation == nil && !reading && pending == nil { activity(false) }
                return
            }
            let snapshot = data, operation = BlockOperation(), token = request, assets = assets, revision = geometryRevision
            chart.message = "Drawing your world"
            operation.addExecutionBlock { [weak self,weak operation] in
                guard let self, let operation, !operation.isCancelled else { return }
                let result = Result { () -> (SCNNode,[SCNMaterial]) in
                    let node = try snapshot.node(key,assets:assets,cancelled:{operation.isCancelled})
                    let light = try Light(data:snapshot,key:key,cancelled:{operation.isCancelled})
                    let bindings = try light.apply(to:node,material:{assets.lit($0)},cancelled:{operation.isCancelled})
                    return (node,bindings)
                }
                SCNTransaction.flush(); assets.releaseArchives()
                DispatchQueue.main.async {
                    guard !operation.isCancelled, !self.disposed, self.request == token, self.geometryRevision == revision else { return }
                    self.mesh = nil
                    switch result {
                    case .failure(let error): self.chart.error = error.localizedDescription; self.chart.message = nil; return
                    case .success(let (node,bindings)):
                            if self.retained(key) {
                            for material in bindings {self.litMaterials[ObjectIdentifier(material)] = material}
                            Light.illuminate(materials:bindings,daylight:self.data.dimension == 0 ? Daylight.light(at:self.elapsed) : 1,
                                nightVision:self.nightVision)
                            self.nodes.removeValue(forKey:key)?.removeFromParentNode()
                            self.nodes[key] = node; self.dirty.remove(key)
                            if !self.initial {
                                view.scene?.rootNode.addChildNode(node)
                                if let eye = view.pointOfView?.position { self.horizon = self.visibleDistance(at:eye); self.fog(at:eye) }
                            }
                            self.doorGroups[key] = Door.collect(node); self.doors = self.doorGroups.values.flatMap {$0}
                            if self.initial, self.entryReady, let feet = self.spawn(near:self.home) {self.install(at:feet)}
                        }
                    }
                    self.pump()
                }
            }
            mesh = operation; assets.queue.addOperation(operation)
        }

        func distant() {
            guard streaming, !initial, chart.error == nil, horizonMap.operation == nil, let centre = region, view?.scene != nil,
                  let page = horizonMap.dirty.min(by:{hypot(Double($0.x*16-centre.x),Double($0.z*16-centre.z))<hypot(Double($1.x*16-centre.x),Double($1.z*16-centre.z))}) else {return}
            horizonMap.dirty.remove(page); horizonMap.pending = page
            var local: [Chunk:Horizon.Tile] = [:]
            for x in (page.x*16-1)...(page.x*16+16) {for z in (page.z*16-1)...(page.z*16+16) {
                let key = Chunk(x:x,z:z)
                if let tile = horizonMap.tiles[key] {local[key] = tile}
            } }
            let tiles = local, operation = BlockOperation(), assets = assets, token = request, revision = horizonMap.revision, near = near
            operation.queuePriority = .low
            operation.addExecutionBlock { [weak self,weak operation] in
                guard let self, let operation, !operation.isCancelled else {return}
                let result = Result {try Horizon.node(page,tiles:tiles,centre:centre,near:near,assets:assets,cancelled:{operation.isCancelled})}
                SCNTransaction.flush(); assets.releaseArchives()
                DispatchQueue.main.async {
                    guard !operation.isCancelled, !self.disposed, self.request == token, self.horizonMap.revision == revision,
                          let scene = self.view?.scene else {return}
                    self.horizonMap.operation = nil; self.horizonMap.pending = nil
                    switch result {
                    case .success(let node):
                        self.horizonMap.pages.removeValue(forKey:page)?.removeFromParentNode()
                        if node.geometry?.sources(for:.vertex).first?.vectorCount ?? 0 > 0 || !node.childNodes.isEmpty {
                            self.horizonMap.pages[page] = node; scene.rootNode.addChildNode(node)
                        }
                    case .failure(let error): self.horizonMap.dirty.insert(page); self.chart.error = error.localizedDescription
                    }
                    if let eye = self.view?.pointOfView?.position {self.updateRegion(at:eye,force:true)}
                    self.distant()
                }
            }
            horizonMap.operation = operation; assets.queue.addOperation(operation)
        }

        private func install(at feet: SCNVector3) {
            guard !installing else { return }
            installing = true
            let area = data.biome(feet), dimension = data.dimension, assets = assets, token = request, records = plans
            assets.queue.addOperation { [weak self] in
                let result = Result { () -> SCNScene in
                    let scene = Landscape.stage()
                    scene.background.contents = Landscape.colour(area.sky); scene.fogColor = Landscape.colour(area.sky)
                    scene.rootNode.childNode(withName:"sunlight",recursively:false)?.light?.intensity = 850
                    scene.rootNode.childNode(withName:"skylight",recursively:false)?.light?.intensity = 400
                    if dimension == 0 {
                        try Landscape.clouds(scene,assets:assets,origin:feet)
                        if let clouds = scene.rootNode.childNode(withName:"drifting-cloud",recursively:false) {
                            let layer = SCNNode(); layer.name = "cloud-layer"; layer.position = .init(feet.x,0,feet.z)
                            clouds.removeFromParentNode(); layer.addChildNode(clouds); scene.rootNode.addChildNode(layer)
                        }
                        try Daylight.install(scene,area:area,assets:assets)
                        scene.rootNode.childNode(withName:"daylight",recursively:false)?.removeAllActions()
                    }
                    for record in records { scene.rootNode.addChildNode(try Trail(record).decoration(assets:assets)) }
                    SCNTransaction.flush(); return scene
                }
                assets.releaseArchives()
                DispatchQueue.main.async {
                    guard let self, !self.disposed, self.request == token else { return }
                    switch result {
                    case .success(let scene): self.attach(scene,at:feet,area:area)
                    case .failure: self.chart.error = "The sky couldn’t load; choose the destination to try again"
                    }
                }
            }
        }

        private func attach(_ scene: SCNScene, at feet: SCNVector3, area: Biome) {
            guard let view else { return }
            let camera = scene.rootNode.childNode(withName:"camera",recursively:false)!
            for node in nodes.values { node.removeFromParentNode(); scene.rootNode.addChildNode(node) }
            camera.position = .init(feet.x,feet.y+FlightView.eyeHeight,feet.z)
            camera.look(at:.init(feet.x+12,feet.y+1.62,feet.z-22))
            if let cover = portalCover {
                cover.removeFromParentNode(); camera.addChildNode(cover)
                cover.runAction(.sequence([.fadeOut(duration:transitions ? 0.7 : 0),.removeFromParentNode()]))
                portalCover = nil
            }
            if transitions, view.scene != nil {
                let colour = Landscape.colour(world == .nether ? 0x54217E : world == .end ? 0x121023 : 0x5B806A)
                view.present(scene,with:.fade(with:colour,duration:1.25),incomingPointOfView:camera,completionHandler:nil)
            } else { view.scene = scene; view.pointOfView = camera }
            view.install(camera,area:area)
            environmentFog = Landscape.colour(area.sky); horizon = visibleDistance(at:camera.position); fog(at:camera.position)
            view.sweep = { [weak self] start,end in
                guard let self else { return start }
                self.target = nil; self.speed = 0
                if self.pending != nil {self.interrupt()}
                let next = self.data.move(from:start,to:end)
                return self.nodes[WorldData.key(Int(floor(next.x)),Int(floor(next.z)))] == nil ? start : next
            }
            initial = false; chart.visible = true; home = camera.position
            doors = Door.collect(scene.rootNode)
            populate(at:camera.position)
            greet()
            onReady?()
            distant()
            if let continuation {self.continuation = nil; pending = continuation; begin(continuation.0)}
        }

        func populate(at point: SCNVector3) {
            guard population == nil else { return }
            let snapshot = data, assets = assets, token = request, operation = BlockOperation()
            populated = point
            operation.queuePriority = .high
            operation.addExecutionBlock { [weak self,weak operation] in
                guard let self, let operation, !operation.isCancelled else { return }
                let result = Result { try Crowd(data:snapshot,at:point,assets:assets) }
                SCNTransaction.flush(); assets.releaseArchives()
                DispatchQueue.main.async {
                    guard !operation.isCancelled, !self.disposed, self.request == token else { return }
                    self.population = nil
                    switch result {
                    case .success(let crowd):
                        self.crowd?.root.removeFromParentNode(); self.crowd = crowd; self.view?.scene?.rootNode.addChildNode(crowd.root)
                        for door in self.doors {for resident in crowd.residents where resident.species == .villager || resident.species == .trader {door.register(resident.actor)}}
                    case .failure: self.chart.error = "Some residents couldn’t load; the world is still available"
                    }
                }
            }
            population = operation; assets.queue.addOperation(operation)
        }

        func greet() {
            guard data.dimension == 2, !initial, !greeting, view?.scene != nil else {return}
            greeting = true
            let snapshot = data, installed = crystals, create = dragon == nil, assets = assets, token = request
            assets.queue.addOperation { [weak self] in
                let result = Result { () -> (SCNNode?,[(Cell,SCNNode)]) in
                    var crystals: [(Cell,SCNNode)] = []
                    for chunk in snapshot.chunks.values where abs(chunk.key.x)<6 && abs(chunk.key.z)<6 {
                        for section in chunk.sections.values where section.y>=4 {
                            guard let layer = section.layers.first, layer.blocks.contains(where:{$0.name == "bedrock"}) else {continue}
                            for x in 0..<16 {for z in 0..<16 {for y in 0..<16 where layer.block(x,y,z).name == "bedrock" {
                                let cell = Cell(x:chunk.key.x*16+x,y:section.y*16+y,z:chunk.key.z*16+z)
                                guard cell.y>72, !installed.contains(cell), snapshot.block(cell.x,cell.y-1,cell.z)?.name == "obsidian" else {continue}
                                let node = try assets.actor("ender_crystal"); node.position = .init(Double(cell.x)+0.5,Double(cell.y)+1,Double(cell.z)+0.5)
                                crystals.append((cell,node))
                            } } }
                        }
                    }
                    let dragon: SCNNode?
                    if create {
                        let actor = SCNNode(); actor.name = "sky-resident"; actor.addChildNode(try assets.actor("ender_dragon")); actor.position = .init(32,96,0)
                        dragon = actor
                    } else {dragon = nil}
                    return (dragon,crystals)
                }
                SCNTransaction.flush(); assets.releaseArchives()
                DispatchQueue.main.async {
                    guard let self, !self.disposed, self.request == token, let scene = self.view?.scene else {return}
                    self.greeting = false
                    switch result {
                    case .failure(let error): self.chart.error = error.localizedDescription
                    case .success(let (dragon,crystals)):
                        if let dragon {self.dragon = dragon; scene.rootNode.addChildNode(dragon)}
                        for (cell,node) in crystals {self.crystals.insert(cell); scene.rootNode.addChildNode(node)}
                        if let dragon = self.dragon, !crystals.isEmpty {
                            scene.rootNode.childNode(withName:"crystal-healing-beam",recursively:false)?.removeFromParentNode()
                            do {self.healing = try Landscape.heal(dragon,root:scene.rootNode,assets:assets)}
                            catch {self.chart.error = error.localizedDescription}
                        }
                    }
                }
            }
        }

        func advance(_ dt: Double) {
            guard !initial, let view, let camera = view.pointOfView, let world else { return }
            if view.exploring && !wasExploring {
                target = nil; speed = 0
                if pending != nil { interrupt() }
            }
            elapsed += dt
            if let dragon {
                let angle = elapsed/48*Double.pi*2, desired = SCNVector3(cos(angle)*34,94+sin(angle*2)*10,sin(angle)*34)
                let start = dragon.position, dx = desired.x-start.x, dy = desired.y-start.y, dz = desired.z-start.z
                let distance = hypot(hypot(dx,dz),dy), fraction = distance>0 ? min(1,dt*14/distance) : 0
                let next = SCNVector3(start.x+dx*fraction,start.y+dy*fraction,start.z+dz*fraction)
                dragon.position = next
                if hypot(next.x-start.x,next.z-start.z)>0.0001 {dragon.eulerAngles.y = atan2(next.x-start.x,next.z-start.z)}
                healing?(CGFloat(elapsed))
            }
            crowd?.advance(dt,data:data,observer:camera.position,visible:{self.nodes[$0] != nil})
            var eye = camera.position
            if wasExploring && !view.exploring {
                home = eye
                let forward = camera.convertVector(.init(0,0,-1),to:nil)
                idleAim = .init(forward.x*24,forward.y*24,forward.z*24)
            }
            wasExploring = view.exploring
            if !view.exploring {
                if !route.isEmpty, let pending {
                    if chart.error != nil || passage != nil {speed = 0}
                    else {
                    if waypoint>=route.count {
                        completeJourney(pending); return
                    }
                    let stop = route[waypoint], dx = stop.point.x-eye.x, dy = stop.point.y-eye.y, dz = stop.point.z-eye.z
                    guide?.isHidden = stop.title.contains("house chest")
                    if waypoint>=route.count-2 { veil?.opacity = min(0.8,(veil?.opacity ?? 0)+dt*0.35) }
                    let remaining = hypot(hypot(dx,dz),dy)
                    if remaining<0.08 { waypoint += 1; blocked = 0 }
                    else {
                        let nextKey = WorldData.key(Int(floor(eye.x+dx/remaining*4)),Int(floor(eye.z+dz/remaining*4)))
                        if nodes[nextKey] != nil {
                            let desired = waypoint<route.count-2 ? cruise : min(2,cruise)
                            speed += (desired-speed)*(1-exp(-dt*2))
                            let step = min(remaining,dt*speed)
                            let next = SCNVector3(eye.x+dx/remaining*step,eye.y+dy/remaining*step,eye.z+dz/remaining*step)
                            let moved = data.move(from:.init(eye.x,eye.y-1.62,eye.z),to:.init(next.x,next.y-1.62,next.z))
                            let progress = hypot(hypot(moved.x-eye.x,moved.z-eye.z),moved.y+1.62-eye.y)
                            blocked = progress<step*0.1 ? blocked+dt : 0
                            eye = .init(moved.x,moved.y+1.62,moved.z)
                            let aim = lookahead(from:eye)
                            FlightView.face(camera,toward:aim,seconds:dt)
                            guide?.position = aim
                            if blocked>2 {repairRoute(at:eye)}
                        } else { speed = 0 }
                    }
                    location(stop.title)
                    }
                } else if let target {
                    let dx = target.x-eye.x, dz = target.z-eye.z, remaining = hypot(dx,dz)
                    if remaining<3 {
                        if let feet = spawn(near:target) {
                            let destination = SCNVector3(feet.x,feet.y+1.62,feet.z), dx = feet.x-eye.x, dy = feet.y+1.62-eye.y, dz = feet.z-eye.z
                            let distance = hypot(hypot(dx,dz),dy), fraction = distance>0 ? min(1,dt*5/distance) : 1
                            let moved = data.move(from:.init(eye.x,eye.y-1.62,eye.z),to:.init(eye.x+dx*fraction,eye.y+dy*fraction-1.62,eye.z+dz*fraction))
                            eye = .init(moved.x,moved.y+1.62,moved.z)
                            if hypot(hypot(destination.x-eye.x,destination.z-eye.z),destination.y-eye.y)<0.3 {
                                home = eye; self.target = nil; speed = 0
                                let forward = camera.convertVector(.init(0,0,-1),to:nil); idleAim = .init(forward.x*24,forward.y*24,forward.z*24)
                            }
                        }
                    } else {
                        speed = min(min(56,max(6,remaining*0.7)),speed+dt*12)
                        let step = min(remaining,dt*speed)
                        var next = SCNVector3(eye.x+dx/remaining*step,eye.y,eye.z+dz/remaining*step)
                        if let ground = data.surface(Int(floor(next.x)),Int(floor(next.z)),below:data.dimension == 1 ? 118 : 320) {
                            let altitude = Double(ground)+FlightView.eyeHeight+min(14,remaining*0.15)
                            next.y += min(8*dt,max(-8*dt,altitude-next.y))
                            let feet = SCNVector3(eye.x,eye.y-1.62,eye.z), desired = SCNVector3(next.x,next.y-1.62,next.z)
                            let moved = data.move(from:feet,to:desired)
                            eye = .init(moved.x,moved.y+1.62,moved.z)
                            FlightView.face(camera,toward:.init(eye.x+dx/remaining*32,eye.y-2,eye.z+dz/remaining*32),seconds:dt)
                        } else { speed = 0 }
                    }
                } else {
                    let target = SCNVector3(home.x+sin(elapsed*0.12)*3,home.y+sin(elapsed*0.2)*0.3,home.z+cos(elapsed*0.12)*3)
                    let dx = target.x-eye.x, dy = target.y-eye.y, dz = target.z-eye.z, distance = hypot(hypot(dx,dz),dy)
                    let fraction = distance>0 ? min(1,dt*1.2/distance) : 1
                    let next = SCNVector3(eye.x+dx*fraction,eye.y+dy*fraction,eye.z+dz*fraction)
                    let feet = SCNVector3(eye.x,eye.y-1.62,eye.z), destination = SCNVector3(next.x,next.y-1.62,next.z)
                    let moved = data.move(from:feet,to:destination)
                    eye = .init(moved.x,moved.y+1.62,moved.z)
                    FlightView.face(camera,toward:.init(eye.x+idleAim.x,eye.y+idleAim.y,eye.z+idleAim.z),seconds:dt)
                }
                if nodes[WorldData.key(Int(floor(eye.x)),Int(floor(eye.z)))] != nil { camera.position = eye }
                else { eye = camera.position; speed = 0 }
            }
            updateRegion(at:eye)
            if hypot(hypot(eye.x-populated.x,eye.z-populated.z),eye.y-populated.y)>64 { populate(at:eye) }
            if elapsed-reported>=0.1 {
                reported = elapsed
                let x = Int(floor(eye.x)), z = Int(floor(eye.z)), key = WorldData.key(x,z)
                let id = data.chunks[key]?.biome(x-key.x*16,Int(floor(eye.y)),z-key.z*16)
                let title = Biome.identifiers[id ?? -1]?.replacingOccurrences(of:"_",with:" ").capitalized ?? world.title
                if route.isEmpty {
                    location(title)
                    if let id {
                        let identity = "\(data.dimension):\(id)"
                        if identity != lastBiome { lastBiome = identity; chart.arrival = title }
                    }
                }
                report?(eye,Double(camera.eulerAngles.y))
                if chart.owner == identity {
                    let diagnostics = view.diagnostics
                    chart.mobs = crowd?.residents.filter {!$0.actor.isHidden}.map {
                        MapMarker(x:$0.actor.position.x,z:$0.actor.position.z,kind:.mob)
                    } ?? []
                    chart.debug = DebugSnapshot(biome:title,loaded:data.chunks.count,rendered:nodes.count,distance:radius,
                        daylight:Int(round((data.dimension == 0 ? Daylight.light(at:elapsed) : 1)*15)),nightVision:nightVision,
                        fps:diagnostics.fps,scale:diagnostics.scale,device:diagnostics.device)
                }
                for door in doors { door.approach(eye) }
            }
            let daylight = data.dimension == 0 ? Daylight.light(at:elapsed) : 1
            let vision = view.exploring && Light.dark(data:data,at:eye,daylight:daylight)
            if Int(elapsed) != lighting || vision != nightVision {
                lighting = Int(elapsed)
                nightVision = vision
                Light.illuminate(materials:Array(litMaterials.values),daylight:daylight,nightVision:nightVision)
                horizon = visibleDistance(at:eye)
                if let scene = view.scene, data.dimension == 0 { Daylight.apply(scene,area:data.biome(eye),seconds:elapsed,eye:eye) }
                if let scene = view.scene {
                    scene.rootNode.childNode(withName:"cloud-layer",recursively:false)?.position = .init((eye.x/512).rounded()*512,0,(eye.z/512).rounded()*512)
                    let buried = data.dimension == 0 && (data.surface(Int(floor(eye.x)),Int(floor(eye.z))).map {Double($0)>eye.y+6} ?? false)
                    scene.rootNode.childNode(withName:"sunlight",recursively:false)?.isHidden = buried
                    if nightVision {
                        scene.rootNode.childNode(withName:"skylight",recursively:false)?.light?.intensity = 520
                    } else if buried {
                        scene.rootNode.childNode(withName:"skylight",recursively:false)?.light?.intensity = 90
                        scene.background.contents = Landscape.colour(0x0C1117); scene.fogColor = Landscape.colour(0x0C1117)
                    } else if data.dimension != 0 {scene.rootNode.childNode(withName:"skylight",recursively:false)?.light?.intensity = 400}
                    environmentFog = scene.fogColor as? NSColor ?? Landscape.colour(data.biome(eye).sky)
                }
            }
            fog(at:eye)
        }

        private func lookahead(from eye: SCNVector3) -> SCNVector3 {
            var start = eye, distance = 4.0
            for stop in route.dropFirst(waypoint) {
                let dx = stop.point.x-start.x, dy = stop.point.y-start.y, dz = stop.point.z-start.z
                let length = hypot(hypot(dx,dz),dy)
                if length>=distance {return .init(start.x+dx/length*distance,start.y+dy/length*distance,start.z+dz/length*distance)}
                distance -= length; start = stop.point
            }
            return start
        }

        private func repairRoute(at eye: SCNVector3) {
            guard passage == nil, waypoint<route.count else {return}
            guard reroutes<1 else {
                chart.error = "The route is blocked; try again or explore here"; activity(false); return
            }
            reroutes += 1; blocked = 0; speed = 0
            let operation = BlockOperation(), snapshot = data, token = request, stop = route[waypoint], index = waypoint
            operation.addExecutionBlock { [weak self,weak operation] in
                guard let operation, !operation.isCancelled else {return}
                let path = Trail.path(data:snapshot,from:eye,to:stop.point)
                DispatchQueue.main.async {
                    guard let self, !operation.isCancelled, !self.disposed, self.request == token, self.waypoint == index else {return}
                    self.passage = nil
                    if let path, !path.isEmpty {
                        self.route.replaceSubrange(index...index,with:path.map {Trail.Stop(point:$0,title:stop.title)})
                    } else {
                        self.chart.error = "The route is blocked; try again or explore here"; self.activity(false)
                    }
                }
            }
            passage = operation; assets.queue.addOperation(operation)
        }

        private func fog(at eye: SCNVector3) {
            guard let scene = view?.scene else { return }
            let x = Int(floor(eye.x)), y = Int(floor(eye.y)), z = Int(floor(eye.z))
            let primary = data.block(x,y,z), medium = primary?.fluid == true ? primary : data.block(x,y,z,layer:1)
            let fluid = medium?.liquid
            let water = assets.waterFog(data.nativeBiome(eye))
            scene.fogStartDistance = fluid == "lava" ? 0 : fluid == "water" ? 2 : horizon
            scene.fogEndDistance = fluid == "lava" ? 3 : fluid == "water" ? water?.distance ?? 35 : horizon+32
            scene.fogColor = fluid == "lava" ? Landscape.colour(0xC84009) : fluid == "water" ? Landscape.colour(water?.colour ?? 0x245A92) : environmentFog
            view?.pointOfView?.camera?.zFar = Double(radius*16+32)
        }

        func skip() {
            guard let pending else {return}
            completeJourney(pending)
        }

        private func completeJourney(_ destination: (World,Int)) {
            portalCover = veil?.clone()
            portalCover?.opacity = 0.85
            if let cover = portalCover {view?.pointOfView?.addChildNode(cover)}
            reset(world:destination.0,seed:seed,biome:destination.1)
            arrived(destination.0)
        }

        func interrupt() {
            passage?.cancel(); passage = nil; route = []; pending = nil; target = nil; speed = 0; blocked = 0; reroutes = 0
            planning = nil; prefetch = []
            guide?.removeFromParentNode(); guide = nil; veil?.removeFromParentNode(); veil = nil
            portalCover?.removeFromParentNode(); portalCover = nil
            chart.message = nil
            if let world {arrived(world)}
            activity(false)
        }

        func dispose() {
            disposed = true; request += 1
            planning = nil; prefetch = []
            reader?.cancel(); reader = nil
            horizonMap.clear()
            generation?.cancel(); mesh?.cancel(); population?.cancel(); passage?.cancel(); generation = nil; mesh = nil; population = nil; passage = nil; crowd = nil; guide = nil; doors = []
            view?.scene = nil; view?.pointOfView = nil; view?.dispose(); nodes = [:]; data = WorldData(dimension:0); report = nil; onReady = nil; litMaterials = [:]; veil = nil; doorGroups = [:]; continuation = nil
            if chart.owner == identity {
                chart.retry = nil; chart.skip = nil; chart.visible = false; chart.mobs = []; chart.debug = DebugSnapshot(); chart.install(data)
            }
            dragon = nil; healing = nil; crystals = []
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(chart:chart,assets:assets,root:root) }
    func makeNSView(context: Context) -> FlightView {
        let view = FlightView(frame:.zero); view.backgroundColor = .clear
        view.preferredFramesPerSecond = 30; view.antialiasingMode = .none
        context.coordinator.view = view
        view.step = { [weak coordinator = context.coordinator] dt in coordinator?.advance(dt) }
        return view
    }

    func updateNSView(_ view: FlightView, context: Context) {
        let coordinator = context.coordinator
        view.materials = moving ? { [weak assets] time in if let assets {assets.animate(at:time-assets.started)} } : nil
        coordinator.location = location; coordinator.report = exploring ? report : nil
        coordinator.activity = activity; coordinator.transitions = moving
        coordinator.arrived = arrived
        chart.retry = { [weak coordinator] in
            guard let coordinator else {return}
            coordinator.chart.error = nil; coordinator.chart.message = nil; coordinator.repairs = [:]
            if let pending = coordinator.pending {coordinator.begin(pending.0)}
            else {
                coordinator.region = nil; coordinator.visit()
                if !coordinator.initial {coordinator.updateRegion(at:coordinator.view?.pointOfView?.position ?? coordinator.home)}
                coordinator.pump()
            }
        }
        chart.skip = { [weak coordinator] in coordinator?.skip() }
        coordinator.radius = min(512,max(8,distance))
        coordinator.streaming = active
        view.controls = controls; view.sensitivity = Float(min(100,max(1,sensitivity)))*0.003; view.inverted = inverted
        view.resolution = resolution
        view.metrics = root.appendingPathComponent("logs/scenery/frames.json")
        view.finish = finish; view.exploring = exploring
        let animated = moving || active && exploring
        view.preferredFramesPerSecond = exploring || coordinator.pending != nil ? (ProcessInfo.processInfo.isLowPowerModeEnabled ? 30 : 60) : 30
        coordinator.onReady = { [weak view] in view?.clock(animated) }
        coordinator.configure(world:world,seed:seed,biome:biome,cinematic:cinematic)
        view.clock(animated)
        view.scene?.isPaused = !moving
    }

    static func dismantleNSView(_ view: FlightView, coordinator: Coordinator) { coordinator.dispose() }
}
