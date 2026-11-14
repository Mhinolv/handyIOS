import Foundation

public struct URLSessionModelTransport: ModelTransport {
    public init() {}
    public func download(_ asset: ModelAsset, progress: @escaping @Sendable (Int64) -> Void) async throws -> URL {
        let delegate = DownloadProgress(progress)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let (temporary, response) = try await session.download(from: asset.url, delegate: delegate)
        guard let response = response as? HTTPURLResponse, response.statusCode == 200 else {
            try? FileManager.default.removeItem(at: temporary)
            throw ModelDownloadError.http
        }
        return temporary
    }
}

private final class DownloadProgress: NSObject, URLSessionDownloadDelegate, Sendable {
    let progress: @Sendable (Int64) -> Void
    init(_ progress: @escaping @Sendable (Int64) -> Void) { self.progress = progress }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) { progress(totalBytesWritten) }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {}
}
