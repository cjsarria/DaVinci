import Foundation
import CoreGraphics

public struct CacheKey: Hashable, Sendable {
    public let rawValue: String

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    public init(url: URL) {
        self.rawValue = url.absoluteString
    }

    public init(url: URL, targetSize: CGSize?, scale: CGFloat) {
        if let targetSize {
            let w = Int(targetSize.width.rounded(.toNearestOrAwayFromZero))
            let h = Int(targetSize.height.rounded(.toNearestOrAwayFromZero))
            let s = String(format: "%.2f", scale)
            self.rawValue = "\(url.absoluteString)@\(w)x\(h)@\(s)"
        } else {
            self.rawValue = url.absoluteString
        }
    }

    public init(url: URL, targetSize: CGSize?, scale: CGFloat, processors: [any ImageProcessor]) {
        let base = CacheKey(url: url, targetSize: targetSize, scale: scale).rawValue
        if processors.isEmpty {
            self.rawValue = base
        } else {
            let sig = processors.map { $0.identifier }.joined(separator: "+")
            self.rawValue = base + "|proc:" + sig
        }
    }
}
