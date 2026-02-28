import Foundation

public protocol ImageProcessor {
    var identifier: String { get }
    func process(_ image: DVImage) -> DVImage
}
