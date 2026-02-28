import Foundation

#if canImport(UIKit)
import UIKit
#endif

public enum BenchmarkMode: String, Codable, Sendable {
    case cold
    case warm
}

public struct BenchmarkReport: Codable, Sendable {
    public struct EngineSnapshot: Codable, Sendable {
        public let engineName: String
        public let timestamp: Date
        public let count: Int
        public let avgLoadMs: Double
        public let avgDecodeMs: Double?
        public let cacheHitRate: Double?
        public let cacheHitRateIsEstimated: Bool
        public let totalBytes: Int?
        public let totalBytesIsEstimated: Bool
    }

    public let mode: BenchmarkMode
    public let durationSeconds: Double
    public let startedAt: Date
    public let finishedAt: Date
    public let settings: LabRequestOptions
    public let deviceModel: String
    public let systemVersion: String
    public let snapshots: [EngineSnapshot]
}

#if canImport(UIKit)

public final class BenchmarkRunner {
    public struct Configuration: Sendable {
        public var durationSeconds: Double
        public var scrollStep: CGFloat
        public var tickInterval: Double

        public init(durationSeconds: Double = 15, scrollStep: CGFloat = 420, tickInterval: Double = 1.0) {
            self.durationSeconds = durationSeconds
            self.scrollStep = scrollStep
            self.tickInterval = tickInterval
        }
    }

    private weak var scrollView: UIScrollView?
    private let aggregator: MetricsAggregator
    private let engineName: String

    private var timer: Timer?
    private var snapshots: [BenchmarkReport.EngineSnapshot] = []

    public init(scrollView: UIScrollView, engineName: String, aggregator: MetricsAggregator) {
        self.scrollView = scrollView
        self.engineName = engineName
        self.aggregator = aggregator
    }

    public func run(
        mode: BenchmarkMode,
        settings: LabRequestOptions,
        configuration: Configuration = Configuration(),
        completion: @escaping (BenchmarkReport) -> Void
    ) {
        stop()
        snapshots = []

        let startedAt = Date()
        let tick = max(0.2, configuration.tickInterval)
        timer = Timer.scheduledTimer(withTimeInterval: tick, repeats: true) { [weak self] _ in
            self?.tick(scrollStep: configuration.scrollStep)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + configuration.durationSeconds) { [weak self] in
            guard let self else { return }
            self.stop()
            let finishedAt = Date()

            self.appendSnapshot(timestamp: finishedAt)

            completion(
                BenchmarkReport(
                    mode: mode,
                    durationSeconds: configuration.durationSeconds,
                    startedAt: startedAt,
                    finishedAt: finishedAt,
                    settings: settings,
                    deviceModel: UIDevice.current.model,
                    systemVersion: UIDevice.current.systemVersion,
                    snapshots: self.snapshots
                )
            )
        }
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func tick(scrollStep: CGFloat) {
        guard let scrollView else { return }
        appendSnapshot(timestamp: Date())

        let maxY = max(0, scrollView.contentSize.height - scrollView.bounds.height)
        guard maxY > 0 else { return }

        var next = scrollView.contentOffset
        next.y = min(maxY, next.y + scrollStep)
        if next.y >= maxY { next.y = 0 }
        scrollView.setContentOffset(next, animated: true)
    }

    private func appendSnapshot(timestamp: Date) {
        let snap = aggregator.snapshot(engineName: engineName)
        snapshots.append(
            .init(
                engineName: engineName,
                timestamp: timestamp,
                count: snap.count,
                avgLoadMs: snap.avgLoadMs,
                avgDecodeMs: snap.avgDecodeMs,
                cacheHitRate: snap.cacheHitRate,
                cacheHitRateIsEstimated: snap.cacheHitRateIsEstimated,
                totalBytes: snap.totalBytes,
                totalBytesIsEstimated: snap.totalBytesIsEstimated
            )
        )
    }
}

#else

public final class BenchmarkRunner {
    public struct Configuration: Sendable {
        public var durationSeconds: Double
        public var tickInterval: Double

        public init(durationSeconds: Double = 15, tickInterval: Double = 1.0) {
            self.durationSeconds = durationSeconds
            self.tickInterval = tickInterval
        }
    }

    private let aggregator: MetricsAggregator
    private let engineName: String

    private var timer: Timer?
    private var snapshots: [BenchmarkReport.EngineSnapshot] = []

    public init(engineName: String, aggregator: MetricsAggregator) {
        self.engineName = engineName
        self.aggregator = aggregator
    }

    public func run(
        mode: BenchmarkMode,
        settings: LabRequestOptions,
        configuration: Configuration = Configuration(),
        completion: @escaping (BenchmarkReport) -> Void
    ) {
        stop()
        snapshots = []

        let startedAt = Date()
        let tick = max(0.2, configuration.tickInterval)
        timer = Timer.scheduledTimer(withTimeInterval: tick, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.appendSnapshot(timestamp: Date())
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + configuration.durationSeconds) { [weak self] in
            guard let self else { return }
            self.stop()
            let finishedAt = Date()

            self.appendSnapshot(timestamp: finishedAt)

            completion(
                BenchmarkReport(
                    mode: mode,
                    durationSeconds: configuration.durationSeconds,
                    startedAt: startedAt,
                    finishedAt: finishedAt,
                    settings: settings,
                    deviceModel: "Mac",
                    systemVersion: ProcessInfo.processInfo.operatingSystemVersionString,
                    snapshots: self.snapshots
                )
            )
        }
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func appendSnapshot(timestamp: Date) {
        let snap = aggregator.snapshot(engineName: engineName)
        snapshots.append(
            .init(
                engineName: engineName,
                timestamp: timestamp,
                count: snap.count,
                avgLoadMs: snap.avgLoadMs,
                avgDecodeMs: snap.avgDecodeMs,
                cacheHitRate: snap.cacheHitRate,
                cacheHitRateIsEstimated: snap.cacheHitRateIsEstimated,
                totalBytes: snap.totalBytes,
                totalBytesIsEstimated: snap.totalBytesIsEstimated
            )
        )
    }
}

#endif
