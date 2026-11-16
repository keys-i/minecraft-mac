import Foundation

// One serial owner keeps the isolated server and the native database reader apart
final class Generation: Operation, @unchecked Sendable {
    static let queue: OperationQueue = {
        let queue = OperationQueue(); queue.name = "Minecraft world generation"
        queue.maxConcurrentOperationCount = 1; queue.qualityOfService = .utility
        return queue
    }()
    let root: URL
    let request: [String:Any]
    let receive: @MainActor ([String:Any]) -> Void
    let complete: @MainActor (Error?) -> Void
    private let lock = NSLock()
    private var process: Process?

    init(root: URL, request: [String:Any], receive: @escaping @MainActor ([String:Any]) -> Void,
         complete: @escaping @MainActor (Error?) -> Void) {
        self.root = root; self.request = request; self.receive = receive; self.complete = complete
    }

    override func cancel() {
        super.cancel()
        lock.lock(); defer { lock.unlock() }
        if process?.isRunning == true { process?.terminate() }
    }

    override func main() {
        let result = Result { try run() }
        guard !isCancelled else { return }
        DispatchQueue.main.async { [self] in
            guard !isCancelled else { return }
            switch result { case .success: complete(nil); case .failure(let error): complete(error) }
        }
    }

    private func run() throws {
        let folder = root.appendingPathComponent("scenery")
        if (try? folder.resourceValues(forKeys:[.isSymbolicLinkKey]).isSymbolicLink) == true { throw ChunkError.format }
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
        let path = folder.appendingPathComponent("request-"+UUID().uuidString+".json")
        try JSONSerialization.data(withJSONObject:request).write(to:path,options:[.atomic])
        defer { try? FileManager.default.removeItem(at:path) }
        let resources = Bundle.main.resourceURL!
        let worker = resources.appendingPathComponent("worker/BedrockWorker")
        let packaged = FileManager.default.isExecutableFile(atPath:worker.path)
        let task = Process(), pipe = Pipe()
        task.executableURL = packaged ? worker : root.appendingPathComponent("target/release/MinecraftWorker")
        let development = root.appendingPathComponent("runtime/standalone/wine")
        let installed = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Bedrock for Mac/runtime/standalone/wine")
        let wine = packaged ? resources.appendingPathComponent("runtime/wine") : FileManager.default.fileExists(atPath:development.appendingPathComponent("bin/wine").path) ? development : installed
        task.arguments = ["--scenery"]
            + ["--root",root.path,"--wine",wine.path,"--network",resources.appendingPathComponent("Network.dylib").path,"--request",path.path]
        task.currentDirectoryURL = resources
        task.environment = ProcessInfo.processInfo.environment.filter { key,_ in
            !["CX_","WINE","DYLD_"].contains(where:key.hasPrefix)
        }
        if packaged { task.environment?["BEDROCK_BUNDLE"] = resources.path }
        task.standardOutput = pipe; task.standardError = FileHandle.nullDevice
        lock.lock()
        if isCancelled { lock.unlock(); return }
        do { try task.run(); process = task; lock.unlock() }
        catch { lock.unlock(); throw error }
        defer { lock.lock(); process = nil; lock.unlock(); try? pipe.fileHandleForReading.close() }
        var buffer = Data(), failure: String?
        while true {
            let data = pipe.fileHandleForReading.availableData
            if data.isEmpty { break }
            buffer.append(data)
            while let end = buffer.firstIndex(of:10) {
                let line = Data(buffer[..<end]); buffer.removeSubrange(...end)
                guard line.count<=64*1024, let value = try? JSONSerialization.jsonObject(with:line) as? [String:Any] else { continue }
                if value["state"] as? String == "world_error" { failure = value["detail"] as? String }
                DispatchQueue.main.async { [self] in if !isCancelled { receive(value) } }
            }
            if buffer.count>64*1024 { cancel(); break }
        }
        task.waitUntilExit()
        if !isCancelled, task.terminationStatus != 0 { throw ChunkError.database(failure ?? "World generation stopped; try again") }
    }
}
