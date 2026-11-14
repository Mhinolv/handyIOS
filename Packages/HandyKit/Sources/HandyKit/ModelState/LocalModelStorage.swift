import Foundation
import CryptoKit

public actor LocalModelStorage: ModelStorage {
    private let root: URL
    public init(root: URL) { self.root = root }

    public func availableBytes() throws -> Int64 {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let values = try root.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values.volumeAvailableCapacityForImportantUsage ?? 0
    }

    public func validates(_ asset: ModelAsset) throws -> Bool {
        try validate(destination(asset), asset: asset)
    }

    public func install(_ temporary: URL, asset: ModelAsset) throws {
        defer { try? FileManager.default.removeItem(at: temporary) }
        guard try validate(temporary, asset: asset) else { throw ModelDownloadError.corrupt }
        let target = destination(asset)
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        // Stage on the same volume, then atomically rename. No partial file is published.
        let staging = target.deletingLastPathComponent().appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: staging) }
        do {
            try FileManager.default.moveItem(at: temporary, to: staging)
            if FileManager.default.fileExists(atPath: target.path) {
                _ = try FileManager.default.replaceItemAt(target, withItemAt: staging)
            } else {
                try FileManager.default.moveItem(at: staging, to: target)
            }
        } catch let error as NSError {
            if error.domain == NSCocoaErrorDomain && error.code == NSFileWriteOutOfSpaceError {
                throw ModelDownloadError.noSpace
            }
            throw error
        }
    }

    private func destination(_ asset: ModelAsset) -> URL {
        root.appendingPathComponent(asset.repository).appendingPathComponent(asset.revision).appendingPathComponent(asset.path)
    }

    private func validate(_ url: URL, asset: ModelAsset) throws -> Bool {
        guard FileManager.default.fileExists(atPath: url.path) else { return false }
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize
        guard Int64(size ?? -1) == asset.byteCount else { return false }
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        var hash = SHA256()
        while let data = try file.read(upToCount: 1024 * 1024), !data.isEmpty {
            try Task.checkCancellation()
            hash.update(data: data)
        }
        return hash.finalize().map { String(format: "%02x", $0) }.joined() == asset.sha256.lowercased()
    }
}
