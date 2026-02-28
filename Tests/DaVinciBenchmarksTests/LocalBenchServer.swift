import Foundation
import Network

/// Minimal HTTP server serving same deterministic payloads as MockURLProtocol. Used for PIN (no URLProtocol injection).
public final class LocalBenchServer: @unchecked Sendable {
    public var latencyMs: Int = 0

    private var listener: NWListener?
    private let queue = DispatchQueue(label: "LocalBenchServer.queue")
    private var requestCountPerPath: [String: Int] = [:]
    private let lock = NSLock()
    private var boundPort: Int = 0

    public init() {}

    public var port: Int { boundPort }
    public var baseURL: URL? {
        guard boundPort > 0 else { return nil }
        return URL(string: "http://127.0.0.1:\(boundPort)")
    }

    public func startCount(for path: String) -> Int {
        lock.lock()
        defer { lock.unlock() }
        return requestCountPerPath[path] ?? 0
    }

    public func startCountsSnapshot() -> [String: Int] {
        lock.lock()
        defer { lock.unlock() }
        return requestCountPerPath
    }

    public func resetCounts() {
        lock.lock()
        requestCountPerPath = [:]
        lock.unlock()
    }

    /// Rewrite https://bench.local/img/1.jpg -> http://127.0.0.1:port/img/1.jpg
    public func url(for benchURL: URL) -> URL? {
        guard let base = baseURL, benchURL.host == "bench.local" else { return nil }
        var c = URLComponents(url: base, resolvingAgainstBaseURL: false)!
        c.path = benchURL.path
        return c.url
    }

    public func start() async throws {
        let listener = try NWListener(using: .tcp, on: .any)
        listener.newConnectionHandler = { [weak self] conn in
            self?.handle(conn)
        }
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
            listener.stateUpdateHandler = { state in
                if state == .ready {
                    listener.stateUpdateHandler = nil
                    if let p = listener.port?.rawValue {
                        self.boundPort = Int(p)
                    }
                    c.resume()
                } else if case .failed(let error) = state {
                    listener.stateUpdateHandler = nil
                    c.resume(throwing: error)
                }
            }
            listener.start(queue: queue)
        }
        self.listener = listener
        if boundPort == 0 {
            throw NSError(domain: "LocalBenchServer", code: -1, userInfo: [NSLocalizedDescriptionKey: "Could not get port"])
        }
    }

    public func stop() {
        listener?.cancel()
        listener = nil
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        readRequest(connection: connection)
    }

    private func readRequest(connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, isComplete, error in
            guard let self = self else { return }
            if let error = error {
                connection.cancel()
                return
            }
            guard let data = data, let line = String(data: data, encoding: .utf8)?.split(separator: "\r\n").first, line.hasPrefix("GET ") else {
                self.send404(connection: connection)
                return
            }
            let path = String(line.dropFirst(4).prefix(while: { $0 != " " }))
            self.lock.lock()
            self.requestCountPerPath[path, default: 0] += 1
            self.lock.unlock()

            let payload = self.payloadForPath(path)
            let delayMs = self.latencyMs
            if delayMs > 0 {
                DispatchQueue.global().asyncAfter(deadline: .now() + Double(delayMs) / 1000.0) {
                    self.sendResponse(connection: connection, payload: payload)
                }
            } else {
                self.sendResponse(connection: connection, payload: payload)
            }
        }
    }

    private func sendResponse(connection: NWConnection, payload: Data) {
        let header = "HTTP/1.1 200 OK\r\nContent-Type: image/png\r\nContent-Length: \(payload.count)\r\nConnection: close\r\n\r\n"
        let headerData = header.data(using: .utf8)!
        connection.send(content: headerData, completion: .contentProcessed { _ in })
        connection.send(content: payload, completion: .contentProcessed { _ in })
        connection.cancel()
    }

    private func send404(connection: NWConnection) {
        let body = "Not Found"
        let header = "HTTP/1.1 404 Not Found\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n"
        let data = (header + body).data(using: .utf8)!
        connection.send(content: data, completion: .contentProcessed { _ in })
        connection.cancel()
    }

    private func payloadForPath(_ path: String) -> Data {
        let id: Int
        if path.hasPrefix("/img/") {
            let suffix = String(path.dropFirst(5)).replacingOccurrences(of: ".jpg", with: "").replacingOccurrences(of: ".png", with: "")
            id = Int(suffix) ?? 0
        } else {
            id = 0
        }
        return MockURLProtocol.makePNGForBenchmark(width: 10, height: 10, seed: id)
    }
}
