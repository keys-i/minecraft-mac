import Foundation
import SceneKit

enum RenderChecks {
    static func run(assets: Assets) throws {
        let panorama = try assets.panorama()
        precondition(panorama != nil && panorama!.size.width>0,"The installed title panorama supplies an authentic loading frame")
        precondition(Block(name:"flowing_water").model == "water" && Block(name:"flowing_lava").model == "lava")
        precondition(Block(name:"scaffolding").render == .cutout && !Block(name:"scaffolding").opaque)
        precondition(Block(name:"mangrove_roots").render == .cutout && !Block(name:"mangrove_roots").opaque)
        precondition(Block(name:"honeycomb_block").opaque && Block(name:"honey_block").render == .blend)

        func values(_ geometry: SCNGeometry, _ semantic: SCNGeometrySource.Semantic) -> [[Double]] {
            let source = geometry.sources(for:semantic)[0]
            precondition(source.usesFloatComponents && [4,8].contains(source.bytesPerComponent))
            return source.data.withUnsafeBytes { bytes in
                (0..<source.vectorCount).map { index in
                    (0..<source.componentsPerVector).map { axis in
                        let offset = source.dataOffset+index*source.dataStride+axis*source.bytesPerComponent
                        return source.bytesPerComponent == 4 ? Double(bytes.loadUnaligned(fromByteOffset:offset,as:Float.self))
                            : bytes.loadUnaligned(fromByteOffset:offset,as:Double.self)
                    }
                }
            }
        }
        func indices(_ element: SCNGeometryElement) -> [Int] {
            precondition(element.primitiveType == .triangles && element.bytesPerIndex == 4)
            return element.data.withUnsafeBytes { bytes in
                (0..<(element.primitiveCount*3)).map { index in
                    Int(bytes.loadUnaligned(fromByteOffset:index*4,as:UInt32.self))
                }
            }
        }
        func compact(_ geometry: SCNGeometry) {
            let count = geometry.sources(for:.vertex)[0].vectorCount
            precondition(count>0 && geometry.sources.allSatisfy {$0.vectorCount == count})
            let referenced = Set(geometry.elements.flatMap {indices($0)})
            precondition(referenced == Set(0..<count),"Every retained vertex must belong to the partition's elements")
        }
        func storage(_ name: String) -> Data {
            var result = Data([0,1,0,0,0,10,0,0,8,4,0])
            result.append(contentsOf:"name".utf8)
            let value = Array(("minecraft:"+name).utf8)
            result.append(contentsOf:[UInt8(value.count),0]); result.append(contentsOf:value)
            result.append(contentsOf:[10,6,0]); result.append(contentsOf:"states".utf8); result.append(contentsOf:[0,0])
            return result
        }
        let wet = try Subchunk(Data([9,2,0])+storage("seagrass")+storage("water"))
        let chunk = try VoxelChunk(key:.init(x:0,z:0),dimension:0,sections:[0:wet],biomeData:nil)
        precondition(chunk.surfaces[0] == 15,"Secondary water contributes to the rendered surface")
        var world = WorldData(dimension:0); world.chunks[chunk.key] = chunk
        precondition(world.medium(at:.init(0.5,0.5,0.5)) == "water")
        world.apply([Cell(x:0,y:0,z:0):Block(name:"air")])
        precondition(world.medium(at:.init(0.5,0.5,0.5)) == nil,"A complete-cell edit clears inherited secondary water")
        precondition(Horizon.Tile(chunk,near:chunk.key).columns[0].contains {$0.block.fluid})
        let snowy = try Subchunk(Data([9,2,0])+storage("snow_layer")+storage("short_grass"))
        var snow = WorldData(dimension:0)
        snow.chunks[chunk.key] = try VoxelChunk(key:chunk.key,dimension:0,sections:[0:snowy],biomeData:nil)
        let snowNode = try snow.node(chunk.key,assets:assets)
        let vegetation = snowNode.childNode(withName:"chunk-overlays",recursively:false)!
        precondition(SCNVector3EqualToVector3(vegetation.position,SCNVector3Zero) && vegetation.geometry != nil,"Snow-covered vegetation retains its native cell alignment")
        precondition(vegetation.geometry!.materials.allSatisfy {$0.isDoubleSided && $0.writesToDepthBuffer})
        snow.apply([Cell(x:0,y:0,z:0):Block(name:"air")])
        precondition(snow.block(0,0,0,layer:1) == nil,"Complete-cell edits clear secondary vegetation as well as water")
        for height in 0...7 {
            let states = ["height":String(height)], top = Double(height+1)/8
            let snow = try Structures.volume("snow",size:[1,1,1],palette:[["Name":"minecraft:snow_layer","Properties":states]],blocks:[0:0],assets:assets)
            let points = values(snow.geometry!,.vertex)
            precondition(abs(points.map {$0[1]}.max()!-top)<0.00001,"Every snow thickness renders at its native height")
            var terrain = WorldData(dimension:0)
            terrain.chunks[chunk.key] = try VoxelChunk(key:chunk.key,dimension:0,sections:[:],biomeData:nil)
            terrain.apply([Cell(x:0,y:0,z:0):Block(name:"snow_layer",states:states)])
            precondition(terrain.vacant(.init(0.5,top,0.5)) && !terrain.vacant(.init(0.5,top-0.01,0.5)),"Snow collision must agree with the rendered surface")
            precondition(abs(terrain.standing(at:.init(0.5,top+0.2,0.5),radius:0.3,height:1.8)!.y-top)<0.00001,"Residents stand on the snow rather than floating above it")
        }
        for name in ["fern","bush","firefly_bush","poppy","dandelion"] {
            precondition(Block(name:name).passable)
            _ = try assets.tiles(Block(name:name).model)
        }
        for name in ["red_shrub","sweet_berry_bush"] {
            precondition(Block(name:name).passable && Block(name:name).render == .cutout,"Shrubs must use passable cutout geometry: \(name)")
        }
        let shrub = try Structures.volume("red-shrub",size:[1,1,1],palette:[["Name":"minecraft:red_shrub"]],blocks:[0:0],assets:assets)
        precondition(shrub.geometry?.sources(for:.vertex).first?.vectorCount == 8,"A shrub must render as crossed leaves rather than a solid cube")
        for growth in 0...7 {
            let berry = try Structures.volume("sweet-berry",size:[1,1,1],palette:[["Name":"minecraft:sweet_berry_bush","Properties":["growth":String(growth)]]],blocks:[0:0],assets:assets)
            precondition(berry.geometry?.sources(for:.vertex).first?.vectorCount == 8,"Every berry stage must use crossed cutout geometry")
            let stage = min(3,growth/2)
            precondition(berry.geometry?.materials.allSatisfy {$0.name == "textures/blocks/sweet_berry_bush_stage\(stage)"} == true,"Every berry stage must use one matching texture")
        }

        let palette: [[String:Any]] = [["Name":"minecraft:seagrass"],["Name":"minecraft:water"],["Name":"minecraft:flowing_water"]]
        let plant = try Structures.volume("wet-plant",size:[1,1,1],palette:palette,blocks:[0:0],fluids:[0:1],assets:assets)
        precondition(plant.geometry?.sources(for:.vertex).first?.vectorCount == 8)
        let water = plant.childNode(withName:"template-fluids",recursively:false)!
        precondition(water.categoryBitMask == 1 && water.geometry!.sources(for:.vertex)[0].vectorCount == 24)
        precondition(water.geometry!.materials.allSatisfy {!$0.writesToDepthBuffer && $0.readsFromDepthBuffer})
        let connected = try Structures.volume("connected-water",size:[2,1,1],palette:palette,blocks:[:],fluids:[0:1,1:2],assets:assets)
        precondition(connected.childNode(withName:"template-fluids",recursively:false)!.geometry!.sources(for:.vertex)[0].vectorCount == 40,
            "Canonical fluid families omit their shared face")

        let panes: [[String:Any]] = [["Name":"minecraft:glass"],["Name":"minecraft:stone"]]
        let onlyGlass = try Structures.volume("glass-only",size:[1,1,1],palette:panes,blocks:[0:0],assets:assets)
        precondition(onlyGlass.geometry == nil,"A translucent-only mesh must not retain an empty opaque vertex source")
        let glassMesh = onlyGlass.childNode(withName:"template-translucent",recursively:false)!.geometry!
        precondition(glassMesh.sources(for:.vertex)[0].vectorCount == 24); compact(glassMesh)
        let dividedMesh = try Structures.volume("mixed-glass",size:[2,1,1],palette:panes,blocks:[0:0,1:1],assets:assets)
        compact(dividedMesh.geometry!)
        compact(dividedMesh.childNode(withName:"template-translucent",recursively:false)!.geometry!)
        let mixedFluid = try Structures.volume("mixed-fluids",size:[2,1,1],palette:[["Name":"minecraft:water"],["Name":"minecraft:lava"]],
            blocks:[0:0,1:1],assets:assets)
        for name in ["template-fluids","template-lava"] {
            let geometry = mixedFluid.childNode(withName:name,recursively:false)!.geometry!
            precondition(geometry.sources(for:.vertex)[0].vectorCount == 24); compact(geometry)
        }
        let depths: [[String:Any]] = [0,7,3].map {["Name":"minecraft:water","Properties":["level":String($0)]]}
        let slope = try Structures.volume("flowing-slope",size:[2,1,2],palette:depths,blocks:[0:0,1:1,2:2],assets:assets)
            .childNode(withName:"template-fluids",recursively:false)!.geometry!
        let points = values(slope,.vertex), normals = values(slope,.normal), uv = values(slope,.texcoord)
        for index in points.indices where normals[index][1] == 0 {
            precondition(abs(uv[index][1]-(1-points[index][1]))<0.00001,"Shallow side textures preserve their texel height")
        }
        let top = Array(points.indices.filter {normals[$0][1]>0}.prefix(4))
        let a = uv[top[0]], b = uv[top[1]]
        precondition(abs(a[0]-b[0])>0.01 && abs(a[1]-b[1])>0.01,"A diagonal gradient rotates the source block's top UVs")
        let flowing = try assets.fluid(lava:false,flowing:true)
        let flowSlot = slope.materials.firstIndex {$0 === flowing}!
        let flowIndices = Set(indices(slope.elements[flowSlot]))
        precondition(top.allSatisfy {flowIndices.contains($0)},"A source block with a gradient uses the flowing top material")

        let stone: [[String:Any]] = [["Name":"minecraft:stone"],["Name":"minecraft:scaffolding"]]
        let boundary = try Structures.volume("cutout-boundary",size:[2,1,1],palette:stone,blocks:[0:0,1:1],assets:assets)
        let mesh = boundary.geometry!
        let slot = mesh.materials.firstIndex {$0.name == "textures/blocks/stone"}!
        precondition(mesh.elements[slot].primitiveCount == 12,"Cutout neighbours must preserve all six solid faces")
        let halo = try Structures.volume("halo",size:[3,1,3],palette:stone,blocks:Dictionary(uniqueKeysWithValues:(0..<9).map {($0,0)}),assets:assets,interior:true)
        precondition(halo.geometry!.sources(for:.vertex)[0].vectorCount == 8,"Only the centre cell's exposed top and bottom are emitted")

        let opaque = try assets.tiles("stone")[0], leaves = try assets.tiles("oak_leaves")[0], glass = try assets.tiles("glass")[0]
        precondition(opaque.blendMode == .replace && opaque.writesToDepthBuffer && !opaque.isDoubleSided)
        precondition(leaves.blendMode == .replace && leaves.writesToDepthBuffer && leaves.isDoubleSided)
        precondition(glass.blendMode == .alpha && !glass.writesToDepthBuffer)
        let log = try assets.tiles("oak_log",states:["axis":"x"])
        precondition(log[0] === log[2] && log[0] === log[4] && log[0] === log[5],"Equivalent rotated faces share one material")
        let short = try assets.tiles("seagrass",states:["sea_grass_type":"default"])
        let tallTop = try assets.tiles("seagrass",states:["sea_grass_type":"double_top"])
        let tallBottom = try assets.tiles("seagrass",states:["sea_grass_type":"double_bot"])
        let kelp = try assets.tiles("kelp",states:["tip":"false"]), kelpTip = try assets.tiles("kelp",states:["tip":"true"])
        precondition(short[0].name == "textures/blocks/seagrass" && tallTop[0].name == "textures/blocks/seagrass_doubletall_top_a")
        precondition(tallBottom[1].name == "textures/blocks/seagrass_doubletall_bottom_b")
        precondition(kelp[0].name == "textures/blocks/kelp_a" && kelpTip[0].name == "textures/blocks/kelp_top")

        let animated = try assets.fluid(lava:false)
        assets.animate(at:0)
        let first = animated.diffuse.contents as! CGImage
        precondition(first.width == first.height)
        assets.animate(at:0.1)
        precondition(first !== (animated.diffuse.contents as! CGImage),"Installed two-tick water metadata advances the cached frame")
        let reused = try assets.fluid(lava:false)
        precondition(animated === reused)
        let river = try assets.water(.river,native:"river"), frozen = try assets.water(.river,native:"frozen_river")
        let ocean = try assets.water(.reef,native:"ocean"), cold = try assets.water(.reef,native:"cold_ocean")
        let warm = try assets.water(.reef,native:"warm_ocean")
        precondition(river.colour == 0x0084FF && frozen.colour == 0x185390,"Native frozen-river water must survive the broad scenery biome")
        precondition(ocean.colour == 0x1787D4 && cold.colour == 0x2080C9 && warm.colour == 0x02B0E5 && ocean.opacity != warm.opacity)
        precondition(assets.waterFog("river")?.colour == 0x0084FF && assets.waterFog("frozen_river")?.colour == 0x185390)
        precondition(assets.waterFog("ocean")?.distance == 60 && assets.waterFog("frozen_river")?.distance == 20,
            "Underwater fog retains the installed native biome distances")
        let overlay = try assets.overlay(end:false)
        assets.animate(at:0)
        let portalFrame = overlay.diffuse.contents as! CGImage
        assets.animate(at:1)
        precondition(portalFrame !== (overlay.diffuse.contents as! CGImage),"The cached portal overlay follows the shared material clock")
        let sameOverlay = try assets.overlay(end:false)
        precondition(sameOverlay === overlay)
        let endOverlay = try assets.overlay(end:true)
        let portal = try Structures.volume("portal",size:[3,1,3],palette:[["Name":"minecraft:end_portal"]],blocks:Dictionary(uniqueKeysWithValues:(0..<9).map {($0,0)}),assets:assets)
        precondition(portal.geometry!.sources(for:.vertex)[0].vectorCount == 36,"All nine portal cells need an opaque void beneath the stars")
        precondition(portal.geometry!.materials.allSatisfy {$0.name == "end-void" && $0.writesToDepthBuffer && $0.blendMode == .replace})
        assets.animate(at:0)
        let portalOffset = endOverlay.diffuse.contentsTransform.m42
        assets.animate(at:1)
        precondition(endOverlay.diffuse.contentsTransform.m42 != portalOffset,"The End overlay retains its native scrolling clock")

        let upper = Data([9,1,1])+storage("oak_leaves")
        let lower = try Subchunk(Data([9,1,0])+storage("stone"))
        let upperSection = try Subchunk(upper)
        let canopy = try VoxelChunk(key:.init(x:0,z:0),dimension:0,sections:[0:lower,1:upperSection],biomeData:nil)
        let spans = Horizon.Tile(canopy,near:canopy.key).columns[0]
        precondition(spans.map(\.block.model) == ["stone","oak_leaves"],"Canopy cutouts cannot replace a solid column's material")

        var mixed = Data([9,1,0,2])
        for _ in 0..<128 { mixed.append(contentsOf:[0,255,0,255]) }
        mixed.append(contentsOf:[2,0,0,0]); mixed.append(storage("stone").dropFirst(5)); mixed.append(storage("oak_leaves").dropFirst(5))
        let section = try Subchunk(mixed)
        let patterned = try VoxelChunk(key:chunk.key,dimension:0,sections:[0:section],biomeData:nil)
        func reference(_ chunk: VoxelChunk, data: WorldData? = nil) -> [[Horizon.Span]] {
            let minimum = chunk.dimension == 0 ? -64 : 0, maximum = chunk.dimension == 1 ? 127 : chunk.dimension == 2 ? 255 : 319
            var columns: [[Horizon.Span]] = []
            for z in 0..<16 {for x in 0..<16 {
                var spans: [Horizon.Span] = []
                for medium in [false,true] {
                    var bottom: Int?, material: Block?, identity: String?
                    for y in minimum...(maximum+1) {
                        func cell(_ layer: Int) -> Block? {
                            guard y<=maximum else {return nil}
                            if let data {return data.block(chunk.key.x*16+x,y,chunk.key.z*16+z,layer:layer)}
                            return chunk.block(x,y,z,layer:layer)
                        }
                        let primary = cell(0)
                        let candidate = medium ? (primary?.fluid == true ? primary : cell(1)) : primary
                        let block = candidate.flatMap { block -> Block? in
                            (medium ? block.fluid : !block.passable && !block.fluid) ? block : nil
                        }
                        let native = block?.fluid == true ? chunk.biome(x,y,z).flatMap {Biome.identifiers[$0]} : nil
                        let same = (medium ? block?.liquid == material?.liquid : block == material) && native == identity
                        if let low = bottom, block == nil || !same {
                            spans.append(.init(bottom:low,top:y,block:material!,native:identity)); bottom = nil; material = nil; identity = nil
                        }
                        if let block {if bottom == nil {bottom = y}; material = block; identity = native}
                    }
                }
                columns.append(spans.sorted {$0.bottom<$1.bottom})
            } }
            return columns
        }
        var biomeBytes = Data(repeating:0,count:512)
        for _ in -4..<0 {biomeBytes.append(contentsOf:[1,7,0,0,0])}
        biomeBytes.append(3)
        for word in 0..<128 {
            var bits: UInt32 = 0
            for bit in 0..<32 {
                let index = word*32+bit
                if index/256>=8 || index%16>=8 {bits |= 1 << bit}
            }
            biomeBytes.append(contentsOf:(0..<4).map {UInt8(truncatingIfNeeded:bits >> ($0*8))})
        }
        biomeBytes.append(contentsOf:[2,0,0,0,7,0,0,0,11,0,0,0])
        let nativeChunk = try VoxelChunk(key:chunk.key,dimension:0,sections:[0:wet],biomeData:biomeBytes)
        let nativeTile = Horizon.Tile(nativeChunk,near:nativeChunk.key)
        precondition(nativeTile.columns[0].map(\.native) == ["river","frozen_river"]
            && nativeTile.columns[0].map(\.top) == [8,16] && nativeTile.columns[8].map(\.native) == ["frozen_river"],
            "Distant fluid spans retain horizontal and vertical native biome boundaries")
        precondition(nativeTile.columns == reference(nativeChunk))
        let nativeHorizon = try Horizon.node(.init(x:0,z:0),tiles:[nativeChunk.key:nativeTile],centre:.init(x:1,z:0),near:0,assets:assets)
        let distantWater = nativeHorizon.childNode(withName:"distant-fluids",recursively:false)!.geometry!
        let frozenFlow = try assets.fluid(lava:false,biome:.river,flowing:true,native:"frozen_river")
        precondition(distantWater.materials.contains {$0 === frozenFlow},"Horizon water uses each span's native material identity")
        let distantPoints = values(distantWater,.vertex), distantNormals = values(distantWater,.normal)
        precondition(distantPoints.indices.filter {distantNormals[$0][1]>0}.allSatisfy {distantPoints[$0][1]>15.8},
            "A fluid biome boundary cannot create an exposed surface inside a continuous column")
        var editedWorld = WorldData(dimension:0); editedWorld.chunks[nativeChunk.key] = nativeChunk
        editedWorld.apply([Cell(x:0,y:0,z:0):Block(name:"air"),Cell(x:0,y:8,z:0):Block(name:"stone"),
            Cell(x:0,y:16,z:0):Block(name:"stone"),Cell(x:0,y:-1,z:0):Block(name:"water")])
        let editedTile = Horizon.Tile(nativeChunk,near:nativeChunk.key,data:editedWorld)
        precondition(editedTile.columns == reference(nativeChunk,data:editedWorld),"Distant snapshots apply the same complete-cell edits as near meshes")
        precondition(editedTile.columns[0].contains {$0.bottom == 16 && $0.top == 17 && $0.block.model == "stone"}
            && editedTile.columns[0].contains {$0.bottom == -1 && $0.top == 0 && $0.block.liquid == "water"},
            "Edits can add spans in missing positive and negative sections")
        let negative = try VoxelChunk(key:.init(x:-1,z:-1),dimension:0,sections:[0:wet],biomeData:nil)
        var negativeWorld = WorldData(dimension:0); negativeWorld.chunks[negative.key] = negative
        negativeWorld.apply([Cell(x:-16,y:0,z:-16):Block(name:"air")])
        precondition(Horizon.Tile(negative,near:negative.key,data:negativeWorld).columns == reference(negative,data:negativeWorld))
        let samples = [chunk,canopy,patterned]
        for sample in samples {
            precondition(Horizon.Tile(sample,near:sample.key).columns == reference(sample),"Uniform and packed sections preserve the reference material/medium bands")
        }
        let started = ProcessInfo.processInfo.systemUptime
        var before = 0
        for _ in 0..<4 {for sample in samples {before += reference(sample).reduce(0) {$0+$1.count}}}
        let divided = ProcessInfo.processInfo.systemUptime
        var after = 0
        for _ in 0..<4 {for sample in samples {after += Horizon.Tile(sample,near:sample.key).columns.reduce(0) {$0+$1.count}}}
        let finished = ProcessInfo.processInfo.systemUptime
        precondition(before == after)
        print(String(format:"Horizon 12-fixture reference %.2f ms, section runs %.2f ms, spans %d",(divided-started)*1000,(finished-divided)*1000,after))

        let fox = try assets.actor("fox",texture:"red")
        precondition(fox.childNode(withName:"head_sleeping",recursively:true) != nil && fox.childNode(withName:"head_sleeping",recursively:true)?.geometry == nil)
        let armadillo = try assets.actor("armadillo")
        precondition(armadillo.childNode(withName:"body_rolled_up",recursively:true) != nil && armadillo.childNode(withName:"body_rolled_up",recursively:true)?.geometry == nil)
        for name in ["camel","camel_husk"] {
            let camel = try assets.actor(name)
            precondition(camel.childNode(withName:"saddle",recursively:true)?.geometry == nil)
        }
        for (name,layer) in [("slime","slime-shell"),("bogged","bogged-clothes"),("breeze","breeze-eyes"),("stray","stray-clothes")] {
            let actor = try assets.actor(name)
            precondition(actor.childNode(withName:layer,recursively:false) != nil,"Required native layer: \(layer)")
        }
    }
}
