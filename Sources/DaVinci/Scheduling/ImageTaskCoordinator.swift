import Foundation

actor ImageTaskCoordinator {
    private struct Entry {
        var task: Task<HTTPResponse, Error>
        var callers: Set<UUID>
    }

    private var inFlight: [CacheKey: Entry] = [:]

    func data(
        for key: CacheKey,
        url: URL,
        priority: RequestPriority,
        loader: @Sendable @escaping (URL, RequestPriority) async throws -> HTTPResponse
    ) async throws -> HTTPResponse {
        let callerID = UUID()

        if var entry = inFlight[key] {
            entry.callers.insert(callerID)
            inFlight[key] = entry

            return try await withTaskCancellationHandler {
                let result = try await entry.task.value
                finishCaller(key: key, callerID: callerID)
                return result
            } onCancel: {
                Task { await self.cancelCaller(key: key, callerID: callerID) }
            }
        }

        let task = Task(priority: priority.taskPriority) {
            try await loader(url, priority)
        }

        inFlight[key] = Entry(task: task, callers: [callerID])

        return try await withTaskCancellationHandler {
            let result = try await task.value
            finishCaller(key: key, callerID: callerID)
            return result
        } onCancel: {
            Task { await self.cancelCaller(key: key, callerID: callerID) }
        }
    }

    private func finishCaller(key: CacheKey, callerID: UUID) {
        guard var entry = inFlight[key] else { return }
        entry.callers.remove(callerID)
        if entry.callers.isEmpty {
            inFlight[key] = nil
        } else {
            inFlight[key] = entry
        }
    }

    private func cancelCaller(key: CacheKey, callerID: UUID) {
        guard var entry = inFlight[key] else { return }
        entry.callers.remove(callerID)
        if entry.callers.isEmpty {
            entry.task.cancel()
            inFlight[key] = nil
        } else {
            inFlight[key] = entry
        }
    }
}
