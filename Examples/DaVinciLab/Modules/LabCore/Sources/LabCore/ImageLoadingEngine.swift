import Foundation

#if canImport(UIKit)
import UIKit
public typealias LabImageView = UIImageView
#else
public final class LabImageView {}
#endif

public protocol ImageLoadingEngine {
    var name: String { get }

    func setImage(
        on imageView: LabImageView,
        url: URL,
        targetSize: CGSize?,
        options: LabRequestOptions,
        completion: ((LabMetrics) -> Void)?
    )

    func prefetch(urls: [URL])
    func clearCaches()
}
