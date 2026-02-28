import Foundation
import Kingfisher

#if canImport(UIKit)
import UIKit

/// Kingfisher engine adapter using a custom URLSessionConfiguration (e.g. MockURLProtocol) for benchmarks.
public final class KingfisherEngineAdapter: @unchecked Sendable, ImageEngine {
    public let name: String = "Kingfisher"
    private let downloader: ImageDownloader

    public init(sessionConfiguration: URLSessionConfiguration) {
        let downloader = ImageDownloader(name: "benchmark.\(UUID().uuidString)")
        downloader.sessionConfiguration = sessionConfiguration
        self.downloader = downloader
    }

    public func setImage(on imageView: UIImageView, url: URL, completion: (() -> Void)?) {
        Task { @MainActor in
            imageView.kf.setImage(with: url, options: [.downloader(downloader)]) { _ in
                completion?()
            }
        }
    }

    public func prefetch(_ urls: [URL]) {
        ImagePrefetcher(urls: urls, options: [.downloader(downloader)]).start()
    }

    public func clearCaches() {
        KingfisherManager.shared.cache.clearMemoryCache()
        KingfisherManager.shared.cache.clearDiskCache {}
    }
}
#endif
