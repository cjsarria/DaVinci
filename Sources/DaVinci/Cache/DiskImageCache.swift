import Foundation
import CryptoKit

public final class DiskImageCache {
    public struct Meta: Codable, Sendable, Equatable {
        public var etag: String?
        public var cachedAt: Date
        public var expiresAt: Date?
        public var contentType: String?

        public init(etag: String?, cachedAt: Date, expiresAt: Date?, contentType: String?) {
            self.etag = etag
            self.cachedAt = cachedAt
            self.expiresAt = expiresAt
            self.contentType = contentType
        }

        public var isExpired: Bool {
            if let expiresAt { return expiresAt <= Date() }
            return false
        }
    }

    public struct Configuration: Sendable {
        public var maxSizeBytes: Int
        public var maxAge: TimeInterval

        public init(maxSizeBytes: Int = 200 * 1024 * 1024, maxAge: TimeInterval = 60 * 60 * 24 * 30) {
            self.maxSizeBytes = max(0, maxSizeBytes)
            self.maxAge = max(0, maxAge)
        }
    }

    private let fileManager: FileManager
    private let directoryURL: URL
    private let lock = NSLock()

    public var configuration: Configuration

    // MARK: - Trimming state (internal, best-effort)

    private static let trimQueue = DispatchQueue(label: "com.davinci.diskcache.trim", qos: .background)
    private var writesSinceLastTrim: Int = 0
    private var lastTrimDate: Date = .distantPast
    private let maxWritesBeforeTrim: Int = 25
    private let minTrimInterval: TimeInterval = 20

    public init(
        directoryURL: URL = DiskImageCache.defaultDirectoryURL(),
        configuration: Configuration = Configuration(),
        fileManager: FileManager = .default
    ) {
        self.directoryURL = directoryURL
        self.configuration = configuration
        self.fileManager = fileManager

        createDirectoryIfNeeded()
    }

    public func getData(for key: CacheKey) -> Data? {
        getEntry(for: key)?.data
    }

    public func getMeta(for key: CacheKey) -> Meta? {
        getEntry(for: key)?.meta
    }

    public func getEntry(for key: CacheKey) -> (data: Data, meta: Meta?)? {
        let url = fileURL(for: key)
        let metaURL = metaFileURL(for: key)
        lock.lock(); defer { lock.unlock() }

        guard let data = try? Data(contentsOf: url) else { return nil }
        let meta: Meta?
        if let metaData = try? Data(contentsOf: metaURL) {
            meta = try? JSONDecoder().decode(Meta.self, from: metaData)
        } else {
            meta = nil
        }
        return (data: data, meta: meta)
    }

    public func setData(_ data: Data, for key: CacheKey) {
        setData(data, for: key, meta: nil)
    }

    public func setData(_ data: Data, for key: CacheKey, meta: Meta?) {
        let url = fileURL(for: key)
        let metaURL = metaFileURL(for: key)
        lock.lock(); defer { lock.unlock() }
        createDirectoryIfNeeded()

        let tmpURL = url.appendingPathExtension("tmp")
        do {
            try data.write(to: tmpURL, options: [.atomic])
            if fileManager.fileExists(atPath: url.path) {
                try fileManager.removeItem(at: url)
            }
            try fileManager.moveItem(at: tmpURL, to: url)
        } catch {
            try? fileManager.removeItem(at: tmpURL)
        }

        if let meta {
            if let encoded = try? JSONEncoder().encode(meta) {
                let metaTmp = metaURL.appendingPathExtension("tmp")
                do {
                    try encoded.write(to: metaTmp, options: [.atomic])
                    if fileManager.fileExists(atPath: metaURL.path) {
                        try fileManager.removeItem(at: metaURL)
                    }
                    try fileManager.moveItem(at: metaTmp, to: metaURL)
                } catch {
                    try? fileManager.removeItem(at: metaTmp)
                }
            }
        } else {
            try? fileManager.removeItem(at: metaURL)
        }

        maybeScheduleTrim()
    }

    public func remove(_ key: CacheKey) {
        let url = fileURL(for: key)
        let metaURL = metaFileURL(for: key)
        lock.lock(); defer { lock.unlock() }
        try? fileManager.removeItem(at: url)
        try? fileManager.removeItem(at: metaURL)
    }

    public func removeAll() {
        lock.lock(); defer { lock.unlock() }
        try? fileManager.removeItem(at: directoryURL)
        createDirectoryIfNeeded()
    }

    public func trimIfNeeded() {
        trim(maxSizeBytes: configuration.maxSizeBytes, maxAge: configuration.maxAge)
    }

    public func trim(maxSizeBytes: Int, maxAge: TimeInterval) {
        let maxSize = max(0, maxSizeBytes)
        let maxAge = max(0, maxAge)

        lock.lock(); defer { lock.unlock() }
        createDirectoryIfNeeded()

        let now = Date()
        let keys: Set<URLResourceKey> = [.contentModificationDateKey, .fileSizeKey, .isDirectoryKey]

        guard let urls = try? fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        ) else {
            return
        }

        var entries: [(url: URL, date: Date, size: Int)] = []
        entries.reserveCapacity(urls.count)

        for url in urls {
            guard let values = try? url.resourceValues(forKeys: keys) else { continue }
            if values.isDirectory == true { continue }

            let date = values.contentModificationDate ?? now
            let size = values.fileSize ?? 0

            if now.timeIntervalSince(date) > maxAge {
                try? fileManager.removeItem(at: url)
                continue
            }

            entries.append((url: url, date: date, size: max(0, size)))
        }

        guard maxSize > 0 else {
            for entry in entries {
                try? fileManager.removeItem(at: entry.url)
            }
            return
        }

        var total = entries.reduce(0) { $0 + $1.size }
        if total <= maxSize { return }

        entries.sort { $0.date < $1.date }

        for entry in entries {
            if total <= maxSize { break }
            try? fileManager.removeItem(at: entry.url)
            total -= entry.size
        }
    }

    // MARK: - Internal helpers

    private func maybeScheduleTrim() {
        let now = Date()

        var shouldTrim = false
        lock.lock()
        writesSinceLastTrim += 1
        let enoughWrites = writesSinceLastTrim >= maxWritesBeforeTrim
        let enoughTime = now.timeIntervalSince(lastTrimDate) >= minTrimInterval
        if enoughWrites && enoughTime {
            writesSinceLastTrim = 0
            lastTrimDate = now
            shouldTrim = true
        }
        lock.unlock()

        guard shouldTrim else { return }

        Self.trimQueue.async { [weak self] in
            self?.trimIfNeeded()
        }
    }

    private func fileURL(for key: CacheKey) -> URL {
        directoryURL.appendingPathComponent(Self.sha256Hex(key.rawValue), isDirectory: false)
    }

    private func metaFileURL(for key: CacheKey) -> URL {
        directoryURL.appendingPathComponent(Self.sha256Hex(key.rawValue) + ".meta.json", isDirectory: false)
    }

    private func createDirectoryIfNeeded() {
        if fileManager.fileExists(atPath: directoryURL.path) { return }
        try? fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    }

    private static func sha256Hex(_ string: String) -> String {
        let digest = SHA256.hash(data: Data(string.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    // Internal test hook (not part of public API)
    func _forceTrimForTests(maxSizeBytes: Int, maxAge: TimeInterval) {
        trim(maxSizeBytes: maxSizeBytes, maxAge: maxAge)
    }

    public static func defaultDirectoryURL() -> URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("DaVinci", isDirectory: true)
    }
}
