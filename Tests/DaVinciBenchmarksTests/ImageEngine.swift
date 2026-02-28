import Foundation

#if canImport(UIKit)
import UIKit

/// Abstraction over DaVinci, Kingfisher, and PINRemoteImage for deterministic benchmark comparison.
/// All engines receive the same URLSession (or equivalent) so network conditions are identical.
public protocol ImageEngine: Sendable {
    var name: String { get }

    /// Load image into the given image view. Completion called on main when done (success or failure).
    func setImage(on imageView: UIImageView, url: URL, completion: (() -> Void)?)

    /// Prefetch URLs (best-effort).
    func prefetch(_ urls: [URL])

    /// Clear all caches so the next load is cold.
    func clearCaches()
}

/// Factory that builds an engine using a session configuration (with MockURLProtocol) for deterministic tests.
public enum ImageEngineFactory {
    /// Builds a fresh session config for each test: MockURLProtocol only, no URLCache, no request cache. Ensures determinism and no cross-test leakage.
    /// Timeout is generous so mock responses (which run off main thread) never hit URLSession’s default 60s and cause -1001.
    public static func makeBenchmarkSessionConfiguration() -> URLSessionConfiguration {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.urlCache = nil
        config.timeoutIntervalForRequest = 120
        config.timeoutIntervalForResource = 300
        return config
    }

    public static func makeDaVinci(config: URLSessionConfiguration) -> ImageEngine {
        DaVinciEngineAdapter(sessionConfiguration: config)
    }

    public static func makeKingfisher(config: URLSessionConfiguration) -> ImageEngine {
        KingfisherEngineAdapter(sessionConfiguration: config)
    }

    public static func makePINRemoteImage(config: URLSessionConfiguration) -> ImageEngine {
        PINRemoteImageEngineAdapter(sessionConfiguration: config)
    }

    /// PIN uses LocalBenchServer (no URLProtocol); pass server so URLs are rewritten to localhost.
    public static func makePINRemoteImage(server: LocalBenchServer) -> ImageEngine {
        PINRemoteImageEngineAdapter(serverBaseURL: server.baseURL)
    }
}
#endif
