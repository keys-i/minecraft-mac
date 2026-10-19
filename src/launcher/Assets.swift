import AppKit
import SceneKit
import simd
import CoreText

struct Archive {
    let data: Data
    let entries: [String: Range<Int>]

    init(_ data: Data) throws {
        guard data.count >= 16, data.count <= 128 * 1024 * 1024,
              Array(data.prefix(8)) == [0x7D,0x27,0x25,0xB1,0xA0,0x52,0x70,0x26] else { throw AssetError.archive }
        func integer(_ offset: Int) -> Int {
            (0..<4).reduce(0) { $0 | (Int(data[offset+$1]) << ($1*8)) }
        }
        let count = integer(8), base = 16+count*256
        guard integer(12) == 1, count <= 100_000, base <= data.count else { throw AssetError.archive }
        var entries: [String: Range<Int>] = [:]
        for index in 0..<count {
            let offset = 16+index*256, length = Int(data[offset])
            guard length <= 247,
                  let name = String(data:data[(offset+1)..<(offset+1+length)],encoding:.utf8) else { throw AssetError.archive }
            let start = base+integer(offset+248), end = start+integer(offset+252)
            guard start >= base, end >= start, end <= data.count else { throw AssetError.archive }
            if end > start { entries[name] = start..<end }
        }
        self.data = data; self.entries = entries
    }

    subscript(_ name: String) -> Data? { entries[name].map { data.subdata(in:$0) } }
}

enum AssetError: Error {
    case archive, model, image, missing(String)
}

final class Assets {
    let started = ProcessInfo.processInfo.systemUptime
    // The live launcher transfers completed graphs from this serial builder to the main thread
    let queue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "Minecraft scenery"
        queue.maxConcurrentOperationCount = 1
        queue.qualityOfService = .userInitiated
        return queue
    }()
    let resources: [URL]
    let behaviours: [URL]
    private var documents: [String: [String: Any]] = [:]
    private var directories: [String: [String]] = [:]
    private var archives: [URL: Archive] = [:]
    private var materials: [String: SCNMaterial] = [:]
    private var tilesets: [String: [SCNMaterial]] = [:]
    private var tables: [String: [String: Any]] = [:]

    init(data: URL, classic: Bool = false) throws {
        func packs(_ directory: String) throws -> [URL] {
            try FileManager.default.contentsOfDirectory(at:data.appendingPathComponent(directory),includingPropertiesForKeys:nil)
                .filter { $0.lastPathComponent == "vanilla" || $0.lastPathComponent.hasPrefix("vanilla_") }
                .sorted { $0.lastPathComponent.compare($1.lastPathComponent,options:.numeric) == .orderedAscending }
        }
        resources = try packs("resource_packs").filter { !classic || $0.lastPathComponent == "vanilla" }
        behaviours = try packs("behavior_packs")
        guard !resources.isEmpty else { throw AssetError.missing("vanilla resource pack") }
    }

    /// Build on the asset queue and transfer the finished graph to the main thread
    @discardableResult
    func load(_ world: World, biome: Int, passage: Passage?, arrival: Passage? = nil, completion: @escaping @MainActor (Result<SCNScene, Error>) -> Void) -> Operation {
        let operation = BlockOperation()
        operation.addExecutionBlock { [weak operation] in
            guard let operation, !operation.isCancelled else { return }
            let result = Result {
                let scene = try passage?.scene(assets:self) ?? Landscape.scene(world,biome:biome,assets:self)
                if let arrival { try Landscape.arrive(scene,world:world,biome:biome,passage:arrival,assets:self) }
                // Commit actions created after preparation before handing the graph to another renderer
                SCNTransaction.flush()
                return scene
            }
            self.releaseArchives()
            guard !operation.isCancelled else { return }
            DispatchQueue.main.async {
                guard !operation.isCancelled else { return }
                completion(result)
            }
        }
        queue.addOperation(operation)
        return operation
    }

    func icons(completion: @escaping @MainActor ([World:NSImage],NSImage?,[String:NSImage],CTFont?,String) -> Void) {
        let operation = BlockOperation()
        operation.addExecutionBlock {
            let paths: [World:String] = [.overworld:"diamond_pickaxe",.nether:"flint_and_steel",.end:"ender_eye",.sift:"amethyst_shard"]
            var images: [World:NSImage] = [:]
            for (world,path) in paths {
                if let material = try? self.texture("textures/items/"+path) {
                    let bitmap = material.diffuse.contents as! CGImage
                    images[world] = NSImage(cgImage:bitmap,size:NSSize(width:32,height:32))
                }
            }
            let face = try? self.texture("textures/blocks/stone")
            let stone = face.map { NSImage(cgImage:$0.diffuse.contents as! CGImage,size:NSSize(width:32,height:32)) }
            var frames: [String:NSImage] = [:]
            for name in ["hotbar_0","selected_hotbar_slot","title","icon_setting","sound_glyph","how_to_play_button_default","camera-small","spyglass"] {
                if let material = try? self.texture((name == "spyglass" ? "textures/items/" : "textures/ui/")+name) {
                    let bitmap = material.diffuse.contents as! CGImage
                    frames[name] = NSImage(cgImage:bitmap,size:NSSize(width:bitmap.width,height:bitmap.height))
                }
            }
            var font: CTFont?
            if let bytes = try? self.file("font/minecraft-ten.ttf"), bytes.count <= 4*1024*1024,
               let provider = CGDataProvider(data:bytes as CFData), let face = CGFont(provider) {
                font = CTFontCreateWithGraphicsFont(face,28,nil,nil)
            }
            let splashes = (try? self.json("splashes.json")["splashes"] as? [String]) ?? []
            let splash = splashes.filter { !$0.isEmpty && $0.count <= 80 }.randomElement() ?? ""
            self.releaseArchives()
            DispatchQueue.main.async { completion(images,stone,frames,font,splash) }
        }
        queue.addOperation(operation)
    }

    func music() throws -> [String] {
        try ["sounds/music/menu","sounds/music/game"].flatMap { directory in
            try names(directory).filter { $0.hasSuffix(".ogg") && !$0.contains("/") && !$0.contains("\\") }
                .map { directory+"/"+$0 }
        }.prefix(128).map { $0 }
    }

    func releaseArchives() { archives.removeAll() }

    private func archive(_ url: URL) throws -> Archive {
        if let found = archives[url] { return found }
        let found = try Archive(Data(contentsOf:url,options:.mappedIfSafe))
        archives[url] = found
        return found
    }

    func file(_ path: String, behaviour: Bool = false) throws -> Data {
        guard !path.hasPrefix("/"), !path.split(separator:"/").contains(".."), !path.contains("\\") else { throw AssetError.missing(path) }
        let directory = (path as NSString).deletingLastPathComponent, name = (path as NSString).lastPathComponent
        for pack in (behaviour ? behaviours : resources).reversed() {
            let bundle = pack.appendingPathComponent("__brarchive/"+directory+".brarchive")
            if FileManager.default.fileExists(atPath:bundle.path), let data = try archive(bundle)[name] { return data }
            let plain = pack.appendingPathComponent(path)
            if FileManager.default.fileExists(atPath:plain.path) { return try Data(contentsOf:plain,options:.mappedIfSafe) }
        }
        throw AssetError.missing(path)
    }

    func json(_ path: String) throws -> [String: Any] {
        if let document = documents[path] { return document }
        let data = try file(path)
        guard data.count <= 2*1024*1024, let result = try JSONSerialization.jsonObject(with:data,options:.json5Allowed) as? [String: Any] else { throw AssetError.model }
        if documents.count < 128 { documents[path] = result }
        return result
    }

    private func names(_ directory: String) throws -> [String] {
        if let names = directories[directory] { return names }
        var result = Set<String>()
        for pack in resources {
            let bundle = pack.appendingPathComponent("__brarchive/"+directory+".brarchive")
            if FileManager.default.fileExists(atPath:bundle.path) { result.formUnion(try archive(bundle).entries.keys) }
            let plain = pack.appendingPathComponent(directory)
            if FileManager.default.fileExists(atPath:plain.path) {
                result.formUnion(try FileManager.default.contentsOfDirectory(atPath:plain.path))
            }
        }
        let names = result.sorted()
        directories[directory] = names
        return names
    }

    func texture(_ path: String, tint: UInt32? = nil, animated: Bool = false) throws -> SCNMaterial {
        let key = path+"-"+(tint.map(String.init) ?? "none")+(animated ? "-animated" : "")
        if let material = materials[key] { return material }
        let data: Data
        do { data = try file(path+".png") }
        catch AssetError.missing { data = try file(path+".tga") }
        guard data.count <= 8*1024*1024, let image = NSImage(data:data),
              let decoded = image.cgImage(forProposedRect:nil,context:nil,hints:nil),
              decoded.width <= 2048, decoded.height <= 4096 else { throw AssetError.image }
        var bitmap = !animated && path.hasPrefix("textures/blocks/") && decoded.height > decoded.width && decoded.height % decoded.width == 0
            ? decoded.cropping(to:CGRect(x:0,y:0,width:decoded.width,height:decoded.width))! : decoded
        if let tint {
            guard let context = CGContext(data:nil,width:bitmap.width,height:bitmap.height,bitsPerComponent:8,bytesPerRow:bitmap.width*4,
                space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue),
                  let data = context.data else { throw AssetError.image }
            context.draw(bitmap,in:CGRect(x:0,y:0,width:bitmap.width,height:bitmap.height))
            let pixels = data.assumingMemoryBound(to:UInt8.self)
            for i in stride(from:0,to:bitmap.width*bitmap.height*4,by:4) {
                for channel in 0..<3 { pixels[i+channel] = UInt8(UInt32(pixels[i+channel])*((tint >> ((2-channel)*8)) & 255)/255) }
            }
            guard let tinted = context.makeImage() else { throw AssetError.image }
            bitmap = tinted
        }
        let material = SCNMaterial()
        material.name = path
        material.diffuse.contents = bitmap
        material.diffuse.magnificationFilter = .nearest
        material.diffuse.minificationFilter = .nearest
        material.diffuse.mipFilter = path.hasPrefix("textures/blocks/") ? .linear : .none
        if path.hasPrefix("textures/blocks/") { material.diffuse.minificationFilter = .linear }
        material.diffuse.wrapS = .repeat; material.diffuse.wrapT = .repeat
        material.lightingModel = .lambert
        material.transparencyMode = .aOne
        // Minecraft cutouts must not hide the opaque mesh beneath them
        material.shaderModifiers = [.fragment: "if (_output.color.a < 0.1) { discard_fragment(); }"]
        material.isDoubleSided = true
        materials[key] = material
        return material
    }

    func actor(_ name: String, texture key: String = "default", variant: Int = 0) throws -> SCNNode {
        let document = try json("entity/"+name+".entity.json")
        guard let entity = document["minecraft:client_entity"] as? [String: Any],
              let description = entity["description"] as? [String: Any],
              let geometries = description["geometry"] as? [String: String], let identifier = geometries[key] ?? geometries["default"],
              let textures = description["textures"] as? [String: String], let image = textures[key] else { throw AssetError.model }
        let definition = try geometry(identifier, entity: name)
        let skin = try texture(image)
        let material = skin.copy() as! SCNMaterial
        // These native shaders use texture alpha for dye or emission rather than holes
        if ["enderman","blaze"].contains(name) || (description["materials"] as? [String: String])?["default"] == "sheep" {
            let image = skin.diffuse.contents as! CGImage
            if image.alphaInfo == .last || image.alphaInfo == .first {
                let alpha = image.alphaInfo == .last ? CGImageAlphaInfo.noneSkipLast : .noneSkipFirst
                let format = CGBitmapInfo(rawValue:(image.bitmapInfo.rawValue & ~CGBitmapInfo.alphaInfoMask.rawValue) | alpha.rawValue)
                material.diffuse.contents = CGImage(width:image.width,height:image.height,bitsPerComponent:image.bitsPerComponent,
                    bitsPerPixel:image.bitsPerPixel,bytesPerRow:image.bytesPerRow,space:image.colorSpace!,bitmapInfo:format,
                    provider:image.dataProvider!,decode:nil,shouldInterpolate:false,intent:.defaultIntent)!
            }
            material.blendMode = .replace
        }
        if name == "enderman" {
            let source = NSBitmapImageRep(cgImage:skin.diffuse.contents as! CGImage)
            let eyes = NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:source.pixelsWide,pixelsHigh:source.pixelsHigh,
                bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
            for y in 0..<source.pixelsHigh { for x in 0..<source.pixelsWide {
                let colour = source.colorAt(x:x,y:y)!.usingColorSpace(.deviceRGB)!
                let emits = colour.alphaComponent>0 && colour.alphaComponent<0.1
                eyes.setColor(NSColor(deviceRed:emits ? colour.redComponent : 0,green:emits ? colour.greenComponent : 0,
                    blue:emits ? colour.blueComponent : 0,alpha:1),atX:x,y:y)
            } }
            material.emission.contents = eyes.cgImage
        }
        if let glow = textures["eyes"] ?? textures["bioluminescent_layer"] {
            material.emission.contents = try texture(glow).diffuse.contents
        } else if name == "blaze" || name == "glow_squid" {
            material.emission.contents = material.diffuse.contents
            material.emission.intensity = 0.4
        }
        if name == "tropicalfish" { material.multiply.contents = Landscape.colour(key == "typeA" ? 0xF4C052 : 0x56B4CE) }
        let model = try node(definition,material:material)
        if name == "copper_golem", let eyes = textures["eyes_"+key] {
            let glow = try texture(eyes).copy() as! SCNMaterial
            glow.lightingModel = .constant
            let layer = try node(definition,material:glow)
            layer.name = "golem-eyes"
            model.addChildNode(layer)
        }
        if name == "tropicalfish", let path = textures[(key == "typeA" ? "aPattern" : "bPattern")+String(variant%6+1)] {
            let markings = try texture(path).copy() as! SCNMaterial
            markings.multiply.contents = Landscape.colour([0xFAF7E9,0xD95D39,0x4DA9BB,0x292D36,0xB471C9,0xF1B844][variant%6])
            let layer = try node(definition,material:markings)
            layer.name = "fish-pattern"; layer.scale = .init(1.006,1.006,1.006)
            model.addChildNode(layer)
        }
        if name == "breeze", let wind = textures["breeze_wind"] {
            for key in ["breeze_wind_top", "breeze_wind_mid", "breeze_wind_bottom"] {
                guard let identifier = geometries[key] else { throw AssetError.model }
                let layer = try node(geometry(identifier, entity: name), material: texture(wind))
                layer.name = key
                layer.runAction(.repeatForever(.rotateBy(x:0,y:.pi*2,z:0,duration:4)))
                model.addChildNode(layer)
            }
        }
        assemble(model, name: name)
        model.name = name
        if let script = description["scripts"] as? [String: Any] {
            let scale = (script["scale"] as? NSNumber)?.doubleValue ?? Double(script["scale"] as? String ?? "") ?? 1
            if scale > 0 && scale <= 16 { model.scale = .init(scale,scale,scale) }
        }
        model.eulerAngles.y = .pi
        return model
    }

    private func assemble(_ model: SCNNode, name: String) {
        if name == "enderman", let head = model.childNode(withName:"head",recursively:true) {
            // Legacy Enderman geometry requires the game's standing head attachment
            head.position.y = 0
            head.childNode(withName:"hat",recursively:false)?.position = .init(0,0,0)
        }
        if name == "blaze" {
            for ring in 0..<3 {
                let orbit = SCNNode(); orbit.name = "rod-orbit-\(ring)"
                model.addChildNode(orbit)
                for index in 0..<4 {
                    guard let rod = model.childNode(withName:"upperBodyParts\(ring*4+index)",recursively:false) else { continue }
                    let phase = ring == 0 ? 0.0 : ring == 1 ? 45 : 27
                    let angle = (Double(index)*90+phase)*Double.pi/180
                    let radius = Double(9-ring*2)/16
                    rod.removeFromParentNode(); orbit.addChildNode(rod)
                    let level = Double([26,22,13][ring])/16
                    rod.position = .init(cos(angle)*radius,level,sin(angle)*radius)
                    let phaseY = Double(ring*4+index)*(ring == 2 ? 1.5 : 2)
                    rod.runAction(.repeatForever(.customAction(duration:18) { node,time in
                        node.position.y = level+cos((phaseY+Double(time)*20)*14.32 * .pi/180)/16
                    }))
                }
                orbit.runAction(.repeatForever(.rotateBy(x:0,y:ring == 1 ? .pi*2 : -.pi*2,z:0,duration:[1,10.0/3,2][ring])))
            }
        }
        guard name == "ender_dragon" else { return }
        // The vanilla renderer assembles repeated segments and mirrored wings in code
        var parts: [String: SCNGeometry] = [:]
        model.enumerateChildNodes { node,_ in if let name = node.name, let mesh = node.geometry { parts[name.lowercased()] = mesh } }
        model.childNodes.forEach { $0.removeFromParentNode() }
        @discardableResult
        func part(_ name: String, at position: SCNVector3, parent: SCNNode? = nil) -> SCNNode {
            let node = SCNNode(geometry:parts[name]); node.name = name; node.position = position
            (parent ?? model).addChildNode(node)
            return node
        }
        part("body",at:.init(0,0,0))
        for index in 0..<5 {
            let neck = part("neck",at:.init(0,0.2+Double(index)*0.1,-1.1-Double(index)*0.48))
            VoxelAdventure.sway(neck,y:0.07,period:5,phase:Double(index)*0.25)
        }
        let head = part("head",at:.init(0,0.7,-3.4))
        part("jaw",at:.init(0,-0.25,-0.5),parent:head)
        for index in 0..<12 {
            let tail = part("neck",at:.init(sin(Double(index)*0.2)*0.2,-Double(index)*0.04,3.2+Double(index)*0.48))
            VoxelAdventure.sway(tail,y:0.08,period:5,phase:Double(index)*0.3)
        }
        for side in [-1.0,1] {
            let mirror = SCNNode(); mirror.scale = .init(side,1,1); model.addChildNode(mirror)
            let wing = part("wing",at:.init(-0.75,0,0),parent:mirror)
            let tip = part("wingtip",at:.init(-3.5,0,0.12),parent:wing)
            VoxelAdventure.sway(wing,z:0.35,period:2.4)
            VoxelAdventure.sway(tip,z:0.25,period:2.4,phase:0.5)
            for rear in [false,true] {
                let leg = part(rear ? "rearleg" : "frontleg",at:.init(side*(rear ? 0.9 : 0.65),-0.7,rear ? 2.2 : -0.4))
                let tip = part(rear ? "rearlegtip" : "frontlegtip",at:.init(0,rear ? -1.3 : -0.9,0),parent:leg)
                part(rear ? "rearfoot" : "frontfoot",at:.init(0,rear ? -1.7 : -1.1,0.1),parent:tip)
                leg.eulerAngles.x = 0.6; tip.eulerAngles.x = -0.7
            }
        }
    }

    private func geometry(_ identifier: String, entity: String, depth: Int = 0) throws -> [String: Any] {
        guard depth < 8 else { throw AssetError.model }
        let stem = (identifier.split(separator:".").dropFirst().first.map(String.init) ?? entity).replacingOccurrences(of:"_",with:"")
        let prefix = entity.replacingOccurrences(of:"_",with:"")
        let candidates = try names("models/entity").filter {
            let name = $0.replacingOccurrences(of:"_",with:"")
            return name.hasPrefix(stem) || name.hasPrefix(prefix)
        }
            .map { "models/entity/"+$0 } + ["models/mobs.json"]
        for candidate in candidates {
            let object = try json(candidate)
            if let definition = object[identifier] as? [String: Any] { return definition }
            if let modern = object["minecraft:geometry"] as? [[String: Any]],
               let definition = modern.first(where: { ($0["description"] as? [String: Any])?["identifier"] as? String == identifier }) { return definition }
            if let entry = object.first(where: { $0.key.split(separator:":").first.map(String.init) == identifier }),
               let derived = entry.value as? [String: Any], let parent = entry.key.split(separator:":").dropFirst().first {
                var base = try geometry(String(parent),entity:entity,depth:depth+1)
                var bones = base["bones"] as? [[String: Any]] ?? []
                for child in derived["bones"] as? [[String: Any]] ?? [] {
                    if let index = bones.firstIndex(where: { $0["name"] as? String == child["name"] as? String }) {
                        let cubes = (bones[index]["cubes"] as? [[String: Any]] ?? []) + (child["cubes"] as? [[String: Any]] ?? [])
                        bones[index].merge(child) { _,value in value }; bones[index]["cubes"] = cubes
                    } else { bones.append(child) }
                }
                base.merge(derived) { _,value in value }; base["bones"] = bones
                return base
            }
        }
        throw AssetError.missing(identifier)
    }

    private func node(_ definition: [String: Any], material: SCNMaterial) throws -> SCNNode {
        let description = definition["description"] as? [String: Any] ?? definition
        let image = material.diffuse.contents as! CGImage
        let width = (description["texture_width"] ?? description["texturewidth"]) as? Double ?? Double(image.width)
        let height = (description["texture_height"] ?? description["textureheight"]) as? Double ?? Double(image.height)
        guard width.isFinite, height.isFinite, width > 0, height > 0, width <= 4096, height <= 4096, let bones = definition["bones"] as? [[String: Any]], bones.count <= 256 else { throw AssetError.model }
        func vector(_ value: Any?) throws -> SCNVector3 {
            guard let value else { return .init(0,0,0) }
            guard let a = value as? [Double], a.count == 3, a.allSatisfy({ $0.isFinite && abs($0) <= 4096 }) else { throw AssetError.model }
            return .init(a[0],a[1],a[2])
        }
        let root = SCNNode()
        var nodes: [String: SCNNode] = [:]
        for bone in bones {
            guard let name = bone["name"] as? String, nodes[name.lowercased()] == nil else { throw AssetError.model }
            let node = SCNNode(); node.name = name; nodes[name.lowercased()] = node
            root.addChildNode(node)
        }
        var bases: [String: simd_float4x4] = [:]
        var parents: [String: String] = [:]
        for bone in bones {
            let name = (bone["name"] as! String).lowercased(), pivot = try vector(bone["pivot"])
            let bind = try vector(bone["bind_pose_rotation"]), pose = SCNNode()
            pose.position = .init(pivot.x/16,pivot.y/16,pivot.z/16)
            pose.eulerAngles = .init(-bind.x * .pi/180,-bind.y * .pi/180,bind.z * .pi/180)
            bases[name] = pose.simdTransform
            parents[name] = (bone["parent"] as? String)?.lowercased()
        }
        for name in nodes.keys {
            var seen = Set([name]), current = name
            while let parent = parents[current] {
                guard nodes[parent] != nil, seen.insert(parent).inserted else { throw AssetError.model }
                current = parent
            }
        }
        for bone in bones {
            let name = (bone["name"] as! String).lowercased(), node = nodes[name]!
            if let parent = parents[name] { nodes[parent]!.addChildNode(node) }
            let pivot = try vector(bone["pivot"]), rotation = try vector(bone["rotation"])
            let pose = SCNNode()
            pose.eulerAngles = .init(-rotation.x * .pi/180,-rotation.y * .pi/180,rotation.z * .pi/180)
            let parent = parents[name].flatMap { bases[$0] } ?? matrix_identity_float4x4
            node.simdTransform = simd_inverse(parent)*bases[name]!*pose.simdTransform
            var mesh = Voxels()
            let cubes = bone["cubes"] as? [[String: Any]] ?? []
            guard cubes.count <= 2048 else { throw AssetError.model }
            for cube in cubes {
                guard cube["origin"] != nil, cube["size"] != nil else { throw AssetError.model }
                let origin = try vector(cube["origin"]), size = try vector(cube["size"])
                let inflate = cube["inflate"] as? Double ?? bone["inflate"] as? Double ?? 0
                let w = Double(size.x), h = Double(size.y), d = Double(size.z)
                guard inflate.isFinite, abs(inflate) <= 16, w >= 0, h >= 0, d >= 0 else { throw AssetError.model }
                var rects: [CGRect]
                var availableFaces = 63
                if let uv = cube["uv"] as? [Double], uv.count == 2, uv.allSatisfy(\.isFinite) {
                    let u = uv[0], v = uv[1]
                    rects = [CGRect(x:u+d+w+d,y:v+d,width:w,height:h),CGRect(x:u,y:v+d,width:d,height:h),
                             CGRect(x:u+d,y:v+d,width:w,height:h),CGRect(x:u+d+w,y:v+d,width:d,height:h),
                             CGRect(x:u+d,y:v,width:w,height:d),CGRect(x:u+d+w,y:v,width:w,height:d)]
                } else if let uv = cube["uv"] as? [String: [String: Any]] {
                    availableFaces = ["south","east","north","west","up","down"].enumerated().reduce(0) { $0 | (uv[$1.element] == nil ? 0 : 1 << $1.offset) }
                    rects = try ["south","east","north","west","up","down"].map { face in
                        let location = uv[face]?["uv"] as? [Double] ?? [0,0]
                        let span = uv[face]?["uv_size"] as? [Double] ?? [0,0]
                        guard location.count == 2, span.count == 2, (location+span).allSatisfy(\.isFinite) else { throw AssetError.model }
                        return CGRect(x:location[0],y:location[1],width:span[0],height:span[1])
                    }
                } else { throw AssetError.model }
                let mirror = cube["mirror"] as? Bool ?? bone["mirror"] as? Bool ?? false
                rects = rects.map { rect in
                    CGRect(x:(rect.origin.x+(mirror ? rect.size.width : 0))/width,y:(rect.origin.y+rect.size.height)/height,
                           width:(mirror ? -rect.size.width : rect.size.width)/width,height:-rect.size.height/height)
                }
                let plane = w == 0 ? [1,3] : h == 0 ? [4,5] : d == 0 ? [0,2] : []
                let faces = plane.isEmpty ? availableFaces : plane.first(where: { availableFaces & (1 << $0) != 0 }).map { 1 << $0 } ?? 0
                let firstVertex = mesh.vertices.count
                mesh.cube(.init((w+inflate*2)/16,(h+inflate*2)/16,(d+inflate*2)/16),
                    at:.init((origin.x+size.x/2-pivot.x)/16,(origin.y+size.y/2-pivot.y)/16,(origin.z+size.z/2-pivot.z)/16),
                    material:material,faces:faces,textureUV:rects)
                if cube["rotation"] != nil {
                    let centre = try cube["pivot"].map(vector) ?? SCNVector3(origin.x+size.x/2,origin.y+size.y/2,origin.z+size.z/2)
                    let angles = try vector(cube["rotation"])
                    let transform = SCNNode()
                    transform.position = .init((centre.x-pivot.x)/16,(centre.y-pivot.y)/16,(centre.z-pivot.z)/16)
                    transform.eulerAngles = .init(-angles.x * .pi/180,-angles.y * .pi/180,angles.z * .pi/180)
                    for index in firstVertex..<mesh.vertices.count {
                        let point = mesh.vertices[index], p = transform.position
                        mesh.vertices[index] = transform.convertPosition(.init(point.x-p.x,point.y-p.y,point.z-p.z),to:nil)
                        mesh.normals[index] = transform.convertVector(mesh.normals[index],to:nil)
                    }
                }
            }
            if bone["neverRender"] as? Bool != true { node.geometry = mesh.node("mesh").geometry }
        }
        return root
    }
}

extension Assets {
    private func table(_ name: String) throws -> [String: Any] {
        if let table = tables[name] { return table }
        var table: [String: Any] = [:]
        for pack in resources {
            let path = pack.appendingPathComponent(name)
            guard FileManager.default.fileExists(atPath:path.path) else { continue }
            let data = try Data(contentsOf:path)
            guard data.count <= 8*1024*1024,
                  let object = try JSONSerialization.jsonObject(with:data,options:.json5Allowed) as? [String: Any] else { throw AssetError.model }
            if name == "biomes_client.json" {
                table.merge(object["biomes"] as? [String: Any] ?? [:]) { _,value in value }
            } else if name == "textures/terrain_texture.json" {
                table.merge(object["texture_data"] as? [String: Any] ?? [:]) { _,value in value }
            } else { table.merge(object) { _,value in value } }
        }
        tables[name] = table
        return table
    }

    func water(_ biome: Biome) throws -> UInt32 {
        let names: [Biome:String] = [.swamp:"swampland",.mangrove:"mangrove_swamp",.river:"river",.reef:"warm_ocean",
            .monument:"deep_ocean",.coast:"beach",.desert:"desert",.jungle:"jungle",.snow:"taiga",.ice:"frozen_ocean"]
        let biomes = try table("biomes_client.json")
        let entry = biomes["minecraft:"+(names[biome] ?? "plains")] as? [String:Any]
        let fallback = biomes["default"] as? [String:Any]
        let colour = entry?["water_surface_color"] as? String ?? fallback?["water_surface_color"] as? String ?? "#44AFF5"
        guard colour.count == 7, colour.first == "#", let value = UInt32(colour.dropFirst(),radix:16) else { throw AssetError.model }
        return value
    }

    func tiles(_ name: String, states: [String: String] = [:]) throws -> [SCNMaterial] {
        let key = name+states.keys.sorted().map { "|"+$0+"="+states[$0]! }.joined()
        if let tiles = tilesets[key] { return tiles }
        let tiles = try resolve(name,states:states)
        tilesets[key] = tiles
        return tiles
    }

    func banner(_ name: String, data: [String:Any]) throws -> SCNMaterial {
        if name.contains("illager_captain") { return try texture("textures/entity/banner/banner_illager") }
        let dyes: [(String,UInt32)] = [("black",0x1D1D21),("red",0xB02E26),("green",0x5E7C16),("brown",0x835432),
            ("blue",0x3C44AA),("purple",0x8932B8),("cyan",0x169C9C),("light_gray",0x9D9D97),
            ("gray",0x474F52),("pink",0xF38BAA),("lime",0x80C71F),("yellow",0xFED83D),
            ("light_blue",0x3AB3DA),("magenta",0xC74EBD),("orange",0xF9801D),("white",0xF9FFFE)]
        let base = data["Base"] as? Int ?? dyes.firstIndex { name == $0.0+"_banner" || name == $0.0+"_wall_banner" } ?? 15
        let patterns = data["Patterns"] as? [[String:Any]] ?? []
        guard dyes.indices.contains(base), patterns.count <= 6 else { throw AssetError.model }
        let names = ["b":"base","bl":"square_bottom_left","br":"square_bottom_right","tl":"square_top_left","tr":"square_top_right",
            "bs":"stripe_bottom","ts":"stripe_top","ls":"stripe_left","rs":"stripe_right","cs":"stripe_center","ms":"stripe_middle",
            "drs":"stripe_downright","dls":"stripe_downleft","ss":"small_stripes","cr":"cross","sc":"straight_cross",
            "bt":"triangle_bottom","tt":"triangle_top","bts":"triangles_bottom","tts":"triangles_top",
            "ld":"diagonal_left","rd":"diagonal_right","lud":"diagonal_up_left","rud":"diagonal_up_right",
            "mc":"circle","mr":"rhombus","vh":"half_vertical","hh":"half_horizontal","vhr":"half_vertical_right","hhb":"half_horizontal_bottom",
            "bo":"border","cbo":"curly_border","gra":"gradient","gru":"gradient_up","bri":"bricks","cre":"creeper",
            "sku":"skull","flo":"flower","moj":"mojang","glb":"globe","pig":"piglin","flw":"flow","gus":"guster"]
        var layers = [("base",base)]
        for pattern in patterns {
            guard let code = pattern["Pattern"] as? String, let path = names[code],
                  let dye = pattern["Color"] as? Int, dyes.indices.contains(dye) else { throw AssetError.model }
            layers.append((path,dye))
        }
        let key = "banner-"+layers.map { $0.0+String($0.1) }.joined(separator:"-")
        if let found = materials[key] { return found }
        guard let context = CGContext(data:nil,width:64,height:64,bitsPerComponent:8,bytesPerRow:256,
            space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue) else { throw AssetError.image }
        context.interpolationQuality = .none
        for (path,dye) in layers {
            let layer = try texture("textures/entity/banner/banner_"+path,tint:dyes[dye].1)
            context.draw(layer.diffuse.contents as! CGImage,in:CGRect(x:0,y:0,width:64,height:64))
        }
        guard let image = context.makeImage() else { throw AssetError.image }
        let material = try texture("textures/entity/banner/banner_base").copy() as! SCNMaterial
        material.name = key; material.diffuse.contents = image; materials[key] = material
        return material
    }

    private func resolve(_ name: String, states: [String: String]) throws -> [SCNMaterial] {
        var name = name.replacingOccurrences(of:"minecraft:",with:"")
        if ["wheat","carrots","potatoes","beetroots"].contains(name) {
            let age = min(7,max(0,Int(states["age"] ?? "7") ?? 7))
            let stage = name == "wheat" ? age : name == "beetroots" ? min(3,age) : min(3,age == 7 ? 3 : age/2)
            return Array(repeating:try texture("textures/blocks/"+name+"_stage_\(stage)"),count:6)
        }
        if name.hasPrefix("waxed_") { name = String(name.dropFirst(6)) }
        if name == "planks" { name = (states["variant"] ?? "oak")+"_planks" }
        if name == "wooden_door" { name = "oak_door" }
        if name == "red_mushroom_block" || name == "brown_mushroom_block" {
            let skin = try texture("textures/blocks/mushroom_block_skin_"+(name == "red_mushroom_block" ? "red" : "brown"))
            return [skin,skin,skin,skin,skin,try texture("textures/blocks/mushroom_block_inside")]
        }
        if name == "grass_block" || name == "grass" {
            let side = try texture("textures/blocks/grass_side_carried")
            return [side,side,side,side,try texture("textures/blocks/grass_top",tint:0x91BD59),try texture("textures/blocks/dirt")]
        }
        let woods = ["oak","spruce","birch","jungle","acacia","dark_oak"]
        for wood in woods {
            if name == wood+"_log" || name == "stripped_"+wood+"_log" {
                let stem = wood == "dark_oak" ? "big_oak" : wood
                let prefix = name.hasPrefix("stripped_") ? "stripped_"+wood+"_log" : "log_"+stem
                let side = try texture("textures/blocks/"+prefix)
                let cap = try texture("textures/blocks/"+prefix+"_top")
                var result = Array(repeating:side,count:6)
                let indices = states["axis"] == "x" ? [1,3] : states["axis"] == "z" ? [0,2] : [4,5]
                for index in indices { result[index] = cap }
                return result
            }
            if name == wood+"_leaves" {
                let stem = wood == "dark_oak" ? "big_oak" : wood
                let material = try texture("textures/blocks/leaves_"+stem,tint:wood == "spruce" ? 0x619961 : 0x77AB2F)
                return Array(repeating:material,count:6)
            }
            if name.hasPrefix(wood+"_") && ["planks","stairs","slab","fence","fence_gate","pressure_plate","button"].contains(String(name.dropFirst(wood.count+1))) {
                return Array(repeating:try texture("textures/blocks/planks_"+(wood == "dark_oak" ? "big_oak" : wood)),count:6)
            }
            if name == wood+"_door" {
                let stem = wood == "oak" ? "wood" : wood
                return Array(repeating:try texture("textures/blocks/door_"+stem+(states["half"] == "upper" ? "_upper" : "_lower")),count:6)
            }
        }
        if name.hasSuffix("_bed") { return Array(repeating:try texture("textures/blocks/wool_colored_"+name.replacingOccurrences(of:"_bed",with:"")),count:6) }
        let aliases = ["dirt_path":"grass_path", "cobblestone_stairs":"cobblestone", "mossy_cobblestone_stairs":"mossy_cobblestone",
                       "stone_brick_stairs":"stonebrick", "stone_brick_slab":"stonebrick", "polished_andesite_stairs":"stone_andesite_smooth",
                       "cut_copper_stairs":"cut_copper", "cut_copper_slab":"cut_copper", "tuff_brick_stairs":"tuff_bricks", "tuff_brick_slab":"tuff_bricks", "stone_bricks":"stonebrick", "mossy_stone_bricks":"stonebrick_mossy", "cracked_stone_bricks":"stonebrick_cracked",
                       "chiseled_stone_bricks":"stonebrick_carved", "end_stone_bricks":"end_bricks", "nether_bricks":"nether_brick",
                       "white_stained_glass_pane":"glass", "glass_pane":"glass", "wall_torch":"torch", "terracotta":"hardened_clay",
                       "piston_head":"piston_top_normal", "redstone_wall_torch":"redstone_torch_on", "snow_block":"snow", "repeater":"repeater_off", "comparator":"comparator_off", "mushroom_stem":"mushroom_block_skin_stem", "pink_terracotta":"hardened_clay_stained_pink",
                       "purple_terracotta":"hardened_clay_stained_purple", "orange_terracotta":"hardened_clay_stained_orange",
                       "red_terracotta":"hardened_clay_stained_red", "yellow_terracotta":"hardened_clay_stained_yellow"]
        let mapped = aliases[name] ?? name
        let definition = try table("blocks.json")[mapped] as? [String: Any]
        let source = definition?["textures"]
        let catalog = try table("textures/terrain_texture.json")
        return try ["south","east","north","west","up","down"].map { face in
            let key: String
            if let single = source as? String { key = single }
            else if let faces = source as? [String: String] { key = faces[face] ?? faces["side"] ?? mapped }
            else { key = mapped }
            let entry = catalog[key] as? [String: Any]
            let value = entry?["textures"]
            let path = value as? String ?? (value as? [String])?.first ?? "textures/blocks/"+key
            return try texture(path,tint:name == "mangrove_leaves" ? 0x78A73F : nil)
        }
    }

    func template(_ name: String) throws -> [String: Any] {
        try NBT.read(file("structures/"+name+".nbt",behaviour:true))
    }
}
