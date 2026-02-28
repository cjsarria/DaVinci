import Foundation
import CoreGraphics

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

public struct CropProcessor: ImageProcessor {
    public let size: CGSize

    public init(size: CGSize) {
        self.size = size
    }

    public var identifier: String {
        let w = Int(size.width.rounded(.toNearestOrAwayFromZero))
        let h = Int(size.height.rounded(.toNearestOrAwayFromZero))
        return "crop(center,\(w)x\(h))"
    }

    public func process(_ image: DVImage) -> DVImage {
        #if canImport(UIKit)
        guard let cg = image.cgImage else { return image }
        let iw = CGFloat(cg.width)
        let ih = CGFloat(cg.height)
        let tw = min(size.width, iw)
        let th = min(size.height, ih)
        let x = max(0, (iw - tw) * 0.5)
        let y = max(0, (ih - th) * 0.5)
        guard let cropped = cg.cropping(to: CGRect(x: x, y: y, width: tw, height: th)) else { return image }
        return UIImage(cgImage: cropped, scale: image.scale, orientation: image.imageOrientation)
        #elseif canImport(AppKit)
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return image }
        let iw = CGFloat(cg.width)
        let ih = CGFloat(cg.height)
        let tw = min(size.width, iw)
        let th = min(size.height, ih)
        let x = max(0, (iw - tw) * 0.5)
        let y = max(0, (ih - th) * 0.5)
        guard let cropped = cg.cropping(to: CGRect(x: x, y: y, width: tw, height: th)) else { return image }
        return NSImage(cgImage: cropped, size: CGSize(width: cropped.width, height: cropped.height))
        #else
        return image
        #endif
    }
}
