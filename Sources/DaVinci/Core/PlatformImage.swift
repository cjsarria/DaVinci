import Foundation

#if canImport(UIKit)
import UIKit
public typealias DVImage = UIImage
#elseif canImport(AppKit)
import AppKit
public typealias DVImage = NSImage
#endif
