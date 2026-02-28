import XCTest
@testable import DaVinci
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

final class DaVinciTests: XCTestCase {
    func testWrapperTypeExists() {
        struct Thing: DaVinciCompatible {}
        let wrapper = Thing().dv
        XCTAssertTrue(type(of: wrapper) == DaVinciWrapper<Thing>.self)
    }

    func testProcessorIdentifierStability() {
        XCTAssertEqual(ResizeProcessor(size: CGSize(width: 20, height: 10)).identifier, "resize(20x10)")
        XCTAssertEqual(CropProcessor(size: CGSize(width: 30, height: 40)).identifier, "crop(center,30x40)")
        XCTAssertEqual(RoundCornersProcessor(radius: 12).identifier, "roundCorners(r=12.00)")
        XCTAssertEqual(BlurProcessor(radius: 3).identifier, "blur(r=3.00)")
    }

    func testCacheKeyIncludesProcessorsSignature() {
        let url = URL(string: "https://example.com/a.png")!
        let processors: [any ImageProcessor] = [
            ResizeProcessor(size: CGSize(width: 10, height: 10)),
            RoundCornersProcessor(radius: 4)
        ]
        let key = CacheKey(url: url, targetSize: CGSize(width: 40, height: 20), scale: 2, processors: processors)
        XCTAssertTrue(key.rawValue.contains("|proc:resize(10x10)+roundCorners(r=4.00)"))
    }

    func testDiskMetaReadWriteRoundTrip() {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let cache = DiskImageCache(directoryURL: dir)
        let key = CacheKey("k")
        let data = Data([0xAA, 0xBB])
        let meta = DiskImageCache.Meta(etag: "etag-1", cachedAt: Date(timeIntervalSince1970: 1), expiresAt: Date(timeIntervalSince1970: 2), contentType: "image/png")
        cache.setData(data, for: key, meta: meta)
        let entry = cache.getEntry(for: key)
        XCTAssertEqual(entry?.data, data)
        XCTAssertEqual(entry?.meta?.etag, meta.etag)
        XCTAssertEqual(entry?.meta?.contentType, meta.contentType)
    }

    func testHTTP304FlowUsesCachedBytes() async throws {
        let url = URL(string: "https://example.com/image.png")!
        let png = try makePNG(width: 12, height: 12)

        let http = SequenceHTTPClient(sequence: [
            .success(HTTPResponse(statusCode: 200, headers: ["etag": "t1", "cache-control": "max-age=0"], data: png)),
            .success(HTTPResponse(statusCode: 304, headers: ["etag": "t1"], data: Data()))
        ])

        let diskDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let client = DaVinciClient(
            httpClient: http,
            decoder: ImageDecoder(),
            coordinator: ImageTaskCoordinator(),
            memoryCache: MemoryImageCache(maxCost: 10_000),
            diskCache: DiskImageCache(directoryURL: diskDir),
            configuration: .init()
        )

        let opts = DaVinciOptions(cachePolicy: .diskOnly, priority: .normal, targetSize: nil, processors: [], retryCount: 0, transition: .none, logContext: nil)

        let first = try await client.loadImage(url: url, scale: 1, options: opts)
        XCTAssertEqual(first.1.cacheSource, .network)

        let second = try await client.loadImage(url: url, scale: 1, options: opts)
        XCTAssertEqual(second.1.cacheSource, .disk)

        let seen = await http.seenIfNoneMatch
        XCTAssertEqual(seen, "t1")
    }

    func testDecoderDecodesValidPNG() async throws {
        let data = Data([
            0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
            0x00, 0x00, 0x00, 0x0D,
            0x49, 0x48, 0x44, 0x52,
            0x00, 0x00, 0x00, 0x01,
            0x00, 0x00, 0x00, 0x01,
            0x08, 0x06, 0x00, 0x00, 0x00,
            0x1F, 0x15, 0xC4, 0x89,
            0x00, 0x00, 0x00, 0x0A,
            0x49, 0x44, 0x41, 0x54,
            0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00, 0x05, 0x00, 0x01,
            0x0D, 0x0A, 0x2D, 0xB4,
            0x00, 0x00, 0x00, 0x00,
            0x49, 0x45, 0x4E, 0x44,
            0xAE, 0x42, 0x60, 0x82
        ])

        let decoder = ImageDecoder()
        _ = try await decoder.decode(data)
    }

    func testDiskImageCacheRoundTrip() throws {
        let fm = FileManager.default
        let base = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let cache = DiskImageCache(directoryURL: base)

        let key = CacheKey("https://example.com/image.png")
        let payload = Data([0x01, 0x02, 0x03, 0x04, 0x05])

        cache.setData(payload, for: key)
        let loaded = cache.getData(for: key)
        XCTAssertEqual(loaded, payload)

        cache.removeAll()
        XCTAssertNil(cache.getData(for: key))
    }

    func testMemoryImageCacheEvictsLRU() async throws {
        let decoder = ImageDecoder()
        let data = Data([
            0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
            0x00, 0x00, 0x00, 0x0D,
            0x49, 0x48, 0x44, 0x52,
            0x00, 0x00, 0x00, 0x01,
            0x00, 0x00, 0x00, 0x01,
            0x08, 0x06, 0x00, 0x00, 0x00,
            0x1F, 0x15, 0xC4, 0x89,
            0x00, 0x00, 0x00, 0x0A,
            0x49, 0x44, 0x41, 0x54,
            0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00, 0x05, 0x00, 0x01,
            0x0D, 0x0A, 0x2D, 0xB4,
            0x00, 0x00, 0x00, 0x00,
            0x49, 0x45, 0x4E, 0x44,
            0xAE, 0x42, 0x60, 0x82
        ])

        let img = try await decoder.decode(data)

        let cache = MemoryImageCache(maxCost: 100)
        let k1 = CacheKey("k1")
        let k2 = CacheKey("k2")

        cache.set(img, for: k1, costBytes: 60)
        cache.set(img, for: k2, costBytes: 60)

        XCTAssertNil(cache.get(k1))
        XCTAssertNotNil(cache.get(k2))
    }

    func testCacheKeyIncludesTargetSize() {
        let url = URL(string: "https://example.com/a.png")!
        let k1 = CacheKey(url: url, targetSize: CGSize(width: 40, height: 20), scale: 2)
        let k2 = CacheKey(url: url, targetSize: CGSize(width: 41, height: 20), scale: 2)
        XCTAssertNotEqual(k1, k2)
        XCTAssertTrue(k1.rawValue.contains("@40x20@2.00"))
    }

    func testDownsamplingRespectsBounds() async throws {
        let png = try makePNG(width: 200, height: 100)
        let decoder = ImageDecoder()
        let target = CGSize(width: 40, height: 40)
        let img = try await decoder.decode(png, downsampleTo: target, scale: 1)

        #if canImport(UIKit)
        XCTAssertLessThanOrEqual(img.size.width, 40.5)
        XCTAssertLessThanOrEqual(img.size.height, 40.5)
        #elseif canImport(AppKit)
        XCTAssertLessThanOrEqual(img.size.width, 40.5)
        XCTAssertLessThanOrEqual(img.size.height, 40.5)
        #endif
    }

    func testCoordinatorCoalescesNetworkFetches() async throws {
        let url = URL(string: "https://example.com/image.png")!
        let payload = try makePNG(width: 10, height: 10)

        let http = MockHTTPClient(result: .success(payload))
        let client = DaVinciClient(
            httpClient: http,
            decoder: ImageDecoder(),
            coordinator: ImageTaskCoordinator(),
            memoryCache: MemoryImageCache(maxCost: 10_000),
            diskCache: DiskImageCache(directoryURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)),
            configuration: .init()
        )

        async let a = client.loadImage(url: url, cachePolicy: .noCache)
        async let b = client.loadImage(url: url, cachePolicy: .noCache)
        _ = try await (a, b)

        let calls = await http.callCount
        XCTAssertEqual(calls, 1)
    }

    func testHTTPClientCancelsUnderlyingRequestsOnTaskCancellation() async {
        class CancellationURLProtocol: URLProtocol {
            private static let lock = NSLock()
            private static var _startedCount: Int = 0
            private static var _cancelledCount: Int = 0
            static var startedSignal: (() -> Void)?

            static var startedCount: Int {
                lock.lock(); defer { lock.unlock() }
                return _startedCount
            }

            static var cancelledCount: Int {
                lock.lock(); defer { lock.unlock() }
                return _cancelledCount
            }

            static func reset() {
                lock.lock()
                _startedCount = 0
                _cancelledCount = 0
            startedSignal = nil
                lock.unlock()
            }

            override class func canInit(with request: URLRequest) -> Bool {
                true
            }

            override class func canonicalRequest(for request: URLRequest) -> URLRequest {
                request
            }

            override func startLoading() {
            Self.lock.lock()
            Self._startedCount += 1
            let signal = Self.startedSignal
            Self.startedSignal = nil
            Self.lock.unlock()
            signal?()
                // No response; cancellation is driven via stopLoading.
            }

            override func stopLoading() {
                Self.lock.lock()
                Self._cancelledCount += 1
                Self.lock.unlock()
                client?.urlProtocol(self, didFailWithError: URLError(.cancelled))
            }
        }

        CancellationURLProtocol.reset()

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [CancellationURLProtocol.self]
        let session = URLSession(configuration: config)
        let client = HTTPClient(session: session)

        let url = URL(string: "https://example.com/cancel.png")!

        var seenError: Error?

        let started = expectation(description: "started")
        CancellationURLProtocol.startedSignal = { started.fulfill() }

        let task = Task {
            do {
                _ = try await client.request(url: url, priority: .normal, additionalHeaders: [:])
                XCTFail("Expected request to be cancelled")
            } catch {
                seenError = error
            }
        }

        await fulfillment(of: [started], timeout: 1.0)
        task.cancel()
        await task.value

        XCTAssertEqual(CancellationURLProtocol.startedCount, 1)
        XCTAssertEqual(CancellationURLProtocol.cancelledCount, 1)
        XCTAssertNotNil(seenError)

        if let urlError = seenError as? URLError {
            XCTAssertEqual(urlError.code, .cancelled)
        } else {
            XCTAssertTrue(seenError is CancellationError)
        }
    }

    // MARK: - Stage 2: Idempotent setImage, currentImageURL, completion contract

    #if canImport(UIKit)
    @MainActor
    func testCurrentImageURLIsNilByDefault() {
        let imageView = UIImageView()
        XCTAssertNil(imageView.dv.currentImageURL)
    }

    @MainActor
    func testSetImageWithNilURLFailsWithInvalidURL() {
        let imageView = UIImageView()
        let expectation = expectation(description: "completion")
        imageView.dv.setImage(with: nil) { result, _ in
            if case .failure(let error) = result, (error as? DaVinciError) == .invalidURL {
                expectation.fulfill()
            }
        }
        wait(for: [expectation], timeout: 1.0)
    }

    @MainActor
    func testSetImageCompletionCalledOnMainThread() async throws {
        let png = try makePNG(width: 2, height: 2)
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let fileURL = tempDir.appendingPathComponent("test.png")
        try png.write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let imageView = UIImageView()
        let completionCalled = expectation(description: "completion")
        var completionOnMain = false
        imageView.dv.setImage(with: fileURL) { _, _ in
            completionOnMain = Thread.isMainThread
            completionCalled.fulfill()
        }
        await fulfillment(of: [completionCalled], timeout: 5.0)
        XCTAssertTrue(completionOnMain, "Completion must be called on main thread")
        XCTAssertEqual(imageView.dv.currentImageURL, fileURL)
    }

    @MainActor
    func testSetImageSameURLTwiceSecondCallIsNoOp() async throws {
        let png = try makePNG(width: 2, height: 2)
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let fileURL = tempDir.appendingPathComponent("idempotent.png")
        try png.write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let imageView = UIImageView()
        let firstCompletion = expectation(description: "first")
        imageView.dv.setImage(with: fileURL) { _, _ in firstCompletion.fulfill() }
        await fulfillment(of: [firstCompletion], timeout: 5.0)

        var secondCompletionCalled = false
        imageView.dv.setImage(with: fileURL) { _, _ in secondCompletionCalled = true }
        // Idempotent: second setImage with same URL does not start a new load, so completion is not called.
        try await Task.sleep(nanoseconds: 300_000_000) // 0.3s
        XCTAssertFalse(secondCompletionCalled, "Idempotent setImage(same URL) must not call completion")
    }
    #endif

    // MARK: - Stage 3: Prefetch and cache hit

    func testPrefetchThenLoadImageHitsCache() async throws {
        let url = URL(string: "https://example.com/prefetch.png")!
        let png = try makePNG(width: 8, height: 8)
        let http = MockHTTPClient(result: .success(png))
        let diskDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let client = DaVinciClient(
            httpClient: http,
            decoder: ImageDecoder(),
            coordinator: ImageTaskCoordinator(),
            memoryCache: MemoryImageCache(maxCost: 10_000),
            diskCache: DiskImageCache(directoryURL: diskDir),
            configuration: .init()
        )
        let prefetcher = ImagePrefetcher(client: client)
        prefetcher.prefetch([url], cachePolicy: .memoryAndDisk, priority: .low)
        try await Task.sleep(nanoseconds: 500_000_000) // 0.5s for prefetch to complete
        let (_, metrics) = try await client.loadImage(url: url, cachePolicy: .memoryAndDisk)
        XCTAssertTrue(metrics.cacheSource == .memory || metrics.cacheSource == .disk, "Expected cache hit after prefetch, got \(metrics.cacheSource)")
    }

    // MARK: - Stage 4: Metrics callback

    func testClearAllCachesRemovesMemoryAndDisk() async throws {
        let url = URL(string: "https://example.com/clear.png")!
        let png = try makePNG(width: 4, height: 4)
        let http = MockHTTPClient(result: .success(png))
        let diskDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let client = DaVinciClient(
            httpClient: http,
            decoder: ImageDecoder(),
            coordinator: ImageTaskCoordinator(),
            memoryCache: MemoryImageCache(maxCost: 10_000),
            diskCache: DiskImageCache(directoryURL: diskDir),
            configuration: .init()
        )
        _ = try await client.loadImage(url: url, cachePolicy: .memoryAndDisk)
        let key = CacheKey(url: url)
        XCTAssertNotNil(client.memoryCache.get(key))
        XCTAssertNotNil(client.diskCache.getData(for: key))
        client.clearAllCaches()
        XCTAssertNil(client.memoryCache.get(key))
        XCTAssertNil(client.diskCache.getData(for: key))
    }

    func testPrefetchSkipsWhenLowDataModeEnabled() async throws {
        let url = URL(string: "https://example.com/lowdata.png")!
        let png = try makePNG(width: 2, height: 2)
        let http = MockHTTPClient(result: .success(png))
        let diskDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let client = DaVinciClient(
            httpClient: http,
            decoder: ImageDecoder(),
            coordinator: ImageTaskCoordinator(),
            memoryCache: MemoryImageCache(maxCost: 10_000),
            diskCache: DiskImageCache(directoryURL: diskDir),
            configuration: .init()
        )
        DaVinciClient.lowDataModeEnabled = true
        defer { DaVinciClient.lowDataModeEnabled = false }
        let prefetcher = ImagePrefetcher(client: client)
        prefetcher.prefetch([url], cachePolicy: .memoryAndDisk)
        try await Task.sleep(nanoseconds: 200_000_000)
        let calls = await http.callCount
        XCTAssertEqual(calls, 0, "Prefetch should not perform network when lowDataModeEnabled")
    }

    func testMetricsCallbackInvokedOnLoad() async throws {
        let url = URL(string: "https://example.com/metrics.png")!
        let png = try makePNG(width: 4, height: 4)
        let http = MockHTTPClient(result: .success(png))
        let diskDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let client = DaVinciClient(
            httpClient: http,
            decoder: ImageDecoder(),
            coordinator: ImageTaskCoordinator(),
            memoryCache: MemoryImageCache(maxCost: 10_000),
            diskCache: DiskImageCache(directoryURL: diskDir),
            configuration: .init()
        )
        let callbackFired = expectation(description: "metrics callback")
        DaVinciDebug.metricsCallback = { callbackUrl, metrics in
            if callbackUrl == url {
                XCTAssertEqual(metrics.cacheSource, .network)
                callbackFired.fulfill()
            }
        }
        defer { DaVinciDebug.metricsCallback = nil }
        _ = try await client.loadImage(url: url, cachePolicy: .noCache)
        await fulfillment(of: [callbackFired], timeout: 2.0)
    }

    func testDiskImageCacheTrimReducesTotalSize() throws {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let cache = DiskImageCache(
            directoryURL: dir,
            configuration: .init(maxSizeBytes: 1_024, maxAge: 60 * 60 * 24 * 30)
        )

        let payload = Data(repeating: 0xAB, count: 600)
        let keys = [
            CacheKey("trim-a"),
            CacheKey("trim-b"),
            CacheKey("trim-c")
        ]

        for key in keys {
            cache.setData(payload, for: key)
        }

        cache._forceTrimForTests(maxSizeBytes: 1_024, maxAge: 60 * 60 * 24 * 30)

        let urls = try fm.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        )

        var totalSize = 0
        for url in urls {
            let values = try url.resourceValues(forKeys: [.fileSizeKey])
            totalSize += values.fileSize ?? 0
        }

        XCTAssertLessThanOrEqual(totalSize, 1_024)
    }

    private func makePNG(width: Int, height: Int) throws -> Data {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bytesPerRow = width * 4
        var data = Data(count: bytesPerRow * height)
        data.withUnsafeMutableBytes { buf in
            memset(buf.baseAddress, 0x7F, buf.count)
        }

        guard let provider = CGDataProvider(data: data as CFData) else {
            throw URLError(.cannotDecodeContentData)
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
            throw URLError(.cannotDecodeContentData)
        }

        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, UTType.png.identifier as CFString, 1, nil) else {
            throw URLError(.cannotCreateFile)
        }
        CGImageDestinationAddImage(dest, cg, nil)
        guard CGImageDestinationFinalize(dest) else {
            throw URLError(.cannotCreateFile)
        }
        return out as Data
    }
}

private actor MockHTTPClient: HTTPClientProtocol {
    private(set) var callCount: Int = 0
    private let result: Result<HTTPResponse, Error>
    private let delayNs: UInt64

    init(result: Result<Data, Error>, delayNs: UInt64 = 200_000_000) {
        self.result = result.map { data in
            HTTPResponse(statusCode: 200, headers: [:], data: data)
        }
        self.delayNs = delayNs
    }

    init(response: Result<HTTPResponse, Error>, delayNs: UInt64 = 200_000_000) {
        self.result = response
        self.delayNs = delayNs
    }

    func request(url: URL, priority: RequestPriority, additionalHeaders: [String : String]) async throws -> HTTPResponse {
        callCount += 1
        try await Task.sleep(nanoseconds: delayNs)
        return try result.get()
    }
}

private actor SequenceHTTPClient: HTTPClientProtocol {
    private var sequence: [Result<HTTPResponse, Error>]
    private(set) var seenIfNoneMatch: String?

    init(sequence: [Result<HTTPResponse, Error>]) {
        self.sequence = sequence
    }

    func request(url: URL, priority: RequestPriority, additionalHeaders: [String : String]) async throws -> HTTPResponse {
        if let v = additionalHeaders["If-None-Match"] {
            seenIfNoneMatch = v
        }
        guard sequence.isEmpty == false else {
            throw URLError(.unknown)
        }
        let next = sequence.removeFirst()
        return try next.get()
    }
}
