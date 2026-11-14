import XCTest
import CryptoKit
@testable import HandyKit

private let goodData = Data("model".utf8)
private func asset(_ name: String = "model.bin") -> ModelAsset {
    ModelAsset(repository: "test/model", revision: String(repeating: "a", count: 40), path: name,
               byteCount: 5, sha256: SHA256.hash(data: goodData).map { String(format: "%02x", $0) }.joined())
}
private actor FakeStorage: ModelStorage {
    var valid: Set<String> = []
    var free: Int64 = 100
    var installs = 0
    var failInstallWithNoSpace = false
    func availableBytes() -> Int64 { free }
    func validates(_ asset: ModelAsset) -> Bool { valid.contains(asset.path) }
    func install(_ temporary: URL, asset: ModelAsset) throws {
        defer { try? FileManager.default.removeItem(at: temporary) }
        if failInstallWithNoSpace { free = 2; throw ModelDownloadError.noSpace }
        let data = try Data(contentsOf: temporary)
        guard data == goodData else { throw ModelDownloadError.corrupt }
        valid.insert(asset.path)
        installs += 1
    }
    func setFree(_ bytes: Int64) { free = bytes }
    func setNoSpaceFailure() { failInstallWithNoSpace = true }
}
private actor FakeTransport: ModelTransport {
    var data = goodData
    var calls = 0
    var pause = false
    func setData(_ value: Data) { data = value }
    func setPause() { pause = true }
    func download(_ asset: ModelAsset, progress: @escaping @Sendable (Int64) -> Void) async throws -> URL {
        calls += 1
        if pause { try await Task.sleep(for: .seconds(30)) }
        try Task.checkCancellation()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try data.write(to: url)
        progress(Int64(data.count))
        return url
    }
}

@MainActor
final class ModelDownloadTests: XCTestCase {
    func testAllFilesRequiredAndOfflineRefresh() async {
        let storage = FakeStorage(), transport = FakeTransport()
        let manager = ModelDownloadManager(manifest: .init(assets: [asset(), asset("vad.bin")]), transport: transport, storage: storage)
        manager.start()
        await manager.waitUntilFinished()
        XCTAssertEqual(manager.state, .ready)
        await manager.refresh()
        XCTAssertEqual(manager.state, .ready)
        let calls = await transport.calls
        XCTAssertEqual(calls, 2)
    }

    func testPartialAndCorruptFilesAllowRetry() async {
        for invalid in [Data("mo".utf8), Data("wrong".utf8)] {
            let storage = FakeStorage(), transport = FakeTransport()
            await transport.setData(invalid)
            let manager = ModelDownloadManager(manifest: .init(assets: [asset()]), transport: transport, storage: storage)
            manager.start()
            await manager.waitUntilFinished()
            XCTAssertEqual(manager.state, .corrupt)
            await transport.setData(goodData)
            manager.start()
            await manager.waitUntilFinished()
            XCTAssertEqual(manager.state, .ready)
        }
    }

    func testLowSpaceDoesNotStartNetworkAndRetryWorks() async {
        let storage = FakeStorage(), transport = FakeTransport()
        await storage.setFree(2)
        let manager = ModelDownloadManager(manifest: .init(assets: [asset()]), transport: transport, storage: storage)
        manager.start()
        await manager.waitUntilFinished()
        XCTAssertEqual(manager.state, .lowSpace(missing: 3))
        let calls = await transport.calls
        XCTAssertEqual(calls, 0)
        await storage.setFree(100)
        manager.start()
        await manager.waitUntilFinished()
        XCTAssertEqual(manager.state, .ready)
    }

    func testNoSpaceDuringInstallReportsRemainingByteDeficit() async {
        let storage = FakeStorage(), transport = FakeTransport()
        await storage.setNoSpaceFailure()
        let manager = ModelDownloadManager(manifest: .init(assets: [asset(), asset("vad.bin")]), transport: transport, storage: storage)
        manager.start()
        await manager.waitUntilFinished()
        XCTAssertEqual(manager.state, .lowSpace(missing: 8))
        XCTAssertEqual(manager.availableBytes, 2)
    }

    func testRealStorageExcludesModelFolderFromBackup() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("Application Support/Models")
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent().deletingLastPathComponent()) }
        let storage = LocalModelStorage(root: root)
        _ = try await storage.availableBytes()
        let values = try URL(fileURLWithPath: root.path).resourceValues(forKeys: [.isExcludedFromBackupKey])
        XCTAssertEqual(values.isExcludedFromBackup, true)
    }

    func testRetryKeepsValidatedFiles() async {
        let storage = FakeStorage(), transport = FakeTransport()
        try! await storage.install(makeFile(goodData), asset: asset())
        let manager = ModelDownloadManager(manifest: .init(assets: [asset(), asset("vad.bin")]), transport: transport, storage: storage)
        manager.start()
        await manager.waitUntilFinished()
        let calls = await transport.calls
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(manager.state, .ready)
    }

    func testCancelCannotPublishReady() async {
        let storage = FakeStorage(), transport = FakeTransport()
        await transport.setPause()
        let manager = ModelDownloadManager(manifest: .init(assets: [asset()]), transport: transport, storage: storage)
        manager.start()
        await Task.yield()
        manager.cancel()
        XCTAssertEqual(manager.state, .notDownloaded)
        await Task.yield()
        XCTAssertEqual(manager.state, .notDownloaded)
    }

    func testEmptyAndMovingManifestFailClosed() async {
        let moving = ModelAsset(repository: "test/model", revision: "main", path: "model", byteCount: 5, sha256: String(repeating: "a", count: 64))
        for manifest in [ModelManifest(assets: []), .init(assets: [moving])] {
            let transport = FakeTransport()
            let manager = ModelDownloadManager(manifest: manifest, transport: transport, storage: FakeStorage())
            manager.start()
            XCTAssertEqual(manager.state, .configurationRequired)
            let calls = await transport.calls
            XCTAssertEqual(calls, 0)
        }
    }

    func testProductionManifestIsConfiguredAndHasUniquePaths() {
        let manifest = ModelManifest.production
        XCTAssertTrue(manifest.isConfigured)
        let paths = manifest.assets.map { $0.repository + "/" + $0.path }
        XCTAssertEqual(Set(paths).count, paths.count)
        XCTAssertEqual(manifest.assets.count, 26)
        XCTAssertEqual(manifest.totalBytes, 484_169_070)
    }

    func testRealStorageRejectsPartialAndEqualSizeCorruption() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let storage = LocalModelStorage(root: root)
        for data in [Data("mo".utf8), Data("wrong".utf8)] {
            let temporary = try makeFile(data)
            do {
                try await storage.install(temporary, asset: asset())
                XCTFail("Invalid file passed validation")
            } catch ModelDownloadError.corrupt { }
            XCTAssertFalse(FileManager.default.fileExists(atPath: temporary.path))
            let valid = try await storage.validates(asset())
            XCTAssertFalse(valid)
        }
        try await storage.install(makeFile(goodData), asset: asset())
        let valid = try await storage.validates(asset())
        XCTAssertTrue(valid)
    }

    func testLaunchMarkerSkipsHashesButCompletionAlwaysHashes() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let manifest = ModelManifest(assets: [asset()])
        let storage = LocalModelStorage(root: root)
        try await storage.install(makeFile(goodData), asset: asset())
        let checked = try await storage.validates(manifest, useMarker: false)
        XCTAssertTrue(checked)
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("validated-model.json").path))

        // A new storage instance models a new process, not an in-memory cache.
        let relaunched = LocalModelStorage(root: root)
        let manager = ModelDownloadManager(manifest: manifest, transport: FakeTransport(), storage: relaunched)
        await manager.refresh()
        XCTAssertEqual(manager.state, .ready)
        let launchHashes = await relaunched.hashedFileCount
        XCTAssertEqual(launchHashes, 0)
        let completionCheck = try await relaunched.validates(manifest, useMarker: false)
        XCTAssertTrue(completionCheck)
        let completionHashes = await relaunched.hashedFileCount
        XCTAssertEqual(completionHashes, 1)
    }

    func testMarkerInvalidationRechecksChangedFilesAndManifest() async throws {
        for change in ["date", "size", "revision", "digest", "missing", "malformed", "absent"] {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: root) }
            let storage = LocalModelStorage(root: root)
            let original = asset()
            var manifest = ModelManifest(assets: [original])
            try await storage.install(makeFile(goodData), asset: original)
            _ = try await storage.validates(manifest, useMarker: false)
            let file = root.appendingPathComponent(original.repository).appendingPathComponent(original.revision)
                .appendingPathComponent(original.path)
            let marker = root.appendingPathComponent("validated-model.json")
            switch change {
            case "date":
                // Equal-size corruption must invalidate the date stamp and fail SHA-256.
                try Data("wrong".utf8).write(to: file)
                try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1)], ofItemAtPath: file.path)
            case "size": try Data("mo".utf8).write(to: file)
            case "revision":
                let revised = ModelAsset(repository: original.repository, revision: String(repeating: "b", count: 40),
                                         path: original.path, byteCount: original.byteCount, sha256: original.sha256)
                manifest = ModelManifest(assets: [revised])
                try await storage.install(makeFile(goodData), asset: revised)
            case "digest":
                manifest = ModelManifest(assets: [ModelAsset(repository: original.repository, revision: original.revision,
                    path: original.path, byteCount: original.byteCount, sha256: String(repeating: "b", count: 64))])
            case "missing": try FileManager.default.removeItem(at: file)
            case "malformed": try Data("invalid".utf8).write(to: marker)
            default: try FileManager.default.removeItem(at: marker)
            }
            let relaunched = LocalModelStorage(root: root)
            let valid = try await relaunched.validates(manifest, useMarker: true)
            XCTAssertEqual(valid, ["revision", "malformed", "absent"].contains(change), change)
            let hashes = await relaunched.hashedFileCount
            XCTAssertEqual(hashes, ["size", "missing"].contains(change) ? 0 : 1, change)
            XCTAssertEqual(FileManager.default.fileExists(atPath: marker.path), valid, change)
        }
    }

    private func makeFile(_ data: Data) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try data.write(to: url)
        return url
    }
}
