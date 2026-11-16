import AppKit
import SceneKit
import SpriteKit
import SwiftUI

@MainActor
final class Chart: ObservableObject {
    var data = WorldData(dimension:0)
    @Published var revision = 0
    @Published var message: String?
    @Published var error: String?
    @Published var progress: Double?
    var retry: (() -> Void)?
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

    @MainActor final class Coordinator {
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
        var radius = 8
        var database: URL?
        var destinations: [[String:Any]] = []
        var target: SCNVector3?
        var landing: SCNVector3?
        var speed = 0.0
        var request = 0
        var elapsed = 0.0
        var reported = 0.0
        var lighting = -1
        var home = SCNVector3Zero
        var initial = true
        var disposed = false
        var location: (String?) -> Void = { _ in }
        var report: ((SCNVector3,Double) -> Void)?
        var onReady: (() -> Void)?
        var crowd: Crowd?
        var population: Operation?
        var populated = SCNVector3Zero
        var reading = false
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
        var geometryRevision = 0
        var doors: [Door] = []
        var guide: SCNNode?
        var revisit = false
        var prefetch = Set<Chunk>()
        var veil: SCNNode?
        var lamps: [SCNNode] = []
        var torches: [SCNVector3] = []
        var environmentFog: NSColor = .black
        var doorGroups: [Chunk:[Door]] = [:]
        var continuation: (World,Int)?
        let identity = UUID()
        var dragon: SCNNode?
        var healing: (@Sendable (CGFloat) -> Void)?
        var crystals = Set<Cell>()
        var greeting = false
        var wasExploring = false
        var idleAim = SCNVector3(12,1,-22)

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
            if pending != nil { passage?.cancel(); passage = nil; pending = nil; route = []; guide?.removeFromParentNode(); guide = nil; veil?.removeFromParentNode(); veil = nil; activity(false) }
            guard self.world != world || self.seed != seed else {
                if self.biome != biome { self.biome = biome; visit() }
                return
            }
            reset(world:world,seed:seed,biome:biome)
        }

        private func reset(world: World, seed: String, biome: Int) {
            request += 1; generation?.cancel(); generation = nil; mesh?.cancel(); mesh = nil
            continuation = nil; doorGroups = [:]
            dragon = nil; healing = nil; crystals = []; greeting = false
            wasExploring = false; idleAim = .init(12,1,-22)
            passage?.cancel(); passage = nil; pending = nil; route = []; guide = nil; veil = nil; lamps = []; torches = []; doors = []; plans = []; restored = false; prefetch = []; revisit = false
            population?.cancel(); population = nil; crowd = nil
            self.world = world; self.seed = seed; self.biome = biome
            data = WorldData(dimension:world.dimension!); nodes = [:]; wanted = []; region = nil
            database = nil; destinations = []; initial = true; installing = false; target = nil; landing = nil; speed = 0; reading = false
            chart.error = nil; chart.install(data)
            visit()
        }

        func begin(_ destination: World) {
            guard passage == nil, let eye = view?.pointOfView?.position, let database else { return }
            target = nil; speed = 0; activity(true); chart.error = nil; chart.message = "Finding a path beneath your world"
            let snapshot = data, seed = seed, token = request, saved = plans
            let operation = BlockOperation(), file = database.deletingLastPathComponent().appendingPathComponent("journeys-\(data.dimension).json")
            operation.addExecutionBlock { [weak self,weak operation] in
                guard let self, let operation, !operation.isCancelled else { return }
                let result = Result { () -> (Trail,[Trail.Stop],SCNNode?,SCNNode,SCNNode) in
                    let kind = destination == .nether ? "nether" : "end"
                    guard let record = saved.first(where:{$0.kind == kind}) ?? Trail.anchor(data:snapshot,eye:eye,destination:destination,seed:seed) else { throw ChunkError.database("Explore a little farther before entering this portal") }
                    let trail = Trail(record)
                    var approach = trail.approach(data:snapshot,eye:eye,chest:destination == .end)
                    approach += trail.route
                    var plans = saved.filter { $0.kind != kind }; plans.append(record)
                    if (try? file.resourceValues(forKeys:[.isSymbolicLinkKey]).isSymbolicLink) == true { throw ChunkError.format }
                    try JSONEncoder().encode(plans).write(to:file,options:[.atomic,.completeFileProtectionUnlessOpen])
                    let guide: SCNNode?
                    if destination == .end {
                        let plane = SCNPlane(width:0.28,height:0.28); plane.firstMaterial = try self.assets.texture("textures/items/ender_eye")
                        guide = SCNNode(geometry:plane); guide?.constraints = [SCNBillboardConstraint()]; guide?.name = "eye-of-ender"
                    } else { guide = nil }
                    let material = try self.assets.texture("textures/blocks/portal",animated:true).copy() as! SCNMaterial
                    material.lightingModel = .constant; material.readsFromDepthBuffer = false; material.writesToDepthBuffer = false
                    let plane = SCNPlane(width:6,height:4); plane.firstMaterial = material
                    let veil = SCNNode(geometry:plane); veil.name = "portal-distortion"; veil.position.z = -0.3; veil.opacity = 0; veil.renderingOrder = 1000
                    Landscape.animate(veil,material:material)
                    return (trail,approach,guide,try trail.decoration(assets:self.assets),veil)
                }
                DispatchQueue.main.async {
                    guard !operation.isCancelled, self.request == token, !self.disposed else { return }
                    self.passage = nil
                    switch result {
                    case .failure(let error): self.chart.error = error.localizedDescription; self.chart.message = nil
                    case .success(let (trail,route,guide,decoration,veil)):
                        self.plans.removeAll { $0.kind == trail.record.kind }; self.plans.append(trail.record)
                        self.data.apply(trail.blocks); self.chart.install(self.data)
                        self.geometryRevision += 1; self.mesh?.cancel(); self.mesh = nil
                        let changed = Set(trail.blocks.keys.map { WorldData.key($0.x,$0.z) })
                        self.prefetch = changed
                        for key in Array(self.nodes.keys) where changed.contains(key) { self.nodes.removeValue(forKey:key)?.removeFromParentNode() }
                        self.route = route; self.waypoint = 0; self.guide = guide
                        self.veil = veil; self.view?.pointOfView?.addChildNode(veil)
                        self.view?.scene?.rootNode.childNode(withName:decoration.name!,recursively:false)?.removeFromParentNode()
                        self.view?.scene?.rootNode.addChildNode(decoration)
                        self.torches = self.data.edits.values.flatMap {$0.filter {$0.value.model.contains("torch")}.keys.map {SCNVector3(Double($0.x)+0.5,Double($0.y)+0.5,Double($0.z)+0.5)}}
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

        func updateRegion(at point: SCNVector3) {
            let next = WorldData.key(Int(floor(point.x)),Int(floor(point.z)))
            guard next != region || wanted.count != (radius*2+1)*(radius*2+1) else { return }
            region = next
            wanted = Set((-radius...radius).flatMap { dx in (-radius...radius).map { Chunk(x:next.x+dx,z:next.z+$0) } })
            for key in Array(nodes.keys) where !wanted.contains(key) { nodes.removeValue(forKey:key)?.removeFromParentNode(); doorGroups.removeValue(forKey:key) }
            doors = doorGroups.values.flatMap {$0}
            data.chunks = data.chunks.filter { wanted.contains($0.key) }
            let missing = wanted.filter { data.chunks[$0] == nil }
            if !missing.isEmpty {
                let ordered = missing.sorted { hypot(Double($0.x-next.x),Double($0.z-next.z))<hypot(Double($1.x-next.x),Double($1.z-next.z)) }
                generate(initial ? Array(ordered.prefix(9)) : ordered)
            }
            pump()
        }

        static func batch(_ chunks: Set<Chunk>, near centre: Chunk) -> [Chunk] {
            Array(chunks.sorted {
                let a = hypot(Double($0.x)-Double(centre.x),Double($0.z)-Double(centre.z))
                let b = hypot(Double($1.x)-Double(centre.x),Double($1.z)-Double(centre.z))
                return a == b ? ($0.x == $1.x ? $0.z<$1.z : $0.x<$1.x) : a<b
            }.prefix(1089))
        }

        func generate(_ chunks: [Chunk], locators: [[String:String]] = []) {
            guard generation == nil, !reading, !disposed, !chunks.isEmpty || !locators.isEmpty else { return }
            prefetch.formUnion(chunks)
            let chunks = Self.batch(Set(chunks),near:region ?? .init(x:0,z:0))
            let token = request
            var ready: [String:Any]?
            chart.message = locators.isEmpty ? "Preparing the next chunks" : "Finding your destination"
            chart.progress = nil
            let operation = Generation(root:root,request:["seed":seed,"dimension":data.dimension,
                "chunks":chunks.map { [$0.x,$0.z] },"locate":locators],receive:{ [weak self] value in
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
            reading = true
            let operation = BlockOperation(), dimension = data.dimension, restore = !restored
            operation.addExecutionBlock { [weak self,weak operation] in
                guard let self, let operation, !operation.isCancelled else { return }
                let result = Result { () -> ([Chunk:VoxelChunk],[[String:Any]],[Trail]) in
                    let database = try Database(database)
                    var loaded: [Chunk:VoxelChunk] = [:]
                    for key in chunks {
                        guard !operation.isCancelled else { throw CancellationError() }
                        guard let value = try database.chunk(key,dimension:dimension) else { throw ChunkError.missing }
                        loaded[key] = value
                    }
                    let metadata = try Data(contentsOf:manifest)
                    guard metadata.count<=4*1024*1024, let value = try JSONSerialization.jsonObject(with:metadata) as? [String:Any] else { throw ChunkError.format }
                    var trails: [Trail] = []
                    let file = manifest.deletingLastPathComponent().appendingPathComponent("journeys-\(dimension).json")
                    if restore, FileManager.default.fileExists(atPath:file.path) {
                        let bytes = try Data(contentsOf:file)
                        guard bytes.count<=64*1024 else { throw ChunkError.format }
                        let records = try JSONDecoder().decode([Trail.Record].self,from:bytes)
                        guard records.count<=2, records.allSatisfy(\.valid) else { throw ChunkError.format }
                        trails = records.map(Trail.init)
                    }
                    return (loaded,(value["destinations"] as? [[String:Any]] ?? []).filter { $0["dimension"] as? Int == dimension },trails)
                }
                DispatchQueue.main.async {
                    guard !operation.isCancelled, !self.disposed, self.request == token else { return }
                    self.reading = false
                    switch result {
                    case .failure(let error): self.chart.error = error.localizedDescription; self.chart.message = nil
                    case .success(let (loaded,destinations,trails)):
                        self.data.chunks.merge(loaded) { _,new in new }; self.destinations = destinations
                        self.prefetch.subtract(loaded.keys)
                        if restore {
                            self.restored = true; self.plans = trails.map(\.record)
                            for trail in trails { self.data.apply(trail.blocks) }
                        }
                        self.chart.install(self.data)
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
                            let missing = self.wanted.union(self.prefetch).filter { self.data.chunks[$0] == nil }
                            if !missing.isEmpty { self.generate(Array(missing)) }
                            self.pump()
                        }
                    }
                }
            }
            Generation.queue.addOperation(operation)
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
            guard mesh == nil, !disposed, let view else { return }
            let centre = region ?? .init(x:0,z:0)
            guard let key = wanted.filter({ nodes[$0] == nil && data.chunks[$0] != nil }).min(by:{
                hypot(Double($0.x-centre.x),Double($0.z-centre.z)) < hypot(Double($1.x-centre.x),Double($1.z-centre.z))
            }) else {
                if generation == nil { chart.message = nil; chart.progress = nil }
                if generation == nil && !reading && pending == nil { activity(false) }
                return
            }
            let snapshot = data, operation = BlockOperation(), token = request, assets = assets, revision = geometryRevision
            chart.message = "Drawing your world"
            operation.addExecutionBlock { [weak self,weak operation] in
                guard let self, let operation, !operation.isCancelled else { return }
                let result = Result { try snapshot.node(key,assets:assets) }
                SCNTransaction.flush(); assets.releaseArchives()
                DispatchQueue.main.async {
                    guard !operation.isCancelled, !self.disposed, self.request == token, self.geometryRevision == revision else { return }
                    self.mesh = nil
                    switch result {
                    case .failure(let error): self.chart.error = error.localizedDescription; self.chart.message = nil; return
                    case .success(let node):
                        if self.wanted.contains(key) {
                            self.nodes[key] = node
                            if !self.initial { view.scene?.rootNode.addChildNode(node) }
                            self.doorGroups[key] = Door.collect(node); self.doors = self.doorGroups.values.flatMap {$0}
                            if self.initial, self.nodes.count>=min(9,self.wanted.count), let feet = self.spawn(near:self.home) { self.install(at:feet) }
                        }
                    }
                    self.pump()
                }
            }
            mesh = operation; assets.queue.addOperation(operation)
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
            if transitions, view.scene != nil {
                let colour = Landscape.colour(world == .nether ? 0x54217E : world == .end ? 0x121023 : 0x5B806A)
                view.present(scene,with:.fade(with:colour,duration:1.25),incomingPointOfView:camera,completionHandler:nil)
            } else { view.scene = scene; view.pointOfView = camera }
            view.install(camera,area:area)
            view.sweep = { [weak self] start,end in
                guard let self else { return start }
                self.target = nil; self.speed = 0
                if self.pending != nil {self.interrupt()}
                return self.data.move(from:start,to:end)
            }
            initial = false; home = camera.position
            doors = Door.collect(scene.rootNode)
            torches = data.edits.values.flatMap {$0.filter {$0.value.model.contains("torch")}.keys.map {SCNVector3(Double($0.x)+0.5,Double($0.y)+0.5,Double($0.z)+0.5)}}
            lamps = (0..<6).map { _ in
                let node = SCNNode(); node.light = SCNLight(); node.light?.type = .omni; node.light?.color = Landscape.colour(0xFFC27D)
                node.light?.intensity = 220; node.light?.attenuationEndDistance = 16; node.light?.castsShadow = false
                scene.rootNode.addChildNode(node); return node
            }
            populate(at:camera.position)
            greet()
            onReady?()
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
                let start = dragon.position, next = data.move(from:start,to:desired,radius:3.5,height:3)
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
                    if waypoint>=route.count {
                        let destination = pending
                        reset(world:destination.0,seed:seed,biome:destination.1); arrived(destination.0); return
                    }
                    let stop = route[waypoint], dx = stop.point.x-eye.x, dy = stop.point.y-eye.y, dz = stop.point.z-eye.z
                    if waypoint>=route.count-2 { veil?.opacity = min(0.8,(veil?.opacity ?? 0)+dt*0.35) }
                    let remaining = hypot(hypot(dx,dz),dy)
                    if remaining<0.35 { waypoint += 1 }
                    else {
                        let nextKey = WorldData.key(Int(floor(eye.x+dx/remaining*4)),Int(floor(eye.z+dz/remaining*4)))
                        if nodes[nextKey] != nil {
                            speed = min(waypoint<route.count-2 ? 10 : 3,speed+dt*5)
                            let step = min(remaining,dt*speed)
                            let next = SCNVector3(eye.x+dx/remaining*step,eye.y+dy/remaining*step,eye.z+dz/remaining*step)
                            let moved = data.move(from:.init(eye.x,eye.y-1.62,eye.z),to:.init(next.x,next.y-1.62,next.z))
                            eye = .init(moved.x,moved.y+1.62,moved.z)
                            let aim = SCNVector3(eye.x+dx/remaining*5,eye.y+dy/remaining*5,eye.z+dz/remaining*5)
                            let rotation = camera.eulerAngles
                            camera.look(at:aim,up:.init(0,1,0),localFront:.init(0,0,-1))
                            let heading = camera.eulerAngles, blend = 1-exp(-dt*5)
                            camera.eulerAngles = .init(rotation.x+(heading.x-rotation.x)*blend,rotation.y+atan2(sin(heading.y-rotation.y),cos(heading.y-rotation.y))*blend,0)
                            guide?.position = aim
                        } else { speed = 0 }
                    }
                    location(stop.title)
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
                            camera.look(at:.init(eye.x+dx/remaining*32,eye.y-2,eye.z+dz/remaining*32))
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
                    camera.look(at:.init(eye.x+idleAim.x,eye.y+idleAim.y,eye.z+idleAim.z))
                }
                camera.position = eye
            }
            updateRegion(at:eye)
            if hypot(hypot(eye.x-populated.x,eye.z-populated.z),eye.y-populated.y)>64 { populate(at:eye) }
            if elapsed-reported>=0.1 {
                reported = elapsed
                let x = Int(floor(eye.x)), z = Int(floor(eye.z)), key = WorldData.key(x,z)
                let id = data.chunks[key]?.biome(x-key.x*16,Int(floor(eye.y)),z-key.z*16)
                if route.isEmpty { location(Biome.identifiers[id ?? -1]?.replacingOccurrences(of:"_",with:" ").capitalized ?? world.title) }
                report?(eye,Double(camera.eulerAngles.y))
                for door in doors { door.approach(eye) }
            }
            if Int(elapsed) != lighting {
                lighting = Int(elapsed)
                if let scene = view.scene, data.dimension == 0 { Daylight.apply(scene,area:data.biome(eye),seconds:elapsed,eye:eye) }
                if let scene = view.scene {
                    scene.rootNode.childNode(withName:"cloud-layer",recursively:false)?.position = .init((eye.x/512).rounded()*512,0,(eye.z/512).rounded()*512)
                    let buried = data.dimension == 0 && (data.surface(Int(floor(eye.x)),Int(floor(eye.z))).map {Double($0)>eye.y+6} ?? false)
                    scene.rootNode.childNode(withName:"sunlight",recursively:false)?.isHidden = buried
                    if buried {
                        scene.rootNode.childNode(withName:"skylight",recursively:false)?.light?.intensity = 90
                        scene.background.contents = Landscape.colour(0x0C1117); scene.fogColor = Landscape.colour(0x0C1117)
                    }
                    environmentFog = scene.fogColor as? NSColor ?? Landscape.colour(data.biome(eye).sky)
                    let near = torches.sorted {hypot(hypot($0.x-eye.x,$0.z-eye.z),$0.y-eye.y)<hypot(hypot($1.x-eye.x,$1.z-eye.z),$1.y-eye.y)}
                    for (index,lamp) in lamps.enumerated() {
                        guard index<near.count else {lamp.isHidden = true; continue}
                        let point = near[index]
                        lamp.isHidden = hypot(hypot(point.x-eye.x,point.z-eye.z),point.y-eye.y)>20
                        lamp.position = point
                    }
                }
            }
            if let scene = view.scene {
                let x = Int(floor(eye.x)), y = Int(floor(eye.y)), z = Int(floor(eye.z))
                let primary = data.block(x,y,z), medium = primary?.fluid == true ? primary : data.block(x,y,z,layer:1)
                let fluid = medium?.name.replacingOccurrences(of:"flowing_",with:"")
                scene.fogStartDistance = fluid == "lava" ? 0 : fluid == "water" ? 2 : Double(radius*16)*0.55
                scene.fogEndDistance = fluid == "lava" ? 3 : fluid == "water" ? 35 : Double(radius*16)-8
                if fluid == "lava" { scene.fogColor = Landscape.colour(0xC84009) }
                else if fluid == "water" { scene.fogColor = Landscape.colour(0x245A92) }
                else {scene.fogColor = environmentFog}
                camera.camera?.zFar = Double(radius*16+32)
            }
        }

        func interrupt() {
            passage?.cancel(); passage = nil; route = []; pending = nil; target = nil; speed = 0
            guide?.removeFromParentNode(); guide = nil; veil?.removeFromParentNode(); veil = nil
            chart.message = nil
            if let world {arrived(world)}
            activity(false)
        }

        func dispose() {
            disposed = true; request += 1
            generation?.cancel(); mesh?.cancel(); population?.cancel(); passage?.cancel(); generation = nil; mesh = nil; population = nil; passage = nil; crowd = nil; guide = nil; doors = []
            view?.scene = nil; view?.pointOfView = nil; view?.dispose(); nodes = [:]; data = WorldData(dimension:0); report = nil; onReady = nil; lamps = []; torches = []; veil = nil; doorGroups = [:]; continuation = nil
            if chart.owner == identity {chart.retry = nil; chart.install(data)}
            dragon = nil; healing = nil; crystals = []
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(chart:chart,assets:assets,root:root) }
    func makeNSView(context: Context) -> FlightView {
        let view = FlightView(frame:.zero); view.backgroundColor = .clear
        view.preferredFramesPerSecond = 60; view.antialiasingMode = .multisampling4X
        context.coordinator.view = view
        view.step = { [weak coordinator = context.coordinator] dt in coordinator?.advance(dt) }
        return view
    }

    func updateNSView(_ view: FlightView, context: Context) {
        let coordinator = context.coordinator
        coordinator.location = location; coordinator.report = exploring ? report : nil
        coordinator.activity = activity; coordinator.transitions = moving
        coordinator.arrived = arrived
        chart.retry = { [weak coordinator] in
            guard let coordinator else {return}
            coordinator.chart.error = nil; coordinator.chart.message = nil
            if let pending = coordinator.pending {coordinator.begin(pending.0)}
            else {
                coordinator.region = nil; coordinator.visit()
                if !coordinator.initial {coordinator.updateRegion(at:coordinator.view?.pointOfView?.position ?? coordinator.home)}
                coordinator.pump()
            }
        }
        coordinator.radius = min(16,max(4,distance))
        view.controls = controls; view.sensitivity = Float(min(100,max(1,sensitivity)))*0.003; view.inverted = inverted
        view.finish = finish; view.exploring = exploring
        let animated = moving || active && exploring
        coordinator.onReady = { [weak view] in view?.clock(animated) }
        coordinator.configure(world:world,seed:seed,biome:biome,cinematic:cinematic)
        view.clock(animated)
        view.scene?.isPaused = !moving; view.isPlaying = animated; view.rendersContinuously = animated
    }

    static func dismantleNSView(_ view: FlightView, coordinator: Coordinator) { coordinator.dispose() }
}
