import Foundation
import SceneKit

@main
struct LauncherChecks {
    @MainActor static func main() {
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
        let start = Date()
        for world in World.allCases {
            let scene = VoxelAdventure.scene(world)
            precondition(scene.rootNode.childNode(withName: "camera", recursively: false)?.camera != nil)
            var nodes = 0
            var actions = 0
            var materials = Set<ObjectIdentifier>()
            scene.rootNode.enumerateChildNodes { node, _ in
                nodes += 1
                if node.hasActions { actions += 1 }
                for material in node.geometry?.materials ?? [] {
                    materials.insert(ObjectIdentifier(material))
                    let image = material.diffuse.contents as! CGImage
                    precondition(image.width == 16 && image.height == 16)
                    precondition(material.diffuse.magnificationFilter == .nearest)
                    precondition(!image.shouldInterpolate)
                }
            }
            precondition(nodes < 100 && actions > 0 && materials.count <= 6)
            if world == .overworld || world == .nether {
                let actor = scene.rootNode.childNode(withName: world == .overworld ? "happy-ghast" : "ghast", recursively: false)!
                let body = actor.childNode(withName: "body", recursively: false)!.geometry as! SCNBox
                precondition(body.width == body.height && body.height == body.length)
                let lengths = (0..<9).map { index in
                    let joint = actor.childNode(withName: "tentacle-\(index)", recursively: false)!
                    let tentacle = joint.childNodes[0]
                    let box = tentacle.geometry as! SCNBox
                    precondition(abs(Double(tentacle.position.y) + box.height / 2) < 0.0001)
                    return box.height
                }
                precondition(Set(lengths).count > 1)
            }
            print("\(world.title): \(nodes) nodes, \(materials.count) shared 16×16 materials")
            precondition(!world.biomes.isEmpty)
            precondition(world.index(-1) == 0 && world.index(999) == world.biomes.count - 1)
            for start in stride(from: 0, to: world.biomes.count, by: 3) {
                let landscape = Landscape.scene(world, biome: start)
                var sceneryNodes = 0, triangles = 0, residents = 0
                var sceneryMaterials = Set<ObjectIdentifier>()
                var species = Set<String>()
                landscape.rootNode.enumerateChildNodes { node, _ in
                    sceneryNodes += 1
                    if node.name?.hasPrefix("resident-") == true { residents += 1 }
                    if let name = node.name, name.hasPrefix("mob-") { species.insert(name) }
                    for element in node.geometry?.elements ?? [] where element.primitiveType == .triangles {
                        triangles += element.primitiveCount
                    }
                    for material in node.geometry?.materials ?? [] {
                        sceneryMaterials.insert(ObjectIdentifier(material))
                        let image = material.diffuse.contents as! CGImage
                        precondition(image.width == 16 && image.height == 16)
                    }
                }
                print("  Page \(start/3): \(sceneryNodes) nodes, \(triangles) triangles, \(sceneryMaterials.count) materials, \(species.count) species")
                precondition(sceneryNodes < 250 && triangles < 45_000 && sceneryMaterials.count <= 48)
                precondition(residents >= 6 && species.count >= (world == .end ? 2 : 3))
                precondition(landscape.rootNode.childNode(withName: "terrain", recursively: false)?.geometry != nil)
                if world != .end {
                    let surface = landscape.rootNode.childNode(withName: "flowing-surface", recursively: false)!
                    let texture = surface.geometry!.firstMaterial!.diffuse.contentsTransform
                    precondition(texture.m11 > 1 && texture.m22 > 1)
                }
                let camera = landscape.rootNode.childNode(withName: "camera", recursively: false)!
                Landscape.focus(landscape, world: world, biome: start, animated: false)
                let first = camera.position
                let lastIndex = min(start + 2, world.biomes.count - 1)
                Landscape.focus(landscape, world: world, biome: lastIndex, animated: false)
                precondition(first.x != camera.position.x)
                Landscape.focus(landscape, world: world, biome: start + 1, animated: true)
                Landscape.focus(landscape, world: world, biome: lastIndex, animated: true)
                precondition(camera.actionKeys == ["journey"])
                if world == .overworld, world.areas(start).contains(.pale) {
                    let creaking = landscape.rootNode.childNodes.first { $0.name?.hasPrefix("resident-creaking-") == true }!
                    Landscape.focus(landscape, world: world, biome: world.biomes.firstIndex(of: .pale)!, animated: false)
                    precondition(!creaking.isHidden)
                    Landscape.focus(landscape, world: world, biome: world.biomes.firstIndex(of: .coast)!, animated: false)
                    precondition(creaking.isHidden)
                }
            }

        }
        precondition(Landscape.height(.lush, x: 1, z: 3, centre: 0) == 0)
        precondition(Landscape.height(.coast, x: 1, z: 3, centre: 0) == 0)
        precondition(Landscape.height(.coast, x: 1, z: 8, centre: 0) > 0)
        let roster = Set(World.allCases.flatMap { $0.biomes.flatMap(\.residents) })
        precondition(roster == Set(Species.allCases))
        precondition(World.overworld.biomes.count == 14 && World.nether.biomes.count == 5)
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
            let scene = passage.scene()
            let camera = scene.rootNode.childNode(withName: "camera", recursively: false)!
            precondition(camera.actionKeys == ["passage"])
            precondition(scene.rootNode.childNode(withName: passage == .stronghold ? "end-portal" : "portal-surface", recursively: true) != nil)
            let first = passage.pose(at: -1), last = passage.pose(at: 999)
            precondition(first.eye.z > last.eye.z)
            for tick in 0...140 {
                let pose = passage.pose(at: Double(tick) / 10)
                precondition(pose.eye.x.isFinite && pose.eye.y.isFinite && pose.eye.z.isFinite)
                if tick > 0 {
                    let before = passage.pose(at: Double(tick - 1) / 10)
                    precondition(abs(pose.eye.z - before.eye.z) < 1.1)
                }
            }
        }
        print("Native progress, motion gates, 31 areas, 42 species and cancellable portal journeys passed")
        print("All native graphs constructed in \(Int(Date().timeIntervalSince(start) * 1000)) ms")
    }
}
