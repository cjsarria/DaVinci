import Foundation

internal protocol HTTPClientProtocol {
    func request(
        url: URL,
        priority: RequestPriority,
        additionalHeaders: [String: String]
    ) async throws -> HTTPResponse
}

internal struct HTTPClient: HTTPClientProtocol {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func request(
        url: URL,
        priority: RequestPriority,
        additionalHeaders: [String: String]
    ) async throws -> HTTPResponse {
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        for (k, v) in additionalHeaders {
            request.setValue(v, forHTTPHeaderField: k)
        }

        return try await withCheckedThrowingContinuation { continuation in
            let task = session.dataTask(with: request) { data, response, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let http = response as? HTTPURLResponse else {
                    continuation.resume(throwing: URLError(.badServerResponse))
                    return
                }
                let headers: [String: String] = http.allHeaderFields.reduce(into: [:]) { acc, kv in
                    guard let key = kv.key as? String else { return }
                    acc[key.lowercased()] = String(describing: kv.value)
                }
                let data = data ?? Data()
                continuation.resume(returning: HTTPResponse(statusCode: http.statusCode, headers: headers, data: data))
            }
            task.priority = priority.urlSessionPriority
            task.resume()
        }
    }
}

internal extension HTTPClientProtocol {
    func request(url: URL, priority: RequestPriority) async throws -> HTTPResponse {
        try await request(url: url, priority: priority, additionalHeaders: [:])
    }

    func request(url: URL) async throws -> HTTPResponse {
        try await request(url: url, priority: .normal, additionalHeaders: [:])
    }
}
