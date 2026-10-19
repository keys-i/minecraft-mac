import AVFoundation
import Combine

@MainActor
final class Music: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published private(set) var title = "Minecraft music"
    private var player: AVAudioPlayer?
    private var operation: Operation?
    private var request = 0
    private var active = false
    private var assets: Assets?
    private var previous: String?
    private var volume: Float = 0.18

    static func enabled(muted: Bool, active: Bool, visible: Bool, playing: Bool) -> Bool {
        !muted && active && visible && !playing
    }

    func update(assets: Assets?, active: Bool, volume: Double) {
        if self.assets !== assets { stop(); self.assets = assets }
        self.active = active
        self.volume = Float(min(1,max(0,volume)))
        player?.volume = self.volume
        guard active, let assets else {
            player?.pause()
            operation?.cancel(); operation = nil; request += 1
            return
        }
        if let player { player.play(); return }
        guard operation == nil else { return }
        request += 1
        let request = request
        operation = assets.song(excluding:previous) { [weak self] loaded in
            guard let self, self.request == request, self.active else { return }
            self.operation = nil
            guard let (player,path) = loaded else { self.title = "Music unavailable in this installation"; return }
            self.player = player; self.previous = path
            self.title = URL(fileURLWithPath:path).deletingPathExtension().lastPathComponent
                .replacingOccurrences(of:"_",with:" ").capitalized
            player.delegate = self; player.volume = self.volume
            if !player.play() { self.player = nil; self.title = "Music couldn’t start" }
        }
    }

    #if LAUNCHER_TEST
    var isPlaying: Bool { player?.isPlaying == true }
    var pending: Bool { operation != nil }
    #endif

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        guard self.player === player else { return }
        let volume = Double(player.volume)
        self.player = nil
        if flag { update(assets:assets,active:active,volume:volume) }
        else { title = "Music couldn’t finish playing" }
    }

    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        guard self.player === player else { return }
        self.player = nil; title = "Music couldn’t be decoded"
    }

    func stop() {
        active = false; request += 1
        operation?.cancel(); operation = nil
        player?.stop(); player?.delegate = nil; player = nil
    }
}

extension Assets {
    @discardableResult
    func song(excluding previous: String?, completion: @escaping @MainActor ((AVAudioPlayer,String)?) -> Void) -> Operation {
        let operation = BlockOperation()
        operation.addExecutionBlock { [weak operation] in
            guard let operation, !operation.isCancelled else { return }
            var loaded: (AVAudioPlayer,String)?
            let tracks = ((try? self.music()) ?? []).shuffled()
            for path in tracks where path != previous || tracks.count == 1 {
                guard !operation.isCancelled else { break }
                if let data = try? self.file(path), !data.isEmpty, data.count <= 32*1024*1024,
                   let player = try? AVAudioPlayer(data:data), player.duration > 0, player.duration <= 1200,
                   player.prepareToPlay() {
                    loaded = (player,path); break
                }
            }
            self.releaseArchives()
            guard !operation.isCancelled else { return }
            DispatchQueue.main.async { if !operation.isCancelled { completion(loaded) } }
        }
        queue.addOperation(operation)
        return operation
    }
}
