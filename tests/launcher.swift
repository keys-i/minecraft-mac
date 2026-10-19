import AppKit
import Foundation
import SceneKit
import CoreText

@main
struct LauncherChecks {
    @MainActor static func main() throws {
        func status(_ progress: Double?, state: String = "busy") -> Status {
            Status(state: state, title: "Fixture", detail: "", progress: progress)
        }
        let compactSettings = Preferences.scale(in:.init(width:700,height:560))
        let largeSettings = Preferences.scale(in:.init(width:1040,height:800))
        precondition(compactSettings >= 1 && largeSettings > compactSettings)
        precondition(Preferences.scale(in:.zero) == compactSettings)
        precondition(Preferences.scale(in:.init(width:4000,height:3000)) <= 1.5)
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
        precondition(abs(Mobs.classicChance(daylight:1)-0.10)<0.0001)
        precondition(abs(Mobs.classicChance(daylight:0)-0.15)<0.0001)
        let hover = Landscape.pose(.meadow,at:0).eye, nextHover = Landscape.pose(.meadow,at:0.1).eye
        precondition(hypot(hover.x-nextHover.x,hover.z-nextHover.z)>0.05)
        let loop = Landscape.pose(.meadow,at:12).eye
        precondition(hypot(hover.x-loop.x,hover.z-loop.z)<0.001)
        let river = Terrain(biome:.river)
        let swimming = SCNVector3(4+Terrain.noise(0,0,scale:32,seed:9)*9,-1.8,0)
        precondition(Mobs.walkable(from:swimming,to:swimming,species:.cod,terrain:river))
        precondition(!Mobs.walkable(from:swimming,to:swimming,species:.cow,terrain:river))
        precondition(!Mobs.walkable(from:.init(50,-1.8,0),to:.init(50,-1.8,0),species:.cod,terrain:river))
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
        flying.keyDown(with:key(13))
        flying.advance(seconds:0.1)
        precondition(abs(eye.position.z+0.8)<0.001 && eye.position.x == 0)
        flying.keyDown(with:key(2))
        let before = eye.position
        flying.advance(seconds:10)
        precondition(abs(hypot(eye.position.x-before.x,eye.position.z-before.z)-0.8)<0.001)
        flying.stop(); precondition(flying.keys.isEmpty)
        flying.keyDown(with:key(49)); flying.advance(seconds:0.1)
        precondition(abs(eye.position.y-10.8)<0.001)
        flying.keyUp(with:key(49,type:.keyUp))
        flying.flagsChanged(with:key(56,type:.flagsChanged,flags:.shift)); flying.advance(seconds:0.1)
        precondition(abs(eye.position.y-10)<0.001)
        flying.stop()
        flying.flagsChanged(with:key(59,type:.flagsChanged,flags:.control))
        flying.keyDown(with:key(13))
        let sprint = eye.position
        flying.advance(seconds:0.1)
        precondition(abs(hypot(eye.position.x-sprint.x,eye.position.z-sprint.z)-1.6)<0.001)
        flying.stop()
        flying.keyDown(with:key(124)); flying.advance(seconds:0.1)
        precondition(-eye.simdWorldTransform.columns.2.x > 0)
        flying.stop()
        flying.keyDown(with:key(126)); flying.advance(seconds:0.1)
        precondition(-eye.simdWorldTransform.columns.2.y > 0)
        flying.stop()
        var trips = 0
        flying.travel = { step in precondition(step == 1); trips += 1 }
        eye.position = .init(81,12,0)
        flying.advance(seconds:0.1); flying.advance(seconds:0.1)
        precondition(trips == 1)
        let nextEye = SCNNode(); nextEye.camera = SCNCamera(); flightScene.rootNode.addChildNode(nextEye)
        flying.pointOfView = nextEye; flying.install(nextEye,area:.forest)
        precondition(nextEye.position.x == -76 && nextEye.position.y > Terrain(biome:.forest).height(-76,0))
        for area in Biome.allCases {
            let arrival = FlightView.arrival(area,point:.init(81,20,-113),height:10)
            precondition(Terrain(biome:area).height(arrival.x,arrival.z) > -90 && arrival.y.isFinite)
        }
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
        let compressedNBT = try NBT.read(Data(base64Encoded:"H4sIAAAAAAAA/+NiYGBmYMxjYGDQYgAAfbuNUwwAAAA=")!)
        precondition(compressedNBT["n"] as? Int == 42)
        rejects { _ = try NBT.read(nbt.dropLast()) }
        rejects { _ = try NBT.read(nbt+Data([0])) }
        rejects { _ = try NBT.read(Data([10,0,0,9,0,1,108,1,255,255,255,255,0])) }
        var mesh = Voxels()
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
        try write("entity/fixture.entity.json",["minecraft:client_entity":["description":["geometry":["default":"geometry.fixture","warm":"geometry.fixture.warm"],"textures":["default":"textures/entity/fixture","warm":"textures/entity/fixture"]]]])
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
        let menus = Launcher(status:.init(state:"ready",title:"Ready",detail:"",progress:nil),background:NSImage(),assets:art)
        menus.showSettings(); precondition(menus.settings && !menus.help)
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
        let tinted = try art.texture("textures/entity/fixture",tint:0x2080E0)
        let bitmap = tinted.diffuse.contents as! CGImage
        let rgba = Array(bitmap.dataProvider!.data! as Data)
        let tintSamples = stride(from:0,to:rgba.count,by:4).map { Array(rgba[$0..<$0+4]) }
        precondition(tintSamples.contains([32,128,224,255]) && tintSamples.contains(where: { $0[3] == 0 }),"Tinted RGBA: \(tintSamples)")
        let warm = try art.actor("fixture",texture:"warm")
        precondition(abs(warm.boundingBox.max.x-warm.boundingBox.min.x-0.125)<0.001)
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
        precondition(World.overworld.biomes.count == 25 && World.nether.biomes.count == 5)
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
        var frames: [String:NSImage]?
        assets.icons { images,stone,loaded,font,splash in
            precondition(Thread.isMainThread && images.count == 4 && stone != nil)
            precondition(font.map { CTFontCopyPostScriptName($0) as String } == "Minecraft-Ten" && !splash.isEmpty && loaded["title"] != nil)
            frames = loaded
        }
        let artLimit = Date().addingTimeInterval(5)
        while frames == nil && Date() < artLimit { RunLoop.main.run(until:Date().addingTimeInterval(0.01)) }
        precondition(frames?["hotbar_0"] != nil && frames?["selected_hotbar_slot"] != nil)
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
        for species in Species.allCases { _ = try factory.make(species); _ = try factory.locomotion(species) }
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
        var lastBat = bat.position, movingFrames = 0, heights = [Double]()
        for frame in 1...60 {
            airborneAnimation.update(atTime:Double(frame)/10)
            if hypot(bat.position.x-lastBat.x,bat.position.z-lastBat.z)>0.001 { movingFrames += 1 }
            lastBat = bat.position; heights.append(shell.position.y)
        }
        precondition(movingFrames>=58,"Flying bats must not wait between their route segments")
        precondition(heights.max()!-heights.min()!>0.8 && base.position.y == basePosition.y,"Crystal shells float while the base stays still")
        airborneAnimation.scene = nil
        let plainsWater = try assets.water(.meadow), riverWater = try assets.water(.river)
        precondition(plainsWater == 0x44AFF5 && riverWater == 0x0084FF)
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
        for lava in [false,true] {
            let material = try Landscape.flow(assets:assets,lava:lava), node = SCNNode()
            Landscape.animate(node,material:material)
            let image = material.diffuse.contents as! CGImage
            precondition(image.height > image.width && image.height%image.width == 0)
            precondition(abs(material.diffuse.contentsTransform.m22-Double(image.width)/Double(image.height)) < 0.0001)
            precondition(material.transparency == 1 && material.lightingModel == .constant)
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
                        precondition(Collision.clear(scene.rootNode,from:.init(0,1.62,-12),to:.init(12,1.62,-12)))
                        precondition(!Collision.clear(scene.rootNode,from:.init(12,1.62,-12),to:.init(17,1.62,-12)))
                    } else {
                        precondition(Collision.clear(scene.rootNode,from:.init(0,1.62,0),to:.init(9,1.62,0)))
                        precondition(Collision.clear(scene.rootNode,from:.init(0,2.8,-14),to:.init(6,2.8,-14)))
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
                    for frame in 0...20 { flight.update(atTime:Double(frame)/10) }
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
                precondition(residents.count >= world.biomes[index].residents.count*2 || world.biomes[index] == .deep)
                precondition(residents.count <= 40)
                for resident in residents {
                    let p = resident.position
                    let floor = Landscape.height(area,x:p.x.rounded(),z:p.z.rounded())
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
            precondition(scene.rootNode.childNode(withName:"camera",recursively:false)!.actionKeys == ["passage"])
            precondition(scene.rootNode.childNode(withName:passage == .stronghold ? "end-portal" : "portal-surface",recursively:true) != nil)
            if passage == .mine {
                precondition(scene.rootNode.childNode(withName:"landmark-wastes",recursively:true) != nil)
                let last = passage.pose(at:Double(passage.duration))
                precondition(last.eye.z > -34 && last.eye.z <= -33.9)
            } else if passage == .stronghold {
                let portal = scene.rootNode.childNode(withName:"end-portal",recursively:true)!
                precondition(passage.pose(at:Double(passage.duration)).eye.y > portal.position.y+0.05 && passage.pose(at:Double(passage.duration)).eye.y <= portal.position.y+0.15)
            }
        }
        print("Installed art: \(Species.allCases.count) species, heroes, \(World.allCases.reduce(0) { $0+$1.biomes.count }) areas and three passages passed in \(Int(Date().timeIntervalSince(start)*1000)) ms")
    }
}
