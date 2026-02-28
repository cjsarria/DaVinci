import Foundation

public struct LabSettings: Sendable {
    public var prefetchEnabled: Bool
    public var downsamplingEnabled: Bool
    public var fadeEnabled: Bool

    public init(prefetchEnabled: Bool = true, downsamplingEnabled: Bool = true, fadeEnabled: Bool = true) {
        self.prefetchEnabled = prefetchEnabled
        self.downsamplingEnabled = downsamplingEnabled
        self.fadeEnabled = fadeEnabled
    }

    public var requestOptions: LabRequestOptions {
        LabRequestOptions(
            prefetchEnabled: prefetchEnabled,
            downsampleEnabled: downsamplingEnabled,
            fadeEnabled: fadeEnabled
        )
    }
}
