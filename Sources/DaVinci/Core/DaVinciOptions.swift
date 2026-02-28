import Foundation
import CoreGraphics

#if canImport(UIKit)
import UIKit
#endif

public struct DaVinciOptions {
    #if canImport(UIKit)
    public var placeholder: UIImage?
    /// When set, the image view’s `accessibilityLabel` is updated after a successful load (VoiceOver).
    public var accessibilityLabel: String?
    #endif

    public var cachePolicy: CachePolicy
    public var priority: RequestPriority
    public var targetSize: CGSize?
    public var processors: [any ImageProcessor]
    public var retryCount: Int
    public var transition: DaVinciTransition
    public var logContext: String?

    public init(
        cachePolicy: CachePolicy = .memoryAndDisk,
        priority: RequestPriority = .normal,
        targetSize: CGSize? = nil,
        processors: [any ImageProcessor] = [],
        retryCount: Int = 0,
        transition: DaVinciTransition = .none,
        logContext: String? = nil,
        accessibilityLabel: String? = nil
    ) {
        self.cachePolicy = cachePolicy
        self.priority = priority
        self.targetSize = targetSize
        self.processors = processors
        self.retryCount = max(0, retryCount)
        self.transition = transition
        self.logContext = logContext
        #if canImport(UIKit)
        self.placeholder = nil
        self.accessibilityLabel = accessibilityLabel
        #endif
    }

    public static var `default`: DaVinciOptions { DaVinciOptions() }

    public func withFade(_ duration: TimeInterval = 0.25) -> DaVinciOptions {
        var copy = self
        copy.transition = .fade(duration: duration)
        return copy
    }
}
