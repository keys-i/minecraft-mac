import AppKit
import Foundation
import SceneKit

@main
struct LauncherChecks {
    @MainActor static func main() throws {
        func status(_ progress: Double?, state: String = "busy") -> Status {
            Status(state: state, title: "Fixture", detail: "", progress: progress)
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
        precondition(SceneryMotion.interval >= 1.0 / 20)
        precondition(SceneryMotion.enabled(reduced: false, paused: false, lowPower: false,
                                          active: true, visible: true, playing: false))
        for disabled in 0..<6 {
            precondition(!SceneryMotion.enabled(reduced: disabled == 0, paused: disabled == 1,
                                                lowPower: disabled == 2, active: disabled != 3,
                                                visible: disabled != 4, playing: disabled == 5))
        }
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
        try FileManager.default.createDirectory(at:texture,withIntermediateDirectories:true)
        try pixels.representation(using:.png,properties:[:])!.write(to:texture.appendingPathComponent("fixture.png"))
        try write("entity/fixture.entity.json",["minecraft:client_entity":["description":["geometry":["default":"geometry.fixture"],"textures":["default":"textures/entity/fixture"]]]])
        func model(_ bones: [[String:Any]]) throws {
            try write("models/entity/fixture.geo.json",["geometry.fixture":["texturewidth":2,"textureheight":2,"bones":bones]])
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
        precondition(Landscape.height(.lush, x: 1, z: 3, centre: 0) == -3)
        precondition(Landscape.height(.coast, x: 1, z: 3, centre: 0) == -4)
        precondition(Landscape.height(.coast, x: 1, z: 8, centre: 0) > 0)
        let roster = Set(World.allCases.flatMap { $0.biomes.flatMap(\.residents) })
        precondition(roster == Set(Species.allCases))
        precondition(World.overworld.biomes.count == 20 && World.nether.biomes.count == 5)
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
        print("Asset queue returned in \(String(format:"%.2f",enqueue)) ms and delivered an original-art graph on the main thread")
        loaded = nil
        for species in Species.allCases { _ = try factory.make(species) }
        let breeze = try factory.make(.breeze)
        precondition(breeze.childNodes.filter { $0.name?.hasPrefix("breeze_wind_") == true }.count == 3)
        let blaze = try factory.make(.blaze)
        let rods = blaze.childNodes.filter { $0.name?.hasPrefix("rod-orbit-") == true }.flatMap(\.childNodes)
        precondition(rods.count == 12)
        precondition(Set(rods.map { "\($0.position.x),\($0.position.y),\($0.position.z)" }).count == 12)
        let dragon = try factory.actor("ender_dragon")
        precondition(abs(dragon.boundingBox.min.x+dragon.boundingBox.max.x) < 0.001)
        let start = Date()
        for world in World.allCases {
            for index in world.biomes.indices {
                let scene = try Landscape.scene(world,biome:index,assets:assets)
                var nodes = 0, triangles = 0
                scene.rootNode.enumerateChildNodes { node,_ in
                    nodes += 1
                    triangles += node.geometry?.elements.reduce(0) { $0+$1.primitiveCount } ?? 0
                }
                print("\(world) \(world.biomes[index]): \(nodes) nodes, \(triangles) triangles")
                fflush(stdout)
                precondition(nodes < 1200 && triangles < 150_000)
                precondition(scene.rootNode.childNode(withName:"habitat-detail",recursively:false) != nil)
                for animated in [false,true] {
                    Landscape.focus(scene,world:world,biome:index,animated:animated)
                    precondition(scene.rootNode.childNode(withName:"camera",recursively:false)!.actionKeys == ["journey"])
                }
                let residents = scene.rootNode.childNodes.filter { $0.name?.hasPrefix("resident-") == true }
                precondition(residents.count >= world.biomes[index].residents.count*2 || world.biomes[index] == .deep)
                precondition(residents.count <= 40)
                for resident in residents {
                    let p = resident.position
                    precondition(Landscape.height(world.biomes[index],x:p.x,z:p.z) > -90)
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
                precondition(last.eye.z < -34)
            } else if passage == .stronghold {
                let portal = scene.rootNode.childNode(withName:"end-portal",recursively:true)!
                precondition(passage.pose(at:Double(passage.duration)).eye.y > portal.position.y+0.05 && passage.pose(at:Double(passage.duration)).eye.y <= portal.position.y+0.15)
            }
        }
        print("Installed art: \(Species.allCases.count) species, heroes, \(World.allCases.reduce(0) { $0+$1.biomes.count }) areas and three passages passed in \(Int(Date().timeIntervalSince(start)*1000)) ms")
    }
}
