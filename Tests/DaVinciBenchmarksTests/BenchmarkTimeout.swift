import Foundation
import XCTest

/// Runs async work with a hard timeout. On timeout: record failure with diagnostics, dump MockURLProtocol state, then throw so the test ends (no indefinite hang).
enum BenchmarkTimeout {

    struct TimeoutError: Error {
        let scenario: String
        let seconds: TimeInterval
        let diagnostics: String
    }

    /// - Parameters:
    ///   - testCase: Used to record failure on timeout.
    ///   - name: Scenario name for logs.
    ///   - seconds: Hard limit (smoke: 25, full: 480).
    /// - Returns: Result of work(), or throws TimeoutError (after recording issue and state dump).
    static func withTimeout<T>(
        _ testCase: XCTestCase,
        name: String,
        seconds: TimeInterval,
        file: StaticString = #file,
        line: UInt = #line,
        work: @escaping () async throws -> T
    ) async throws -> T {
        let timeoutSeconds = seconds
        let lock = NSLock()
        var resumed = false

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<T, Error>) in
            func resumeOnce(_ result: Result<T, Error>) {
                lock.lock()
                defer { lock.unlock() }
                guard !resumed else { return }
                resumed = true
                continuation.resume(with: result)
            }

            Task {
                do {
                    let value = try await work()
                    resumeOnce(.success(value))
                } catch {
                    resumeOnce(.failure(error))
                }
            }

            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + timeoutSeconds) {
                lock.lock()
                let alreadyResumed = resumed
                lock.unlock()
                if !alreadyResumed {
                    print("[BENCH] Timed out: \(name) after \(timeoutSeconds)s")
                    fflush(stdout)
                    let diag = Self.dumpDiagnostics(name: name)
                    resumeOnce(.failure(TimeoutError(scenario: name, seconds: timeoutSeconds, diagnostics: diag)))
                    DispatchQueue.main.async {
                        testCase.record(XCTIssue(type: .assertionFailure, compactDescription: "Timed out: \(name) after \(timeoutSeconds)s. \(diag)"))
                    }
                }
            }
        }
    }

    private static func dumpDiagnostics(name: String) -> String {
        let started = MockURLProtocol.startedCount
        let completed = MockURLProtocol.completedCount
        let cancelled = MockURLProtocol.cancelledCount
        let lastURL = MockURLProtocol.lastRequestedURL?.absoluteString ?? "none"
        let rejected = MockURLProtocol.lastRejectedURL?.absoluteString ?? "none"
        let smoke = ProcessInfo.processInfo.environment["DAVINCI_BENCH_SMOKE"] ?? "not set"
        return "started=\(started) completed=\(completed) cancelled=\(cancelled) lastRequestedURL=\(lastURL) lastRejectedURL=\(rejected) DAVINCI_BENCH_SMOKE=\(smoke)"
    }
}
