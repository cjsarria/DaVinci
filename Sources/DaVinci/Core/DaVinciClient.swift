import Foundation
import CoreGraphics

#if canImport(UIKit)
import UIKit
#endif

#if canImport(AppKit)
import AppKit
#endif

public final class DaVinciClient {
    public struct Configuration: Sendable {
        public var memoryCacheMaxCostBytes: Int
        public var diskCache: DiskImageCache.Configuration

        public init(
            memoryCacheMaxCostBytes: Int = 50 * 1024 * 1024,
            diskCache: DiskImageCache.Configuration = .init()
        ) {
            self.memoryCacheMaxCostBytes = max(0, memoryCacheMaxCostBytes)
            self.diskCache = diskCache
        }
    }

    internal let httpClient: HTTPClientProtocol
    internal let decoder: ImageDecoder
    internal let coordinator: ImageTaskCoordinator
    public let memoryCache: MemoryImageCache
    public let diskCache: DiskImageCache
    public let configuration: Configuration

    internal init(
        httpClient: HTTPClientProtocol,
        decoder: ImageDecoder,
        coordinator: ImageTaskCoordinator,
        memoryCache: MemoryImageCache,
        diskCache: DiskImageCache,
        configuration: Configuration
    ) {
        self.httpClient = httpClient
        self.decoder = decoder
        self.coordinator = coordinator
        self.memoryCache = memoryCache
        self.diskCache = diskCache
        self.configuration = configuration
    }

    /// Creates a client with optional custom URLSession (e.g. background configuration).
    /// When using a background session, the app must set the session delegate and handle completion in `application(_:handleEventsForBackgroundURLSession:completionHandler:)`.
    public static func makeDefault(
        configuration: Configuration = Configuration(),
        session: URLSession? = nil
    ) -> DaVinciClient {
        let memory = MemoryImageCache(maxCost: configuration.memoryCacheMaxCostBytes)
        let disk = DiskImageCache(configuration: configuration.diskCache)
        let http: HTTPClientProtocol = session.map { HTTPClient(session: $0) } ?? HTTPClient()
        return DaVinciClient(
            httpClient: http,
            decoder: ImageDecoder(),
            coordinator: ImageTaskCoordinator(),
            memoryCache: memory,
            diskCache: disk,
            configuration: configuration
        )
    }

    private static let lock = NSLock()
    private static var _shared: DaVinciClient = DaVinciClient.makeDefault()

    public static var shared: DaVinciClient {
        get { lock.lock(); defer { lock.unlock() }; return _shared }
        set { lock.lock(); _shared = newValue; lock.unlock() }
    }

    /// When `true`, prefetch will not start new network requests (respects Low Data Mode / user preference).
    /// Set from your app using `NWPathMonitor` (e.g. `path.isConstrained`) or a user setting.
    public static var lowDataModeEnabled: Bool = false

    /// App-wide default options used when you call `setImage(with: url)` (the overload without an `options` parameter).
    /// Set at launch to customize default cache policy, priority, transition, etc.
    public static var defaultOptions: DaVinciOptions = .default
}

public extension DaVinciClient {
    /// Removes all entries from memory and disk caches. Use on logout or when the user requests data deletion.
    func clearAllCaches() {
        memoryCache.removeAll()
        diskCache.removeAll()
    }

    /// Clears memory and disk caches for the shared client. Safe to call from any thread.
    static func clearSharedCaches() {
        shared.clearAllCaches()
    }

    func loadImage(
        url: URL,
        targetSize: CGSize? = nil,
        scale: CGFloat = 1,
        cachePolicy: CachePolicy = .memoryAndDisk,
        priority: RequestPriority = .normal
    ) async throws -> (DVImage, ImageLoadMetrics) {
        try await loadImage(
            url: url,
            scale: scale,
            options: DaVinciOptions(
                cachePolicy: cachePolicy,
                priority: priority,
                targetSize: targetSize,
                processors: []
            )
        )
    }

    /// When `onPreview` is non-nil and the image is loaded from network, a small preview is decoded and delivered first, then the full image. Use for progressive-style UX.
    func loadImage(
        url: URL,
        scale: CGFloat = 1,
        options: DaVinciOptions = .default,
        onPreview: (@MainActor (DVImage) -> Void)? = nil
    ) async throws -> (DVImage, ImageLoadMetrics) {
        var didDecode = false
        func markDecodeStarted() {
            didDecode = true
        }

        let traceId = UUID().uuidString
        let start = Date().timeIntervalSinceReferenceDate

        let memoryKey = CacheKey(url: url, targetSize: options.targetSize, scale: scale, processors: options.processors)
        let diskKey = CacheKey(url: url)

        if options.cachePolicy == .memoryAndDisk || options.cachePolicy == .memoryOnly {
            if let cached = memoryCache.get(memoryKey) {
                let end = Date().timeIntervalSinceReferenceDate
                let result: (DVImage, ImageLoadMetrics) = (
                    cached,
                    ImageLoadMetrics(
                        cacheSource: .memory,
                        startTime: start,
                        endTime: end,
                        networkTimeMs: 0,
                        decodeTimeMs: 0,
                        downloadedBytes: nil
                    )
                )

                #if DEBUG
                Self.debugLog(cacheSource: .memory, decodeTimeMs: result.1.decodeTimeMs, url: url)
                #endif

                DaVinciDebug.log(.info, traceId: traceId, url: url, metrics: result.1, logContext: options.logContext, message: "loaded")
                DaVinciDebug.metricsCallback?(url, result.1)
                return result
            }
        }

        var diskEntry: (data: Data, meta: DiskImageCache.Meta?)?
        if options.cachePolicy == .memoryAndDisk || options.cachePolicy == .diskOnly {
            diskEntry = diskCache.getEntry(for: diskKey)
            if let diskEntry, diskEntry.meta?.isExpired != true {
                markDecodeStarted()
                let decodeStart = Date().timeIntervalSinceReferenceDate
                let decoded = try await decoder.decode(diskEntry.data, downsampleTo: options.targetSize, scale: scale)
                let image = try await applyProcessors(options.processors, to: decoded)
                let decodeEnd = Date().timeIntervalSinceReferenceDate

                if options.cachePolicy == .memoryAndDisk || options.cachePolicy == .memoryOnly {
                    memoryCache.set(image, for: memoryKey, costBytes: Self.costBytes(for: image))
                }

                let end = Date().timeIntervalSinceReferenceDate
                let result: (DVImage, ImageLoadMetrics) = (
                    image,
                    ImageLoadMetrics(
                        cacheSource: .disk,
                        startTime: start,
                        endTime: end,
                        networkTimeMs: nil,
                        decodeTimeMs: (decodeEnd - decodeStart) * 1000,
                        downloadedBytes: diskEntry.data.count
                    )
                )

                #if DEBUG
                Self.debugLog(cacheSource: .disk, decodeTimeMs: result.1.decodeTimeMs, url: url)
                #endif

                DaVinciDebug.log(.info, traceId: traceId, url: url, metrics: result.1, logContext: options.logContext, message: "loaded")
                DaVinciDebug.metricsCallback?(url, result.1)
                return result
            }
        }

        var conditionalHeaders: [String: String] = [:]
        if let etag = diskEntry?.meta?.etag {
            conditionalHeaders["If-None-Match"] = etag
        }

        let headersCopy = conditionalHeaders
        let networkStart = Date().timeIntervalSinceReferenceDate
        var response: HTTPResponse?
        var lastError: Error?
        let maxAttempts = max(1, options.retryCount + 1)
        for _ in 0..<maxAttempts {
            do {
                let r = try await coordinator.data(for: diskKey, url: url, priority: options.priority) { url, prio in
                    try await self.httpClient.request(url: url, priority: prio, additionalHeaders: headersCopy)
                }
                response = r
                lastError = nil
                break
            } catch {
                lastError = error
            }
        }
        if let lastError {
            DaVinciDebug.log(.error, traceId: traceId, url: url, metrics: nil, logContext: options.logContext, message: "error=\(lastError)")
            throw lastError
        }
        let networkEnd = Date().timeIntervalSinceReferenceDate
        let responseUnwrapped = response!

        let dataToDecode: Data
        var cacheSource: ImageCacheSource = .network

        if responseUnwrapped.statusCode == 304, let diskEntry {
            dataToDecode = diskEntry.data
            cacheSource = .disk
        } else {
            guard (200...299).contains(responseUnwrapped.statusCode) else {
                throw URLError(.badServerResponse)
            }
            dataToDecode = responseUnwrapped.data
        }

        if (options.cachePolicy == .memoryAndDisk || options.cachePolicy == .diskOnly), responseUnwrapped.statusCode != 304 {
            let meta = DiskImageCache.Meta(
                etag: responseUnwrapped.headers["etag"],
                cachedAt: Date(),
                expiresAt: Self.parseExpiresAt(from: responseUnwrapped.headers, cachedAt: Date()),
                contentType: responseUnwrapped.headers["content-type"]
            )
            diskCache.setData(responseUnwrapped.data, for: diskKey, meta: meta)
        }

        if let onPreview = onPreview, responseUnwrapped.statusCode != 304, dataToDecode.count > 2048 {
            let previewSize = CGSize(width: 240, height: 240)
            if let preview = try? await decoder.decode(dataToDecode, downsampleTo: previewSize, scale: scale) {
                await MainActor.run { onPreview(preview) }
            }
        }

        markDecodeStarted()
        let decodeStart = Date().timeIntervalSinceReferenceDate
        let decoded = try await decoder.decode(dataToDecode, downsampleTo: options.targetSize, scale: scale)
        let image = try await applyProcessors(options.processors, to: decoded)
        let decodeEnd = Date().timeIntervalSinceReferenceDate

        if options.cachePolicy == .memoryAndDisk || options.cachePolicy == .memoryOnly {
            memoryCache.set(image, for: memoryKey, costBytes: Self.costBytes(for: image))
        }

        let end = Date().timeIntervalSinceReferenceDate
        let result: (DVImage, ImageLoadMetrics) = (
            image,
            ImageLoadMetrics(
                cacheSource: cacheSource,
                startTime: start,
                endTime: end,
                networkTimeMs: (networkEnd - networkStart) * 1000,
                decodeTimeMs: (decodeEnd - decodeStart) * 1000,
                downloadedBytes: dataToDecode.count
            )
        )

        #if DEBUG
        Self.debugLog(cacheSource: cacheSource, decodeTimeMs: result.1.decodeTimeMs, url: url)
        #endif

        assert(cacheSource != .memory || didDecode == false, "DaVinci: decode triggered on memory hit (BUG)")

        DaVinciDebug.log(.info, traceId: traceId, url: url, metrics: result.1, logContext: options.logContext, message: "loaded")
        DaVinciDebug.metricsCallback?(url, result.1)
        return result
    }
}

private extension DaVinciClient {
    static let debugLogLock = NSLock()
    static var debugLogRemaining: Int = 10

    static func debugLog(cacheSource: ImageCacheSource, decodeTimeMs: Double?, url: URL) {
        debugLogLock.lock(); defer { debugLogLock.unlock() }
        guard debugLogRemaining > 0 else { return }
        debugLogRemaining -= 1

        let decodeText = decodeTimeMs.map { String(format: "%.1f", $0) } ?? "—"
        print("DaVinci: source=\(cacheSource) decodeTime=\(decodeText)ms url=\(url.absoluteString)")
    }
}

private extension DaVinciClient {
    static func costBytes(for image: DVImage) -> Int {
        #if canImport(UIKit)
        if let ui = image as? UIImage {
            if let cg = ui.cgImage {
                return max(0, cg.bytesPerRow * cg.height)
            }
        }
        return 0
        #elseif canImport(AppKit)
        if let ns = image as? NSImage {
            if let cg = ns.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                return max(0, cg.bytesPerRow * cg.height)
            }
        }
        return 0
        #else
        return 0
        #endif
    }
}

private extension DaVinciClient {
    func applyProcessors(_ processors: [any ImageProcessor], to image: DVImage) async throws -> DVImage {
        guard processors.isEmpty == false else { return image }

        var current = image
        for p in processors {
            current = p.process(current)
        }
        return current
    }
}

private extension DaVinciClient {
    static func parseExpiresAt(from headers: [String: String], cachedAt: Date) -> Date? {
        guard let cacheControl = headers["cache-control"]?.lowercased() else { return nil }
        // Best effort parse of "max-age=NN"
        let parts = cacheControl.split(separator: ",")
        for part in parts {
            let trimmed = part.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("max-age=") {
                let v = trimmed.replacingOccurrences(of: "max-age=", with: "")
                if let seconds = TimeInterval(v) {
                    return cachedAt.addingTimeInterval(seconds)
                }
            }
        }
        return nil
    }
}
