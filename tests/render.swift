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

        let palette: [[String:Any]] = [["Name":"minecraft:seagrass"],["Name":"minecraft:water"],["Name":"minecraft:flowing_water"]]
        let plant = try Structures.volume("wet-plant",size:[1,1,1],palette:palette,blocks:[0:0],fluids:[0:1],assets:assets)
        precondition(plant.geometry?.sources(for:.vertex).first?.vectorCount == 8)
        let water = plant.childNode(withName:"template-fluids",recursively:false)!
        precondition(water.categoryBitMask == 1 && water.geometry!.sources(for:.vertex)[0].vectorCount == 24)
        precondition(water.geometry!.materials.allSatisfy {!$0.writesToDepthBuffer && $0.readsFromDepthBuffer})
        let connected = try Structures.volume("connected-water",size:[2,1,1],palette:palette,blocks:[:],fluids:[0:1,1:2],assets:assets)
        precondition(connected.childNode(withName:"template-fluids",recursively:false)!.geometry!.sources(for:.vertex)[0].vectorCount == 40,
            "Canonical fluid families omit their shared face")

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
        func reference(_ chunk: VoxelChunk) -> [[Horizon.Span]] {
            let minimum = chunk.dimension == 0 ? -64 : 0, maximum = chunk.dimension == 1 ? 127 : chunk.dimension == 2 ? 255 : 319
            var columns: [[Horizon.Span]] = []
            for z in 0..<16 {for x in 0..<16 {
                var spans: [Horizon.Span] = []
                for medium in [false,true] {
                    var bottom: Int?, material: Block?
                    for y in minimum...(maximum+1) {
                        let primary = y<=maximum ? chunk.block(x,y,z) : nil
                        let candidate = y<=maximum ? (medium ? (primary?.fluid == true ? primary : chunk.block(x,y,z,layer:1)) : primary) : nil
                        let block = candidate.flatMap { block -> Block? in
                            (medium ? block.fluid : !block.passable && !block.fluid) ? block : nil
                        }
                        let same = medium ? block?.liquid == material?.liquid : block == material
                        if let low = bottom, block == nil || !same {
                            spans.append(.init(bottom:low,top:y,block:material!)); bottom = nil; material = nil
                        }
                        if let block {if bottom == nil {bottom = y}; material = block}
                    }
                }
                columns.append(spans.sorted {$0.bottom<$1.bottom})
            } }
            return columns
        }
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
