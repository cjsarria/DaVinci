import Foundation
import CoreGraphics

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

public struct RoundCornersProcessor: ImageProcessor {
    public let radius: CGFloat

    public init(radius: CGFloat) {
        self.radius = radius
    }

    public var identifier: String {
        let r = String(format: "%.2f", radius)
        return "roundCorners(r=\(r))"
    }

    public func process(_ image: DVImage) -> DVImage {
        #if canImport(UIKit)
        let rect = CGRect(origin: .zero, size: image.size)
        return UIGraphicsImageRenderer(size: image.size).image { _ in
            UIBezierPath(roundedRect: rect, cornerRadius: radius).addClip()
            image.draw(in: rect)
        }
        #elseif canImport(AppKit)
        let rect = CGRect(origin: .zero, size: image.size)
        let out = NSImage(size: image.size)
        out.lockFocus()
        NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).addClip()
        image.draw(in: rect)
        out.unlockFocus()
        return out
        #else
        return image
        #endif
    }
}
