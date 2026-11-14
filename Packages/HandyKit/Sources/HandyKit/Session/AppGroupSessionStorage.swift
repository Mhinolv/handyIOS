import Foundation
import Darwin

/// Both processes must use the same App Group directory and this storage adapter.
/// A separate, stable lock file protects read/modify/write across atomic file replacements.
public final class AppGroupSessionStorage: SessionStorage {
    private let directory: URL
    private let localLock = NSLock()

    public init(directory: URL) {
        self.directory = directory
    }

    public convenience init(appGroupIdentifier: String = HandyConfiguration.appGroupIdentifier) throws {
        guard let directory = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier
        ) else { throw AppGroupStorageError.containerUnavailable }
        self.init(directory: directory)
    }

    public func transaction<T>(_ body: (inout Data?) throws -> T) throws -> T {
        localLock.lock()
        defer { localLock.unlock() }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let lockURL = directory.appendingPathComponent("dictation-session.lock")
        let descriptor = open(lockURL.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        defer { close(descriptor) }
        while flock(descriptor, LOCK_EX) != 0 {
            if errno != EINTR { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        }
        defer { flock(descriptor, LOCK_UN) }
        let url = directory.appendingPathComponent("dictation-session.json")
        var data: Data?
        do { data = try Data(contentsOf: url) }
        catch CocoaError.fileReadNoSuchFile { data = nil }
        let original = data
        let result = try body(&data)
        if data != original {
            if let data { try data.write(to: url, options: .atomic) }
            else if original != nil { try FileManager.default.removeItem(at: url) }
        }
        return result
    }
}

public enum AppGroupStorageError: Error {
    case containerUnavailable
}
