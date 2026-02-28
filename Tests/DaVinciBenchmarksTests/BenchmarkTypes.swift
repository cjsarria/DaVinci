import Foundation

/// Result for a single benchmark scenario run (one engine).
public struct BenchmarkResult: Codable, Sendable {
    public let scenario: String
    public let engine: String
    public let durationSeconds: Double
    public let cpuSeconds: Double?
    public let peakMemoryBytes: Int?
    public let networkStartCount: Int
    public let totalRequests: Int
    public let completedCount: Int?
    public let cancelledCount: Int?
    public let dedupSupported: Bool?
    public let warmImprovementPercent: Double?
    public let timestamp: String

    public init(
        scenario: String,
        engine: String,
        durationSeconds: Double,
        cpuSeconds: Double? = nil,
        peakMemoryBytes: Int? = nil,
        networkStartCount: Int,
        totalRequests: Int,
        completedCount: Int? = nil,
        cancelledCount: Int? = nil,
        dedupSupported: Bool? = nil,
        warmImprovementPercent: Double? = nil,
        timestamp: String = ISO8601DateFormatter().string(from: Date())
    ) {
        self.scenario = scenario
        self.engine = engine
        self.durationSeconds = durationSeconds
        self.cpuSeconds = cpuSeconds
        self.peakMemoryBytes = peakMemoryBytes
        self.networkStartCount = networkStartCount
        self.totalRequests = totalRequests
        self.completedCount = completedCount
        self.cancelledCount = cancelledCount
        self.dedupSupported = dedupSupported
        self.warmImprovementPercent = warmImprovementPercent
        self.timestamp = timestamp
    }
}

/// Thread-safe aggregation of results for report generation.
public actor MetricsAggregator {
    private var results: [BenchmarkResult] = []

    public func add(_ result: BenchmarkResult) {
        results.append(result)
    }

    public func snapshot() -> [BenchmarkResult] {
        results
    }

    public func reset() {
        results = []
    }
}
