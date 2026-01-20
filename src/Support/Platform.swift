#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

// MARK: - Typealiases

#if canImport(UIKit)
typealias PlatformFont = UIFont
typealias PlatformColor = UIColor
#else
typealias PlatformFont = NSFont
typealias PlatformColor = NSColor
#endif

// MARK: - Colors

#if canImport(UIKit)
let labelColor: PlatformColor = .label
let tintColor: PlatformColor = .tintColor
#else
let tintColor: PlatformColor = .systemBlue
let labelColor: PlatformColor = .labelColor
#endif
