#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

extension NSTextAlignment {
	init(_ alignment: Block.TextAlignment) {
		self = switch alignment {
			case .left: .left
			case .right: .right
			case .center: .center
			case .justify: .justified
		}
	}
}
