import Foundation
import SceneKit

struct Cell: Hashable, Codable {
    let x: Int
    let y: Int
    let z: Int
    var point: SCNVector3 { .init(Double(x)+0.5,Double(y),Double(z)+0.5) }
}

// The saved plan reconstructs scenery edits without changing the owner's game world
struct Trail {
    struct Record: Codable {
        let kind: String
        let x: Int
        let y: Int
        let z: Int
        let seed: Int
        var version: Int? = nil
        var anchors: [Cell]? = nil
        var connections: [[Cell]]? = nil
        var shelter: Cell? = nil
        var foundation: Int? = nil
        var valid: Bool { ["nether","end"].contains(kind) && (-29_998_999...29_998_999).contains(x) && (-29_998_999...29_998_999).contains(z) && (32...250).contains(y)
            && (version == nil || version == 2)
            && (anchors == nil || anchors!.count == (kind == "end" ? 13 : 7) && anchors!.allSatisfy {abs(Double($0.x)-Double(x))<192 && abs(Double($0.z)-Double(z))<480 && (-55...300).contains($0.y)})
            && (foundation == nil || (1...128).contains(foundation!))
            && (shelter == nil || abs(Double(shelter!.x)-Double(x))<64 && abs(Double(shelter!.z)-Double(z))<64 && (0...300).contains(shelter!.y))
            && (connections == nil || anchors != nil && connections!.count == anchors!.count-1 && connections!.allSatisfy {$0.count<=2048 && $0.allSatisfy {abs(Double($0.x)-Double(x))<192 && abs(Double($0.z)-Double(z))<480 && (-55...300).contains($0.y)}}) }
    }
    struct Stop {
        let point: SCNVector3
        let title: String
    }
    let record: Record
    var blocks: [Cell:Block] = [:]
    var route: [Stop] = []
    var remains: [SCNVector3] = []
    var entrance: SCNVector3 { route.first!.point }
    var portal: SCNVector3 { route.last!.point }

    init(_ input: Record) {
        precondition(input.valid)
        var record = input
        let end = record.kind == "end", base = max(-44,record.y-(end ? 77 : 62))
        let levels = end ? [record.y,base+40,base+25,base+16,base+7,base,base-1,base-2,base-2,base-3,base-5,base-5,base-5]
            : [record.y,base+30,base+17,base+7,base+2,base,base]
        if record.anchors == nil {
            record.anchors = levels.enumerated().map { index,y in
                let x = index == 0 ? 0 : Int((Terrain.random(index,13,seed:record.seed)-0.5)*48)
                let z = index*30+(index == 0 ? 0 : Int(Terrain.random(index,17,seed:record.seed)*9))
                return Cell(x:record.x+x,y:y,z:record.z+z)
            }
        }
        record.version = 2
        self.record = record
        let centres = record.anchors!
        let titles = end ? ["Follow the eyes of Ender","Ravine cracks","The old mineshaft","Forgotten dungeon",
            "Lush caverns and dripstone","The breached stronghold","Forgotten prisons","Ruined kitchens",
            "The white-eyed shrine","Abandoned sleeping quarters","The underground aqueduct","A crack behind the false wall","The grand End portal"]
            : ["A cave beneath your world","Abandoned mineshaft","Forgotten dungeon","Buried city ruins","Broken mining rails","Dormant redstone and obsidian lava","The Nether portal"]
        func random(_ x: Int,_ z: Int) -> Double {Terrain.random(x,z,seed:record.seed)}
        func put(_ cell: Cell,_ name: String,_ states: [String:String] = [:]) {blocks[cell] = Block(name:name,states:states)}
        func local(_ index: Int,_ x: Int,_ y: Int,_ z: Int) -> Cell {
            let c = centres[index]; return Cell(x:c.x+x,y:c.y+y,z:c.z+z)
        }
        func box(_ index: Int,_ xs: ClosedRange<Int>,_ ys: ClosedRange<Int>,_ zs: ClosedRange<Int>,_ name: String,_ states: [String:String] = [:]) {
            for x in xs {for y in ys {for z in zs {put(local(index,x,y,z),name,states)}}}
        }
        // Air brushes intersect the real seed's caves instead of sealing them inside rock shells
        func cavern(_ c: Cell,_ rx: Int,_ ry: Int,_ rz: Int) {
            for x in -rx...rx {for y in -ry...ry {for z in -rz...rz {
                let nx = Double(x)/Double(rx), ny = Double(y)/Double(ry), nz = Double(z)/Double(rz)
                let edge = nx*nx+ny*ny+nz*nz
                let rough = Terrain.noise(Double(c.x+x),Double(c.z+z+y*2),scale:5,seed:record.seed)*0.17
                if edge<0.91+rough {
                    put(Cell(x:c.x+x,y:c.y+y,z:c.z+z),"air")
                }
            } } }
        }
        for (index,c) in centres.enumerated() {
            let natural = !end || index<5
            if natural {
                let wide = index == 0 ? 6 : index == 1 ? 13 : index == 3 ? 19 : 15
                cavern(Cell(x:c.x,y:c.y+4,z:c.z),wide,index == 1 && end ? 19 : 10,wide+3)
            }
        }
        // Existing clear cave connections are persisted; missing connections use seeded curved erosion
        var links: [[SCNVector3]] = []
        for index in 0..<(centres.count-1) {
            let a = centres[index], last = centres[index+1]
            let b = index == centres.count-2 ? Cell(x:last.x,y:last.y+1,z:last.z-(end ? 4 : 2)) : last
            if let connection = record.connections?[index], connection.count>=2 {
                links.append(connection.map {.init(Double($0.x)+0.5,Double($0.y)+1.62,Double($0.z)+0.5)})
                continue
            }
            let length = hypot(hypot(Double(b.x-a.x),Double(b.z-a.z)),Double(b.y-a.y))
            let count = max(2,Int(ceil(length/1.25)))
            let bend = (random(index,41)-0.5)*18
            var points: [SCNVector3] = []
            for step in 0...count {
                let t = Double(step)/Double(count), slope = min(1,max(0,(t-0.35)/0.3))
                let ease = slope*slope*(3-2*slope)
                let x = Double(a.x)+Double(b.x-a.x)*t+sin(t * .pi)*bend
                let z = Double(a.z)+Double(b.z-a.z)*t+sin(t * .pi*2)*2
                let y = Double(a.y)+Double(b.y-a.y)*ease
                let c = Cell(x:Int(x.rounded()),y:Int(y.rounded()),z:Int(z.rounded()))
                if step%2 == 0 || step == count {
                    let radius = 3+Int(random(step,index)*3)
                    cavern(Cell(x:c.x,y:c.y+3,z:c.z),radius,4+Int(random(index,step)*3),radius)
                }
                points.append(.init(x+0.5,y+1.62,z+0.5))
            }
            links.append(points)
        }
        func room(_ index: Int,_ width: Int,_ depth: Int,_ height: Int,_ material: String) {
            for x in (-width-1)...(width+1) {for y in -1...height {for z in (-depth-1)...(depth+1) {
                let edge = abs(x)>width || abs(z)>depth || y == -1 || y == height
                let cell = local(index,x,y,z)
                if !edge {put(cell,"air"); continue}
                let damage = random(cell.x+y,cell.z)
                let stone = material == "stone_bricks" ? (damage<0.23 ? "mossy_stone_bricks" : damage<0.48 ? "cracked_stone_bricks" : material) : material
                put(cell,stone)
                if y>1 && y<height && damage<0.09 {put(cell,"air")}
            } } }
            for x in [-width+1,width-1] {for z in stride(from:-depth+2,through:depth-1,by:6) {
                put(local(index,x,0,z),material)
                put(local(index,x,1,z),"torch",["torch_facing_direction":"top"])
            } }
        }
        // Broken, supported crossings leave the surrounding ravine open
        for x in -12...12 {
            for z in -1...1 {put(local(1,x,-1,z),"oak_planks")}
            if x%7 != 0 {put(local(1,x,0,0),"rail",["rail_direction":"1"])}
            if x%6 == 0 {for z in [-2,2] {box(1,x...x,-24...3,z...z,"oak_log")}; box(1,x...x,4...4,-2...2,"oak_planks")}
        }
        let dungeon = end ? 3 : 2
        room(dungeon,7,7,6,"mossy_cobblestone")
        for x in [-5,5] {put(local(dungeon,x,0,3),"chest",["facing_direction":"2"]); put(local(dungeon,x,3,5),"cobweb")}
        put(local(dungeon,4,0,-3),"mob_spawner")
        if end {
            for x in -12...12 {for z in -12...12 where x*x+z*z<150 {
                if random(x,z)<0.76 {put(local(4,x,-1,z),"moss_block")}
                if abs(x)>3 && random(x+1,z)<0.12 {
                    let height = 1+Int(random(z,x)*4)
                    box(4,x...x,0...(height-1),z...z,"dripstone_block")
                    put(local(4,x,height,z),"pointed_dripstone",["dripstone_thickness":"tip","hanging":"0"])
                }
                if random(x+5,z)<0.08 {box(4,x...x,5...7,z...z,"cave_vines")}
            } }
            box(4,-10...(-7),-2...(-1),-6...8,"water")
            for i in 5...12 {room(i,i == 8 || i == 12 ? 12 : 9,i == 12 ? 13 : 9,i == 8 || i == 12 ? 12 : 7,"stone_bricks")}
            // The entrance is a breached ruin, rather than a pristine door in a cave wall
            for x in -10...10 {for z in -12...(-9) where abs(x)>3 {
                for y in 0...Int(random(x,z)*3) {put(local(5,x,y,z),"cracked_stone_bricks")}
            } }
            for x in [-7,7] {
                box(6,x...x,0...3,-6...6,"iron_bars")
                remains.append(local(6,x<0 ? -8 : 8,0,2).point)
            }
            for z in -6...6 {put(local(7,-7,0,z),z%3 == 0 ? "furnace" : "stone_bricks")}
            for z in [-5,0,5] {
                put(local(7,4,0,z),"oak_fence"); put(local(7,4,1,z),"oak_pressure_plate")
                put(local(7,6,0,z),"oak_stairs",["facing":"west"])
            }
            put(local(7,-6,0,5),"cauldron"); put(local(7,-6,0,-5),"crafting_table")
            box(8,4...8,0...1,5...7,"chiseled_stone_bricks")
            box(8,5...7,2...4,6...7,"light_blue_wool")
            box(8,5...7,5...6,6...7,"brown_terracotta")
            for x in [5,7] {put(local(8,x,6,5),"white_wool")}
            for x in [-7,7] {for z in [-5,0,5] {
                put(local(9,x,0,z),"red_bed",["facing":"north","part":"foot"])
                put(local(9,x,0,z-1),"red_bed",["facing":"north","part":"head"])
                put(local(9,x,0,z+1),"chest")
            } }
            for x in [-6,6] {box(10,(x-1)...(x+1),-2...(-1),-8...8,"water")}
            box(11,-8...8,0...5,3...3,"cracked_stone_bricks")
            box(11,-1...1,0...2,3...3,"air")
            for x in [-9,9] {for z in [-9,0,9] {
                box(12,x...x,0...8,z...z,"chiseled_stone_bricks")
                box(12,(x-1)...(x+1),9...9,(z-1)...(z+1),"stone_bricks")
                put(local(12,x,10,z),"torch",["torch_facing_direction":"top"])
            } }
        } else {
            for x in [-12,12] {for z in [-9,0,9] {
                box(3,(x-2)...(x+2),-1...0,(z-2)...(z+2),"chiseled_deepslate")
                for dx in [x-2,x+2] {box(3,dx...dx,-8...6,z...z,"deepslate_bricks")}
                box(3,(x-2)...(x+2),7...7,z...z,"deepslate_tiles")
                put(local(3,x,1,z),"soul_torch",["torch_facing_direction":"top"])
            } }
            for z in -8...8 where z%4 != 0 {put(local(4,0,-1,z),"oak_planks"); put(local(4,0,0,z),"rail")}
            for x in -10...10 {for z in -10...10 where x*x+z*z<105 {
                put(local(5,x,-2,z),"obsidian")
                put(local(5,x,-1,z),abs(x)<3 || random(x,z)<0.32 ? "obsidian" : "lava")
            } }
            for x in -9...(-4) {put(local(5,x,0,-8),"redstone_wire"); put(local(5,x,-1,-8),"obsidian")}
            put(local(5,-9,0,-7),"lever"); put(local(5,-4,0,-7),"redstone_lamp")
        }
        // Recheck the full camera envelope after furnishing, keeping bends clear without box tunnels
        for (index,points) in links.enumerated() {
            for (a,b) in zip(points,points.dropFirst()) {
                let count = max(1,Int(ceil(hypot(hypot(b.x-a.x,b.z-a.z),b.y-a.y)/0.25)))
                for step in 0...count {
                    let t = Double(step)/Double(count)
                    let x = Int(floor(a.x+(b.x-a.x)*t)), y = Int(floor(a.y+(b.y-a.y)*t-1.62)), z = Int(floor(a.z+(b.z-a.z)*t))
                    for dx in -1...1 {for dz in -1...1 {for dy in 0...2 {put(Cell(x:x+dx,y:y+dy,z:z+dz),"air")}}}
                }
            }
            route += points.map {Stop(point:$0,title:titles[index+1])}
        }
        if end {
            box(12,-4...4,-2...(-2),-4...4,"lava")
            box(12,-3...3,-1...(-1),-3...3,"stone_bricks")
            for offset in -1...1 {for (x,z,facing) in [(offset,-2,"south"),(offset,2,"north"),(-2,offset,"east"),(2,offset,"west")] {
                put(local(12,x,0,z),"end_portal_frame",["end_portal_eye_bit":"1","facing":facing])
            } }
            box(12,-1...1,0...0,-1...1,"end_portal")
            // Enter above the ring, then descend through its centre
            let c = centres.last!
            route.append(Stop(point:.init(Double(c.x)+0.5,Double(c.y)+2.62,Double(c.z)-3.5),title:"The grand End portal"))
            route.append(Stop(point:.init(Double(c.x)+0.5,Double(c.y)+2.62,Double(c.z)+0.5),title:"The eyes are watching"))
            route.append(Stop(point:.init(Double(c.x)+0.5,Double(c.y)+1.62,Double(c.z)+0.5),title:"Entering the End"))
        } else {
            let index = centres.count-1
            for x in -2...2 {for y in 0...5 where abs(x) == 2 || y == 0 || y == 5 {put(local(index,x,y,0),"obsidian")}}
            box(index,-1...1,1...4,0...0,"portal",["portal_axis":"x"])
            let c = centres.last!
            route.append(Stop(point:.init(Double(c.x)+0.5,Double(c.y)+2.62,Double(c.z)+2.5),title:"Entering the Nether"))
        }
        if let house = record.shelter {
            for x in -4...4 {for z in -4...4 {for y in -(record.foundation ?? 8)...5 {
                let cell = Cell(x:house.x+x,y:house.y+y,z:house.z+z)
                if y<0 {put(cell,"cobblestone")}
                else if y == 5 {put(cell,"oak_planks")}
                else if abs(x) == 4 || abs(z) == 4 {put(cell,"oak_planks")}
                else {put(cell,"air")}
            } } }
            for x in -1...1 {for y in 0...2 {put(Cell(x:house.x+x,y:house.y+y,z:house.z-4),"air")}}
            for x in [-4,4] {for z in -1...1 {put(Cell(x:house.x+x,y:house.y+2,z:house.z+z),"glass_pane")}}
            put(Cell(x:house.x-2,y:house.y,z:house.z+2),"chest",["facing_direction":"2"])
            put(Cell(x:house.x+2,y:house.y,z:house.z+2),"crafting_table")
            put(Cell(x:house.x+3,y:house.y+2,z:house.z),"wall_torch",["facing":"west"])
        }
        route[0] = Stop(point:route[0].point,title:titles[0])
    }

    static func plan(_ record: Record, data: WorldData) -> Trail {
        if record.version == 2 {return Trail(record)}
        var record = Trail(record).record
        let entrance = record.anchors![0].point
        let nearby = record.kind == "end" ? chests(data:data,near:entrance).filter {cell in
            data.surface(cell.x,cell.z).map {cell.y>$0-8} ?? false
        } : []
        let reachable = nearby.prefix(8).contains {chest in
            [(1,0),(-1,0),(0,1),(0,-1)].contains {dx,dz in
                path(data:data,from:.init(entrance.x,entrance.y+1.62,entrance.z),
                    to:.init(Double(chest.x+dx)+0.5,Double(chest.y)+1.62,Double(chest.z+dz)+0.5)) != nil
            }
        }
        if record.kind == "end" && !reachable {
            var sites: [(Cell,Int,Int)] = []
            for (dx,dz) in [(-12,-10),(12,-10),(-12,10),(12,10)] {
                let x = record.x+dx, z = record.z+dz
                var heights: [Int] = []
                for ox in [-4,0,4] {for oz in [-4,0,4] {
                    guard var y = data.surface(x+ox,z+oz) else {continue}
                    while y>0, let block = data.block(x+ox,y,z+oz), ["leaves","log","wood"].contains(where:block.name.contains) {y -= 1}
                    if data.block(x+ox,y,z+oz)?.fluid == false {heights.append(y)}
                } }
                if heights.count == 9, let low = heights.min(), let high = heights.max(), high-low<120 {
                    sites.append((Cell(x:x,y:high+1,z:z),high-low+2,high-low))
                }
            }
            if let site = sites.min(by:{$0.2<$1.2}) {record.shelter = site.0; record.foundation = site.1}
            else {record.shelter = Cell(x:record.x-12,y:record.y,z:record.z-10); record.foundation = 16}
        }
        var centres = record.anchors!
        for index in 1..<centres.count where index<(record.kind == "end" ? 5 : 6) {
            let c = centres[index]
            var best: (Cell,Double)?
            for dx in stride(from:-12,through:12,by:3) {for dz in stride(from:-12,through:12,by:3) {for dy in stride(from:-9,through:9,by:3) {
                let cell = Cell(x:c.x+dx,y:c.y+dy,z:c.z+dz)
                guard let floor = data.standing(at:cell.point,radius:0.3,height:1.8),
                      data.surface(cell.x,cell.z).map({Double($0)>floor.y+5}) == true else {continue}
                let score = Double(dx*dx+dz*dz+dy*dy)
                if score<(best?.1 ?? .infinity) {best = (Cell(x:cell.x,y:Int(floor.y),z:cell.z),score)}
            } } }
            if let best {centres[index] = best.0}
        }
        record.anchors = centres
        record.connections = zip(centres,centres.dropFirst()).map { a,b in
            let start = SCNVector3(a.point.x,a.point.y+1.62,a.point.z), end = SCNVector3(b.point.x,b.point.y+1.62,b.point.z)
            return path(data:data,from:start,to:end)?.map {Cell(x:Int(floor($0.x)),y:Int(floor($0.y-1.62+0.01)),z:Int(floor($0.z)))} ?? []
        }
        return Trail(record)
    }
    static func anchor(data: WorldData, eye: SCNVector3, destination: World, seed: String) -> Record? {
        let x = Int(floor(eye.x)), z = Int(floor(eye.z))
        let candidates = stride(from:24,through:64,by:8).flatMap { radius in (0..<12).map { index in
            let angle = Double(index)*Double.pi/6
            return (x+Int(cos(angle)*Double(radius)),z+Int(sin(angle)*Double(radius)))
        } }
        let available = candidates.compactMap { x,z -> (Int,Int,Int)? in
            guard let y = data.surface(x,z,below:data.dimension == 1 ? 118 : 250), (32...249).contains(y),
                  let floor = data.block(x,y,z), !floor.fluid else {return nil}
            return (x,y+1,z)
        }
        func score(_ point: (Int,Int,Int)) -> Double {
            let (x,y,z) = point
            var openings = 0.0
            for dx in [-3,0,3] {for dz in [-3,0,3] {for depth in [3,6,9] {
                if data.block(x+dx,y-depth,z+dz)?.air == true {openings += 1}
            } } }
            return openings*4-hypot(Double(x)-eye.x,Double(z)-eye.z)*0.03
        }
        guard let point = available.max(by:{score($0)<score($1)}) else {return nil}
        return Record(kind:destination == .end ? "end" : "nether",x:point.0,y:point.1,z:point.2,seed:Seed.number(seed))
    }

    func decoration(assets: Assets) throws -> SCNNode {
        let root = SCNNode(); root.name = "ruins-"+record.kind
        let factory = Mobs(assets:assets)
        for (index,point) in remains.enumerated() {
            let skeleton = try factory.make(.skeleton)
            skeleton.name = "ancient-skeleton-remains"
            skeleton.position = .init(point.x,point.y+0.18,point.z-0.8)
            skeleton.eulerAngles = .init(.pi/2,0,index == 0 ? 0.12 : -0.18)
            skeleton.childNode(withName:index == 0 ? "leftarm" : "rightleg",recursively:true)?.isHidden = true
            root.addChildNode(skeleton)
        }
        return root
    }

    static func chests(data: WorldData, near eye: SCNVector3) -> [Cell] {
        var cells = Set<Cell>()
        for chunk in data.chunks.values where abs(Double(chunk.key.x*16)-eye.x)<80 && abs(Double(chunk.key.z*16)-eye.z)<80 {
            for section in chunk.sections.values {
                guard let palette = section.layers.first, palette.blocks.contains(where:{$0.name == "chest"}) else {continue}
                for x in 0..<16 {for z in 0..<16 {for y in 0..<16 where palette.block(x,y,z).name == "chest" {
                    cells.insert(Cell(x:chunk.key.x*16+x,y:section.y*16+y,z:chunk.key.z*16+z))
                } } }
            }
        }
        for changes in data.edits.values {for (cell,block) in changes where block.name == "chest" {cells.insert(cell)}}
        return cells.filter {data.block($0.x,$0.y,$0.z)?.name == "chest" && hypot(Double($0.x)-eye.x,Double($0.z)-eye.z)<64}
    }

    func approach(data original: WorldData, eye: SCNVector3, chest: Bool) -> [Stop] {
        var data = original; data.apply(blocks)
        let entrance = entrance, seed = record.seed
        var result: [Stop] = [], start = eye
        if chest {
            var chests = Self.chests(data:data,near:eye)
            chests.sort { hypot(Double($0.x)-eye.x,Double($0.z)-eye.z)<hypot(Double($1.x)-eye.x,Double($1.z)-eye.z) }
            chests = Array(chests.prefix(8))
            if !chests.isEmpty {
                let offset = Int(Terrain.random(Int(eye.x),Int(eye.z),seed:seed)*Double(chests.count))
                chests = Array(chests[offset...])+Array(chests[..<offset])
            }
            for chest in chests.prefix(8) {
                let targets = [(1,0),(-1,0),(0,1),(0,-1)].map { dx,dz in SCNVector3(Double(chest.x+dx)+0.5,Double(chest.y)+1.62,Double(chest.z+dz)+0.5) }
                if let path = targets.compactMap({ Self.path(data:data,from:eye,to:$0) }).min(by:{$0.count<$1.count}), let last = path.last {
                    result += path.map {Stop(point:$0,title:"An eye of Ender in the house chest")}; start = last; break
                }
            }
        }
        if let path = Self.path(data:data,from:start,to:entrance) {
            result += path.map {Stop(point:$0,title:chest ? "Follow the eyes of Ender" : "The nearby cave entrance")}
        } else {
            // A high, collision-checked approach keeps obstructed terrain from forcing a cut
            let distance = hypot(entrance.x-start.x,entrance.z-start.z)
            var altitude = max(start.y,entrance.y)+8
            for index in 0...max(1,Int(distance)) {
                let t = Double(index)/Double(max(1,Int(distance)))
                if let ground = data.surface(Int(start.x+(entrance.x-start.x)*t),Int(start.z+(entrance.z-start.z)*t)) {altitude = max(altitude,Double(ground)+8)}
            }
            result += [Stop(point:.init(start.x,altitude,start.z),title:"Above your world"),Stop(point:.init(entrance.x,altitude,entrance.z),title:"The cave entrance")]
        }
        return result
    }

    static func path(data: WorldData, from start: SCNVector3, to end: SCNVector3) -> [SCNVector3]? {
        func cell(_ eye: SCNVector3) -> Cell {Cell(x:Int(floor(eye.x)),y:Int(floor(eye.y-1.62+0.1)),z:Int(floor(eye.z)))}
        let first = cell(start), last = cell(end)
        guard data.vacant(last.point), hypot(Double(last.x-first.x),Double(last.z-first.z))<160 else {return nil}
        func estimate(_ cell: Cell) -> Double {Double(abs(cell.x-last.x)+abs(cell.y-last.y)+abs(cell.z-last.z))}
        var heap: [(Cell,Double)] = [(first,estimate(first))]
        func push(_ value: (Cell,Double)) {
            heap.append(value); var i = heap.count-1
            while i>0 {let p = (i-1)/2; if heap[p].1<=heap[i].1 {break}; heap.swapAt(i,p); i = p}
        }
        func pop() -> Cell? {
            guard !heap.isEmpty else {return nil}
            let first = heap[0].0, tail = heap.removeLast()
            if !heap.isEmpty {
                heap[0] = tail; var i = 0
                while i*2+1<heap.count {
                    var child = i*2+1; if child+1<heap.count, heap[child+1].1<heap[child].1 {child += 1}
                    if heap[i].1<=heap[child].1 {break}; heap.swapAt(i,child); i = child
                }
            }
            return first
        }
        var previous: [Cell:Cell] = [:], costs: [Cell:Double] = [first:0], visited = Set<Cell>()
        while let current = pop(), visited.count<24_000 {
            if current == last {
                var cells = [current], cursor = current
                while cursor != first {guard let next = previous[cursor] else {return nil}; cells.append(next); cursor = next}
                var points: [Cell] = []
                for value in cells.reversed() {
                    if points.count>=2 {
                        let a = points[points.count-2], b = points[points.count-1]
                        if (b.x-a.x,b.y-a.y,b.z-a.z) == (value.x-b.x,value.y-b.y,value.z-b.z) {points.removeLast()}
                    }
                    points.append(value)
                }
                return points.map {.init(Double($0.x)+0.5,Double($0.y)+1.62,Double($0.z)+0.5)}
            }
            guard visited.insert(current).inserted else {continue}
            for (dx,dy,dz) in [(1,0,0),(-1,0,0),(0,0,1),(0,0,-1),(0,1,0),(0,-1,0)] {
                let next = Cell(x:current.x+dx,y:current.y+dy,z:current.z+dz)
                guard !visited.contains(next), next.y>=min(first.y,last.y)-4, next.y<=max(first.y,last.y)+12,
                      abs(next.x-first.x)<160, abs(next.z-first.z)<160, data.vacant(next.point) else {continue}
                let cost = costs[current,default:0]+(dy == 0 ? 1 : 1.2)
                if cost<costs[next,default:Double.infinity] {costs[next] = cost; previous[next] = current; push((next,cost+estimate(next)))}
            }
        }
        return nil
    }
}
