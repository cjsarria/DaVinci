import Foundation

/// Limits how many tasks run concurrently (e.g. max 12 in-flight for benchmark).
public actor ConcurrencyLimiter {
    private let maxConcurrent: Int
    private var active: Int = 0
    private var pending: [CheckedContinuation<Void, Never>] = []

    public init(maxConcurrent: Int) {
        self.maxConcurrent = max(1, maxConcurrent)
    }

    /// Run `operation` when a slot is free; release the slot when done.
    public func withSlot<T>(operation: () async throws -> T) async rethrows -> T {
        await acquire()
        do {
            let result = try await operation()
            await release()
            return result
        } catch {
            await release()
            throw error
        }
    }

    private func acquire() async {
        if active < maxConcurrent {
            active += 1
            return
        }
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            pending.append(c)
        }
        active += 1
    }

    private func release() async {
        active -= 1
        if let next = pending.first {
            pending.removeFirst()
            next.resume()
        }
    }
}
