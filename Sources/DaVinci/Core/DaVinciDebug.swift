import Foundation

public enum DaVinciLogLevel: Int, Sendable {
    case none
    case error
    case info
    case verbose
}

public struct DaVinciDebug {
    public static var enabled: Bool = false
    public static var logLevel: DaVinciLogLevel = .none

    /// Optional callback for each completed image load (cache source, decode time, bytes, etc.).
    /// Invoked on an arbitrary queue; dispatch to main if updating UI. Set to `nil` to disable.
    public static var metricsCallback: (@Sendable (URL, ImageLoadMetrics) -> Void)? = nil

    static func log(
        _ level: DaVinciLogLevel,
        traceId: String,
        url: URL,
        metrics: ImageLoadMetrics?,
        logContext: String?,
        message: String
    ) {
        guard enabled else { return }
        guard logLevel != .none, level.rawValue <= logLevel.rawValue else { return }

        var parts: [String] = [
            "[DaVinci]",
            "level=\(level)",
            "trace=\(traceId)",
            "url=\(url.absoluteString)"
        ]

        if let logContext { parts.append("ctx=\(logContext)") }

        if let metrics {
            parts.append("src=\(metrics.cacheSource)")
            if let n = metrics.networkTimeMs { parts.append(String(format: "netMs=%.2f", n)) }
            if let d = metrics.decodeTimeMs { parts.append(String(format: "decMs=%.2f", d)) }
            if let b = metrics.downloadedBytes { parts.append("bytes=\(b)") }
        }

        parts.append(message)
        print(parts.joined(separator: " "))
    }
}
