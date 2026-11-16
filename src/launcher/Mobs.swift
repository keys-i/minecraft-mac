import AppKit
import CoreText
import ImageIO
import SceneKit

enum Species: String, CaseIterable {
    case pig, cow, sheep, wolf, fox, rabbit, goat, llama, camel, armadillo, frog, creeper, chicken, zombie, ironGolem
    case panda, parrot, ocelot, mooshroom, creaking, turtle, dolphin, squid, axolotl, glowsquid
    case warden, bat, bee, spider, slime, villager, golem
    case piglin, hoglin, strider, blaze, skeleton, ghast, magma, enderman, endermite, shulker
    case illager, vindicator, allay, vex
    case horse, polarBear, witch, guardian, drowned, breeze, bogged, witherSkeleton, piglinBrute, zombifiedPiglin
    case cod, salmon, sniffer, husk, ravager, silverfish, tropical, snowGolem, cat
    case camelHusk, parched, nautilus, zombieNautilus, happyGhast
    case caveSpider, evoker, elderGuardian, pufferfish, stray
    case donkey, mule, phantom, tadpole, traderLlama, trader, wither, zoglin, zombieHorse, zombieVillager, sulfurCube

    var flying: Bool { [.bee, .parrot, .bat, .blaze, .ghast, .allay, .vex, .happyGhast, .phantom, .wither].contains(self) }
    var swimming: Bool { [.dolphin, .squid, .glowsquid, .axolotl, .guardian, .elderGuardian, .cod, .salmon, .tropical, .pufferfish, .nautilus, .zombieNautilus, .tadpole].contains(self) }
    var amphibious: Bool { [.axolotl,.turtle,.drowned,.frog].contains(self) }
    var cube: Bool { [.slime,.magma,.sulfurCube].contains(self) }
    var hostile: Bool {
        [.creeper,.zombie,.warden,.spider,.caveSpider,.slime,.creaking,.piglin,.hoglin,.blaze,.skeleton,.ghast,
         .magma,.enderman,.endermite,.shulker,.illager,.vindicator,.evoker,.vex,.witch,.guardian,.elderGuardian,
         .drowned,.breeze,.bogged,.witherSkeleton,.piglinBrute,.zombifiedPiglin,.husk,.ravager,.silverfish,
         .phantom,.wither,.zoglin,.zombieVillager,.camelHusk,.parched,.zombieNautilus,.stray,.sulfurCube].contains(self)
    }
}

// Prototypes share the installed game's geometry and textures within one scene
// Imported rigs face actor +Z; replace the full Euler vector to avoid decomposed half-turns
final class Mobs {
    struct Motion {
        var speed: Double
        var width: Double
        var height: Double
        var waterSpeed = 0.8
        var interval = 2.0...7.0
        var horizontal = 10.0
        var vertical = 4.0
        var offset = 0.0
        var reselect = false
        var skip: Rig.Skip?
        var scale = 1.0
        var size = 1
    }
    let assets: Assets
    private var models: [String: SCNNode] = [:]
    private var locomotions: [String:Motion] = [:]
    private var clips: [String:Rig.Clip] = [:]
    private let variants = NSMapTable<SCNNode,NSNumber>(keyOptions:.weakMemory,valueOptions:.strongMemory)
    private var classics: [Species:SCNNode] = [:]

    init(assets: Assets) { self.assets = assets }

    // Face the movement actually presented after all route actions for this frame
    static func face(_ actor: SCNNode) {
        var previous = actor.position
        actor.constraints = [SCNTransformConstraint(inWorldSpace:false) { node,transform in
            let point = SCNVector3(transform.m41,transform.m42,transform.m43)
            let dx = point.x-previous.x, dz = point.z-previous.z
            previous = point
            guard hypot(dx,dz)>0.00001 else { return transform }
            var facing = SCNMatrix4MakeRotation(atan2(dx,dz),0,1,0)
            facing = SCNMatrix4Scale(facing,node.scale.x,node.scale.y,node.scale.z)
            facing.m41 = transform.m41; facing.m42 = transform.m42; facing.m43 = transform.m43
            return facing
        }]
    }

    // Native herd bounds describe one spawn attempt, not the habitat's population cap
    func group(_ species: Species, biome: Biome, seed: Int) throws -> Int? {
        guard seed>=0 else { throw AssetError.model }
        let condition: Int
        switch species {
        case .pig,.cow,.axolotl,.bat,.bee,.zombieHorse,.sulfurCube: condition = 0
        case .sheep: condition = biome == .meadow || biome == .cherry ? 1 : 0
        case .horse: condition = biome == .savanna ? 1 : 0
        case .donkey: condition = biome == .meadow ? 2 : biome == .savanna ? 1 : 0
        case .enderman:
            if [.central,.highlands,.midlands,.islands,.barrens,.city].contains(biome) { condition = 3 }
            else if biome == .warped { condition = 2 }
            else if [.wastes,.crimson,.soul,.basalt].contains(biome) { condition = 1 }
            else { condition = 0 }
        default: return nil
        }
        let data: Data
        let ruleName = species == .sulfurCube ? "sulfur_cube" : species == .zombieHorse ? "zombie_horse" : species.rawValue
        do { data = try assets.file("spawn_rules/"+ruleName+".json",behaviour:true) }
        catch AssetError.missing { return nil }
        guard data.count<=2*1024*1024,
              let document = try JSONSerialization.jsonObject(with:data,options:.json5Allowed) as? [String:Any],
              let rule = document["minecraft:spawn_rules"] as? [String:Any],
              let conditions = rule["conditions"] as? [[String:Any]], conditions.indices.contains(condition) else { throw AssetError.model }
        let raw = conditions[condition]["minecraft:herd"]
        let herds = raw as? [[String:Any]] ?? (raw as? [String:Any]).map { [$0] } ?? []
        guard !herds.isEmpty, herds.count<=32 else { throw AssetError.model }
        var bounds: ClosedRange<Int>?
        for herd in herds {
            guard let lower = herd["min_size"] as? NSNumber, let upper = herd["max_size"] as? NSNumber,
                  CFGetTypeID(lower) != CFBooleanGetTypeID(), CFGetTypeID(upper) != CFBooleanGetTypeID(),
                  lower.doubleValue == Double(lower.intValue), upper.doubleValue == Double(upper.intValue),
                  (1...32).contains(lower.intValue), (lower.intValue...32).contains(upper.intValue),
                  bounds == nil || bounds == (lower.intValue...upper.intValue) else { throw AssetError.model }
            bounds = lower.intValue...upper.intValue
        }
        let range = bounds!
        return range.lowerBound+min(range.count-1,Int(Terrain.random(seed,0,seed:261)*Double(range.count)))
    }

    func crown(_ pig: SCNNode) throws {
        guard let head = pig.childNode(withName:"head",recursively:true) else { throw AssetError.model }
        let bounds = head.boundingBox, width = bounds.max.x-bounds.min.x+0.08
        let centre = SCNVector3((bounds.max.x+bounds.min.x)/2,bounds.max.y+0.05,(bounds.max.z+bounds.min.z)/2)
        var mesh = Voxels()
        let gold = try assets.tiles("gold_block")[0]
        for side in [-1.0,1] {
            mesh.cube(.init(width,0.1,0.055),at:.init(centre.x,centre.y,centre.z+side*width/2),material:gold)
            mesh.cube(.init(0.055,0.1,width),at:.init(centre.x+side*width/2,centre.y,centre.z),material:gold)
            for x in [-width/2,0,width/2] {
                mesh.cube(.init(0.075,0.14,0.075),at:.init(centre.x+x,centre.y+0.1,centre.z+side*width/2),material:gold)
            }
            for (index,x) in [-width/3,0,width/3].enumerated() {
                let gem = try assets.tiles(["redstone_block","emerald_block","lapis_block"][index])[0]
                mesh.cube(.init(0.055,0.055,0.065),at:.init(centre.x+x,centre.y,centre.z+side*width/2),material:gem)
            }
        }
        let crown = mesh.node("technoblade-crown"); crown.categoryBitMask = 1
        head.addChildNode(crown)
        var body: SCNNode?
        pig.enumerateChildNodes { node,_ in if node.name?.lowercased() == "body", body == nil { body = node } }
        guard let body else { throw AssetError.model }
        let bodyBounds = body.geometry?.boundingBox ?? body.boundingBox
        let corners = [bodyBounds.min.x,bodyBounds.max.x].flatMap { x in [bodyBounds.min.y,bodyBounds.max.y].flatMap { y in
            [bodyBounds.min.z,bodyBounds.max.z].map { z in body.convertPosition(.init(x,y,z),to:pig) }
        } }
        let left = corners.map(\.x).min()!, right = corners.map(\.x).max()!, top = corners.map(\.y).max()!
        let back = corners.map(\.z).min()!, front = corners.map(\.z).max()!
        let forward = head.convertPosition(.init(0,0,0),to:pig).z >= (back+front)/2 ? 1.0 : -1.0
        let capeWidth = (right-left)*0.95, capeHeight = (front-back)*1.05
        let cape = SCNNode(); cape.name = "technoblade-cape"
        cape.position = .init((left+right)/2,top+0.025,forward>0 ? front-0.05 : back+0.05)
        cape.eulerAngles.x = forward * .pi/2
        pig.addChildNode(cape)
        let cloth = try assets.texture("textures/blocks/wool_colored_red")
        var parent = cape
        var folds: [SCNNode] = []
        for index in 0..<3 {
            var mesh = Voxels()
            mesh.cube(.init(capeWidth,capeHeight/3,1.0/64),at:.init(0,-capeHeight/6,0),material:cloth)
            let fold = mesh.node("cape-fold-\(index)"); fold.categoryBitMask = 1
            if index>0 { fold.position.y = -capeHeight/3 }
            parent.addChildNode(fold)
            folds.append(fold)
            parent = fold
        }
        let logo = assets.data.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("scenery/Technoblade.png")
        if let size = try? logo.resourceValues(forKeys:[.fileSizeKey]).fileSize, size<=1024*1024,
           let source = CGImageSourceCreateWithURL(logo as CFURL,nil), CGImageSourceGetCount(source) == 1,
           let image = CGImageSourceCreateImageAtIndex(source,0,nil), image.width<=1024, image.height<=1024 {
            let material = SCNMaterial(); material.diffuse.contents = image; material.lightingModel = .lambert
            material.diffuse.magnificationFilter = .nearest; material.diffuse.minificationFilter = .nearest
            material.blendMode = .alpha; material.writesToDepthBuffer = false
            let face = SCNPlane(width:capeWidth*0.85,height:capeWidth*0.85*Double(image.height)/Double(image.width))
            face.firstMaterial = material
            let emblem = SCNNode(geometry:face); emblem.name = "technoblade-emblem"; emblem.categoryBitMask = 1
            emblem.position = .init(0,-capeHeight/6,-forward*0.011)
            emblem.eulerAngles.y = forward>0 ? .pi : 0; folds[1].addChildNode(emblem)
        }
        var previous = pig.presentation.worldPosition, last = 0.0, phase = 0.0
        cape.runAction(.repeatForever(.customAction(duration:60) { [weak pig] _,time in
            guard let pig else { return }
            let now = Double(time), dt = max(0.001,now>=last ? now-last : now)
            let point = pig.presentation.worldPosition
            let distance = hypot(point.x-previous.x,point.z-previous.z)
            previous = point; last = now; phase += distance*10
            let speed = min(3,distance/dt)
            for (index,fold) in folds.enumerated() {
                let droop = index == 2 ? -forward*0.22 : 0
                fold.eulerAngles.x = droop+(0.01+speed*0.035)*sin(phase-Double(index)*0.7+now*1.4)
                fold.eulerAngles.z = sin(now*1.8-Double(index)*0.6)*0.015
            }
        }),forKey:"walking-cloth")
    }

    func jockey() throws -> SCNNode {
        let chicken = try make(.chicken), rider = try make(.zombie)
        rider.name = "jockey-rider"; rider.scale = .init(0.5,0.5,0.5)
        rider.position.y = 0.45
        for name in ["rightLeg","leftLeg"] {
            rider.childNode(withName:name,recursively:true)?.eulerAngles.x = -.pi/2
        }
        chicken.addChildNode(rider)
        return chicken
    }

    func make(_ species: Species, biome: Biome? = nil, variant: Int = 0, classic: Bool = false, baby: Bool = false, named: String? = nil) throws -> SCNNode {
        guard variant>=0 else {throw AssetError.model}
        if classic && !baby && [.pig,.cow,.chicken,.wolf].contains(species) {
            if let model = classics[species] { return try self.named(model.clone(),species:species,baby:false,name:named) }
            let data = assets.resources[0].deletingLastPathComponent().deletingLastPathComponent()
            let old = try Assets(data:data,classic:true)
            let model = try old.actor(species.rawValue)
            model.name = "mob-"+species.rawValue
            old.releaseArchives(); classics[species] = model
            return try self.named(model.clone(),species:species,baby:false,name:named)
        }
        let name: String
        switch species {
        case .donkey: name = "donkey_v3"
        case .mule: name = "mule_v3"
        case .traderLlama: name = "trader_llama"
        case .trader: name = "wandering_trader"
        case .zombieHorse: name = "zombie_horse_v3"
        case .zombieVillager: name = "zombie_villager_v2"
        case .sulfurCube: name = "sulfur_cube"
        case .camelHusk: name = "camel_husk"
        case .zombieNautilus: name = "zombie_nautilus"
        case .happyGhast: name = "happy_ghast"
        case .caveSpider: name = "cave_spider"
        case .evoker: name = "evocation_illager"
        case .elderGuardian: name = "elder_guardian"
        case .villager: name = "villager_v2"
        case .snowGolem: name = "snow_golem"
        case .tropical: name = "tropicalfish"
        case .horse: name = "horse_v3"
        case .polarBear: name = "polar_bear"
        case .witherSkeleton: name = "wither_skeleton"
        case .piglinBrute: name = "piglin_brute"
        case .zombifiedPiglin: name = "zombie_pigman"
        case .golem: name = "copper_golem"
        case .ironGolem: name = "iron_golem"
        case .glowsquid: name = "glow_squid"
        case .magma: name = "magma_cube"
        case .illager: name = "pillager"
        default: name = species.rawValue
        }
        let texture: String
        switch species {
        case .sulfurCube: texture = baby || Self.size(species,variant:variant) == 1 ? "small" : "default"
        case .donkey: texture = "donkey"
        case .mule: texture = "mule"
        case .zombieHorse: texture = "zombie"
        case .zombieNautilus: texture = biome == .reef ? "coral" : "default"
        case .panda: texture = ["default","lazy","worried","playful","brown","weak","aggressive"][variant%7]
        case .mooshroom: texture = variant%2 == 0 ? "default" : "brown"
        case .happyGhast: texture = "happy_ghast"
        case .horse: texture = ["base_white","base_creamy","base_chestnut","base_brown","base_black","base_gray","base_darkbrown"][variant%7]
        case .cat: texture = biome == .swamp ? "all_black" : ["white","black","red","siamese","british","calico","persian","ragdoll","tabby","all_black","jellie"][variant%11]
        case .tropical: texture = variant%2 == 0 ? "typeA" : "typeB"
        case .wolf:
            switch biome {
            case .forest: texture = "woods_default"
            case .snow: texture = "ashen_default"
            case .jungle: texture = "rusty_default"
            case .savanna: texture = "spotted_default"
            case .badlands: texture = "striped_default"
            default: texture = ["pale_default","ashen_default","black_default","chestnut_default","rusty_default","snowy_default","spotted_default","striped_default","woods_default"][variant%9]
            }
        case .fox: texture = [.snow,.ice,.peaks].contains(biome) ? "arctic" : "red"
        case .rabbit:
            if named == "Toast" { texture = "toast" }
            else if biome == .desert { texture = "gold" }
            else if [.snow,.ice,.peaks].contains(biome) { texture = ["white","white_splotched"][variant%2] }
            else { texture = ["brown","black","salt"][variant%3] }
        case .llama,.traderLlama: texture = ["creamy","white","brown","gray"][variant%4]
        case .frog: texture = biome == .mangrove ? "warm" : [.snow,.ice,.peaks].contains(biome) ? "cold" : "temperate"
        case .parrot: texture = ["red_blue","green","blue","yellow_blue","grey"][variant%5]
        case .ocelot: texture = "wild"
        case .axolotl: texture = ["lucy","wild","gold","cyan"][variant%4]
        case .pig,.cow,.chicken: texture = [.desert,.savanna,.jungle,.badlands].contains(biome) ? "warm" : [.snow,.peaks,.ice].contains(biome) ? "cold" : "default"
        case .villager,.zombieVillager:
            switch biome {
            case .desert,.badlands: texture = "desert"
            case .jungle: texture = "jungle"
            case .savanna: texture = "savanna"
            case .snow,.ice,.peaks: texture = "snow"
            case .swamp,.mangrove: texture = "swamp"
            default: texture = "plains"
            }
        case .golem: texture = ["default","exposed","weathered"][variant%3]
        case .elderGuardian: texture = "elder"
        case .shulker: texture = "undyed"
        default: texture = "default"
        }
        let model: SCNNode
        var infantScale: Double?
        do { model = try actor(name,texture:texture,label:species.rawValue,variant:variant,baby:baby) }
        catch AssetError.missing(let path) where baby && path == "baby geometry for "+name {
            model = try actor(name,texture:texture,label:species.rawValue,variant:variant)
            infantScale = try infancy(species)
        }
        // Normal puff uses the behaviour's scale rather than a client-entity script
        if species == .pufferfish { model.scale = .init(1.2,1.2,1.2) }
        // Native kitten geometry cancels its behaviour scale through the client script
        if species == .cat && (!baby || infantScale != nil) { model.scale = .init(0.8,0.8,0.8) }
        if species == .villager && (!baby || infantScale != nil) { model.scale = .init(0.9375,0.9375,0.9375) }
        if species == .polarBear {
            guard let entity = try assets.json("entity/polar_bear.entity.json")["minecraft:client_entity"] as? [String:Any],
                  let description = entity["description"] as? [String:Any], let scripts = description["scripts"] as? [String:Any],
                  let expression = scripts["scale"] else {throw AssetError.model}
            let nativeBaby = baby && infantScale == nil
            let scale = try Rig.scale(expression,baby:nativeBaby)*locomotion(species,baby:nativeBaby).scale
            model.scale = .init(scale,scale,scale)
        }
        if !baby {
            if species == .donkey { model.scale = .init(0.87,0.87,0.87) }
            if species == .mule { model.scale = .init(0.92,0.92,0.92) }
            if species == .wither { model.scale = .init(2,2,2) }
        }
        if species == .slime || species == .magma {
            let size = Double(Self.size(species,variant:variant))
            model.scale = .init(size,size,size)
        }
        if let infantScale { model.scale = .init(model.scale.x*infantScale,model.scale.y*infantScale,model.scale.z*infantScale) }
        let result = try self.named(model,species:species,baby:baby,name:named)
        if species.cube {variants.setObject(NSNumber(value:variant),forKey:result)}
        return result
    }

    private func named(_ model: SCNNode, species: Species, baby: Bool, name: String?) throws -> SCNNode {
        if species == .sheep && name == "jeb_" { try fleece(model,baby:baby,colours:Self.dyes) }
        var result = model
        if name == "Dinnerbone" || name == "Grumm" {
            let bounds = model.boundingBox, wrapper = SCNNode()
            wrapper.name = model.name
            model.position.y += (bounds.min.y+bounds.max.y)*model.scale.y+0.1
            model.eulerAngles.z += Double.pi
            wrapper.addChildNode(model)
            result = wrapper
        }
        if let name {
            let font = NSFont(name:"Mojangles",size:16) ?? NSFont(name:"Monocraft",size:16) ?? NSFont.monospacedSystemFont(ofSize:16,weight:.regular)
            let line = CTLineCreateWithAttributedString(NSAttributedString(string:name,attributes:[.font:font,.foregroundColor:NSColor.white]))
            let width = Int(ceil(CTLineGetTypographicBounds(line,nil,nil,nil)))+8
            guard width<=512, let context = CGContext(data:nil,width:width,height:24,bitsPerComponent:8,bytesPerRow:width*4,
                space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue) else { throw AssetError.image }
            context.setFillColor(NSColor.black.withAlphaComponent(0.45).cgColor)
            context.fill(CGRect(x:0,y:0,width:width,height:24)); context.setShouldAntialias(false)
            context.textPosition = .init(x:4,y:5); CTLineDraw(line,context)
            let material = SCNMaterial(); material.diffuse.contents = context.makeImage(); material.lightingModel = .constant
            material.diffuse.magnificationFilter = .nearest; material.diffuse.minificationFilter = .nearest
            material.blendMode = .alpha; material.writesToDepthBuffer = false; material.isDoubleSided = true
            let plane = SCNPlane(width:Double(width)*0.022,height:0.528); plane.firstMaterial = material
            let tag = SCNNode(geometry:plane); tag.name = "nametag-"+name; tag.categoryBitMask = 1
            tag.position.y = result.boundingBox.max.y+0.35
            tag.constraints = [SCNBillboardConstraint()]; result.addChildNode(tag)
        }
        return result
    }

    private static let dyes: [UInt32] = [0xFFFFFF,0xF9801D,0xC74EBD,0x3AB3DA,0xFED83D,0x80C71F,0xF38BAA,0x474F52,
        0x9D9D97,0x169C9C,0x8932B8,0x3C44AA,0x835432,0x5E7C16,0xB02E26,0x1D1D21]

    func pink(_ sheep: SCNNode, baby: Bool = false) throws { try fleece(sheep,baby:baby,colours:[Self.dyes[6]]) }

    private func fleece(_ sheep: SCNNode, baby: Bool, colours: [UInt32]) throws {
        guard sheep.name == "mob-sheep", !colours.isEmpty, colours.count<=16 else { throw AssetError.model }
        let mask = try assets.texture("textures/entity/sheep/sheep"+(baby ? "_baby" : "")).diffuse.contents!
        let values = (colours+[colours[0]]).map { colour in NSValue(scnVector4:.init(
            Double((colour>>16)&255)/255,Double((colour>>8)&255)/255,Double(colour&255)/255,1)) }
        sheep.enumerateChildNodes { node,_ in
            guard let source = node.geometry else { return }
            let mesh = source.copy() as! SCNGeometry
            mesh.materials = source.materials.map { source in
                let material = source.copy() as! SCNMaterial
                material.transparent.contents = mask
                material.transparent.magnificationFilter = .nearest; material.transparent.minificationFilter = .nearest
                material.transparent.mipFilter = .none
                var shaders = material.shaderModifiers ?? [:]
                shaders[.surface] = """
                #pragma arguments
                float4 wool;
                #pragma body
                _surface.diffuse.rgb *= mix(float3(1.0), wool.rgb, _surface.transparent.a);
                _surface.transparent = float4(1.0);
                """
                material.shaderModifiers = shaders
                material.setValue(values[0],forKey:"wool")
                if colours.count>1 {
                    let cycle = CAKeyframeAnimation(keyPath:"wool")
                    cycle.values = values; cycle.duration = 20; cycle.repeatCount = .infinity
                    material.addAnimation(cycle,forKey:"wool")
                }
                return material
            }
            node.geometry = mesh
        }
    }

    func charged() throws -> SCNNode {
        let model = try make(.creeper), aura = try actor("creeper",texture:"charged")
        aura.name = "charged-aura"
        aura.enumerateChildNodes { node,_ in
            guard let source = node.geometry else { return }
            let mesh = source.copy() as! SCNGeometry
            mesh.materials = source.materials.map { source in
                let material = source.copy() as! SCNMaterial
                material.blendMode = .add; material.lightingModel = .constant; material.diffuse.intensity = 0.5
                let scroll = CABasicAnimation(keyPath:"diffuse.contentsTransform")
                scroll.fromValue = NSValue(scnMatrix4:SCNMatrix4Identity)
                scroll.toValue = NSValue(scnMatrix4:SCNMatrix4MakeTranslation(1,1,0))
                scroll.duration = 5; scroll.repeatCount = .infinity
                material.addAnimation(scroll,forKey:"charge")
                return material
            }
            node.geometry = mesh
        }
        model.addChildNode(aura)
        return model
    }

    func skeletonHorse() throws -> SCNNode {
        let model = try actor("skeleton_horse_v3",texture:"skeleton")
        model.enumerateChildNodes { node,_ in
            if let name = node.name, ["Saddle","Bit","Bridle","Rein","Bag","MuleEar"].contains(where:{ name.hasPrefix($0) }) { node.isHidden = true }
        }
        return model
    }

    // Herobrine is a custom cameo built from the owner's Steve skin, not a vanilla mob
    func herobrine() throws -> SCNNode {
        let model = try actor("player")
        model.name = "custom-herobrine"
        guard let head = model.childNode(withName:"head",recursively:true) else { throw AssetError.model }
        let white = SCNMaterial(); white.diffuse.contents = NSColor.white; white.lightingModel = .constant
        var mesh = Voxels()
        for side in [-1.0,1] { mesh.cube(.init(2.0/16,1.0/16,0.002),at:.init(side*2.0/16,3.5/16,-4.01/16),material:white) }
        let eyes = mesh.node("custom-white-eyes"); eyes.categoryBitMask = 1
        head.addChildNode(eyes)
        return model
    }

    func actor(_ name: String, texture: String = "default", label: String? = nil, variant: Int = 0, baby: Bool = false) throws -> SCNNode {
        let variantKey = name == "horse_v3" || name == "villager_v2" ? "-\(variant%5)" : name == "tropicalfish" ? "-\(variant%6)" : ""
        let key = name+"-"+texture+variantKey+(baby ? "-baby" : "")
        if let model = models[key] { return model.clone() }
        let model = try assets.actor(name,texture:texture,variant:variant,baby:baby)
        model.name = "mob-"+(label ?? name)
        let gaze = Rig.gaze(model)
        let weapons = ["skeleton":"bow_standby","stray":"bow_standby","bogged":"bow_standby","parched":"bow_standby",
            "wither_skeleton":"stone_sword","piglin":"crossbow_standby","piglin_brute":"gold_axe",
            "zombie_pigman":"crossbow_standby","pillager":"crossbow_standby"]
        if let weapon = weapons[name], let hand = model.childNode(withName:"leftItem",recursively:true) {
            let item = try assets.item(weapon)
            if weapon == "bow_standby" {
                item.eulerAngles.y = .pi/2
                item.position = .init(0.5/16,-2.5/16,1.0/16)
            } else if weapon == "crossbow_standby" {
                item.eulerAngles = .init(-Double.pi/2,3 * Double.pi/180,-45.75 * Double.pi/180)
                item.position = .init(0.5/16,-0.5/16,-1.5/16)
            } else {
                // The sprite's lower-left grip must meet the hand, not its image centre
                item.pivot = SCNMatrix4MakeTranslation(-3.5*0.75/16,-4.5*0.75/16,0)
                item.eulerAngles = .init(0,Double.pi/2,Double.pi/4)
            }
            if ["skeleton","stray","bogged","parched","wither_skeleton","zombie_pigman"].contains(name) {
                hand.parent?.eulerAngles.x += 18 * .pi/180
            }
            hand.addChildNode(item)
        }
        if name == "vindicator" {
            if let arms = model.childNode(withName:"arms",recursively:true) {
                arms.position.y -= 3.0/16; arms.position.z -= 1.0/16
                arms.eulerAngles.x += 42.97 * .pi/180
            }
            model.enumerateChildNodes { node,_ in
                if ["rightarm","leftarm","rightitem","leftitem"].contains(node.name?.lowercased() ?? "") { node.isHidden = true }
            }
        }
        if name == "bat" { try flap(model) }
        if name == "spider" || name == "cave_spider" { try spider(model) }
        let equine = ["horse_v3","skeleton_horse_v3","zombie_horse_v3","donkey_v3","mule_v3"].contains(name)
        var index = 0
        func animate(_ node: SCNNode) {
            let part = node.name?.lowercased() ?? ""
            if part.contains("tentacle") {
                VoxelAdventure.sway(node,x:0.15,z:0.1,period:4,phase:Double(index)*0.7)
                index += 1
            } else if part.contains("wing") && key != "ender_dragon-default" && key != "bat-default" && key != "phantom-default" {
                if key.hasPrefix("parrot-") {
                    // shortcut: a bounded ambient clock substitutes the game's unpublished wing_flap queries
                    let sign = part == "wing0" ? 1.0 : -1.0
                    node.eulerAngles.z += sign*(5*Double.pi/180+0.5)
                    VoxelAdventure.sway(node,z:sign*0.5,period:1.0/3)
                } else {VoxelAdventure.sway(node,z:0.4,period:key.hasPrefix("bee-") ? 0.3 : 1.2)}
            } else if part.contains("tail") && key != "ender_dragon-default" && key != "phantom-default" && !key.hasPrefix("rabbit-") {
                if key.hasPrefix("parrot-") {
                    node.eulerAngles.x = -Double.pi/3
                    VoxelAdventure.sway(node,x:-17*Double.pi/180,period:360/38.17,phase:Double.pi/2)
                } else {VoxelAdventure.sway(node,y:0.13,period:2.8)}
            } else if part == "body" && key.hasPrefix("parrot-") {
                let base = node.position
                let bounce = SCNAction.customAction(duration:1.0/3) { child,time in
                    let phase = sin(Double(time)*6*Double.pi)
                    let offset = (phase+1)*0.15/16
                    child.position.y = base.y+offset
                }
                node.runAction(.repeatForever(bounce))
            }
        }
        model.enumerateChildNodes { node,_ in animate(node) }
        if let gaze, name != "bat", !equine {VoxelAdventure.sway(gaze,y:0.07,period:7)}
        models[key] = model
        return model.clone()
    }

    private func spider(_ model: SCNNode) throws {
        guard let animations = try assets.json("animations/spider.animation.json")["animations"] as? [String:[String:Any]],
              let pose = animations["animation.spider.default_leg_pose"]?["bones"] as? [String:[String:Any]],
              pose.count == 8 else { throw AssetError.model }
        for (name,tracks) in pose {
            guard let node = model.childNode(withName:name,recursively:true),
                  let values = tracks["rotation"] as? [Any], values.count == 3 else { throw AssetError.model }
            let angles = try values.map { value -> Double in
                let number: Double?
                if let value = value as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID() { number = value.doubleValue }
                else if let value = value as? String, value.hasSuffix(" - this") { number = Double(value.dropLast(7)) }
                else { throw AssetError.model }
                guard let number, number.isFinite, abs(number)<=360 else { throw AssetError.model }
                return number * Double.pi/180
            }
            node.eulerAngles = .init(-angles[0],angles[1],-angles[2])
        }
    }

    private func flap(_ model: SCNNode) throws {
        guard let animations = try assets.json("animations/bat.animation.json")["animations"] as? [String:[String:Any]],
              let flying = animations["animation.bat.flying"], let duration = flying["animation_length"] as? Double,
              duration.isFinite, (0.01...10).contains(duration),
              let bones = flying["bones"] as? [String:[String:Any]], !bones.isEmpty, bones.count <= 32 else { throw AssetError.model }
        for (name,tracks) in bones {
            guard let node = model.childNode(withName:name,recursively:true) else { throw AssetError.model }
            for field in ["rotation","position"] {
                guard let raw = tracks[field] else { continue }
                let frames: [(Double,[Double])]
                if let vector = raw as? [Double] { frames = [(0,vector)] }
                else {
                    guard let values = raw as? [String:[Double]], !values.isEmpty, values.count <= 64 else { throw AssetError.model }
                    frames = try values.map { key,value in
                        guard let time = Double(key), time.isFinite, (0...duration).contains(time) else { throw AssetError.model }
                        return (time,value)
                    }.sorted { $0.0 < $1.0 }
                }
                guard frames.first?.0 == 0 else { throw AssetError.model }
                let rotation = field == "rotation", base = rotation ? node.eulerAngles : node.position
                var steps = [SCNAction](), previous = 0.0
                for (index,frame) in frames.enumerated() {
                    let (time,values) = frame
                    guard values.count == 3, values.allSatisfy({ $0.isFinite && abs($0)<=4096 }),
                          index == 0 || time>previous else { throw AssetError.model }
                    let factor = rotation ? Double.pi/180 : 1.0/16
                    let value = SCNVector3(base.x+values[0]*factor*(rotation ? -1 : 1),
                        base.y+values[1]*factor,base.z+values[2]*factor*(rotation ? -1 : 1))
                    if index == 0 {
                        if rotation { node.eulerAngles = value } else { node.position = value }
                    } else {
                        steps.append(rotation ? .rotateTo(x:value.x,y:value.y,z:value.z,duration:time-previous,usesShortestUnitArc:false)
                            : .move(to:value,duration:time-previous))
                    }
                    previous = time
                }
                if !steps.isEmpty {
                    if previous<duration { steps.append(.wait(duration:duration-previous)) }
                    node.runAction(.repeatForever(.sequence(steps)),forKey:field)
                }
            }
        }
    }

    private func entity(_ species: Species) throws -> [String:Any] {
        let aliases: [Species:String] = [.ironGolem:"iron_golem",.glowsquid:"glow_squid",.magma:"magma_cube",
            .illager:"pillager",.polarBear:"polar_bear",.witherSkeleton:"wither_skeleton",.piglinBrute:"piglin_brute",
            .zombifiedPiglin:"zombie_pigman",.golem:"copper_golem",.tropical:"tropicalfish",.villager:"villager_v2",
            .snowGolem:"snow_golem",.camelHusk:"camel_husk",.zombieNautilus:"zombie_nautilus",.happyGhast:"happy_ghast",
            .caveSpider:"cave_spider",.evoker:"evocation_illager",.elderGuardian:"elder_guardian",.traderLlama:"trader_llama",
            .trader:"wandering_trader",.zombieHorse:"zombie_horse",.zombieVillager:"zombie_villager_v2",.sulfurCube:"sulfur_cube",.cod:"fish"]
        let path = "entities/"+(aliases[species] ?? species.rawValue)+".json"
        let data = try assets.file(path,behaviour:true)
        guard data.count <= 2*1024*1024,
              let object = try JSONSerialization.jsonObject(with:data,options:.json5Allowed) as? [String:Any],
              let entity = object["minecraft:entity"] as? [String:Any] else { throw AssetError.model }
        return entity
    }

    private func infancy(_ species: Species) throws -> Double {
        let definition = try entity(species)
        guard let groups = definition["component_groups"] as? [String:[String:Any]],
              let name = groups.keys.sorted().first(where:{ groups[$0]?["minecraft:is_baby"] != nil }) else {
            throw AssetError.missing("baby component for "+species.rawValue)
        }
        func scale(_ group: [String:Any]?) throws -> Double {
            guard let raw = group?["minecraft:scale"] else { return 1 }
            guard let values = raw as? [String:Any], let value = values["value"] as? NSNumber,
                  CFGetTypeID(value) != CFBooleanGetTypeID(), value.doubleValue.isFinite,
                  (0.01...4).contains(value.doubleValue) else { throw AssetError.model }
            return value.doubleValue
        }
        return try scale(groups[name])/scale(groups[name.replacingOccurrences(of:"baby",with:"adult")])
    }

    enum Activity { case work, gather, celebrate, home, sleep }

    static func activity(at seconds: Double, rain: Double = 0) -> Activity {
        guard seconds.isFinite, rain.isFinite else { return .home }
        // The scenery sky starts at noon, six thousand ticks after sunrise
        let cycle = max(0,seconds).truncatingRemainder(dividingBy:Daylight.period)
        let tick = (cycle/Daylight.period*24000+6000).truncatingRemainder(dividingBy:24000)
        if tick>=12000 { return .sleep }
        if rain>0.2 || tick>=11000 { return .home }
        if tick>=8000 && tick<8120 { return .celebrate }
        if tick>=8000 && tick<10000 { return .gather }
        return .work
    }

    // Routes are authored standing positions; the separate bed position is the lying body's centre
    @discardableResult
    func routine(_ actor: SCNNode, model: SCNNode, route: [SCNVector3], bed: SCNVector3,
                 facing: Double, gather: Int? = nil, root: SCNNode, seed: Int,
                 clock: @escaping () -> Double = { ProcessInfo.processInfo.systemUptime }) throws -> Bool {
        func finite(_ p: SCNVector3) -> Bool { [p.x,p.y,p.z].allSatisfy { $0.isFinite && abs($0)<=4096 } }
        guard (2...64).contains(route.count), route.allSatisfy(finite), finite(bed), facing.isFinite,
              gather == nil || route.indices.contains(gather!) else { throw AssetError.model }
        guard hypot(hypot(actor.position.x-route[0].x,actor.position.z-route[0].z),actor.position.y-route[0].y)<0.01 else { return false }
        let motion = try locomotion(.villager)
        var lengths = [0.0]
        for (a,b) in zip(route,route.dropFirst()) {
            guard Collision.clear(root,from:a,to:b,radius:motion.width/2,height:motion.height) else { return false }
            lengths.append(lengths.last!+hypot(hypot(b.x-a.x,b.z-a.z),b.y-a.y))
        }
        let bedside = route.last!, distance = hypot(hypot(bed.x-bedside.x,bed.z-bedside.z),bed.y-bedside.y)
        guard lengths.last!>0.1, distance<=2.5,
              Collision.clear(root,from:bedside,to:bed,radius:motion.width/2,height:0.4) else { return false }
        let walk = lengths.last!, settle = max(0.6,distance), epoch = assets.started
        let working = atan2(-actor.worldFront.x,-actor.worldFront.z)
        var bodies: [(SCNNode,SCNVector3,SCNVector3)] = [], heads: [(SCNNode,SCNVector3)] = []
        var arms: [(SCNNode,SCNVector3)] = [], legs: [(SCNNode,SCNVector3,Double)] = []
        model.enumerateChildNodes { node,_ in
            switch node.name?.lowercased() {
            case "body": bodies.append((node,node.position,node.eulerAngles))
            case "head-gaze": node.removeAllActions(); heads.append((node,node.eulerAngles))
            case "arms": arms.append((node,node.eulerAngles))
            case "leg0": legs.append((node,node.eulerAngles,1))
            case "leg1": legs.append((node,node.eulerAngles,-1))
            default: break
            }
        }
        guard !bodies.isEmpty else { throw AssetError.model }
        Self.face(actor)
        var cursor = 0.0, previous = 0.0
        actor.removeAction(forKey:"wander")
        actor.runAction(.repeatForever(.customAction(duration:Daylight.period) { node,time in
            let now = Double(time), delta = min(0.1,now>=previous ? now-previous : now)
            previous = now
            let seconds = clock()-epoch
            guard seconds.isFinite, seconds>=0, seconds<Double(Int.max) else { return }
            let phase = Self.activity(at:seconds,rain:Daylight.rain(at:seconds))
            let destination: Double
            switch phase {
            case .work: destination = 0
            case .gather,.celebrate: destination = lengths[gather ?? 0]
            case .home: destination = walk
            case .sleep: destination = walk+settle
            }
            let before = cursor, position = node.position
            cursor += max(-motion.speed*delta,min(motion.speed*delta,destination-cursor))
            let lying = max(0,min(1,(cursor-walk)/settle)), moving = abs(cursor-before)>0.00001
            if cursor<=walk {
                let index = (0..<(route.count-1)).first(where:{ cursor<=lengths[$0+1] }) ?? route.count-2
                let a = route[index], b = route[index+1], t = (cursor-lengths[index])/max(0.001,lengths[index+1]-lengths[index])
                node.position = .init(a.x+(b.x-a.x)*t,a.y+(b.y-a.y)*t,a.z+(b.z-a.z)*t)
                if moving && hypot(node.position.x-position.x,node.position.z-position.z)>0.00001 {
                    node.eulerAngles = .init(0,atan2(node.position.x-position.x,node.position.z-position.z),0)
                }
                if cursor == 0 && !moving {
                    node.eulerAngles = .init(0,working,0)
                }
            } else {
                node.position = .init(bedside.x+(bed.x-bedside.x)*lying,bedside.y+(bed.y-bedside.y)*lying,bedside.z+(bed.z-bedside.z)*lying)
                node.eulerAngles = .init(0,facing,0)
            }
            let celebration = phase == .celebrate && !moving ? sin(seconds*5+Double(seed)) : 0
            for (body,position,rotation) in bodies {
                body.position = .init(position.x,position.y+lying/16+abs(celebration)*0.025,position.z-lying*15/16)
                body.eulerAngles = .init(rotation.x+lying*Double.pi/2,rotation.y,rotation.z)
            }
            for (head,rotation) in heads {
                head.eulerAngles = .init(rotation.x+(1-lying)*sin(seconds*1.4+Double(seed))*0.04,
                    rotation.y+(1-lying)*sin(seconds*0.5+Double(seed))*0.12,rotation.z)
            }
            for (arm,rotation) in arms { arm.eulerAngles.x = rotation.x+celebration*15*Double.pi/180 }
            for (leg,rotation,sign) in legs { leg.eulerAngles.x = rotation.x+(moving && lying == 0 ? sin(cursor*7)*0.5*sign : 0) }
        }),forKey:"routine")
        return true
    }

    func oxidation(_ actor: SCNNode, model: SCNNode, stage: Int, seed: Int,
                   clock: @escaping () -> Double = { ProcessInfo.processInfo.systemUptime }) throws {
        guard (0...3).contains(stage) else { throw AssetError.model }
        let definition = try entity(.golem)
        guard let groups = definition["component_groups"] as? [String:[String:Any]],
              let timer = groups["minecraft:copper_oxidizing"]?["minecraft:timer"] as? [String:Any],
              let interval = timer["time"] as? [Double], interval.count == 2,
              interval.allSatisfy({ $0.isFinite }), interval[0]>=60, interval[1]>=interval[0], interval[1]<=604800,
              let client = try assets.json("entity/copper_golem.entity.json")["minecraft:client_entity"] as? [String:Any],
              let description = client["description"] as? [String:Any], let textures = description["textures"] as? [String:String] else { throw AssetError.model }
        let keys = ["default","exposed","weathered","oxidized"]
        var images: [(CGImage,CGImage)] = []
        var paths: [(String,String)] = []
        for key in keys {
            guard let body = textures[key], let eyes = textures["eyes_"+key] else { throw AssetError.model }
            images.append((try assets.texture(body).diffuse.contents as! CGImage,try assets.texture(eyes).diffuse.contents as! CGImage))
            paths.append((body,eyes))
        }
        var materials: [(SCNMaterial,Bool)] = [], poses: [(SCNNode,SCNMatrix4)] = []
        model.enumerateChildNodes { node,_ in
            poses.append((node,node.transform))
            guard let source = node.geometry else { return }
            let mesh = source.copy() as! SCNGeometry
            mesh.materials = source.materials.map { material in
                let copy = material.copy() as! SCNMaterial
                materials.append((copy,material.name?.contains("_eyes") == true))
                return copy
            }
            node.geometry = mesh
        }
        let waits = (0..<3).map { interval[0]+Terrain.random(seed,$0,seed:271)*(interval[1]-interval[0]) }
        let epoch = assets.started
        var previous = -1, checked = -1
        actor.runAction(.repeatForever(.customAction(duration:Daylight.period) { node,_ in
            let seconds = clock()-epoch
            guard seconds.isFinite, seconds>=0, seconds<Double(Int.max) else { return }
            guard Int(seconds) != checked else { return }
            checked = Int(seconds)
            var current = stage, remaining = seconds
            while current<3 && remaining>=waits[current] { remaining -= waits[current]; current += 1 }
            guard current != previous else { return }
            previous = current
            for (material,eyes) in materials {
                material.diffuse.contents = eyes ? images[current].1 : images[current].0
                material.name = eyes ? paths[current].1 : paths[current].0
            }
            if current == 3 {
                node.removeAction(forKey:"wander")
                for (part,transform) in poses { part.removeAllActions(); part.transform = transform }
                node.removeAction(forKey:"oxidation")
            }
        }),forKey:"oxidation")
    }

    func rig(_ model: SCNNode, species: Species, baby: Bool = false) throws -> Rig {
        func clip(_ file: String, _ name: String) throws -> Rig.Clip {
            if let cached = clips[name] {return cached}
            guard let animations = try assets.json("animations/"+file)["animations"] as? [String:[String:Any]],
                  let definition = animations[name] else {throw AssetError.model}
            let clip = try Rig.Clip(definition); clips[name] = clip
            return clip
        }
        let variant = variants.object(forKey:model)?.intValue ?? 0
        let motion = try locomotion(species,baby:baby,variant:variant)
        if species == .rabbit {
            return try Rig(model,species:species,clip:clip("rabbit.v2.animation.json",baby ? "animation.rabbit.move.baby" : "animation.rabbit.move.v2"),baby:baby)
        }
        if species == .axolotl {
            let prefix = "animation.axolotl."+(baby ? "baby_" : "")
            return try Rig(model,species:species,clip:clip("axolotl.animation.json",prefix+"walk_floor"),
                swim:clip("axolotl.animation.json",prefix+"swim"),wade:clip("axolotl.animation.json",prefix+"walk_floor_underwater"),baby:baby)
        }
        return try Rig(model,species:species,baby:baby,weight:motion.speed/4,size:motion.size)
    }

    static func size(_ species: Species, variant: Int) -> Int {
        if species == .sulfurCube {return variant%100<5 ? 1 : 2}
        return species.cube ? 1 << (variant%3) : 1
    }

    func locomotion(_ species: Species, baby: Bool = false, variant: Int = 0) throws -> Motion {
        guard variant>=0 else {throw AssetError.model}
        let size = species == .sulfurCube && baby ? 1 : Self.size(species,variant:variant)
        let key = species.rawValue+(baby ? "-baby" : "")+(species.cube ? "-\(size)" : "")
        if let found = locomotions[key] { return found }
        let entity: [String:Any]
        do { entity = try self.entity(species) }
        catch AssetError.missing {
            let fallback = Motion(speed:0.8,width:0.6,height:1.8)
            locomotions[key] = fallback
            return fallback
        }
        guard var components = entity["components"] as? [String:Any] else { throw AssetError.model }
        if let raw = entity["component_groups"], !(raw is NSNull) {
            guard let groups = raw as? [String:Any] else { throw AssetError.model }
            let active: [Species:String] = [.enderman:"minecraft:enderman_calm",.armadillo:"minecraft:unrolled",.happyGhast:"minecraft:adult_mobile",
                .sulfurCube:"minecraft:sulfur_cube_medium",.zoglin:"zoglin_adult",.zombieHorse:"minecraft:horse_adult"]
            let infant = groups.keys.sorted().first { (groups[$0] as? [String:Any])?["minecraft:is_baby"] != nil }
            let adult = infant?.replacingOccurrences(of:"baby",with:"adult")
            let names: [String?]
            if species == .slime || species == .magma {
                names = ["minecraft:slime_"+(size == 1 ? "small" : size == 2 ? "medium" : "large"),"minecraft:slime_calm"]
            } else if species == .sulfurCube {
                names = ["minecraft:sulfur_cube_ai","minecraft:sulfur_cube_"+(size == 1 ? "small" : "medium"),"minecraft:sulfur_cube_without_target"]
            } else {names = baby ? [infant] : ["adult","minecraft:adult",adult,active[species]]}
            for name in names.compactMap({ $0 }) {
                if let raw = groups[name] {
                    guard let group = raw as? [String:Any] else { throw AssetError.model }
                    components.merge(group) { _,new in new }
                }
            }
        }
        func number(_ component: String, _ field: String, fallback: Double) throws -> Double {
            guard let raw = components[component] else { return fallback }
            guard let attributes = raw as? [String:Any] else { throw AssetError.model }
            guard let value = attributes[field] else { return fallback }
            if component == "minecraft:movement", let range = value as? [String:Any] {
                guard let lower = range["range_min"] as? NSNumber, let upper = range["range_max"] as? NSNumber,
                      CFGetTypeID(lower) != CFBooleanGetTypeID(), CFGetTypeID(upper) != CFBooleanGetTypeID(),
                      lower.doubleValue.isFinite, upper.doubleValue.isFinite,
                      (0...16).contains(lower.doubleValue), (lower.doubleValue...16).contains(upper.doubleValue) else { throw AssetError.model }
                return (lower.doubleValue+upper.doubleValue)/2
            }
            guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(), number.doubleValue.isFinite else { throw AssetError.model }
            return number.doubleValue
        }
        let movement = try number("minecraft:movement","value",fallback:0.25)
        let multiplier = try number("minecraft:behavior.random_stroll","speed_multiplier",fallback:1)
        let width = try number("minecraft:collision_box","width",fallback:0.6)
        let height = try number("minecraft:collision_box","height",fallback:1.8)
        let scale = try number("minecraft:scale","value",fallback:1)
        guard (0...16).contains(movement), (0...16).contains(multiplier),
              (0.01...16).contains(width), (0.01...16).contains(height), (0.01...16).contains(scale) else { throw AssetError.model }
        // shortcut: the bat's 20-tick visual speed is approximate; float_wander does not publish a world-speed conversion
        var result = Motion(speed:min(2,movement*multiplier*(species == .bat ? 20 : 4)),width:width*scale,height:height*scale)
        result.scale = scale; result.size = size
        if species == .rabbit {
            guard let jump = components["minecraft:jump.dynamic"] as? [String:Any],
                  let skip = jump["regular_skip_data"] as? [String:Any] else {throw AssetError.model}
            func value(_ name: String, range: ClosedRange<Double>) throws -> Double {
                guard let value = skip[name] as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID(),
                      value.doubleValue.isFinite, range.contains(value.doubleValue) else {throw AssetError.model}
                return value.doubleValue
            }
            result.skip = try Rig.Skip(height:value("height",range:0.01...2),duration:value("animation_duration",range:1...100)/20,
                delay:value("jump_delay",range:0...100)/20,distance:value("distance_scale",range:0.01...4))
        }
        if species.cube {
            guard let jump = components["minecraft:movement.jump"] as? [String:Any],
                  let delay = jump["jump_delay"] as? [NSNumber], delay.count == 2,
                  delay.allSatisfy({CFGetTypeID($0) != CFBooleanGetTypeID() && $0.doubleValue.isFinite && (0...10).contains($0.doubleValue)}),
                  delay[0].doubleValue<=delay[1].doubleValue else {throw AssetError.model}
            // shortcut: native JSON omits jump power, so scenery uses the existing 20 m/s² gravity and a size-bounded arc
            let height = min(1,max(0.3,result.height*0.45))
            result.skip = Rig.Skip(height:height,duration:sqrt(8*height/20),delay:(delay[0].doubleValue+delay[1].doubleValue)/2,
                distance:1,takeoff:0,landing:1,variation:(delay[1].doubleValue-delay[0].doubleValue)/2)
        }
        let underwater = try number("minecraft:underwater_movement","value",fallback:movement)
        guard (0...16).contains(underwater) else {throw AssetError.model}
        result.waterSpeed = min(2,underwater*4)
        let floating = "minecraft:behavior.float_wander", hovering = "minecraft:behavior.random_hover"
        if let raw = components[floating] {
            guard let goal = raw as? [String:Any] else {throw AssetError.model}
            if let raw = goal["float_duration"] {
                guard let range = raw as? [NSNumber], range.count == 2,
                      range.allSatisfy({CFGetTypeID($0) != CFBooleanGetTypeID() && $0.doubleValue.isFinite && (0.05...60).contains($0.doubleValue)}),
                      range[1].doubleValue>=range[0].doubleValue else {throw AssetError.model}
                result.interval = range[0].doubleValue...range[1].doubleValue
            }
            result.horizontal = try number(floating,"xz_dist",fallback:result.horizontal)
            result.vertical = try number(floating,"y_dist",fallback:result.vertical)
            result.offset = try number(floating,"y_offset",fallback:result.offset)
            if let raw = goal["random_reselect"] {
                guard let value = raw as? NSNumber, CFGetTypeID(value) == CFBooleanGetTypeID() else {throw AssetError.model}
                result.reselect = value.boolValue
            }
        }
        if components[hovering] != nil {
            let interval = try number(hovering,"interval",fallback:1)
            guard (0.05...60).contains(interval) else {throw AssetError.model}
            result.interval = interval...interval
            result.horizontal = try number(hovering,"xz_dist",fallback:result.horizontal)
            result.vertical = try number(hovering,"y_dist",fallback:result.vertical)
            result.offset = try number(hovering,"y_offset",fallback:result.offset)
            result.reselect = true
        }
        guard (0.1...32).contains(result.horizontal), (0.1...32).contains(result.vertical), abs(result.offset)<=32 else {throw AssetError.model}
        locomotions[key] = result
        return result
    }

    static func legSign(_ name: String) -> Double {
        if let number = name.last?.wholeNumberValue {return [0,3].contains(number%4) ? 1 : -1}
        if let horse = ["legbl":-28.6/45.8,"legbr":28.6/45.8,"legfl":1,"legfr":-1][name] {return horse}
        let side = name.contains("left") ? 1.0 : -1.0
        return side * (["hind","back","rear"].contains(where:name.contains) ? -1 : 1)
    }

    static func pose(_ legs: [(SCNNode,SCNVector3,Double)], species: Species, distance: Double) {
        for (leg,base,sign) in legs {
            if [.spider,.caveSpider].contains(species), let index = leg.name?.last?.wholeNumberValue {
                let phase = Double(index/2)*Double.pi/2, side = index%2 == 0 ? 1.0 : -1
                leg.eulerAngles = .init(base.x,base.y-side*abs(cos(distance*76.34*Double.pi/180+phase))*22.92*Double.pi/180,
                    base.z-side*abs(sin(distance*38.17*Double.pi/180+phase))*22.92*Double.pi/180)
            } else {leg.eulerAngles = .init(base.x+sin(distance*7)*(species == .enderman ? 0.35 : 0.5)*sign,base.y,base.z)}
        }
    }

    // shortcut: original dimensions and calm speed guide scenery routes, use the game engine for full behaviour
    func wander(_ actor: SCNNode, model: SCNNode, species: Species, area: Biome, seed: Int, baby: Bool = false,
                root: SCNNode, ground: ((Double,Double) -> Double)? = nil, point: @escaping (Double,Double) -> SCNVector3) throws {
        let variant = variants.object(forKey:model)?.intValue ?? 0
        let terrain = Terrain(biome:area), origin = actor.position, motion = try locomotion(species,baby:baby,variant:variant)
        let height = model.childNode(withName:"jockey-rider",recursively:true) == nil ? motion.height : max(1.5,motion.height)
        guard motion.speed > 0 else { return }
        Self.face(actor)
        if species == .bat {
            let duration = [motion.interval.lowerBound,motion.interval.upperBound], horizontal = motion.horizontal
            let vertical = motion.vertical, offset = motion.offset, reselect = motion.reselect
            var target = origin, previous = 0.0, elapsed = 0.0, nextChoice = 0.0, choice = 0
            actor.runAction(.repeatForever(.customAction(duration:60) { [weak root] node,time in
                guard let root else { return }
                let now = Double(time), delta = min(0.1,now>=previous ? now-previous : now)
                previous = now; elapsed += delta
                let near = hypot(hypot(node.position.x-target.x,node.position.z-target.z),node.position.y-target.y)<0.15
                if elapsed>=nextChoice && (reselect || near) {
                    for _ in 0..<4 {
                        choice += 1
                        let x = origin.x+(Terrain.random(seed,choice,seed:211)-0.5)*horizontal*2
                        let z = origin.z+(Terrain.random(seed,choice,seed:212)-0.5)*horizontal*2
                        let candidate = SCNVector3(x,origin.y+offset+(Terrain.random(seed,choice,seed:213)-0.5)*vertical*2,z)
                        if Collision.clear(root,from:node.position,to:candidate,radius:motion.width/2,height:height+0.2) {
                            target = candidate; break
                        }
                    }
                    nextChoice = elapsed+duration[0]+Terrain.random(seed,choice,seed:214)*(duration[1]-duration[0])
                }
                let start = node.position, dx = target.x-start.x, dy = target.y-start.y, dz = target.z-start.z
                let distance = sqrt(dx*dx+dy*dy+dz*dz)
                guard distance>0.001 else { return }
                let step = min(1,delta*motion.speed/distance)
                node.position = .init(start.x+dx*step,start.y+dy*step,start.z+dz*step)
                node.eulerAngles = .init(0,atan2(dx,dz),0)
            }),forKey:"wander")
            return
        }
        let rig = try rig(model,species:species,baby:baby)
        if let gaze = Rig.gaze(model), ![.horse,.donkey,.mule,.zombieHorse].contains(species) {
            gaze.removeAllActions()
            VoxelAdventure.sway(gaze,y:0.16,period:7+Double(seed%7),phase:Double(seed)*1.7)
        }
        if let skip = motion.skip {
            var previous = 0.0, wait = 0.0, choice = 0, target: SCNVector3?, hop: Rig.Hop?
            var time = 0.0, distance = 0.0, falling = false, velocity = 0.0
            actor.runAction(.repeatForever(.customAction(duration:60) { [weak root] node,elapsed in
                guard let root else {return}
                let now = Double(elapsed), dt = min(0.1,max(0,now>=previous ? now-previous : now)); previous = now
                wait -= dt
                if falling {
                    velocity = max(-12,velocity-dt*20)
                    let floor = point(node.position.x,node.position.z), start = node.position
                    let next = SCNVector3(start.x,max(floor.y,start.y+velocity*dt),start.z)
                    node.position = Collision.move(root,from:start,to:next,radius:motion.width/2,height:height)
                    if abs(node.position.y-floor.y)<0.05 {falling = false; velocity = 0}
                    rig.idle(); return
                }
                if let current = hop {
                    time += dt
                    let phase = min(1,time/skip.duration), start = node.position, next = current.point(phase)
                    let moved = Collision.move(root,from:start,to:next,radius:motion.width/2,height:height)
                    let dx = moved.x-start.x, dz = moved.z-start.z, travelled = hypot(dx,dz)
                    node.position = moved; distance += travelled
                    if travelled>0.00001 {node.eulerAngles = .init(0,atan2(dx,dz),0)}
                    rig.apply(distance:distance,phase:phase)
                    if hypot(hypot(moved.x-next.x,moved.z-next.z),moved.y-next.y)>0.001 {
                        hop = nil; target = nil; falling = true; velocity = 0; wait = skip.pause(Terrain.random(seed,choice,seed:88)); rig.idle()
                    } else if phase>=1 {hop = nil; wait = skip.pause(Terrain.random(seed,choice,seed:88)); rig.idle()}
                    return
                }
                guard wait<=0 else {rig.idle(); return}
                if target.map({hypot($0.x-node.position.x,$0.z-node.position.z)<0.15}) ?? true {
                    target = nil
                    for _ in 0..<8 {
                        choice += 1
                        let angle = Terrain.random(seed,choice,seed:85)*Double.pi*2
                        let span = 1+Terrain.random(seed,choice,seed:86)*4
                        let candidate = point(origin.x+cos(angle)*span,origin.z+sin(angle)*span)
                        if Self.walkable(from:node.position,to:candidate,species:species,terrain:terrain,ground:ground) {target = candidate; break}
                    }
                }
                guard let goal = target else {wait = skip.pause(Terrain.random(seed,choice,seed:88)); rig.idle(); return}
                let start = node.position, dx = goal.x-start.x, dz = goal.z-start.z, length = hypot(dx,dz)
                guard length>0.001 else {target = nil; return}
                let span = min(length,motion.speed*skip.duration*skip.distance)
                let landing = point(start.x+dx/length*span,start.z+dz/length*span)
                let next = Rig.Hop(start:start,end:landing,skip:skip)
                guard next.clear({Collision.clear(root,from:$0,to:$1,radius:motion.width/2,height:height)}) else {
                    target = nil; wait = skip.pause(Terrain.random(seed,choice,seed:88)); rig.idle(); return
                }
                hop = next; time = 0; rig.apply(distance:distance,phase:0)
            }),forKey:"wander")
            return
        }
        var steps: [SCNAction] = [], start = origin, visited = [origin], travelled = 0.0
        for index in 0..<12 {
            var end = index >= 6 ? visited[11-index] : start
            for attempt in 0..<(index < 6 ? 12 : 0) {
                let angle = Terrain.random(seed,index*12+attempt,seed:85)*2 * .pi
                let distance = 1+Terrain.random(seed,index*12+attempt,seed:86)*4
                let candidate = point(origin.x+cos(angle)*distance,origin.z+sin(angle)*distance)
                if Self.walkable(from:start,to:candidate,species:species,terrain:terrain,ground:ground)
                    && Collision.clear(root,from:start,to:candidate,radius:motion.width/2,height:height) { end = candidate; break }
            }
            if index < 6 { visited.append(end) }
            let length = sqrt(pow(end.x-start.x,2)+pow(end.y-start.y,2)+pow(end.z-start.z,2))
            if !species.flying { steps.append(.wait(duration:1.5+Terrain.random(seed,index,seed:87)*4)) }
            if length>0.1 {
                let heading = atan2(end.x-start.x,end.z-start.z)
                if !species.flying { steps.append(.rotateTo(x:0,y:heading,z:0,duration:0.35,usesShortestUnitArc:true)) }
                let a = start, b = end, duration = length/motion.speed, distance = travelled
                let hopping = [.frog,.slime,.magma,.sulfurCube].contains(species)
                let travel = SCNAction.customAction(duration:duration) { node,time in
                    let t = min(1,Double(time)/duration)
                    node.eulerAngles = .init(0,heading,0)
                    node.position = .init(a.x+(b.x-a.x)*t,a.y+(b.y-a.y)*t,a.z+(b.z-a.z)*t)
                    if species.swimming {rig.swimming(distance:distance+length*t,time:Double(time),speed:motion.waterSpeed/4)}
                    else if !species.flying {rig.apply(distance:distance+length*t,time:Double(time))}
                    if hopping { node.position.y += abs(sin(Double(time)*7))*(species == .slime || species == .magma ? 0.65 : 0.3) }
                    if species.swimming || species.flying { node.position.y += sin(Double(time)*2+Double(seed))*0.12 }
                }
                steps.append(travel)
                steps.append(.run { _ in rig.idle() })
                travelled += length
            }
            if species == .sheep, let head = model.childNode(withName:"head",recursively:true) {
                let base = head.eulerAngles.x
                steps.append(.customAction(duration:3) { _,time in head.eulerAngles.x = base+sin(Double(time)/3 * .pi)*0.8 })
            }
            if length <= 0.1 {
                steps.append(.rotateBy(x:0,y:0.3,z:0,duration:1.2))
                steps.append(.rotateBy(x:0,y:-0.3,z:0,duration:1.2))
            }
            start = end
        }
        actor.runAction(.repeatForever(.sequence(steps)),forKey:"wander")
    }

    static func classicChance(daylight: Double) -> Double { 0.10+0.05*(1-min(1,max(0,daylight))) }

    static func walkable(from start: SCNVector3, to end: SCNVector3, species: Species, terrain: Terrain,
                         ground sample: ((Double,Double) -> Double)? = nil) -> Bool {
        for index in 1...8 {
            let t = Double(index)/8, x = start.x+(end.x-start.x)*t, z = start.z+(end.z-start.z)*t
            let ground = sample?(x.rounded(),z.rounded()) ?? terrain.height(x.rounded(),z.rounded())
            if species.swimming {
                if ground >= min(start.y,end.y)-0.5 { return false }
            } else if !species.flying && species != .strider {
                let bridge = [.witherSkeleton].contains(species)
                if terrain.biome.passage == nil && ground < 0.9 && species != .drowned || !bridge && abs(ground-start.y)>1 { return false }
            }
        }
        return true
    }
}
