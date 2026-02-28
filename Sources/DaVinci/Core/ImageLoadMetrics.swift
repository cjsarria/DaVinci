import Foundation

public enum ImageCacheSource: Sendable {
    case memory
    case disk
    case network
}

public struct ImageLoadMetrics: Sendable {
    public let cacheSource: ImageCacheSource
    public let startTime: TimeInterval
    public let endTime: TimeInterval
    public let networkTimeMs: Double?
    public let decodeTimeMs: Double?
    public let downloadedBytes: Int?

    public init(
        cacheSource: ImageCacheSource,
        startTime: TimeInterval,
        endTime: TimeInterval,
        networkTimeMs: Double?,
        decodeTimeMs: Double?,
        downloadedBytes: Int?
    ) {
        self.cacheSource = cacheSource
        self.startTime = startTime
        self.endTime = endTime
        self.networkTimeMs = networkTimeMs
        self.decodeTimeMs = decodeTimeMs
        self.downloadedBytes = downloadedBytes
    }
}
