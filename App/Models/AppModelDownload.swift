import Foundation
import HandyKit

extension ModelDownloadManager {
    static func appDefault() -> ModelDownloadManager {
        let root = URL.applicationSupportDirectory.appendingPathComponent("Models", isDirectory: true)
        return ModelDownloadManager(manifest: .production, transport: URLSessionModelTransport(), storage: LocalModelStorage(root: root))
    }
}
