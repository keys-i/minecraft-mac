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
            precondition(world.biomes.count == 3)
            let landscape = Landscape.scene(world)
            var sceneryNodes = 0, triangles = 0, residents = 0
            var sceneryMaterials = Set<ObjectIdentifier>()
            landscape.rootNode.enumerateChildNodes { node, _ in
                sceneryNodes += 1
                if node.name?.hasPrefix("resident-") == true { residents += 1 }
                for element in node.geometry?.elements ?? [] where element.primitiveType == .triangles {
                    triangles += element.primitiveCount
                }
                for material in node.geometry?.materials ?? [] {
                    sceneryMaterials.insert(ObjectIdentifier(material))
                }
            }
            precondition(sceneryNodes < 250 && triangles < 50_000 && sceneryMaterials.count <= 32)
            precondition(residents >= 3)
            precondition(landscape.rootNode.childNode(withName: "terrain", recursively: false)?.geometry != nil)
            if world != .end {
                let surface = landscape.rootNode.childNode(withName: "flowing-surface", recursively: false)!
                let texture = surface.geometry!.firstMaterial!.diffuse.contentsTransform
                precondition(texture.m11 > 1 && texture.m22 > 1)
            }
            let camera = landscape.rootNode.childNode(withName: "camera", recursively: false)!
            Landscape.focus(landscape, biome: 0, animated: false)
            let first = camera.position
            Landscape.focus(landscape, biome: 2, animated: false)
            let last = camera.position
            precondition(first.x != last.x)
            Landscape.focus(landscape, biome: 99, animated: false)
            precondition(camera.position.x == last.x)
            Landscape.focus(landscape, biome: -1, animated: false)
            precondition(camera.position.x == first.x)
            Landscape.focus(landscape, biome: 1, animated: true)
            Landscape.focus(landscape, biome: 2, animated: true)
            precondition(camera.actionKeys == ["journey"])
            print("  Landscape: \(sceneryNodes) nodes, \(triangles) triangles, \(sceneryMaterials.count) materials")
        }
        print("Native progress, motion, release filtering, textures and twelve biome camera states passed")
        print("Actor studies and four landscapes constructed in \(Int(Date().timeIntervalSince(start) * 1000)) ms")
    }
}
