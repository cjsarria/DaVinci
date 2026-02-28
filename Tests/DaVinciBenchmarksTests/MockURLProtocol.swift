import Foundation
import UniformTypeIdentifiers

#if canImport(UIKit)
import UIKit
#endif
#if canImport(CoreGraphics)
import CoreGraphics
#endif
#if canImport(ImageIO)
import ImageIO
#endif

// MARK: - MockURLProtocol (URLProtocol for deterministic bench.local requests)

/// Intercepts `https://bench.local/img/{id}.jpg`; returns deterministic PNG (seeded by URL id, no random); configurable latency; thread-safe request counting.
public final class MockURLProtocol: URLProtocol {

    public struct ResponseConfig: Sendable {
        public var latencyMs: Int
        public var statusCode: Int
        public init(latencyMs: Int = 0, statusCode: Int = 200) {
            self.latencyMs = max(0, latencyMs)
            self.statusCode = statusCode
        }
    }

    private static let lock = NSLock()
    private static var _startCountPerURL: [String: Int] = [:]
    private static var _responseConfig: ResponseConfig = ResponseConfig()
    private static var _lastRequestedURL: URL?
    private static var _lastRejectedURL: URL?
    private static var _completedCount: Int = 0
    private static var _cancelledCount: Int = 0

    /// Set by test setUp. Called when a non–bench.local request is seen; must fail the test (e.g. XCTFail).
    public static var onNonBenchLocalRequest: ((URL) -> Void)?

    public static var lastRequestedURL: URL? {
        lock.lock()
        defer { lock.unlock() }
        return _lastRequestedURL
    }

    public static var lastRejectedURL: URL? {
        lock.lock()
        defer { lock.unlock() }
        return _lastRejectedURL
    }

    public static var startedCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return _startCountPerURL.values.reduce(0, +)
    }

    public static var completedCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return _completedCount
    }

    public static var cancelledCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return _cancelledCount
    }

    public static func startCount(for url: URL) -> Int {
        lock.lock()
        defer { lock.unlock() }
        return _startCountPerURL[url.absoluteString] ?? 0
    }

    public static func startCountsSnapshot() -> [String: Int] {
        lock.lock()
        defer { lock.unlock() }
        return _startCountPerURL
    }

    public static func setResponseConfig(_ config: ResponseConfig) {
        lock.lock()
        _responseConfig = config
        lock.unlock()
    }

    /// Resets request counters and response config to default. Call at start of each test to avoid cross-test leakage.
    public static func reset() {
        lock.lock()
        _startCountPerURL = [:]
        _responseConfig = ResponseConfig(latencyMs: 50, statusCode: 200)
        _lastRequestedURL = nil
        _lastRejectedURL = nil
        _completedCount = 0
        _cancelledCount = 0
        lock.unlock()
    }

    /// Accept all requests so none go to real network; non–bench.local is failed in startLoading.
    override public class func canInit(with request: URLRequest) -> Bool {
        return request.url != nil
    }

    override public class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override public func startLoading() {
        guard let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        Self.lock.lock()
        Self._lastRequestedURL = url
        Self.lock.unlock()

        guard url.host == "bench.local", url.path.hasPrefix("/img/") else {
            Self.lock.lock()
            Self._lastRejectedURL = url
            Self.lock.unlock()
            Self.onNonBenchLocalRequest?(url)
            let error = URLError(.unsupportedURL, userInfo: [NSLocalizedDescriptionKey: "Non–bench.local URL in test", "URL": url.absoluteString])
            client?.urlProtocol(self, didFailWithError: error)
            return
        }

        let key = url.absoluteString
        Self.lock.lock()
        Self._startCountPerURL[key, default: 0] += 1
        let config = Self._responseConfig
        Self.lock.unlock()

        let payload = Self.payloadForURL(url)
        let delayMs = config.latencyMs
        let statusCode = config.statusCode

        // Run delay off the main thread so we don't compete with test/UI and cause URLSession timeouts (60s).
        let deadline = delayMs > 0 ? DispatchTime.now() + Double(delayMs) / 1000.0 : DispatchTime.now()
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: deadline) { [weak self] in
            guard let self = self else { return }
            self.respondWith(payload: payload, statusCode: statusCode)
        }
    }

    override public func stopLoading() {
        Self.lock.lock()
        Self._cancelledCount += 1
        Self.lock.unlock()
        client?.urlProtocol(self, didFailWithError: URLError(.cancelled))
    }

    private func respondWith(payload: Data, statusCode: Int) {
        Self.lock.lock()
        Self._completedCount += 1
        Self.lock.unlock()
        guard let client = client else { return }
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: statusCode,
            httpVersion: "1.1",
            headerFields: ["Content-Type": "image/png", "Content-Length": "\(payload.count)"]
        )!
        client.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client.urlProtocol(self, didLoad: payload)
        client.urlProtocolDidFinishLoading(self)
    }

    private static func payloadForURL(_ url: URL) -> Data {
        let path = url.path
        let id: Int
        if path.hasPrefix("/img/") {
            let suffix = String(path.dropFirst(5)).replacingOccurrences(of: ".jpg", with: "").replacingOccurrences(of: ".png", with: "")
            id = Int(suffix) ?? 0
        } else {
            id = 0
        }
        return makePNGForBenchmark(width: 10, height: 10, seed: id)
    }

    /// Same payload generator as LocalBenchServer for fair comparison.
    public static func makePNGForBenchmark(width: Int, height: Int, seed: Int) -> Data {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bytesPerRow = width * 4
        var data = Data(count: bytesPerRow * height)
        data.withUnsafeMutableBytes { buf in
            guard let base = buf.baseAddress else { return }
            memset(base, Int32(0x7F + (seed % 32)), buf.count)
        }
        guard let provider = CGDataProvider(data: data as CFData) else {
            return Data([0x89, 0x50, 0x4E, 0x47])
        }
        guard let cg = CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        ) else {
            return Data([0x89, 0x50, 0x4E, 0x47])
        }
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, UTType.png.identifier as CFString, 1, nil) else {
            return Data([0x89, 0x50, 0x4E, 0x47])
        }
        CGImageDestinationAddImage(dest, cg, nil)
        guard CGImageDestinationFinalize(dest) else {
            return Data([0x89, 0x50, 0x4E, 0x47])
        }
        return out as Data
    }
}
