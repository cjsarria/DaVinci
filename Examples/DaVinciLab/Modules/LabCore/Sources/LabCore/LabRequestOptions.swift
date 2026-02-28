import Foundation

public struct LabRequestOptions: Sendable, Codable, Equatable {
    public var prefetchEnabled: Bool
    public var downsampleEnabled: Bool
    public var fadeEnabled: Bool

    public init(prefetchEnabled: Bool, downsampleEnabled: Bool, fadeEnabled: Bool) {
        self.prefetchEnabled = prefetchEnabled
        self.downsampleEnabled = downsampleEnabled
        self.fadeEnabled = fadeEnabled
    }

    public static var `default`: LabRequestOptions {
        LabRequestOptions(prefetchEnabled: true, downsampleEnabled: true, fadeEnabled: true)
    }
}
