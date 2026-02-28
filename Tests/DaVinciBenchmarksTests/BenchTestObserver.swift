import Foundation
import XCTest

/// Logs [TEST START] / [TEST END] for every test so xcodebuild output shows which test was running when a hang occurs.
final class BenchTestObserver: NSObject, XCTestObservation {

    private static var registered = false
    private static let lock = NSLock()

    static func registerIfNeeded() {
        lock.lock()
        defer { lock.unlock() }
        guard !registered else { return }
        XCTestObservationCenter.shared.addTestObserver(BenchTestObserver())
        registered = true
    }

    func testCaseDidStart(_ testCase: XCTestCase) {
        let name = testCase.name
        print("[TEST START] \(name)")
        fflush(stdout)
    }

    func testCaseDidFinish(_ testCase: XCTestCase) {
        let name = testCase.name
        print("[TEST END] \(name)")
        fflush(stdout)
    }
}
