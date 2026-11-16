import SceneKit

// Native numeric tracks own their joints; attention rotates a separate pivot
final class Rig {
    // Calm setup accepts only constant arithmetic and these named initial guardian values
    private struct Constant {
        let bytes: [UInt8]
        var cursor = 0
        var depth = 0

        init(_ expression: String, guardian: Bool) throws {
            var source = expression.lowercased().filter {!$0.isWhitespace}
            guard source.utf8.count<=256 else {throw AssetError.model}
            if source == "query.is_pregnant?1.0:0.0" {source = "0"}
            if guardian {
                for (name,value) in [("query.life_time","0"),("variable.spike_extension","0.55"),
                                     ("variable.spike_shake","0"),("variable.tail_base_angle","0"),
                                     ("query.eye_target_x_rotation","0"),("query.eye_target_y_rotation","0")] {
                    source = source.replacingOccurrences(of:name,with:value)
                }
            }
            bytes = Array(source.utf8)
        }

        mutating func expression() throws -> Double {
            var value = try product()
            while cursor<bytes.count && [43,45].contains(bytes[cursor]) {
                let sign = bytes[cursor]; cursor += 1
                let rhs = try product(); value += sign == 43 ? rhs : -rhs
            }
            return value
        }

        mutating func product() throws -> Double {
            var value = try atom()
            while cursor<bytes.count && [42,47].contains(bytes[cursor]) {
                let operation = bytes[cursor]; cursor += 1
                let rhs = try atom()
                guard operation != 47 || rhs != 0 else {throw AssetError.model}
                value = operation == 42 ? value*rhs : value/rhs
            }
            return value
        }

        mutating func atom() throws -> Double {
            guard cursor<bytes.count, depth<16 else {throw AssetError.model}
            depth += 1; defer {depth -= 1}
            let token = bytes[cursor]
            if token == 43 || token == 45 {cursor += 1; return try (token == 45 ? -1.0 : 1.0)*atom()}
            let cosine = Array("math.cos(".utf8)
            let isCosine = bytes[cursor...].starts(with:cosine)
            if isCosine || token == 40 {
                cursor += isCosine ? cosine.count : 1
                let value = try expression()
                guard cursor<bytes.count, bytes[cursor] == 41 else {throw AssetError.model}
                cursor += 1
                return isCosine ? cos(value*Double.pi/180) : value
            }
            let start = cursor
            while cursor<bytes.count && ((48...57).contains(bytes[cursor]) || bytes[cursor] == 46) {cursor += 1}
            guard start<cursor, let value = Double(String(decoding:bytes[start..<cursor],as:UTF8.self)), value.isFinite else {throw AssetError.model}
            return value
        }
    }

    private static func component(_ value: Any, guardian: Bool) throws -> (value:Double,reset:Bool) {
        if let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() {
            guard number.doubleValue.isFinite, abs(number.doubleValue)<=4096 else {throw AssetError.model}
            return (number.doubleValue,false)
        }
        guard let raw = value as? String else {throw AssetError.model}
        var source = raw.filter {!$0.isWhitespace}
        let reset = source.hasSuffix("-this")
        if reset {source = String(source.dropLast(5)); if source.isEmpty {source = "0"}}
        var parser = try Constant(source,guardian:guardian)
        let result = try parser.expression()
        guard parser.cursor == parser.bytes.count, result.isFinite, abs(result)<=4096 else {throw AssetError.model}
        return (result,reset)
    }

    static func scale(_ value: Any, baby: Bool) throws -> Double {
        let expression: String
        if let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() {expression = number.stringValue}
        else if let raw = value as? String {
            let source = raw.filter {!$0.isWhitespace}
            if source.hasPrefix("query.is_baby?") {
                let choices = source.dropFirst("query.is_baby?".count).split(separator:":",omittingEmptySubsequences:false)
                guard choices.count == 2 else {throw AssetError.model}
                expression = String(choices[baby ? 0 : 1])
            } else {expression = source}
        } else {throw AssetError.model}
        var parser = try Constant(expression,guardian:false)
        let scale = try parser.expression()
        guard parser.cursor == parser.bytes.count, scale.isFinite, (0.01...16).contains(scale) else {throw AssetError.model}
        return scale
    }

    // Reset channels replace animated values, while the importer's inverse binds remain intact
    static func setup(_ tracks: [String:[String:Any]], model: SCNNode, definition: [String:Any], guardian: Bool = false) throws {
        guard let bones = definition["bones"] as? [[String:Any]], !bones.isEmpty, bones.count<=512, tracks.count<=64 else {throw AssetError.model}
        func vector(_ value: Any?) throws -> SCNVector3 {
            guard let value else {return SCNVector3Zero}
            guard let values = value as? [NSNumber], values.count == 3,
                  values.allSatisfy({CFGetTypeID($0) != CFBooleanGetTypeID() && $0.doubleValue.isFinite && abs($0.doubleValue)<=4096}) else {throw AssetError.model}
            return .init(values[0].doubleValue,values[1].doubleValue,values[2].doubleValue)
        }
        func rotation(_ angles: SCNVector3) -> simd_float4x4 {
            let pose = SCNNode(), radians = Double.pi/180
            pose.eulerAngles = .init(-angles.x*radians,angles.y*radians,-angles.z*radians)
            return pose.simdTransform
        }
        var definitions: [String:[String:Any]] = [:], bases: [String:simd_float4x4] = [:], nodes: [String:SCNNode] = [:]
        model.enumerateChildNodes { node,_ in if let name = node.name {nodes[name.lowercased()] = node} }
        for bone in bones {
            guard let name = bone["name"] as? String, definitions[name.lowercased()] == nil else {throw AssetError.model}
            let key = name.lowercased(), pivot = try vector(bone["pivot"]), bind = try vector(bone["bind_pose_rotation"])
            var transform = rotation(bind); transform.columns.3 = .init(Float(pivot.x/16),Float(pivot.y/16),Float(pivot.z/16),1)
            definitions[key] = bone; bases[key] = transform
        }
        for (name,fields) in tracks {
            let key = name.lowercased()
            guard let bone = definitions[key], let node = nodes[key], let own = bases[key] else {throw AssetError.model}
            let parent = (bone["parent"] as? String)?.lowercased()
            guard parent == nil || bases[parent!] != nil else {throw AssetError.model}
            let bind = simd_inverse(parent.flatMap {bases[$0]} ?? matrix_identity_float4x4)*own
            if let raw = fields["rotation"] {
                guard let values = raw as? [Any], values.count == 3 else {throw AssetError.model}
                let base = try vector(bone["rotation"]), original = [base.x,base.y,base.z]
                let angles = try zip(original,values).map { base,value in
                    let channel = try component(value,guardian:guardian)
                    return channel.reset ? channel.value : base+channel.value
                }
                let position = node.position
                node.simdTransform = bind*rotation(.init(angles[0],angles[1],angles[2]))
                node.position = position
            }
            if let raw = fields["position"] {
                guard let values = raw as? [Any], values.count == 3 else {throw AssetError.model}
                let base = bind.columns.3, original = [Double(base.x),Double(base.y),Double(base.z)]
                let position = try values.enumerated().map { axis,value in
                    let channel = try component(value,guardian:guardian)
                    return channel.reset ? (channel.value+(axis == 1 && parent == nil ? 24 : 0))/16 : original[axis]+channel.value/16
                }
                node.position = .init(position[0],position[1],position[2])
            }
            if let raw = fields["scale"] {
                let scale = try component(raw,guardian:guardian).value
                guard (0...16).contains(scale) else {throw AssetError.model}
                node.isHidden = scale == 0
                if scale>0 {node.scale = .init(scale,scale,scale)}
            }
        }
    }

    static func rest(_ model: SCNNode, definition: [String:Any], name: String, baby: Bool, assets: Assets) throws {
        let source: (String,[String],Bool)
        switch name {
        case "wolf" where !baby: source = ("wolf.animations.json",["animation.wolf.setup"],false)
        case "parrot": source = ("parrot.animation.json",["animation.parrot.base"],false)
        case "guardian","elder_guardian": source = ("guardian.animation.json",["animation.guardian.setup","animation.guardian.spikes","animation.guardian.swim","animation.guardian.move_eye"],true)
        case "witch": source = ("villager.animation.json",["animation.villager.general"],false)
        case "evocation_illager": source = ("evoker.animation.json",["animation.evoker.general"],false)
        case "turtle": source = ("turtle.animations.json",["animation.turtle.general"],false)
        default: return
        }
        guard let animations = try assets.json("animations/"+source.0)["animations"] as? [String:[String:Any]] else {throw AssetError.model}
        for animation in source.1 {
            guard var tracks = animations[animation]?["bones"] as? [String:[String:Any]] else {throw AssetError.model}
            // The baby turtle keeps the general controller but has no pregnancy bone
            if name == "turtle" && baby {tracks.removeValue(forKey:"eggbelly")}
            try setup(tracks,model:model,definition:definition,guardian:source.2)
        }
    }

    struct Frame {
        let time: Double
        let before: SCNVector3
        let after: SCNVector3
        let curved: Bool
    }

    struct Channel {
        let frames: [Frame]

        init(_ value: Any, duration: Double) throws {
            func vector(_ value: Any?) throws -> SCNVector3 {
                guard let numbers = value as? [NSNumber], numbers.count == 3,
                      numbers.allSatisfy({ CFGetTypeID($0) != CFBooleanGetTypeID() && $0.doubleValue.isFinite && abs($0.doubleValue)<=4096 }) else { throw AssetError.model }
                return .init(numbers[0].doubleValue,numbers[1].doubleValue,numbers[2].doubleValue)
            }
            if value is [NSNumber] {
                let v = try vector(value)
                frames = [Frame(time:0,before:v,after:v,curved:false)]
            } else {
                guard let values = value as? [String:Any], !values.isEmpty, values.count<=128 else {throw AssetError.model}
                frames = try values.map { key,value in
                    guard let time = Double(key), time.isFinite, (0...duration).contains(time) else {throw AssetError.model}
                    if let keyframe = value as? [String:Any] {
                        guard keyframe["lerp_mode"] == nil || ["linear","catmullrom"].contains(keyframe["lerp_mode"] as? String ?? "") else {throw AssetError.model}
                        return try Frame(time:time,before:vector(keyframe["pre"] ?? keyframe["post"]),
                            after:vector(keyframe["post"] ?? keyframe["pre"]),curved:keyframe["lerp_mode"] as? String == "catmullrom")
                    }
                    let v = try vector(value)
                    return Frame(time:time,before:v,after:v,curved:false)
                }.sorted { $0.time<$1.time }
                guard frames.first?.time == 0, zip(frames,frames.dropFirst()).allSatisfy({ $0.0.time<$0.1.time }) else {throw AssetError.model}
            }
        }

        func sample(_ time: Double) -> SCNVector3 {
            guard let index = frames.indices.dropFirst().first(where:{time<frames[$0].time}) else {return frames.last!.after}
            let a = frames[index-1], b = frames[index], t = max(0,(time-a.time)/(b.time-a.time))
            func component(_ p0: Double, _ p1: Double, _ p2: Double, _ p3: Double) -> Double {
                if !a.curved && !b.curved {return p1+(p2-p1)*t}
                return 0.5*((2*p1)+(-p0+p2)*t+(2*p0-5*p1+4*p2-p3)*t*t+(-p0+3*p1-3*p2+p3)*t*t*t)
            }
            let previous = index>1 ? frames[index-2].after : a.after
            let next = index+1<frames.count ? frames[index+1].before : b.before
            return .init(component(previous.x,a.after.x,b.before.x,next.x),component(previous.y,a.after.y,b.before.y,next.y),
                component(previous.z,a.after.z,b.before.z,next.z))
        }
    }

    struct Clip {
        struct Bone {
            let name: String
            let rotation: Channel?
            let position: Channel?
        }
        let duration: Double
        let bones: [Bone]

        init(_ value: [String:Any]) throws {
            guard let length = value["animation_length"] as? NSNumber, CFGetTypeID(length) != CFBooleanGetTypeID(),
                  length.doubleValue.isFinite, (0.05...10).contains(length.doubleValue),
                  let bones = value["bones"] as? [String:[String:Any]], !bones.isEmpty, bones.count<=32 else {throw AssetError.model}
            let duration = length.doubleValue
            self.duration = duration
            self.bones = try bones.keys.sorted().map { name in
                let fields = bones[name]!
                guard fields["scale"] == nil,
                      fields["relative_to"] == nil || (fields["relative_to"] as? [String:String]) == ["rotation":"entity"] else {throw AssetError.model}
                return try Bone(name:name,rotation:fields["rotation"].map {try Channel($0,duration:duration)},
                    position:fields["position"].map {try Channel($0,duration:duration)})
            }
        }
    }

    struct Skip {
        let height: Double
        let duration: Double
        let delay: Double
        let distance: Double
    }

    struct Hop {
        let start: SCNVector3
        let end: SCNVector3
        let skip: Skip

        func point(_ phase: Double) -> SCNVector3 {
            // Native rabbit tracks crouch before takeoff and extend through landing
            let t = min(1,max(0,(phase-1.0/6)/(8.0/9-1.0/6)))
            return .init(start.x+(end.x-start.x)*t,start.y+(end.y-start.y)*t+4*skip.height*t*(1-t),start.z+(end.z-start.z)*t)
        }

        func clear(_ sweep: (SCNVector3,SCNVector3) -> Bool) -> Bool {
            let steps = max(16,Int(ceil(hypot(hypot(end.x-start.x,end.z-start.z),end.y-start.y)/0.1)))
            var previous = start
            for frame in 1...steps {
                let next = point(Double(frame)/Double(steps))
                if !sweep(previous,next) {return false}
                previous = next
            }
            return true
        }
    }

    private struct Joint {
        let node: SCNNode
        let rotation: SCNVector3
        let position: SCNVector3
        let track: Clip.Bone
    }
    private let species: Species
    private let clip: Clip?
    private let joints: [Joint]
    private let weight: Double
    private var resting = true
    let legs: [(SCNNode,SCNVector3,Double)]

    init(_ model: SCNNode, species: Species, clip: Clip? = nil, weight: Double = 1) throws {
        self.species = species; self.clip = clip; self.weight = weight
        legs = clip == nil ? Self.legs(model) : []
        joints = try clip?.bones.map { track in
            guard let node = model.childNode(withName:track.name,recursively:true) else {throw AssetError.model}
            node.removeAllActions()
            return Joint(node:node,rotation:node.eulerAngles,position:node.position,track:track)
        } ?? []
    }

    static func legs(_ model: SCNNode) -> [(SCNNode,SCNVector3,Double)] {
        var legs: [(SCNNode,SCNVector3,Double)] = []
        model.enumerateChildNodes { node,_ in
            let name = node.name?.lowercased() ?? ""
            guard name.contains("leg") else {return}
            var parent = node.parent
            while let ancestor = parent, ancestor !== model {
                if ancestor.name == "jockey-rider" || ancestor.name?.lowercased().contains("leg") == true {return}
                parent = ancestor.parent
            }
            legs.append((node,node.eulerAngles,Mobs.legSign(name)))
        }
        return legs
    }

    @discardableResult static func gaze(_ model: SCNNode) -> SCNNode? {
        if let gaze = model.childNode(withName:"head-gaze",recursively:true) {return gaze}
        guard let head = model.childNode(withName:"head",recursively:true), let parent = head.parent else {return nil}
        let pivot = SCNNode(); pivot.name = "head-gaze"; pivot.position = head.position
        parent.addChildNode(pivot); pivot.addChildNode(head); head.position = SCNVector3Zero
        return pivot
    }

    func apply(distance: Double, phase: Double? = nil) {
        guard let clip, let phase else {
            if clip != nil {idle()}
            else {
                resting = false
                if species == .polarBear {
                    // shortcut: the calm controller weight uses scenery's speed conversion rather than native runtime query samples
                    let swing = -cos(distance*38.17*Double.pi/180)*80*Double.pi/180*weight
                    for (leg,base,sign) in legs {leg.eulerAngles = .init(base.x+swing*sign,base.y,base.z)}
                } else {Mobs.pose(legs,species:species,distance:distance)}
            }
            return
        }
        resting = false
        let time = min(1,max(0,phase))*clip.duration, radians = Double.pi/180
        for joint in joints {
            if let channel = joint.track.rotation {
                let v = channel.sample(time), b = joint.rotation
                joint.node.eulerAngles = .init(b.x-v.x*radians,b.y+v.y*radians,b.z-v.z*radians)
            }
            if let channel = joint.track.position {
                let v = channel.sample(time), b = joint.position
                joint.node.position = .init(b.x+v.x/16,b.y+v.y/16,b.z+v.z/16)
            }
        }
    }

    func idle() {
        guard !resting else {return}
        resting = true
        for (leg,base,_) in legs {leg.eulerAngles = base}
        for joint in joints {joint.node.eulerAngles = joint.rotation; joint.node.position = joint.position}
    }
}
