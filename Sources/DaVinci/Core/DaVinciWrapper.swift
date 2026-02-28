import Foundation

public struct DaVinciWrapper<Base> {
    public let base: Base

    public init(_ base: Base) {
        self.base = base
    }
}

public protocol DaVinciCompatible {}

extension DaVinciCompatible {
    public var dv: DaVinciWrapper<Self> { DaVinciWrapper(self) }
}
