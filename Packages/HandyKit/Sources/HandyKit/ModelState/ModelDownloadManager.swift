import Foundation
import Combine

public enum ModelDownloadState: Equatable, Sendable {
    case notDownloaded, downloading(received: Int64, total: Int64), checking, ready
    case stopped, corrupt, lowSpace(missing: Int64), configurationRequired
}

public protocol ModelTransport: Sendable {
    /// Return a temporary file. Cancel the request when the caller task is cancelled.
    func download(_ asset: ModelAsset, progress: @escaping @Sendable (Int64) -> Void) async throws -> URL
}

public protocol ModelStorage: Sendable {
    func availableBytes() async throws -> Int64
    func validates(_ asset: ModelAsset) async throws -> Bool
    func validates(_ manifest: ModelManifest, useMarker: Bool) async throws -> Bool
    /// Validate the temporary file before atomic publication. Always remove the temporary file.
    func install(_ temporary: URL, asset: ModelAsset) async throws
}

public extension ModelStorage {
    func validates(_ manifest: ModelManifest, useMarker: Bool) async throws -> Bool {
        for asset in manifest.assets {
            guard try await validates(asset) else { return false }
        }
        return manifest.isConfigured
    }
}

public enum ModelDownloadError: Error { case corrupt, http, noSpace }

@MainActor
public final class ModelDownloadManager: ObservableObject {
    @Published public private(set) var state: ModelDownloadState = .notDownloaded
    @Published public private(set) var availableBytes: Int64 = 0
    public let manifest: ModelManifest
    private let transport: any ModelTransport
    private let storage: any ModelStorage
    private let now: @Sendable () -> TimeInterval
    private var task: Task<Void, Never>?
    private var generation = UUID()
    private var lastProgress: TimeInterval = -.infinity

    public init(manifest: ModelManifest, transport: any ModelTransport, storage: any ModelStorage,
                now: @escaping @Sendable () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.manifest = manifest
        self.transport = transport
        self.storage = storage
        self.now = now
    }

    public func refresh() async {
        guard task == nil else { return }
        guard manifest.isConfigured else { state = .configurationRequired; return }
        let token = generation
        state = .checking
        do {
            availableBytes = try await storage.availableBytes()
            let valid = try await storage.validates(manifest, useMarker: true)
            guard task == nil, generation == token else { return }
            state = valid ? .ready : .notDownloaded
        } catch { if task == nil, generation == token { state = .stopped } }
    }

    public func start() {
        guard task == nil else { return }
        guard manifest.isConfigured else { state = .configurationRequired; return }
        let token = UUID()
        generation = token
        task = Task { [weak self] in
            guard let self else { return }
            await self.run(token)
            if self.generation == token { self.task = nil }
        }
    }

    public func cancel() {
        generation = UUID()
        task?.cancel()
        task = nil
        state = .notDownloaded
    }

    public func waitUntilFinished() async { await task?.value }

    private func run(_ token: UUID) async {
        guard generation == token, !Task.isCancelled else { return }
        var remainingBytes = manifest.totalBytes
        do {
            state = .checking
            var pending: [ModelAsset] = []
            for asset in manifest.assets {
                if try await !storage.validates(asset) { pending.append(asset) }
                try Task.checkCancellation()
            }
            let required = pending.reduce(Int64(0)) { $0 + $1.byteCount }
            remainingBytes = required
            availableBytes = try await storage.availableBytes()
            try Task.checkCancellation()
            guard availableBytes >= required else {
                if generation == token { state = .lowSpace(missing: required - availableBytes) }
                return
            }
            var completed = manifest.totalBytes - required
            lastProgress = -.infinity
            for asset in pending {
                let base = completed
                state = .downloading(received: completed, total: manifest.totalBytes)
                let temporary = try await transport.download(asset) { [weak self] received in
                    Task { @MainActor in
                        guard let self, self.generation == token, case .downloading = self.state else { return }
                        let time = self.now()
                        guard time - self.lastProgress >= 0.25 else { return }
                        self.lastProgress = time
                        self.state = .downloading(received: base + min(max(0, received), asset.byteCount), total: self.manifest.totalBytes)
                    }
                }
                // The storage owns cleanup, including cancellation after a transfer completes.
                if Task.isCancelled {
                    try? FileManager.default.removeItem(at: temporary)
                    throw CancellationError()
                }
                state = .checking
                try await storage.install(temporary, asset: asset)
                try Task.checkCancellation()
                remainingBytes -= asset.byteCount
                completed += asset.byteCount
                state = .downloading(received: completed, total: manifest.totalBytes)
            }
            state = .checking
            guard try await storage.validates(manifest, useMarker: false) else { throw ModelDownloadError.corrupt }
            try Task.checkCancellation()
            if generation == token { state = .ready }
        } catch {
            guard generation == token else { return }
            if error is CancellationError { state = .notDownloaded }
            else if case ModelDownloadError.corrupt = error { state = .corrupt }
            else if Self.isNoSpace(error) {
                guard let free = try? await storage.availableBytes() else {
                    if generation == token { state = .stopped }
                    return
                }
                guard generation == token else { return }
                availableBytes = free
                state = .lowSpace(missing: max(0, remainingBytes - free))
            }
            else { state = .stopped }
        }
    }

    private static func isNoSpace(_ error: Error) -> Bool {
        if case ModelDownloadError.noSpace = error { return true }
        let error = error as NSError
        return (error.domain == NSCocoaErrorDomain && error.code == NSFileWriteOutOfSpaceError)
            || (error.domain == NSPOSIXErrorDomain && error.code == 28)
    }
}
