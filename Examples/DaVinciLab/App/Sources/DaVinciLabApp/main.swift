#if canImport(UIKit)
import UIKit

UIApplicationMain(
    CommandLine.argc,
    CommandLine.unsafeArgv,
    nil,
    NSStringFromClass(AppDelegate.self)
)
#else
// No-op entry point for non-UIKit platforms (enables `swift build` on macOS).
print("DaVinciLabApp is iOS-only. Open Examples/DaVinciLab/Package.swift in Xcode and run on an iOS simulator.")
#endif
