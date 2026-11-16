import AppKit
import ImageIO
import SceneKit
import SwiftUI

struct Skin: NSViewRepresentable {
    let assets: Assets
    let skin: String
    let cape: String
    let slim: Bool
    let active: Bool
    var failed: (String) -> Void = { _ in }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    enum Failure: LocalizedError {
        case file, size, png, legacy, dimensions(Bool)

        var errorDescription: String? {
            switch self {
            case .file: return "This image couldn't be opened"
            case .size: return "Choose an image smaller than 4 MB"
            case .png: return "Choose a valid PNG image"
            case .legacy: return "Legacy skins use wide arms"
            case .dimensions(let cape):
                return cape ? "Choose a 64 × 32 cape PNG, or an exact scaled version up to 1024 pixels wide"
                    : "Choose a 64 × 64 or 64 × 32 skin PNG, or an exact scaled version up to 1024 pixels wide"
            }
        }
    }

    /// Validate file and pixel bounds before ImageIO allocates the decoded image
    static func image(at url: URL, cape: Bool = false) throws -> CGImage {
        guard url.isFileURL,
              let values = try? url.resourceValues(forKeys:[.isRegularFileKey,.fileSizeKey]),
              values.isRegularFile == true else { throw Failure.file }
        let limit = 4*1024*1024
        guard let size = values.fileSize, size > 0, size < limit else { throw Failure.size }
        let data: Data
        do {
            let file = try FileHandle(forReadingFrom:url)
            defer { try? file.close() }
            data = try file.read(upToCount:limit) ?? Data()
        } catch { throw Failure.file }
        guard data.count < limit else { throw Failure.size }
        guard data.count >= 24, Array(data.prefix(8)) == [137,80,78,71,13,10,26,10],
              let source = CGImageSourceCreateWithData(data as CFData,[kCGImageSourceShouldCache:false] as CFDictionary),
              let type = CGImageSourceGetType(source), type as String == "public.png",
              CGImageSourceGetCount(source) == 1,
              let properties = CGImageSourceCopyPropertiesAtIndex(source,0,nil) as? [CFString:Any],
              let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
              let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue else { throw Failure.png }
        guard width >= 64, width <= 1024, width%64 == 0,
              height == width/2 || !cape && height == width else { throw Failure.dimensions(cape) }
        guard let image = CGImageSourceCreateImageAtIndex(source,0,[kCGImageSourceShouldCacheImmediately:true] as CFDictionary),
              image.width == width, image.height == height else { throw Failure.png }
        return image
    }

    final class View: SCNView {
        var active = false
        var reducedMotion = false
        private var observers: [NSObjectProtocol] = []

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            observers.forEach(NotificationCenter.default.removeObserver)
            observers.removeAll()
            if let window {
                for name in [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification, NSWindow.didChangeOcclusionStateNotification] {
                    observers.append(NotificationCenter.default.addObserver(forName:name,object:window,queue:.main) { [weak self] _ in self?.refresh() })
                }
                observers.append(NotificationCenter.default.addObserver(forName:.NSProcessInfoPowerStateDidChange,object:nil,queue:.main) { [weak self] _ in self?.refresh() })
            }
            refresh()
        }

        func refresh() {
            let moving = scene != nil && active && !reducedMotion && !ProcessInfo.processInfo.isLowPowerModeEnabled
                && window?.isKeyWindow == true && window?.occlusionState.contains(.visible) == true && !isHiddenOrHasHiddenAncestor
                && bounds.width > 0 && bounds.height > 0
            guard isPlaying != moving || rendersContinuously != moving || scene?.isPaused == moving else { return }
            scene?.isPaused = !moving
            isPlaying = moving
            rendersContinuously = moving
            needsDisplay = true
        }

        override func layout() { super.layout(); refresh() }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        func dispose() {
            observers.forEach(NotificationCenter.default.removeObserver)
            observers.removeAll()
            active = false
            scene?.isPaused = true
            isPlaying = false
            rendersContinuously = false
            pointOfView = nil
            scene = nil
        }

        deinit { observers.forEach(NotificationCenter.default.removeObserver) }
    }

    final class Coordinator {
        var input: (skin:String,cape:String,slim:Bool)?
        var request = 0
        var operation: Operation?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> View {
        let view = View(frame:.zero)
        view.backgroundColor = .clear
        view.preferredFramesPerSecond = 15
        view.antialiasingMode = .multisampling2X
        view.allowsCameraControl = false
        view.setAccessibilityRole(.image)
        view.setAccessibilityLabel("Your Minecraft skin")
        return view
    }

    func updateNSView(_ view: View, context: Context) {
        view.active = active
        view.reducedMotion = reduceMotion
        view.refresh()
        let coordinator = context.coordinator
        if let input = coordinator.input, input.skin == skin, input.cape == cape, input.slim == slim { return }
        coordinator.input = (skin,cape,slim)
        coordinator.request += 1
        coordinator.operation?.cancel()
        view.pointOfView = nil
        view.scene = nil
        view.needsDisplay = true
        view.refresh()
        guard !skin.isEmpty else { return }
        let request = coordinator.request, operation = BlockOperation()
        let skin = skin, cape = cape, slim = slim, assets = assets, failed = failed
        coordinator.operation = operation
        operation.addExecutionBlock { [weak operation, weak coordinator, weak view] in
            guard let operation, !operation.isCancelled else { return }
            let result = Result {
                defer { assets.releaseArchives() }
                let skinImage = try Self.image(at:URL(fileURLWithPath:skin))
                guard !slim || skinImage.width == skinImage.height else { throw Failure.legacy }
                let capeImage = try cape.isEmpty ? nil : Self.image(at:URL(fileURLWithPath:cape),cape:true)
                let model = try assets.avatar(skin:skinImage,cape:capeImage,slim:slim)
                model.eulerAngles.y = .pi-0.28
                model.enumerateChildNodes { node,_ in
                    if node.name?.lowercased() == "cape", node.geometry != nil {
                        node.eulerAngles.x -= 0.11
                        VoxelAdventure.sway(node,x:0.035,period:4.5)
                    }
                }
                let scene = SCNScene()
                scene.rootNode.addChildNode(model)
                let camera = SCNNode()
                camera.camera = SCNCamera()
                camera.camera?.usesOrthographicProjection = true
                camera.camera?.orthographicScale = 1.2
                camera.camera?.zNear = 0.01
                camera.camera?.zFar = 20
                camera.position = .init(0,1.05,6)
                scene.rootNode.addChildNode(camera)
                let ambient = SCNNode()
                ambient.light = SCNLight()
                ambient.light?.type = .ambient
                ambient.light?.intensity = 650
                scene.rootNode.addChildNode(ambient)
                let light = SCNNode()
                light.light = SCNLight()
                light.light?.type = .directional
                light.light?.intensity = 700
                light.eulerAngles = .init(-0.5,-0.6,0)
                scene.rootNode.addChildNode(light)
                scene.isPaused = true
                SCNTransaction.flush()
                return (scene,camera)
            }
            guard !operation.isCancelled else { return }
            DispatchQueue.main.async { [weak operation, weak coordinator, weak view] in
                guard let operation, !operation.isCancelled, let coordinator, coordinator.request == request, let view else { return }
                coordinator.operation = nil
                switch result {
                case .success(let (scene,camera)):
                    view.scene = scene
                    view.pointOfView = camera
                    view.needsDisplay = true
                    view.setAccessibilityLabel(cape.isEmpty ? "Your imported Minecraft skin" : "Your imported Minecraft skin and cape")
                    view.setAccessibilityHelp(nil)
                    failed("")
                case .failure(let error):
                    view.setAccessibilityLabel("Skin preview unavailable")
                    let message = (error as? LocalizedError)?.errorDescription ?? "Choose your skin again in Settings → Character"
                    view.setAccessibilityHelp(message)
                    failed(message)
                }
                view.refresh()
            }
        }
        assets.queue.addOperation(operation)
    }

    static func dismantleNSView(_ view: View, coordinator: Coordinator) {
        coordinator.request += 1
        coordinator.operation?.cancel()
        coordinator.operation = nil
        view.dispose()
    }
}
