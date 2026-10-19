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
        }
        print("Native progress, six motion stop conditions, release filtering and four bounded adventure scenes passed")
        print("Four scene graphs constructed in \(Int(Date().timeIntervalSince(start) * 1000)) ms")
    }
}
