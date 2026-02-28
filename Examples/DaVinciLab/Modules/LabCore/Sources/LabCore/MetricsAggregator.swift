import Foundation

public final class MetricsAggregator {
    public struct Snapshot: Sendable {
        public let engineName: String
        public let runMode: BenchmarkMode?
        public let count: Int
        public let avgLoadMs: Double
        public let avgDecodeMs: Double?
        public let cacheHitRate: Double?
        public let cacheHitRateIsEstimated: Bool
        public let totalBytes: Int?
        public let totalBytesIsEstimated: Bool
    }

    private let lock = NSLock()
    private var metrics: [String: [LabMetrics]] = [:]

    public init() {}

    public func reset(engineName: String) {
        lock.lock(); defer { lock.unlock() }
        metrics[engineName] = []
    }

    public func record(engineName: String, metric: LabMetrics) {
        lock.lock(); defer { lock.unlock() }
        metrics[engineName, default: []].append(metric)
    }

    public func snapshot(engineName: String) -> Snapshot {
        snapshot(engineName: engineName, runMode: nil)
    }

    public func snapshot(engineName: String, runMode: BenchmarkMode?) -> Snapshot {
        lock.lock(); defer { lock.unlock() }

        let allItems = metrics[engineName] ?? []
        let items: [LabMetrics]
        if let runMode {
            items = allItems.filter { $0.runMode == runMode }
        } else {
            items = allItems
        }
        let count = items.count
        let avgLoad = items.map { $0.loadTimeMs }.reduce(0, +) / Double(max(1, count))

        let decodeValues = items.compactMap { $0.decodeTimeMs }
        let avgDecode: Double? = decodeValues.isEmpty ? nil : (decodeValues.reduce(0, +) / Double(decodeValues.count))

        let knownCache = items.filter { $0.cacheSource != .unknown }
        let hits = knownCache.filter { $0.cacheSource == .memory || $0.cacheSource == .disk }.count
        let hitRate: Double? = knownCache.isEmpty ? nil : (Double(hits) / Double(knownCache.count))
        let hitEstimated = knownCache.count != items.count

        let knownBytes = items.compactMap { $0.bytes }
        let bytesTotal: Int? = knownBytes.isEmpty ? nil : knownBytes.reduce(0, +)
        let bytesEstimated = knownBytes.count != items.count

        return Snapshot(
            engineName: engineName,
            runMode: runMode,
            count: count,
            avgLoadMs: avgLoad,
            avgDecodeMs: avgDecode,
            cacheHitRate: hitRate,
            cacheHitRateIsEstimated: hitEstimated,
            totalBytes: bytesTotal,
            totalBytesIsEstimated: bytesEstimated
        )
    }

    public func allEngineNames() -> [String] {
        lock.lock(); defer { lock.unlock() }
        return Array(metrics.keys).sorted()
    }
}
