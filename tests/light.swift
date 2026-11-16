import AppKit
import SceneKit

// Called by the native launcher checks, with no world files or GPU needed
enum LightChecks {
    static func run() throws {
        let key = Chunk(x:0,z:0)
        var world = WorldData(dimension:0)
        world.chunks[key] = try VoxelChunk(key:key,dimension:0,sections:[:],biomeData:nil)
        var edits: [Cell:Block] = [:]
        for y in -16...20 { for z in 0..<16 { edits[Cell(x:4,y:y,z:z)] = Block(name:"stone") } }
        edits[Cell(x:2,y:2,z:2)] = Block(name:"torch")
        edits[Cell(x:12,y:2,z:13)] = Block(name:"torch")
        edits[Cell(x:13,y:2,z:13)] = Block(name:"water")
        for x in 6...10 { for z in 6...10 {
            edits[Cell(x:x,y:10,z:z)] = Block(name:"stone")
            for y in 0...9 where x == 6 || x == 10 || z == 6 || z == 10 {
                edits[Cell(x:x,y:y,z:z)] = Block(name:"stone")
            }
            edits[Cell(x:x,y:0,z:z)] = Block(name:"stone")
        } }
        edits[Cell(x:8,y:10,z:8)] = Block(name:"air")
        world.apply(edits)
        let light = try Light(data:world,key:key)
        precondition(light.levels(x:8,y:8,z:8).sky == 15,"Open shafts carry full skylight downwards")
        precondition(light.levels(x:9,y:8,z:8).sky == 14,"Skylight spreads into the entrance with distance loss")
        precondition(light.levels(x:8,y:9,z:9).sky == 14,"The roof blocks direct light beside the shaft")
        precondition(light.levels(x:4,y:8,z:2).sky == 0,"Opaque walls have no skylight")
        precondition(light.levels(x:2,y:2,z:2).block == 14)
        precondition(light.levels(x:3,y:2,z:2).block == 13)
        precondition(light.levels(x:5,y:2,z:2).block == 0,"A solid wall prevents torchlight leaking through it")
        precondition(light.levels(x:13,y:2,z:13).block == 11,"Water attenuates blocklight by three levels")
        precondition(light.levels(x:13,y:2,z:13).sky == 12,"Water attenuates direct skylight")
        precondition(light.levels(x:-1,y:64,z:2) == (0,0),"Missing chunks are sealed instead of pretending to be air")
        precondition(light.metrics.cells == 46*384*46 && light.metrics.workingBytes == light.metrics.cells*6)

        let material = SCNMaterial()
        let cutout = "if (_output.color.a < 0.1) { discard_fragment(); }"
        material.shaderModifiers = [.fragment:cutout]
        Light.configure(material:material)
        precondition(material.lightingModel == .constant && material.shaderModifiers?[.fragment] == cutout)
        precondition(material.shaderModifiers?[.geometry]?.contains("_geometry.color = float4(1.0)") == true)
        precondition(material.shaderModifiers?[.surface]?.contains("in.minecraftLight") == true)
        let before = material.shaderModifiers
        Light.configure(material:material)
        precondition(material.shaderModifiers == before,"Configuring a cached lit material must be idempotent")
        Light.illuminate(materials:[material],daylight:0)
        precondition((material.value(forKey:"minecraftDay") as? NSNumber)?.doubleValue == 0)
        Light.illuminate(materials:[material],daylight:1)
        precondition((material.value(forKey:"minecraftDay") as? NSNumber)?.doubleValue == 1)

        // Interleaved Float vertices verify native decoding, child transforms and source retention
        let positions: [Float] = [0,1,2,77, 1,1,2,77, 0,2,2,77]
        let normals = [SCNVector3(0,0,1),SCNVector3(0,0,1),SCNVector3(0,0,1)]
        let source = positions.withUnsafeBytes { bytes in
            SCNGeometrySource(data:Data(bytes),semantic:.vertex,vectorCount:3,usesFloatComponents:true,
                              componentsPerVector:3,bytesPerComponent:4,dataOffset:0,dataStride:16)
        }
        let uv = SCNGeometrySource(textureCoordinates:[.zero,.init(x:1,y:0),.init(x:0,y:1)])
        let geometry = SCNGeometry(sources:[source,SCNGeometrySource(normals:normals),uv],
                                   elements:[SCNGeometryElement(indices:[Int32(0),1,2],primitiveType:.triangles)])
        let original = SCNMaterial(); geometry.materials = [original]
        let root = SCNNode(), node = SCNNode(geometry:geometry)
        root.position = .init(1,0,0); node.position = .init(0,0,1); root.addChildNode(node)
        let bindings = try light.apply(to:root,material:{ _ in material })
        precondition(bindings.count == 1 && bindings[0] === material && original.shaderModifiers == nil)
        precondition(node.geometry?.sources(for:.color).first?.vectorCount == 3)
        precondition(node.geometry?.sources(for:.texcoord).count == 1 && node.geometry?.materials.first === material)
        precondition(geometry.sources(for:.color).isEmpty,"Baking must not mutate a shared source geometry")

        do { _ = try Light(data:world,key:key,cancelled:{true}); preconditionFailure("Cancelled lights must not return a partial field") }
        catch is CancellationError {}
        do { try light.apply(to:root,cancelled:{true}); preconditionFailure("Cancelled baking must stop") }
        catch is CancellationError {}

        // A generated two-layer subchunk verifies secondary water and original emitters
        func section(_ names: [String]) throws -> Subchunk {
            var bytes = Data([9,UInt8(names.count),0])
            for name in names {
                bytes.append(contentsOf:[0,1,0,0,0,10,0,0,8,4,0])
                bytes.append(contentsOf:"name".utf8)
                let value = Array(("minecraft:"+name).utf8)
                bytes.append(contentsOf:[UInt8(value.count),0]); bytes.append(contentsOf:value)
                bytes.append(contentsOf:[10,6,0]); bytes.append(contentsOf:"states".utf8); bytes.append(contentsOf:[0,0])
            }
            return try Subchunk(bytes)
        }
        var secondary = WorldData(dimension:0)
        secondary.chunks[key] = try VoxelChunk(key:key,dimension:0,sections:[0:try section(["air","water"])],biomeData:nil)
        let wet = try Light(data:secondary,key:key)
        precondition(wet.levels(x:8,y:15,z:8).sky == 12 && wet.levels(x:8,y:14,z:8).sky == 9)
        secondary.apply([Cell(x:8,y:15,z:8):Block(name:"air")])
        let drained = try Light(data:secondary,key:key)
        precondition(drained.levels(x:8,y:15,z:8).sky == 15,"Complete-cell edits remove inherited water attenuation")
        secondary.edits.removeAll()
        secondary.chunks[key] = try VoxelChunk(key:key,dimension:0,sections:[0:try section(["glowstone"])],biomeData:nil)
        let generated = try Light(data:secondary,key:key)
        precondition(generated.levels(x:8,y:15,z:8).block == 15 && generated.levels(x:8,y:16,z:8).block == 14)
        precondition(generated.levels(x:8,y:15,z:8).sky == 0)
        print("Voxel lighting: cells=\(light.metrics.cells), visits=\(light.metrics.visits), seconds=\(light.metrics.seconds), workingBytes=\(light.metrics.workingBytes)")
    }
}
