import Foundation

public enum DaVinciTransition: Sendable {
    case none
    case fade(duration: TimeInterval)

    public static func fade(_ duration: TimeInterval = 0.25) -> DaVinciTransition {
        .fade(duration: duration)
    }
}
