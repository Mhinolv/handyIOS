import Foundation
import CryptoKit

public actor LocalModelStorage: ModelStorage {
    private let root: URL
    // Internal diagnostic used to assert that launch does not read model contents.
    private(set) var hashedFileCount = 0
    public init(root: URL) { self.root = root }

    public func availableBytes() throws -> Int64 {
        try prepareRoot()
        var directory = root
        directory.removeAllCachedResourceValues()
        let values = try directory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values.volumeAvailableCapacityForImportantUsage ?? 0
    }

    public func validates(_ asset: ModelAsset) throws -> Bool {
        try prepareRoot()
        return try validate(destination(asset), asset: asset)
    }

    public func install(_ temporary: URL, asset: ModelAsset) throws {
        defer { try? FileManager.default.removeItem(at: temporary) }
        try prepareRoot()
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

    private struct FileStamp: Codable, Equatable {
        let repository: String
        let revision: String
        let path: String
        let expectedBytes: Int64
        let sha256: String
        let actualBytes: Int
        let modified: Date
    }

    private struct ValidationMarker: Codable, Equatable {
        let version: Int
        let files: [FileStamp]
    }

    public func validates(_ manifest: ModelManifest, useMarker: Bool) async throws -> Bool {
        try prepareRoot()
        guard manifest.isConfigured else { return false }
        let markerURL = root.appendingPathComponent("validated-model.json")
        guard let before = try stamps(manifest) else {
            try? FileManager.default.removeItem(at: markerURL)
            return false
        }
        let expected = ValidationMarker(version: 1, files: before)
        if useMarker,
           let data = try? Data(contentsOf: markerURL),
           let saved = try? JSONDecoder().decode(ValidationMarker.self, from: data), saved == expected {
            return true
        }
        // Remove stale evidence before the full check. Never leave a marker for corrupt files.
        try? FileManager.default.removeItem(at: markerURL)
        for asset in manifest.assets {
            guard try validate(destination(asset), asset: asset) else { return false }
        }
        // A file that changed during validation cannot receive a marker.
        guard let after = try stamps(manifest), before == after else { return false }
        try Task.checkCancellation()
        try JSONEncoder().encode(expected).write(to: markerURL, options: .atomic)
        return true
    }

    private func stamps(_ manifest: ModelManifest) throws -> [FileStamp]? {
        var result: [FileStamp] = []
        for asset in manifest.assets {
            let url = destination(asset)
            guard FileManager.default.fileExists(atPath: url.path) else { return nil }
            let values = try url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey])
            guard values.isRegularFile == true, let size = values.fileSize,
                  Int64(size) == asset.byteCount, let modified = values.contentModificationDate else { return nil }
            result.append(FileStamp(repository: asset.repository, revision: asset.revision, path: asset.path,
                                    expectedBytes: asset.byteCount, sha256: asset.sha256,
                                    actualBytes: size, modified: modified))
        }
        return result
    }

    private func prepareRoot() throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        var directory = root
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try directory.setResourceValues(values)
    }

    private func destination(_ asset: ModelAsset) -> URL {
        root.appendingPathComponent(asset.repository).appendingPathComponent(asset.revision).appendingPathComponent(asset.path)
    }

    private func validate(_ url: URL, asset: ModelAsset) throws -> Bool {
        guard FileManager.default.fileExists(atPath: url.path) else { return false }
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize
        guard Int64(size ?? -1) == asset.byteCount else { return false }
        hashedFileCount += 1
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
