import Foundation
import LabCore

#if canImport(UIKit)
import UIKit
import DaVinci

public final class DaVinciEngine: ImageLoadingEngine {
    public let name: String = "DaVinci"
    private let aggregator: MetricsAggregator

    public init(aggregator: MetricsAggregator) {
        self.aggregator = aggregator
    }

    @MainActor
    public func setImage(
        on imageView: LabImageView,
        url: URL,
        targetSize: CGSize?,
        options requestOptions: LabRequestOptions,
        completion: ((LabMetrics) -> Void)?
    ) {
        let start = Date().timeIntervalSinceReferenceDate

        var dvOptions = DaVinciOptions.default
        dvOptions.targetSize = requestOptions.downsampleEnabled ? targetSize : nil
        dvOptions.cachePolicy = .memoryAndDisk
        dvOptions.priority = .normal
        dvOptions.transition = requestOptions.fadeEnabled ? .fade(duration: 0.2) : .none

        #if DEBUG
        print("[DaVinciLab][EngineDaVinci] setImage url=\(url.absoluteString) targetSize=\(String(describing: targetSize))")
        #endif

        // Call setImage directly on main (we're already on main from cellForItemAt).
        // Wrapping in Task { @MainActor in } serialized starts and caused over-cancellation when cells were configured quickly.
        imageView.dv.setImage(with: url, options: dvOptions) { result, metrics in
            let end = Date().timeIntervalSinceReferenceDate
            let loadMs = (end - start) * 1000

            let source: LabCacheSource
            if let m = metrics {
                switch m.cacheSource {
                case .memory: source = .memory
                case .disk: source = .disk
                case .network: source = .network
                }
            } else {
                source = .unknown
            }

            let lab = LabMetrics(
                cacheSource: source,
                loadTimeMs: loadMs,
                decodeTimeMs: metrics?.decodeTimeMs,
                bytes: metrics?.downloadedBytes
            )

            completion?(lab)
        }
    }

    public func prefetch(urls: [URL]) {
        ImagePrefetcher(client: .shared).prefetch(urls)
    }

    public func clearCaches() {
        DaVinciClient.shared.memoryCache.removeAll()
        DaVinciClient.shared.diskCache.removeAll()
    }
}

#else

public final class DaVinciEngine: ImageLoadingEngine {
    public let name: String = "DaVinci"

    public init(aggregator: MetricsAggregator) {
        _ = aggregator
    }

    public func setImage(
        on imageView: LabImageView,
        url: URL,
        targetSize: CGSize?,
        options: LabRequestOptions,
        completion: ((LabMetrics) -> Void)?
    ) {
        _ = imageView
        _ = url
        _ = targetSize
        _ = options
        completion?(LabMetrics(cacheSource: .unknown, loadTimeMs: 0, decodeTimeMs: nil, bytes: nil))
    }

    public func prefetch(urls: [URL]) { _ = urls }
    public func clearCaches() {}
}

#endif
