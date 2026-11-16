import SceneKit

// Residents choose new goals against the same blocks as the camera
final class Crowd {
    final class Resident {
        let actor: SCNNode
        let model: SCNNode
        let species: Species
        let motion: Mobs.Motion
        var velocity = SCNVector3Zero
        var airborne = false
        var swimming: Bool
        var nextChoice = 0.0
        let width: Double
        let height: Double
        let home: SCNVector3
        let seed: Int
        var target: SCNVector3?
        var choice = 0
        var wait = 0.0
        var stride = 0.0
        let legs: [(SCNNode,SCNVector3,Double)]
        let head: SCNNode?
        let rest: SCNVector3
        var watching = false
        var glance = -1

        init(actor: SCNNode, model: SCNNode, species: Species, motion: Mobs.Motion, width: Double, height: Double, seed: Int) {
            self.actor = actor; self.model = model; self.species = species; swimming = species.swimming
            self.motion = motion; self.width = width; self.height = height; self.seed = seed; home = actor.position
            var legs: [(SCNNode,SCNVector3,Double)] = []
            model.enumerateChildNodes { node,_ in
                let name = node.name?.lowercased() ?? ""
                if name.contains("leg") {
                    let side = Mobs.legSign(name)
                    legs.append((node,node.eulerAngles,side))
                }
            }
            self.legs = legs
            head = model.childNode(withName:"head",recursively:true)
            rest = head?.eulerAngles ?? .init(0,0,0)
        }
    }

    let root = SCNNode()
    private(set) var residents: [Resident] = []
    private var elapsed = 0.0
    private var accumulated = 0.0
    private var leashes: [(SCNNode,SCNNode,[SCNNode])] = []

    init(data: WorldData, at eye: SCNVector3, assets: Assets) throws {
        root.name = "living-world"; root.categoryBitMask = 1
        let factory = Mobs(assets:assets), cx = Int(floor(eye.x)), cz = Int(floor(eye.z))
        let buried = data.dimension == 0 && (data.surface(cx,cz).map {Double($0)>eye.y+6} ?? false)
            && data.block(cx,Int(floor(eye.y)),cz)?.fluid != true
        var village = false
        for chunk in data.chunks.values where abs(chunk.key.x-cx/16)<4 && abs(chunk.key.z-cz/16)<4 {
            if chunk.sections.values.contains(where:{ $0.layers.contains { $0.blocks.contains { $0.name == "bed" || $0.name.hasSuffix("_bed") || $0.name == "bell" } } }) { village = true; break }
        }
        var crowned = false
        for index in 0..<112 where residents.count<64 {
            let angle = Terrain.random(index,0,seed:421)*Double.pi*2
            let radius = 6+sqrt(Terrain.random(index,1,seed:421))*70
            let x = cx+Int(cos(angle)*radius), z = cz+Int(sin(angle)*radius)
            let sample = SCNVector3(Double(x)+0.5,eye.y,Double(z)+0.5), biome = data.biome(sample)
            var choices = biome.residents
            if village && radius<48 { choices += [.villager,.villager,.cat,.pig,.sheep,.ironGolem,.golem] }
            else { choices.removeAll { [.villager,.golem,.ironGolem,.trader,.traderLlama,.mule].contains($0) } }
            if buried { choices = [.bat,.bat,.spider,.caveSpider,.skeleton,.zombie,.creeper] }
            guard !choices.isEmpty else { continue }
            let species = choices[index%choices.count]
            let maxY = data.dimension == 1 || biome.underground || buried ? Int(eye.y) : 320
            guard let top = data.surface(x,z,below:maxY), let block = data.block(x,top,z) else { continue }
            if !species.flying && !species.swimming && ["leaves","planks","log","stairs","slab","bed","glass","fence","wall","hay","roof"].contains(where:block.name.contains) { continue }
            if species.swimming && !block.fluid || !species.swimming && !species.flying && block.fluid && species != .strider && !species.amphibious { continue }
            var point = SCNVector3(Double(x)+0.5,Double(top)+1,Double(z)+0.5)
            if species.swimming {
                point.y -= 1.4
                guard data.block(x,Int(floor(point.y)),z)?.name == "water" else { continue }
            }
            if species.amphibious && !species.swimming && block.name.contains("water") {
                for y in stride(from:top,through:data.dimension == 0 ? -64 : 0,by:-1) {
                    if let floor = data.block(x,y,z), !floor.passable && !floor.fluid {point.y = Double(y)+1; break}
                }
            }
            if species.flying { point.y += 2+Terrain.random(index,2,seed:421)*4 }
            let baby = index%7 == 0 && [.pig,.cow,.sheep,.villager,.horse,.cat,.axolotl,.chicken].contains(species)
            let name = species == .sheep && index%5 == 0 ? "jeb_" : species == .rabbit && index%3 == 0 ? "Toast" : nil
            let model = species == .creeper && index%9 == 0 ? try factory.charged()
                : try factory.make(species,biome:biome,variant:index,classic:false,baby:baby,named:name)
            let motion = try factory.locomotion(species)
            if species.swimming {
                point.y = min(point.y,Double(top)+0.85-motion.height)
                guard data.immersed(point,radius:motion.width/2,height:motion.height,in:"water") else {continue}
            }
            if !species.flying && !species.swimming {
                guard let floor = data.standing(at:point,radius:motion.width/2*(baby ? 0.5 : 1),height:motion.height*(baby ? 0.5 : 1),lava:species == .strider,water:species.amphibious) else {continue}
                point = floor
            }
            guard species.swimming || data.vacant(point,radius:motion.width/2,height:motion.height) else { continue }
            if species == .pig && !crowned { try factory.crown(model); crowned = true }
            if species == .sheep && index%11 == 0 { try factory.pink(model,baby:baby) }
            let actor = SCNNode(); actor.name = "resident-"+species.rawValue
            actor.position = point; actor.eulerAngles.y = angle; actor.categoryBitMask = 1
            if !species.flying && !species.swimming { model.position.y = max(0,-model.boundingBox.min.y*model.scale.y) }
            actor.addChildNode(model); root.addChildNode(actor)
            residents.append(Resident(actor:actor,model:model,species:species,motion:motion,width:motion.width*(baby ? 0.5 : 1),height:motion.height*(baby ? 0.5 : 1),seed:index))
        }
        if let trader = residents.first(where:{ $0.species == .trader }) {
            for llama in residents.filter({ $0.species == .traderLlama }).prefix(2) {
                let beside = SCNVector3(trader.actor.position.x+3,trader.actor.position.y,trader.actor.position.z+2)
                guard let floor = data.standing(at:beside,radius:llama.width/2,height:llama.height) else {continue}
                let material = SCNMaterial(); material.diffuse.contents = NSColor.brown; material.lightingModel = .lambert
                let shape = SCNBox(width:0.025,height:0.025,length:1,chamferRadius:0); shape.firstMaterial = material
                let segments = (0..<24).map { _ in
                    let node = SCNNode(geometry:shape); node.name = "trader-leash"; node.categoryBitMask = 1
                    root.addChildNode(node); return node
                }
                llama.actor.position = floor
                leashes.append((trader.actor,llama.actor,segments))
            }
        }
    }

    static func attention(_ species: Species) -> Double {
        switch species {
        case .villager,.trader,.piglin,.piglinBrute,.illager,.vindicator,.evoker,.enderman,.witch,.warden: return 0.4
        case .wolf,.cat,.fox,.dolphin,.allay,.parrot,.ironGolem: return 0.3
        case .zombie,.skeleton,.creeper,.spider,.horse,.donkey,.mule,.golem: return 0.2
        default: return 0.1
        }
    }

    func advance(_ dt: Double, data: WorldData, observer: SCNVector3? = nil, visible: ((Chunk) -> Bool)? = nil) {
        elapsed += dt; accumulated += dt
        guard accumulated>=1.0/30 else { return }
        let dt = min(0.1,accumulated); accumulated = 0
        let night = Daylight.light(at:elapsed)<0.15
        for resident in residents {
            let actor = resident.actor, species = resident.species
            let key = WorldData.key(Int(floor(actor.position.x)),Int(floor(actor.position.z)))
            actor.isHidden = visible.map {!$0(key)} ?? false
            if [.zombie,.skeleton,.husk,.phantom].contains(species) && data.dimension == 0 { actor.isHidden = actor.isHidden || !night }
            if actor.isHidden { continue }
            let wet = data.medium(at:.init(actor.position.x,actor.position.y+resident.height*0.5,actor.position.z)) == "water"
            let support = species.amphibious ? data.standing(at:actor.position,radius:resident.width/2,height:resident.height,water:true) : nil
            if species.amphibious {
                if species == .drowned {resident.swimming = false}
                else if wet && support == nil {resident.swimming = true}
                else if !wet && support != nil {resident.swimming = false}
                else if species == .axolotl && support != nil {resident.swimming = false}
            }
            let swimming = resident.swimming
            if let observer, let head = resident.head {
                let turn = Int(elapsed/8)
                if turn != resident.glance {
                    resident.glance = turn
                    resident.watching = Terrain.random(resident.seed,turn,seed:487)<Self.attention(species)
                }
                let point = head.presentation.worldPosition
                let dx = observer.x-point.x, dz = observer.z-point.z, distance = hypot(dx,dz)
                var yaw = atan2(dx,dz)-actor.eulerAngles.y
                yaw = atan2(sin(yaw),cos(yaw))
                if resident.watching && resident.wait>0 && distance<12 {
                    actor.eulerAngles.y += yaw*(1-exp(-dt*3))
                    yaw = atan2(dx,dz)-actor.eulerAngles.y
                    yaw = atan2(sin(yaw),cos(yaw))
                }
                let watching = resident.watching && distance<16 && abs(yaw)<1.35
                let pitch = watching ? atan2(observer.y-point.y,max(0.01,distance)) : 0
                let target = SCNVector3(resident.rest.x+min(0.65,max(-0.65,pitch)),resident.rest.y+(watching ? yaw : 0),resident.rest.z)
                let blend = 1-exp(-dt*6)
                head.eulerAngles = .init(head.eulerAngles.x+(target.x-head.eulerAngles.x)*blend,
                    head.eulerAngles.y+(target.y-head.eulerAngles.y)*blend,head.eulerAngles.z+(target.z-head.eulerAngles.z)*blend)
            }
            resident.wait -= dt
            if species.flying && resident.motion.reselect && elapsed>=resident.nextChoice {
                resident.target = nil; resident.wait = 0
            }
            if !species.flying && !swimming,
               data.standing(at:actor.position,radius:resident.width/2,height:resident.height,lava:species == .strider,water:species.amphibious) == nil {
                resident.airborne = true
                resident.velocity.y = max(-12,resident.velocity.y-dt*20)
                let next = SCNVector3(actor.position.x,actor.position.y+resident.velocity.y*dt,actor.position.z)
                actor.position = data.move(from:actor.position,to:next,radius:resident.width/2,height:resident.height)
                if let floor = data.standing(at:actor.position,radius:resident.width/2,height:resident.height,lava:species == .strider,water:species.amphibious) {
                    actor.position = floor; resident.velocity = SCNVector3Zero; resident.airborne = false
                }
                for (leg,base,_) in resident.legs {leg.eulerAngles = base}
                continue
            }
            resident.airborne = false
            if resident.target == nil && resident.wait<=0 {
                for _ in 0..<8 {
                    resident.choice += 1
                    let choice = resident.choice, angle = Terrain.random(resident.seed,choice,seed:431)*Double.pi*2
                    let distance = 2+Terrain.random(resident.seed,choice,seed:432)*(species.flying ? resident.motion.horizontal : 10)
                    let x = actor.position.x+cos(angle)*distance, z = actor.position.z+sin(angle)*distance
                    var target = SCNVector3(x,actor.position.y,z)
                    if species.flying {
                        target.y += resident.motion.offset+(Terrain.random(resident.seed,choice,seed:433)-0.5)*resident.motion.vertical*2
                        if let floor = data.surface(Int(floor(x)),Int(floor(z)),below:Int(actor.position.y)+1) {
                            target.y = max(target.y,Double(floor)+1.5)
                        }
                        if species == .bee, let floor = data.surface(Int(floor(x)),Int(floor(z)),below:Int(actor.position.y)+8) {
                            target.y = Double(floor)+2+Terrain.random(resident.seed,choice,seed:436)*3
                        }
                        guard data.vacant(target,radius:resident.width/2,height:resident.height),
                              data.medium(at:target) == nil else {continue}
                    } else if swimming {
                        target.y += (Terrain.random(resident.seed,choice,seed:433)-0.5)*3
                        guard data.immersed(target,radius:resident.width/2,height:resident.height,in:"water") else {continue}
                    } else {
                        if species == .villager && night {target = resident.home}
                        guard let floor = data.standing(at:target,radius:resident.width/2,height:resident.height,lava:species == .strider,water:species.amphibious) else {continue}
                        target = floor
                    }
                    resident.nextChoice = elapsed+resident.motion.interval.lowerBound+Terrain.random(resident.seed,choice,seed:435)*(resident.motion.interval.upperBound-resident.motion.interval.lowerBound)
                    resident.target = target; break
                }
                if resident.target == nil {resident.wait = species.flying ? resident.motion.interval.lowerBound : 1.5}
            }
            guard let target = resident.target else {
                for (leg,base,_) in resident.legs {leg.eulerAngles.x += (base.x-leg.eulerAngles.x)*(1-exp(-dt*10))}
                continue
            }
            let start = actor.position, dx = target.x-start.x, dy = target.y-start.y, dz = target.z-start.z
            let distance = hypot(hypot(dx,dz),dy)
            if distance<0.15 {
                resident.target = nil
                resident.wait = species.flying || swimming ? 0 : Terrain.random(resident.seed,resident.choice,seed:434)*4
                continue
            }
            let speed = swimming ? resident.motion.waterSpeed : resident.motion.speed
            let step = min(distance,dt*speed), scale = step/distance
            var next = SCNVector3(start.x+dx*scale,start.y+dy*scale,start.z+dz*scale)
            if species.flying || swimming {
                let blend = 1-exp(-dt*(species == .bat ? 8 : 3))
                resident.velocity = .init(resident.velocity.x+(dx/distance*speed-resident.velocity.x)*blend,
                    resident.velocity.y+(dy/distance*speed-resident.velocity.y)*blend,resident.velocity.z+(dz/distance*speed-resident.velocity.z)*blend)
                next = .init(start.x+resident.velocity.x*dt,start.y+resident.velocity.y*dt,start.z+resident.velocity.z*dt)
            }
            let moved: SCNVector3
            if swimming {
                moved = data.immersed(next,radius:resident.width/2,height:resident.height,in:"water") ? data.move(from:start,to:next,radius:resident.width/2,height:resident.height) : start
            } else if species.flying {
                moved = data.medium(at:next) == nil ? data.move(from:start,to:next,radius:resident.width/2,height:resident.height) : start
            } else {
                moved = data.walk(from:start,to:next,radius:resident.width/2,height:resident.height,lava:species == .strider,water:species.amphibious)
            }
            let mx = moved.x-start.x, my = moved.y-start.y, mz = moved.z-start.z, travelled = hypot(mx,mz)
            if hypot(travelled,my)<step*0.1 {
                resident.target = nil; resident.velocity = SCNVector3Zero; resident.wait = species.flying ? 0 : 0.3
                for (leg,base,_) in resident.legs {leg.eulerAngles = base}
                continue
            }
            actor.position = moved
            if travelled>0.00001 {actor.eulerAngles = .init(0,atan2(mx,mz),0)}
            resident.stride += travelled*7
            if !species.flying && !swimming {Mobs.pose(resident.legs,species:species,distance:resident.stride/7)}
        }
        for (trader,llama,segments) in leashes {
            let a = trader.position, b = llama.position
            func point(_ t: Double) -> SCNVector3 { .init(a.x+(b.x-a.x)*t,a.y+0.85+(b.y-a.y)*t-sin(t*Double.pi)*0.5,a.z+(b.z-a.z)*t) }
            for (index,segment) in segments.enumerated() {
                let a = point(Double(index)/24), b = point(Double(index+1)/24)
                segment.position = .init((a.x+b.x)/2,(a.y+b.y)/2,(a.z+b.z)/2)
                segment.scale.z = hypot(hypot(b.x-a.x,b.z-a.z),b.y-a.y)
                segment.look(at:b,up:.init(0,1,0),localFront:.init(0,0,1))
            }
        }
    }
}
