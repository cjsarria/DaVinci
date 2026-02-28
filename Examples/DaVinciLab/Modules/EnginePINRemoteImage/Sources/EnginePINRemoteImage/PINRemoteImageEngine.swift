import Foundation
import LabCore

#if canImport(UIKit)
import UIKit
import PINRemoteImage

public final class PINRemoteImageEngine: ImageLoadingEngine {
    public let name: String = "PINRemoteImage"
    private let aggregator: MetricsAggregator

    public init(aggregator: MetricsAggregator) {
        self.aggregator = aggregator
    }

    public func setImage(
        on imageView: LabImageView,
        url: URL,
        targetSize: CGSize?,
        options requestOptions: LabRequestOptions,
        completion: ((LabMetrics) -> Void)?
    ) {
        let start = Date().timeIntervalSinceReferenceDate

        _ = targetSize
        _ = requestOptions

        #if DEBUG
        print("[DaVinciLab][EnginePIN] setImage url=\(url.absoluteString)")
        #endif

        // Cancel any in-flight load so reuse doesn't show wrong image.
        imageView.pin_cancelImageDownload()

        // Use PIN's view API; set image ourselves in completion so we always update UI and record metrics.
        imageView.pin_setImage(from: url) { result in
            let end = Date().timeIntervalSinceReferenceDate
            let loadMs = (end - start) * 1000
            DispatchQueue.main.async {
                if let img = result.image {
                    imageView.image = img
                }
                let lab = LabMetrics(cacheSource: .unknown, loadTimeMs: loadMs, decodeTimeMs: nil, bytes: nil)
                completion?(lab)
            }
        }
    }

    public func prefetch(urls: [URL]) {
        let manager = PINRemoteImageManager.shared()
        for url in urls {
            manager.downloadImage(with: url) { _ in }
        }
    }

    public func clearCaches() {
        PINRemoteImageManager.shared().cache.removeAllObjects()
    }
}

#else

public final class PINRemoteImageEngine: ImageLoadingEngine {
    public let name: String = "PINRemoteImage"

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
