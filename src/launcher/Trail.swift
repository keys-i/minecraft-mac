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
        var valid: Bool { ["nether","end"].contains(kind) && (-29_998_999...29_998_999).contains(x) && (-29_998_999...29_998_999).contains(z) && (32...250).contains(y) }
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

    init(_ record: Record) {
        self.record = record
        precondition(record.valid)
        let end = record.kind == "end", base = max(-47,record.y-(end ? 68 : 50))
        func at(_ x: Int,_ y: Int,_ z: Int) -> Cell { Cell(x:record.x+x,y:y,z:record.z+z) }
        func random(_ x: Int,_ z: Int) -> Double { Terrain.random(x,z,seed:record.seed) }
        func block(_ cell: Cell,_ name: String,_ states: [String:String] = [:]) { blocks[cell] = Block(name:name,states:states) }
        func box(_ x: ClosedRange<Int>,_ y: ClosedRange<Int>,_ z: ClosedRange<Int>,_ name: String) {
            for dx in x { for dy in y { for dz in z { block(at(dx,dy,dz),name) } } }
        }
        func stop(_ x: Int,_ y: Int,_ z: Int,_ title: String) { route.append(Stop(point:.init(Double(record.x+x)+0.5,Double(y)+2.62,Double(record.z+z)+0.5),title:title)) }
        func chamber(_ x: Int,_ y: Int,_ z: Int,_ width: Int,_ depth: Int,_ height: Int,_ stone: String) {
            for dx in (x-width-1)...(x+width+1) { for dy in (y-2)...(y+height+1) { for dz in (z-depth-1)...(z+depth+1) {
                let cell = at(dx,dy,dz)
                if blocks[cell]?.air != true {block(cell,stone)}
            } } }
            box((x-width)...(x+width),y...(y+height),(z-depth)...(z+depth),"air")
            for dx in (x-width)...(x+width) { for dz in (z-depth)...(z+depth) {
                if random(dx,dz)<0.2 { block(at(dx,y-1,dz),stone == "stone_bricks" ? "mossy_stone_bricks" : "cobbled_deepslate") }
            } }
            if stone.contains("bricks") || stone.contains("tiles") {
                let trim = stone.contains("deepslate") ? "deepslate_bricks" : "stone_bricks"
                for dz in stride(from:z-depth+3,through:z+depth-2,by:7) {
                    for dx in [x-width+1,x+width-1] {
                        box(dx...dx,y...(y+height-1),dz...dz,trim)
                        box((dx-1)...(dx+1),(y+height-2)...(y+height-2),dz...dz,trim)
                    }
                    box((x-width+2)...(x+width-2),(y+height-1)...(y+height-1),dz...dz,trim)
                }
                for dx in [x-width-1,x+width+1] {for dz in (z-depth)...(z+depth) {for dy in 0...height where random(dx+dy,dz)<0.27 {
                    block(at(dx,y+dy,dz),stone.contains("deepslate") ? "cracked_deepslate_bricks" : "cracked_stone_bricks")
                } } }
            }
            for dx in [x-width,x+width] { for dz in stride(from:z-depth+2,through:z+depth-1,by:6) {
                block(at(dx,y,dz),"cobblestone"); block(at(dx,y+1,dz),"torch",["torch_facing_direction":"top"])
            } }
        }
        func corridor(_ a: Cell,_ b: Cell,_ rails: Bool = false,_ ruined: Bool = false) {
            let distance = max(abs(b.x-a.x),abs(b.y-a.y),abs(b.z-a.z),1)
            for index in 0...distance {
                let t = Double(index)/Double(distance)
                let x = Int((Double(a.x)+(Double(b.x-a.x))*t).rounded())
                let y = Int((Double(a.y)+(Double(b.y-a.y))*t).rounded())
                let z = Int((Double(a.z)+(Double(b.z-a.z))*t).rounded())
                for dx in -2...2 { for dz in -2...2 {
                    for dy in -1...5 {
                        let cell = Cell(x:x+dx,y:y+dy,z:z+dz)
                        let shell = dy == -1 || dy == 5 || abs(dx) == 2
                        if !shell || blocks[cell] == nil { block(cell,shell ? "stone" : "air") }
                    }
                } }
                if rails && (index%11<8 || !ruined) { block(Cell(x:x,y:y,z:z),"rail",["rail_direction":a.x == b.x ? "0" : "1"]) }
                if rails && index%7 == 3 {
                    for dx in [-2,2] { for dy in 0...3 { block(Cell(x:x+dx,y:y+dy,z:z),"oak_log") } }
                    for dx in -2...2 { block(Cell(x:x+dx,y:y+4,z:z),"oak_planks") }
                    block(Cell(x:x-1,y:y+2,z:z),"wall_torch",["facing":"east"])
                    if ruined && index%3 == 0 { block(Cell(x:x+2,y:y+3,z:z),"cobweb") }
                }
            }
        }

        stop(0,record.y,0,end ? "Follow the eyes of Ender" : "A cave beneath your world")
        let mine = at(0,base+24,25)
        corridor(at(0,record.y,0),mine)
        stop(0,base+24,25,end ? "Ravine" : "Abandoned mineshaft")
        // A broken shaft crosses the descending tunnel rather than replacing its floor
        chamber(0,base+24,31,10,10,12,"stone")
        for x in -8...8 { for z in 27...35 where abs(x)>3 {
            block(at(x,base+24,z),"oak_planks")
            if z == 31 && x%5 != 0 { block(at(x,base+25,z),"rail",["rail_direction":"1"]) }
        } }
        for x in [-9,9] { for y in (base+24)...(base+34) { block(at(x,y,31),"oak_log") } }
        corridor(at(0,base+24,34),at(0,base+12,55),true,true)
        stop(0,base+24,34,"The broken mine bridge")
        stop(0,base+12,55,"Old mining galleries")
        chamber(0,base+12,60,7,7,5,"mossy_cobblestone")
        block(at(-5,base+12,61),"chest",["facing_direction":"3"])
        block(at(5,base+12,61),"chest",["facing_direction":"3"])
        for x in [-3,3] { block(at(x,base+13,63),"cobweb") }
        stop(0,base+12,60,"Forgotten dungeon")
        corridor(at(0,base+12,65),at(0,base+3,84))
        stop(0,base+12,65,"Beyond the dungeon")
        if end {
            for z in 12...42 {
                let bend = Int((sin(Double(z)*0.2)*2).rounded()), width = 2+Int(random(z,11)*2)
                for x in (bend-width)...(bend+width) {for y in (base+25)...(record.y+3) {block(at(x,y,z),"air")}}
            }
            chamber(0,base+3,87,12,10,12,"dripstone_block")
            for x in -11...11 { for z in 78...96 {
                if random(x,z)<0.7 { block(at(x,base+2,z),"moss_block") }
                if abs(x)>3 && random(x,z)<0.13 {
                    for y in 0...Int(random(z,x)*4) { block(at(x,base+3+y,z),"dripstone_block") }
                }
                if random(z,x)<0.12 { for y in 0...Int(random(x,z)*4) { block(at(x,base+14-y,z),"glow_lichen") } }
            } }
            box(-10...(-7),(base+2)...(base+2),79...94,"water")
            stop(0,base+3,88,"Lush caverns and dripstone")
            corridor(at(0,base+3,96),at(0,base,108))
            stop(0,base+3,96,"The dripstone passage")
            chamber(0,base,114,8,9,7,"stone_bricks")
            // Jagged rubble leaves a walkable breach into the buried stronghold
            for x in -7...7 where abs(x)>2 { for y in 0...Int(random(x,108)*4) { block(at(x,base+y,106),y%2 == 0 ? "cracked_stone_bricks" : "mossy_stone_bricks") } }
            stop(0,base,110,"The broken stronghold")
            for x in [-6,6] {
                for z in 110...119 { block(at(x,base,z),"iron_bars"); block(at(x,base+1,z),"iron_bars"); block(at(x,base+2,z),"iron_bars") }
                remains.append(at(x == -6 ? -7 : 7,base,115).point)
            }
            stop(0,base,118,"Forgotten prisons")
            corridor(at(0,base,121),at(0,base,131))
            chamber(0,base,137,8,8,5,"stone_bricks")
            for z in 132...142 { block(at(-7,base,z),z%3 == 0 ? "furnace" : "stone_bricks") }
            for z in stride(from:133,through:141,by:3) {
                block(at(4,base,z),"oak_fence"); block(at(4,base+1,z),"oak_pressure_plate")
                block(at(6,base,z),"oak_stairs",["facing":"west"])
            }
            block(at(-6,base,140),"cauldron"); block(at(-6,base,133),"crafting_table")
            stop(0,base,139,"Ruined kitchens")
            corridor(at(0,base,144),at(0,base,154))
            chamber(0,base,161,10,9,10,"stone_bricks")
            box(2...6,base...(base+1),165...168,"chiseled_stone_bricks")
            box(3...5,(base+2)...(base+4),167...168,"light_blue_wool")
            box(3...5,(base+5)...(base+6),167...168,"brown_terracotta")
            for x in [3,5] { block(at(x,base+6,166),"white_wool") }
            for x in [-7,7] { for z in [156,161,166] { box((x-1)...(x+1),base...base,z...z,"oak_stairs") } }
            stop(0,base,162,"The white-eyed shrine")
            corridor(at(0,base,169),at(0,base,179))
            chamber(0,base,185,8,8,5,"mossy_stone_bricks")
            for x in [-6,6] { for z in [181,185,189] {
                block(at(x,base,z),"red_bed",["facing":"north","part":"foot"])
                block(at(x,base,z-1),"red_bed",["facing":"north","part":"head"])
                block(at(x,base,z+1),"chest")
            } }
            stop(0,base,185,"Abandoned sleeping quarters")
            corridor(at(0,base,192),at(0,base-3,202))
            stop(0,base,192,"Stairs to the aqueduct")
            stop(0,base-3,202,"The lower galleries")
            chamber(0,base-3,209,9,8,7,"stone_bricks")
            box(-7...(-4),(base-4)...(base-3),202...215,"water")
            box(4...7,(base-4)...(base-3),202...215,"water")
            for x in [-3,3] { for z in 202...215 { block(at(x,base-3,z),"stone_brick_wall") } }
            stop(0,base-3,211,"The underground aqueduct")
            corridor(at(0,base-3,215),at(6,base-3,217))
            corridor(at(6,base-3,217),at(6,base-3,221))
            stop(0,base-3,215,"Beyond the water channels")
            stop(6,base-3,218,"A hidden turn in the aqueduct")
            // The false wall has a narrow, permanently explorable breach
            box(3...9,(base-3)...(base+1),220...220,"cracked_stone_bricks")
            box(5...7,(base-3)...(base-1),220...220,"air")
            corridor(at(6,base-3,221),at(6,base-3,232))
            stop(6,base-3,222,"A crack behind the false wall")
            chamber(6,base-3,246,12,12,12,"stone_bricks")
            for x in [-3,15] {for z in [238,246,254] {
                box(x...x,(base-3)...(base+6),z...z,"chiseled_stone_bricks")
                box((x-1)...(x+1),(base+7)...(base+7),(z-1)...(z+1),"stone_bricks")
                block(at(x,base+8,z),"torch",["torch_facing_direction":"top"])
                for y in (base+9)...(base+11) {block(at(x,y,z),"chain",["pillar_axis":"y"])}
            } }
            for z in [235,257] {for x in -2...14 where (x+2)%4 == 0 && abs(x-6)>2 {
                box(x...x,(base-2)...(base+1),z...z,"iron_bars")
            } }
            box(2...10,(base-4)...(base-4),242...250,"lava")
            box(3...9,(base-3)...(base-3),243...249,"stone_bricks")
            for offset in -1...1 {
                for (x,z,facing) in [(6+offset,244,"south"),(6+offset,248,"north"),(4,246+offset,"east"),(8,246+offset,"west")] {
                    block(at(x,base-2,z),"end_portal_frame",["end_portal_eye_bit":"1","facing":facing])
                }
            }
            box(5...7,(base-2)...(base-2),245...247,"end_portal")
            stop(6,base-3,240,"The grand End portal")
            stop(6,base-1,243,"Above the portal steps")
            stop(6,base-1,245,"The eyes are watching")
            route.append(Stop(point:.init(Double(record.x+6)+0.5,Double(base)-0.38,Double(record.z+246)+0.5),title:"Entering the End"))
        } else {
            chamber(0,base+3,91,16,14,16,"deepslate_tiles")
            for x in [-9,9] {for z in [82,91,100] {
                box((x-1)...(x+1),(base+3)...(base+4),(z-1)...(z+1),"chiseled_deepslate")
                box(x...x,(base+5)...(base+6),z...z,"deepslate_bricks")
                block(at(x,base+7,z),"soul_torch",["torch_facing_direction":"top"])
            } }
            for x in [-12,12] { for z in [82,91,100] {
                box((x-2)...(x+2),(base+3)...(base+9),(z-2)...(z+2),"deepslate_bricks")
                box((x-1)...(x+1),(base+3)...(base+7),(z-1)...(z+1),"air")
                box((x-1)...(x+1),(base+3)...(base+5),(z-2)...(z-2),"air")
                if random(x,z)<0.65 { block(at(x,base+10,z),"sculk") }
            } }
            for x in [-6,6] { for z in 79...103 where random(x,z)<0.5 {block(at(x,base+2,z),"sculk")} }
            stop(0,base+3,91,"Buried city ruins")
            corridor(at(0,base+3,104),at(0,base,121),true,true)
            stop(0,base+3,104,"Leaving the buried city")
            stop(0,base,121,"Broken mining rails")
            chamber(0,base,132,12,14,12,"blackstone")
            box(-9...9,(base-2)...(base-1),125...142,"lava")
            for x in -9...9 { for z in 125...142 where abs(x)<3 || z>137 || random(x,z)<0.35 { block(at(x,base-1,z),"obsidian") } }
            for z in 121...129 where z%3 != 0 {block(at(0,base,z),"rail")}
            for x in -8...(-4) {block(at(x,base,123),"redstone_wire")}
            block(at(-8,base,122),"lever"); block(at(-4,base,122),"redstone_lamp")
            stop(0,base,129,"Broken rails and dormant redstone")
            for x in -2...2 { for y in 0...5 where abs(x) == 2 || y == 0 || y == 5 {block(at(x,base+y,138),"obsidian")} }
            for x in -1...1 { for y in 1...4 {block(at(x,base+y,138),"portal",["portal_axis":"x"])} }
            stop(0,base,135,"The obsidian lava pool")
            stop(0,base+1,137,"The portal threshold")
            stop(0,base+1,139,"Entering the Nether")
        }
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
        guard let point = available.min(by:{$0.1<$1.1}) else {return nil}
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

    func approach(data original: WorldData, eye: SCNVector3, chest: Bool) -> [Stop] {
        var data = original; data.apply(blocks)
        let entrance = entrance, seed = record.seed
        var result: [Stop] = [], start = eye
        if chest {
            var chests: [Cell] = []
            for chunk in data.chunks.values {
                for section in chunk.sections.values {
                    guard let palette = section.layers.first, palette.blocks.contains(where:{$0.name == "chest"}) else {continue}
                    for x in 0..<16 { for z in 0..<16 { for y in 0..<16 where palette.block(x,y,z).name == "chest" {
                        let cell = Cell(x:chunk.key.x*16+x,y:section.y*16+y,z:chunk.key.z*16+z)
                        if data.block(cell.x,cell.y,cell.z)?.name == "chest", hypot(Double(cell.x)-eye.x,Double(cell.z)-eye.z)<64 {chests.append(cell)}
                    } } }
                }
            }
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
