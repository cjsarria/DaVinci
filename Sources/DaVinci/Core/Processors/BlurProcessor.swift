import Foundation
import CoreGraphics

#if canImport(CoreImage)
import CoreImage
#endif

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

public struct BlurProcessor: ImageProcessor {
    public let radius: Double

    public init(radius: Double) {
        self.radius = radius
    }

    public var identifier: String {
        let r = String(format: "%.2f", radius)
        return "blur(r=\(r))"
    }

    public func process(_ image: DVImage) -> DVImage {
        #if canImport(CoreImage)
        #if canImport(UIKit)
        guard let cg = image.cgImage else { return image }
        let ciImage = CIImage(cgImage: cg)
        guard let filter = CIFilter(name: "CIGaussianBlur") else { return image }
        filter.setValue(ciImage, forKey: kCIInputImageKey)
        filter.setValue(radius, forKey: kCIInputRadiusKey)
        let context = CIContext(options: nil)
        guard let out = filter.outputImage else { return image }
        let rect = ciImage.extent
        guard let outCG = context.createCGImage(out, from: rect) else { return image }
        return UIImage(cgImage: outCG, scale: image.scale, orientation: image.imageOrientation)
        #elseif canImport(AppKit)
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return image }
        let ciImage = CIImage(cgImage: cg)
        guard let filter = CIFilter(name: "CIGaussianBlur") else { return image }
        filter.setValue(ciImage, forKey: kCIInputImageKey)
        filter.setValue(radius, forKey: kCIInputRadiusKey)
        let context = CIContext(options: nil)
        guard let out = filter.outputImage else { return image }
        let rect = ciImage.extent
        guard let outCG = context.createCGImage(out, from: rect) else { return image }
        return NSImage(cgImage: outCG, size: image.size)
        #else
        return image
        #endif
        #else
        return image
        #endif
    }
}
