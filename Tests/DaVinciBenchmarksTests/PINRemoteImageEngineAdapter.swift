import Foundation
import PINRemoteImage

#if canImport(UIKit)
import UIKit

/// PIN adapter using LocalBenchServer URLs (PIN cannot use custom URLProtocol). All requests go to http://127.0.0.1:port/img/{id}.jpg.
public final class PINRemoteImageEngineAdapter: @unchecked Sendable, ImageEngine {
    public let name: String = "PINRemoteImage"
    private let serverBaseURL: URL?

    /// - Parameter serverBaseURL: Base URL of LocalBenchServer (e.g. http://127.0.0.1:12345). If nil, uses bench.local (only works if PIN used URLProtocol).
    public init(serverBaseURL: URL?) {
        self.serverBaseURL = serverBaseURL
    }

    /// For factory that only has session config: PIN ignores it; use init(serverBaseURL:) from tests.
    public convenience init(sessionConfiguration: URLSessionConfiguration) {
        self.init(serverBaseURL: nil)
    }

    private func resolveURL(_ url: URL) -> URL {
        guard let base = serverBaseURL, url.host == "bench.local" else { return url }
        return base.appendingPathComponent(url.path)
    }

    public func setImage(on imageView: UIImageView, url: URL, completion: (() -> Void)?) {
        let resolved = resolveURL(url)
        Task { @MainActor in
            imageView.pin_setImage(from: resolved) { _ in
                completion?()
            }
        }
    }

    public func prefetch(_ urls: [URL]) {
        let resolved = urls.map(resolveURL)
        let manager = PINRemoteImageManager.shared()
        for url in resolved {
            manager.downloadImage(with: url) { _ in }
        }
    }

    public func clearCaches() {
        PINRemoteImageManager.shared().cache.removeAllObjects()
    }
}
#endif
