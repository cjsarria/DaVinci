import Foundation
import CoreGraphics

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

public struct ResizeProcessor: ImageProcessor {
    public let size: CGSize

    public init(size: CGSize) {
        self.size = size
    }

    public var identifier: String {
        let w = Int(size.width.rounded(.toNearestOrAwayFromZero))
        let h = Int(size.height.rounded(.toNearestOrAwayFromZero))
        return "resize(\(w)x\(h))"
    }

    public func process(_ image: DVImage) -> DVImage {
        #if canImport(UIKit)
        UIGraphicsImageRenderer(size: size).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        #elseif canImport(AppKit)
        let newImage = NSImage(size: size)
        newImage.lockFocus()
        image.draw(in: CGRect(origin: .zero, size: size))
        newImage.unlockFocus()
        return newImage
        #else
        return image
        #endif
    }
}
