import DaVinci
import Foundation

#if canImport(UIKit)
import UIKit

/// DaVinci engine adapter using an injected URLSession (e.g. MockURLProtocol) for deterministic benchmarks.
public final class DaVinciEngineAdapter: @unchecked Sendable, ImageEngine {
    public let name: String = "DaVinci"
    private let sessionConfig: URLSessionConfiguration
    private let client: DaVinciClient

    public init(sessionConfiguration: URLSessionConfiguration) {
        self.sessionConfig = sessionConfiguration
        let session = URLSession(configuration: sessionConfiguration)
        self.client = DaVinciClient.makeDefault(session: session)
    }

    public func setImage(on imageView: UIImageView, url: URL, completion: (() -> Void)?) {
        Task { @MainActor in
            let opts = DaVinciOptions(
                cachePolicy: .memoryAndDisk,
                priority: .normal,
                targetSize: nil,
                processors: [],
                retryCount: 0,
                transition: .none
            )
            imageView.dv.setImage(with: url, options: opts) { _, _ in
                completion?()
            }
        }
    }

    public func prefetch(_ urls: [URL]) {
        let prefetcher = ImagePrefetcher(client: client)
        prefetcher.prefetch(urls, cachePolicy: .memoryAndDisk, priority: .low)
    }

    public func clearCaches() {
        client.clearAllCaches()
    }
}
#endif
