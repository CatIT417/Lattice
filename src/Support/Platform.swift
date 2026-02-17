#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

// MARK: - Typealiases

#if canImport(UIKit)
typealias PlatformFont = UIFont
typealias PlatformColor = UIColor
typealias PlatformFontDescriptor = UIFontDescriptor
#else
typealias PlatformFont = NSFont
typealias PlatformColor = NSColor
typealias PlatformFontDescriptor = NSFontDescriptor
#endif

// MARK: - Colors

#if canImport(UIKit)
let labelColor: PlatformColor = .label
let tintColor: PlatformColor = .tintColor
let separatorColor: PlatformColor = .separator
let backgroundColor: PlatformColor = .systemBackground
#else
let tintColor: PlatformColor = .systemBlue
let labelColor: PlatformColor = .labelColor
let separatorColor: PlatformColor = .separatorColor
let backgroundColor: PlatformColor = .windowBackgroundColor
#endif

// MARK: - Actions

func copyToClipboard(_ string: String) {
	#if os(iOS)
	UIPasteboard.general.string = string
	#elseif os(macOS)
	NSPasteboard.general.clearContents()
	NSPasteboard.general.setString(string, forType: .string)
	#endif
}
