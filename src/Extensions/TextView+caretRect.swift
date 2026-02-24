#if os(macOS)
import AppKit

extension NSTextView {
	func caretRectForCurrentSelection(fallbackFont: NSFont? = nil) -> CGRect {
		let resolvedFont = font ?? fallbackFont ?? NSFont.systemFont(ofSize: NSFont.systemFontSize)
		let fallbackLineHeight = max(1, resolvedFont.ascender - resolvedFont.descender + resolvedFont.leading)

		let screenRect = firstRect(
			forCharacterRange: NSRange(
				location: clamp(selectedRange().location, to: 0...string.utf16Length),
				length: 0
			),
			actualRange: nil
		).standardized

		guard let window else {
			return CGRect(x: textContainerOrigin.x, y: textContainerOrigin.y, width: 1, height: fallbackLineHeight)
		}

		let rectInView = convert(window.convertFromScreen(screenRect), from: nil)

		if !rectInView.origin.x.isFinite || !rectInView.origin.y.isFinite {
			return CGRect(
				x: textContainerOrigin.x,
				y: textContainerOrigin.y,
				width: 1,
				height: fallbackLineHeight
			)
		}

		return CGRect(
			x: rectInView.origin.x,
			y: rectInView.origin.y,
			width: max(1, rectInView.width),
			height: max(fallbackLineHeight, rectInView.height)
		)
	}
}

#elseif os(iOS)
import UIKit

extension UITextView {
	func caretRectForCurrentSelection() -> CGRect {
		guard let selectedRange = selectedTextRange else {
			return CGRect(x: textContainerInset.left, y: textContainerInset.top, width: 1, height: font?.lineHeight ?? 16)
		}

		return caretRect(for: selectedRange.start)
	}
}
#endif
