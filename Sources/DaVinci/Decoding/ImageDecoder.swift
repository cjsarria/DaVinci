import Foundation
import ImageIO

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

internal enum ImageDecodingError: Error {
    case invalidData
}

internal struct ImageDecoder {
    /// Max concurrent decodes to avoid CPU spikes (default 4).
    static let maxConcurrentDecodes: Int = 4

    private let queue: DispatchQueue
    private let semaphore: DispatchSemaphore

    init(
        queue: DispatchQueue = DispatchQueue(label: "com.davinci.decoding", qos: .userInitiated),
        maxConcurrent: Int = ImageDecoder.maxConcurrentDecodes
    ) {
        self.queue = queue
        self.semaphore = DispatchSemaphore(value: maxConcurrent)
    }

    func decode(_ data: Data) async throws -> DVImage {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { [semaphore] in
                semaphore.wait()
                defer { semaphore.signal() }
                do {
                    let image = try decodeSync(data)
                    continuation.resume(returning: image)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func decode(_ data: Data, downsampleTo pointSize: CGSize?, scale: CGFloat) async throws -> DVImage {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { [semaphore] in
                semaphore.wait()
                defer { semaphore.signal() }
                do {
                    if let pointSize {
                        let image = try decodeDownsampledSync(data, to: pointSize, scale: scale)
                        continuation.resume(returning: image)
                    } else {
                        let image = try decodeSync(data)
                        continuation.resume(returning: image)
                    }
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func decodeSync(_ data: Data) throws -> DVImage {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw ImageDecodingError.invalidData
        }

        #if canImport(UIKit)
        return UIImage(cgImage: cgImage)
        #elseif canImport(AppKit)
        let size = NSSize(width: cgImage.width, height: cgImage.height)
        return NSImage(cgImage: cgImage, size: size)
        #else
        throw ImageDecodingError.invalidData
        #endif
    }

    private func decodeDownsampledSync(_ data: Data, to pointSize: CGSize, scale: CGFloat) throws -> DVImage {
        let maxDimensionInPixels = max(pointSize.width, pointSize.height) * max(1, scale)
        let maxPixelSize = max(1, Int(maxDimensionInPixels.rounded(.up)))

        let options: [CFString: Any] = [
            kCGImageSourceShouldCache: false,
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceCreateThumbnailWithTransform: true
        ]

        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw ImageDecodingError.invalidData
        }

        #if canImport(UIKit)
        return UIImage(cgImage: cgImage)
        #elseif canImport(AppKit)
        let size = NSSize(width: cgImage.width, height: cgImage.height)
        return NSImage(cgImage: cgImage, size: size)
        #else
        throw ImageDecodingError.invalidData
        #endif
    }
}
