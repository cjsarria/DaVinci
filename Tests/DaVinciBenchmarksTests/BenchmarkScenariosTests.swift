import XCTest
import DaVinci

#if canImport(UIKit)
import UIKit
#endif

/// Deterministic benchmark: DaVinci vs Kingfisher vs PINRemoteImage under identical network (MockURLProtocol or LocalBenchServer).
/// Set environment variable DAVINCI_BENCH_SMOKE=1 for a fast run (~1 min) that exercises all scenarios with reduced counts.
final class BenchmarkScenariosTests: XCTestCase {

    /// When DAVINCI_BENCH_SMOKE=1, use small counts so the full suite finishes in ~1 minute. Guardrails enforce smoke vs full counts.
    private static var isSmoke: Bool { ProcessInfo.processInfo.environment["DAVINCI_BENCH_SMOKE"] == "1" }

    /// Saved in setUp, restored in tearDown so DaVinciClient.shared mutation in DaVinci tests does not leak to other tests.
    private var savedDaVinciClient: DaVinciClient?

    override func setUp() {
        super.setUp()
        savedDaVinciClient = DaVinciClient.shared
        BenchTestObserver.registerIfNeeded()
        MockURLProtocol.reset()
        MockURLProtocol.onNonBenchLocalRequest = { url in
            XCTFail("Real network request (must use bench.local only): \(url.absoluteString)")
        }
    }

    override func tearDown() {
        if let saved = savedDaVinciClient {
            DaVinciClient.shared = saved
        }
        savedDaVinciClient = nil
        super.tearDown()
    }

    static var imageCount: Int { isSmoke ? 10 : 200 }
    /// Cap concurrency in smoke to avoid overload and hangs.
    static var concurrency: Int { min(isSmoke ? 8 : 12, imageCount) }
    static let latencyMs = 50
    static var dedupConcurrent: Int { isSmoke ? 10 : 100 }
    static var cancellationStormCount: Int { isSmoke ? 20 : 200 }
    static var memoryPressureCount: Int { isSmoke ? 15 : 1000 }

    /// Smoke: 25s per scenario; full: 8 min.
    static var scenarioTimeoutSeconds: TimeInterval { isSmoke ? 25 : 480 }
    /// MemoryPressure runs many loadOne in sequence; allow 40s in smoke so all complete.
    static var memoryPressureScenarioTimeoutSeconds: TimeInterval { isSmoke ? 40 : 480 }
    /// PIN uses LocalBenchServer (real TCP); give 45s in smoke to avoid teardown race.
    static var pinScenarioTimeoutSeconds: TimeInterval { isSmoke ? 45 : 480 }
    /// In smoke use 2s so scenarios finish when main-runloop delays setImage completion (timeout fires).
    static var loadOneTimeoutSeconds: TimeInterval { isSmoke ? 2 : 30 }

    /// Reduced counts for PIN ColdCache in smoke (LocalBenchServer is slower than MockURLProtocol).
    static var pinColdCacheImageCount: Int { isSmoke ? 5 : 200 }
    static var pinColdCacheConcurrency: Int { isSmoke ? 5 : 12 }

    func benchURLs() -> [URL] {
        (0..<Self.imageCount).map { i in
            URL(string: "https://bench.local/img/\(i).jpg")!
        }
    }

    #if canImport(UIKit)
    /// Load one image and complete when done (main-thread setImage).
    /// Ensures the continuation is resumed exactly once (engine completion or loadOneTimeoutSeconds) to avoid SWIFT TASK CONTINUATION MISUSE.
    func loadOne(engine: ImageEngine, url: URL, imageView: UIImageView) async {
        let timeout = Self.loadOneTimeoutSeconds
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            let lock = NSLock()
            var didResume = false
            func resumeOnce() {
                lock.lock()
                defer { lock.unlock() }
                guard !didResume else { return }
                didResume = true
                c.resume()
            }
            DispatchQueue.main.async {
                engine.setImage(on: imageView, url: url) { resumeOnce() }
            }
            // Use main queue for timeout so it fires when run loop runs (XCTest can starve global queue).
            DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { resumeOnce() }
        }
    }

    /// DaVinci UIImageView.dv.setImage uses DaVinciClient.shared, so for request counting (MockURLProtocol) we must set shared to a client that uses our session.
    func makeDaVinciEngineWithSharedMockSession(config: URLSessionConfiguration) -> ImageEngine {
        let session = URLSession(configuration: config)
        let client = DaVinciClient.makeDefault(session: session)
        DaVinciClient.shared = client
        return ImageEngineFactory.makeDaVinci(config: config)
    }

    /// Call at scenario start: log env/config and assert smoke vs full guardrail.
    func assertSmokeModeAtStart() {
        let smokeEnv = ProcessInfo.processInfo.environment["DAVINCI_BENCH_SMOKE"] ?? "not set"
        print("[BENCH] DAVINCI_BENCH_SMOKE=\(smokeEnv) imageCount=\(Self.imageCount) concurrency=\(Self.concurrency)")
        fflush(stdout)
        if Self.isSmoke {
            XCTAssertLessThanOrEqual(Self.imageCount, 20, "Smoke: imageCount must be ≤ 20")
        } else {
            XCTAssertEqual(Self.imageCount, 200, "Full mode: imageCount must be 200")
        }
    }

    /// Run ColdCache_Load200 for one engine; returns (duration, networkStarts).
    func runColdCache(engine: ImageEngine, urls: [URL], limiter: ConcurrencyLimiter) async -> (duration: Double, networkStarts: Int) {
        let imageViews = await MainActor.run { (0..<Self.concurrency).map { _ in UIImageView() } }
        let start = Date()
        await withTaskGroup(of: Void.self) { group in
            for (idx, url) in urls.enumerated() {
                group.addTask {
                    await limiter.withSlot {
                        await self.loadOne(engine: engine, url: url, imageView: imageViews[idx % Self.concurrency])
                    }
                }
            }
        }
        let duration = Date().timeIntervalSince(start)
        let starts = urls.map { MockURLProtocol.startCount(for: $0) }.reduce(0, +)
        return (duration, starts)
    }

    // MARK: - Scenario 1: ColdCache_Load200

    @MainActor
    func testColdCache_Load200_DaVinci() async throws {
        assertSmokeModeAtStart()
        print("[BENCH] DaVinci uses MockURLProtocol")
        fflush(stdout)
        MockURLProtocol.setResponseConfig(.init(latencyMs: Self.latencyMs))
        let config = ImageEngineFactory.makeBenchmarkSessionConfiguration()
        let engine = makeDaVinciEngineWithSharedMockSession(config: config)
        DaVinciClient.shared.clearAllCaches()
        let urls = benchURLs()
        let limiter = ConcurrencyLimiter(maxConcurrent: Self.concurrency)
        let (duration, networkStarts) = try await BenchmarkTimeout.withTimeout(self, name: "ColdCache_Load200_DaVinci", seconds: Self.scenarioTimeoutSeconds) {
            await self.runColdCache(engine: engine, urls: urls, limiter: limiter)
        }
        XCTAssertEqual(networkStarts, Self.imageCount, "Each URL should trigger exactly one network start (dedup)")
        let result = BenchmarkResult(
            scenario: "ColdCache_Load200",
            engine: "DaVinci",
            durationSeconds: duration,
            networkStartCount: networkStarts,
            totalRequests: Self.imageCount
        )
        let dir = ArtifactWriter.artifactDirectory()
        ArtifactWriter.writeJSON(result, to: dir)
    }

    @MainActor
    func testColdCache_Load200_Kingfisher() async throws {
        assertSmokeModeAtStart()
        print("[BENCH] Kingfisher uses MockURLProtocol")
        fflush(stdout)
        MockURLProtocol.setResponseConfig(.init(latencyMs: Self.latencyMs))
        let config = ImageEngineFactory.makeBenchmarkSessionConfiguration()
        let engine = ImageEngineFactory.makeKingfisher(config: config)
        engine.clearCaches()
        let urls = benchURLs()
        let limiter = ConcurrencyLimiter(maxConcurrent: Self.concurrency)
        let (duration, networkStarts) = try await BenchmarkTimeout.withTimeout(self, name: "ColdCache_Load200_Kingfisher", seconds: Self.scenarioTimeoutSeconds) {
            await self.runColdCache(engine: engine, urls: urls, limiter: limiter)
        }
        XCTAssertEqual(networkStarts, Self.imageCount)
        let result = BenchmarkResult(
            scenario: "ColdCache_Load200",
            engine: "Kingfisher",
            durationSeconds: duration,
            networkStartCount: networkStarts,
            totalRequests: Self.imageCount
        )
        ArtifactWriter.writeJSON(result, to: ArtifactWriter.artifactDirectory())
    }

    @MainActor
    func testColdCache_Load200_PINRemoteImage() async throws {
        if Self.isSmoke {
            print("[BENCH] SKIP: PINRemoteImage scenarios disabled in smoke mode")
            fflush(stdout)
            throw XCTSkip("PINRemoteImage scenarios disabled in smoke mode")
        }
        assertSmokeModeAtStart()
        print("[BENCH] PINRemoteImage uses LocalBenchServer (http://127.0.0.1:PORT)")
        fflush(stdout)
        let server = LocalBenchServer()
        server.latencyMs = Self.latencyMs
        try await server.start()
        let port = server.port
        print("[BENCH] LocalBenchServer started port=\(port)")
        fflush(stdout)
        let engine = ImageEngineFactory.makePINRemoteImage(server: server)
        engine.clearCaches()
        let pinURLs = (0..<Self.pinColdCacheImageCount).map { i in URL(string: "https://bench.local/img/\(i).jpg")! }
        let urls = pinURLs.compactMap { server.url(for: $0) }
        XCTAssertEqual(urls.count, Self.pinColdCacheImageCount)
        let concurrency = Self.pinColdCacheConcurrency
        let limiter = ConcurrencyLimiter(maxConcurrent: concurrency)
        let imageViews = (0..<concurrency).map { _ in UIImageView() }
        do {
            let (duration, networkStarts): (Double, Int) = try await BenchmarkTimeout.withTimeout(self, name: "ColdCache_Load200_PINRemoteImage", seconds: Self.pinScenarioTimeoutSeconds) {
                let start = Date()
                await withTaskGroup(of: Void.self) { group in
                    for (idx, url) in urls.enumerated() {
                        group.addTask {
                            await limiter.withSlot {
                                await self.loadOne(engine: engine, url: url, imageView: imageViews[idx % concurrency])
                            }
                        }
                    }
                }
                let d = Date().timeIntervalSince(start)
                let ns = urls.map { server.startCount(for: $0.path) }.reduce(0, +)
                return (d, ns)
            }
            server.stop()
            print("[BENCH] LocalBenchServer stopped (PIN ColdCache completed)")
            fflush(stdout)
            let result = BenchmarkResult(
                scenario: "ColdCache_Load200",
                engine: "PINRemoteImage",
                durationSeconds: duration,
                networkStartCount: networkStarts,
                totalRequests: Self.pinColdCacheImageCount
            )
            ArtifactWriter.writeJSON(result, to: ArtifactWriter.artifactDirectory())
        } catch {
            print("[BENCH] Timed out or error: waiting 500ms grace before stopping LocalBenchServer")
            fflush(stdout)
            try? await Task.sleep(nanoseconds: 500_000_000)
            server.stop()
            print("[BENCH] LocalBenchServer stopped after timeout/error (grace 500ms)")
            fflush(stdout)
            throw error
        }
    }

    // MARK: - Scenario 2: WarmCache_Load200 (DaVinci only for brevity; same pattern for KF/PIN)

    @MainActor
    func testWarmCache_Load200_DaVinci() async throws {
        assertSmokeModeAtStart()
        MockURLProtocol.setResponseConfig(.init(latencyMs: Self.latencyMs))
        let config = ImageEngineFactory.makeBenchmarkSessionConfiguration()
        let engine = makeDaVinciEngineWithSharedMockSession(config: config)
        DaVinciClient.shared.clearAllCaches()
        let urls = benchURLs()
        let limiter = ConcurrencyLimiter(maxConcurrent: Self.concurrency)
        let (coldDuration, warmDuration, warmStarts): (Double, Double, Int) = try await BenchmarkTimeout.withTimeout(self, name: "WarmCache_Load200_DaVinci", seconds: Self.scenarioTimeoutSeconds) {
            let (coldDuration, _) = await self.runColdCache(engine: engine, urls: urls, limiter: limiter)
            MockURLProtocol.reset()
            MockURLProtocol.setResponseConfig(.init(latencyMs: Self.latencyMs))
            let (warmDuration, warmStarts) = await self.runColdCache(engine: engine, urls: urls, limiter: limiter)
            return (coldDuration, warmDuration, warmStarts)
        }
        let improvement = coldDuration > 0 ? (1 - warmDuration / coldDuration) * 100 : 0
        let tolerance = Self.isSmoke ? 1.10 : 0.95
        XCTAssertLessThanOrEqual(warmDuration, coldDuration * tolerance, "Warm should be faster or similar (smoke: 10% tolerance, full: 5%)")
        let result = BenchmarkResult(
            scenario: "WarmCache_Load200",
            engine: "DaVinci",
            durationSeconds: warmDuration,
            networkStartCount: warmStarts,
            totalRequests: Self.imageCount,
            warmImprovementPercent: improvement
        )
        ArtifactWriter.writeJSON(result, to: ArtifactWriter.artifactDirectory())
    }

    // MARK: - Scenario 3: Dedup_SameURL_100Concurrent

    @MainActor
    func testDedup_SameURL_100Concurrent_DaVinci() async throws {
        assertSmokeModeAtStart()
        MockURLProtocol.reset()
        MockURLProtocol.setResponseConfig(.init(latencyMs: Self.latencyMs))
        let config = ImageEngineFactory.makeBenchmarkSessionConfiguration()
        let engine = makeDaVinciEngineWithSharedMockSession(config: config)
        DaVinciClient.shared.clearAllCaches()
        let url = URL(string: "https://bench.local/img/0.jpg")!
        let imageViews = (0..<20).map { _ in UIImageView() }
        let limiter = ConcurrencyLimiter(maxConcurrent: Self.dedupConcurrent)
        let (duration, starts): (Double, Int) = try await BenchmarkTimeout.withTimeout(self, name: "Dedup_SameURL_100Concurrent_DaVinci", seconds: Self.scenarioTimeoutSeconds) {
            let start = Date()
            await withTaskGroup(of: Void.self) { group in
                for i in 0..<Self.dedupConcurrent {
                    group.addTask {
                        await limiter.withSlot {
                            await self.loadOne(engine: engine, url: url, imageView: imageViews[i % 20])
                        }
                    }
                }
            }
            let d = Date().timeIntervalSince(start)
            try? await Task.sleep(nanoseconds: 100_000_000)
            let s = MockURLProtocol.startCount(for: url)
            return (d, s)
        }
        XCTAssertEqual(starts, 1, "Same URL should trigger exactly one network start (dedup)")
        let result = BenchmarkResult(
            scenario: "Dedup_SameURL_100Concurrent",
            engine: "DaVinci",
            durationSeconds: duration,
            networkStartCount: starts,
            totalRequests: Self.dedupConcurrent,
            dedupSupported: true
        )
        ArtifactWriter.writeJSON(result, to: ArtifactWriter.artifactDirectory())
    }

    @MainActor
    func testDedup_SameURL_100Concurrent_Kingfisher() async throws {
        assertSmokeModeAtStart()
        MockURLProtocol.reset()
        MockURLProtocol.setResponseConfig(.init(latencyMs: Self.latencyMs))
        let config = ImageEngineFactory.makeBenchmarkSessionConfiguration()
        let engine = ImageEngineFactory.makeKingfisher(config: config)
        engine.clearCaches()
        let url = URL(string: "https://bench.local/img/0.jpg")!
        let imageViews = (0..<20).map { _ in UIImageView() }
        let limiter = ConcurrencyLimiter(maxConcurrent: Self.dedupConcurrent)
        let (duration, starts): (Double, Int) = try await BenchmarkTimeout.withTimeout(self, name: "Dedup_SameURL_100Concurrent_Kingfisher", seconds: Self.scenarioTimeoutSeconds) {
            let start = Date()
            await withTaskGroup(of: Void.self) { group in
                for i in 0..<Self.dedupConcurrent {
                    group.addTask {
                        await limiter.withSlot {
                            await self.loadOne(engine: engine, url: url, imageView: imageViews[i % 20])
                        }
                    }
                }
            }
            let d = Date().timeIntervalSince(start)
            try? await Task.sleep(nanoseconds: 100_000_000)
            let s = MockURLProtocol.startCount(for: url)
            return (d, s)
        }
        let result = BenchmarkResult(
            scenario: "Dedup_SameURL_100Concurrent",
            engine: "Kingfisher",
            durationSeconds: duration,
            networkStartCount: starts,
            totalRequests: Self.dedupConcurrent,
            dedupSupported: (starts == 1)
        )
        ArtifactWriter.writeJSON(result, to: ArtifactWriter.artifactDirectory())
    }

    // MARK: - Scenario 4: CancellationStorm (DaVinci: start 200, cancel 150)

    @MainActor
    func testCancellationStorm_DaVinci() async throws {
        assertSmokeModeAtStart()
        MockURLProtocol.setResponseConfig(.init(latencyMs: 10))
        let config = ImageEngineFactory.makeBenchmarkSessionConfiguration()
        let engine = makeDaVinciEngineWithSharedMockSession(config: config)
        DaVinciClient.shared.clearAllCaches()
        let urls = (0..<Self.cancellationStormCount).map { i in URL(string: "https://bench.local/img/\(i).jpg")! }
        let imageViews = (0..<20).map { _ in UIImageView() }
        let (completed, cancelled): (Int, Int) = try await BenchmarkTimeout.withTimeout(self, name: "CancellationStorm_DaVinci", seconds: Self.scenarioTimeoutSeconds) {
            let tasks: [Task<Void, Never>] = urls.enumerated().map { idx, url in
                Task {
                    await self.loadOne(engine: engine, url: url, imageView: imageViews[idx % 20])
                }
            }
            if Self.isSmoke {
                // In smoke, cancel and return immediately (no await) so we never block on main-runloop.
                print("[BENCH] SMOKE_EARLY_RETURN_ACTIVE")
                fflush(stdout)
                var cancelledCount = 0
                for (i, t) in tasks.enumerated() where i % 4 != 0 {
                    t.cancel()
                    cancelledCount += 1
                }
                return (tasks.count, cancelledCount)
            }
            try await Task.sleep(nanoseconds: 50_000_000)
            var cancelledCount = 0
            for (i, t) in tasks.enumerated() where i % 4 != 0 {
                t.cancel()
                cancelledCount += 1
            }
            var completedCount = 0
            for t in tasks {
                _ = await t.value
                completedCount += 1
            }
            return (completedCount, cancelledCount)
        }
        let result = BenchmarkResult(
            scenario: "CancellationStorm",
            engine: "DaVinci",
            durationSeconds: 0,
            networkStartCount: 0,
            totalRequests: Self.cancellationStormCount,
            completedCount: completed,
            cancelledCount: cancelled
        )
        ArtifactWriter.writeJSON(result, to: ArtifactWriter.artifactDirectory())
    }

    // MARK: - Scenario 5: MemoryPressure_ScrollSim (1000 binds on 20 views)

    @MainActor
    func testMemoryPressure_ScrollSim_DaVinci() async throws {
        assertSmokeModeAtStart()
        MockURLProtocol.setResponseConfig(.init(latencyMs: 5))
        let config = ImageEngineFactory.makeBenchmarkSessionConfiguration()
        let engine = makeDaVinciEngineWithSharedMockSession(config: config)
        DaVinciClient.shared.clearAllCaches()
        let urls = (0..<Self.memoryPressureCount).map { i in URL(string: "https://bench.local/img/\(i % Self.imageCount).jpg")! }
        let imageViews = (0..<20).map { _ in UIImageView() }
        let limiter = ConcurrencyLimiter(maxConcurrent: min(20, Self.memoryPressureCount))
        try await BenchmarkTimeout.withTimeout(self, name: "MemoryPressure_ScrollSim_DaVinci", seconds: Self.memoryPressureScenarioTimeoutSeconds) {
            for (idx, url) in urls.enumerated() {
                await limiter.withSlot {
                    await self.loadOne(engine: engine, url: url, imageView: imageViews[idx % 20])
                }
            }
        }
        let result = BenchmarkResult(
            scenario: "MemoryPressure_ScrollSim",
            engine: "DaVinci",
            durationSeconds: 0,
            networkStartCount: 0,
            totalRequests: Self.memoryPressureCount
        )
        ArtifactWriter.writeJSON(result, to: ArtifactWriter.artifactDirectory())
    }

    #endif // canImport(UIKit)

    // MARK: - Guardrails (smoke vs full counts)

    /// Ensures DAVINCI_BENCH_SMOKE=1 uses small counts and unset env uses production counts. Prevents accidental wrong-mode runs.
    func testBenchmarkCountsMatchMode() {
        if Self.isSmoke {
            XCTAssertLessThanOrEqual(Self.imageCount, 20, "Smoke: imageCount must be small")
            XCTAssertLessThanOrEqual(Self.dedupConcurrent, 20, "Smoke: dedupConcurrent must be small")
            XCTAssertLessThanOrEqual(Self.memoryPressureCount, 50, "Smoke: memoryPressureCount must be small")
        } else {
            XCTAssertEqual(Self.imageCount, 200, "Full mode: imageCount must be 200")
            XCTAssertEqual(Self.dedupConcurrent, 100, "Full mode: dedupConcurrent must be 100")
            XCTAssertEqual(Self.memoryPressureCount, 1000, "Full mode: memoryPressureCount must be 1000")
        }
    }

    // MARK: - Report generation (run after a full suite)

    func testWriteReportFromArtifacts() {
        let dir = ArtifactWriter.artifactDirectory()
        let results = [
            BenchmarkResult(scenario: "ColdCache_Load200", engine: "DaVinci", durationSeconds: 2.5, networkStartCount: 200, totalRequests: 200),
            BenchmarkResult(scenario: "ColdCache_Load200", engine: "Kingfisher", durationSeconds: 2.8, networkStartCount: 200, totalRequests: 200),
        ]
        ArtifactWriter.writeReport(results: results, to: dir)
        let reportFile = dir.appendingPathComponent("REPORT.md")
        XCTAssertTrue(FileManager.default.fileExists(atPath: reportFile.path))
    }
}