import AppKit
import Foundation
import SceneKit
import CoreText
import SwiftUI

@main
struct LauncherChecks {
    @MainActor static func main() throws {
        var assetErrors = Set<String>()
        for kind in ["nether","end"] {
            let record = Trail.Record(kind:kind,x:0,y:70,z:0,seed:42), trail = Trail(record)
            precondition(trail.blocks == Trail(record).blocks && trail.route.count>8)
            precondition(trail.blocks.values.contains(where:{$0.name == (kind == "end" ? "end_portal" : "portal")}))
            precondition(trail.route.allSatisfy {$0.point.x.isFinite && $0.point.y > -64 && $0.point.y<320 && $0.point.z.isFinite})
            let decoded = try JSONDecoder().decode(Trail.Record.self,from:JSONEncoder().encode(record))
            precondition(decoded.valid)
            var terrain = WorldData(dimension:0)
            for key in Set(trail.blocks.keys.map {WorldData.key($0.x,$0.z)}) {
                terrain.chunks[key] = try VoxelChunk(key:key,dimension:0,sections:[:],biomeData:nil)
            }
            terrain.apply(trail.blocks)
            let start = SCNVector3(trail.entrance.x,trail.entrance.y+6,trail.entrance.z-10)
            let approach = trail.approach(data:terrain,eye:start,chest:false)
            let points = [start]+approach.map(\.point)+trail.route.map(\.point)
            for (a,b) in zip(points,points.dropFirst()) {
                let count = max(1,Int(ceil(hypot(hypot(b.x-a.x,b.z-a.z),b.y-a.y)*10)))
                for index in 0...count {
                    let t = Double(index)/Double(count), feet = SCNVector3(a.x+(b.x-a.x)*t,a.y+(b.y-a.y)*t-1.62,a.z+(b.z-a.z)*t)
                    precondition(terrain.vacant(feet),"Blocked portal route: \(kind) at \(feet)")
                }
            }
        }
        precondition(!Trail.Record(kind:"end",x:Int.min,y:0,z:0,seed:0).valid)
        precondition(!Block(name:"grass_block").passable && Block(name:"short_grass").passable)
        precondition(!Block(name:"mangrove_roots").passable && !Block(name:"brown_mushroom_block").passable)
        precondition(!Block(name:"end_portal_frame").passable && Block(name:"end_portal").passable)
        precondition(Crowd.attention(.villager) == 0.4 && Crowd.attention(.cow) == 0.1)
        func status(_ progress: Double?, state: String = "busy") -> Status {
            Status(state: state, title: "Fixture", detail: "", progress: progress)
        }
        let pending = try JSONDecoder().decode(Status.self,from:Data(#"{"state":"busy","title":"Opening","detail":""}"#.utf8))
        let playing = try JSONDecoder().decode(Status.self,from:Data(#"{"state":"playing","title":"Minecraft","detail":"","game_pid":42}"#.utf8))
        precondition(pending.gamePID == nil && playing.gamePID == 42)
        let session = ["PATH":"/usr/bin", "HOME":"/fixture", "BEDROCK_HOME":"/private/fixture",
                       "BEDROCK_LAUNCH_TOKEN":"nonce", "BEDROCK_WINDOW_FRAME":"0 0 1040 760",
                       "BEDROCK_WINDOW_FULLSCREEN":"0", "wine":"case-sensitive"]
        let injected = ["CX_ROOT":"/untrusted", "WINEPREFIX":"/untrusted", "WINEDEBUG":"+all",
                        "DYLD_INSERT_LIBRARIES":"/untrusted.dylib", "DYLD_LIBRARY_PATH":"/untrusted"]
        precondition(Launcher.environment(session.merging(injected) { _, new in new }) == session)
        var wheel = Scrolling()
        precondition(wheel.step(-1,precise:false,at:1) == 1)
        precondition(wheel.step(-1,precise:false,at:1.01) == 0)
        precondition(wheel.step(1,precise:false,at:1.2) == -1)
        precondition(wheel.step(.nan,precise:false,at:2) == 0)
        precondition(wheel.step(1,precise:false,at:.infinity) == 0)
        var trackpad = Scrolling()
        precondition(trackpad.step(5,precise:true,at:1) == 0)
        precondition(trackpad.step(5,precise:true,at:1.01) == 0)
        precondition(trackpad.step(3,precise:true,at:1.02) == -1)
        precondition(trackpad.step(-5,precise:true,at:2) == 0)
        precondition(trackpad.step(-8,precise:true,at:3) == 0)
        precondition(trackpad.step(-4,precise:true,at:3.01) == 1)
        for world in World.allCases {
            let chart = Minimap.image(world:world,at:.init(0,10,0))
            precondition(chart?.width == 33 && chart?.height == 33)
        }
        precondition(Minimap.image(world:.overworld,at:.init(Double.nan,0,0)) == nil)
        let emptyMap = WorldData(dimension:0)
        precondition(Minimap.image(data:emptyMap,at:.init(Double.nan,0,0)) == nil)
        precondition(Minimap.image(data:emptyMap,at:.init(0,Double.greatestFiniteMagnitude,0)) == nil)
        precondition(Minimap.image(data:emptyMap,at:.init(0,70,0))?.width == 128)
        precondition(Minimap.image(world:.overworld,at:.init(30_000_001,0,0)) == nil)
        let coloured = GameTitle.formatted("§1C§2o§3l§4o§5r§6m§7a§8t§9i§ac!")
        precondition(String(coloured.characters) == "Colormatic!" && coloured.runs.count == 10)
        precondition(GameTitle.formatted("§6Gold").runs.first?.foregroundColor == Color(red:1,green:170.0/255,blue:0))
        precondition(GameTitle.formatted("§1Blue§rReset").runs.last?.foregroundColor == .yellow)
        precondition(String(GameTitle.formatted("Unknown §x and trailing §").characters) == "Unknown §x and trailing §")
        precondition([0,0.9,1,1.7,1.8].map { Loading.frame(at:$0) } == [0,9,8,1,0])
        precondition(Loading.frame(at:.nan) == 0 && Loading.frame(at:.infinity) == 0 && Loading.frame(at:-1) == 0)
        func gameWindow(_ pid: Int = 42, layer: Int = 0, width: Int = 1040) -> [String:Any] {
            [kCGWindowOwnerPID as String:pid,kCGWindowLayer as String:layer,
             kCGWindowBounds as String:["Width":width,"Height":760]]
        }
        precondition(Launcher.gameWindow(42,windows:[gameWindow()]))
        for windows in [[],[gameWindow(43)],[gameWindow(layer:1)],[gameWindow(width:100)],[[:]]] as [[[String:Any]]] {
            precondition(!Launcher.gameWindow(42,windows:windows))
        }
        precondition(!Launcher.gameWindow(1,windows:[gameWindow(1)]))
        precondition(!Launcher.gameWindow(Int(Int32.max)+1,windows:[]))
        precondition(Launcher.frameReady(42,state:42) && !Launcher.frameReady(42,state:43))
        precondition(!Launcher.frameReady(1,state:1) && !Launcher.frameReady(-1,state:UInt64.max))
        let compactSettings = Preferences.scale(in:.init(width:700,height:560))
        let largeSettings = Preferences.scale(in:.init(width:1040,height:800))
        precondition(compactSettings >= 1 && largeSettings > compactSettings)
        precondition(Preferences.scale(in:.zero) == compactSettings)
        precondition(Preferences.scale(in:.init(width:4000,height:3000)) <= 1.5)
        let title = GameTitle.width(in:CGSize(width:1040,height:760))
        let fullscreenTitle = GameTitle.width(in:CGSize(width:2016,height:1310))
        precondition(title > 500 && fullscreenTitle > title*1.8)
        precondition(GameTitle.width(in:CGSize(width:760,height:620)) < 760-56)
        let shortTitle = GameTitle.width(in:CGSize(width:3440,height:620))
        precondition(shortTitle < fullscreenTitle && shortTitle < 620*1.3)
        precondition(GameTitle.width(in:CGSize(width:4032,height:2620)) == fullscreenTitle*2)
        let controls = LauncherView.scale(in:CGSize(width:2016,height:1310))
        precondition(abs(controls*controls-5)<0.001)
        for size in [CGSize(width:760,height:620),CGSize(width:1040,height:760),CGSize(width:2560,height:720)] {
            let scale = LauncherView.scale(in:size)
            precondition(scale >= 1 && scale < controls)
            precondition(320*scale < size.width-56)
            precondition(size.width/2+126*scale+16 < size.width-24-56*scale)
            precondition(LauncherView.scale(in:size,extra:72) <= scale)
        }
        precondition(status(nil).stage == nil)
        precondition(status(-0.1).fraction == 0)
        precondition(status(1.5).fraction == 1)
        precondition(status(.nan).fraction == nil)
        precondition(status(.infinity).fraction == nil)
        precondition(status(0.2).stage == 0)
        precondition(status(0.349).stage == 0)
        precondition(status(0.35).stage == 1)
        precondition(status(0.899).stage == 1)
        precondition(status(0.9).stage == 2)
        precondition(status(nil, state: "playing").stage == 3)
        precondition(status(0.5, state: "error").stage == nil)
        precondition(Daylight.light(at:0) == 1 && Daylight.light(at:600) == 0 && Daylight.light(at:1200) == 1)
        precondition(Daylight.rain(at:0) == 0 && Daylight.rain(at:240) == 1 && Daylight.rain(at:400) == 0 && Daylight.rain(at:.nan) == 0)
        precondition(Mobs.activity(at:0) == .work && Mobs.activity(at:100) == .celebrate)
        precondition(Mobs.activity(at:106) == .gather && Mobs.activity(at:250) == .home)
        precondition(Mobs.activity(at:300) == .sleep && Mobs.activity(at:900) == .work)
        precondition(Mobs.activity(at:0,rain:1) == .home && Mobs.activity(at:.nan) == .home)
        precondition(abs(Mobs.classicChance(daylight:1)-0.10)<0.0001)
        precondition(abs(Mobs.classicChance(daylight:0)-0.15)<0.0001)
        let hover = Landscape.pose(.meadow,at:0).eye, nextHover = Landscape.pose(.meadow,at:0.1).eye
        precondition(hypot(hover.x-nextHover.x,hover.z-nextHover.z)>0.05)
        let loop = Landscape.pose(.meadow,at:8).eye
        for area in World.allCases.flatMap(\.biomes) where area.passage == nil {
            for frame in 0...36 {
                let eye = Landscape.pose(area,at:Double(frame)/2).eye
                precondition(eye.y>Terrain(biome:area).height(eye.x.rounded(),eye.z.rounded())+0.1)
            }
        }
        precondition(hypot(hover.x-loop.x,hover.z-loop.z)<0.001)
        let river = Terrain(biome:.river)
        let swimming = SCNVector3(4+Terrain.noise(0,0,scale:32,seed:9)*9,-1.8,0)
        precondition(Mobs.walkable(from:swimming,to:swimming,species:.cod,terrain:river))
        precondition(!Mobs.walkable(from:swimming,to:swimming,species:.cow,terrain:river))
        precondition(!Mobs.walkable(from:.init(50,-1.8,0),to:.init(50,-1.8,0),species:.cod,terrain:river))
        precondition(!Mobs.walkable(from:swimming,to:swimming,species:.cod,terrain:river,ground:{ _,_ in 2 }))
        precondition(SceneryMotion.enabled(reduced: false, paused: false, lowPower: false,
                                          active: true, visible: true, playing: false))
        for disabled in 0..<6 {
            precondition(!SceneryMotion.enabled(reduced: disabled == 0, paused: disabled == 1,
                                                lowPower: disabled == 2, active: disabled != 3,
                                                visible: disabled != 4, playing: disabled == 5))
        }
        precondition(Music.enabled(muted:false,active:true,visible:true,playing:false))
        for disabled in 0..<4 {
            precondition(!Music.enabled(muted:disabled == 0,active:disabled != 1,
                                        visible:disabled != 2,playing:disabled == 3))
        }
        var shortcut = ShortcutHint()
        shortcut.focus(at:10)
        precondition(shortcut.showing && shortcut.delay(at:10) == 60)
        shortcut.advance(at:69)
        precondition(shortcut.showing)
        shortcut.advance(at:70)
        precondition(!shortcut.showing && shortcut.delay(at:70) == 70)
        shortcut.focus(at:90)
        shortcut.advance(at:159)
        precondition(!shortcut.showing)
        shortcut.advance(at:160)
        precondition(shortcut.showing && shortcut.delay(at:160) == 60)
        shortcut.focus(at:190)
        precondition(shortcut.delay(at:190) == 30)
        shortcut.focus(at:230)
        precondition(!shortcut.showing && shortcut.delay(at:230) == 70)
        shortcut.advance(at:300)
        shortcut.dismiss(at:305)
        precondition(!shortcut.showing && shortcut.delay(at:305) == 70)
        shortcut.show(at:310)
        precondition(shortcut.showing && shortcut.delay(at:310) == 60)
        let flying = FlightView(frame:.init(x:0,y:0,width:320,height:200))
        let flightScene = SCNScene(), eye = SCNNode()
        eye.camera = SCNCamera(); eye.position = .init(0,10,0)
        flightScene.rootNode.addChildNode(eye)
        flying.scene = flightScene; flying.pointOfView = eye
        flying.install(eye,area:.meadow); flying.exploring = true
        func key(_ code: UInt16, type: NSEvent.EventType = .keyDown, flags: NSEvent.ModifierFlags = []) -> NSEvent {
            NSEvent.keyEvent(with:type,location:.zero,modifierFlags:flags,timestamp:0,windowNumber:0,
                context:nil,characters:"",charactersIgnoringModifiers:"",isARepeat:false,keyCode:code)!
        }
        let defaults = Controls()
        precondition(defaults.matches(.look,event:key(37,flags:.command)))
        precondition(defaults.matches(.map,event:key(46)))
        precondition(!defaults.matches(.map,event:key(46,flags:.command)))
        precondition(defaults.pressed(.forward,keys:[13],modifiers:[.control,.shift]))
        precondition(defaults.pressed(.sprint,keys:[13],modifiers:.control))
        precondition(defaults.pressed(.descend,keys:[],modifiers:.shift))
        precondition(Controls(data:Data("invalid".utf8)) == defaults)
        precondition(Controls(data:Data(repeating:0,count:16_385)) == defaults)
        var remapped = defaults
        remapped.assign(.init(code:2),to:.forward)
        precondition(remapped.key(.forward).code == 2 && remapped.key(.right).code == 13)
        precondition(Controls(data:remapped.data) == remapped)
        let preserved = remapped
        remapped.assign(.init(code:53),to:.map)
        remapped.assign(.init(code:12,modifiers:.command),to:.map)
        precondition(remapped == preserved)
        remapped.assign(.init(code:60),to:.map)
        precondition(remapped.key(.map).code == 56 && remapped.key(.descend).code == 46)
        precondition(remapped.matches(.map,event:key(60,type:.flagsChanged,flags:.shift)))
        precondition(!remapped.matches(.map,event:key(60,type:.flagsChanged)))
        flying.keyDown(with:key(13))
        flying.advance(seconds:0.1)
        precondition(abs(eye.position.z+1.6)<0.001 && eye.position.x == 0)
        flying.keyDown(with:key(2))
        let before = eye.position
        flying.advance(seconds:10)
        precondition(abs(hypot(eye.position.x-before.x,eye.position.z-before.z)-1.6)<0.001)
        flying.stop(); precondition(flying.keys.isEmpty)
        flying.keyDown(with:key(49)); flying.advance(seconds:0.1)
        precondition(abs(eye.position.y-11.6)<0.001)
        flying.keyUp(with:key(49,type:.keyUp))
        flying.flagsChanged(with:key(56,type:.flagsChanged,flags:.shift)); flying.advance(seconds:0.1)
        precondition(abs(eye.position.y-10)<0.001)
        flying.stop()
        flying.flagsChanged(with:key(59,type:.flagsChanged,flags:.control))
        flying.keyDown(with:key(13,flags:.control))
        let sprint = eye.position
        flying.advance(seconds:0.1)
        precondition(abs(hypot(eye.position.x-sprint.x,eye.position.z-sprint.z)-3.2)<0.001)
        flying.stop()
        flying.keyDown(with:key(124)); flying.advance(seconds:0.1)
        precondition(-eye.simdWorldTransform.columns.2.x > 0)
        flying.stop()
        flying.keyDown(with:key(126)); flying.advance(seconds:0.1)
        precondition(-eye.simdWorldTransform.columns.2.y > 0)
        flying.stop()
        var arrowBinding = defaults
        arrowBinding.assign(.init(code:126),to:.forward)
        flying.controls = arrowBinding
        let customFront = eye.simdWorldTransform.columns.2, customStart = eye.simdWorldPosition
        flying.keyDown(with:key(126)); flying.advance(seconds:0.1)
        precondition(abs(simd_distance(eye.simdWorldPosition,customStart)-1.6)<0.001)
        precondition(simd_length(eye.simdWorldTransform.columns.2-customFront)<0.001,"A rebound arrow must not turn and move at once")
        flying.stop(); flying.controls = defaults
        var chordBinding = defaults
        chordBinding.assign(.init(code:13,modifiers:.option),to:.forward)
        flying.controls = chordBinding
        let chordStart = eye.simdWorldPosition
        flying.keyDown(with:key(13)); flying.advance(seconds:0.1)
        precondition(simd_distance(eye.simdWorldPosition,chordStart)<0.001)
        flying.flagsChanged(with:key(58,type:.flagsChanged,flags:.option)); flying.advance(seconds:0.1)
        precondition(abs(simd_distance(eye.simdWorldPosition,chordStart)-1.6)<0.001,"Movement chords must work when the letter is pressed first")
        flying.stop(); flying.controls = defaults
        var trips = 0
        flying.travel = { step in precondition(step == 1); trips += 1 }
        flying.visit(1); precondition(trips == 1)
        let eastEdge = Double(Region.span/2)-0.5, southEdge = Double(Region.span/2)-32.5
        precondition(Atlas.index(at:.init(eastEdge-0.01,0,0),count:25) == 0 && Atlas.index(at:.init(eastEdge+0.01,0,0),count:25) == 1)
        precondition(Atlas.index(at:.init(0,0,southEdge+0.01),count:25) == 5)
        precondition(Atlas.index(at:.init(-999,0,0),count:25) == nil && Atlas.index(at:.init(99999,0,0),count:25) == nil)
        for world in World.allCases {
            for index in world.biomes.indices {
                let origin = Atlas.offset(index,count:world.biomes.count)
                precondition(Atlas.index(at:origin,count:world.biomes.count) == index)
                for other in Atlas.neighbours(index,count:world.biomes.count) {
                    precondition(Atlas.neighbours(other,count:world.biomes.count).contains(index))
                }
            }
        }
        var edgeHeights = Set<Double>()
        for z in stride(from:-112.0,through:48,by:4) {
            let west = Terrain.sample(world:.overworld,at:.init(95,20,z))
            let east = Terrain.sample(world:.overworld,at:.init(96,20,z))
            edgeHeights.insert(west.height)
            precondition(abs(west.height-east.height)<=4,"Biome boundaries must join without an abrupt cliff")
        }
        precondition(edgeHeights.count>1,"Biome boundaries must retain natural relief")
        var grassland = 0, riverbed = Set<String>()
        for x in stride(from:-80.0,through:80,by:2) { for z in stride(from:-110.0,through:40,by:2) {
            let sample = Terrain.sample(world:.overworld,at:.init(x,20,z))
            if sample.biome.surface == "grass_block" && sample.height>=1 {
                precondition(sample.surface == "grass_block","Ordinary dry grassland must not become gravel")
                grassland += 1
            } else if sample.fluid { riverbed.insert(sample.surface) }
        } }
        precondition(grassland>1000 && ["gravel","sand","clay","dirt"].allSatisfy(riverbed.contains))
        let outskirts = (-30...(-5)).flatMap { x in (-20...20).map { Region(x:x,z:$0) } }
        var changedSeed = false
        for seed in [0,-1,1234567,Int.min,Int.max] {
            for key in -20..<26 {
                let region = Region.from(key,count:26,seed:seed)
                precondition(Region.at(region.origin,seed:seed) == region)
                precondition(Region.from(region.key(26),count:26,seed:seed) == region)
            }
            for x in -12 ... -5 {
                let point = SCNVector3(Double(x*Region.span+19),20,-Double(Region.span*3)+30)
                let a = Terrain.sample(world:.overworld,at:point,seed:seed), b = Terrain.sample(world:.overworld,at:point,seed:seed)
                precondition(a.height == b.height && a.surface == b.surface && a.biome == b.biome)
                let original = Terrain.sample(world:.overworld,at:point)
                changedSeed = changedSeed || a.height != original.height || a.biome != original.biome
            }
        }
        precondition(changedSeed,"Different seeds must change the procedural outskirts")
        let landmarks = outskirts.filter { $0.landmark(.overworld) }.count
        let climates = Set(outskirts.map { $0.biome(.overworld) })
        let repeats = outskirts.filter { $0.biome(.overworld) == Region(x:$0.x+1,z:$0.z).biome(.overworld) }.count
        precondition((100...300).contains(landmarks) && climates.count>7 && repeats>100)
        precondition(World.overworld.biomes.indices.allSatisfy { Region.from($0,count:World.overworld.biomes.count).landmark(.overworld) })
        let wilderness = Terrain(biome:.meadow,authored:false)
        precondition(wilderness.plots.isEmpty && !wilderness.paved(0,0) && !wilderness.reserved(0,-16))
        for area in World.overworld.biomes where area.level<0 {
            let index = World.overworld.biomes.firstIndex(of:area)!, p = Atlas.offset(index,count:World.overworld.biomes.count)
            let cave = Terrain.sample(world:.overworld,at:.init(p.x,-56,p.z))
            let surface = Terrain.sample(world:.overworld,at:.init(p.x,20,p.z))
            precondition(cave.biome == area && cave.height < -32)
            precondition(!surface.biome.underground && surface.height>cave.height+20)
        }
        for index in 0..<25 {
            let before = Atlas.offset(index,count:25), after = Atlas.offset(index,count:26)
            precondition(before.x == after.x && before.z == after.z)
        }
        let meadow = Terrain(biome:.meadow)
        precondition(meadow.paved(0,0) && meadow.occupied(0,0) && !meadow.paved(45,40))
        var exited = false
        flying.finish = { exited = true }; flying.keyDown(with:key(53))
        precondition(exited && flying.keys.isEmpty)
        flying.dispose(); precondition(flying.controller.pointOfView == nil)
        var roaming = Journey()
        roaming.travel(-1)
        precondition(roaming.biome == World.overworld.biomes.count-1 && roaming.passage == nil)
        roaming.travel(1)
        precondition(roaming.biome == 0 && roaming.world == .overworld)
        let releases = [
            AppRelease(tag_name: "v1", html_url: URL(string: "https://github.com/keys-i/minecraft-mac/releases/tag/v1")!, assets: [.init(name: "App.dmg")]),
            AppRelease(tag_name: "v1", html_url: URL(string: "https://example.com/releases/tag/v1")!, assets: [.init(name: "App.dmg")]),
            AppRelease(tag_name: "v1", html_url: URL(string: "https://github.com/other/repo/releases/tag/v1")!, assets: [.init(name: "App.dmg")]),
            AppRelease(tag_name: "v1", html_url: URL(string: "https://github.com/keys-i/minecraft-mac/releases/tag/v1")!, assets: [.init(name: "source.tar.gz")])
        ]
        precondition(releases.map(\.hasInstaller) == [true, false, false, false])
        func rejects(_ operation: () throws -> Void) {
            var rejected = false
            do { try operation() } catch { rejected = true }
            precondition(rejected)
        }
        var bytes = Data([0x7D,0x27,0x25,0xB1,0xA0,0x52,0x70,0x26,1,0,0,0,1,0,0,0])
        bytes.append(5)
        bytes.append(contentsOf: "a.png".utf8)
        bytes.append(Data(count:242))
        bytes.append(Data([0,0,0,0,3,0,0,0,1,2,3]))
        let archive = try Archive(bytes)
        precondition(archive["a.png"] == Data([1,2,3]))
        rejects { _ = try Archive(bytes.dropLast()) }
        bytes[12] = 2
        rejects { _ = try Archive(bytes) }
        let nbt = Data([10,0,0,3,0,1,110,0,0,0,42,0])
        let plainNBT = try NBT.read(nbt)
        precondition(plainNBT["n"] as? Int == 42)
        let littleNBT = Data([10,0,0,3,1,0,110,42,0,0,0,0])
        let littleValue = try NBT.read(littleNBT,littleEndian:true)
        precondition(littleValue["n"] as? Int == 42)
        var paletteOffset = 0
        let paletteNBT = littleNBT+littleNBT
        let paletteFirst = try NBT.decode(paletteNBT,offset:&paletteOffset,littleEndian:true)
        precondition(paletteFirst["n"] as? Int == 42)
        precondition(paletteOffset == littleNBT.count)
        let paletteSecond = try NBT.decode(paletteNBT,offset:&paletteOffset,littleEndian:true)
        precondition(paletteSecond["n"] as? Int == 42)
        precondition(paletteOffset == paletteNBT.count)
        rejects { _ = try NBT.read(littleNBT+littleNBT,littleEndian:true) }
        let compressedNBT = try NBT.read(Data(base64Encoded:"H4sIAAAAAAAA/+NiYGBmYMxjYGDQYgAAfbuNUwwAAAA=")!)
        precondition(compressedNBT["n"] as? Int == 42)
        rejects { _ = try NBT.read(nbt.dropLast()) }
        rejects { _ = try NBT.read(nbt+Data([0])) }
        rejects { _ = try NBT.read(Data([10,0,0,9,0,1,108,1,255,255,255,255,0])) }
        var mesh = Voxels()
        let automaticDoor = Door(); automaticDoor.geometry = SCNBox(width:1,height:2,length:0.1875,chamferRadius:0)
        automaticDoor.swing = -.pi/2
        automaticDoor.axis = .init(1,0,0)
        let copy = automaticDoor.clone(); precondition(copy.swing == automaticDoor.swing)
        precondition(copy.axis.x == 1)
        automaticDoor.approach(.init(0,1,1)); precondition(automaticDoor.action(forKey:"door") != nil)
        let doorway = SCNScene(); copy.categoryBitMask = 2; doorway.rootNode.addChildNode(copy)
        let doorRenderer = SCNRenderer(device:nil,options:nil); doorRenderer.scene = doorway
        precondition(doorRenderer.prepare(doorway,shouldAbortBlock:nil)); SCNTransaction.flush()
        func throughDoor() -> Bool { Collision.clear(doorway.rootNode,from:.init(-2,0,0),to:.init(2,0,0),radius:0.1) }
        precondition(!throughDoor())
        Door.clearance(doorway.rootNode) {
            precondition(throughDoor())
            Door.clearance(doorway.rootNode) { precondition(throughDoor()) }
            precondition(throughDoor())
        }
        precondition(!throughDoor()); doorRenderer.scene = nil
        mesh.cube(.init(1,1,1),at:.init(0,0,0),material:SCNMaterial(),faces:1,
                  textureUV:Array(repeating:CGRect(x:0,y:0.75,width:0.5,height:-0.5),count:6))
        precondition(mesh.uv[0].y == 0.75 && mesh.uv[2].y == 0.25)
        var obstacle = Voxels()
        obstacle.cube(.init(1,4,8),at:.init(1,2,0),material:SCNMaterial())
        let obstacleScene = SCNScene(), walls = obstacleScene.rootNode
        walls.addChildNode(obstacle.node("wall"))
        let collision = SCNRenderer(device:nil,options:nil)
        collision.scene = obstacleScene
        precondition(collision.prepare(obstacleScene,shouldAbortBlock:nil))
        precondition(!Collision.vacant(walls,at:.init(1,2,0)))
        precondition(Collision.vacant(walls,at:.init(-2,2,0)))
        precondition(!Collision.clear(walls,from:.init(-2,1,0),to:.init(3,1,0)))
        precondition(!Collision.clear(walls,from:.init(3,1,0),to:.init(-2,1,0)))
        precondition(Collision.clear(walls,from:.init(-2,5,0),to:.init(3,5,0)))
        let slide = Collision.move(walls,from:.init(-1,1,0),to:.init(3,1,2))
        precondition(slide.x < 0.5 && abs(slide.z-2)<0.001)
        let immersion = SCNScene()
        Landscape.medium(immersion,area:.wastes,eye:.init(4,0,-6))
        precondition(immersion.fogStartDistance == 0 && immersion.fogEndDistance == 1.5)
        Landscape.medium(immersion,area:.wastes,eye:.init(4,8,-6))
        precondition(immersion.fogStartDistance == 38 && immersion.fogEndDistance == 100)

        let fixture = FileManager.default.temporaryDirectory.appendingPathComponent("minecraft-art-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:fixture.appendingPathComponent("resource_packs/vanilla"),withIntermediateDirectories:true)
        try FileManager.default.createDirectory(at:fixture.appendingPathComponent("behavior_packs/vanilla"),withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:fixture) }
        let skinPixels = NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:64,pixelsHigh:64,bitsPerSample:8,
            samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
        let skinFile = fixture.appendingPathComponent("skin.png")
        try skinPixels.representation(using:.png,properties:[:])!.write(to:skinFile)
        let decodedSkin = try Skin.image(at:skinFile)
        precondition(decodedSkin.width == 64)
        rejects { _ = try Skin.image(at:skinFile,cape:true) }
        let capePixels = NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:64,pixelsHigh:32,bitsPerSample:8,
            samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
        let capeFile = fixture.appendingPathComponent("cape.png")
        try capePixels.representation(using:.png,properties:[:])!.write(to:capeFile)
        let decodedCape = try Skin.image(at:capeFile,cape:true), legacySkin = try Skin.image(at:capeFile)
        precondition(decodedCape.height == 32 && legacySkin.height == 32)
        rejects { _ = try Skin.image(at:fixture.appendingPathComponent("missing.png")) }
        try Data("not a PNG".utf8).write(to:skinFile)
        rejects { _ = try Skin.image(at:skinFile) }
        try Data(count:4*1024*1024).write(to:skinFile)
        rejects { _ = try Skin.image(at:skinFile) }
        func write(_ path: String, _ object: Any) throws {
            let url = fixture.appendingPathComponent("resource_packs/vanilla/"+path)
            try FileManager.default.createDirectory(at:url.deletingLastPathComponent(),withIntermediateDirectories:true)
            try JSONSerialization.data(withJSONObject:object).write(to:url)
        }
        let pixels = NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:2,pixelsHigh:2,bitsPerSample:8,
                                      samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
        for x in 0..<2 { for y in 0..<2 { pixels.setColor(NSColor(deviceRed:1,green:1,blue:1,alpha:1),atX:x,y:y) } }
        let texture = fixture.appendingPathComponent("resource_packs/vanilla/textures/entity")
        pixels.setColor(NSColor(deviceRed:0,green:0,blue:0,alpha:0),atX:0,y:0)
        try FileManager.default.createDirectory(at:texture,withIntermediateDirectories:true)
        try pixels.representation(using:.png,properties:[:])!.write(to:texture.appendingPathComponent("fixture.png"))
        try write("entity/fixture.entity.json",["minecraft:client_entity":["description":["geometry":["default":"geometry.fixture","warm":"geometry.fixture.warm","baby":"geometry.fixture.baby"],"textures":["default":"textures/entity/fixture","warm":"textures/entity/fixture","baby":"textures/entity/fixture"]]]])
        try write("models/entity/baby_fixture.geo.json",["minecraft:geometry":[["description":["identifier":"geometry.fixture.baby","texture_width":2,"texture_height":2],
            "bones":[["name":"body","cubes":[["origin":[0,0,0],"size":[1,1,1],"uv":[0,0]]]]]]]])
        try write("models/entity/fixture_warm.geo.json",["geometry.fixture.warm":["texturewidth":2,"textureheight":2,
            "bones":[["name":"body","cubes":[["origin":[0,0,0],"size":[2,1,1],"uv":[0,0]]]]]]])
        func model(_ bones: [[String:Any]]) throws {
            try write("models/entity/fix_ture.geo.json",["geometry.fixture":["texturewidth":2,"textureheight":2,"bones":bones]])
        }
        let cube: [String:Any] = ["origin":[0,0,0],"size":[1,1,1],"uv":[0,0]]
        try model([["name":"Body","pivot":[0,16,0],"bind_pose_rotation":[90,0,0],"cubes":[cube]],
                   ["name":"head","parent":"body","pivot":[0,32,0],"cubes":[cube]]])
        for (version,value) in [("1.9",9),("1.10",10)] {
            let pack = fixture.appendingPathComponent("resource_packs/vanilla_"+version)
            try FileManager.default.createDirectory(at:pack,withIntermediateDirectories:true)
            try Data([UInt8(value)]).write(to:pack.appendingPathComponent("precedence"))
        }
        let art = try Assets(data:fixture)
        let infant = try art.actor("fixture",baby:true)
        precondition(abs(infant.boundingBox.max.x-infant.boundingBox.min.x-1.0/16)<0.001)
        try write("biomes_client.json",["biomes":["default":["water_surface_color":"#44AFF5","water_surface_transparency":0.65],
            "minecraft:river":["water_surface_color":"#0084FF","water_surface_transparency":0.8]]])
        let defaultWater = try art.water(.meadow), tintedWater = try art.water(.river)
        precondition(defaultWater.colour == 0x44AFF5 && defaultWater.opacity == 0.65)
        precondition(tintedWater.colour == 0x0084FF && tintedWater.opacity == 0.8)
        try write("biomes_client.json",["biomes":["default":["water_surface_transparency":1.1]]])
        rejects { _ = try Assets(data:fixture).water(.meadow) }
        let menus = Launcher(status:.init(state:"ready",title:"Ready",detail:"",progress:nil),background:NSImage(),assets:art)
        menus.showSettings(); precondition(menus.settings && !menus.help)
        let delegate = AppDelegate(); delegate.launcher = menus
        let bridgeResources = fixture.appendingPathComponent("runtime/wine")
        try FileManager.default.createDirectory(at:bridgeResources,withIntermediateDirectories:true)
        try JSONSerialization.data(withJSONObject:["handoff_patch_sha256":String(repeating:"a",count:64)])
            .write(to:bridgeResources.appendingPathComponent("dxmt-unix-bridge.json"))
        let launched = Process(); launched.environment = ["EXISTING":"kept"]
        menus.preparePresentation(launched,resources:fixture)
        precondition(launched.environment?["EXISTING"] == "kept" && UUID(uuidString:launched.environment?["BEDROCK_LAUNCH_TOKEN"] ?? "") != nil)
        menus.preparePresentation(Process(),resources:fixture.appendingPathComponent("missing"))
        for digest in ["bad",String(repeating:"g",count:64),String(repeating:"Ａ",count:64)] {
            try JSONSerialization.data(withJSONObject:["handoff_patch_sha256":digest])
                .write(to:bridgeResources.appendingPathComponent("dxmt-unix-bridge.json"))
            let rejected = Process(); rejected.environment = [:]
            menus.preparePresentation(rejected,resources:fixture)
            precondition(rejected.environment?["BEDROCK_LAUNCH_TOKEN"] == nil)
        }
        menus.running = true
        menus.status = status(nil,state:"playing")
        precondition(delegate.applicationShouldTerminate(NSApplication.shared) == .terminateNow)
        menus.running = false
        menus.opening = true; menus.running = true
        for state in ["busy","checking","playing","cancelling"] {
            menus.status = status(nil,state:state); precondition(menus.loading)
        }
        for state in ["ready","new","error","cancelled"] {
            menus.status = status(nil,state:state); precondition(!menus.loading)
        }
        menus.status = status(nil); menus.opening = false
        precondition(!menus.loading)
        menus.running = false
        menus.showHelp(); precondition(menus.help && !menus.settings)
        menus.showSettings(); precondition(menus.settings && !menus.help)
        let behaviours = fixture.appendingPathComponent("behavior_packs/vanilla/entities")
        try FileManager.default.createDirectory(at:behaviours,withIntermediateDirectories:true)
        let absent = try Mobs(assets:art).locomotion(.pig)
        precondition(absent.speed == 0.8 && absent.width == 0.6 && absent.height == 1.8)
        for value in [0,-1,true,"invalid",["range_min":0.1,"range_max":0.3],["range_min":0.3,"range_max":0.1]] as [Any] {
            let entity: [String:Any] = ["minecraft:entity":["components":["minecraft:movement":["value":value],"minecraft:collision_box":["width":0.5,"height":1.8]]]]
            try JSONSerialization.data(withJSONObject:entity).write(to:behaviours.appendingPathComponent("pig.json"))
            if let number = value as? Int, !(value is Bool), number == 0 {
                let still = try Mobs(assets:Assets(data:fixture)).locomotion(.pig)
                precondition(still.speed == 0 && still.width == 0.5)
            } else if let range = value as? [String:Double], range["range_min"] == 0.1 {
                let varied = try Mobs(assets:Assets(data:fixture)).locomotion(.pig)
                precondition(abs(varied.speed-0.8)<0.001)
            } else { rejects { _ = try Mobs(assets:Assets(data:fixture)).locomotion(.pig) } }
        }
        for groups in [NSNull(),42] as [Any] {
            let entity: [String:Any] = ["minecraft:entity":["components":["minecraft:movement":["value":0]],"component_groups":groups]]
            try JSONSerialization.data(withJSONObject:entity).write(to:behaviours.appendingPathComponent("pig.json"))
            if groups is NSNull {
                let valid = try Mobs(assets:Assets(data:fixture)).locomotion(.pig)
                precondition(valid.speed == 0)
            } else { rejects { _ = try Mobs(assets:Assets(data:fixture)).locomotion(.pig) } }
        }
        let tinted = try art.texture("textures/entity/fixture",tint:0x2080E0)
        let bitmap = tinted.diffuse.contents as! CGImage
        let rgba = Array(bitmap.dataProvider!.data! as Data)
        let tintSamples = stride(from:0,to:rgba.count,by:4).map { Array(rgba[$0..<$0+4]) }
        precondition(tintSamples.contains([32,128,224,255]) && tintSamples.contains(where: { $0[3] == 0 }),"Tinted RGBA: \(tintSamples)")
        let warm = try art.actor("fixture",texture:"warm")
        precondition(abs(warm.boundingBox.max.x-warm.boundingBox.min.x-0.125)<0.001)
        for blend in [false,true] {
            try write("materials/entity.material",["materials":["entity_alphatest:base":["+states":blend ? ["Blending"] : []],"base":["+defines":blend ? [] : ["USE_COLOR_MASK"]]]])
            let model = try Assets(data:fixture).actor("fixture")
            let material = model.childNode(withName:"head",recursively:true)!.geometry!.firstMaterial!
            precondition(material.blendMode == (blend ? .alpha : .replace))
            if !blend { precondition(material.shaderModifiers?[.fragment]?.contains("discard") == false) }
        }
        try write("materials/entity.material",["materials":["entity_alphatest:entity_alphatest":[:]]])
        rejects { _ = try Assets(data:fixture).actor("fixture") }
        try FileManager.default.removeItem(at:fixture.appendingPathComponent("resource_packs/vanilla/materials/entity.material"))
        let silent = Data(base64Encoded:"UklGRiQAAABXQVZFZm10IBAAAAABAAEAQB8AAIA+AAACABAAZGF0YQAAAAA=")!
        var wave = silent
        let samples = Data(count:16000)
        wave.append(samples)
        func size(_ number: UInt32, at offset: Int) {
            var little = number.littleEndian
            withUnsafeBytes(of:&little) { wave.replaceSubrange(offset..<offset+4,with:$0) }
        }
        size(UInt32(wave.count-8),at:4); size(UInt32(samples.count),at:40)
        let songs = fixture.appendingPathComponent("resource_packs/vanilla/sounds/music/menu")
        try FileManager.default.createDirectory(at:songs,withIntermediateDirectories:true)
        try wave.write(to:songs.appendingPathComponent("fixture.ogg"))
        let music = Music()
        music.update(assets:art,active:true,volume:0)
        let musicLimit = Date().addingTimeInterval(5)
        while music.pending && Date() < musicLimit { RunLoop.main.run(until:Date().addingTimeInterval(0.01)) }
        precondition(music.isPlaying && music.title == "Fixture")
        music.update(assets:art,active:false,volume:0)
        precondition(!music.isPlaying && !music.pending)
        music.update(assets:art,active:true,volume:0)
        precondition(music.isPlaying)
        music.stop(); precondition(!music.isPlaying && !music.pending)
        music.update(assets:art,active:true,volume:0); music.stop()
        art.queue.waitUntilAllOperationsAreFinished()
        RunLoop.main.run(until:Date().addingTimeInterval(0.02))
        precondition(!music.isPlaying && !music.pending)
        precondition(art.resources.map(\.lastPathComponent) == ["vanilla","vanilla_1.9","vanilla_1.10"])
        let latest = try art.file("precedence")
        precondition(latest == Data([10]))
        let pack = fixture.appendingPathComponent("resource_packs/vanilla")
        try FileManager.default.createDirectory(at:pack.appendingPathComponent("__brarchive"),withIntermediateDirectories:true)
        try FileManager.default.createDirectory(at:pack.appendingPathComponent("folder"),withIntermediateDirectories:true)
        var stub = bytes.dropLast(3)
        stub[12] = 1; stub[268] = 0
        try stub.write(to:pack.appendingPathComponent("__brarchive/folder.brarchive"))
        try Data([9]).write(to:pack.appendingPathComponent("folder/a.png"))
        let fallback = try art.file("folder/a.png")
        precondition(fallback == Data([9]))
        let actor = try art.actor("fixture")
        let head = actor.childNode(withName:"head",recursively:true)!
        precondition(abs(head.worldPosition.y-2) < 0.0001 && abs(head.worldPosition.z) < 0.0001)
        try model([["name":"sheet","cubes":[["origin":[0,0,0],"size":[1,0,1],"uv":["down":["uv":[0,0],"uv_size":[1,1]]]]]]])
        let sheet = try Assets(data:fixture).actor("fixture").childNode(withName:"sheet",recursively:true)!
        precondition(sheet.geometry!.elements.reduce(0) { $0+$1.primitiveCount } == 2)
        try model([["name":"a","parent":"b"],["name":"b","parent":"a"]])
        rejects { _ = try Assets(data:fixture).actor("fixture") }
        try model([["name":"a","parent":"missing"]])
        rejects { _ = try Assets(data:fixture).actor("fixture") }
        try model([["name":"a","cubes":[["origin":[0,0,0],"size":[1,1,1],"uv":["north":["uv":[0],"uv_size":[1,1]]]]]]])
        rejects { _ = try Assets(data:fixture).actor("fixture") }
        try model([["name":"a","pivot":[1],"cubes":[cube]]])
        rejects { _ = try Assets(data:fixture).actor("fixture") }
        rejects { _ = try art.file("../account") }
        rejects { _ = try art.file("/account") }
        var cancelledDelivered = false, failureDelivered = false
        art.queue.isSuspended = true
        let obsolete = art.load(.overworld,biome:0,passage:nil) { _ in cancelledDelivered = true }
        obsolete.cancel()
        art.load(.overworld,biome:0,passage:nil) { result in
            precondition(Thread.isMainThread)
            if case .failure = result { failureDelivered = true }
        }
        art.queue.isSuspended = false
        let deadline = Date().addingTimeInterval(3)
        while !failureDelivered && Date() < deadline { RunLoop.main.run(until:Date().addingTimeInterval(0.01)) }
        precondition(failureDelivered && !cancelledDelivered)
        print("Original synthetic archive, NBT, UV, bind pose, parent and malformed-model fixtures passed")
        precondition(Landscape.height(.lush, x: 9, z: 7, centre: 0) < 0)
        precondition(Landscape.height(.coast, x: 1, z: -10, centre: 0) < 0)
        precondition(Landscape.height(.coast, x: 1, z: 8, centre: 0) > 0)
        let roster = Set(World.allCases.flatMap { $0.biomes.flatMap(\.residents) })
        precondition(roster == Set(Species.allCases))
        precondition(World.overworld.biomes.count == 26 && World.nether.biomes.count == 5)
        precondition(Terrain(biome:.meadow).reserved(1,5))
        let village = Terrain(biome:.meadow)
        for plot in village.plots {
            let level = village.height(plot.midX,plot.midY)
            precondition(village.occupied(plot.midX,plot.midY))
            for x in [plot.midX-1,plot.midX+1] { for z in [plot.midY-1,plot.midY+1] {
                precondition(village.height(x,z) == level)
            } }
        }
        precondition(!village.occupied(24,6) && !village.reserved(24,6))
        var journey = Journey()
        for _ in 0..<18 { journey.tick(rotate: false) }
        precondition(journey.biome == 0 && journey.elapsed == 0)
        for _ in 0..<18 { journey.tick(rotate: true) }
        precondition(journey.biome == 1)
        journey.area(999)
        for _ in 0..<18 { journey.tick(rotate: true) }
        precondition(journey.world == .nether && journey.passage == .mine && journey.biome == 0)
        for _ in 0..<Passage.mine.duration { journey.tick(rotate: false) }
        precondition(journey.passage == nil && journey.elapsed == 0)
        journey.select(.end, animated: true)
        precondition(journey.passage == .stronghold)
        journey.select(.sift, animated: true)
        precondition(journey.passage == .rift && journey.elapsed == 0)
        journey.area(-1)
        precondition(journey.passage == nil && journey.biome == 0)
        journey.select(.nether, animated: false)
        precondition(journey.passage == nil && journey.world == .nether)
        journey.select(.end, animated: true)
        journey.skip()
        precondition(journey.passage == nil && journey.world == .end)
        for passage in [Passage.mine, .stronghold, .rift] {
            let first = passage.pose(at: -1), last = passage.pose(at: 999)
            precondition(first.eye.z > last.eye.z)
            for tick in 0...(passage.duration*10) {
                let pose = passage.pose(at: Double(tick) / 10)
                precondition(pose.eye.x.isFinite && pose.eye.y.isFinite && pose.eye.z.isFinite)
                if tick > 0 {
                    let before = passage.pose(at: Double(tick - 1) / 10)
                    precondition(abs(pose.eye.z - before.eye.z) < 1.5)
                }
            }
        }
        print("Progress, motion gates, selection, cancellation and journey paths passed")
        guard let data = ProcessInfo.processInfo.environment["BEDROCK_SCENERY_DATA"] else {
            print("Installed-art integration skipped; set BEDROCK_SCENERY_DATA to your game/data directory")
            return
        }
        let assets = try Assets(data:URL(fileURLWithPath:data)), factory = Mobs(assets:try Assets(data:URL(fileURLWithPath:data)))
        do {
            let chart = Chart(), view = FlightView(frame:.zero), scene = SCNScene(), camera = SCNNode()
            camera.name = "camera"; camera.camera = SCNCamera(); scene.rootNode.addChildNode(camera)
            view.scene = scene; view.pointOfView = camera
            let coordinator = Expedition.Coordinator(chart:chart,assets:assets,root:URL(fileURLWithPath:"/nonexistent-minecraft-fixture"))
            coordinator.view = view; coordinator.world = .overworld; coordinator.initial = false
            let centre = Chunk(x:32,z:32)
            for dx in -8...8 {for dz in -8...8 {
                let key = Chunk(x:centre.x+dx,z:centre.z+dz)
                coordinator.data.chunks[key] = try VoxelChunk(key:key,dimension:0,sections:[:],biomeData:nil); coordinator.wanted.insert(key)
            } }
            coordinator.region = centre; camera.position = .init(520.5,22.62,520.5); camera.eulerAngles = .init(-0.2,0.8,0)
            coordinator.populated = camera.position; coordinator.home = .init(10,4,10)
            var returned: World?
            coordinator.arrived = {returned = $0}; coordinator.pending = (.end,0)
            coordinator.route = [.init(point:.init(525.5,22.62,525.5),title:"Fixture")]
            view.exploring = true; coordinator.advance(1.0/60)
            precondition(returned == .overworld && coordinator.pending == nil && coordinator.route.isEmpty,"Entering Look around must cancel the cinematic in the current world")
            camera.position = .init(525.5,26.62,525.5); coordinator.populated = camera.position
            let before = camera.position, direction = camera.convertVector(.init(0,0,-1),to:nil)
            view.exploring = false; coordinator.advance(1.0/60)
            let after = camera.position, retained = camera.convertVector(.init(0,0,-1),to:nil)
            // SceneKit stores positions as Float even though its Mac API exposes Double
            let precision = [before.x,before.y,before.z].map {Double(Float($0).ulp)}.max()!*sqrt(3)
            precondition(hypot(hypot(after.x-before.x,after.z-before.z),after.y-before.y)<=0.02+precision,"Leaving Look around must retain the camera and obey the hover speed budget")
            precondition(direction.x*retained.x+direction.y*retained.y+direction.z*retained.z>0.999,"Leaving Look around must retain the viewing direction")
            var grass: [Cell:Block] = [:]
            for x in 470...570 {for z in 470...570 {grass[Cell(x:x,y:20,z:z)] = Block(name:"grass_block")}}
            var terrain = coordinator.data; terrain.apply(grass)
            let crowd = try Crowd(data:terrain,at:.init(520.5,22.62,520.5),assets:assets)
            let resident = crowd.residents.first(where:{$0.head != nil && !$0.species.flying && !$0.species.swimming})!
            resident.actor.position = .init(520.5,21,520.5); resident.actor.eulerAngles = .init(0,0,0)
            resident.target = .init(525.5,21,520.5); resident.wait = 2; resident.glance = 0; resident.watching = true
            crowd.advance(1.0/30,data:terrain,observer:.init(516.5,22.62,520.5))
            let delta = resident.actor.position.x-520.5
            precondition(delta>0 && delta*sin(resident.actor.eulerAngles.y)>0,"Camera attention must never reverse a walking mob")
            resident.target = nil; resident.wait = 4; resident.watching = true; resident.glance = 0
            let head = resident.head!, original = head.eulerAngles
            let point = head.presentation.worldPosition
            crowd.advance(1.0/30,data:terrain,observer:.init(point.x+8,point.y+1,point.z+4))
            precondition(abs(head.eulerAngles.y-original.y)+abs(head.eulerAngles.x-original.x)>0.0001,"An attentive resident must turn its head towards the observer")
            crowd.advance(1.0/30,data:terrain,visible:{_ in false})
            precondition(crowd.residents.allSatisfy {$0.actor.isHidden},"Residents wait for their terrain mesh to become visible")
            crowd.advance(1.0/30,data:terrain,visible:{_ in true})
            precondition(crowd.residents.contains {!$0.actor.isHidden},"Residents return as their terrain is drawn")
            coordinator.dispose()
        }
        let waxed = try assets.tiles("waxed_copper"), plain = try assets.tiles("copper_block"), links = try assets.tiles("iron_chain")
        precondition(waxed[0] === plain[0] && links[0].diffuse.contents != nil)
        var chain = WorldData(dimension:0)
        chain.chunks[.init(x:0,z:0)] = try VoxelChunk(key:.init(x:0,z:0),dimension:0,sections:[:],biomeData:nil)
        chain.apply([Cell(x:0,y:0,z:0):Block(name:"iron_chain",states:["pillar_axis":"y"])])
        precondition(chain.vacant(.init(0.1,0,0.1),radius:0.1) && !chain.vacant(.init(0.5,0,0.5),radius:0.1))
        _ = try chain.node(.init(x:0,z:0),assets:assets)
        let region = Set((-16...16).flatMap { x in (-16...16).map {Chunk(x:x,z:$0)} })
        let extra = Set((17...25).flatMap {x in (-2...2).map {Chunk(x:x,z:$0)} })
        let requested = region.union(extra), batch = Expedition.Coordinator.batch(requested,near:.init(x:0,z:0))
        precondition(batch.count == 1089 && batch.first == Chunk(x:0,z:0))
        let remainder = requested.subtracting(batch)
        precondition(!remainder.isEmpty && Set(batch).union(remainder) == requested)
        precondition(Expedition.Coordinator.batch(remainder,near:.init(x:0,z:0)).count == remainder.count)
        for kind in ["nether","end"] {
            let trail = Trail(.init(kind:kind,x:0,y:70,z:0,seed:42))
            var terrain = WorldData(dimension:0)
            for key in Set(trail.blocks.keys.map {WorldData.key($0.x,$0.z)}) {terrain.chunks[key] = try VoxelChunk(key:key,dimension:0,sections:[:],biomeData:nil)}
            terrain.apply(trail.blocks)
            var meshes = 0
            for key in terrain.chunks.keys {
                do {let node = try terrain.node(key,assets:assets); meshes += node.childNodes.count}
                catch {assetErrors.insert(String(describing:error))}
            }
            precondition(meshes>0)
            _ = try trail.decoration(assets:assets)
        }
        _ = try assets.texture("textures/blocks/portal",animated:true)
        _ = try assets.texture("textures/items/ender_eye")
        for error in assetErrors.sorted() {print("Portal asset failure: "+error)}
        precondition(assetErrors.isEmpty)
        let legacyPixels = CGContext(data:nil,width:64,height:32,bitsPerComponent:8,bytesPerRow:256,
            space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
        legacyPixels.setFillColor(CGColor(gray:0,alpha:1)); legacyPixels.fill(CGRect(x:0,y:0,width:64,height:32))
        let opaqueAvatar = try assets.avatar(skin:legacyPixels.makeImage()!,cape:nil,slim:false)
        precondition(opaqueAvatar.childNode(withName:"hat",recursively:true)?.geometry == nil,
            "Opaque legacy padding must not cover the character's face")
        legacyPixels.clear(CGRect(x:32,y:0,width:32,height:16))
        let layeredAvatar = try assets.avatar(skin:legacyPixels.makeImage()!,cape:nil,slim:false)
        precondition(layeredAvatar.childNode(withName:"hat",recursively:true)?.geometry != nil,
            "Transparent legacy skins must retain their optional hat layer")
        let seededRegion = Region(x:-5,z:-3,seed:-12345), seededArea = World.overworld.biomes[seededRegion.biome(.overworld)]
        let seededTerrain = Terrain(biome:seededArea,authored:seededRegion.landmark(.overworld),worldSeed:seededRegion.landmark(.overworld) ? 0 : seededRegion.seed)
        let originalTerrain = try seededTerrain.node(assets:assets,region:seededRegion)
        let rebuiltTerrain = try seededTerrain.node(assets:assets,x:64..<80,z:0..<16,bounded:false,region:seededRegion)
        let originalSection = originalTerrain.childNodes.compactMap { $0 as? Section }.first { $0.x == 64 && $0.z == 0 }!
        let rebuiltSection = rebuiltTerrain.childNodes.compactMap { $0 as? Section }.first { $0.x == 64 && $0.z == 0 }!
        precondition(originalSection.childNodes.count == rebuiltSection.childNodes.count)
        for (original,rebuilt) in zip(originalSection.childNodes,rebuiltSection.childNodes) {
            precondition(original.geometry?.sources(for:.vertex).first?.data == rebuilt.geometry?.sources(for:.vertex).first?.data)
            precondition(original.geometry?.sources(for:.normal).first?.data == rebuilt.geometry?.sources(for:.normal).first?.data)
        }
        let wetRegion = Region.from(World.overworld.biomes.firstIndex(of:.river)!,count:World.overworld.biomes.count)
        let wetStream = Stream(world:.overworld,assets:assets,failed:{ fatalError("Wet chunk failed") })
        wetStream.distance(4); wetStream.update(at:wetRegion.origin)
        func settleWater() {
            let deadline = Date().addingTimeInterval(10)
            while wetStream.outstanding>0 && Date()<deadline { RunLoop.main.run(until:Date().addingTimeInterval(0.01)) }
            precondition(wetStream.outstanding == 0)
        }
        func waterLight(_ expected: Double) {
            var count = 0
            wetStream.root.enumerateChildNodes { node,_ in
                for material in node.geometry?.materials ?? [] where material.name?.contains("water") == true {
                    precondition(abs(material.diffuse.intensity-expected)<0.001)
                    count += 1
                }
            }
            precondition(count>0,"A wet streamed region must retain visible water")
        }
        settleWater(); wetStream.illuminate(0); waterLight(0.2)
        wetStream.update(at:.init(wetRegion.origin.x+16,0,wetRegion.origin.z))
        settleWater(); waterLight(0.2)
        wetStream.illuminate(1); waterLight(1)
        wetStream.dispose()
        let glass = try assets.tiles("glass_pane"), white = try assets.tiles("white_stained_glass_pane"), red = try assets.tiles("red_stained_glass_pane")
        precondition(glass[0].name == "textures/blocks/glass" && glass[1].name == "textures/blocks/glass_pane_top")
        precondition(white[0].name == "textures/blocks/glass_white" && white[1].name == "textures/blocks/glass_pane_top_white")
        precondition(red[0].name == "textures/blocks/glass_red" && !white[0].writesToDepthBuffer)
        precondition(!glass[0].isDoubleSided && !white[0].isDoubleSided)
        precondition(Species.allCases.count == 86)
        for species in [Species.donkey,.mule,.phantom,.tadpole,.traderLlama,.trader,.wither,.zoglin,.zombieHorse,.zombieVillager,.sulfurCube] {
            let model = try factory.make(species)
            precondition(model.boundingBox.max.y>model.boundingBox.min.y)
            let movement = try factory.locomotion(species)
            precondition(movement.speed>0 && movement.width>0 && movement.height>0)
        }
        for species in [Species.spider,.caveSpider] {
            let model = try factory.make(species)
            let leg = model.childNode(withName:"leg0",recursively:true)!
            precondition(abs(leg.eulerAngles.y-Double.pi/4)<0.001 && abs(leg.eulerAngles.z-Double.pi/4)<0.001)
            let material = model.childNode(withName:"head",recursively:true)!.geometry!.firstMaterial!
            let surface = NSBitmapImageRep(cgImage:material.diffuse.contents as! CGImage)
            let glow = NSBitmapImageRep(cgImage:material.emission.contents as! CGImage)
            var eyes = 0
            for y in 0..<surface.pixelsHigh { for x in 0..<surface.pixelsWide {
                precondition(surface.colorAt(x:x,y:y)!.alphaComponent == 1)
                if glow.colorAt(x:x,y:y)!.redComponent>0.1 { eyes += 1 }
            } }
            precondition(eyes == 20,"Original spider eye pixels must glow without holes in the skin")
        }
        let nativeBaby = try factory.make(.villager,baby:true)
        let babyArms = nativeBaby.childNode(withName:"arms",recursively:true)!
        precondition(abs(babyArms.position.y-1.25/16)<0.001 && abs(babyArms.position.z)<0.001)
        precondition(abs(babyArms.eulerAngles.x)<0.001,"Baby cubes already fold the arms; adult general pose must stay excluded")
        precondition(nativeBaby.scale.x == 1 && nativeBaby.childNode(withName:"head",recursively:true)!.scale.x == 1)
        let traderLlama = try factory.make(.traderLlama)
        let traderCoat = traderLlama.childNode(withName:"head",recursively:true)!.geometry!.firstMaterial!.diffuse.contents as! CGImage
        precondition(traderCoat.width>0 && traderCoat.height>0)
        precondition(traderLlama.childNode(withName:"chest1",recursively:true)?.isHidden == true)
        let sulfurCube = try factory.make(.sulfurCube)
        precondition(sulfurCube.childNode(withName:"sulfur-shell",recursively:false)?.childNode(withName:"sulfur_cube",recursively:true)?.geometry?.firstMaterial?.blendMode == .alpha)
        let zombieHerd = try factory.group(.zombieHorse,biome:.savanna,seed:1), donkeyHerd = try factory.group(.donkey,biome:.savanna,seed:1)
        precondition(zombieHerd == 1 && donkeyHerd == 1)
        let sulfurHerd = try factory.group(.sulfurCube,biome:.sulfur,seed:1)!
        precondition((2...4).contains(sulfurHerd))
        try movement(factory)
        let edgeScene = SCNScene(), edgeTerrain = Terrain(biome:.meadow)
        edgeScene.rootNode.addChildNode(try edgeTerrain.node(assets:assets,x:0..<4,z:0..<2))
        let edgeRenderer = SCNRenderer(device:nil,options:nil); edgeRenderer.scene = edgeScene
        precondition(edgeRenderer.prepare(edgeScene,shouldAbortBlock:nil))
        let pathLevel = edgeTerrain.height(1,0)
        precondition(edgeTerrain.paved(1,0) && !edgeTerrain.paved(2,0) && pathLevel == edgeTerrain.height(2,0))
        precondition(!Collision.clear(edgeScene.rootNode,from:.init(1,pathLevel-0.03,0),to:.init(2,pathLevel-0.03,0),radius:0),"Grass must close the edge above a recessed path")
        edgeRenderer.scene = nil
        for species in Species.allCases {
            do { _ = try factory.make(species); _ = try factory.locomotion(species) }
            catch { fatalError("Original model \(species.rawValue) failed: \(error)") }
        }
        let crownPig = try factory.make(.pig); try factory.crown(crownPig)
        precondition(crownPig.childNode(withName:"technoblade-crown",recursively:true) != nil)
        precondition(crownPig.childNode(withName:"technoblade-cape",recursively:true)?.childNode(withName:"cape-fold-0",recursively:false) != nil)
        for species in [Species.pig,.cow,.sheep,.chicken,.wolf,.horse,.cat,.axolotl,.villager] {
            let baby = try factory.make(species,baby:true)
            precondition(baby.boundingBox.max.y>baby.boundingBox.min.y)
        }
        for species in [Species.pig,.cow,.sheep,.horse,.axolotl,.bat,.bee,.enderman] {
            let count = try factory.group(species,biome:.meadow,seed:17)
            precondition(count != nil && (1...32).contains(count!))
        }
        let toast = try factory.make(.rabbit,named:"Toast")
        precondition(toast.childNode(withName:"body",recursively:true)?.geometry?.firstMaterial?.name?.contains("toast") == true)
        precondition(toast.scale.x == 1,"Rabbit client scale must cancel the adult behaviour scale")
        let adultCat = try factory.make(.cat), kitten = try factory.make(.cat,baby:true)
        precondition(abs(adultCat.scale.x-0.8)<0.0001 && kitten.scale.x == 1)
        let inverted = try factory.make(.chicken,named:"Dinnerbone")
        precondition(abs(inverted.childNodes.first!.eulerAngles.z-Double.pi)<0.001 && inverted.boundingBox.min.y>=0)
        let ordinary = try factory.make(.sheep), pink = try factory.make(.sheep)
        try factory.pink(pink)
        let rainbow = try factory.make(.sheep,named:"jeb_")
        let ordinaryWool = ordinary.childNode(withName:"body",recursively:true)!.geometry!.firstMaterial!
        let pinkWool = pink.childNode(withName:"body",recursively:true)!.geometry!.firstMaterial!
        precondition(ordinaryWool !== pinkWool && ordinaryWool.shaderModifiers?[.surface] == nil)
        precondition(pinkWool.shaderModifiers?[.surface]?.contains("_surface.transparent.a") == true)
        precondition(rainbow.childNode(withName:"body",recursively:true)!.geometry!.firstMaterial!.animationKeys.contains("wool"))
        let charged = try factory.charged(), aura = charged.childNode(withName:"charged-aura",recursively:false)!
        precondition(aura.childNode(withName:"head",recursively:true)!.geometry!.firstMaterial!.blendMode == .add)
        precondition(aura.childNode(withName:"head",recursively:true)!.geometry!.firstMaterial!.animationKeys.contains("charge"))
        _ = try factory.skeletonHorse()
        let herobrine = try factory.herobrine()
        precondition(herobrine.childNode(withName:"custom-white-eyes",recursively:true) != nil)
        let jockey = try factory.jockey(); precondition(jockey.childNode(withName:"jockey-rider",recursively:true) != nil)
        for species in [Species.skeleton,.witherSkeleton,.illager] {
            var weapons = 0
            try factory.make(species).enumerateChildNodes { node,_ in if node.name?.hasPrefix("held-") == true { weapons += 1 } }
            precondition(weapons == 1)
        }
        var calmWeapons = 0
        try factory.make(.vindicator).enumerateChildNodes { node,_ in if node.name?.hasPrefix("held-") == true { calmWeapons += 1 } }
        precondition(calmWeapons == 0)
        let mapView = FlightView(frame:.zero)
        var arrived: [Int] = []
        var navigation: [Bool] = []
        let map = Atlas(world:.overworld,index:0,tile:try Landscape.scene(.overworld,assets:assets),assets:assets,
            view:mapView,arrived:{ arrived.append($0) },failed:{ fatalError("Neighbour graph failed") },activity:{ navigation.append($0) })
        let neighbours = Date().addingTimeInterval(20)
        while (map.tiles[1] == nil || map.tiles[5] == nil) && Date()<neighbours { RunLoop.main.run(until:Date().addingTimeInterval(0.01)) }
        precondition(map.tiles[1] != nil && map.tiles[5] != nil && map.tiles.count <= 5)
        let mapCamera = mapView.pointOfView!; mapCamera.removeAllActions()
        mapCamera.worldPosition = .init((eastEdge+0.1),10,30)
        mapCamera.eulerAngles = .init(0.1,0.4,0)
        let mapBefore = mapCamera.simdWorldTransform
        map.update(1)
        precondition(map.active == 1 && arrived == [1] && abs(mapCamera.worldPosition.x-(eastEdge+0.1))<0.001)
        precondition(simd_length(mapCamera.simdWorldTransform.columns.2-mapBefore.columns.2)<0.001,"Crossing must retain direction")
        mapCamera.worldPosition = .init((eastEdge-0.1),10,30); map.update(2)
        precondition(map.active == 0 && arrived == [1,0] && abs(mapCamera.worldPosition.x-(eastEdge-0.1))<0.001)
        let north = Date().addingTimeInterval(20)
        while map.tiles[5] == nil && Date()<north { RunLoop.main.run(until:Date().addingTimeInterval(0.01)) }
        precondition(map.tiles[5] != nil)
        mapCamera.worldPosition = .init(3,10,(southEdge+0.1)); map.update(2.1)
        precondition(map.active == 5 && abs(mapCamera.worldPosition.z-(southEdge+0.1))<0.001)
        mapCamera.worldPosition = .init(3,10,(southEdge-0.1)); map.update(2.2)
        precondition(map.active == 0 && abs(mapCamera.worldPosition.z-(southEdge-0.1))<0.001)
        let resumed = mapCamera.simdWorldTransform
        map.resume()
        precondition(simd_length(mapCamera.simdWorldTransform.columns.3-resumed.columns.3)<0.001,"Escape must preserve position")
        precondition(simd_length(mapCamera.simdWorldTransform.columns.2-resumed.columns.2)<0.001,"Escape must preserve direction")
        mapCamera.removeAllActions()
        let tour = SCNRenderer(device:nil,options:nil); tour.scene = map.scene
        precondition(tour.prepare(map.scene,shouldAbortBlock:nil))
        map.visit(1)
        map.update(3); map.update(3.1)
        precondition(abs(mapCamera.simdWorldFront.y)<0.95,"Guided climbs must keep scenery in view")
        for frame in 0..<2400 {
            map.update(3+Double(frame)/30)
            tour.update(atTime:Double(frame)/30)
            RunLoop.main.run(until:Date().addingTimeInterval(0.005))
            if map.active == 1 && mapCamera.worldPosition.x>Double(Region.span)-12 && navigation.last == false { break }
        }
        precondition(map.active == 1 && mapCamera.worldPosition.x > Double(Region.span)-12,"Area flight stopped at \(mapCamera.worldPosition), area \(map.active), navigation \(navigation), pending \(map.pendingChunks)")
        precondition(navigation == [true,false],"A completed flight must release the automatic-tour gate")
        mapView.exploring = true
        var reports = 0
        mapView.report = { _,_ in reports += 1 }
        Adventure.motion(mapView,enabled:false,active:true)
        RunLoop.main.run(until:Date().addingTimeInterval(0.25))
        precondition(reports>0 && map.scene.isPaused && !mapView.rendersContinuously)
        Adventure.motion(mapView,enabled:false,active:false)
        let stopped = reports
        RunLoop.main.run(until:Date().addingTimeInterval(0.2))
        precondition(reports == stopped,"Inactive spectator must stop map updates")
        tour.scene = nil
        map.dispose(); mapView.dispose(); mapView.scene = nil
        for (size,centre,ceiling) in [(SCNVector3(4,0.2,4),SCNVector3(3,12,southEdge-0.1),11.71),
                                     (SCNVector3(0.4,20,4),SCNVector3(3,10,southEdge-0.1),10.01)] {
            let view = FlightView(frame:.zero)
            var activity = [Bool]()
            let map = Atlas(world:.overworld,index:0,tile:try Landscape.scene(.overworld,assets:assets),assets:assets,
                view:view,arrived:{ _ in },failed:{ fatalError("Blocked map failed") },activity:{ activity.append($0) })
            let obstacle = SCNNode(geometry:SCNBox(width:size.x,height:size.y,length:size.z,chamferRadius:0))
            obstacle.categoryBitMask = 2; obstacle.position = centre
            map.tiles[0]!.rootNode.addChildNode(obstacle)
            let camera = view.pointOfView!; camera.removeAllActions(); camera.worldPosition = .init(3,10,southEdge-0.1)
            map.update(0)
            let renderer = SCNRenderer(device:nil,options:nil); renderer.scene = map.scene
            precondition(renderer.prepare(map.scene,shouldAbortBlock:nil)); SCNTransaction.flush()
            map.visit(1)
            var maximum = camera.worldPosition.y
            for frame in 1...500 {
                map.update(Double(frame)/30); renderer.update(atTime:Double(frame)/30)
                maximum = max(maximum,camera.worldPosition.y)
                RunLoop.main.run(until:Date().addingTimeInterval(0.005))
                if activity.last == false && activity.contains(true) { break }
            }
            precondition(maximum<ceiling && map.active == 0 && activity == [true,false],
                "Terrain recovery must preserve structure walls and roofs")
            map.dispose(); renderer.scene = nil; view.dispose(); view.scene = nil
        }
        var frames: [String:NSImage]?
        assets.icons { images,stone,loaded,font,splash in
            precondition(Thread.isMainThread && images.count == 4 && stone != nil)
            precondition(font.map { CTFontCopyPostScriptName($0) as String } == "Minecraft-Ten" && !splash.isEmpty && loaded["title"] != nil)
            frames = loaded
        }
        let artLimit = Date().addingTimeInterval(5)
        while frames == nil && Date() < artLimit { RunLoop.main.run(until:Date().addingTimeInterval(0.01)) }
        precondition(NSFont(name:"Mojangles",size:16) != nil)
        for name in ["accessibility_glyph","keyboard_and_mouse_glyph","video_glyph","controller_glyph"] { precondition(frames?[name] != nil) }
        precondition(frames?["hotbar_0"] != nil && frames?["selected_hotbar_slot"] != nil)
        precondition(frames?["loading-dirt"] != nil && frames?["loading_bar"]?.size == .init(width:640,height:8))
        let tracks = try assets.music()
        precondition(tracks.contains("sounds/music/game/sweden.ogg") && tracks.contains("sounds/music/menu/menu1.ogg"))
        var decoded = false
        assets.song(excluding:nil) { song in
            precondition(song != nil && song!.0.duration > 0 && !song!.0.isPlaying)
            decoded = true
        }
        let audioLimit = Date().addingTimeInterval(10)
        while !decoded && Date() < audioLimit { RunLoop.main.run(until:Date().addingTimeInterval(0.01)) }
        precondition(decoded)
        var loaded: SCNScene?
        let queued = Date()
        assets.load(.overworld,biome:0,passage:nil) { result in
            precondition(Thread.isMainThread)
            switch result {
            case .success(let scene): loaded = scene
            case .failure(let error): fatalError("Habitat load failed: \(error)")
            }
        }
        let enqueue = Date().timeIntervalSince(queued)*1000
        let limit = Date().addingTimeInterval(5)
        while loaded == nil && Date() < limit { RunLoop.main.run(until:Date().addingTimeInterval(0.01)) }
        precondition(loaded?.rootNode.childNode(withName:"terrain",recursively:false) != nil)
        let residents = loaded!.rootNode.childNodes.filter { $0.name?.hasPrefix("resident-") == true }
        let positions = residents.map(\.position)
        let animation = SCNRenderer(device:nil,options:nil); animation.scene = loaded; animation.isPlaying = true
        for frame in 0...400 { animation.update(atTime:Double(frame)/20) }
        let moved = zip(residents,positions).filter { hypot($0.0.position.x-$0.1.x,$0.0.position.z-$0.1.z)>0.2 }.count
        precondition(moved >= 4,"Residents must keep moving during the idle hover, got \(moved)")
        let idleCamera = loaded!.rootNode.childNode(withName:"camera",recursively:false)!
        precondition(abs(idleCamera.simdWorldTransform.columns.0.y)<0.001,"Idle aiming must keep the horizon level")
        animation.scene = nil
        print("Asset queue returned in \(String(format:"%.2f",enqueue)) ms and delivered an original-art graph on the main thread")
        loaded = nil
        let cat = try factory.make(.cat), catBody = cat.childNode(withName:"body",recursively:true)!
        precondition(abs(catBody.eulerAngles.x + .pi/2)<0.001)
        let catTail = cat.childNode(withName:"tail1",recursively:true)!
        precondition(abs(catTail.eulerAngles.x - 51.57 * .pi/180)<0.001)
        let villager = try factory.make(.villager)
        let arms = villager.childNode(withName:"arms",recursively:true)!
        precondition(abs(arms.eulerAngles.x - 42.97 * .pi/180)<0.001)
        for variant in 0..<5 {
            let model = try factory.make(.villager,biome:.desert,variant:variant)
            let material = model.childNode(withName:"body",recursively:true)!.geometry!.firstMaterial!
            precondition(material.name?.hasPrefix("villager-desert-") == true && material.blendMode == .replace)
        }
        precondition(Set(World.allCases.flatMap { $0.biomes.flatMap(\.residents) }) == Set(Species.allCases))
        let stray = try factory.make(.stray), evoker = try factory.make(.evoker)
        precondition(stray.childNode(withName:"stray-clothes",recursively:true) != nil)
        precondition(evoker.childNode(withName:"arms",recursively:true)?.geometry != nil)
        precondition(evoker.childNode(withName:"leftarm",recursively:true)?.geometry == nil)
        precondition(evoker.childNode(withName:"rightarm",recursively:true)?.geometry == nil)
        for variant in 0..<35 {
            let horse = try factory.make(.horse,variant:variant)
            precondition((horse.childNode(withName:"horse-markings",recursively:true) != nil) == (variant%5 != 0))
            horse.enumerateChildNodes { part,_ in
                if let name = part.name, ["Saddle","Bit","Bridle","Rein","Bag","MuleEar"].contains(where:{ name.hasPrefix($0) }) {
                    precondition(part.isHidden)
                }
            }
        }
        for block in ["oak_log","cherry_log","mangrove_log","pale_oak_log","basalt","bone_block","hay_block"] {
            let upright = try assets.tiles(block)
            for (axis,ends) in [("x",[1,3]),("z",[0,2])] {
                let horizontal = try assets.tiles(block,states:["axis":axis])
                for index in ends { precondition(horizontal[index].name == upright[4].name) }
                precondition(upright.allSatisfy { SCNMatrix4EqualToMatrix4($0.diffuse.contentsTransform,SCNMatrix4Identity) })
            }
        }
        for (direction,front) in [("south",0),("east",1),("north",2),("west",3),("up",4),("down",5)] {
            let furnace = try assets.tiles("furnace",states:["facing":direction])
            precondition(furnace[front].name?.contains("furnace_front") == true)
        }
        for species in [Species.pig,.cow,.chicken,.wolf] { _ = try factory.make(species,classic:true) }
        _ = try factory.make(.cow,biome:.desert)
        _ = try factory.make(.chicken,biome:.snow)
        let airborne = SCNScene(), bat = SCNNode(), batModel = try factory.make(.bat)
        bat.position = .init(0,3,0); bat.addChildNode(batModel); airborne.rootNode.addChildNode(bat)
        try factory.wander(bat,model:batModel,species:.bat,area:.dripstone,seed:15,root:airborne.rootNode) { x,z in .init(x,3,z) }
        let crystal = try assets.actor("ender_crystal")
        airborne.rootNode.addChildNode(crystal)
        let shell = crystal.childNode(withName:"outerglass",recursively:true)!, base = crystal.childNode(withName:"base",recursively:true)!
        let basePosition = base.position
        SCNTransaction.flush()
        let airborneAnimation = SCNRenderer(device:nil,options:nil); airborneAnimation.scene = airborne; airborneAnimation.isPlaying = true
        airborneAnimation.update(atTime:0)
        var lastBat = bat.position, movingFrames = 0, heights = [Double](), batHeights = [Double]()
        for frame in 1...600 {
            airborneAnimation.update(atTime:Double(frame)/10)
            let dx = bat.position.x-lastBat.x, dz = bat.position.z-lastBat.z, distance = hypot(dx,dz)
            if distance>0.001 {
                let forward = batModel.presentation.worldFront
                precondition((forward.x*dx+forward.z*dz)/distance>0.95,"Bats must face their flight direction")
                movingFrames += 1
            }
            lastBat = bat.position; heights.append(shell.position.y)
            batHeights.append(bat.position.y)
        }
        precondition(movingFrames>=580,"Flying bats must not wait between their route segments")
        precondition(batHeights.max()!-batHeights.min()!>0.4,"Bats must change flight height")
        precondition(heights.max()!-heights.min()!>0.8 && base.position.y == basePosition.y,"Crystal shells float while the base stays still")
        airborneAnimation.scene = nil
        let plainsWater = try assets.water(.meadow), riverWater = try assets.water(.river)
        precondition(plainsWater.colour == 0x44AFF5 && riverWater.colour == 0x0084FF)
        precondition(plainsWater.opacity == 0.65)
        let breeze = try factory.make(.breeze)
        let fish = try factory.make(.tropical,variant:3)
        precondition(fish.childNode(withName:"fish-pattern",recursively:true) != nil)
        precondition(breeze.childNodes.filter { $0.name?.hasPrefix("breeze_wind_") == true }.count == 3)
        let blaze = try factory.make(.blaze)
        let blazePixels = NSBitmapImageRep(cgImage:blaze.childNode(withName:"head",recursively:true)!.geometry!.firstMaterial!.diffuse.contents as! CGImage)
        precondition(blazePixels.colorAt(x:8,y:12)!.alphaComponent == 1)
        let rods = blaze.childNodes.filter { $0.name?.hasPrefix("rod-orbit-") == true }.flatMap(\.childNodes)
        precondition(rods.count == 12)
        precondition(Set(rods.map { "\($0.position.x),\($0.position.y),\($0.position.z)" }).count == 12)
        let enderman = try factory.make(.enderman)
        let headBounds = enderman.childNode(withName:"head",recursively:true)!
        let bodyBounds = enderman.childNode(withName:"body",recursively:true)!
        precondition(headBounds.convertPosition(headBounds.geometry!.boundingBox.min,to:enderman).y >= bodyBounds.convertPosition(bodyBounds.geometry!.boundingBox.max,to:enderman).y-0.04)
        let enderSkin = headBounds.geometry!.firstMaterial!
        let eyePixels = NSBitmapImageRep(cgImage:enderSkin.emission.contents as! CGImage)
        precondition(eyePixels.colorAt(x:8,y:12)!.alphaComponent == 1 && eyePixels.colorAt(x:8,y:12)!.redComponent>0.3)
        let copper = try factory.make(.golem)
        precondition(copper.childNode(withName:"golem-eyes",recursively:true) != nil)
        for (species,width,height,speed) in [(Species.blaze,0.5,1.8,0.92),(.enderman,0.6,2.9,1.2),(.golem,0.6,0.98,0.8),(.villager,0.6,1.9,1.2),(.sheep,0.9,1.3,0.8)] {
            let motion = try factory.locomotion(species)
            precondition(abs(motion.width-width)<0.001 && abs(motion.height-height)<0.001 && abs(motion.speed-speed)<0.001)
        }
        var fixtures = Voxels()
        for fixture in ["torch","wall_torch","bell","wheat","lantern","brewing_stand","illager_captain_wall_banner","oak_door","spruce_trapdoor","ladder"] {
            let handled = try Structures.fixture(fixture,states:["facing":"west","age":"7"],at:.init(0,0,0),assets:assets,mesh:&fixtures)
            precondition(handled)
        }
        precondition(!fixtures.vertices.isEmpty && fixtures.materials.contains { $0.name?.contains("wheat_stage_7") == true })
        func placed(_ name: String, _ states: [String:String]) throws -> SCNNode {
            var mesh = Voxels()
            let handled = try Structures.fixture(name,states:states,at:.init(0,0,0),assets:assets,mesh:&mesh)
            precondition(handled)
            return mesh.node("placed-"+name)
        }
        for (facing,dx,dz) in [("east",1.0,0.0),("west",-1,0),("north",0,-1),("south",0,1)] {
            var mesh = Voxels()
            try Structures.fixture("wall_torch",states:["facing":facing],at:.init(0,0,0),assets:assets,mesh:&mesh)
            let contact = mesh.vertices.map { ($0.x-0.5)*dx+($0.z-0.5)*dz }.min()!
            precondition((-0.57 ... -0.5).contains(contact),"A wall torch must reach its support face")
        }
        for name in ["chest","trapped_chest","ender_chest"] {
            let chest = try placed(name,["facing":"south"])
            precondition(chest.geometry!.sources(for:.vertex)[0].vectorCount == 72)
            precondition(abs(chest.boundingBox.max.y-14.0/16)<0.001)
        }
        let northBanner = try placed("illager_captain_wall_banner",["facing":"north"])
        precondition(northBanner.boundingBox.min.z>0.85 && northBanner.boundingBox.max.z<0.99)
        precondition(abs(northBanner.boundingBox.max.x-northBanner.boundingBox.min.x-20.0/24)<0.001)
        let southLadder = try placed("ladder",["facing":"south"])
        precondition(abs(southLadder.boundingBox.min.z-0.0625)<0.001)
        let door = try placed("oak_door",["facing":"north","open":"false"])
        let opened = try placed("oak_door",["facing":"north","open":"true","hinge":"right"])
        precondition(abs(door.boundingBox.min.z-0.8125)<0.001 && abs(opened.boundingBox.min.x-0.8125)<0.001)
        let hatch = try placed("spruce_trapdoor",["facing":"east","open":"true"])
        precondition(abs(hatch.boundingBox.max.x-0.1875)<0.001 && hatch.boundingBox.max.y == 1)
        let stand = try placed("brewing_stand",["has_bottle_0":"true","has_bottle_2":"true"])
        precondition(stand.geometry!.materials.contains { $0.name == "textures/blocks/brewing_stand_base" })
        precondition(stand.geometry!.sources(for:.vertex)[0].vectorCount == 108 && stand.boundingBox.max.y == 1)
        let banner = try assets.banner("wall_banner",data:["Base":13,"Patterns":[["Pattern":"tt","Color":0],["Pattern":"bt","Color":0]]])
        let bannerPixels = NSBitmapImageRep(cgImage:banner.diffuse.contents as! CGImage)
        let centre = bannerPixels.colorAt(x:2,y:20)!.usingColorSpace(.deviceRGB)!
        precondition(centre.redComponent>centre.greenComponent+0.3 && centre.blueComponent>centre.greenComponent+0.3)
        let pattern = bannerPixels.colorAt(x:10,y:2)!.usingColorSpace(.deviceRGB)!
        precondition(pattern.redComponent<0.2 && pattern.greenComponent<0.2)
        let ship = try Structures.template("endcity/ship",assets:assets).geometry!
        precondition(ship.materials.contains { $0.name == "textures/blocks/brewing_stand_base" })
        let tower = try Structures.template("endcity/tower_top",assets:assets).geometry!
        precondition(tower.materials.contains { $0.name == "banner-base13-triangle_top0-triangle_bottom0" })
        precondition(!tower.materials.contains { $0.name?.contains("banner_illager") == true })
        rejects { _ = try assets.banner("wall_banner",data:["Base":16]) }
        rejects { _ = try assets.banner("wall_banner",data:["Patterns":[["Pattern":"../invalid","Color":0]]]) }
        for (area,y,from,to) in [(Biome.desert,1.62,10.0,-4.0),(.jungle,7.62,4,-3),(.monument,3.62,28,0)] {
            let interior = SCNScene(); interior.rootNode.addChildNode(try Structures.build(area,x:0,y:0,assets:assets))
            let renderer = SCNRenderer(device:nil,options:nil); renderer.scene = interior
            precondition(renderer.prepare(interior,shouldAbortBlock:nil))
            precondition(Collision.clear(interior.rootNode,from:.init(0,y,from-18),to:.init(0,y,to-18)),"\(area) must have a reachable interior")
            precondition(!Collision.clear(interior.rootNode,from:.init(0,y,to-18),to:.init(50,y,to-18)),"\(area) must retain solid side walls")
        }
        precondition(Passage.stronghold.pose(at:0).eye.y-Passage.stronghold.pose(at:28).eye.y > 40)
        let dragon = try factory.actor("ender_dragon")
        precondition(abs(dragon.boundingBox.min.x+dragon.boundingBox.max.x) < 0.001)
        let window = try Structures.template("mansion/wall_window",assets:assets).geometry!
        precondition(zip(window.materials,window.elements).contains { $0.0.name?.contains("glass") == true && $0.1.primitiveCount > 0 })
        let panePositions = window.sources(for:.vertex)[0], paneNormals = window.sources(for:.normal)[0], paneCoordinates = window.sources(for:.texcoord)[0]
        func paneValue(_ source: SCNGeometrySource, _ index: Int, _ axis: Int) -> Double {
            source.data.withUnsafeBytes { bytes in
                let offset = source.dataOffset+index*source.dataStride+axis*source.bytesPerComponent
                return source.bytesPerComponent == 4 ? Double(bytes.loadUnaligned(fromByteOffset:offset,as:Float.self)) : bytes.loadUnaligned(fromByteOffset:offset,as:Double.self)
            }
        }
        var glassFaces = 0
        for (material,element) in zip(window.materials,window.elements) where material.name?.contains("/glass") == true && material.name?.contains("pane_top") != true {
            for triangle in 0..<element.primitiveCount {
                let indices = (0..<3).map { corner in element.data.withUnsafeBytes { Int($0.loadUnaligned(fromByteOffset:(triangle*3+corner)*element.bytesPerIndex,as:UInt32.self)) } }
                guard abs(paneValue(paneNormals,indices[0],1))<0.1 else { continue }
                let axis = abs(paneValue(paneNormals,indices[0],0))>0.9 ? 2 : 0
                for index in indices.dropFirst() {
                    precondition(abs(abs(paneValue(panePositions,index,axis)-paneValue(panePositions,indices[0],axis))-abs(paneValue(paneCoordinates,index,0)-paneValue(paneCoordinates,indices[0],0)))<0.001,"Glass texels must retain their block-space width")
                }
                glassFaces += 1
            }
        }
        precondition(glassFaces>0)
        for lava in [false,true] {
            let material = try Landscape.flow(assets:assets,lava:lava), node = SCNNode()
            Landscape.animate(node,material:material)
            let image = material.diffuse.contents as! CGImage
            precondition(image.height > image.width && image.height%image.width == 0)
            precondition(abs(material.diffuse.contentsTransform.m22-Double(image.width)/Double(image.height)) < 0.0001)
            precondition(abs(material.transparency-(lava ? 1 : plainsWater.opacity))<0.0001 && material.lightingModel == .constant)
            if lava { precondition(material.emission.contentsTransform.m22 == material.diffuse.contentsTransform.m22) }
        }
        let start = Date()
        for world in World.allCases {
            for index in world.biomes.indices {
                let scene = try Landscape.scene(world,biome:index,assets:assets)
                if let passage = world.biomes[index].passage {
                    let camera = scene.rootNode.childNode(withName:"camera",recursively:false)!
                    precondition(camera.action(forKey:"passage") == nil && camera.action(forKey:"journey") != nil)
                    precondition(scene.rootNode.childNode(withName:"passage-masonry",recursively:false) != nil)
                    if passage == .mine {
                        precondition(Collision.clear(scene.rootNode,from:.init(0,1.62,-16),to:.init(12,1.62,-16)))
                        precondition(!Collision.clear(scene.rootNode,from:.init(12,1.62,-16),to:.init(17,1.62,-16)))
                    } else {
                        precondition(Collision.clear(scene.rootNode,from:.init(0,1.62,0),to:.init(9,1.62,0)))
                        precondition(Collision.clear(scene.rootNode,from:.init(0,2.8,-14),to:.init(5,2.8,-14)))
                        precondition(!Collision.clear(scene.rootNode,from:.init(5,2.8,-14),to:.init(7,2.8,-14)))
                    }
                    let residents = scene.rootNode.childNodes.filter { $0.name?.hasPrefix("passage-resident-") == true }
                    let origins = residents.map(\.position)
                    SCNTransaction.flush()
                    let animation = SCNRenderer(device:nil,options:nil); animation.scene = scene; animation.isPlaying = true
                    for frame in 0...400 { animation.update(atTime:Double(frame)/20) }
                    precondition(zip(residents,origins).filter { hypot($0.0.position.x-$0.1.x,$0.0.position.z-$0.1.z)>0.2 }.count >= 2,"Passage residents must keep moving during visits")
                    animation.scene = nil
                }
                var nodes = 0, triangles = 0
                scene.rootNode.enumerateChildNodes { node,_ in
                    nodes += 1
                    triangles += node.geometry?.elements.reduce(0) { $0+$1.primitiveCount } ?? 0
                }
                print("\(world) \(world.biomes[index]): \(nodes) nodes, \(triangles) triangles")
                fflush(stdout)
                precondition(nodes < 1200 && triangles < 350_000)
                if world == .end {
                    precondition((scene.background.contents as? [CGImage])?.count == 6)
                }
                if world.biomes[index] == .central {
                    let beam = scene.rootNode.childNode(withName:"crystal-healing-beam",recursively:false)!
                    let dragon = scene.rootNode.childNode(withName:"sky-resident",recursively:false)!
                    precondition(!beam.isHidden,"Reduced Motion must retain the static healing connection")
                    SCNTransaction.flush()
                    let flight = SCNRenderer(device:nil,options:nil); flight.scene = scene; flight.isPlaying = true
                    var previousDragon = dragon.position
                    for frame in 0...20 {
                        flight.update(atTime:Double(frame)/10)
                        let dx = dragon.position.x-previousDragon.x, dz = dragon.position.z-previousDragon.z, distance = hypot(dx,dz)
                        if distance>0.001 {
                            let forward = dragon.childNodes[0].presentation.worldFront
                            precondition((forward.x*dx+forward.z*dz)/distance>0.95,"Dragons must fly forwards")
                        }
                        previousDragon = dragon.position
                    }
                    precondition(!beam.isHidden && beam.scale.y > 0 && beam.scale.y <= 32)
                    let endpoint = beam.convertPosition(.init(0,0.5,0),to:scene.rootNode)
                    let target = dragon.convertPosition(.init(0,0.6,0),to:scene.rootNode)
                    precondition(abs(endpoint.x-target.x)+abs(endpoint.y-target.y)+abs(endpoint.z-target.z)<0.1,"Crystal healing beam follows the dragon: \(endpoint) vs \(target)")
                    let landmark = scene.rootNode.childNode(withName:"landmark-central",recursively:true)!
                    let position = landmark.position
                    landmark.position.x += 1000
                    SCNTransaction.flush()
                    flight.update(atTime:2.1)
                    precondition(beam.isHidden,"Distant dragons must not retain a healing connection")
                    landmark.position = position
                    flight.scene = nil
                }
                if world.biomes[index] == .city {
                    let eye = Landscape.pose(.city,at:0).eye
                    precondition(Collision.clear(scene.rootNode,from:eye,to:.init(eye.x,eye.y+1,eye.z-6),radius:0.35))
                }
                if world.biomes[index] == .meadow {
                    let sites = Structures.sites(in:scene.rootNode)
                    precondition(sites.filter { $0.kind == .bed }.count == 4 && sites.filter { $0.kind == .work }.count == 4)
                    precondition(sites.filter { $0.kind == .work && $0.block == "composter" }.contains { site in
                        site.standing.contains { abs($0.y-site.point.y+0.0625)<0.001 }
                    })
                    precondition(sites.filter { $0.kind == .path }.flatMap(\.standing).contains { abs($0.y-2.5)<0.001 })
                    let workers = scene.rootNode.childNodes.filter { $0.action(forKey:"routine") != nil }
                    print("Village routines",workers.count); fflush(stdout)
                    precondition(workers.count == 4,"Every adult villager needs a reachable work and bed route")
                    precondition(scene.rootNode.childNode(withName:"resident-villager-7-baby",recursively:false) != nil)
                    precondition(scene.rootNode.childNode(withName:"template-village/plains/houses/plains_temple_4",recursively:true) != nil)
                    precondition(scene.rootNode.childNode(withName:"template-village/plains/houses/plains_weaponsmith_1",recursively:true) != nil)
                    let fountain = scene.rootNode.childNode(withName:"template-village/plains/town_centers/plains_fountain_01",recursively:true)!
                    precondition(fountain.geometry!.materials.contains { $0.name == "textures/entity/bell/bell" })
                    let cloud = scene.rootNode.childNode(withName:"drifting-cloud",recursively:false)!
                    precondition(cloud.geometry?.firstMaterial?.name == "cloud-volume")
                    precondition(cloud.geometry!.firstMaterial!.transparency<1 && cloud.categoryBitMask == 1)
                    precondition(cloud.childNodes.count == 2 && cloud.childNodes.allSatisfy { $0.geometry === cloud.geometry && $0.categoryBitMask == 1 })
                    let sky = scene.rootNode.childNode(withName:"daylight",recursively:false) as! Daylight
                    Daylight.apply(scene,area:.meadow,seconds:240)
                    precondition(sky.weather?.birthRate ?? 0 > 0)
                    Daylight.apply(scene,area:.meadow,seconds:0)
                    precondition(sky.weather?.birthRate == 0)
                    sky.isHidden = true; Daylight.apply(scene,area:.meadow,seconds:240)
                    precondition(sky.weather?.birthRate == 0)
                    sky.isHidden = false
                    var tributePigs = 0
                    scene.rootNode.enumerateChildNodes { node,_ in if node.name == "technoblade-crown" { tributePigs += 1 } }
                    precondition(tributePigs == 1)
                    precondition(scene.rootNode.childNode(withName:"resident-pig-0",recursively:false) != nil)
                    precondition(scene.rootNode.childNode(withName:"resident-horse-0",recursively:false) != nil)
                    Daylight.apply(scene,area:.meadow,seconds:600)
                    precondition(scene.rootNode.childNode(withName:"daylight",recursively:false)?.childNode(withName:"stars",recursively:false)?.opacity == 1)
                    Daylight.apply(scene,area:.meadow,seconds:0)
                    precondition(scene.rootNode.childNode(withName:"daylight",recursively:false)?.childNode(withName:"sun",recursively:false)?.opacity == 1)
                    let crowns = scene.rootNode.childNodes.filter { $0.name == "wind-canopy" }
                    precondition(crowns.count > 2 && crowns.allSatisfy { $0.geometry === crowns[0].geometry && $0.categoryBitMask == 2 })
                }
                let area = world.biomes[index], terrain = Terrain(biome:area)
                for step in 0...36 {
                    let eye = Landscape.pose(area,at:Double(step)/2).eye
                    let floor = terrain.height(eye.x.rounded(),eye.z.rounded())
                    precondition(floor > -90 && eye.y > floor+0.1,"Camera ground at \(area), t=\(Double(step)/2), eye=\(eye), floor=\(floor)")
                    if area.underground || world == .nether {
                        precondition(eye.y < max(floor+9,terrain.ceiling(eye.x,eye.z))-0.1)
                    }
                }
                if world.biomes[index] == .mansion {
                    let jockey = scene.rootNode.childNode(withName:"resident-chicken-jockey",recursively:false)!
                    precondition(jockey.position.y == 5 && jockey.childNode(withName:"jockey-rider",recursively:true) != nil)
                    precondition(Collision.vacant(scene.rootNode,at:.init(jockey.position.x,5.8,jockey.position.z)))
                    var rooms: [SCNGeometry] = []
                    scene.rootNode.enumerateChildNodes { node,_ in
                        if node.name == "template-mansion/1x1_a1", let geometry = node.geometry { rooms.append(geometry) }
                    }
                    precondition(rooms.count == 18 && rooms.allSatisfy { $0 === rooms[0] })
                }
                if world.biomes[index].passage == nil { precondition(scene.rootNode.childNode(withName:"habitat-detail",recursively:false) != nil) }
                for animated in [false,true] {
                    Landscape.focus(scene,world:world,biome:index,animated:animated)
                    precondition(scene.rootNode.childNode(withName:"camera",recursively:false)!.actionKeys == ["journey"])
                    precondition(Collision.vacant(scene.rootNode,at:scene.rootNode.childNode(withName:"camera",recursively:false)!.position),"Camera must start outside solid blocks in \(area)")
                }
                let residents = scene.rootNode.childNodes.filter { $0.name?.hasPrefix("resident-") == true || $0.name?.hasPrefix("passage-resident-") == true }
                precondition(residents.count >= world.biomes[index].residents.count || world.biomes[index] == .deep)
                precondition(residents.count <= 40)
                for resident in residents {
                    let p = resident.position
                    let origin = Atlas.offset(index,count:world.biomes.count)
                    let floor = Terrain.sample(world:world,at:.init(origin.x+p.x.rounded(),area.level+8,origin.z+p.z.rounded())).height-area.level
                    precondition(floor > -90)
                    let name = resident.childNodes[0].name!.replacingOccurrences(of:"mob-",with:"")
                    if let species = Species(rawValue:name), species.swimming {
                        precondition(p.y < 0.9 && p.y > floor && floor < 0)
                    }
                }
            }
        }
        for passage in [Passage.mine,.stronghold,.rift] {
            let scene = try passage.scene(assets:assets)
            if passage != .rift {
                for tick in 1...(passage.duration*20) {
                    let previous = passage.pose(at:Double(tick-1)/20).eye, next = passage.pose(at:Double(tick)/20).eye
                    precondition(Collision.clear(scene.rootNode,from:previous,to:next,radius:0.2),"Blocked camera in \(passage) at tick \(tick)")
                }
            }
            precondition(scene.rootNode.childNode(withName:"camera",recursively:false)!.actionKeys == ["passage"])
            precondition(scene.rootNode.childNode(withName:passage == .stronghold ? "end-portal" : "portal-surface",recursively:true) != nil)
            if passage == .mine {
                precondition(scene.rootNode.childNode(withName:"landmark-wastes",recursively:true) == nil)
                let last = passage.pose(at:Double(passage.duration))
                precondition(last.eye.z > -34 && last.eye.z <= -33.9)
            } else if passage == .stronghold {
                let portal = scene.rootNode.childNode(withName:"end-portal",recursively:true)!
                let feet = passage.pose(at:Double(passage.duration)).eye.y-1.62
                precondition(feet<=portal.position.y && feet>portal.position.y-0.1)
            }
        }
        print("Installed art: \(Species.allCases.count) species, heroes, \(World.allCases.reduce(0) { $0+$1.biomes.count }) areas and three passages passed in \(Int(Date().timeIntervalSince(start)*1000)) ms")
    }

    @MainActor static func movement(_ factory: Mobs) throws {
        let scene = SCNScene(), actor = SCNNode(), horse = try factory.make(.horse,variant:1)
        let terrain = Terrain(biome:.meadow)
        actor.position = .init(8,terrain.height(8,8),8); actor.addChildNode(horse); scene.rootNode.addChildNode(actor)
        try factory.wander(actor,model:horse,species:.horse,area:.meadow,seed:17,root:scene.rootNode) { x,z in
            .init(x,terrain.height(x.rounded(),z.rounded()),z)
        }
        let renderer = SCNRenderer(device:nil,options:nil); renderer.scene = scene; renderer.isPlaying = true
        SCNTransaction.flush(); renderer.update(atTime:0)
        var before = actor.position, checked = 0, posed = false
        for frame in 1...400 {
            renderer.update(atTime:Double(frame)/20)
            let dx = actor.position.x-before.x, dz = actor.position.z-before.z, distance = hypot(dx,dz)
            if distance>0.001 {
                let forward = horse.presentation.worldFront
                precondition((forward.x*dx+forward.z*dz)/distance>0.95,"Native models must walk forwards: \(forward), delta \(dx), \(dz), actor \(actor.eulerAngles), model \(horse.eulerAngles)")
                let bl = horse.childNode(withName:"LegBL",recursively:true)!.eulerAngles.x
                let br = horse.childNode(withName:"LegBR",recursively:true)!.eulerAngles.x
                let fl = horse.childNode(withName:"LegFL",recursively:true)!.eulerAngles.x
                let fr = horse.childNode(withName:"LegFR",recursively:true)!.eulerAngles.x
                precondition(abs(bl+br)<0.001 && abs(fl+fr)<0.001 && bl*fr>=0 && br*fl>=0)
                posed = posed || abs(fl)>0.1; checked += 1
            }
            before = actor.position
        }
        precondition(checked>10 && posed)
        renderer.scene = nil

        for species in Species.allCases where species != .horse {
            let scene = SCNScene(), actor = SCNNode(), model = try factory.make(species)
            let area: Biome = species.swimming ? .river : .meadow, terrain = Terrain(biome:area)
            func point(_ x: Double, _ z: Double) -> SCNVector3 {
                .init(x,species.swimming ? -2 : terrain.height(x.rounded(),z.rounded())+(species.flying ? 3 : 0),z)
            }
            actor.position = point(species.swimming ? 4 : 8,8)
            actor.addChildNode(model); scene.rootNode.addChildNode(actor)
            try factory.wander(actor,model:model,species:species,area:area,seed:17,root:scene.rootNode,point:point)
            let renderer = SCNRenderer(device:nil,options:nil); renderer.scene = scene; renderer.isPlaying = true
            SCNTransaction.flush(); renderer.update(atTime:0)
            var before = actor.position
            for frame in 1...400 {
                renderer.update(atTime:Double(frame)/20)
                let dx = actor.position.x-before.x, dz = actor.position.z-before.z, distance = hypot(dx,dz)
                if distance>0.001 {
                    let forward = model.presentation.worldFront
                    precondition(forward.x*dx+forward.z*dz>0,"\(species) must not move backwards: \(forward), delta \(dx), \(dz), actor \(actor.eulerAngles), model \(model.eulerAngles)")
                }
                before = actor.position
            }
            renderer.scene = nil
        }

        let schedules = SCNScene(), villager = SCNNode(), body = try factory.make(.villager)
        villager.addChildNode(body); schedules.rootNode.addChildNode(villager)
        var clock = factory.assets.started
        let installed = try factory.routine(villager,model:body,route:[.init(0,0,0),.init(0,0,2),.init(0,0,4)],
            bed:.init(0,0.6,4),facing:0,gather:1,root:schedules.rootNode,seed:0,clock:{ clock })
        precondition(installed)
        let copper = SCNNode(), golem = try factory.make(.golem)
        copper.addChildNode(golem); schedules.rootNode.addChildNode(copper)
        try factory.oxidation(copper,model:golem,stage:0,seed:0,clock:{ clock })
        let animation = SCNRenderer(device:nil,options:nil); animation.scene = schedules; animation.isPlaying = true
        SCNTransaction.flush(); animation.update(atTime:0)
        var moment = 0.0, directions = Set<Int>()
        for phase in [250.0,0,300] {
            clock = factory.assets.started+phase
            for _ in 1...200 {
                let before = villager.position
                moment += 0.05; animation.update(atTime:moment)
                let dx = villager.position.x-before.x, dz = villager.position.z-before.z, distance = hypot(dx,dz)
                if phase != 300 && distance>0.001 {
                    let forward = body.presentation.worldFront
                    precondition((forward.x*dx+forward.z*dz)/distance>0.95,"Villagers must face both their outward and return routes")
                    directions.insert(dz>0 ? 1 : -1)
                }
            }
        }
        precondition(directions == [-1,1])
        precondition(abs(villager.position.z-4)<0.01 && abs(villager.position.y-0.6)<0.01)
        precondition(abs(body.childNode(withName:"body",recursively:true)!.eulerAngles.x-Double.pi/2)<0.01)
        clock = factory.assets.started+28000; animation.update(atTime:moment+0.1)
        var exposed = false
        golem.enumerateChildNodes { node,_ in exposed = exposed || node.geometry?.materials.contains { $0.name?.contains("exposed") == true } == true }
        precondition(exposed)
        clock = factory.assets.started+90000; animation.update(atTime:moment+0.2)
        precondition(copper.action(forKey:"oxidation") == nil)
        animation.scene = nil
    }
}
