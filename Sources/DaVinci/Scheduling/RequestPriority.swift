import Foundation

public enum RequestPriority: Int, Sendable {
    case veryLow
    case low
    case normal
    case high
    case veryHigh

    var urlSessionPriority: Float {
        switch self {
        case .veryLow: return 0.05
        case .low: return 0.2
        case .normal: return 0.5
        case .high: return 0.8
        case .veryHigh: return 1.0
        }
    }

    var taskPriority: TaskPriority {
        switch self {
        case .veryLow: return .background
        case .low: return .utility
        case .normal: return .userInitiated
        case .high: return .userInitiated
        case .veryHigh: return .userInitiated
        }
    }
}
