import Foundation

public enum LabCacheSource: String, Codable, Sendable {
    case memory
    case disk
    case network
    case unknown
}

public struct LabMetrics: Sendable {
    public let cacheSource: LabCacheSource
    public let loadTimeMs: Double
    public let decodeTimeMs: Double?
    public let bytes: Int?
    public let runMode: BenchmarkMode?

    public init(
        cacheSource: LabCacheSource,
        loadTimeMs: Double,
        decodeTimeMs: Double?,
        bytes: Int?,
        runMode: BenchmarkMode? = nil
    ) {
        self.cacheSource = cacheSource
        self.loadTimeMs = loadTimeMs
        self.decodeTimeMs = decodeTimeMs
        self.bytes = bytes
        self.runMode = runMode
    }
}
