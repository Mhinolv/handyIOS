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
    func availableBytes() -> Int64 { free }
    func validates(_ asset: ModelAsset) -> Bool { valid.contains(asset.path) }
    func install(_ temporary: URL, asset: ModelAsset) throws {
        defer { try? FileManager.default.removeItem(at: temporary) }
        let data = try Data(contentsOf: temporary)
        guard data == goodData else { throw ModelDownloadError.corrupt }
        valid.insert(asset.path)
        installs += 1
    }
    func setFree(_ bytes: Int64) { free = bytes }
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

    private func makeFile(_ data: Data) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try data.write(to: url)
        return url
    }
}
