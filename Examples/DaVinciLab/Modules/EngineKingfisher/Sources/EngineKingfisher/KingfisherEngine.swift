import Foundation
import LabCore

#if canImport(UIKit)
import UIKit
import Kingfisher

public final class KingfisherEngine: ImageLoadingEngine {
    public let name: String = "Kingfisher"
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

        var kfOptions: KingfisherOptionsInfo = []
        kfOptions.append(.cacheOriginalImage)

        if requestOptions.fadeEnabled {
            kfOptions.append(.transition(.fade(0.2)))
        }

        if requestOptions.downsampleEnabled, let targetSize {
            let processor = DownsamplingImageProcessor(size: targetSize)
            kfOptions.append(.processor(processor))
            kfOptions.append(.scaleFactor(UIScreen.main.scale))
        }

        imageView.kf.setImage(with: url, options: kfOptions) { result in
            DispatchQueue.main.async {
                let end = Date().timeIntervalSinceReferenceDate
                let loadMs = (end - start) * 1000

                let source: LabCacheSource
                switch result {
                case .success(let value):
                    switch value.cacheType {
                    case .none: source = .network
                    case .memory: source = .memory
                    case .disk: source = .disk
                    }
                case .failure:
                    source = .unknown
                }

                let lab = LabMetrics(cacheSource: source, loadTimeMs: loadMs, decodeTimeMs: nil, bytes: nil)
                completion?(lab)
            }
        }
    }

    public func prefetch(urls: [URL]) {
        let resources = urls.map { KF.ImageResource(downloadURL: $0) }
        Kingfisher.ImagePrefetcher(resources: resources).start()
    }

    public func clearCaches() {
        ImageCache.default.clearMemoryCache()
        ImageCache.default.clearDiskCache()
    }
}

#else

public final class KingfisherEngine: ImageLoadingEngine {
    public let name: String = "Kingfisher"

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
