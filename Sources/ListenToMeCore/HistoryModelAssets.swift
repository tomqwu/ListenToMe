import CryptoKit
import Foundation

/// Explicit installation of the optional History model. No conversation text enters this owner.
public actor HistoryModelAssets {
    public struct Asset: Sendable {
        public let name: String
        public let bytes: Int64
        public let sha256: String
        public var url: URL {
            URL(string: "https://huggingface.co/sentence-transformers/paraphrase-multilingual-mpnet-base-v2/resolve/"
                + HistoryModelAssets.revision + "/" + name)!
        }
    }
    public enum Status: Sendable, Equatable { case notInstalled, installing, ready, failed(String) }
    public enum AssetError: Error, LocalizedError {
        case busy, invalidAsset(String), unsafeDirectory
        public var errorDescription: String? {
            switch self {
            case .busy: "The search model is already being installed or removed."
            case .unsafeDirectory: "The search model folder must be a local directory without symbolic links."
            case .invalidAsset(let name):
                "The search model file \(name) is missing or failed verification. Try downloading again."
            }
        }
    }
    public static let revision = "4328cf26390c98c5e3c738b4460a05b95f4911f5"
    public static let assets: [Asset] = [
        Asset(name: "config.json", bytes: 723,
              sha256: "8b94b5c10efd3c3ca667e5ccd501314eb670cefbf7a465f0a3fc0928a1a0ab87"),
        Asset(name: "tokenizer.json", bytes: 9081518,
              sha256: "2c3387be76557bd40970cec13153b3bbf80407865484b209e655e5e4729076b8"),
        Asset(name: "tokenizer_config.json", bytes: 402,
              sha256: "a312d5bef89ec4c9355638520a31582e761f205d79df3002a3bd390d7077455f"),
        Asset(name: "special_tokens_map.json", bytes: 239,
              sha256: "378eb3bf733eb16e65792d7e3fda5b8a4631387ca04d2015199c4d4f22ae554d"),
        Asset(name: "sentencepiece.bpe.model", bytes: 5069051,
              sha256: "cfc8146abe2a0488e9e2a0c56de7952f7c11ab059eca145a0a727afce0db2865"),
        Asset(name: "model.safetensors", bytes: 1112201288,
              sha256: "b5722100700c48b74c9c199c5f39ff9493c94d1497f719e791d4bc3861d7714a")
    ]
    public static let totalBytes = assets.reduce(Int64(0)) { $0 + $1.bytes }
    public private(set) var status: Status = .notInstalled
    typealias Downloader = @Sendable (URL, URL, @escaping @Sendable (Double) -> Void) async throws -> Void
    private let directory: URL
    private let inventory: [Asset]
    private let downloader: Downloader
    private var generation = 0
    private var operation: Task<Void, any Error>?
    private var operationID: UUID?
    private var removing = false
    private var progressUpdates: HistoryAssetProgressGate?
    private var installed: URL { directory.appendingPathComponent("mpnet-" + Self.revision, isDirectory: true) }

    public init(directory: URL) {
        self.directory = directory.standardizedFileURL; inventory = Self.assets; downloader = Self.download
    }
    /// Small byte fixtures exercise the same verification/publication path without real downloads.
    init(directory: URL, assets: [Asset], downloader: @escaping Downloader) {
        precondition(!assets.isEmpty && Set(assets.map(\.name)).count == assets.count)
        precondition(assets.allSatisfy { !$0.name.isEmpty && !$0.name.contains("/") && !$0.name.contains("..") })
        self.directory = directory.standardizedFileURL; inventory = assets; self.downloader = downloader
    }

    /// Full local integrity check; never starts a download. Call when opening/loading the model,
    /// not on each keystroke. Hashing runs off the actor so Remove remains responsive.
    public func installedDirectory() async -> URL? {
        guard operation == nil, !removing else { return nil }
        guard (try? validateOwner()) != nil else { status = .notInstalled; return nil }
        let mine = generation; let folder = installed
        let valid = await Self.verified(folder, inventory: inventory)
        guard mine == generation, operation == nil, !removing else { return nil }
        guard (try? validateOwner()) != nil else { status = .notInstalled; return nil }
        status = valid ? .ready : .notInstalled
        return valid ? folder : nil
    }

    public func install(progress: @escaping @Sendable (Double) -> Void = { _ in }) async throws {
        try Task.checkCancellation()
        guard operation == nil, !removing else { throw AssetError.busy }
        try validateOwner()
        generation += 1
        let mine = generation; let id = UUID()
        status = .installing; operationID = id
        let updates = HistoryAssetProgressGate(progress)
        progressUpdates = updates
        let work = Task { try await self.performInstall(generation: mine, progress: { updates.send($0) }) }
        operation = work
        defer {
            updates.close()
            if operationID == id { operation = nil; operationID = nil; progressUpdates = nil }
        }
        do {
            try await withTaskCancellationHandler { try await work.value } onCancel: { updates.close(); work.cancel() }
            try Task.checkCancellation()
        } catch {
            if mine == generation {
                status = error is CancellationError ? .notInstalled : .failed(error.localizedDescription)
            }
            throw error
        }
    }

    /// Revokes publication before waiting for even an uncooperative downloader to exit. Only this
    /// owner's model folder/current staging are removed; other models and history are untouched.
    public func remove() async throws {
        guard !removing else { throw AssetError.busy }
        try validateOwner()
        removing = true; generation += 1; progressUpdates?.close(); status = .notInstalled
        defer { removing = false }
        let work = operation
        work?.cancel()
        _ = await work?.result
        try validateOwner()
        // lstat semantics: never traverse a final model-directory symlink during removal.
        if let attributes = try? FileManager.default.attributesOfItem(atPath: installed.path) {
            guard attributes[.type] as? FileAttributeType == .typeDirectory else { throw AssetError.unsafeDirectory }
            try FileManager.default.removeItem(at: installed)
        }
    }

    /// Reject user-supplied link boundaries. macOS's two standard temporary-path aliases are
    /// allowed only when their actual canonical targets match the known system locations.
    private func validateOwner() throws {
        guard directory.isFileURL else { throw AssetError.unsafeDirectory }
        var component = URL(fileURLWithPath: "/", isDirectory: true)
        for part in directory.pathComponents.dropFirst() {
            component.appendPathComponent(part, isDirectory: true)
            let attributes: [FileAttributeKey: Any]
            do { attributes = try FileManager.default.attributesOfItem(atPath: component.path) } catch {
                let code = (error as NSError).code
                if code == NSFileNoSuchFileError || code == NSFileReadNoSuchFileError { return }
                throw error
            }
            let type = attributes[.type] as? FileAttributeType
            if type == .typeSymbolicLink {
                let systemAliases = ["/var": "/private/var", "/tmp": "/private/tmp"]
                guard let target = systemAliases[component.path],
                      component.path != directory.path else { throw AssetError.unsafeDirectory }
                let destination = try FileManager.default.destinationOfSymbolicLink(atPath: component.path)
                let absolute = destination.hasPrefix("/") ? destination : "/" + destination
                guard absolute == target else { throw AssetError.unsafeDirectory }
            } else if type != .typeDirectory { throw AssetError.unsafeDirectory }
        }
    }

    private func check(_ mine: Int) throws {
        try Task.checkCancellation()
        try validateOwner()
        guard mine == generation, !removing else { throw CancellationError() }
    }
    private func performInstall(generation mine: Int, progress: @escaping @Sendable (Double) -> Void) async throws {
        try check(mine)
        if await Self.verified(installed, inventory: inventory) {
            try check(mine); status = .ready; progress(1); return
        }
        try check(mine)
        try PrivateStorage.createDirectory(at: directory)
        try PrivateStorage.setExcludedFromBackup(true, at: directory)
        let stage = directory.appendingPathComponent(".mpnet-install-" + UUID().uuidString, isDirectory: true)
        try PrivateStorage.createDirectory(at: stage)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: stage.path)
        try PrivateStorage.setExcludedFromBackup(true, at: stage)
        let ownerIdentity = try Self.directoryIdentity(directory)
        let stageIdentity = try Self.directoryIdentity(stage)
        defer {
            // A moved/replaced owner must not redirect cleanup into someone else's folder.
            // Preserve unsafe staging for later review instead of following the new path.
            if (try? validateOwner()) != nil,
               (try? Self.directoryIdentity(directory)) == ownerIdentity,
               (try? Self.directoryIdentity(stage)) == stageIdentity {
                try? FileManager.default.removeItem(at: stage)
            }
        }
        let total = Double(inventory.reduce(Int64(0)) { $0 + $1.bytes })
        var complete: Int64 = 0
        progress(0)
        for asset in inventory {
            try check(mine)
            let completed = Double(complete)
            try await downloader(asset.url, stage.appendingPathComponent(asset.name)) { fraction in
                progress(min(1, max(0, (completed + Double(asset.bytes) * min(1, max(0, fraction))) / total)))
            }
            try check(mine)
            // URLSession moves a temporary file; moving does not inherit iOS directory protection.
            let file = stage.appendingPathComponent(asset.name)
            let attributes = try file.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey])
            guard attributes.isSymbolicLink != true, attributes.isRegularFile == true else {
                throw AssetError.invalidAsset(asset.name)
            }
            var protection = PrivateStorage.directoryAttributes
            protection[.posixPermissions] = 0o600
            try FileManager.default.setAttributes(protection,
                ofItemAtPath: stage.appendingPathComponent(asset.name).path)
            guard await Self.verifiedFile(stage.appendingPathComponent(asset.name), asset: asset) else {
                try check(mine); throw AssetError.invalidAsset(asset.name)
            }
            try check(mine); complete += asset.bytes
        }
        try check(mine)
        // No await between the final cancellation/generation fence and the atomic directory move.
        // An old invalid installation is never offered as ready while being replaced.
        if FileManager.default.fileExists(atPath: installed.path) { try FileManager.default.removeItem(at: installed) }
        try FileManager.default.moveItem(at: stage, to: installed)
        status = .ready; progress(1)
    }

    private struct DirectoryIdentity: Equatable {
        let device: UInt64
        let inode: UInt64
    }
    private static func directoryIdentity(_ url: URL) throws -> DirectoryIdentity {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard attributes[.type] as? FileAttributeType == .typeDirectory,
              let device = attributes[.systemNumber] as? UInt64,
              let inode = attributes[.systemFileNumber] as? UInt64 else { throw AssetError.unsafeDirectory }
        return DirectoryIdentity(device: device, inode: inode)
    }

    private static func verified(_ folder: URL, inventory: [Asset]) async -> Bool {
        guard let values = try? folder.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
              values.isDirectory == true, values.isSymbolicLink != true,
              let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path),
              Set(names) == Set(inventory.map(\.name)) else { return false }
        for asset in inventory {
            guard await verifiedFile(folder.appendingPathComponent(asset.name), asset: asset) else { return false }
        }
        return !Task.isCancelled
    }
    private static func verifiedFile(_ file: URL, asset: Asset) async -> Bool {
        let work = Task.detached(priority: .utility) { () -> Bool in
            do {
                let values = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
                guard values.isRegularFile == true, values.isSymbolicLink != true,
                      values.fileSize.map(Int64.init) == asset.bytes else { return false }
                let handle = try FileHandle(forReadingFrom: file)
                defer { try? handle.close() }
                var hash = SHA256(); var count: Int64 = 0
                while true {
                    try Task.checkCancellation()
                    let bytes = try handle.read(upToCount: 1 << 20) ?? Data()
                    if bytes.isEmpty { break }
                    count += Int64(bytes.count)
                    guard count <= asset.bytes else { return false }
                    hash.update(data: bytes)
                }
                let digest = hash.finalize().map { String(format: "%02x", $0) }.joined()
                return count == asset.bytes && digest == asset.sha256
            } catch { return false }
        }
        return await withTaskCancellationHandler { await work.value } onCancel: { work.cancel() }
    }
    private static func download(_ url: URL, to destination: URL,
                                 progress: @escaping @Sendable (Double) -> Void) async throws {
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        let delegate = HistoryAssetDownloadProgress(progress: progress)
        let (temporary, response) = try await session.download(from: url, delegate: delegate)
        defer { try? FileManager.default.removeItem(at: temporary) }
        try Task.checkCancellation()
        guard let response = response as? HTTPURLResponse, response.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        try FileManager.default.moveItem(at: temporary, to: destination)
    }
}

private final class HistoryAssetDownloadProgress: NSObject, URLSessionDownloadDelegate, Sendable {
    private let progress: @Sendable (Double) -> Void
    init(progress: @escaping @Sendable (Double) -> Void) { self.progress = progress }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {}
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        progress(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
    }
}

/// A producer may ignore cancellation. Closing the gate synchronously prevents its progress from
/// resurrecting an obsolete installation. The callback must only enqueue/update progress briefly.
private final class HistoryAssetProgressGate: @unchecked Sendable {
    private let lock = NSLock()
    private var open = true
    private let callback: @Sendable (Double) -> Void
    init(_ callback: @escaping @Sendable (Double) -> Void) { self.callback = callback }
    func send(_ value: Double) {
        lock.lock(); defer { lock.unlock() }
        if open { callback(value) }
    }
    func close() { lock.lock(); defer { lock.unlock() }; open = false }
}
