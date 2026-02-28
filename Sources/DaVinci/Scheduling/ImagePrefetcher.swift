import Foundation
import CoreGraphics

public enum PrefetchPriority: Sendable {
    case low
    case normal
    case high

    var requestPriority: RequestPriority {
        switch self {
        case .low: return .low
        case .normal: return .normal
        case .high: return .high
        }
    }
}

public final class ImagePrefetcher {
    private let client: DaVinciClient
    private let inFlight = InFlightStore()

    public init(client: DaVinciClient = .shared) {
        self.client = client
    }

    public func prefetch(
        _ urls: [URL],
        cachePolicy: CachePolicy = .memoryAndDisk,
        priority: PrefetchPriority = .low
    ) {
        prefetch(urls, cachePolicy: cachePolicy, priority: priority.requestPriority)
    }

    public func prefetch(
        _ urls: [URL],
        cachePolicy: CachePolicy = .memoryAndDisk,
        priority: RequestPriority = .low,
        targetSize: CGSize? = nil,
        scale: CGFloat = 1
    ) {
        guard cachePolicy != .noCache else { return }
        if DaVinciClient.lowDataModeEnabled { return }

        for url in urls {
            let key = CacheKey(url: url)

            if cachePolicy == .memoryAndDisk || cachePolicy == .memoryOnly {
                if client.memoryCache.get(key) != nil { continue }
            }

            if cachePolicy == .memoryAndDisk || cachePolicy == .diskOnly {
                if client.diskCache.getData(for: key) != nil { continue }
            }

            let task = Task(priority: priority.taskPriority) { [weak self] in
                guard let self else { return }
                defer { Task { await self.inFlight.remove(key) } }

                do {
                    _ = try await self.client.loadImage(
                        url: url,
                        targetSize: targetSize,
                        scale: scale,
                        cachePolicy: cachePolicy,
                        priority: priority
                    )
                } catch {
                    return
                }
            }

            Task {
                let inserted = await inFlight.insertIfAbsent(task, for: key)
                if inserted == false {
                    task.cancel()
                }
            }
        }
    }

    public func cancel(_ urls: [URL]) {
        Task {
            for url in urls {
                let key = CacheKey(url: url)
                if let task = await inFlight.remove(key) {
                    task.cancel()
                }
            }
        }
    }
}

private actor InFlightStore {
    private var tasks: [CacheKey: Task<Void, Never>] = [:]

    func insertIfAbsent(_ task: Task<Void, Never>, for key: CacheKey) -> Bool {
        if tasks[key] != nil { return false }
        tasks[key] = task
        return true
    }

    @discardableResult
    func remove(_ key: CacheKey) -> Task<Void, Never>? {
        tasks.removeValue(forKey: key)
    }
}
